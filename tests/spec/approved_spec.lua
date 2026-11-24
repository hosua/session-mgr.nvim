local approved = require "session-mgr.approved"

describe("approved roots", function()
  it("reads nothing from a missing or broken file", function()
    local root = tmpdir()
    eq({}, approved.read(root))
    vim.fn.writefile({ "{not json" }, approved.file(root))
    eq({}, approved.read(root))
    vim.fn.writefile({ '{"a":1}' }, approved.file(root))
    eq({}, approved.read(root))
  end)

  it("creates the directory, appends, and never duplicates", function()
    local root = tmpdir() .. "/does/not/exist/yet"
    ok(approved.add(root, "/"))
    ok(approved.add(root, "/home/"))
    ok(approved.add(root, "/"))
    eq({ "/", "/home" }, approved.read(root))
    eq(vim.json.encode { "/", "/home" }, table.concat(vim.fn.readfile(approved.file(root)), "\n"))
    eq(true, approved.is_approved("/home", root))
    eq(false, approved.is_approved("/srv", root))
  end)

  it("leaves no temp file behind", function()
    local root = tmpdir()
    ok(approved.add(root, "/"))
    eq({ "approved_roots.json" }, vim.fn.readdir(root))
  end)

  it("remembers a no for this run only, per directory", function()
    approved.reset_declined()
    eq(false, approved.is_declined "/")
    approved.decline "/"
    eq(true, approved.is_declined "/")
    eq(false, approved.is_declined "/home")
    approved.reset_declined()
    eq(false, approved.is_declined "/")
  end)
end)
