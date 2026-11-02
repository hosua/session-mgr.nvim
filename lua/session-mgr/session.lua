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
--- Session name `autosave` writes to, so the file is <project>/autosave.vim.
M.AUTOSAVE_NAME = "autosave"

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

--- The "Reload with ..." line, naming the key the user really has. load!
--- means "default" only while autosave is off: when it is on, load! prefers
--- autosave.vim.
local function reload_hint(name)
  local cfg = config.get()
  local cmd = (name == cfg.default_name and not cfg.autosave) and ":SessionMgr load!" or (":SessionMgr load " .. name)
  local key = hints.key_for "load"
  return key and ("Reload with %s  or  %s"):format(cmd, key) or ("Reload with " .. cmd)
end

--- @param project SessionMgrProject
--- @param raw_name string
--- @param opts { silent: boolean|nil, background: boolean|nil }|nil
---   silent: no success message. background: an autosave; keep your windows
---   open and leave the active session as it is.
--- @return boolean ok, string|nil err
function M.save(project, raw_name, opts)
  local cfg = config.get()
  local name, err = validate.name(raw_name)
  if not name then
    notify("Not saved: " .. err, vim.log.levels.ERROR)
    return false, err
  end
  local file = paths.session_file(cfg.root, project.key, name)
  local background = opts and opts.background or false
  local ctx = { project = project, name = name, file = file, autosave = background }
  if vim.fn.mkdir(vim.fs.dirname(file), "p") == 0 then
    err = "cannot create " .. vim.fs.dirname(file)
    notify("Not saved: " .. err, vim.log.levels.ERROR)
    return false, err
  end

  emit("pre_save", ctx)
  -- :mksession already skips floats, quickfix and nofile windows. Closing them
  -- first only keeps manual saves tidy, and a timer must not shut your windows.
  local tree_was_open = not background and close_special_windows()
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
  if not background then
    state.set_active(project, name)
  end
  emit("post_save", ctx)
  if not (opts and opts.silent) then
    notify(("Saved %s\n%s"):format(vim.fn.fnamemodify(file, ":~"), reload_hint(name)))
  end
  return true
end

--- Re-save the ACTIVE session if `resave_active` is on. Never creates a
--- session: with nothing active, or with the file gone, it does nothing.
--- @return boolean saved
function M.resave_active()
  local cfg = config.get()
  local project, name = state.active_target()
  if not (cfg.resave_active and project and name) or not store.exists(cfg.root, project.key, name) then
    return false
  end
  return (M.save(project, name, { silent = true }))
end

--- True when some listed buffer is a file. A start screen or an empty buffer
--- is not worth a session, and saving it would replace a good autosave.vim.
local function has_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

--- Write the current layout to this project's "autosave" session if
--- `autosave` is on and a file is open.
--- @return boolean saved
function M.autosave()
  if not (config.get().autosave and has_files()) then
    return false
  end
  return (M.save(require("session-mgr.project").detect(), M.AUTOSAVE_NAME, { silent = true, background = true }))
end

--- Which session `load!` (no name) opens in `project`: autosave.vim while
--- autosave is on and the file exists, else the default session if it
--- exists. With autosave off only the default session counts.
--- @param project SessionMgrProject
--- @return string|nil name, string|nil why  why: the message when neither fits
function M.default_target(project)
  local cfg = config.get()
  local has = function(name)
    return store.exists(cfg.root, project.key, name)
  end
  if cfg.autosave and has(M.AUTOSAVE_NAME) then
    return M.AUTOSAVE_NAME
  end
  if has(cfg.default_name) then
    return cfg.default_name
  end
  if cfg.autosave then
    return nil, ("No %q or %q session for %s"):format(M.AUTOSAVE_NAME, cfg.default_name, project.label)
  end
  local why = ("No %q session for %s"):format(cfg.default_name, project.label)
  if has(M.AUTOSAVE_NAME) then
    why = why .. (". Autosave is off, so autosave.vim is skipped: :SessionMgr load %s"):format(M.AUTOSAVE_NAME)
  end
  return nil, why
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

--- Before wiping every buffer: ask about unsaved buffers and running
--- terminals, then run `go`, or call on_done(false) if you cancel.
--- @param verb "load"|"clear" names the button ("discard & load")
--- @param failed string message prefix when :wall fails
local function after_guard(verb, failed, go, on_done)
  local loss = guard.collect()
  if guard.is_clean(loss) then
    return go()
  end
  guard.ask(loss, function(choice)
    if choice == "write" then
      local ok, err = pcall(vim.cmd.wall)
      if not ok then
        notify(failed .. ", :wall failed: " .. tostring(err), vim.log.levels.ERROR)
        return on_done(false)
      end
      go()
    elseif choice == "discard" then
      go()
    else
      on_done(false)
    end
  end, verb)
end

--- @param project SessionMgrProject the project the session belongs to
--- @param name string
--- @param on_done fun(ok: boolean)|nil
--- @param opts { silent: boolean|nil }|nil silent: no "Loaded ..." message
function M.load(project, name, on_done, opts)
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
      M.resave_active()
    end
    -- The layout a load is about to wipe goes to autosave.vim, so a wrong
    -- load can be undone. Not when loading this project's autosave: that
    -- would overwrite the very file being loaded.
    if not (name == M.AUTOSAVE_NAME and project.key == require("session-mgr.project").detect().key) then
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
    if not (opts and opts.silent) then
      notify(("Loaded %s (%s)"):format(name, project.label))
    end
    on_done(true)
  end

  if not cfg.load.replace then
    return go()
  end
  after_guard("load", "Not loaded", go, on_done)
end

--- How to reach a subcommand: the user's own key if they mapped one,
--- else the command itself.
local function key_or_cmd(sub)
  return hints.key_for(sub) or (":SessionMgr " .. sub)
end

--- Start over: wipe every buffer, window and tab and leave no session
--- active. The layout being left goes to autosave.vim first (and to the
--- active session with resave_active), so `:SessionMgr load autosave`
--- brings it back until the next autosave.
--- @param on_done fun(ok: boolean)|nil
function M.new(on_done)
  on_done = on_done or function() end
  after_guard("clear", "Not cleared", function()
    M.resave_active()
    M.autosave()
    vim.cmd "silent! %bwipeout!"
    vim.cmd "silent! tabonly!"
    vim.cmd "silent! only!"
    state.clear()
    notify(("New session: nothing open. Save it with %s"):format(key_or_cmd "save"))
    on_done(true)
  end, on_done)
end

--- True when nvim looks freshly started: no file arguments, no named or
--- modified buffer, no active session, and no float focused (a picker the
--- first :SessionMgr opened).
local function fresh_start()
  if vim.fn.argc(-1) > 0 or state.active() then
    return false
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and (vim.api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].modified) then
      return false
    end
  end
  return vim.api.nvim_win_get_config(0).relative == ""
end

--- Load this project's autosave.vim when autosave is on and nvim was started
--- without files, then say how to start fresh instead.
--- @return boolean loaded
function M.autoload()
  local cfg = config.get()
  if not (cfg.autosave and fresh_start()) then
    return false
  end
  local project = require("session-mgr.project").detect()
  if not store.exists(cfg.root, project.key, M.AUTOSAVE_NAME) then
    return false
  end
  local loaded = false
  M.load(project, M.AUTOSAVE_NAME, function(ok)
    loaded = ok
  end, { silent = true })
  if loaded then
    notify(
      ("Last autosaved session was automatically loaded. You can start a new session with %s"):format(key_or_cmd "new")
    )
  end
  return loaded
end

return M
