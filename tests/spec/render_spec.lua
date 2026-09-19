local F = require "fixture_rows"
local model = require "session-mgr.ui.model"
local render = require "session-mgr.ui.render"
local OPTS = { home = "/home/me" }

local function project_state(extra)
  return model.new(vim.tbl_extend("force", { project = F.project_a, rows = F.rows_a() }, extra or {}))
end
local function all_state(extra)
  return model.new(
    vim.tbl_extend("force", { scope = "all", project = F.project_a, rows = F.rows_all(), height = 30 }, extra or {})
  )
end
local function span_text(out, hl)
  local got = {}
  for _, s in ipairs(out.spans) do
    if s.hl == hl then
      got[#got + 1] = out.lines[s.row + 1]:sub(s.col_start + 1, s.col_end)
    end
  end
  return got
end

describe("render project view", function()
  local out = render.render(project_state { active = { key = "%a", name = "coolio" } }, F.NOW, OPTS)
  it("golden", function()
    eq(
      {
        "  This project   All projects                                5 sessions",
        " / type / to filter by name",
        "    #  Name ▲     Uses  Last used         Updated           Created",
        "▌   1  default     125  5m 57s ago        1h ago            2026-08-10",
        "    2  abc           2  1m ago            2026-09-18 11:00  2026-09-16",
        "    3  cool         42  2026-09-11 12:00  6h ago            2026-08-20",
        "    4  cooli         0  Never             2026-09-05 12:00  2026-09-05",
        "  ● 5  coolio        7  Just now          Just now          2026-09-17",
      },
      vim.tbl_map(function(l)
        return (l:gsub("%s+$", ""))
      end, out.lines)
    )
  end)
  it("no line is wider than the reported width", function()
    for i, l in ipairs(out.lines) do
      ok(vim.fn.strdisplaywidth(l) <= out.width, ("line %d is %d > %d"):format(i, vim.fn.strdisplaywidth(l), out.width))
    end
  end)
  it("titles by project and marks cursor line, default and active", function()
    eq(" Load a session for repo-a ", out.title)
    eq(3, out.cursor_row)
    eq("SessionMgrCursorLine", out.line_hl[3])
    eq({ "default" }, span_text(out, "SessionMgrDefault"))
    eq({ "● " }, span_text(out, "SessionMgrActive"))
    eq({ "Never" }, vim.tbl_map(vim.trim, span_text(out, "SessionMgrNever")))
  end)
  it("spans are byte-accurate despite multibyte glyphs on the line", function()
    eq({ "Name ▲" }, vim.tbl_map(vim.trim, span_text(out, "SessionMgrSortActive")))
    eq({ "1", "2", "3", "4", "5" }, vim.tbl_map(vim.trim, span_text(out, "SessionMgrIndex")))
  end)
end)

describe("render hit regions", function()
  local out = render.render(project_state(), F.NOW, OPTS)
  local function hit_at(line, needle)
    local col = out.lines[line]:find(needle, 1, true)
    return render.hit(out.regions, line, col)
  end
  it("resolves header clicks to sort keys", function()
    eq({ "sort", "uses" }, { hit_at(3, "Uses").kind, hit_at(3, "Uses").id })
    eq("last_used", hit_at(3, "Last used").id)
    eq("created", hit_at(3, "Created").id)
  end)
  it("resolves scope tabs and rows, and nothing in between", function()
    eq({ "scope", "all" }, { hit_at(1, "All projects").kind, hit_at(1, "All projects").id })
    eq("project", hit_at(1, "This project").id)
    eq({ "row", 3 }, { hit_at(6, "cool").kind, hit_at(6, "cool").id })
    eq(nil, render.hit(out.regions, 2, 5))
    eq(nil, render.hit(out.regions, 99, 1))
  end)
  it("covers a row from its first to its last byte", function()
    eq("row", render.hit(out.regions, 4, 1).kind) -- the multibyte cursor bar
    eq("row", render.hit(out.regions, 4, #out.lines[4]).kind)
  end)
end)

describe("render all-projects view", function()
  it("draws group headers with a home-relative path and a non-git note", function()
    local out = render.render(all_state(), F.NOW, OPTS)
    eq(" Showing your saved sessions for all projects ", out.title)
    -- Lua patterns are byte-based, so "─+" would not mean what it says.
    ok(vim.startswith(out.lines[4], " Notes  ~/dev/Notes  (folder, not a git repo) ───"), out.lines[4])
    ok(vim.startswith(out.lines[6], " repo-a  ~/dev/repo-a ───"), out.lines[6])
    ok(vim.endswith(out.lines[6], "─"), out.lines[6])
    eq("SessionMgrGroupLine", out.line_hl[3])
  end)
  it("flattened filter view shows the project and highlights matched characters", function()
    local out = render.render(model.reduce(all_state(), { type = "set_filter", text = "coo" }), F.NOW, OPTS)
    ok(out.lines[1]:find "5 of 8$", out.lines[1])
    ok(out.lines[2]:find "^ / coo", out.lines[2])
    ok(out.lines[4]:find "cool  repo%-a", out.lines[4])
    eq(15, #span_text(out, "SessionMgrMatch")) -- 3 characters x 5 rows
    eq({ "c", "o", "o" }, vim.list_slice(span_text(out, "SessionMgrMatch"), 1, 3))
  end)
  it("renders only the visible window and keeps the chrome fixed", function()
    local s = model.reduce(all_state { height = 4 }, { type = "last" })
    local out = render.render(s, F.NOW, OPTS)
    eq(render.CHROME_LINES + 4, #out.lines)
    ok(out.lines[3]:find "Name", "header must stay on line 3")
    ok(out.lines[#out.lines]:find "cooli", out.lines[#out.lines])
    eq(11, out.list_lines)
  end)
  it("column widths do not change while scrolling", function()
    local s = all_state { height = 3 }
    local a = render.render(s, F.NOW, OPTS).width
    eq(a, render.render(model.reduce(s, { type = "last" }), F.NOW, OPTS).width)
  end)
end)

describe("render edge cases", function()
  it("explains an empty project and an empty filter result", function()
    local empty = render.render(model.new { project = F.project_a, rows = {} }, F.NOW, OPTS)
    ok(empty.lines[4]:find "No sessions yet for repo%-a", empty.lines[4])
    ok(empty.lines[5]:find ":SessionMgr save", empty.lines[5])
    local none = render.render(model.reduce(project_state(), { type = "set_filter", text = "zzz" }), F.NOW, OPTS)
    ok(none.lines[4]:find 'No session name matches "zzz"', none.lines[4])
  end)
  it("truncates very long names and keeps the table aligned", function()
    local rows = F.rows_a()
    rows[1].name = ("x"):rep(80)
    local out = render.render(model.new { project = F.project_a, rows = rows }, F.NOW, OPTS)
    ok(out.lines[#out.lines]:find "x…", out.lines[#out.lines])
    for _, l in ipairs(out.lines) do
      ok(vim.fn.strdisplaywidth(l) <= out.width)
    end
  end)
  it("non-git project: path in the title and a scoping warning in the footer", function()
    local p =
      { key = "%n", root = "/home/me/path/to/a/really/long/nested/place/projectA", label = "projectA", is_git = false }
    local out = render.render(model.new { project = p, rows = {} }, F.NOW, OPTS)
    ok(out.title:find("…/projectA", 1, true), out.title)
    eq(2, out.chrome_bottom)
    ok(out.lines[#out.lines]:find "not a git repo", out.lines[#out.lines])
    eq(0, render.render(project_state(), F.NOW, OPTS).chrome_bottom)
  end)
  it("is never narrower than its own footer", function()
    local out = render.render(model.new { project = F.project_a, rows = {} }, F.NOW, OPTS)
    local w = 2
    for _, c in ipairs(out.footer) do
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    ok(out.width >= w, ("width %d < footer %d"):format(out.width, w))
  end)
  it("footer switches to filter keys while the filter has focus", function()
    local out = render.render(model.reduce(project_state(), { type = "focus_filter", focused = true }), F.NOW, OPTS)
    eq("esc", out.footer[4][1])
    ok(out.lines[2]:find "█", out.lines[2])
  end)
end)
