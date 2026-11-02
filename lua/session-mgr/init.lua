--- session-mgr.nvim: public API.
---
--- setup() is optional: every entry point resolves the config on first use,
--- so the plugin works with `opts = {}` or with no setup call at all.
local M = {}

-- Declared before setup(): setup resets it so a changed `root` is re-checked.
local migrated = false

local DEFAULT_KEYS = {
  { "<leader>ss", "save", "session save as" },
  { "<leader>sl", "load", "session load picker" },
  { "<leader>sa", "autosave", "session autosave on/off" },
  { "<leader>sA", "all", "session picker, all projects" },
  { "<leader>sS", "save!", "session save default" },
  { "<leader>sL", "load!", "session load default" },
}

--- "300s" reads worse than "5m": whole minutes as minutes, else seconds.
local function every(seconds)
  return seconds % 60 == 0 and ("%dm"):format(seconds / 60) or ("%ds"):format(seconds)
end

--- Switch autosave for this nvim: starts or stops the timer, and the exit
--- save follows the same flag. Not persisted; the next start uses `autosave`
--- from your config again.
--- @param on boolean
--- @param opts { quiet: boolean|nil }|nil quiet: no message
--- @return boolean on
function M.set_autosave(on, opts)
  local cfg = require("session-mgr.config").get()
  cfg.autosave = on
  local timer = require "session-mgr.autosave"
  timer.stop()
  if on and cfg.autosave_interval > 0 then
    timer.start(cfg.autosave_interval * 1000)
  end
  if not (opts and opts.quiet) then
    local when = cfg.autosave_interval > 0 and ("every %s, "):format(every(cfg.autosave_interval)) or ""
    require("session-mgr.session").notify(
      on and ("Autosave on: autosave.vim %son exit and before a load"):format(when) or "Autosave off"
    )
  end
  return on
end

--- @return boolean on
function M.toggle_autosave()
  return M.set_autosave(not require("session-mgr.config").get().autosave)
end

--- @param opts table|nil user overrides, merged over config.defaults
function M.setup(opts)
  local cfg = require("session-mgr.config").resolve(opts)
  migrated = false
  local group = vim.api.nvim_create_augroup("session-mgr", { clear = true })
  -- Always registered, since autosave can be switched on later with
  -- set_autosave(). Each save checks its own option.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "session-mgr: write autosave.vim and re-save the active session",
    callback = function()
      local session = require "session-mgr.session"
      session.resave_active()
      session.autosave()
    end,
  })
  M.set_autosave(cfg.autosave, { quiet = true })
  if cfg.keymaps then
    for _, k in ipairs(DEFAULT_KEYS) do
      vim.keymap.set("n", k[1], ("<cmd>SessionMgr %s<cr>"):format(k[2]), { desc = k[3] })
    end
  end
end

local function current_project()
  return require("session-mgr.project").detect()
end

--- Import legacy sessions once per nvim instance (and, thanks to the marker
--- file, effectively once ever). Called by every entry point that reads or
--- writes the store, so it happens before the first listing.
function M.ensure_migrated()
  local cfg = require("session-mgr.config").get()
  if migrated or not cfg.migrate_legacy then
    return
  end
  migrated = true
  local migrate = require "session-mgr.migrate"
  if migrate.has_run(cfg.root) then
    return
  end
  local imported, problems = migrate.run(cfg.root, require("session-mgr.project").detect, cfg.default_name)
  local notify = require("session-mgr.session").notify
  if #imported > 0 then
    local lines = { ("Imported %d legacy session(s); the original files were left untouched:"):format(#imported) }
    for _, a in ipairs(imported) do
      lines[#lines + 1] = ("  %s  ->  %s / %s"):format(vim.fs.basename(a.from), a.project.label, a.name)
    end
    notify(table.concat(lines, "\n"))
  end
  if #problems > 0 then
    notify("Legacy sessions not imported:\n  " .. table.concat(problems, "\n  "), vim.log.levels.WARN)
  end
end

--- Save the current project's session `name`; nil/"" means the default session.
--- @param name string|nil
--- @return boolean ok, string|nil err
function M.save(name)
  M.ensure_migrated()
  local cfg = require("session-mgr.config").get()
  return require("session-mgr.session").save(current_project(), (name and name ~= "") and name or cfg.default_name)
end

--- Load the current project's session `name`; nil/"" means the default session.
--- @param name string|nil
--- @param on_done fun(ok: boolean)|nil
function M.load(name, on_done)
  M.ensure_migrated()
  local cfg = require("session-mgr.config").get()
  local n = (name and name ~= "") and name or cfg.default_name
  require("session-mgr.session").load(current_project(), n, on_done)
end

--- @return boolean ok, string|nil err
function M.rename(old, new)
  M.ensure_migrated()
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
  M.ensure_migrated()
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
  M.ensure_migrated()
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
