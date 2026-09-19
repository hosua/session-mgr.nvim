--- Saving and loading: the only module that runs :mksession and :source.
local config = require "session-mgr.config"
local guard = require "session-mgr.guard"
local hints = require "session-mgr.hints"
local paths = require "session-mgr.paths"
local state = require "session-mgr.state"
local store = require "session-mgr.store"
local validate = require "session-mgr.validate"

local M = {}
local TITLE = "session-mgr"

--- Messages go to a corner toast when there is a UI to draw it on, else to
--- vim.notify (headless, or toast = false). Warnings and errors always show.
local function notify(msg, level)
  local cfg = config.get()
  if not (cfg.notify or (level or 0) >= vim.log.levels.WARN) then
    return
  end
  if cfg.toast and #vim.api.nvim_list_uis() > 0 then
    require("session-mgr.ui.toast").show(msg, level)
  else
    vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
  end
end
M.notify = notify

--- Run a user hook or fire a User autocmd; a failing hook must never break a save.
local function emit(event, ctx)
  local hook = config.get().hooks[event]
  if hook then
    local ok, err = pcall(hook, ctx)
    if not ok then
      notify(("hooks.%s failed: %s"):format(event, err), vim.log.levels.WARN)
    end
  end
  local pattern = "SessionMgr" .. event:gsub("^%l", string.upper):gsub("_(%l)", function(c)
    return c:upper()
  end)
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = pattern, data = ctx, modeline = false })
end

--- Close windows that would come back as empty splits: floats, file trees,
--- quickfix and friends. Never closes the last window of a tab.
--- @return boolean tree_was_open
local function close_special_windows()
  local cfg = config.get().close_before_save
  local tree_was_open = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft, bt = vim.bo[buf].filetype, vim.bo[buf].buftype
      local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
      local special = is_float or vim.tbl_contains(cfg.filetypes, ft) or vim.tbl_contains(cfg.buftypes, bt)
      local tab_wins = #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))
      if special and (is_float or tab_wins > 1) then
        tree_was_open = tree_was_open or ft == "NvimTree"
        pcall(vim.api.nvim_win_close, win, false)
      end
    end
  end
  return tree_was_open
end

local function reopen_tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    local win = vim.api.nvim_get_current_win()
    pcall(api.tree.open)
    pcall(vim.api.nvim_set_current_win, win)
  end
end

--- The "Reload with ..." line, naming the key the user really has.
local function reload_hint(name)
  local cmd = name == config.get().default_name and ":SessionMgr load!" or (":SessionMgr load " .. name)
  local key = hints.key_for "load"
  return key and ("Reload with %s  or  %s"):format(cmd, key) or ("Reload with " .. cmd)
end

--- @param project SessionMgrProject
--- @param raw_name string
--- @param opts { silent: boolean|nil }|nil silent: no success message (autosave)
--- @return boolean ok, string|nil err
function M.save(project, raw_name, opts)
  local cfg = config.get()
  local name, err = validate.name(raw_name)
  if not name then
    notify("Not saved: " .. err, vim.log.levels.ERROR)
    return false, err
  end
  local file = paths.session_file(cfg.root, project.key, name)
  local ctx = { project = project, name = name, file = file }
  if vim.fn.mkdir(vim.fs.dirname(file), "p") == 0 then
    err = "cannot create " .. vim.fs.dirname(file)
    notify("Not saved: " .. err, vim.log.levels.ERROR)
    return false, err
  end

  emit("pre_save", ctx)
  local tree_was_open = close_special_windows()
  local saved_ssop = vim.o.sessionoptions
  if cfg.sessionoptions then
    vim.o.sessionoptions = table.concat(cfg.sessionoptions, ",")
  end
  local ok, mk_err = pcall(vim.cmd.mksession, { args = { vim.fn.fnameescape(file) }, bang = true })
  vim.o.sessionoptions = saved_ssop
  if tree_was_open and cfg.reopen_after_save then
    reopen_tree()
  end
  if not ok then
    notify("Not saved: " .. tostring(mk_err), vim.log.levels.ERROR)
    return false, tostring(mk_err)
  end

  local stored, store_err = store.touch_saved(cfg.root, project, name)
  if not stored then
    notify("Saved, but the index was not updated: " .. tostring(store_err), vim.log.levels.WARN)
  end
  state.set_active(project, name)
  emit("post_save", ctx)
  if not (opts and opts.silent) then
    notify(("Saved %s\n%s"):format(vim.fn.fnamemodify(file, ":~"), reload_hint(name)))
  end
  return true
end

--- Re-save the ACTIVE session if `autosave` is on. Never creates a session:
--- with nothing active, or with the file gone, it does nothing.
--- @return boolean saved
function M.autosave()
  local cfg = config.get()
  local project, name = state.active_target()
  if not (cfg.autosave and project and name) or not store.exists(cfg.root, project.key, name) then
    return false
  end
  return (M.save(project, name, { silent = true }))
end

--- Source `file`, after proving it lives under the sessions root: a session
--- file is Vimscript, and sourcing runs it.
local function source(file)
  local cfg = config.get()
  local real_root, real_file = vim.uv.fs_realpath(cfg.root), vim.uv.fs_realpath(file)
  if not (real_root and real_file and paths.is_under(real_root, real_file)) then
    return false, "refusing to source a file outside " .. cfg.root
  end
  local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(real_file))
  return ok, ok and nil or tostring(err)
end

--- @param project SessionMgrProject the project the session belongs to
--- @param name string
--- @param on_done fun(ok: boolean)|nil
function M.load(project, name, on_done)
  on_done = on_done or function() end
  local cfg = config.get()
  local file = paths.session_file(cfg.root, project.key, name)
  if not vim.uv.fs_stat(file) then
    notify(("No session named %q for %s"):format(name, project.label), vim.log.levels.WARN)
    return on_done(false)
  end
  local ctx = { project = project, name = name, file = file }

  local function go()
    -- Switching away: keep the session being left up to date first. Skipped
    -- when reloading the active session itself, which would defeat "load".
    if not (state.active_in(project) == name) then
      M.autosave()
    end
    emit("pre_load", ctx)
    if cfg.load.replace then
      vim.cmd "silent! %bwipeout!"
    end
    local ok, err = source(file)
    if not ok then
      notify(("Could not load %s: %s"):format(name, err), vim.log.levels.ERROR)
      return on_done(false)
    end
    store.touch_loaded(cfg.root, project, name)
    state.set_active(project, name)
    emit("post_load", ctx)
    notify(("Loaded %s (%s)"):format(name, project.label))
    on_done(true)
  end

  local loss = cfg.load.replace and guard.collect() or nil
  if not loss or guard.is_clean(loss) then
    return go()
  end
  guard.ask(loss, function(choice)
    if choice == "write" then
      local ok, err = pcall(vim.cmd.wall)
      if not ok then
        notify("Not loaded, :wall failed: " .. tostring(err), vim.log.levels.ERROR)
        return on_done(false)
      end
      go()
    elseif choice == "discard" then
      go()
    else
      on_done(false)
    end
  end)
end

return M
