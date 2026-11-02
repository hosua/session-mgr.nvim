local F = require "fixture_procs"
local pm = require "session-mgr.ui.procs_model"

local function rows(state)
  return vim.tbl_map(function(r)
    return r.prefix .. (r.has_children and (r.expanded and "[-]" or "[+]") or "") .. r.node.id
  end, pm.visible(state))
end
local function act(state, ...)
  for _, a in ipairs { ... } do
    state = pm.reduce(state, a)
  end
  return state
end
local function new(extra)
  return pm.new(vim.tbl_extend("force", { forest = F.forest() }, extra or {}))
end

describe("procs model", function()
  it("starts collapsed, biggest tree first, orphans last", function()
    eq({ "[+]200", "[+]300", "600", "[+]orphans" }, rows(new()))
  end)
  it("sorts siblings at every level and keeps children under parents", function()
    local s = act(new(), { type = "open_all" })
    eq({
      "[-]200",
      "└─[-]201",
      "  ├─[-]220",
      "  │ └─221",
      "  └─210",
      "[-]300",
      "└─301",
      "600",
      "[-]orphans",
      "└─[-]400",
      "  └─401",
    }, rows(s))
    s = act(s, { type = "set_sort", key = "pid" })
    eq("  ├─210", rows(s)[3])
  end)
  it("toggles a fold under the cursor and closes the parent from a leaf", function()
    local s = act(new(), { type = "toggle_fold" })
    eq({ "[-]200", "└─[+]201" }, vim.list_slice(rows(s), 1, 2))
    s = act(s, { type = "move", delta = 1 }, { type = "close_fold" })
    eq("[+]200", rows(s)[1])
    eq(1, s.cursor)
  end)
  it("keeps folds and the cursor across a refresh", function()
    local s = act(new(), { type = "toggle_fold" }, { type = "move", delta = 1 })
    s = act(s, { type = "set_forest", forest = F.forest() })
    eq("201", pm.current(s).id)
    eq(true, pm.visible(s)[1].expanded)
  end)
  it("cursor follows its process when the sort changes", function()
    local s = act(new(), { type = "move", delta = 1 })
    eq("300", pm.current(s).id)
    s = act(s, { type = "set_sort", key = "pid" }, { type = "reverse" })
    eq("300", pm.current(s).id)
  end)
  it("filter keeps ancestors of a match and opens them", function()
    local s = act(new(), { type = "set_filter", text = "TSSERVER" })
    eq({ "[-]200", "└─[-]201", "  └─[-]220", "    └─221" }, rows(s))
    eq(true, pm.visible(s)[4].matched)
    eq(false, pm.visible(s)[1].matched)
  end)
  it("filter matches the cwd too", function()
    local s = pm.new { forest = F.forest({}, { cwd = { [300] = "/srv/u/dev/bar" } }) }
    eq({ "[-]300", "└─301" }, rows(act(s, { type = "set_filter", text = "dev/bar" })))
  end)
end)

describe("procs model marks and targets", function()
  it("x hits the cursor process only, X its whole tree", function()
    local s = new()
    local _, pids, kb = pm.targets(s, "term")
    eq({ 200 }, pids)
    eq(2964, kb)
    _, pids, kb = pm.targets(s, "kill_tree")
    eq({ 210, 221, 220, 201, 200 }, pids)
    eq(F.forest().by_id["200"].tree, kb)
  end)
  it("space marks and steps down; marks win over the cursor", function()
    local s = act(new(), { type = "toggle_mark" }, { type = "toggle_mark" })
    eq(3, s.cursor)
    local _, pids = pm.targets(s, "term")
    eq({ 200, 300 }, pids)
  end)
  it("drops marks on processes that died", function()
    local s = act(new(), { type = "toggle_mark" })
    local f = F.forest()
    f.by_id["200"] = nil
    s = act(s, { type = "set_forest", forest = f })
    eq({}, s.marks)
  end)
  it("cannot mark the orphans root; acting on it targets its children", function()
    local s = act(new(), { type = "last" }, { type = "toggle_mark" })
    eq({}, s.marks)
    local _, pids = pm.targets(act(s, { type = "last" }), "kill_tree")
    eq({ 401, 400 }, pids)
  end)
  it("does not double count a marked child inside a marked tree", function()
    local s = act(new(), { type = "toggle_fold" }, { type = "toggle_mark" }, { type = "toggle_mark" })
    local _, pids, kb = pm.targets(s, "kill_tree")
    eq(5, #pids)
    eq(F.forest().by_id["200"].tree, kb)
  end)
end)

describe("procs model without data", function()
  it("is empty and safe before the first sample", function()
    local s = act(pm.new {}, { type = "move", delta = 3 }, { type = "toggle_fold" }, { type = "toggle_mark" })
    eq({}, pm.visible(s))
    eq(nil, pm.current(s))
  end)
end)
