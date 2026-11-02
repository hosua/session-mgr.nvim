local F = require "fixture_procs"
local pm = require "session-mgr.ui.procs_model"
local pr = require "session-mgr.ui.procs_render"
local preview = require "session-mgr.ui.procs_preview"
local render = require "session-mgr.ui.render"

local function trimmed(out)
  return vim.tbl_map(function(l)
    return (l:gsub("%s+$", ""))
  end, out.lines)
end

describe("procs render", function()
  local forest = F.forest({ own_pid = 301 }, { cwd = { [200] = "/srv/u/dev/foo" } })
  local state = pm.reduce(pm.new { forest = forest }, { type = "toggle_fold" })
  local out = pr.render(state, { home = "/srv/u", big_kb = 1024 * 1024 })

  it("golden", function()
    eq({
      "  This project   All projects   Processes              10 procs  11G",
      " / type / to filter by command or cwd",
      "      PID  Tree ▼    RSS    Thr    CPU%  Command",
      "▌     200     11G   2.9M      1       …  [-]nvim  ~/dev/foo",
      "      201     11G   9.4G      5       …  └─[+]nvim --embed",
      "  ●   300    366M   2.9M      1       …  [+]nvim run.js",
      "      600     39M    39M      1       …  nvim --headless --embed",
      "              63M                        [+]orphaned LSPs",
    }, vim.list_slice(trimmed(out), 1, 8))
  end)
  it("draws big trees as a warning", function()
    local hit = vim.tbl_filter(function(s)
      return s.row == 3 and s.hl == "SessionMgrProcBig"
    end, out.spans)
    eq(1, #hit)
  end)
  it("has clickable tabs, sort headers, rows and fold boxes", function()
    eq("procs", render.hit(out.regions, 1, 35).id)
    eq("tree", render.hit(out.regions, 3, 15).id)
    local box = render.hit(out.regions, 4, out.lines[4]:find("[-]", 1, true))
    eq("fold", box.kind)
    eq(1, box.id)
    eq("row", render.hit(out.regions, 5, 3).kind)
  end)
  it("parks the cursor row and keeps the footer inside the width", function()
    eq(3, out.cursor_row)
    local fw = 2
    for _, c in ipairs(out.footer) do
      fw = fw + vim.fn.strdisplaywidth(c[1])
    end
    ok(out.width >= fw)
  end)
  it("truncates the command to max_width", function()
    local open = pm.reduce(state, { type = "open_all" })
    ok(pr.render(open).width > 75)
    local narrow = pr.render(open, { max_width = 75 })
    eq(75, narrow.width)
    for _, l in ipairs(narrow.lines) do
      ok(vim.fn.strdisplaywidth(l) <= 75, l)
    end
    ok(table.concat(narrow.lines, "\n"):find("…", 1, true))
  end)
  it("says why the list is empty", function()
    eq("  reading processes…", trimmed(pr.render(pm.new {}))[4])
    eq(
      "  the Processes tab needs /proc (Linux)",
      trimmed(pr.render(pm.new { error = "the Processes tab needs /proc (Linux)" }))[4]
    )
    local none = pm.reduce(pm.new { forest = forest }, { type = "set_filter", text = "zzz" })
    eq('  No process matches "zzz"', trimmed(pr.render(none))[4])
  end)
  it("counts marks on the filter line", function()
    local marked = pm.reduce(state, { type = "toggle_mark" })
    ok(trimmed(pr.render(marked))[2]:find "1 marked", trimmed(pr.render(marked))[2])
  end)
end)

describe("procs preview", function()
  local forest = F.forest({ own_pid = 201 }, { cwd = { [200] = "/srv/u/dev/foo" }, swap = { [201] = 2048 } })
  it("shows the process and what x / X would hit", function()
    local out = preview.build(forest.by_id["201"], { width = 50, height = 30, home = "/srv/u", memory = "rss" })
    eq(" 201 nvim ", out.title)
    local text = table.concat(out.lines, "\n")
    ok(text:find "parent 200", text)
    ok(text:find "swap +2.0M", text)
    ok(text:find "this nvim lives in this tree", text)
    ok(text:find "x SIGTERM to 201 only", text)
    ok(text:find "X SIGKILL to 4 processes", text)
  end)
  it("explains the orphans root and never offers x on it", function()
    local out = preview.build(forest.by_id.orphans, { width = 50, height = 30, memory = "rss" })
    local text = table.concat(out.lines, "\n")
    ok(text:find "whose nvim is gone", text)
    ok(not text:find "SIGTERM", text)
  end)
  it("never grows taller than the pane and keeps the key lines", function()
    local out = preview.build(forest.by_id["201"], { width = 50, height = 8, memory = "pss" })
    eq(8, #out.lines)
    ok(out.lines[8]:find "SIGKILL", out.lines[8])
  end)
end)
