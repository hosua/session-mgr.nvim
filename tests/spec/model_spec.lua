local F = require "fixture_rows"
local model = require "session-mgr.ui.model"

local function names(state)
  local out = {}
  for _, it in ipairs((model.visible(state))) do
    out[#out + 1] = it.kind == "group" and ("[" .. it.label .. "]") or (it.index .. ":" .. it.row.name)
  end
  return out
end
local function project_state(extra)
  return model.new(vim.tbl_extend("force", { project = F.project_a, rows = F.rows_a() }, extra or {}))
end
local function all_state(extra)
  return model.new(vim.tbl_extend("force", { scope = "all", project = F.project_a, rows = F.rows_all() }, extra or {}))
end
local function act(state, ...)
  for _, a in ipairs { ... } do
    state = model.reduce(state, a)
  end
  return state
end

describe("model ordering", function()
  it("defaults to A-Z with `default` pinned first", function()
    eq({ "1:default", "2:abc", "3:cool", "4:cooli", "5:coolio" }, names(project_state()))
  end)
  it("keeps `default` pinned under every sort and direction", function()
    for _, key in ipairs(model.SORT_KEYS) do
      local s = act(project_state(), { type = "set_sort", key = key })
      eq("1:default", names(s)[1], key)
      eq("1:default", names(act(s, { type = "reverse" }))[1], key .. " reversed")
    end
  end)
  it("sorts counts and dates descending first, names ascending first", function()
    eq(
      { "1:default", "2:cool", "3:coolio", "4:abc", "5:cooli" },
      names(act(project_state(), { type = "set_sort", key = "uses" }))
    )
    eq("desc", act(project_state(), { type = "set_sort", key = "updated" }).sort.dir)
  end)
  it("toggles direction when the same column is chosen again", function()
    local s = act(project_state(), { type = "set_sort", key = "name" })
    eq("desc", s.sort.dir)
    eq({ "1:default", "2:coolio", "3:cooli", "4:cool", "5:abc" }, names(s))
  end)
  it("puts never-used last in both directions", function()
    local s = act(project_state(), { type = "set_sort", key = "last_used" })
    eq("5:cooli", names(s)[5])
    eq("5:cooli", names(act(s, { type = "reverse" }))[5])
  end)
  it("cycles sort columns both ways, wrapping", function()
    eq("uses", act(project_state(), { type = "cycle_sort", delta = 1 }).sort.key)
    eq("created", act(project_state(), { type = "cycle_sort", delta = -1 }).sort.key)
  end)
  it("does not mutate the state it was given", function()
    local s = project_state()
    local copy = vim.deepcopy(s)
    act(s, { type = "set_sort", key = "uses" }, { type = "move", delta = 2 }, { type = "set_filter", text = "c" })
    eq(copy, s)
  end)
end)

describe("model grouping", function()
  it("groups by project A-Z (case-insensitive), numbering per group, default first in each", function()
    eq({
      "[Notes]",
      "1:default",
      "[repo-a]",
      "1:default",
      "2:abc",
      "3:cool",
      "4:cooli",
      "5:coolio",
      "[repo-b]",
      "1:cool",
      "2:cooli",
    }, names(all_state()))
  end)
  it("sorts within groups and leaves the group order alone", function()
    local got = names(act(all_state(), { type = "set_sort", key = "uses" }))
    eq({ "[repo-b]", "1:cool", "2:cooli" }, vim.list_slice(got, 9, 11))
    eq("[Notes]", got[1])
  end)
  it("flattens under a filter, tags rows with their project, allows duplicate names", function()
    local s = act(all_state(), { type = "set_filter", text = "coo" })
    eq({ "1:cool", "2:cool", "3:cooli", "4:cooli", "5:coolio" }, names(s))
    local items, count, total = model.visible(s)
    eq({ 5, 8 }, { count, total })
    eq(true, items[1].show_project)
    eq({ "repo-a", "repo-b" }, { items[1].row.label, items[2].row.label })
    eq({ 1, 2, 3 }, items[1].positions)
  end)
  it("a filter narrows but the chosen sort still orders", function()
    local s = act(all_state(), { type = "set_sort", key = "uses" }, { type = "set_filter", text = "coo" })
    eq("5:cooli", names(s)[5]) -- 0 uses last, although it is a better fuzzy match than coolio
  end)
  it("groups never count as selectable", function()
    local items, count = model.visible(all_state())
    eq(8, count)
    eq(nil, items[1].selectable)
    eq(1, items[2].selectable)
  end)
end)

describe("model cursor and scrolling", function()
  it("clamps at both ends", function()
    eq(1, act(project_state(), { type = "move", delta = -5 }).cursor)
    eq(5, act(project_state(), { type = "move", delta = 99 }).cursor)
    eq(5, act(project_state(), { type = "last" }).cursor)
    eq(1, act(project_state(), { type = "last" }, { type = "first" }).cursor)
    eq(3, act(project_state(), { type = "goto", index = 3 }).cursor)
  end)
  it("pages by height-1 and half-pages by height/2", function()
    local s = all_state { height = 4 }
    eq(4, act(s, { type = "page", delta = 1 }).cursor)
    eq(3, act(s, { type = "half_page", delta = 1 }).cursor)
  end)
  it("scrolls just enough to keep the cursor visible", function()
    local s = act(all_state { height = 4 }, { type = "last" })
    eq(8, s.cursor)
    eq(8, s.scroll_top) -- 11 items, 4 lines: items 8..11
    s = act(s, { type = "first" })
    eq(1, s.scroll_top) -- shows the group header above the first row too
  end)
  it("keeps a group header on screen with its first row when moving up", function()
    local s = act(all_state { height = 3 }, { type = "last" }, { type = "goto", index = 7 })
    eq(9, s.scroll_top) -- item 9 is [repo-b], item 10 is its first row
  end)
  it("wheel scrolling moves the view and drags the cursor into it", function()
    local s = act(all_state { height = 4 }, { type = "scroll", delta = 3 })
    eq(4, s.scroll_top)
    eq(2, s.cursor) -- first selectable in items 4..7 is repo-a/abc? no: item 4 = 1:default of repo-a
  end)
  it("wheel scrolling cannot run past the end", function()
    eq(8, act(all_state { height = 4 }, { type = "scroll", delta = 99 }).scroll_top)
    eq(1, act(project_state(), { type = "scroll", delta = 99 }).scroll_top)
  end)
  it("follows the same session across re-sorts and filters", function()
    local s = act(project_state(), { type = "goto", index = 3 }) -- cool
    eq("cool", model.current(s).name)
    s = act(s, { type = "set_sort", key = "uses" })
    eq("cool", model.current(s).name)
    s = act(s, { type = "set_filter", text = "coo" })
    eq("cool", model.current(s).name)
    eq("default", model.current(act(s, { type = "set_filter", text = "def" })).name)
  end)
  it("resets to the top when the scope changes", function()
    local s = act(project_state(), { type = "last" }, { type = "set_rows", rows = F.rows_all(), scope = "all" })
    eq({ "all", 1, 1 }, { s.scope, s.cursor, s.scroll_top })
  end)
  it("survives an empty list", function()
    local s = act(model.new { project = F.project_a, rows = {} }, { type = "move", delta = 1 }, { type = "last" })
    eq(1, s.cursor)
    eq(nil, model.current(s))
  end)
  it("resize keeps the cursor visible", function()
    local s = act(all_state { height = 20 }, { type = "last" }, { type = "resize", height = 2 })
    eq(10, s.scroll_top)
  end)
end)
