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
  if vim.fn.executable "git" == 1 then
    h.ok "git found (sessions are keyed by the git root)"
  else
    h.warn("git not found: every directory is its own project", { "Install git, or set project.git_root = false" })
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

  local migrate = require "session-mgr.migrate"
  if not cfg.migrate_legacy then
    h.info "legacy migration disabled (migrate_legacy = false)"
  elseif migrate.has_run(root) then
    h.ok("legacy sessions already imported (" .. paths.tilde(root .. "/" .. migrate.MARKER, vim.env.HOME) .. ")")
  else
    local actions, skipped = migrate.plan(root, require("session-mgr.project").detect, cfg.default_name)
    h.info(("%d legacy session(s) will be imported on first use"):format(#actions))
    for _, a in ipairs(actions) do
      h.info(("  %s -> %s / %s"):format(vim.fs.basename(a.from), a.project.label, a.name))
    end
    for _, s in ipairs(skipped) do
      h.warn(s)
    end
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
