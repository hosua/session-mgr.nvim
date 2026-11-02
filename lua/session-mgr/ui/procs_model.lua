--- Processes tab view model. Pure, like ui/model.lua: `reduce(state, action)`
--- returns a NEW state and `visible(state)` flattens the forest into the rows
--- on screen. Every row is selectable, so `cursor` and `scroll_top` both
--- count rows.
---
--- Folds and marks are keyed by node id (the pid as a string), so they
--- survive a refresh that rebuilds every node table.
local tree = require "session-mgr.procs.tree"

local M = {}

M.SORT_KEYS = { "pid", "tree", "own", "threads", "cpu", "command" }
--- Sizes and load are interesting from the top; pids and names read upward.
local NATURAL_DIR = { pid = "asc", tree = "desc", own = "desc", threads = "desc", cpu = "desc", command = "asc" }

--- @class SessionMgrProcsState
--- @field forest table result of procs.tree.build, or nil before the first sample
--- @field error string|nil why there is no forest (no /proc, ps failed)
--- @field sort { key: string, dir: "asc"|"desc" }
--- @field expanded table<string, boolean>
--- @field marks table<string, boolean>
--- @field filter string
--- @field filter_focused boolean
--- @field cursor integer
--- @field scroll_top integer
--- @field height integer

--- @return SessionMgrProcsState
function M.new(opts)
  opts = opts or {}
  return M.reduce({
    forest = opts.forest,
    error = opts.error,
    sort = vim.deepcopy(opts.sort or { key = "tree", dir = "desc" }),
    expanded = {},
    marks = {},
    filter = "",
    filter_focused = false,
    cursor = 1,
    scroll_top = 1,
    height = opts.height or 20,
  }, { type = "noop" })
end

local function value(node, key)
  if key == "pid" then
    return node.pid
  elseif key == "threads" then
    return node.proc and node.proc.threads
  elseif key == "command" then
    return (node.proc and node.proc.args or node.label or ""):lower()
  end
  return node[key] -- tree, own, cpu
end

local function comparator(sort)
  local key, asc = sort.key, sort.dir == "asc"
  return function(a, b)
    -- The synthetic orphans root always sits at the bottom.
    if (a.pid == nil) ~= (b.pid == nil) then
      return b.pid == nil
    end
    local x, y = value(a, key), value(b, key)
    if x ~= y then
      if x == nil or y == nil then
        return y == nil -- unknown (first CPU sample) sorts last both ways
      end
      if asc then
        return x < y
      end
      return x > y
    end
    return (a.pid or 0) < (b.pid or 0)
  end
end

local function matches(node, needle)
  if needle == "" then
    return true
  end
  local hay = (node.proc and node.proc.args or node.label or "") .. "\n" .. (node.cwd or "")
  return hay:lower():find(needle, 1, true) ~= nil
end

--- @class SessionMgrProcRow
--- @field node SessionMgrProcNode
--- @field index integer
--- @field depth integer
--- @field prefix string tree glyphs drawn before the fold box
--- @field has_children boolean
--- @field expanded boolean
--- @field matched boolean the filter hit this row itself, not only a descendant

