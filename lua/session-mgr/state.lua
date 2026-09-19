--- Per-instance state: which session this nvim last saved or loaded.
--- Deliberately not persisted; two nvim instances in one project can each
--- have a different active session.
local M = {}

--- @type { key: string, name: string }|nil
local active
--- The whole project of the active session, for autosave. @type SessionMgrProject|nil
local active_project

--- @param project SessionMgrProject
--- @param name string
function M.set_active(project, name)
  active = { key = project.key, name = name }
  active_project = vim.deepcopy(project)
end

function M.clear()
  active, active_project = nil, nil
end

--- @return SessionMgrProject|nil project, string|nil name
function M.active_target()
  if active then
    return vim.deepcopy(active_project), active.name
  end
end

--- @return { key: string, name: string }|nil
function M.active()
  return active and vim.deepcopy(active) or nil
end

--- Name of the active session if it belongs to `project`.
--- @return string|nil
function M.active_in(project)
  return active and active.key == project.key and active.name or nil
end

return M
