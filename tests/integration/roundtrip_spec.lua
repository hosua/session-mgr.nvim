-- Real :mksession / :source round trips under a throwaway XDG tree.
local real = vim.fn.expand "~/.local/share/nvim"
assert(not vim.startswith(vim.fn.stdpath "data", real), "refusing to run against real data")

local sm = require "session-mgr"
local config = require "session-mgr.config"
local guard = require "session-mgr.guard"
local paths = require "session-mgr.paths"
local project = require "session-mgr.project"

local msgs = {}
vim.notify = function(m)
  msgs[#msgs + 1] = m
end

--- A fresh project dir with three files, made the cwd. The .session-root
--- marker makes it its own project (it is not under git and not under home).
local function workspace()
  local dir = vim.uv.fs_realpath(tmpdir())
  vim.fn.writefile({}, dir .. "/.session-root")
  for _, f in ipairs { "a.txt", "b.txt", "c.txt" } do
    vim.fn.writefile({ f }, dir .. "/" .. f)
  end
  vim.cmd "silent! %bwipeout!"
  vim.cmd.cd(dir)
  project.clear_cache()
  msgs = {}
  return dir
end

local function open_names()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= "" then
      out[#out + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(b))
    end
  end
  table.sort(out)
  return out
end

describe("round trip", function()
  it("saves 2 tabs / 3 files and restores exactly them", function()
    local dir = workspace()
    local cfg = config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt | vsplit b.txt | tabnew c.txt"
    ok(sm.save "work")
    local file = paths.session_file(cfg.root, project.detect().key, "work")
    ok(vim.uv.fs_stat(file), "session file written")
    ok(msgs[#msgs]:find("Saved ", 1, true) and msgs[#msgs]:find(":SessionMgr load work", 1, true), msgs[#msgs])

    vim.cmd "silent! %bwipeout! | tabonly | edit other.txt"
    local done
    sm.load("work", function(okk)
      done = okk
    end)
    eq(true, done)
    eq({ "a.txt", "b.txt", "c.txt" }, open_names())
    eq(2, #vim.api.nvim_list_tabpages())
    eq(dir, vim.uv.fs_realpath(vim.fn.getcwd()))
    eq({ key = project.detect().key, name = "work" }, sm.active())
    local rows = require("session-mgr.store").list(cfg.root, project.detect())
    local row = vim.iter(rows):find(function(r)
      return r.name == "work"
    end)
    eq(1, row.uses)
  end)

  it("save with no name uses the default session; the hint says load! only with autosave off", function()
    workspace()
    local cfg = config.resolve { root = tmpdir(), autosave = false }
    vim.cmd "edit a.txt"
    ok(sm.save())
    ok(vim.uv.fs_stat(paths.session_file(cfg.root, project.detect().key, "default")))
    ok(msgs[#msgs]:find(":SessionMgr load!", 1, true), msgs[#msgs])
    config.resolve { root = cfg.root }
    ok(sm.save())
    ok(msgs[#msgs]:find(":SessionMgr load default", 1, true), msgs[#msgs])
  end)

  it("replace = false keeps what was open", function()
    workspace()
    config.resolve { root = tmpdir(), load = { replace = false } }
    vim.cmd "edit a.txt"
    sm.save "one"
    vim.cmd "edit b.txt"
    sm.load "one"
    ok(vim.tbl_contains(open_names(), "b.txt"), "b.txt must survive an additive load")
  end)

  it("rejects a traversal name and writes nothing", function()
    workspace()
    local cfg = config.resolve { root = tmpdir() }
    eq(false, (sm.save "../evil"))
    eq({}, vim.fn.glob(cfg.root .. "/**/*.vim", false, true))
    eq(nil, vim.uv.fs_stat(vim.fs.dirname(cfg.root) .. "/evil.vim"))
  end)

  it("warns instead of erroring for a session that does not exist", function()
    workspace()
    config.resolve { root = tmpdir() }
    local done
    sm.load("nope", function(okk)
      done = okk
    end)
    eq(false, done)
    ok(msgs[#msgs]:find "No session named", msgs[#msgs])
  end)

  it("refuses to source a session file that is a symlink out of the root", function()
    workspace()
    local cfg = config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt"
    sm.save "real"
    local outside = tmpdir() .. "/evil.vim"
    vim.fn.writefile({ "let g:session_mgr_pwned = 1" }, outside)
    vim.uv.fs_symlink(outside, paths.session_file(cfg.root, project.detect().key, "link"))
    sm.load "link"
    eq(nil, vim.g.session_mgr_pwned)
    ok(msgs[#msgs]:find "outside", msgs[#msgs])
  end)
end)

describe("dirty-buffer guard", function()
  local ask = guard.ask
  local function dirty_setup()
    workspace()
    config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt"
    sm.save "base"
    vim.cmd "edit b.txt"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
  end

  it("cancel keeps everything", function()
    dirty_setup()
    guard.ask = function(_, cb)
      cb(nil)
    end
    local done
    sm.load("base", function(okk)
      done = okk
    end)
    eq(false, done)
    eq(true, vim.bo.modified)
  end)

  it("write saves the buffer to disk, then loads", function()
    dirty_setup()
    local seen
    guard.ask = function(loss, cb)
      seen = loss
      cb "write"
    end
    sm.load "base"
    eq("b.txt", seen.modified[1].name)
    eq({ "changed" }, vim.fn.readfile "b.txt")
    eq({ "a.txt" }, open_names())
  end)

  it("discard drops the change and loads", function()
    dirty_setup()
    guard.ask = function(_, cb)
      cb "discard"
    end
    sm.load "base"
    eq({ "b.txt" }, vim.fn.readfile "b.txt")
    eq({ "a.txt" }, open_names())
  end)

  it("lists unnamed modified buffers separately", function()
    workspace()
    vim.cmd "enew"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scratch" })
    local loss = guard.collect()
    eq(1, #loss.unnamed)
    eq(0, #loss.modified)
    vim.cmd "silent! %bwipeout!"
  end)

  guard.ask = ask
end)

describe(":SessionMgr", function()
  vim.cmd "runtime plugin/session-mgr.lua"
  it("save! / load! / rename / delete work end to end", function()
    workspace()
    local cfg = config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt"
    vim.cmd "SessionMgr save!"
    vim.cmd "SessionMgr save feature x"
    eq({ "default", "feature x" }, sm.names())
    vim.cmd "SessionMgr rename default main"
    ok(msgs[#msgs]:find "Usage" == nil)
    vim.cmd "SessionMgr delete main"
    eq({ "feature x" }, sm.names())
    eq(nil, vim.uv.fs_stat(paths.session_file(cfg.root, project.detect().key, "main")))
  end)

  it("completes subcommands, bang forms and session names", function()
    workspace()
    config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt"
    sm.save "alpha"
    sm.save "beta"
    local c = require("session-mgr.commands").complete
    eq({ "load", "load!" }, c("lo", "SessionMgr lo", 13))
    eq({ "alpha" }, c("al", "SessionMgr load al", 18))
    eq({ "alpha", "beta" }, c("", "SessionMgr delete ", 18))
    eq({}, c("", "SessionMgr all ", 15))
  end)

  it("reports an unknown subcommand and a misplaced bang", function()
    vim.cmd "SessionMgr frobnicate"
    ok(msgs[#msgs]:find "Unknown subcommand", msgs[#msgs])
    vim.cmd "SessionMgr delete! x"
    ok(msgs[#msgs]:find "does not take !", msgs[#msgs])
  end)
end)

describe("legacy migration on first use", function()
  it("imports before the first listing and tells the user", function()
    local dir = workspace()
    local root = tmpdir()
    vim.fn.writefile({ "cd " .. dir, "badd +1 a.txt", "edit a.txt" }, root .. "/" .. paths.escape(dir) .. ".vim")
    config.resolve { root = root }
    require("session-mgr").setup { root = root }
    eq({ "default" }, sm.names())
    ok(msgs[1]:find "Imported 1 legacy", msgs[1])
    sm.load()
    eq({ "a.txt" }, open_names())
  end)

  it("does nothing when migrate_legacy = false", function()
    local dir = workspace()
    local root = tmpdir()
    vim.fn.writefile({ "cd " .. dir }, root .. "/" .. paths.escape(dir) .. ".vim")
    require("session-mgr").setup { root = root, migrate_legacy = false }
    eq({}, sm.names())
  end)
end)

describe(":checkhealth session-mgr", function()
  it("runs without error", function()
    workspace()
    require("session-mgr").setup { root = tmpdir() }
    vim.cmd "edit a.txt"
    sm.save "x"
    local okk, err = pcall(vim.cmd, "silent checkhealth session-mgr")
    ok(okk, tostring(err))
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    ok(text:find "1 session%(s%) in 1 project", text)
    ok(not text:find "ERROR", text)
    vim.cmd "silent! %bwipeout!"
  end)
end)

describe("resave_active", function()
  local session = require "session-mgr.session"
  local function setup(resave)
    workspace()
    local root = tmpdir()
    require("session-mgr").setup { root = root, resave_active = resave, autosave = false }
    vim.cmd "edit a.txt"
    sm.save "one"
    sm.save "two"
    return root
  end
  local function files_in(root, name)
    return require("session-mgr.sessfile").parse(paths.session_file(root, project.detect().key, name)).files
  end

  it("re-saves the session being left when switching", function()
    local root = setup(true)
    vim.cmd "edit b.txt" -- active is "two"; it has only a.txt on disk
    sm.load "one"
    ok(vim.tbl_contains(files_in(root, "two"), "b.txt"), vim.inspect(files_in(root, "two")))
  end)

  it("does not re-save when reloading the active session itself", function()
    local root = setup(true)
    vim.cmd "edit b.txt"
    sm.load "two"
    ok(not vim.tbl_contains(files_in(root, "two"), "b.txt"))
  end)

  it("VimLeavePre saves the active session, silently", function()
    local root = setup(true)
    vim.cmd "edit c.txt"
    msgs = {}
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    ok(vim.tbl_contains(files_in(root, "two"), "c.txt"))
    eq({}, msgs)
  end)

  it("is off by default, and never creates a session", function()
    local root = setup(false)
    vim.cmd "edit b.txt"
    eq(false, session.resave_active())
    require("session-mgr").setup { root = root, resave_active = true, autosave = false }
    require("session-mgr.state").clear()
    eq(false, session.resave_active()) -- nothing active
    sm.save "three"
    sm.delete "three"
    eq(false, session.resave_active()) -- active cleared by delete
  end)
end)

describe("autosave", function()
  local session = require "session-mgr.session"
  local timer = require "session-mgr.autosave"
  local function setup(opts)
    workspace()
    local root = tmpdir()
    require("session-mgr").setup(vim.tbl_extend("force", { root = root }, opts or {}))
    return root
  end
  local function file(root)
    return paths.session_file(root, project.detect().key, "autosave")
  end
  local function files_in(root)
    return require("session-mgr.sessfile").parse(file(root)).files
  end

  it("is on by default with a 5 minute timer", function()
    setup()
    eq(true, config.get().autosave)
    eq(300, config.get().autosave_interval)
    eq(true, timer.running())
    eq(1, #vim.api.nvim_get_autocmds { group = "session-mgr", event = "VimLeavePre" })
  end)

  it("writes autosave.vim silently and leaves the active session alone", function()
    local root = setup()
    vim.cmd "edit a.txt"
    sm.save "work"
    vim.cmd "vsplit b.txt | copen"
    msgs = {}
    eq(true, session.autosave())
    eq({}, msgs)
    ok(vim.fs.basename(file(root)) == "autosave.vim")
    eq(
      { "a.txt", "b.txt" },
      (function()
        local f = files_in(root)
        table.sort(f)
        return f
      end)()
    )
    eq("work", sm.active().name)
    ok(vim.fn.getqflist({ winid = 0 }).winid ~= 0, "quickfix window was closed")
    vim.cmd "cclose"
  end)

  it("skips when no file is open, so an empty start never overwrites it", function()
    local root = setup()
    eq(false, session.autosave())
    ok(not vim.uv.fs_stat(file(root)))
  end)

  it("writes on exit and before a load wipes the buffers", function()
    local root = setup()
    vim.cmd "edit a.txt"
    sm.save "one"
    vim.cmd "edit c.txt"
    sm.load "one"
    ok(vim.tbl_contains(files_in(root), "c.txt"), vim.inspect(files_in(root)))
    vim.cmd "edit b.txt"
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    ok(vim.tbl_contains(files_in(root), "b.txt"))
  end)

  it("loading autosave does not overwrite it first", function()
    local root = setup()
    vim.cmd "edit a.txt"
    session.autosave()
    vim.cmd "edit c.txt"
    sm.load "autosave"
    eq({ "a.txt" }, files_in(root))
    eq({ "a.txt" }, open_names())
  end)

  it("the timer writes on its own, and waits while a float has focus", function()
    local root = setup()
    vim.cmd "edit a.txt"
    local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 2,
    })
    timer.start(20)
    vim.wait(100)
    ok(not vim.uv.fs_stat(file(root)), "saved while a float had focus")
    vim.api.nvim_win_close(float, true)
    ok(
      vim.wait(6000, function()
        return vim.uv.fs_stat(file(root)) ~= nil
      end, 20),
      "timer never wrote autosave.vim"
    )
    timer.stop()
  end)

  it("autosave = false or interval 0 starts no timer", function()
    local root = setup { autosave = false }
    eq(false, timer.running())
    vim.cmd "edit a.txt"
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    ok(not vim.uv.fs_stat(file(root)), "exit save ran with autosave off")
    setup { autosave_interval = 0 }
    eq(false, timer.running())
  end)

  it("toggles at runtime: timer, exit save and message follow", function()
    local root = setup { autosave = false }
    vim.cmd "edit a.txt"
    msgs = {}
    vim.cmd "SessionMgr autosave"
    eq(true, config.get().autosave)
    eq(true, timer.running())
    eq({ "Autosave on: autosave.vim every 5m, on exit and before a load" }, msgs)
    vim.api.nvim_exec_autocmds("VimLeavePre", {})
    ok(vim.uv.fs_stat(file(root)), "exit save did not run after toggling on")
    vim.cmd "SessionMgr autosave off"
    eq(false, config.get().autosave)
    eq(false, timer.running())
    eq("Autosave off", msgs[#msgs])
    vim.cmd "SessionMgr autosave off"
    eq(false, config.get().autosave)
    vim.cmd "SessionMgr autosave bogus"
    ok(msgs[#msgs]:find("Usage: :SessionMgr autosave", 1, true), msgs[#msgs])
    eq({ "off", "on", "toggle" }, require("session-mgr.commands").complete("", "SessionMgr autosave ", 0))
  end)
end)

describe("load! with no name", function()
  local session = require "session-mgr.session"
  local function setup(opts)
    workspace()
    local root = tmpdir()
    require("session-mgr").setup(vim.tbl_extend("force", { root = root, autosave_interval = 0 }, opts or {}))
    return root
  end
  --- Saves "default" with a.txt and autosave with b.txt, then opens c.txt.
  local function both()
    vim.cmd "edit a.txt"
    sm.save()
    vim.cmd "silent! %bwipeout! | edit b.txt"
    eq(true, session.autosave())
    vim.cmd "silent! %bwipeout! | edit c.txt"
  end

  it("prefers autosave while autosave is on", function()
    setup()
    both()
    sm.load()
    eq({ "b.txt" }, open_names())
    eq("autosave", sm.active().name)
  end)

  it("loads default when autosave is off, even with autosave.vim present", function()
    setup()
    both()
    require("session-mgr").set_autosave(false, { quiet = true })
    vim.cmd "SessionMgr load!"
    eq({ "a.txt" }, open_names())
    eq("default", sm.active().name)
  end)

  it("falls back to default when autosave.vim does not exist", function()
    setup()
    vim.cmd "edit a.txt"
    sm.save()
    vim.cmd "silent! %bwipeout! | edit c.txt"
    sm.load()
    eq("default", sm.active().name)
  end)

  it("loads autosave when it is the only one and autosave is on", function()
    setup()
    vim.cmd "edit b.txt"
    session.autosave()
    vim.cmd "silent! %bwipeout! | edit c.txt"
    sm.load()
    eq({ "b.txt" }, open_names())
  end)

  it("says why when there is nothing to load", function()
    setup()
    local loaded
    sm.load(nil, function(okk)
      loaded = okk
    end)
    eq(false, loaded)
    ok(msgs[#msgs]:find('No "autosave" or "default" session for', 1, true), msgs[#msgs])

    vim.cmd "edit b.txt"
    session.autosave()
    require("session-mgr").set_autosave(false, { quiet = true })
    vim.cmd "SessionMgr load!"
    eq({ "b.txt" }, open_names())
    ok(msgs[#msgs]:find(":SessionMgr load autosave", 1, true), msgs[#msgs])
  end)

  it("an explicit name loads exactly that session", function()
    setup()
    both()
    vim.cmd "SessionMgr load default"
    eq({ "a.txt" }, open_names())
  end)
end)

describe("autoload at startup", function()
  local session = require "session-mgr.session"
  local prompt = require "session-mgr.prompt"
  local approved = require "session-mgr.approved"

  local function setup(opts)
    workspace()
    local root = tmpdir()
    require("session-mgr").setup(vim.tbl_extend("force", { root = root, autosave_interval = 0 }, opts or {}))
    return root
  end
  --- Writes autosave.vim with b.txt, then looks like a fresh start again.
  local function autosaved()
    vim.cmd "edit b.txt"
    eq(true, session.autosave())
    vim.cmd "silent! %bwipeout!"
    require("session-mgr.state").clear()
    msgs = {}
  end
  local function with_map(lhs, fn)
    local leader = vim.g.mapleader
    vim.g.mapleader = " "
    vim.keymap.set("n", lhs, "<cmd>SessionMgr new<cr>")
    local okk, err = pcall(fn)
    vim.keymap.del("n", lhs)
    vim.g.mapleader = leader
    assert(okk, err)
  end
  --- Replace the two questions; `answers.autoload` / `answers.approve` are
  --- what "the user" says. Records what was asked in `asked`.
  local function with_answers(answers, fn)
    local saved = { prompt.ask_autoload, prompt.ask_approve }
    local asked = { autoload = {}, approve = {} }
    prompt.ask_autoload = function(info, cb)
      asked.autoload[#asked.autoload + 1] = info
      cb(answers.autoload)
    end
    prompt.ask_approve = function(info, cb)
      asked.approve[#asked.approve + 1] = info
      cb(answers.approve)
    end
    local okk, err = pcall(fn, asked)
    prompt.ask_autoload, prompt.ask_approve = saved[1], saved[2]
    assert(okk, err)
  end
  local function autoload()
    local result
    session.autoload(function(loaded)
      result = loaded
    end)
    return result
  end

  it("asks first, says which project and why, and loads on y", function()
    setup()
    autosaved()
    with_answers({ autoload = true }, function(asked)
      eq(true, autoload())
      eq(1, #asked.autoload)
      local info = asked.autoload[1]
      eq({ "marker", ".session-root", "autosave" }, { info.project.kind, info.project.marker, info.name })
      ok(info.saved and info.saved > 0, "saved time is passed")
    end)
    eq({ "b.txt" }, open_names())
    ok(msgs[#msgs]:find("Loaded autosave (marker .session-root at", 1, true), msgs[#msgs])
  end)

  it("names the user's key for a new session after a y", function()
    setup()
    autosaved()
    with_map(" sn", function()
      with_answers({ autoload = true }, function()
        eq(true, autoload())
      end)
    end)
    ok(msgs[#msgs]:find("start a new session with <leader>sn", 1, true), msgs[#msgs])
  end)

  it("leaves nvim empty on n and says how to load it later", function()
    setup()
    autosaved()
    with_answers({ autoload = false }, function(asked)
      eq(false, autoload())
      eq(1, #asked.autoload)
    end)
    eq({}, open_names())
    eq(nil, sm.active())
    eq({ "Autosave not loaded. Load it later with :SessionMgr load!" }, msgs)
  end)

  it("autoload = always loads without asking", function()
    setup { autoload = "always" }
    autosaved()
    with_answers({ autoload = false }, function(asked)
      eq(true, autoload())
      eq(0, #asked.autoload)
    end)
    eq({ "b.txt" }, open_names())
  end)

  it("autoload = false never asks", function()
    setup { autoload = false }
    autosaved()
    with_answers({ autoload = true }, function(asked)
      eq(false, autoload())
      eq(0, #asked.autoload)
    end)
    eq({}, open_names())
  end)

  it("does nothing with autosave off, a file open, or no autosave.vim", function()
    setup()
    with_answers({ autoload = true }, function(asked)
      eq(false, autoload()) -- no autosave.vim yet
      autosaved()
      vim.cmd "edit a.txt"
      eq(false, autoload())
      eq({ "a.txt" }, open_names())
      vim.cmd "silent! %bwipeout!"
      require("session-mgr").set_autosave(false, { quiet = true })
      eq(false, autoload())
      eq({}, open_names())
      eq(0, #asked.autoload)
    end)
  end)

  it("does nothing once a session is active", function()
    setup()
    autosaved()
    require("session-mgr.state").set_active(project.detect(), "other")
    with_answers({ autoload = true }, function(asked)
      eq(false, autoload())
      eq(0, #asked.autoload)
    end)
    eq({}, open_names())
  end)

  it("never asks while an ignored buffer is open", function()
    setup()
    autosaved()
    vim.cmd "enew"
    vim.bo.filetype = "gitcommit"
    with_answers({ autoload = true }, function(asked)
      eq(false, autoload())
      eq(0, #asked.autoload)
    end)
    vim.cmd "silent! %bwipeout!"
  end)

  it("headless setup never autoloads", function()
    setup()
    autosaved()
    vim.wait(50)
    eq({}, open_names())
  end)
end)

describe("ignored buffers", function()
  local session = require "session-mgr.session"
  it("a lone COMMIT_EDITMSG does not count as a file and never overwrites autosave.vim", function()
    local dir = workspace()
    local root = tmpdir()
    require("session-mgr").setup { root = root, autosave_interval = 0 }
    vim.cmd "edit b.txt"
    eq(true, session.autosave())
    local file = paths.session_file(root, project.detect().key, "autosave")
    local before = table.concat(vim.fn.readfile(file), "\n")
    vim.cmd "silent! %bwipeout!"
    vim.fn.mkdir(dir .. "/.git", "p")
    vim.cmd("edit " .. dir .. "/.git/COMMIT_EDITMSG")
    eq(false, session.autosave())
    eq(before, table.concat(vim.fn.readfile(file), "\n"))
    vim.cmd "silent! %bwipeout!"
  end)

  it("skips the autosave while the current buffer is ignored, even with real files open", function()
    local dir = workspace()
    local root = tmpdir()
    require("session-mgr").setup { root = root, autosave_interval = 0 }
    vim.cmd "edit a.txt"
    vim.cmd("split " .. dir .. "/MERGE_MSG")
    eq(false, session.autosave())
    vim.cmd "wincmd p"
    eq(true, session.autosave())
    vim.cmd "silent! %bwipeout!"
  end)
end)

describe("parents of home", function()
  local session = require "session-mgr.session"
  local prompt = require "session-mgr.prompt"
  local approved = require "session-mgr.approved"

  --- cwd = a parent of a fake $HOME, holding one file, with a fresh sessions root.
  local function world()
    local base = vim.uv.fs_realpath(tmpdir())
    local parent, home = base .. "/users", base .. "/users/me"
    vim.fn.mkdir(home, "p")
    vim.fn.writefile({ "x" }, parent .. "/x.txt")
    local saved_home = vim.env.HOME
    vim.env.HOME = home
    vim.cmd "silent! %bwipeout!"
    vim.cmd.cd(parent)
    project.clear_cache()
    msgs = {}
    local root = tmpdir()
    require("session-mgr").setup { root = root, autosave_interval = 0 }
    return {
      parent = parent,
      root = root,
      restore = function()
        vim.env.HOME = saved_home
        project.clear_cache()
        approved.reset_declined()
      end,
    }
  end
  local function stubbed(w, answers, fn)
    local saved = { prompt.ask_autoload, prompt.ask_approve }
    local asked = { autoload = {}, approve = {} }
    prompt.ask_autoload = function(info, cb)
      asked.autoload[#asked.autoload + 1] = info
      cb(answers.autoload)
    end
    prompt.ask_approve = function(info, cb)
      asked.approve[#asked.approve + 1] = info
      cb(answers.approve)
    end
    local okk, err = pcall(fn, asked)
    prompt.ask_autoload, prompt.ask_approve = saved[1], saved[2]
    w.restore()
    assert(okk, err)
  end
  --- An autosave.vim that exists for the (still unapproved) parent.
  local function seed_autosave(w)
    ok(approved.add(w.root, w.parent))
    vim.cmd "edit x.txt"
    eq(true, session.autosave())
    vim.cmd "silent! %bwipeout!"
    require("session-mgr.state").clear()
    vim.fn.delete(approved.file(w.root))
    project.clear_cache()
    approved.reset_declined()
    eq("pending", project.detect().kind)
    msgs = {}
  end

  it("a manual save asks, and a no writes nothing", function()
    local w = world()
    stubbed(w, { approve = false }, function(asked)
      vim.cmd "edit x.txt"
      eq(false, (sm.save "work"))
      eq(1, #asked.approve)
      eq(w.parent, asked.approve[1].project.root)
      eq(w.root, asked.approve[1].sessions_root)
      eq({}, approved.read(w.root))
      eq(false, vim.uv.fs_stat(paths.session_file(w.root, project.detect().key, "work")) ~= nil)
      eq(true, approved.is_declined(w.parent))
      ok(msgs[#msgs]:find("No session for", 1, true), msgs[#msgs])
    end)
  end)

  it("a yes saves, persists the approval, and is never asked again", function()
    local w = world()
    stubbed(w, { approve = true }, function(asked)
      vim.cmd "edit x.txt"
      eq(true, (sm.save "work"))
      eq({ w.parent }, approved.read(w.root))
      eq("approved", project.detect().kind)
      ok(vim.uv.fs_stat(paths.session_file(w.root, project.detect().key, "work")))
      ok(msgs[#msgs]:find("approved directory", 1, true), msgs[#msgs])
      eq(true, (sm.save "again"))
      eq(1, #asked.approve)
    end)
  end)

  it("the exit autosave never asks and skips an unapproved directory", function()
    local w = world()
    stubbed(w, { approve = true }, function(asked)
      vim.cmd "edit x.txt"
      eq(false, session.autosave())
      eq(0, #asked.approve)
      eq(nil, vim.uv.fs_stat(w.root .. "/" .. paths.escape(w.parent)))
      ok(approved.add(w.root, w.parent))
      eq(true, session.autosave())
    end)
  end)

  it("startup asks to approve only when an autosave.vim exists, then asks to load", function()
    local w = world()
    stubbed(w, { approve = true, autoload = true }, function(asked)
      local done
      session.autoload(function(v)
        done = v
      end)
      eq({ false, 0, 0 }, { done, #asked.approve, #asked.autoload }) -- nothing saved here yet
      seed_autosave(w)
      session.autoload(function(v)
        done = v
      end)
      eq({ true, 1, 1 }, { done, #asked.approve, #asked.autoload })
      eq("approved directory", require("session-mgr.project").why(asked.autoload[1].project))
      eq({ w.parent }, approved.read(w.root))
      eq({ "x.txt" }, open_names())
    end)
  end)

  it("a no at startup skips autoload for the run and does not fall back to home", function()
    local w = world()
    stubbed(w, { approve = false, autoload = true }, function(asked)
      seed_autosave(w)
      local done
      session.autoload(function(v)
        done = v
      end)
      session.autoload(function(v)
        done = v
      end)
      eq({ false, 1, 0 }, { done, #asked.approve, #asked.autoload })
      eq({}, open_names())
      eq("pending", project.detect().kind)
    end)
  end)
end)

describe("directories without access", function()
  local session = require "session-mgr.session"
  local prompt = require "session-mgr.prompt"
  local approved = require "session-mgr.approved"
  local sm = require "session-mgr"

  --- cwd = a real chmod'd directory under a fake $HOME. Skipped as root,
  --- since root passes every access check.
  local function world(mode)
    local base = vim.uv.fs_realpath(tmpdir())
    local home, dir = base .. "/me", base .. "/me/locked"
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "x" }, dir .. "/x.txt")
    local saved_home = vim.env.HOME
    vim.env.HOME = home
    vim.cmd "silent! %bwipeout!"
    vim.cmd.cd(dir)
    vim.uv.fs_chmod(dir, mode) -- after cd: a mode 000 directory cannot be entered
    project.clear_cache()
    msgs = {}
    local root = tmpdir()
    require("session-mgr").setup { root = root, autosave_interval = 0 }
    return {
      dir = dir,
      root = root,
      restore = function()
        vim.uv.fs_chmod(dir, tonumber("755", 8))
        vim.cmd.cd(base)
        vim.env.HOME = saved_home
        project.clear_cache()
        approved.reset_declined()
      end,
    }
  end

  local function stubbed(w, answer, fn)
    local saved = prompt.ask_approve
    local asked = {}
    prompt.ask_approve = function(info, cb)
      asked[#asked + 1] = info
      cb(answer)
    end
    local okk, err = pcall(fn, asked)
    prompt.ask_approve = saved
    w.restore()
    assert(okk, err)
  end

  local is_root = vim.uv.getuid() == 0

  it("a read-only directory is pending with reason no_write", function()
    if is_root then
      return
    end
    local w = world(tonumber("555", 8))
    stubbed(w, false, function()
      local p = project.detect()
      eq({ "pending", w.dir, "no_write" }, { p.kind, p.root, p.pending_reason })
    end)
  end)

  it("a directory with no permissions is pending with reason no_access", function()
    if is_root then
      return
    end
    local w = world(0)
    stubbed(w, false, function()
      eq("no_access", project.detect(w.dir).pending_reason)
    end)
  end)

  it("a yes saves under the directory, not home, and is never asked again", function()
    if is_root then
      return
    end
    local w = world(tonumber("555", 8))
    stubbed(w, true, function(asked)
      vim.cmd "edit x.txt"
      eq(true, (sm.save "work"))
      eq(1, #asked)
      eq("no_write", asked[1].project.pending_reason)
      eq({ w.dir }, approved.read(w.root))
      local p = project.detect()
      eq({ "approved", w.dir }, { p.kind, p.root })
      ok(vim.uv.fs_stat(paths.session_file(w.root, p.key, "work")))
      eq(true, (sm.save "again"))
      eq(1, #asked)
      -- Still approved once the directory becomes writable.
      vim.uv.fs_chmod(w.dir, tonumber("755", 8))
      project.clear_cache()
      eq("approved", project.detect().kind)
    end)
  end)

  it("a no writes nothing, skips the autosave, and asks again on the next manual save", function()
    if is_root then
      return
    end
    local w = world(tonumber("555", 8))
    stubbed(w, false, function(asked)
      vim.cmd "edit x.txt"
      eq(false, (sm.save "work"))
      eq({}, approved.read(w.root))
      eq(false, session.autosave())
      eq(1, #asked)
      eq(false, (sm.save "work"))
      eq(2, #asked)
      eq("pending", project.detect().kind)
    end)
  end)

  it("require_access = false files it under home without asking", function()
    if is_root then
      return
    end
    local w = world(tonumber("555", 8))
    stubbed(w, false, function(asked)
      require("session-mgr").setup { root = w.root, autosave_interval = 0, project = { require_access = false } }
      project.clear_cache()
      eq("home", project.detect().kind)
      vim.cmd "edit x.txt"
      eq(true, (sm.save "work"))
      eq(0, #asked)
    end)
  end)
end)

describe("new session", function()
  local session = require "session-mgr.session"
  local function setup(opts)
    workspace()
    local root = tmpdir()
    require("session-mgr").setup(vim.tbl_extend("force", { root = root, autosave_interval = 0 }, opts or {}))
    return root
  end

  it("wipes every buffer, tab and window, clears the active session, and autosaves first", function()
    local root = setup()
    vim.cmd "edit a.txt | vsplit b.txt | tabnew c.txt"
    sm.save "work"
    vim.cmd "SessionMgr new"
    eq({}, open_names())
    eq(1, #vim.api.nvim_list_tabpages())
    eq(1, #vim.api.nvim_list_wins())
    eq(nil, sm.active())
    ok(msgs[#msgs]:find("New session: nothing open. Save it with", 1, true), msgs[#msgs])
    local files =
      require("session-mgr.sessfile").parse(paths.session_file(root, project.detect().key, "autosave")).files
    table.sort(files)
    eq({ "a.txt", "b.txt", "c.txt" }, files)
  end)

  it("asks about unsaved buffers, and cancel keeps everything", function()
    setup()
    vim.cmd "edit a.txt"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
    local real, verb = guard.ask, nil
    guard.ask = function(_, cb, v)
      verb = v
      cb(nil)
    end
    local done
    session.new(function(okk)
      done = okk
    end)
    guard.ask = real
    eq("clear", verb)
    eq(false, done)
    eq({ "a.txt" }, open_names())
    vim.cmd "silent! %bwipeout!"
  end)
end)
