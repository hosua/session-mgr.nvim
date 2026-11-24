--- Directories you said "yes" to when session-mgr asked whether a pending
--- directory may hold a session: a parent of your home (/ or /home), or one
--- you cannot read or write. Stored as a JSON array in
--- <config.root>/approved_roots.json, written atomically. A "no" is only
--- remembered for this nvim run.
local M = {}

local uv = vim.uv
local FILE = "approved_roots.json"

--- @type table<string, boolean>
local declined = {}

--- @param root string config.root
--- @return string
function M.file(root)
  return vim.fs.normalize(root) .. "/" .. FILE
end

--- Approved directories, normalized. A missing file is an empty list; a file
--- that does not hold a JSON array of strings is ignored (and never rewritten
--- until the next approval, which replaces it).
--- @param root string|nil defaults to config.root
--- @return string[]
function M.read(root)
  root = root or require("session-mgr.config").get().root
  local fd = uv.fs_open(M.file(root), "r", 420)
  if not fd then
    return {}
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0) or ""
  uv.fs_close(fd)
  local ok, list = pcall(vim.json.decode, data)
  if not ok or type(list) ~= "table" or not vim.islist(list) then
    return {}
  end
  local out = {}
  for _, dir in ipairs(list) do
    if type(dir) == "string" and dir ~= "" then
      out[#out + 1] = vim.fs.normalize(dir)
    end
  end
  return out
end

--- @param root string|nil defaults to config.root
--- @return table<string, boolean>
function M.set(root)
  local set = {}
  for _, dir in ipairs(M.read(root)) do
    set[dir] = true
  end
  return set
end

--- @return boolean
function M.is_approved(dir, root)
  return M.set(root)[vim.fs.normalize(dir)] == true
end

--- Append `dir`, creating the directory and the file when needed. Already
--- approved: no write.
--- @param root string config.root
--- @param dir string
--- @return boolean ok, string|nil err
function M.add(root, dir)
  dir = vim.fs.normalize(dir)
  local list = M.read(root)
  if vim.tbl_contains(list, dir) then
    return true
  end
  list[#list + 1] = dir
  if vim.fn.mkdir(vim.fs.normalize(root), "p") == 0 and not uv.fs_stat(root) then
    return false, "cannot create " .. root
  end
  local path = M.file(root)
  local tmp = ("%s.%d.tmp"):format(path, uv.os_getpid())
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    return false, err
  end
  local _, werr = uv.fs_write(fd, vim.json.encode(list), 0)
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
  require("session-mgr.project").clear_cache()
  return true
end

--- Remember a "no" for this nvim run.
function M.decline(dir)
  declined[vim.fs.normalize(dir)] = true
end

--- @return boolean
function M.is_declined(dir)
  return declined[vim.fs.normalize(dir)] == true
end

--- Forget every "no" (tests, and a fresh setup()).
function M.reset_declined()
  declined = {}
end

return M
