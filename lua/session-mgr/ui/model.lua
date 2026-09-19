--- Picker view model. Pure: `reduce(state, action)` returns a NEW state and
--- `visible(state)` derives what is on the list. No windows, no clock, no
--- disk, so sorting, grouping, pinning, filtering, paging and scrolling are
--- all plain table tests.
---
--- Vocabulary: an *item* is a line of the list (a group header or a session
--- row); a *selectable* is a session row. `cursor` counts selectables,
--- `scroll_top` counts items.
local fuzzy = require "session-mgr.fuzzy"

local M = {}

M.SORT_KEYS = { "name", "uses", "last_used", "updated", "created" }
--- Names read best A-Z; counts and dates are interesting from the top.
local NATURAL_DIR = { name = "asc", uses = "desc", last_used = "desc", updated = "desc", created = "desc" }

--- @class SessionMgrPickerState
--- @field scope "project"|"all"
--- @field project SessionMgrProject
--- @field rows SessionMgrRow[] rows for the current scope
--- @field sort { key: string, dir: "asc"|"desc" }
--- @field filter string
--- @field filter_focused boolean
--- @field cursor integer 1-based index into the selectable rows
--- @field scroll_top integer 1-based index into the items
--- @field height integer visible list lines
--- @field default_name string
--- @field active { key: string, name: string }|nil

--- @return SessionMgrPickerState
function M.new(opts)
  return M.reduce({
    scope = opts.scope or "project",
    project = opts.project,
    rows = opts.rows or {},
    sort = vim.deepcopy(opts.sort or { key = "name", dir = "asc" }),
    filter = "",
    filter_focused = false,
    cursor = 1,
    scroll_top = 1,
    height = opts.height or 20,
    default_name = opts.default_name or "default",
    active = opts.active,
  }, { type = "noop" })
end

local function comparator(sort, default_name, pin_default)
  local key, asc = sort.key, sort.dir == "asc"
  return function(a, b)
    if pin_default and (a.name == default_name) ~= (b.name == default_name) then
      return a.name == default_name
    end
    if key ~= "name" then
      local x, y = a[key], b[key]
      if x ~= y then
        if x == nil or y == nil then
          return y == nil -- "never" sorts last in both directions
        end
        if asc then
          return x < y
        end
        return x > y
      end
    end
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then
      if key == "name" and not asc then
        return x > y
      end
      return x < y
    end
    return a.key < b.key
  end
end

--- @class SessionMgrItem
--- @field kind "group"|"row"
--- @field row SessionMgrRow|nil
--- @field index integer|nil number shown in the # column (continuous across groups)
--- @field selectable integer|nil position among the selectable rows
--- @field positions integer[]|nil matched byte positions in the name
--- @field show_project boolean|nil flat all-projects list: print the project after the name
--- @field label string|nil group: project label
--- @field root string|nil group: project root
--- @field is_git boolean|nil group

