--- The two questions session-mgr asks on its own: "load the autosave you
--- left in this project?" at startup, and "may a parent of your home hold a
--- session?". Both are y/N modals from popup.nvim (via ui.style.confirm),
--- default No: Enter, Esc and q all answer no.
---
--- ask_autoload and ask_approve are function fields so tests can stub them,
--- like guard.ask. The line builders are pure.
local paths = require "session-mgr.paths"
local project_mod = require "session-mgr.project"
local timefmt = require "session-mgr.timefmt"

local M = {}

local function row(label, value, hl)
  return { { ("  %-8s"):format(label), "SessionMgrDim" }, { value, hl } }
end

--- @class SessionMgrAutoloadInfo
--- @field project SessionMgrProject
--- @field name string session name
--- @field saved integer|nil epoch seconds the session was written
--- @field now integer
--- @field home string|nil

--- Body of the startup question. Pure.
--- @param info SessionMgrAutoloadInfo
--- @return table[] lines as { text, hl } chunk lists
function M.autoload_lines(info)
  local p = info.project
  local saved = "unknown"
  if info.saved then
    local rel = timefmt.relative(info.now, info.saved)
    saved = rel == timefmt.datetime(info.saved) and rel or ("%s (%s)"):format(rel, timefmt.datetime(info.saved))
  end
  return {
    row("Project", paths.tilde(p.root, info.home), "SessionMgrName"),
    row("Why", project_mod.why(p)),
    row("Session", info.name .. ".vim"),
    row("Saved", saved),
  }
end

--- @class SessionMgrApproveInfo
--- @field project SessionMgrProject
--- @field sessions_root string config.root
--- @field home string|nil

--- Body of the "parent of your home" question. Pure.
--- @param info SessionMgrApproveInfo
--- @return table[]
function M.approve_lines(info)
  local where = paths.tilde(info.project.root, info.home)
  return {
    { { "  " }, { where, "SessionMgrName" }, { " is a parent of your home directory." } },
    { { "  A session saved here is stored under THIS user's data dir:" } },
    { { "    " }, { paths.tilde(info.sessions_root, info.home), "SessionMgrName" } },
    { { "  root and sudo have their own $HOME and data dir, so they will", "SessionMgrWarn" } },
    { { "  not find it unless they use the same sessions root.", "SessionMgrWarn" } },
  }
end

--- A y/N modal. Enter and the other cancel keys answer no.
--- @param opts { title: string, lines: table[], yes: string, no: string, danger: boolean|nil }
--- @param cb fun(yes: boolean)
local function yes_no(opts, cb)
  local f = require("session-mgr.ui.style").confirm {
    title = opts.title,
    danger = opts.danger,
    lines = opts.lines,
    choices = {
      { key = "y", label = opts.yes, value = "yes" },
      { key = "n", label = opts.no .. " (default)", value = "no" },
    },
    on_choice = function(value)
      cb(value == "yes")
    end,
  }
  -- Enter is the default answer, and the default is No.
  vim.keymap.set("n", "<CR>", "n", { buffer = f.buf, remap = true, nowait = true })
end

--- Ask whether to load the autosave. A function field so tests can stub it.
--- @param info SessionMgrAutoloadInfo
--- @param cb fun(yes: boolean)
function M.ask_autoload(info, cb)
  yes_no({
    title = "Load your last autosaved session?",
    lines = M.autoload_lines(info),
    yes = "load it",
    no = "no, start empty",
  }, cb)
end

--- Ask whether a parent of $HOME may hold a session. A function field so
--- tests can stub it.
--- @param info SessionMgrApproveInfo
--- @param cb fun(yes: boolean)
function M.ask_approve(info, cb)
  yes_no({
    title = ("Create a session for %s ?"):format(paths.tilde(info.project.root, info.home)),
    danger = true,
    lines = M.approve_lines(info),
    yes = "create sessions here",
    no = "no session here",
  }, cb)
end

return M
