local project = require "session-mgr.project"
local OPTS = { git_root = true, git_timeout_ms = 2000, markers = { ".hg", ".session-root" }, fallback = "home" }

--- Run `fn` with $HOME pointing at `home`, then put it back.
local function with_home(home, fn)
  local saved = vim.env.HOME
  vim.env.HOME = home
  project.clear_cache()
  local okk, err = pcall(fn)
  vim.env.HOME = saved
  project.clear_cache()
  assert(okk, err)
end

--- A fake home: <base>/users/me, with <base>/users above it.
local function world()
  local base = vim.uv.fs_realpath(tmpdir())
  vim.fn.mkdir(base .. "/users/me/work/deep", "p")
  vim.fn.mkdir(base .. "/elsewhere/x", "p")
  return base, base .. "/users/me"
end

local function with(overrides)
  return vim.tbl_extend("force", OPTS, overrides)
end

describe("project.from_root", function()
  it("builds key, label and kind", function()
    eq(
      { key = "%home%me%dev%mach", root = "/home/me/dev/mach", label = "mach", is_git = true, kind = "git" },
      project.from_root("/home/me/dev/mach/", true)
    )
    eq("cwd", project.from_root("/x/y", false).kind)
    eq(".hg", project.from_root("/x/y", false, "marker", ".hg").marker)
  end)
end)

describe("project.resolve (pure)", function()
  local home = "/home/me"
  local function ctx(extra)
    return vim.tbl_extend("force", {
      home = home,
      markers = { ".hg", ".session-root" },
      exists = function()
        return false
      end,
      fallback = "home",
      approved = {},
    }, extra or {})
  end

  it("git root wins over everything", function()
    local p = project.resolve("/home/me/a/b", ctx { git_top = "/home/me/a" })
    eq({ "git", "/home/me/a", true }, { p.kind, p.root, p.is_git })
  end)

  it("the nearest marker wins, and is named", function()
    local present = { ["/home/me/a/.hg"] = true, ["/home/me/a/b/.session-root"] = true }
    local p = project.resolve(
      "/home/me/a/b/c",
      ctx {
        exists = function(path)
          return present[path] == true
        end,
      }
    )
    eq({ "marker", "/home/me/a/b", ".session-root" }, { p.kind, p.root, p.marker })
  end)

  it("a marker in a parent of home is never looked at", function()
    local looked = {}
    local p = project.resolve(
      "/home/me/a",
      ctx {
        exists = function(path)
          looked[#looked + 1] = path
          return path == "/home/.hg" or path == "/.hg"
        end,
      }
    )
    eq("home", p.kind)
    for _, path in ipairs(looked) do
      ok(vim.startswith(path, "/home/me"), path)
    end
  end)

  it("falls back to home, or to the cwd", function()
    local p = project.resolve("/srv/data", ctx())
    eq({ "home", "/home/me" }, { p.kind, p.root })
    p = project.resolve("/srv/data", ctx { fallback = "cwd" })
    eq({ "cwd", "/srv/data" }, { p.kind, p.root })
  end)

  it("a parent of home is pending until approved", function()
    for _, dir in ipairs { "/", "/home" } do
      eq("ancestor_pending", project.resolve(dir, ctx()).kind)
      eq("ancestor_pending", project.resolve(dir, ctx { fallback = "cwd" }).kind)
      local p = project.resolve(dir, ctx { approved = { [dir] = true } })
      eq({ "approved", dir }, { p.kind, p.root })
    end
    eq("home", project.resolve("/home/me", ctx()).kind)
  end)

  it("keys stay the escaped root, so existing sessions are found", function()
    eq("%home%me", project.resolve("/srv/x", ctx()).key)
    eq("%home%me%a", project.resolve("/home/me/a/b", ctx { git_top = "/home/me/a" }).key)
  end)
end)

describe("project.describe and why", function()
  local home = "/home/me"
  it("names the scope and the reason", function()
    eq("git root ~/dev/foo", project.describe(project.from_root("/home/me/dev/foo", true), home))
    eq("marker .hg at ~/dev/foo", project.describe(project.from_root("/home/me/dev/foo", false, "marker", ".hg"), home))
    eq("home ~ (no git repo here)", project.describe(project.from_root("/home/me", false, "home"), home))
    eq("directory /srv/x (no git repo here)", project.describe(project.from_root("/srv/x", false, "cwd"), home))
    eq("approved directory /", project.describe(project.from_root("/", false, "approved"), home))
    eq(
      "/home (parent of home, not approved)",
      project.describe(project.from_root("/home", false, "ancestor_pending"), home)
    )
  end)
  it("why is the short reason the startup question shows", function()
    eq("git root", project.why(project.from_root("/a", true)))
    eq("marker .hg", project.why(project.from_root("/a", false, "marker", ".hg")))
    eq("home fallback", project.why(project.from_root("/home/me", false, "home")))
    eq("approved directory", project.why(project.from_root("/", false, "approved")))
  end)
  it("shortens a long path for titles", function()
    local p = project.from_root("/home/me/path/to/a/really/long/nested/place/projectA", true)
    local text = project.describe(p, home, 30)
    ok(text:find("projectA", 1, true) and text:find("…", 1, true), text)
  end)
end)

describe("project.detect", function()
  it("falls back to home outside git", function()
    local base, home = world()
    with_home(home, function()
      local p = project.detect(base .. "/elsewhere/x", OPTS)
      eq({ "home", home, false }, { p.kind, p.root, p.is_git })
    end)
  end)

  it("keeps the cwd with fallback = cwd", function()
    local base, home = world()
    with_home(home, function()
      local p = project.detect(base .. "/elsewhere/x", with { fallback = "cwd" })
      eq({ "cwd", base .. "/elsewhere/x" }, { p.kind, p.root })
    end)
  end)

  it("resolves a subdirectory to the git root", function()
    local base, home = world()
    vim.system({ "git", "init", "-q", home .. "/work" }):wait()
    with_home(home, function()
      local p = project.detect(home .. "/work/deep", OPTS)
      eq({ "git", home .. "/work", true }, { p.kind, p.root, p.is_git })
    end)
    ok(base)
  end)

  it("ignores git when git_root is false", function()
    local _, home = world()
    vim.system({ "git", "init", "-q", home .. "/work" }):wait()
    with_home(home, function()
      eq("home", project.detect(home .. "/work/deep", with { git_root = false }).kind)
    end)
  end)

  it("finds a .session-root marker in a parent directory", function()
    local _, home = world()
    vim.fn.writefile({}, home .. "/work/.session-root")
    with_home(home, function()
      local p = project.detect(home .. "/work/deep", with { git_root = false })
      eq({ "marker", home .. "/work", ".session-root" }, { p.kind, p.root, p.marker })
    end)
  end)

  it("a parent of home is pending, then approved once it is in approved_roots.json", function()
    local base, home = world()
    local sessions = tmpdir()
    require("session-mgr.config").resolve { root = sessions }
    with_home(home, function()
      local p = project.detect(base .. "/users", OPTS)
      eq("ancestor_pending", p.kind)
      ok(require("session-mgr.approved").add(sessions, base .. "/users"))
      eq("approved", project.detect(base .. "/users", OPTS).kind)
    end)
  end)
end)
