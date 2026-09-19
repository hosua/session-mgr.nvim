--- The on-disk store: session files plus one index.json per project.
---
---   <root>/<key>/<name>.vim
---   <root>/<key>/index.json   { version, root, label, is_git, sessions = { [name] = entry } }
---   entry = { uses, created, updated, last_used }   epoch seconds; last_used absent until first load
---
--- One index per project rather than one global file, so nvim instances in
--- different projects never write the same file. Within a project, writes
--- are re-read -> mutate -> temp file -> rename, so a reader never sees a
--- half-written index; two racing writers can at worst lose one `uses` bump.
---
--- The filesystem is the truth about which sessions exist; the index only
--- adds metadata. Every read reconciles the two, in both directions.
local paths = require "session-mgr.paths"
local sessfile = require "session-mgr.sessfile"

local M = {}

M.VERSION = 1
local uv = vim.uv

--- @class SessionMgrRow
--- @field name string
--- @field file string
--- @field key string
--- @field label string
--- @field root string|nil
--- @field is_git boolean
--- @field uses integer
--- @field created integer
--- @field updated integer
--- @field last_used integer|nil

local function read_file(path)
  local fd = uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

--- @return boolean ok, string|nil err
local function write_atomic(path, data)
  local tmp = ("%s.%d.tmp"):format(path, uv.os_getpid())
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    return false, err
  end
  local _, werr = uv.fs_write(fd, data, 0)
  uv.fs_close(fd)
  if werr then
    uv.fs_unlink(tmp)
    return false, werr
  end
  local ok, rerr = uv.fs_rename(tmp, path)
  if not ok then
    uv.fs_unlink(tmp)
    return false, rerr
  end
  return true
end

