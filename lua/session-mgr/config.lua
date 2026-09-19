--- Config: defaults, validation, and the resolved table the rest of the
--- plugin reads. The defaults table below IS the README's config section;
--- tests/spec/readme_spec.lua fails when the two drift apart.
local M = {}

--- @class SessionMgrConfig
M.defaults = {
  -- Where sessions live: <root>/<escaped project root>/<name>.vim
  root = vim.fn.stdpath "data" .. "/sessions",
  -- The session used by `:SessionMgr save!` / `load!`. Always listed first.
  default_name = "default",
  -- Re-save the ACTIVE session on exit and before switching to another one.
  -- Never creates a session by itself.
  autosave = false,
  -- One-time, copy-only import of legacy <root>/%path%to%cwd.vim files.
  migrate_legacy = true,
  load = {
    -- true: wipe all buffers, then source (you get exactly that session).
    -- false: source on top of what is open, like a bare :source.
    replace = true,
  },
  -- 'sessionoptions' used only while saving. false = use your own setting.
  sessionoptions = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "terminal" },
  -- Windows closed before :mksession so they are not restored as empty splits.
  close_before_save = {
    filetypes = { "NvimTree", "neo-tree", "qf", "lazy", "mason", "TelescopePrompt" },
    buftypes = { "nofile", "prompt" },
  },
  -- Reopen nvim-tree after saving if it was open.
  reopen_after_save = true,
  project = {
    -- true: key sessions by the git root. false: always by the cwd.
    git_root = true,
    git_timeout_ms = 500,
  },
  picker = {
    -- false = follow 'winborder' (falls back to "rounded" when that is empty).
    border = false,
    max_width = 0.9, -- fraction of the editor
    max_height = 0.8,
    preview = true,
    preview_min_columns = 120, -- hide the preview pane below this editor width
    preview_width = 0.4, -- fraction of the picker
    mouse = true, -- click, double-click, wheel, clickable headers
    hover = true, -- highlight the row under the mouse (sets 'mousemoveevent' while open)
    refresh_ms = 1000, -- re-render relative times while open; 0 = never
    default_sort = { key = "name", dir = "asc" }, -- name|uses|last_used|updated|created
  },
  save_prompt = {
    width = 60,
    max_list_height = 10,
    prefill_active = true, -- start with the active session's name typed in
  },
  confirm = {
    delete_default_twice = true,
  },
  hints = {
    -- Key shown in "Reload with ..." messages. false = discover it from your
    -- mappings (any normal-mode map whose rhs is `<cmd>SessionMgr load<cr>`).
    load_key = false,
  },
  hooks = {
    -- Each is false or function(ctx) with ctx = { project, name, file }.
    pre_save = false,
    post_save = false,
    pre_load = false,
    post_load = false,
  },
  -- true: install <leader>ss / sl / sa / sS / sL.
  keymaps = false,
  -- false silences success messages; warnings and errors always show.
  notify = true,
  -- true: messages appear in a small self-closing float (top right) instead of
  -- vim.notify, whose two-line save message would stop at "Press ENTER".
  toast = true,
}

local SORT_KEYS = { name = true, uses = true, last_used = true, updated = true, created = true }

local resolved

--- Collect "a.b.c" paths present in `user` but absent from `defaults`, so a
--- typo in the user's opts is reported instead of silently ignored.
local function unknown_keys(user, defaults, prefix, out)
  for k, v in pairs(user) do
    local path = prefix .. tostring(k)
    if defaults[k] == nil then
      out[#out + 1] = path
    elseif type(v) == "table" and type(defaults[k]) == "table" and not vim.islist(defaults[k]) then
      unknown_keys(v, defaults[k], path .. ".", out)
    end
  end
  table.sort(out)
  return out
end

--- Options whose default is `false` meaning "unset" accept another type.
local OPTIONAL = {
  sessionoptions = "table",
  ["picker.border"] = { "string", "table" },
  ["hints.load_key"] = "string",
  ["hooks.pre_save"] = "function",
  ["hooks.post_save"] = "function",
  ["hooks.pre_load"] = "function",
  ["hooks.post_load"] = "function",
}

--- Every leaf must have the same type as its default (or its OPTIONAL type).
local function type_errors(cfg, defaults, prefix, out)
  for k, dv in pairs(defaults) do
    local path, v = prefix .. k, cfg[k]
    local alt = OPTIONAL[path]
    local alts = type(alt) == "table" and alt or { alt }
    if type(dv) == "table" and not vim.islist(dv) and type(v) == "table" then
      type_errors(v, dv, path .. ".", out)
    elseif type(v) ~= type(dv) and not (v == false and alt) and not vim.tbl_contains(alts, type(v)) then
      local want = alt and (table.concat(alts, "|") .. " or false") or type(dv)
      out[#out + 1] = ("%s must be %s, got %s"):format(path, want, type(v))
    end
  end
  table.sort(out)
  return out
end

local function fraction(v)
  return type(v) == "number" and v > 0 and v <= 1
end

--- @param opts table|nil
--- @return SessionMgrConfig cfg, string[] problems
function M.resolve(opts)
  opts = opts or {}
  local problems = {}
  for _, k in ipairs(unknown_keys(opts, M.defaults, "", {})) do
    problems[#problems + 1] = "unknown key " .. k
  end
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  vim.list_extend(problems, type_errors(cfg, M.defaults, "", {}))

  if type(cfg.picker) == "table" then
    for _, k in ipairs { "max_width", "max_height", "preview_width" } do
      if type(cfg.picker[k]) == "number" and not fraction(cfg.picker[k]) then
        problems[#problems + 1] = ("picker.%s must be in (0, 1], got %s"):format(k, cfg.picker[k])
        cfg.picker[k] = M.defaults.picker[k]
      end
    end
    local sort = cfg.picker.default_sort
    if type(sort) == "table" and not (SORT_KEYS[sort.key] and (sort.dir == "asc" or sort.dir == "desc")) then
      problems[#problems + 1] =
        "picker.default_sort must be { key = name|uses|last_used|updated|created, dir = asc|desc }"
      cfg.picker.default_sort = vim.deepcopy(M.defaults.picker.default_sort)
    end
  end
  if type(cfg.root) == "string" then
    cfg.root = vim.fs.normalize(cfg.root)
  end

  resolved = cfg
  if #problems > 0 then
    vim.notify("session-mgr: " .. table.concat(problems, "; "), vim.log.levels.WARN)
  end
  return cfg, problems
end

--- @return SessionMgrConfig
function M.get()
  return resolved or M.resolve()
end

return M
