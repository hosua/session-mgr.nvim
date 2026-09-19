-- The picker driven through real keys in a real (headless) float.
local real = vim.fn.expand "~/.local/share/nvim"
assert(not vim.startswith(vim.fn.stdpath "data", real), "refusing to run against real data")

local sm = require "session-mgr"
local picker = require "session-mgr.ui.picker"
local project = require "session-mgr.project"
local store = require "session-mgr.store"
local paths = require "session-mgr.paths"

vim.notify = function() end
-- Headless nvim is 80x24. Never set 'columns' here: resizing a headless UI
-- that has a tabline trips an assertion in debug builds. Stub float.editor.

local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "x", false)
end
local function lines()
  return vim.api.nvim_buf_get_lines(picker.current().float.buf, 0, -1, false)
end
local function wait_for(fn)
  ok(vim.wait(1000, fn, 10), "timed out")
end

local root, dir
local function world()
  picker.close()
  vim.cmd "silent! %bwipeout!"
  dir = vim.uv.fs_realpath(tmpdir())
  vim.fn.writefile({ "a" }, dir .. "/a.txt")
  vim.cmd.cd(dir)
  project.clear_cache()
  root = tmpdir()
  sm.setup { root = root, picker = { refresh_ms = 0 } }
  vim.cmd "edit a.txt"
  for _, n in ipairs { "default", "beta", "alpha" } do
    sm.save(n)
  end
  local other = project.from_root("/srv/other", true)
  vim.fn.mkdir(paths.project_dir(root, other.key), "p")
  vim.fn.writefile({ "cd /srv/other" }, paths.session_file(root, other.key, "alpha"))
  store.touch_saved(root, other, "alpha", os.time())
end