--- Names of the *.vim files in a project directory.
--- @return table<string, uv.fs_stat.result>
local function session_files(dir)
  local out = {}
  for name, kind in vim.fs.dir(dir) do
    if (kind == "file" or kind == "link") and name:sub(-#paths.EXT) == paths.EXT then
      local stat = uv.fs_stat(dir .. "/" .. name)
      if stat then
        out[name:sub(1, -#paths.EXT - 1)] = stat
      end
    end
  end
  return out
end

local function blank_index()
  return { version = M.VERSION, sessions = {} }
end

--- Load and sanity-check index.json. A corrupt file is moved aside (never
--- deleted) and replaced by a blank index that reconcile() then refills.
--- @return table idx, string|nil warning
local function load_index(root, key, now)
  local file = paths.index_file(root, key)
  local data = read_file(file)
  if not data then
    return blank_index()
  end
  local ok, idx = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
  if not ok or type(idx) ~= "table" or type(idx.sessions) ~= "table" or type(idx.version) ~= "number" then
    local aside = ("%s.corrupt-%d"):format(file, now)
    uv.fs_rename(file, aside)
    return blank_index(), "index was corrupt; moved to " .. aside
  end
  return idx
end

--- Make the index agree with the files on disk. Mutates and returns `idx`
--- (a table this module just decoded, never a caller's), plus the set of
--- names that had a file but no record.
local function reconcile(idx, dir, project)
  local files = session_files(dir)
  local adopted = {}
  for name in pairs(idx.sessions) do
    if not files[name] then
      idx.sessions[name] = nil -- record without a file
    end
  end
  for name, stat in pairs(files) do
    local e = idx.sessions[name]
    if type(e) ~= "table" then
      e = {} -- file without a record: rebuild what the filesystem knows
      idx.sessions[name] = e
      adopted[name] = true
    end
    e.uses = type(e.uses) == "number" and e.uses or 0
    e.updated = type(e.updated) == "number" and e.updated or stat.mtime.sec
    e.created = type(e.created) == "number" and e.created or math.min(stat.mtime.sec, e.updated)
    e.last_used = type(e.last_used) == "number" and e.last_used or nil
  end
  if project then
    idx.root, idx.label, idx.is_git = project.root, project.label, project.is_git
  elseif not idx.root then
    -- Index lost: the session files still know where they were saved from.
    for name in pairs(files) do
      local info = sessfile.parse(paths.session_file(vim.fs.dirname(dir), vim.fs.basename(dir), name))
      if info and info.cwd then
        idx.root, idx.label, idx.is_git = info.cwd, vim.fs.basename(info.cwd), false
        break
      end
    end
  end
  return idx, adopted
end

--- @param root string config.root
--- @param key string project key
--- @param project SessionMgrProject|nil when known, refreshes root/label/is_git
--- @return table idx, string|nil warning, table<string, boolean> adopted
function M.read(root, key, project, now)
  local idx, warning = load_index(root, key, now or os.time())
  local _, adopted = reconcile(idx, paths.project_dir(root, key), project)
  return idx, warning, adopted
end

--- Re-read, apply `fn(idx)`, write atomically.
--- @param fn fun(idx: table, adopted: table<string, boolean>)
--- @return boolean ok, string|nil err
function M.update(root, project, fn, now)
  local dir = paths.project_dir(root, project.key)
  vim.fn.mkdir(dir, "p")
  local idx, _, adopted = M.read(root, project.key, project, now)
  if idx.version > M.VERSION then
    return false,
      ("index.json is version %d, newer than this plugin understands (%d); not writing"):format(idx.version, M.VERSION)
  end
  fn(idx, adopted)
  if next(idx.sessions) == nil then
    idx.sessions = vim.empty_dict() -- otherwise encoded as [] and read back as a list
  end
  return write_atomic(paths.index_file(root, project.key), vim.json.encode(idx))
end

--- Record a save. Call after the .vim file has been written.
function M.touch_saved(root, project, name, now)
  now = now or os.time()
  return M.update(root, project, function(idx, adopted)
    local e = idx.sessions[name] or { uses = 0 }
    -- A file with no record is the save that just happened: it is new now,
    -- whatever the mtime granularity says.
    if adopted[name] or not e.created then
      e.created = now
    end
    e.updated = now
    idx.sessions[name] = e
  end, now)
end

--- Record an imported session with the timestamps of the file it came from.
function M.adopt(root, project, name, ts)
  return M.update(root, project, function(idx)
    idx.sessions[name] = { uses = 0, created = ts, updated = ts }
  end, ts)
end

--- Record a load.
function M.touch_loaded(root, project, name, now)
  now = now or os.time()
  return M.update(root, project, function(idx)
    local e = idx.sessions[name]
    if e then
      e.uses = e.uses + 1
      e.last_used = now
    end
  end, now)
end

--- Rename the file and carry its metrics along.
--- @return boolean ok, string|nil err
function M.rename(root, project, old, new)
  local from, to = paths.session_file(root, project.key, old), paths.session_file(root, project.key, new)
  if not uv.fs_stat(from) then
    return false, ("no session named %q"):format(old)
  end
  if uv.fs_stat(to) then
    return false, ("a session named %q already exists"):format(new)
  end
  -- Read metrics before the move: afterwards reconcile() would drop the old record.
  local entry = M.read(root, project.key, project).sessions[old]
  local ok, err = uv.fs_rename(from, to)
  if not ok then
    return false, err
  end
  return M.update(root, project, function(idx)
    idx.sessions[new] = entry
    idx.sessions[old] = nil
  end)
end

--- Delete the file and its record.
--- @return boolean ok, string|nil err
function M.remove(root, project, name)
  local file = paths.session_file(root, project.key, name)
  if not uv.fs_stat(file) then
    return false, ("no session named %q"):format(name)
  end
  local ok, err = uv.fs_unlink(file)
  if not ok then
    return false, err
  end
  return M.update(root, project, function(idx)
    idx.sessions[name] = nil
  end)
end

--- @return boolean
function M.exists(root, key, name)
  return uv.fs_stat(paths.session_file(root, key, name)) ~= nil
end

local function rows_of(root, key, idx)
  local rows = {}
  for name, e in pairs(idx.sessions) do
    rows[#rows + 1] = {
      name = name,
      file = paths.session_file(root, key, name),
      key = key,
      label = idx.label or key,
      root = idx.root,
      is_git = idx.is_git == true,
      uses = e.uses,
      created = e.created,
      updated = e.updated,
      last_used = e.last_used,
    }
  end
  return rows
end

--- Sessions of one project. Unsorted: ordering belongs to the view model.
--- @return SessionMgrRow[]
function M.list(root, project)
  return rows_of(root, project.key, (M.read(root, project.key, project)))
end

--- Sessions of every project under `root`.
--- @return SessionMgrRow[]
function M.list_all(root)
  local rows = {}
  if not uv.fs_stat(root) then
    return rows
  end
  for key, kind in vim.fs.dir(root) do
    if kind == "directory" then
      vim.list_extend(rows, rows_of(root, key, (M.read(root, key))))
    end
  end
  return rows
end

return M