--- @param state SessionMgrPickerState
--- @return SessionMgrItem[] items, integer selectable_count, integer total_rows
function M.visible(state)
  local matched = {}
  for _, row in ipairs(state.rows) do
    local positions = fuzzy.match(state.filter, row.name)
    if positions then
      matched[#matched + 1] = { row = row, positions = positions }
    end
  end

  local items, n = {}, 0
  local function push_rows(list, show_project)
    for _, m in ipairs(list) do
      n = n + 1
      -- Numbering runs on across groups, so # is always a valid {count}G target.
      items[#items + 1] =
        { kind = "row", row = m.row, index = n, selectable = n, positions = m.positions, show_project = show_project }
    end
  end
  local function sorted(list, pin)
    local cmp = comparator(state.sort, state.default_name, pin)
    table.sort(list, function(a, b)
      return cmp(a.row, b.row)
    end)
    return list
  end

  if state.scope == "all" and state.filter == "" then
    local groups, order = {}, {}
    for _, m in ipairs(matched) do
      if not groups[m.row.key] then
        groups[m.row.key] =
          { label = m.row.label, root = m.row.root, is_git = m.row.is_git, key = m.row.key, list = {} }
        order[#order + 1] = groups[m.row.key]
      end
      table.insert(groups[m.row.key].list, m)
    end
    table.sort(order, function(a, b)
      local x, y = a.label:lower(), b.label:lower()
      if x ~= y then
        return x < y
      end
      return a.key < b.key
    end)
    for _, g in ipairs(order) do
      items[#items + 1] = { kind = "group", label = g.label, root = g.root, is_git = g.is_git }
      push_rows(sorted(g.list, true), false)
    end
  else
    -- One project, or a filtered all-projects list (flattened: a filter is a
    -- search for a name, and group headers would only get in the way).
    push_rows(sorted(matched, state.scope == "project"), state.scope == "all")
  end
  return items, n, #state.rows
end

local function item_of_cursor(items, cursor)
  for i, it in ipairs(items) do
    if it.selectable == cursor then
      return i, it
    end
  end
end

--- The session under the cursor.
--- @return SessionMgrRow|nil
function M.current(state)
  local _, it = item_of_cursor((M.visible(state)), state.cursor)
  return it and it.row or nil
end

--- Clamp the cursor and scroll just enough to keep it on screen. A group
--- header directly above the first row of a group is kept visible with it.
local function settle(state, items, count)
  state.cursor = math.max(1, math.min(state.cursor, math.max(count, 1)))
  local max_top = math.max(1, #items - state.height + 1)
  local at = item_of_cursor(items, state.cursor)
  if at then
    local top_needed = (items[at - 1] and items[at - 1].kind == "group") and at - 1 or at
    if top_needed < state.scroll_top then
      state.scroll_top = top_needed
    elseif at > state.scroll_top + state.height - 1 then
      state.scroll_top = at - state.height + 1
    end
  end
  state.scroll_top = math.max(1, math.min(state.scroll_top, max_top))
  return state
end

--- Keep the cursor on the same session across a re-sort or re-filter.
local function follow(state, before)
  if before then
    for _, it in ipairs((M.visible(state))) do
      if it.kind == "row" and it.row.key == before.key and it.row.name == before.name then
        state.cursor = it.selectable
        return
      end
    end
  end
  state.cursor = 1
end

--- @param state SessionMgrPickerState
--- @param action table { type = ..., ... }
--- @return SessionMgrPickerState
function M.reduce(state, action)
  local s = vim.deepcopy(state)
  local t = action.type
  local before = (t == "set_sort" or t == "cycle_sort" or t == "reverse" or t == "set_filter" or t == "set_rows")
      and M.current(state)
    or nil

  if t == "move" then
    s.cursor = s.cursor + action.delta
  elseif t == "page" then
    s.cursor = s.cursor + action.delta * math.max(1, s.height - 1)
  elseif t == "half_page" then
    s.cursor = s.cursor + action.delta * math.max(1, math.floor(s.height / 2))
  elseif t == "first" then
    s.cursor = 1
  elseif t == "last" then
    s.cursor = math.huge
  elseif t == "goto" then
    s.cursor = action.index
  elseif t == "scroll" then
    -- Mouse wheel: move the view, then pull the cursor back inside it.
    local items, count = M.visible(s)
    s.scroll_top = math.max(1, math.min(s.scroll_top + action.delta, math.max(1, #items - s.height + 1)))
    local first, last
    for i = s.scroll_top, math.min(#items, s.scroll_top + s.height - 1) do
      if items[i].selectable then
        first, last = first or items[i].selectable, items[i].selectable
      end
    end
    if first then
      s.cursor = math.max(first, math.min(s.cursor, last))
    end
    s.cursor = math.max(1, math.min(s.cursor, math.max(count, 1)))
    return s
  elseif t == "set_sort" then
    if s.sort.key == action.key then
      s.sort.dir = s.sort.dir == "asc" and "desc" or "asc"
    else
      s.sort = { key = action.key, dir = NATURAL_DIR[action.key] }
    end
  elseif t == "cycle_sort" then
    local at = 1
    for i, k in ipairs(M.SORT_KEYS) do
      if k == s.sort.key then
        at = i
      end
    end
    local key = M.SORT_KEYS[(at - 1 + action.delta) % #M.SORT_KEYS + 1]
    s.sort = { key = key, dir = NATURAL_DIR[key] }
  elseif t == "reverse" then
    s.sort.dir = s.sort.dir == "asc" and "desc" or "asc"
  elseif t == "set_filter" then
    s.filter = action.text
  elseif t == "focus_filter" then
    s.filter_focused = action.focused
  elseif t == "set_rows" then
    s.rows = action.rows
    s.scope = action.scope or s.scope
    if action.scope and action.scope ~= state.scope then
      before, s.scroll_top = nil, 1
    end
  elseif t == "set_active" then
    s.active = action.active
  elseif t == "resize" then
    s.height = math.max(1, action.height)
  end

  if before or t == "set_filter" or t == "set_rows" then
    follow(s, before)
  end
  local items, count = M.visible(s)
  return settle(s, items, count)
end

return M
