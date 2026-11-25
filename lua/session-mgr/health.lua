--- :checkhealth session-mgr
local M = {}

function M.check()
  local h = vim.health
  local cfg, problems = require("session-mgr.config").get(), {}
  h.start "session-mgr: environment"
  if vim.fn.has "nvim-0.11" == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error "Neovim >= 0.11 is required"
  end
  -- Which copy is loaded matters when a dev checkout and a lazy clone coexist.
  local src = debug.getinfo(require("session-mgr").setup, "S").source:gsub("^@", "")
  h.info("loaded from " .. vim.fn.fnamemodify(src, ":~"))
  for _, mod in ipairs { "popup", "plenary" } do
    if pcall(require, mod) then
      h.ok(mod .. ".nvim found")
    else
      h.error(mod .. ".nvim not found", { "Add it to the lazy spec dependencies of session-mgr.nvim" })
    end
  end
  -- The startup question and the settings menu need these two popup.nvim features.
  if pcall(require, "popup") then
    local legend_ok = type(require("popup.legend").footer) == "function"
    local menu_ok = type(require("popup.list_menu").border_footer) == "function"
    if legend_ok and menu_ok then
      h.ok "popup.nvim has confirm menus and border legends"
    else
      h.error(
        "popup.nvim is too old: it lacks legend.footer or list_menu border_legend",
        { "Update popup.nvim (the confirm-menu release)" }
      )
    end
  end
  if vim.fn.executable "git" == 1 then
    h.ok "git found (a git root is the first choice for a project)"
  else
    h.warn(
      "git not found: projects come from markers, else your home",
      { "Install git, or set project.git_root = false" }
    )
  end

  h.start "session-mgr: storage"
  local root = cfg.root
  if vim.fn.isdirectory(root) == 0 then
    h.info(root .. " does not exist yet; it is created on the first save")
  elseif vim.fn.filewritable(root) == 2 then
    h.ok(vim.fn.fnamemodify(root, ":~") .. " is writable")
  else
    h.error(root .. " is not writable")
  end
  local store, paths = require "session-mgr.store", require "session-mgr.paths"
  local projects, sessions = 0, 0
  if vim.fn.isdirectory(root) == 1 then
    for key, kind in vim.fs.dir(root) do
      if kind == "directory" then
        projects = projects + 1
        local idx, warning = store.read(root, key)
        sessions = sessions + vim.tbl_count(idx.sessions)
        if warning then
          problems[#problems + 1] = key .. ": " .. warning
        end
        if idx.version > store.VERSION then
          problems[#problems + 1] = ("%s: index version %d is newer than this plugin (%d); read-only"):format(
            key,
            idx.version,
            store.VERSION
          )
        end
        if not idx.root then
          problems[#problems + 1] = key .. ": project root unknown (no index and no `cd` line in its sessions)"
        end
      end
    end
  end
  h.info(("%d session(s) in %d project(s)"):format(sessions, projects))
  for _, p in ipairs(problems) do
    h.warn(p)
  end
  if #problems == 0 and projects > 0 then
    h.ok "every index.json parses"
  end

  local settings = require "session-mgr.settings"
  local sfile = settings.read(root)
  local spath = paths.tilde(settings.file(root), vim.env.HOME)
  if sfile.status == "missing" then
    h.info(spath .. " does not exist (nothing was remembered; setup() decides)")
  elseif sfile.status == "ok" then
    local n = vim.tbl_count(sfile.raw)
    h.ok(("%s parses (%d key%s, %d in use)"):format(spath, n, n == 1 and "" or "s", vim.tbl_count(sfile.values)))
  else
    h.error(spath .. " is ignored: " .. sfile.err, { "Fix it with :SessionMgr settings, then e" })
  end
  for _, key in ipairs(settings.names()) do
    local value, source, locked = settings.get(key, root)
    h.info(("%s = %s (%s%s)"):format(key, value, source, locked and (", " .. locked) or ""))
  end

  local migrate = require "session-mgr.migrate"
  if not cfg.migrate_legacy then
    h.info "legacy migration disabled (migrate_legacy = false)"
  elseif migrate.has_run(root) then
    h.ok("legacy sessions already imported (" .. paths.tilde(root .. "/" .. migrate.MARKER, vim.env.HOME) .. ")")
  else
    local actions, skipped = migrate.plan(root, require("session-mgr.project").detect_legacy, cfg.default_name)
    h.info(("%d legacy session(s) will be imported on first use"):format(#actions))
    for _, a in ipairs(actions) do
      h.info(("  %s -> %s / %s"):format(vim.fs.basename(a.from), a.project.label, a.name))
    end
    for _, s in ipairs(skipped) do
      h.warn(s)
    end
  end

  h.start "session-mgr: processes tab"
  local ok_procs, why = require("session-mgr.procs.collect").supported()
  if ok_procs then
    h.ok("/proc and ps found; memory shown as " .. cfg.procs.memory:upper())
  else
    h.warn(why)
  end

  h.start "session-mgr: editor"
  h.info(
    "sessionoptions while saving: "
      .. (cfg.sessionoptions and table.concat(cfg.sessionoptions, ",") or vim.o.sessionoptions)
  )
  if not vim.tbl_contains(cfg.sessionoptions or vim.split(vim.o.sessionoptions, ","), "curdir") then
    h.warn "`curdir` is not in sessionoptions: sessions will not restore their directory"
  end
  local key = require("session-mgr.hints").key_for "load"
  if key then
    h.ok("load key shown in messages: " .. key)
  else
    h.info "no mapping to `<cmd>SessionMgr load<cr>` found; messages will only name the command"
  end
  local active = require("session-mgr").active()
  h.info("active session: " .. (active and active.name or "none"))
end

return M
