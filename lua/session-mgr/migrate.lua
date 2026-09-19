--- One-time import of the legacy flat layout.
---
--- Before this plugin, sessions were single files directly under the root,
--- named after the escaped cwd: <root>/%home%me%dev%mach.vim. They are
--- COPIED into the per-project layout and never modified or deleted, so
--- going back to the old mappings keeps working.
---
--- The cwd comes from the `cd` line inside each file, not from decoding the
--- file name: a path containing a literal "%" makes the name ambiguous, the
--- `cd` line is exact.
---
---   cwd is its project's root      -> that project's default session
---   cwd is a subfolder of the root -> a named session: "sysconfig-terraform"
---   cwd no longer exists           -> default session of a project at that path
local paths = require "session-mgr.paths"
local sessfile = require "session-mgr.sessfile"
local store = require "session-mgr.store"
local validate = require "session-mgr.validate"

local M = {}

M.MARKER = ".migrated-legacy-v1.json"
local uv = vim.uv

--- "sysconfig/terraform" -> "sysconfig-terraform", made safe as a session name.
--- @return string
function M.derive_name(relpath)
  local name = relpath:gsub("[/\\]+", "-"):gsub("%c", ""):gsub("^%.+", "")
  return (validate.name(name:sub(1, validate.MAX_BYTES))) or "legacy"
end

local function read_marker(root)
  local fd = io.open(root .. "/" .. M.MARKER, "r")
  if not fd then
    return nil
  end
  local ok, data = pcall(vim.json.decode, fd:read "*a")
  fd:close()
  return ok and type(data) == "table" and data or nil
end

--- @class SessionMgrMigration
--- @field from string legacy file
--- @field to string new file
--- @field project SessionMgrProject
--- @field name string
--- @field mtime integer
--- @field missing boolean the legacy cwd no longer exists

--- Work out what would be imported. Reads the filesystem, writes nothing.
--- @param root string
--- @param detect fun(cwd: string): SessionMgrProject
--- @param default_name string
--- @return SessionMgrMigration[] actions
--- @return string[] skipped reasons, for health/reporting
function M.plan(root, detect, default_name)
  local actions, skipped, taken = {}, {}, {}
  local done = (read_marker(root) or {}).imported or {}
  if not uv.fs_stat(root) then
    return actions, skipped
  end
  local names = {}
  for name, kind in vim.fs.dir(root) do
    if kind == "file" and name:sub(-#paths.EXT) == paths.EXT and not done[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  for _, fname in ipairs(names) do
    local from = root .. "/" .. fname
    local info = sessfile.parse(from)
    local cwd = info and info.cwd
    if not cwd then
      -- No cd line (curdir was not in sessionoptions): fall back to decoding.
      local guess = fname:sub(1, -#paths.EXT - 1):gsub("%%", "/")
      cwd = vim.fn.isdirectory(guess) == 1 and vim.fs.normalize(guess) or nil
    end
    if not cwd then
      skipped[#skipped + 1] = fname .. ": cannot tell which directory it was saved from"
    else
      local missing = vim.fn.isdirectory(cwd) == 0
      local project = missing and require("session-mgr.project").from_root(cwd, false) or detect(cwd)
      local name = default_name
      if not missing and cwd ~= project.root and vim.startswith(cwd, project.root .. "/") then
        name = M.derive_name(cwd:sub(#project.root + 2))
      end
      -- Never overwrite: an existing or already planned target gets a suffix.
      local base, n = name, 0
      while taken[project.key .. "/" .. name] or store.exists(root, project.key, name) do
        n = n + 1
        name = base .. "-legacy" .. (n > 1 and n or "")
      end
      taken[project.key .. "/" .. name] = true
      local stat = uv.fs_stat(from)
      actions[#actions + 1] = {
        from = from,
        to = paths.session_file(root, project.key, name),
        project = project,
        name = name,
        mtime = stat and stat.mtime.sec or os.time(),
        missing = missing,
      }
    end
  end
  return actions, skipped
end

--- Copy the planned files and record them. Idempotent: a second run plans nothing.
--- @return SessionMgrMigration[] imported
--- @return string[] problems
function M.run(root, detect, default_name)
  local actions, problems = M.plan(root, detect, default_name)
  if not uv.fs_stat(root) then
    return {}, problems
  end
  local marker = read_marker(root) or { version = 1, imported = {} }
  local imported = {}
  for _, a in ipairs(actions) do
    vim.fn.mkdir(vim.fs.dirname(a.to), "p")
    local ok, err = uv.fs_copyfile(a.from, a.to, { excl = true })
    if ok then
      store.adopt(root, a.project, a.name, a.mtime)
      marker.imported[vim.fs.basename(a.from)] = a.project.key .. "/" .. a.name .. paths.EXT
      imported[#imported + 1] = a
    else
      problems[#problems + 1] = ("%s: %s"):format(vim.fs.basename(a.from), err)
    end
  end
  marker.done_at = os.time()
  local fd = io.open(root .. "/" .. M.MARKER, "w")
  if fd then
    fd:write(vim.json.encode(marker))
    fd:close()
  end
  return imported, problems
end

--- @return boolean
function M.has_run(root)
  return read_marker(root) ~= nil
end

return M
