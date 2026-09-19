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
    local row = require("session-mgr.store").list(cfg.root, project.detect())[1]
    eq(1, row.uses)
  end)

  it("save with no name uses the default session and says load!", function()
    workspace()
    local cfg = config.resolve { root = tmpdir() }
    vim.cmd "edit a.txt"
    ok(sm.save())
    ok(vim.uv.fs_stat(paths.session_file(cfg.root, project.detect().key, "default")))
    ok(msgs[#msgs]:find(":SessionMgr load!", 1, true), msgs[#msgs])
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
