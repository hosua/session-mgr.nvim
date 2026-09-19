--- Per-instance state: which session this nvim last saved or loaded.
--- Deliberately not persisted; two nvim instances in one project can each
--- have a different active session.
local M = {}

--- @type { key: string, name: string }|nil
local active

--- @param project SessionMgrProject
--- @param name string
function M.set_active(project, name)
  active = { key = project.key, name = name }
end

function M.clear()
  active = nil
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
