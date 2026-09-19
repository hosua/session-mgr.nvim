local F = require "fixture_rows"
local preview = require "session-mgr.ui.preview"
local OPTS = { width = 44, height = 12, home = "/home/me", now = F.NOW }
local row = F.rows_a()[1] -- cool: 42 uses

describe("preview.build", function()
  it("shows project, cwd, layout, times and files", function()
    local info = { cwd = "/home/me/dev/repo-a", tabs = 2, wins = 3, files = { "src/a.lua", "/home/me/notes/todo.md" } }
    local out = preview.build(row, info, OPTS)
    eq(" cool.vim ", out.title)
    eq({
      " project  repo-a",
      " cwd      ~/dev/repo-a",
      " layout   2 tabs, 3 windows",
      " saved    6h ago",
      " loaded   2026-09-11 12:00, 42 times",
      "",
      " 2 files",
      "  src/a.lua",
      "  ~/notes/todo.md",
    }, out.lines)
  end)
  it("uses singular forms and says never", function()
    local r = vim.tbl_extend("force", row, { uses = 0, last_used = vim.NIL })
    r.last_used = nil
    local out = preview.build(r, { cwd = "/x", tabs = 1, wins = 1, files = { "a" } }, OPTS)
    eq(" layout   1 tab, 1 window", out.lines[3])
    eq(" loaded   never", out.lines[5])
    eq(" 1 file", out.lines[7])
  end)
  it("caps the file list to the pane and counts the rest", function()
    local files = {}
    for i = 1, 30 do
      files[i] = ("f%d.lua"):format(i)
    end
    local out = preview.build(row, { cwd = "/x", tabs = 1, wins = 1, files = files }, OPTS)
    eq(12, #out.lines)
    eq("  … and 26 more", out.lines[12])
  end)
  it("shortens long directories from the left and keeps the file name", function()
    local long = "a/very/long/directory/structure/that/does/not/fit/anywhere/file_name.lua"
    local out = preview.build(row, { cwd = "/x", tabs = 1, wins = 1, files = { long } }, OPTS)
    ok(out.lines[8]:find("file_name.lua", 1, true), out.lines[8])
    ok(out.lines[8]:find("…", 1, true), out.lines[8])
    ok(vim.fn.strdisplaywidth(out.lines[8]) <= 44, out.lines[8])
  end)
  it("handles no selection, an unreadable file and an empty workspace", function()
    ok(preview.build(nil, nil, OPTS).lines[1]:find "nothing selected")
    local bad = preview.build(row, nil, vim.tbl_extend("force", OPTS, { err = "cannot read x" }))
    ok(bad.lines[1]:find "cannot read this session")
    ok(preview.build(row, { tabs = 1, wins = 1, files = {} }, OPTS).lines[8]:find "no files")
  end)
end)
