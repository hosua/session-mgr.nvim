--- session-mgr.nvim: public API.
---
--- setup() is optional: every entry point resolves the config on first use,
--- so the plugin works with `opts = {}` or with no setup call at all.
local M = {}

local DEFAULT_KEYS = {
  { "<leader>ss", "save", "session save as" },
  { "<leader>sl", "load", "session load picker" },
  { "<leader>sa", "all", "session picker, all projects" },
  { "<leader>sS", "save!", "session save default" },
  { "<leader>sL", "load!", "session load default" },
}

--- @param opts table|nil user overrides, merged over config.defaults
function M.setup(opts)
  local cfg = require("session-mgr.config").resolve(opts)
  if cfg.keymaps then
    for _, k in ipairs(DEFAULT_KEYS) do
      vim.keymap.set("n", k[1], ("<cmd>SessionMgr %s<cr>"):format(k[2]), { desc = k[3] })
    end
  end
end

local function current_project()
  return require("session-mgr.project").detect()
end

--- Save the current project's session `name`; nil/"" means the default session.
--- @param name string|nil
--- @return boolean ok, string|nil err
function M.save(name)
  local cfg = require("session-mgr.config").get()
  return require("session-mgr.session").save(current_project(), (name and name ~= "") and name or cfg.default_name)
end

--- Load the current project's session `name`; nil/"" means the default session.
--- @param name string|nil
--- @param on_done fun(ok: boolean)|nil
function M.load(name, on_done)
  local cfg = require("session-mgr.config").get()
  local n = (name and name ~= "") and name or cfg.default_name
  require("session-mgr.session").load(current_project(), n, on_done)
end

--- @return boolean ok, string|nil err
function M.rename(old, new)
  local cfg = require("session-mgr.config").get()
  local clean, err = require("session-mgr.validate").name(new)
  if not clean then
    return false, err
  end
  local project = current_project()
  local ok, rerr = require("session-mgr.store").rename(cfg.root, project, old, clean)
  local state = require "session-mgr.state"
  if ok and state.active_in(project) == old then
    state.set_active(project, clean)
  end
  return ok, rerr
end

--- @return boolean ok, string|nil err
function M.delete(name)
  local cfg = require("session-mgr.config").get()
  local project = current_project()
  local ok, err = require("session-mgr.store").remove(cfg.root, project, name)
  local state = require "session-mgr.state"
  if ok and state.active_in(project) == name then
    state.clear()
  end
  return ok, err
end

--- Names of the current project's sessions, default first, then A-Z.
--- @return string[]
function M.names()
  local cfg = require("session-mgr.config").get()
  local names = vim.tbl_map(function(r)
    return r.name
  end, require("session-mgr.store").list(cfg.root, current_project()))
  table.sort(names, function(a, b)
    if (a == cfg.default_name) ~= (b == cfg.default_name) then
      return a == cfg.default_name
    end
    return a:lower() < b:lower()
  end)
  return names
end

--- @return { key: string, name: string }|nil
function M.active()
  return require("session-mgr.state").active()
end

return M
