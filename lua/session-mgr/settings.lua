--- Permanent options you change from inside nvim (the startup question's
--- "never ask again", `:SessionMgr settings`). They live in
--- <config.root>/settings.json, a JSON object beside approved_roots.json.
---
--- Precedence: a key present in settings.json wins over the same option in
--- setup(). A missing key leaves the choice to setup(). Unknown keys are kept
--- when the file is rewritten and ignored otherwise. A value the schema does
--- not allow is ignored with one warning. A file that is not valid JSON is
--- never overwritten: fix it by hand (`:SessionMgr settings`, then `e`).
---
--- A new option is one entry in SCHEMA.
local jsonfile = require "session-mgr.jsonfile"

local M = {}

local FILE = "settings.json"

--- @class SessionMgrSetting
--- @field values string[] allowed values, in cycling order
--- @field desc string one line for the settings menu
--- @field setup fun(cfg: SessionMgrConfig): string the value setup() asks for
--- @field locked? fun(cfg: SessionMgrConfig): string|nil why setup() overrules the file, or nil

--- @type table<string, SessionMgrSetting>
M.SCHEMA = {
  autoload = {
    values = { "prompt", "always", "never" },
    desc = "plain nvim in a project with an autosave: ask, load it, or leave it",
    setup = function(cfg)
      return (cfg.autoload == false or not cfg.autosave) and "never" or cfg.autoload
    end,
    -- setup(autoload = false) and autosave = false are the hard off switches.
    locked = function(cfg)
      if cfg.autoload == false then
        return "setup() has autoload = false"
      end
      if not cfg.autosave then
        return "setup() has autosave = false"
      end
    end,
  },
}

--- Option names in menu order.
--- @return string[]
function M.names()
  local names = vim.tbl_keys(M.SCHEMA)
  table.sort(names)
  return names
end

--- @param root string|nil defaults to config.root
--- @return string
function M.file(root)
  return vim.fs.normalize(root or require("session-mgr.config").get().root) .. "/" .. FILE
end

local warned = {}

--- Forget which warnings were shown (tests, and a fresh setup()).
function M.reset_warned()
  warned = {}
end

local function warn_once(id, msg)
  if warned[id] then
    return
  end
  warned[id] = true
  require("session-mgr.session").notify(msg, vim.log.levels.WARN)
end

--- @class SessionMgrSettingsFile
--- @field status "missing"|"ok"|"error"
--- @field err string|nil why the file cannot be used
--- @field raw table every key in the file, unknown ones included
--- @field values table<string, string> the valid, known ones

--- Read the file. Never throws; warns once per problem.
--- @param root string|nil
--- @return SessionMgrSettingsFile
function M.read(root)
  local path = M.file(root)
  local data, err = jsonfile.read(path)
  if err == "missing" then
    return { status = "missing", raw = {}, values = {} }
  end
  if err or type(data) ~= "table" or (next(data) ~= nil and vim.islist(data)) then
    err = err or "not a JSON object"
    warn_once(path .. "|file", ("%s is ignored: %s"):format(vim.fn.fnamemodify(path, ":~"), err))
    return { status = "error", err = err, raw = {}, values = {} }
  end
  local values = {}
  for key, value in pairs(data) do
    local def = M.SCHEMA[key]
    if def then
      if vim.tbl_contains(def.values, value) then
        values[key] = value
      else
        warn_once(
          ("%s|%s|%s"):format(path, key, vim.inspect(value)),
          ("settings.json: %s = %s is ignored (use %s)"):format(
            key,
            vim.json.encode(value),
            table.concat(def.values, ", ")
          )
        )
      end
    end
  end
  return { status = "ok", raw = data, values = values }
end

--- The value in force and where it comes from.
--- @param key string
--- @param root string|nil
--- @return string value, "settings"|"setup" source, string|nil locked why setup() overrules the file
function M.get(key, root)
  local def = assert(M.SCHEMA[key], "unknown setting " .. tostring(key))
  local cfg = require("session-mgr.config").get()
  local locked = def.locked and def.locked(cfg)
  if locked then
    return def.setup(cfg), "setup", locked
  end
  local from_file = M.read(root).values[key]
  if from_file then
    return from_file, "settings"
  end
  return def.setup(cfg), "setup"
end

--- Just the value. Everything that acts on a setting calls this one.
--- @param key string
--- @return string
function M.effective(key)
  return (M.get(key))
end

--- JSON text for a settings object: one key per line, sorted.
--- @param obj table
--- @return string
local function encode(obj)
  local keys = vim.tbl_keys(obj)
  if #keys == 0 then
    return "{}\n"
  end
  table.sort(keys)
  local lines = {}
  for i, k in ipairs(keys) do
    lines[i] = ("  %s: %s%s"):format(vim.json.encode(k), vim.json.encode(obj[k]), i < #keys and "," or "")
  end
  return "{\n" .. table.concat(lines, "\n") .. "\n}\n"
end

--- @param root string|nil
--- @param change fun(raw: table)
--- @return boolean ok, string|nil err
local function rewrite(root, change)
  local file = M.read(root)
  if file.status == "error" then
    return false,
      ("%s is not usable (%s); fix it by hand first"):format(vim.fn.fnamemodify(M.file(root), ":~"), file.err)
  end
  local raw = vim.deepcopy(file.raw)
  change(raw)
  return jsonfile.write(M.file(root), encode(raw))
end

--- Write `key = value` into settings.json.
--- @param key string
--- @param value string
--- @param root string|nil
--- @return boolean ok, string|nil err
function M.set(key, value, root)
  local def = M.SCHEMA[key]
  if not def then
    return false, ("unknown setting %q"):format(tostring(key))
  end
  if not vim.tbl_contains(def.values, value) then
    return false, ("%s must be one of %s, got %s"):format(key, table.concat(def.values, ", "), vim.inspect(value))
  end
  return rewrite(root, function(raw)
    raw[key] = value
  end)
end

--- Remove `key` from settings.json so setup() decides again.
--- @param key string
--- @param root string|nil
--- @return boolean ok, string|nil err
function M.reset(key, root)
  if not M.SCHEMA[key] then
    return false, ("unknown setting %q"):format(tostring(key))
  end
  if M.read(root).status == "missing" then
    return true
  end
  return rewrite(root, function(raw)
    raw[key] = nil
  end)
end

--- The next allowed value after the one in force.
--- @param key string
--- @param root string|nil
--- @return boolean ok, string|nil err_or_value
function M.cycle(key, root)
  local def = M.SCHEMA[key]
  if not def then
    return false, ("unknown setting %q"):format(tostring(key))
  end
  local current = M.get(key, root)
  local at = 0
  for i, v in ipairs(def.values) do
    if v == current then
      at = i
    end
  end
  local value = def.values[at % #def.values + 1]
  local ok, err = M.set(key, value, root)
  return ok, ok and value or err
end

--- Rows for the settings menu. Pure given the files on disk.
--- @param root string|nil
--- @return { key: string, value: string, source: string, locked: string|nil, desc: string }[]
function M.rows(root)
  local rows = {}
  for _, key in ipairs(M.names()) do
    local value, source, locked = M.get(key, root)
    rows[#rows + 1] = { key = key, value = value, source = source, locked = locked, desc = M.SCHEMA[key].desc }
  end
  return rows
end

return M