describe("picker", function()
  it("opens a float sized to its content, with title and rows", function()
    world()
    local p = picker.open "project"
    local cfg = vim.api.nvim_win_get_config(p.float.win)
    eq("editor", cfg.relative)
    ok(cfg.title[1][1]:find "Load a session for", vim.inspect(cfg.title))
    eq(3 + 3 + 2, cfg.height) -- chrome + 3 rows + the non-git note
    ok(lines()[4]:find "default", lines()[4])
    eq(vim.api.nvim_get_current_win(), p.float.win)
  end)

  it("moves, sorts and toggles scope with keys", function()
    world()
    picker.open "project"
    keys "j"
    eq("alpha", require("session-mgr.ui.model").current(picker.current().state).name)
    keys "G"
    eq("beta", require("session-mgr.ui.model").current(picker.current().state).name)
    keys "l"
    eq("uses", picker.current().state.sort.key)
    keys "o"
    eq("asc", picker.current().state.sort.dir)
    keys "a"
    eq("all", picker.current().state.scope)
    ok(table.concat(lines(), "\n"):find "other", "all-projects view lists the other project")
    local title = vim.api.nvim_win_get_config(picker.current().float.win).title[1][1]
    eq(" Showing your saved sessions for all projects ", title)
  end)

  it("filters live through the input overlay; <CR> keeps, <Esc> clears", function()
    world()
    picker.open "all"
    keys "/"
    ok(picker.current().filter_input, "filter input opened")
    -- TextChangedI does not fire under feedkeys("x"); typing for real is
    -- covered by tests/smoke/picker.sh. Here: set the text, fire the event.
    local fi = picker.current().filter_input
    fi.set_text "al"
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = fi.buf })
    wait_for(function()
      return picker.current().state.filter == "al"
    end)
    eq(3, select(2, require("session-mgr.ui.model").visible(picker.current().state))) -- alpha x2 + def[a]u[l]t
    keys "<CR>"
    wait_for(function()
      return not picker.current().filter_input
    end)
    eq("al", picker.current().state.filter)
    eq(vim.api.nvim_get_current_win(), picker.current().float.win)
    keys "<C-l>"
    eq("", picker.current().state.filter)
  end)

  it("never lets the window scroll (header stays on line 3)", function()
    world()
    local p = picker.open "all"
    keys "G"
    eq(1, vim.fn.getwininfo(p.float.win)[1].topline)
    ok(lines()[3]:find "Name", lines()[3])
  end)

  it("<CR> closes the picker and loads the session", function()
    world()
    vim.cmd "enew"
    picker.open "project"
    require("session-mgr.state").clear() -- world() left "alpha" active from its last save
    keys "j<CR>"
    eq(nil, picker.current()) -- closed synchronously, before the load is scheduled
    wait_for(function()
      return sm.active() and sm.active().name == "alpha"
    end)
    eq("a.txt", vim.fs.basename(vim.api.nvim_buf_get_name(0)))
  end)

  it("r renames through an input with a .vim suffix", function()
    world()
    picker.open "project"
    keys "jr"
    wait_for(function()
      return vim.bo.filetype == "session-mgr-input"
    end)
    eq("alpha", vim.api.nvim_get_current_line())
    -- feedkeys("x") ends Insert mode when its input runs out, so the pending
    -- `startinsert` may or may not still be in effect here.
    keys(vim.fn.mode() == "i" and "<C-u>gamma<CR>" or "ccgamma<CR>")
    wait_for(function()
      return store.exists(root, project.detect().key, "gamma")
    end)
    eq(false, store.exists(root, project.detect().key, "alpha"))
    wait_for(function()
      return picker.current() and table.concat(lines(), "\n"):find "gamma" ~= nil
    end)
  end)

  it("d asks first; q cancels, d deletes; default asks twice", function()
    world()
    local key = project.detect().key
    picker.open "project"
    keys "jd"
    keys "q"
    wait_for(function()
      return vim.api.nvim_get_current_win() == picker.current().float.win
    end)
    eq(true, store.exists(root, key, "alpha"))
    keys "d"
    keys "d"
    wait_for(function()
      return not store.exists(root, key, "alpha")
    end)
    keys "gg"
    keys "d"
    keys "d"
    vim.wait(50)
    eq(true, store.exists(root, key, "default")) -- first yes only opened the second question
    keys "d"
    wait_for(function()
      return not store.exists(root, key, "default")
    end)
  end)

  it("closes when focus leaves, and restores mousemoveevent", function()
    world()
    vim.o.mousemoveevent = false
    picker.open "project"
    eq(true, vim.o.mousemoveevent)
    keys "q"
    wait_for(function()
      return picker.current() == nil
    end)
    eq(false, vim.o.mousemoveevent)
  end)

  it("fits 80x24, and re-lays itself out on VimResized", function()
    world()
    local float = require "session-mgr.ui.float"
    local p = picker.open "all"
    local cfg = vim.api.nvim_win_get_config(p.float.win)
    ok(cfg.width + 2 <= 80 and cfg.height + 2 <= 24, vim.inspect { cfg.width, cfg.height })
    local editor = float.editor
    float.editor = function()
      return { width = 50, height = 9 }
    end
    vim.api.nvim_exec_autocmds("VimResized", {})
    float.editor = editor
    cfg = vim.api.nvim_win_get_config(p.float.win)
    ok(cfg.width + 2 <= 50 and cfg.height + 2 <= 9, vim.inspect { cfg.width, cfg.height })
    ok(lines()[3]:find "Name", "header survives a tiny window")
    picker.close()
  end)
  it("shows a preview beside the list on a wide editor; p toggles it; narrow hides it", function()
    world()
    local float = require "session-mgr.ui.float"
    local editor = float.editor
    float.editor = function()
      return { width = 170, height = 40 }
    end
    local p = picker.open "project"
    ok(float.is_open(p.preview), "preview opened")
    local list, pv = vim.api.nvim_win_get_config(p.float.win), vim.api.nvim_win_get_config(p.preview.win)
    eq(list.col + list.width + 2, pv.col)
    eq(false, pv.focusable)
    local text = table.concat(vim.api.nvim_buf_get_lines(p.preview.buf, 0, -1, false), "\n")
    ok(text:find "a.txt" and text:find "1 tab, 1 window", text)
    keys "p"
    eq(nil, p.preview)
    keys "p"
    ok(float.is_open(p.preview))
    float.editor = function()
      return { width = 100, height = 40 }
    end
    vim.api.nvim_exec_autocmds("VimResized", {})
    eq(nil, p.preview)
    float.editor = editor
    local win = p.float.win
    picker.close()
    eq(false, vim.api.nvim_win_is_valid(win))
  end)
end)
