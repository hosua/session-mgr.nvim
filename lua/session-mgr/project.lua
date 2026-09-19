--- Which project does a directory belong to?
---
--- A project is the git root of the cwd, or the cwd itself outside git.
--- Git worktrees resolve to their own top level, so each worktree has its
--- own sessions; that is correct, since their file paths differ.
local paths = require "session-mgr.paths"

local M = {}

--- @class SessionMgrProject
--- @field key string   escaped root, the directory name under config.root
--- @field root string  absolute path
--- @field label string basename, for display
--- @field is_git boolean

--- @type table<string, SessionMgrProject>
local cache = {}

--- Build a project from a known root. Pure.
--- @return SessionMgrProject
function M.from_root(root, is_git)
  root = vim.fs.normalize(root)
  local label = vim.fs.basename(root)
  return { key = paths.escape(root), root = root, label = label ~= "" and label or root, is_git = is_git }
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

--- @param cwd string|nil defaults to the current directory
--- @param opts { git_root: boolean, git_timeout_ms: integer }|nil
--- @return SessionMgrProject
function M.detect(cwd, opts)
  opts = opts or require("session-mgr.config").get().project
  cwd = vim.fs.normalize(cwd or vim.fn.getcwd())
  local hit = cache[cwd]
  if hit then
    return hit
  end
  local top = opts.git_root and git_root(cwd, opts.git_timeout_ms) or nil
  local project = M.from_root(top or cwd, top ~= nil)
  cache[cwd] = project
  return project
end

function M.clear_cache()
  cache = {}
end

return M
