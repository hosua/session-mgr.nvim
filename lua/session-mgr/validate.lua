--- Session-name validation. Names become filenames, so this is the boundary
--- that makes path traversal impossible rather than unlikely. Pure.
local M = {}

M.MAX_BYTES = 100

--- @param raw any
--- @return string|nil name cleaned name, or nil
--- @return string|nil err why it was rejected
function M.name(raw)
  if type(raw) ~= "string" then
    return nil, "name must be text"
  end
  local name = vim.trim(raw)
  -- The UI always shows ".vim"; typing it as well should not double it.
  if name:sub(-4):lower() == ".vim" then
    name = name:sub(1, -5)
  end
  if name == "" then
    return nil, "name is empty"
  end
  if #name > M.MAX_BYTES then
    return nil, ("name is longer than %d bytes"):format(M.MAX_BYTES)
  end
  if name:find "[/\\]" then
    return nil, "name cannot contain / or \\"
  end
  if name:find "%c" then
    return nil, "name cannot contain control characters"
  end
  if name:sub(1, 1) == "." then
    return nil, "name cannot start with a dot"
  end
  return name
end

return M
