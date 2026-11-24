--- Config: defaults, validation, and the resolved table the rest of the
--- plugin reads. The defaults table below IS the README's config section;
--- tests/spec/readme_spec.lua fails when the two drift apart.
local M = {}

--- @class SessionMgrConfig
M.defaults = {
  -- Where sessions live: <root>/<escaped project root>/<name>.vim
  root = vim.fn.stdpath "data" .. "/sessions",
  -- The session `:SessionMgr save!` writes. `load!` loads it too, unless
  -- autosave is on and autosave.vim exists. Always listed first.
  default_name = "default",
  -- Write the current layout to this project's "autosave" session
  -- (autosave.vim) every autosave_interval seconds, on exit, and before a
  -- load replaces your buffers. Skipped while no file is open, so an empty
  -- start screen never overwrites it. Leaves the active session alone.
  autosave = true,
  autosave_interval = 300, -- seconds; 0 = only on exit and before a load
  -- Starting nvim with no files in a project that has an autosave.vim:
  -- "prompt" asks first (default is No), "always" loads it without asking,
  -- false never offers it. Needs autosave = true.
  autoload = "prompt",
  -- Re-save the ACTIVE session on exit and before switching to another one.
  -- Never creates a session by itself.
  resave_active = false,
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
  -- Which project a directory belongs to: the git root, else the nearest
  -- parent holding one of `markers`, else `fallback`.
  project = {
    -- true: look for a git root first. false: skip git and go to the markers.
    git_root = true,
    git_timeout_ms = 500,
    -- Drop one of these into a directory (a `.session-root` file is enough)
    -- to make it a project. The search stops at your home directory.
    markers = { ".hg", ".session-root" },
    -- Where to go when neither git nor a marker matches. "home": your home
    -- directory. "cwd": the current directory.
    fallback = "home",
    -- true: a directory you cannot read or write (and that git and the
    -- markers missed) asks for approval before it holds a session, like a
    -- parent of your home. false turns only this rule off.
    require_access = true,
  },
  -- Buffers that never count as "a file is open" and never get autosaved
  -- over, such as the message editor `git commit` starts. Patterns are Lua
  -- patterns matched against the full buffer name.
  ignore = {
    filetypes = { "gitcommit", "gitrebase", "gitconfig", "hgcommit", "svn", "crontab" },
    patterns = {
      "COMMIT_EDITMSG$",
      "MERGE_MSG$",
      "TAG_EDITMSG$",
      "git%-rebase%-todo$",
      "addp%-hunk%-edit%.diff$",
      "/%.git/",
    },
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
  -- The Processes tab of the picker (:SessionMgr procs). Linux only: it reads /proc.
  procs = {
    refresh_ms = 2000, -- re-sample while the tab is showing; 0 = only on `r`
    -- "pss": proportional memory from /proc/<pid>/smaps_rollup, so shared
    -- libraries are counted once and tree totals add up. "rss": what htop
    -- shows as RES; cheaper, but shared pages count in every process.
    memory = "pss",
    default_sort = { key = "tree", dir = "desc" }, -- pid|tree|own|threads|cpu|command
    orphans = true, -- list mason language servers whose nvim is gone
    big_mb = 1024, -- memory at or above this is drawn as a warning
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
    -- Each is false or function(ctx) with ctx = { project, name, file, autosave }.
    pre_save = false,
    post_save = false,
    pre_load = false,
    post_load = false,
  },
  -- true: install <leader>ss / sl / sa / sA / sn / sS / sL.
  keymaps = false,
  -- false silences success messages; warnings and errors always show.
  notify = true,
  -- true: messages appear in a small self-closing float (top right) instead of
  -- vim.notify, whose two-line save message would stop at "Press ENTER".
  toast = true,
}

local SORT_KEYS = { name = true, uses = true, last_used = true, updated = true, created = true }
local PROC_SORT_KEYS = { pid = true, tree = true, own = true, threads = true, cpu = true, command = true }

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
  autoload = "string",
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
  if type(cfg.procs) == "table" then
    local pc = cfg.procs
    if type(pc.memory) == "string" and pc.memory ~= "pss" and pc.memory ~= "rss" then
      problems[#problems + 1] = ("procs.memory must be pss|rss, got %s"):format(pc.memory)
      pc.memory = M.defaults.procs.memory
    end
    local sort = pc.default_sort
    if type(sort) == "table" and not (PROC_SORT_KEYS[sort.key] and (sort.dir == "asc" or sort.dir == "desc")) then
      problems[#problems + 1] = "procs.default_sort must be { key = pid|tree|own|threads|cpu|command, dir = asc|desc }"
      pc.default_sort = vim.deepcopy(M.defaults.procs.default_sort)
    end
    for _, k in ipairs { "refresh_ms", "big_mb" } do
      if type(pc[k]) == "number" and pc[k] < 0 then
        problems[#problems + 1] = ("procs.%s must be >= 0, got %s"):format(k, pc[k])
        pc[k] = M.defaults.procs[k]
      end
    end
  end
  if cfg.autoload ~= false and cfg.autoload ~= "prompt" and cfg.autoload ~= "always" then
    if type(cfg.autoload) == "string" then
      problems[#problems + 1] = ("autoload must be prompt|always|false, got %q"):format(cfg.autoload)
    end
    cfg.autoload = M.defaults.autoload
  end
  if type(cfg.project) == "table" then
    local pj = cfg.project
    if type(pj.fallback) == "string" and pj.fallback ~= "home" and pj.fallback ~= "cwd" then
      problems[#problems + 1] = ("project.fallback must be home|cwd, got %s"):format(pj.fallback)
      pj.fallback = M.defaults.project.fallback
    end
    -- The type check above already reported a non-boolean; fall back to the default.
    if type(pj.require_access) ~= "boolean" then
      pj.require_access = M.defaults.project.require_access
    end
  end
  for _, g in ipairs { { "project", "markers" }, { "ignore", "filetypes" }, { "ignore", "patterns" } } do
    local list = type(cfg[g[1]]) == "table" and cfg[g[1]][g[2]]
    local all_strings = type(list) == "table"
      and vim.iter(list):all(function(v)
        return type(v) == "string"
      end)
    if type(list) == "table" and not all_strings then
      problems[#problems + 1] = ("%s.%s must be a list of strings"):format(g[1], g[2])
      cfg[g[1]][g[2]] = vim.deepcopy(M.defaults[g[1]][g[2]])
    end
  end
  local every = cfg.autosave_interval
  if type(every) == "number" and every ~= 0 and every < 10 then
    problems[#problems + 1] = ("autosave_interval must be 0 or >= 10 seconds, got %s"):format(every)
    cfg.autosave_interval = M.defaults.autosave_interval
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
