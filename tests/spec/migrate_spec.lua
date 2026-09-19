local migrate = require "session-mgr.migrate"
local paths = require "session-mgr.paths"
local project = require "session-mgr.project"
local store = require "session-mgr.store"

--- A sessions root holding legacy files shaped like the real ones: a git
--- repo root, two of its subfolders, a plain folder, and a vanished folder.
local function legacy_world()
  local base = vim.uv.fs_realpath(tmpdir())
  local repo, plain = base .. "/mach", base .. "/scratch"
  vim.fn.mkdir(repo .. "/sysconfig/terraform", "p")
  vim.fn.mkdir(repo .. "/wellstat", "p")
  vim.fn.mkdir(plain, "p")
  vim.system({ "git", "init", "-q", repo }):wait()
  local root = base .. "/sessions"
  vim.fn.mkdir(root, "p")
  local function legacy(cwd, extra)
    local body = { "let SessionLoad = 1", "cd " .. cwd, "badd +1 a.txt" }
    vim.list_extend(body, extra or {})
    vim.fn.writefile(body, root .. "/" .. paths.escape(cwd) .. ".vim")
  end
  legacy(repo)
  legacy(repo .. "/sysconfig/terraform")
  legacy(repo .. "/wellstat")
  legacy(plain)
  legacy(base .. "/gone")
  project.clear_cache()
  local detect = function(cwd)
    return project.detect(cwd, { git_root = true, git_timeout_ms = 2000 })
  end
  return root, detect, repo, plain, base
end

local function summary(actions)
  local out = {}
  for _, a in ipairs(actions) do
    out[#out + 1] = a.project.label .. "/" .. a.name
  end
  table.sort(out)
  return out
end

describe("migrate.derive_name", function()
  it("joins path components and stays a valid name", function()
    eq("sysconfig-terraform", migrate.derive_name "sysconfig/terraform")
    eq("hidden-x", migrate.derive_name ".hidden/x")
    eq("legacy", migrate.derive_name "...")
  end)
end)

describe("migrate", function()
  it("plans the repo root as default and subfolders as named sessions", function()
    local root, detect = legacy_world()
    local actions, skipped = migrate.plan(root, detect, "default")
    eq({}, skipped)
    eq(
      { "gone/default", "mach/default", "mach/sysconfig-terraform", "mach/wellstat", "scratch/default" },
      summary(actions)
    )
  end)

  it("copies, keeps the originals byte-identical, and records legacy mtimes", function()
    local root, detect, repo = legacy_world()
    local legacy_file = root .. "/" .. paths.escape(repo) .. ".vim"
    local before = vim.fn.readfile(legacy_file)
    local imported, problems = migrate.run(root, detect, "default")
    eq({}, problems)
    eq(5, #imported)
    eq(before, vim.fn.readfile(legacy_file))
    local p = detect(repo)
    eq(before, vim.fn.readfile(paths.session_file(root, p.key, "default")))
    local rows = store.list(root, p)
    eq(3, #rows)
    eq(vim.uv.fs_stat(legacy_file).mtime.sec, rows[1].created)
    eq(0, rows[1].uses)
  end)

  it("is idempotent", function()
    local root, detect = legacy_world()
    migrate.run(root, detect, "default")
    ok(migrate.has_run(root))
    eq({}, (migrate.plan(root, detect, "default")))
    eq({}, (migrate.run(root, detect, "default")))
  end)

  it("never overwrites an existing session", function()
    local root, detect, repo = legacy_world()
    local p = detect(repo)
    vim.fn.mkdir(paths.project_dir(root, p.key), "p")
    vim.fn.writefile({ "mine" }, paths.session_file(root, p.key, "default"))
    migrate.run(root, detect, "default")
    eq({ "mine" }, vim.fn.readfile(paths.session_file(root, p.key, "default")))
    ok(store.exists(root, p.key, "default-legacy"))
  end)

  it("skips a file with no cd line and an undecodable name, and says why", function()
    local root, detect = legacy_world()
    vim.fn.writefile({ "badd +1 a" }, root .. "/%no%such%place.vim")
    local _, skipped = migrate.plan(root, detect, "default")
    eq(1, #skipped)
    ok(skipped[1]:find "cannot tell")
  end)

  it("a missing root is a no-op", function()
    eq({}, (migrate.run("/nonexistent/sessions", project.detect, "default")))
  end)
end)
