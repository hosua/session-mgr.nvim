--- Path helpers. Pure: nothing here touches the filesystem, so all of it is
--- unit-tested with plain strings.
---
--- Layout: <root>/<key>/<name>.vim, where <key> is the project's absolute
--- root with separators replaced by "%" (the same escaping the old
--- hand-rolled mappings used). Keys are never decoded back into paths: the
--- real path is stored in the project's index.json instead.
local M = {}

M.EXT = ".vim"
local MAX_KEY_BYTES = 200 -- most filesystems cap a name at 255 bytes
local HASH_CHARS = 8
local ELLIPSIS = "…"

--- @param abs string absolute path
--- @return string key safe to use as one directory name
function M.escape(abs)
  local key = vim.fs.normalize(abs):gsub("[/\\:]", "%%")
  if #key <= MAX_KEY_BYTES then
    return key
  end
  -- Long paths: keep a readable prefix, make it unique with a hash of the whole.
  return key:sub(1, MAX_KEY_BYTES - HASH_CHARS - 1) .. "-" .. vim.fn.sha256(key):sub(1, HASH_CHARS)
end

--- @return string
function M.project_dir(root, key)
  return root .. "/" .. key
end

--- @return string
function M.session_file(root, key, name)
  return M.project_dir(root, key) .. "/" .. name .. M.EXT
end

--- @return string
function M.index_file(root, key)
  return M.project_dir(root, key) .. "/index.json"
end

--- "/home/me/x" -> "~/x" when under `home`.
--- @return string
function M.tilde(path, home)
  path = vim.fs.normalize(path)
  home = home and vim.fs.normalize(home)
  if home and home ~= "" and (path == home or vim.startswith(path, home .. "/")) then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

--- Home-relative path shortened to `max` display cells, always keeping the
--- last component whole because that is the part that identifies the
--- project: "~/path/to/long…/projectA".
--- @param path string
--- @param home string|nil
--- @param max integer
--- @return string
function M.display_path(path, home, max)
  local full = M.tilde(path, home)
  if vim.fn.strdisplaywidth(full) <= max then
    return full
  end
  local last = vim.fs.basename(full)
  local room = max - vim.fn.strdisplaywidth(last) - 2 -- "…/"
  if room < 1 then
    return ELLIPSIS .. "/" .. last
  end
  local head = full:sub(1, #full - #last - 1)
  return vim.fn.strcharpart(head, 0, room) .. ELLIPSIS .. "/" .. last
end

--- String-level containment check. Callers that are about to execute a file
--- must pass realpath()-resolved arguments so a symlink cannot escape `root`.
--- @return boolean
function M.is_under(root, path)
  root, path = vim.fs.normalize(root), vim.fs.normalize(path)
  return vim.startswith(path, root .. "/")
end

return M
