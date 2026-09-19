local store = require "session-mgr.store"
local paths = require "session-mgr.paths"
local project = require "session-mgr.project"

local function setup()
  local root = tmpdir()
  local p = project.from_root("/home/me/dev/mach", true)
  vim.fn.mkdir(paths.project_dir(root, p.key), "p")
  return root, p
end

local function touch(root, p, name, body)
  vim.fn.writefile(body or { "cd /home/me/dev/mach" }, paths.session_file(root, p.key, name))
end

local function by_name(rows)
  local out = {}
  for _, r in ipairs(rows) do
    out[r.name] = r
  end
  return out
end

describe("store", function()
  it("records a save, then loads, with the right timestamps", function()
    local root, p = setup()
    touch(root, p, "work")
    ok(store.touch_saved(root, p, "work", 1000))
    ok(store.touch_loaded(root, p, "work", 2000))
    ok(store.touch_loaded(root, p, "work", 3000))
    ok(store.touch_saved(root, p, "work", 4000))
    local r = by_name(store.list(root, p)).work
    eq({ 2, 1000, 4000, 3000 }, { r.uses, r.created, r.updated, r.last_used })
    eq({ "mach", "/home/me/dev/mach", true }, { r.label, r.root, r.is_git })
  end)

  it("leaves last_used nil until the first load", function()
    local root, p = setup()
    touch(root, p, "fresh")
    store.touch_saved(root, p, "fresh", 1000)
    eq(nil, by_name(store.list(root, p)).fresh.last_used)
  end)

  it("adopts a file that has no record, from its mtime", function()
    local root, p = setup()
    touch(root, p, "orphan")
    local r = by_name(store.list(root, p)).orphan
    eq(0, r.uses)
    ok(r.updated > 0 and r.created == r.updated)
  end)

  it("drops a record whose file is gone", function()
    local root, p = setup()
    touch(root, p, "gone")
    store.touch_saved(root, p, "gone", 1000)
    vim.uv.fs_unlink(paths.session_file(root, p.key, "gone"))
    eq({}, store.list(root, p))
  end)

  it("moves a corrupt index aside and rebuilds from the files", function()
    local root, p = setup()
    touch(root, p, "work")
    vim.fn.writefile({ "{ not json" }, paths.index_file(root, p.key))
    local _, warning = store.read(root, p.key, p, 5000)
    ok(warning and warning:find "corrupt", "expected a warning")
    ok(vim.uv.fs_stat(paths.index_file(root, p.key) .. ".corrupt-5000"), "corrupt file must be kept")
    ok(by_name(store.list(root, p)).work)
  end)

  it("refuses to write an index from a newer version", function()
    local root, p = setup()
    touch(root, p, "work")
    vim.fn.writefile(
      { vim.json.encode { version = 99, sessions = { work = { uses = 7 } } } },
      paths.index_file(root, p.key)
    )
    local ok_, err = store.touch_saved(root, p, "work", 1000)
    eq(false, ok_)
    ok(err:find "newer")
    eq(7, by_name(store.list(root, p)).work.uses)
  end)

  it("rename carries the metrics and refuses to clobber", function()
    local root, p = setup()
    touch(root, p, "a")
    touch(root, p, "b")
    store.touch_saved(root, p, "a", 1000)
    store.touch_loaded(root, p, "a", 2000)
    eq(false, (store.rename(root, p, "a", "b")))
    eq(false, (store.rename(root, p, "missing", "c")))
    ok(store.rename(root, p, "a", "c"))
    local rows = by_name(store.list(root, p))
    eq(nil, rows.a)
    eq({ 1, 1000, 2000 }, { rows.c.uses, rows.c.created, rows.c.last_used })
  end)

  it("remove deletes the file and the record", function()
    local root, p = setup()
    touch(root, p, "a")
    store.touch_saved(root, p, "a", 1000)
    ok(store.remove(root, p, "a"))
    eq(false, store.exists(root, p.key, "a"))
    eq({}, store.list(root, p))
    eq(false, (store.remove(root, p, "a")))
  end)

  it("keeps an emptied index readable (sessions stays an object)", function()
    local root, p = setup()
    touch(root, p, "a")
    store.touch_saved(root, p, "a", 1000)
    store.remove(root, p, "a")
    touch(root, p, "b")
    ok(store.touch_saved(root, p, "b", 2000))
    eq(2000, by_name(store.list(root, p)).b.updated)
  end)

  it("interleaved writers both land", function()
    local root, p = setup()
    touch(root, p, "a")
    touch(root, p, "b")
    store.touch_saved(root, p, "a", 1000)
    store.touch_saved(root, p, "b", 1001) -- a second instance, after re-reading
    local rows = by_name(store.list(root, p))
    ok(rows.a and rows.b)
    eq(1000, rows.a.updated)
  end)

  it("list_all spans projects and recovers the root of an index-less project", function()
    local root, p = setup()
    touch(root, p, "work")
    store.touch_saved(root, p, "work", 1000)
    local q = project.from_root("/srv/other", false)
    vim.fn.mkdir(paths.project_dir(root, q.key), "p")
    vim.fn.writefile({ "cd /srv/other" }, paths.session_file(root, q.key, "default"))
    vim.fn.writefile({ "legacy" }, root .. "/%legacy%file.vim") -- top-level files are not projects
    local rows = store.list_all(root)
    eq(2, #rows)
    local other = vim.tbl_filter(function(r)
      return r.name == "default"
    end, rows)[1]
    eq({ "/srv/other", "other" }, { other.root, other.label })
  end)

  it("list_all on a missing root is empty, not an error", function()
    eq({}, store.list_all "/nonexistent/sessions")
  end)
end)
