local project = require "session-mgr.project"
local OPTS = { git_root = true, git_timeout_ms = 2000 }

describe("project", function()
  it("from_root builds key and label", function()
    eq(
      { key = "%home%me%dev%mach", root = "/home/me/dev/mach", label = "mach", is_git = true },
      project.from_root("/home/me/dev/mach/", true)
    )
  end)

  it("uses the cwd outside git", function()
    project.clear_cache()
    local dir = vim.uv.fs_realpath(tmpdir())
    local p = project.detect(dir, OPTS)
    eq(dir, p.root)
    eq(false, p.is_git)
  end)

  it("resolves a subdirectory to the git root", function()
    project.clear_cache()
    local dir = vim.uv.fs_realpath(tmpdir())
    vim.system({ "git", "init", "-q", dir }):wait()
    vim.fn.mkdir(dir .. "/a/b", "p")
    local p = project.detect(dir .. "/a/b", OPTS)
    eq(dir, p.root)
    eq(true, p.is_git)
  end)

  it("ignores git when git_root is false", function()
    project.clear_cache()
    local dir = vim.uv.fs_realpath(tmpdir())
    vim.system({ "git", "init", "-q", dir }):wait()
    vim.fn.mkdir(dir .. "/sub", "p")
    eq(dir .. "/sub", project.detect(dir .. "/sub", { git_root = false, git_timeout_ms = 100 }).root)
  end)
end)
