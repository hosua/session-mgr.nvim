--- Config: defaults, validation, and the resolved table the rest of the
--- plugin reads. The defaults table below IS the README's config section;
--- keep the two identical.
local M = {}

--- @class SessionMgrConfig
M.defaults = {
  notify = true,
}

local resolved

--- Collect "a.b.c" paths present in `user` but absent from `defaults`, so a
--- typo in the user's opts is reported instead of silently ignored.
local function unknown_keys(user, defaults, prefix, out)
  for k, v in pairs(user) do
    local path = prefix .. tostring(k)
    if defaults[k] == nil then
      out[#out + 1] = path
    elseif type(v) == "table" and type(defaults[k]) == "table" and not vim.islist(defaults[k]) then
      unknown_keys(v, defaults[k], path .. ".", out)
    end
  end
  return out
end

--- @param opts table|nil
--- @return SessionMgrConfig cfg, string[] unknown
function M.resolve(opts)
  opts = opts or {}
  local unknown = unknown_keys(opts, M.defaults, "", {})
  resolved = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  if #unknown > 0 then
    vim.notify("session-mgr: unknown config key(s): " .. table.concat(unknown, ", "), vim.log.levels.WARN)
  end
  return resolved, unknown
end

--- @return SessionMgrConfig
function M.get()
  return resolved or M.resolve()
end

return M
