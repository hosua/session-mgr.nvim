--- Which project does a directory belong to?
---
--- In order: the git root of the cwd, the nearest ancestor holding a marker
--- (`project.markers`), else the home directory (or the cwd itself with
--- `project.fallback = "cwd"`). A directory that is a parent of $HOME (/ or
--- /home), or one the current user cannot read or write (`project.require_access`),
--- is never picked silently: it comes back as "pending" with a `pending_reason`
--- and stays that way until it is approved once (see session-mgr.approved).
--- Git worktrees resolve to their own top level, so each worktree has its
--- own sessions; that is correct, since their file paths differ.
local paths = require "session-mgr.paths"

local M = {}

--- @alias SessionMgrProjectKind "git"|"marker"|"home"|"cwd"|"approved"|"pending"
--- @alias SessionMgrPendingReason "home_parent"|"no_read"|"no_write"|"no_access"

--- @class SessionMgrProject
--- @field key string   escaped root, the directory name under config.root
--- @field root string  absolute path
--- @field label string basename, for display
--- @field is_git boolean
--- @field kind SessionMgrProjectKind
--- @field marker string|nil  the marker file or directory that made this project
--- @field pending_reason SessionMgrPendingReason|nil  why a "pending" project needs approval

--- @type table<string, SessionMgrProject>
local cache = {}

--- Build a project from a known root. Pure.
--- @param kind SessionMgrProjectKind|nil defaults to "git" when is_git, else "cwd"
--- @param marker string|nil
--- @param pending_reason SessionMgrPendingReason|nil
--- @return SessionMgrProject
function M.from_root(root, is_git, kind, marker, pending_reason)
  root = vim.fs.normalize(root)
  local label = vim.fs.basename(root)
  return {
    key = paths.escape(root),
    root = root,
    label = label ~= "" and label or root,
    is_git = is_git,
    kind = kind or (is_git and "git" or "cwd"),
    marker = marker,
    pending_reason = pending_reason,
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

--- Why `dir` needs an approval question, or nil when it does not. A parent
--- of $HOME wins over a missing permission. `access(dir, "R"|"W")` is
--- injected so this stays pure; nil means "assume full access".
--- @param dir string
--- @param home string
--- @param access (fun(dir: string, mode: "R"|"W"): boolean)|nil
--- @param require_access boolean|nil false turns the permission rule off
--- @return SessionMgrPendingReason|nil
function M.pending_reason(dir, home, access, require_access)
  if M.is_home_ancestor(dir, home) then
    return "home_parent"
  end
  if require_access == false or not access then
    return nil
  end
  local can_read, can_write = access(dir, "R"), access(dir, "W")
  if not can_read and not can_write then
    return "no_access"
  end
  return (not can_read and "no_read") or (not can_write and "no_write") or nil
end

--- The resolution rules, with every input passed in. Pure.
--- `access` and `require_access` are optional: without `access` only a
--- parent of $HOME needs approval.
--- @param cwd string
--- @param ctx { git_top: string|nil, home: string, markers: string[], exists: fun(path: string): boolean, fallback: "home"|"cwd", approved: table<string, boolean>, access: (fun(dir: string, mode: "R"|"W"): boolean)|nil, require_access: boolean|nil }
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
  if cwd ~= vim.fs.normalize(ctx.home) then
    -- An approved directory stays approved, also after it became accessible.
    if ctx.approved[cwd] then
      return M.from_root(cwd, false, "approved")
    end
    local reason = M.pending_reason(cwd, ctx.home, ctx.access, ctx.require_access)
    if reason then
      return M.from_root(cwd, false, "pending", nil, reason)
    end
  end
  if ctx.fallback == "cwd" then
    return M.from_root(cwd, false, "cwd")
  end
  return M.from_root(ctx.home, false, "home")
end

local REASONS = {
  home_parent = { "parent of your home", "parent of home" },
  no_read = { "no read access", "no read access" },
  no_write = { "no write access", "no write access" },
  no_access = { "no read or write access", "no read or write access" },
}

--- Short reason a directory is pending: "parent of your home", "no write access".
--- @param reason SessionMgrPendingReason|nil nil reads as home_parent
--- @return string
function M.reason_short(reason)
  return REASONS[reason or "home_parent"][1]
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
  elseif kind == "pending" then
    return M.reason_short(project.pending_reason) .. ", not approved yet"
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
  elseif kind == "pending" then
    tail = (" (%s, not approved)"):format(REASONS[project.pending_reason or "home_parent"][2])
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
    tostring(opts.require_access),
    table.concat(opts.markers or {}, ","),
  }, "\0")
  local hit = cache[cache_key]
  if hit then
    return hit
  end
  local home = vim.uv.os_homedir() or cwd
  -- Only read approved_roots.json when a directory is actually in question.
  local approved = setmetatable({}, {
    __index = function(_, dir)
      return require("session-mgr.approved").set()[dir]
    end,
  })
  local project = M.resolve(cwd, {
    git_top = opts.git_root and git_root(cwd, opts.git_timeout_ms) or nil,
    home = home,
    markers = opts.markers or {},
    exists = function(path)
      return vim.uv.fs_stat(path) ~= nil
    end,
    fallback = opts.fallback or "home",
    approved = approved,
    access = require("session-mgr.access").check,
    require_access = opts.require_access,
  })
  -- A pending directory is re-read each time: approving it, here or
  -- in another nvim, must take effect without a restart.
  if project.kind ~= "pending" then
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
  return M.detect(cwd, {
    git_root = cfg.git_root,
    git_timeout_ms = cfg.git_timeout_ms,
    markers = {},
    fallback = "cwd",
    require_access = false,
  })
end

function M.clear_cache()
  cache = {}
end

return M
