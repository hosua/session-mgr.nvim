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

--- A fresh project dir with three files, made the cwd.
local function workspace()
  local dir = vim.uv.fs_realpath(tmpdir())
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

  it("loads autosave.vim and names the user's key for a new session", function()
    setup()
    autosaved()
    with_map(" sn", function()
      eq(true, session.autoload())
    end)
    eq({ "b.txt" }, open_names())
    eq({
      "Last autosaved session was automatically loaded. You can start a new session with <leader>sn",
    }, msgs)
  end)

  it("names :SessionMgr new when no key is mapped", function()
    setup()
    autosaved()
    eq(true, session.autoload())
    ok(msgs[#msgs]:find("start a new session with :SessionMgr new", 1, true), msgs[#msgs])
  end)

  it("does nothing with autosave off, a file open, or no autosave.vim", function()
    setup()
    eq(false, session.autoload()) -- no autosave.vim yet
    autosaved()
    vim.cmd "edit a.txt"
    eq(false, session.autoload())
    eq({ "a.txt" }, open_names())
    vim.cmd "silent! %bwipeout!"
    require("session-mgr").set_autosave(false, { quiet = true })
    eq(false, session.autoload())
    eq({}, open_names())
  end)

  it("does nothing once a session is active", function()
    setup()
    autosaved()
    require("session-mgr.state").set_active(project.detect(), "other")
    eq(false, session.autoload())
    eq({}, open_names())
  end)

  it("headless setup never autoloads", function()
    setup()
    autosaved()
    vim.wait(50)
    eq({}, open_names())
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
