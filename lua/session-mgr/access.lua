--- Can the current user read and write a directory, and who owns it. The
--- real inputs for project.resolve, which takes them as plain functions so
--- specs can fake them.
local M = {}

--- A failed stat counts as no access.
--- @param dir string
--- @param mode "R"|"W"
--- @return boolean
function M.check(dir, mode)
  local ok = vim.uv.fs_access(dir, mode)
  return ok == true
end

--- Name for a numeric id from /etc/passwd or /etc/group, else the number.
--- @param lines string[]
--- @param id integer
--- @return string
function M.name_for(lines, id)
  for _, line in ipairs(lines) do
    local name, num = line:match "^([^:]*):[^:]*:(%d+):"
    if name and tonumber(num) == id then
      return name
    end
  end
  return tostring(id)
end

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

--- @param dir string
--- @return { user: string, group: string }|nil nil when the stat fails
function M.owner(dir)
  local st = vim.uv.fs_stat(dir)
  if not st then
    return nil
  end
  return {
    user = M.name_for(read_lines "/etc/passwd", st.uid),
    group = M.name_for(read_lines "/etc/group", st.gid),
  }
end

return M
