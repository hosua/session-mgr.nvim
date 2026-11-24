--- Which project does a directory belong to?
---
--- In order: the git root of the cwd, the nearest ancestor holding a marker
--- (`project.markers`), else the home directory (or the cwd itself with
--- `project.fallback = "cwd"`). A directory that is a parent of $HOME (/ or
--- /home) is never picked silently: it comes back as "ancestor_pending" and
--- stays that way until it is approved once (see session-mgr.approved).
--- Git worktrees resolve to their own top level, so each worktree has its
--- own sessions; that is correct, since their file paths differ.
local paths = require "session-mgr.paths"

local M = {}

--- @alias SessionMgrProjectKind "git"|"marker"|"home"|"cwd"|"approved"|"ancestor_pending"

--- @class SessionMgrProject
--- @field key string   escaped root, the directory name under config.root
--- @field root string  absolute path
--- @field label string basename, for display
--- @field is_git boolean
--- @field kind SessionMgrProjectKind
--- @field marker string|nil  the marker file or directory that made this project

--- @type table<string, SessionMgrProject>
local cache = {}

--- Build a project from a known root. Pure.
--- @param kind SessionMgrProjectKind|nil defaults to "git" when is_git, else "cwd"
--- @param marker string|nil
--- @return SessionMgrProject
function M.from_root(root, is_git, kind, marker)
  root = vim.fs.normalize(root)
  local label = vim.fs.basename(root)
  return {
    key = paths.escape(root),
    root = root,
    label = label ~= "" and label or root,
    is_git = is_git,
    kind = kind or (is_git and "git" or "cwd"),
    marker = marker,
  }
end

--- @param cwd string
--- @param timeout_ms integer
--- @return string|nil git top level
local function git_root(cwd, timeout_ms)
  if vim.fn.executable "git" == 0 then
    return nil
  end
  local ok, proc = pcall(vim.system, { "git", "-C", cwd, "rev-parse", "--show-toplevel" }, { text = true })
  if not ok then
    return nil
  end
  local res = proc:wait(timeout_ms)
  if res.code ~= 0 or not res.stdout then
    return nil -- not a repo, or git took longer than the timeout
  end
  local top = vim.trim(res.stdout)
  return top ~= "" and top or nil
end

--- True when `dir` is a strict parent of `home` (/ and /home for /home/me).
--- @return boolean
function M.is_home_ancestor(dir, home)
  dir, home = vim.fs.normalize(dir), vim.fs.normalize(home)
  if dir == home then
    return false
  end
  return dir == "/" or vim.startswith(home, dir .. "/")
end

--- Nearest ancestor of `cwd` (cwd included) holding one of `markers`. The
--- walk stops at $HOME and never looks at a parent of $HOME. `exists` is
--- injected so this stays pure.
--- @param cwd string
--- @param home string
--- @param markers string[]
--- @param exists fun(path: string): boolean
--- @return string|nil dir, string|nil marker
function M.find_marker(cwd, home, markers, exists)
  local dir = vim.fs.normalize(cwd)
  home = vim.fs.normalize(home)
  while dir and not M.is_home_ancestor(dir, home) do
    for _, m in ipairs(markers) do
      if exists(dir .. "/" .. m) then
        return dir, m
      end
    end
    if dir == home then
      break
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

--- The resolution rules, with every input passed in. Pure.
--- @param cwd string
--- @param ctx { git_top: string|nil, home: string, markers: string[], exists: fun(path: string): boolean, fallback: "home"|"cwd", approved: table<string, boolean> }
--- @return SessionMgrProject
function M.resolve(cwd, ctx)
  cwd = vim.fs.normalize(cwd)
  if ctx.git_top then
    return M.from_root(ctx.git_top, true, "git")
  end
  local dir, marker = M.find_marker(cwd, ctx.home, ctx.markers, ctx.exists)
  if dir then
    return M.from_root(dir, false, "marker", marker)
  end
  if M.is_home_ancestor(cwd, ctx.home) then
    local kind = ctx.approved[cwd] and "approved" or "ancestor_pending"
    return M.from_root(cwd, false, kind)
  end
  if ctx.fallback == "cwd" then
    return M.from_root(cwd, false, "cwd")
  end
  return M.from_root(ctx.home, false, "home")
end

--- Why this project was chosen: "git root", "marker .hg", "home fallback",
--- "approved directory". Pure.
--- @param project SessionMgrProject
--- @return string
function M.why(project)
  local kind = project.kind or (project.is_git and "git" or "cwd")
  if kind == "git" then
    return "git root"
  elseif kind == "marker" then
    return "marker " .. (project.marker or "?")
  elseif kind == "home" then
    return "home fallback"
  elseif kind == "approved" then
    return "approved directory"
  elseif kind == "ancestor_pending" then
    return "parent of your home, not approved yet"
  end
  return "current directory"
end

--- One line saying which project this is and why: "git root ~/dev/foo",
--- "home ~ (no git repo here)". Pure.
--- @param project SessionMgrProject
--- @param home string|nil defaults to the home directory
--- @param max_width integer|nil shorten the path so the whole line fits this many cells
--- @return string
function M.describe(project, home, max_width)
  home = home or vim.uv.os_homedir()
  local kind = project.kind or (project.is_git and "git" or "cwd")
  local head, tail = "", ""
  if kind == "git" then
    head = "git root "
  elseif kind == "marker" then
    head = ("marker %s at "):format(project.marker or "?")
  elseif kind == "home" then
    head, tail = "home ", " (no git repo here)"
  elseif kind == "approved" then
    head = "approved directory "
  elseif kind == "ancestor_pending" then
    tail = " (parent of home, not approved)"
  else
    head, tail = "directory ", " (no git repo here)"
  end
  local where = paths.tilde(project.root, home)
  if max_width then
    local room = max_width - vim.fn.strdisplaywidth(head) - vim.fn.strdisplaywidth(tail)
    where = paths.display_path(project.root, home, math.max(room, 8))
  end
  return head .. where .. tail
end

--- @param cwd string|nil defaults to the current directory
--- @param opts SessionMgrConfig.project|nil
--- @return SessionMgrProject
function M.detect(cwd, opts)
  opts = opts or require("session-mgr.config").get().project
  cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
  local cache_key = table.concat({
    cwd,
    tostring(opts.git_root),
    tostring(opts.fallback),
    table.concat(opts.markers or {}, ","),
  }, "\0")
  local hit = cache[cache_key]
  if hit then
    return hit
  end
  local home = vim.uv.os_homedir() or cwd
  local approved = {}
  if M.is_home_ancestor(cwd, home) then
    approved = require("session-mgr.approved").set()
  end
  local project = M.resolve(cwd, {
    git_top = opts.git_root and git_root(cwd, opts.git_timeout_ms) or nil,
    home = home,
    markers = opts.markers or {},
    exists = function(path)
      return vim.uv.fs_stat(path) ~= nil
    end,
    fallback = opts.fallback or "home",
    approved = approved,
  })
  -- An unapproved parent of home is re-read each time: approving it, here or
  -- in another nvim, must take effect without a restart.
  if project.kind ~= "ancestor_pending" then
    cache[cache_key] = project
  end
  return project
end

--- How the pre-markers versions keyed a directory: git root, else the
--- directory itself. Legacy session files are filed this way.
--- @param cwd string
--- @return SessionMgrProject
function M.detect_legacy(cwd)
  local cfg = require("session-mgr.config").get().project
  return M.detect(cwd, { git_root = cfg.git_root, git_timeout_ms = cfg.git_timeout_ms, markers = {}, fallback = "cwd" })
end

function M.clear_cache()
  cache = {}
end

return M