--- @param state SessionMgrProcsState
--- @return SessionMgrProcRow[]
function M.visible(state)
  local rows = {}
  if not state.forest then
    return rows
  end
  local needle = state.filter:lower()
  local cmp = comparator(state.sort)

  -- With a filter: which nodes are on a path to a match?
  -- A hit keeps its whole subtree too: filtering by an nvim's cwd should
  -- show that nvim's servers, not an expanded node with nothing under it.
  local keep = {}
  local function mark_keep(node, inside_hit)
    local hit = matches(node, needle)
    local any = hit or inside_hit
    for _, c in ipairs(node.children) do
      any = mark_keep(c, hit or inside_hit) or any
    end
    keep[node] = any
    return any
  end
  if needle ~= "" then
    for _, r in ipairs(state.forest.roots) do
      mark_keep(r)
    end
  end

  local function walk(nodes, guides)
    local list = {}
    for _, n in ipairs(nodes) do
      if needle == "" or keep[n] then
        list[#list + 1] = n
      end
    end
    table.sort(list, cmp)
    for i, n in ipairs(list) do
      local last = i == #list
      local depth = #guides
      local prefix = ""
      if depth > 0 then
        prefix = table.concat(guides, "", 2) .. (last and "└─" or "├─")
      end
      -- A filter opens every branch that leads to a hit.
      local open = state.expanded[n.id] or (needle ~= "" and #n.children > 0)
      rows[#rows + 1] = {
        node = n,
        index = #rows + 1,
        depth = depth,
        prefix = prefix,
        has_children = #n.children > 0,
        expanded = open and #n.children > 0 or false,
        matched = needle ~= "" and matches(n, needle),
      }
      if open then
        local next_guides = vim.list_extend(vim.deepcopy(guides), { last and "  " or "│ " })
        walk(n.children, next_guides)
      end
    end
  end
  walk(state.forest.roots, {})
  return rows
end

--- @return SessionMgrProcRow|nil
function M.current_row(state)
  return M.visible(state)[state.cursor]
end

--- @return SessionMgrProcNode|nil
function M.current(state)
  local row = M.current_row(state)
  return row and row.node or nil
end

--- What x / X would hit: the marked nodes if there are any, else the cursor
--- row. Nodes no longer in the forest are dropped.
--- @param state SessionMgrProcsState
--- @param mode "term"|"kill_tree"
--- @return SessionMgrProcNode[] nodes, integer[] pids, integer kb freed (tree totals for kill_tree)
function M.targets(state, mode)
  local nodes = {}
  if state.forest then
    local ids = vim.tbl_keys(state.marks)
    table.sort(ids)
    for _, id in ipairs(ids) do
      nodes[#nodes + 1] = state.forest.by_id[id]
    end
  end
  if #nodes == 0 then
    local cur = M.current(state)
    if cur and cur.pid then
      nodes = { cur }
    elseif cur then -- the orphans root: its children, not itself
      nodes = { unpack(cur.children) }
    end
  end
  local pids, seen, kb = {}, {}, 0
  for _, n in ipairs(nodes) do
    local list = mode == "kill_tree" and tree.subtree_pids(n) or { n.pid }
    local new = false
    for _, pid in ipairs(list) do
      if not seen[pid] then
        seen[pid], new = true, true
        pids[#pids + 1] = pid
      end
    end
    if new then
      kb = kb + (mode == "kill_tree" and n.tree or n.own)
    end
  end
  return nodes, pids, kb
end

local function settle(s, count)
  s.cursor = math.max(1, math.min(s.cursor, math.max(count, 1)))
  if s.cursor < s.scroll_top then
    s.scroll_top = s.cursor
  elseif s.cursor > s.scroll_top + s.height - 1 then
    s.scroll_top = s.cursor - s.height + 1
  end
  s.scroll_top = math.max(1, math.min(s.scroll_top, math.max(1, count - s.height + 1)))
  return s
end

local function index_of(s, id)
  for i, r in ipairs(M.visible(s)) do
    if r.node.id == id then
      return i
    end
  end
end

--- @param state SessionMgrProcsState
--- @param action table
--- @return SessionMgrProcsState
function M.reduce(state, action)
  -- `forest` is rebuilt wholesale on refresh and never mutated, and it holds
  -- parent back-pointers, so it is shared rather than deep-copied.
  local forest = state.forest
  local s = vim.deepcopy(vim.tbl_extend("force", state, { forest = false }))
  s.forest = forest
  local t = action.type
  local cur = M.current(state)
  local follow_id = cur and cur.id

  if t == "move" then
    s.cursor = s.cursor + action.delta
    follow_id = nil
  elseif t == "page" then
    s.cursor = s.cursor + action.delta * math.max(1, s.height - 1)
    follow_id = nil
  elseif t == "half_page" then
    s.cursor = s.cursor + action.delta * math.max(1, math.floor(s.height / 2))
    follow_id = nil
  elseif t == "first" then
    s.cursor, follow_id = 1, nil
  elseif t == "last" then
    s.cursor, follow_id = math.huge, nil
  elseif t == "goto" then
    s.cursor, follow_id = action.index, nil
  elseif t == "scroll" then
    local count = #M.visible(s)
    s.scroll_top = math.max(1, math.min(s.scroll_top + action.delta, math.max(1, count - s.height + 1)))
    s.cursor = math.max(s.scroll_top, math.min(s.cursor, s.scroll_top + s.height - 1))
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
  elseif t == "set_forest" then
    s.forest, s.error = action.forest, action.error
    -- Marks on processes that are gone would silently shrink the next batch.
    for id in pairs(s.marks) do
      if not (s.forest and s.forest.by_id[id]) then
        s.marks[id] = nil
      end
    end
  elseif t == "toggle_fold" or t == "open_fold" or t == "close_fold" then
    local row = M.current_row(state)
    if row then
      local id = row.node.id
      if t == "close_fold" and not row.expanded and row.node.parent then
        -- Like zc on a closed fold: close the enclosing one and land on it.
        id = row.node.parent.id
        follow_id = id
      end
      if t == "toggle_fold" then
        s.expanded[id] = not row.expanded or nil
      else
        s.expanded[id] = t == "open_fold" or nil
      end
    end
  elseif t == "open_all" then
    if s.forest then
      for id, n in pairs(s.forest.by_id) do
        if #n.children > 0 then
          s.expanded[id] = true
        end
      end
    end
  elseif t == "close_all" then
    s.expanded = {}
    -- Land on the root the cursor was inside.
    local top = cur
    while top and top.parent do
      top = top.parent
    end
    follow_id = top and top.id
  elseif t == "toggle_mark" then
    if cur and cur.pid then
      s.marks[cur.id] = not s.marks[cur.id] or nil
    end
    s.cursor, follow_id = s.cursor + 1, nil -- htop-style: mark and step down
  elseif t == "clear_marks" then
    s.marks = {}
  elseif t == "resize" then
    s.height = math.max(1, action.height)
  end

  if follow_id then
    s.cursor = index_of(s, follow_id) or s.cursor
  end
  return settle(s, #M.visible(s))
end

return M
