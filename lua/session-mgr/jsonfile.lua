--- Small JSON files in the sessions root (approved_roots.json, settings.json).
--- Reads go through plenary.path. Writes land in a temp file first and are
--- renamed over the target, so a crash leaves the old file or the new one.
local Path = require "plenary.path"

local M = {}

local uv = vim.uv

--- @param path string
--- @return any|nil value, string|nil err  err is "missing" when there is no file
function M.read(path)
  local file = Path:new(path)
  if not file:exists() then
    return nil, "missing"
  end
  local okr, text = pcall(file.read, file)
  if not okr then
    return nil, "cannot read: " .. tostring(text)
  end
  local ok, value = pcall(vim.json.decode, text)
  if not ok then
    return nil, "not valid JSON: " .. tostring(value):gsub("^.-:%d+: ", "")
  end
  return value
end

--- Write `text` to `path`, creating the parent directories.
--- @param path string
--- @param text string
--- @return boolean ok, string|nil err
function M.write(path, text)
  local okm, merr = pcall(function()
    Path:new(path):parent():mkdir { parents = true, exists_ok = true }
  end)
  if not okm then
    return false, "cannot create the directory: " .. tostring(merr)
  end
  local tmp = ("%s.%d.tmp"):format(path, uv.os_getpid())
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    return false, err
  end
  local _, werr = uv.fs_write(fd, text, 0)
  uv.fs_close(fd)
  if werr then
    uv.fs_unlink(tmp)
    return false, werr
  end
  local renamed, rerr = uv.fs_rename(tmp, path)
  if not renamed then
    uv.fs_unlink(tmp)
    return false, rerr
  end
  return true
end

return M
