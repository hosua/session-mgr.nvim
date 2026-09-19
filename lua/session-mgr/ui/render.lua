--- Picker rendering. Pure: (state, now, opts) -> exactly what goes on screen.
---
---   lines    buffer lines
---   spans    { row, col_start, col_end, hl }        0-based row, BYTE columns
---   regions  { row, col_start, col_end, kind, id }  clickable boxes, same units
---            kind = "scope" (id project|all), "sort" (id = sort key), "row" (id = selectable)
---   line_hl  { [row] = hl }                         whole-line highlights
---   cursor_row  0-based buffer row of the selected session, or nil
---
--- Byte columns are what vim.fn.getmousepos().column reports (1-based), so a
--- click resolves with a table lookup. Window titles and footers cannot be
--- clicked, which is why the scope tabs and the column header are buffer lines.
local model = require "session-mgr.ui.model"
local paths = require "session-mgr.paths"
local timefmt = require "session-mgr.timefmt"

local M = {}

M.CHROME_LINES = 3 -- scope tabs, filter, column header
local NAME_MAX = 40
local GAP = "  "
local ELLIPSIS = "…"
local ARROW = { asc = " ▲", desc = " ▼" }
local COLUMNS = {
  { key = "name", title = "Name" },
  { key = "uses", title = "Uses", right = true },
  { key = "last_used", title = "Last used" },
  { key = "updated", title = "Updated" },
  { key = "created", title = "Created" },
}

local width = vim.fn.strdisplaywidth

local function truncate(text, max)
  if width(text) <= max then
    return text
  end
  return vim.fn.strcharpart(text, 0, max - 1) .. ELLIPSIS
end

--- Accumulates one line while tracking byte offsets for spans and regions.
local function Line(row, out)
  local self = { text = "" }
  --- @param text string
  --- @param hl string|nil
  --- @param region { kind: string, id: any }|nil
  function self.add(text, hl, region)
    local from = #self.text
    self.text = self.text .. text
    if hl and text ~= "" then
      table.insert(out.spans, { row = row, col_start = from, col_end = #self.text, hl = hl })
    end
    if region then
      table.insert(
        out.regions,
        { row = row, col_start = from, col_end = #self.text, kind = region.kind, id = region.id }
      )
    end
    return self
  end
  --- Pad `text` to `w` display cells.
  function self.cell(text, w, right, hl, region)
    local pad = (" "):rep(math.max(0, w - width(text)))
    return self.add(right and (pad .. text) or (text .. pad), hl, region)
  end
  function self.done()
    out.lines[row + 1] = self.text
  end
  return self
end

local function cells_of(item, now)
  local r = item.row
  return {
    uses = tostring(r.uses),
    last_used = timefmt.relative(now, r.last_used),
    updated = timefmt.relative(now, r.updated),
    created = timefmt.date(r.created),
  }
end

--- @param state SessionMgrPickerState
--- @param now integer
--- @param opts { home: string|nil, min_width: integer|nil, load_key: string|nil }|nil
function M.render(state, now, opts)
  opts = opts or {}
  local out = { lines = {}, spans = {}, regions = {}, line_hl = {} }
  local items, count, total = model.visible(state)

  -- Column widths come from EVERY item, not just the visible window, so the
  -- table does not jitter sideways while scrolling.
  local w = { index = 1 }
  for _, c in ipairs(COLUMNS) do
    w[c.key] = width(c.title) + 2 -- room for the sort arrow
  end
  local rendered = {}
  for i, it in ipairs(items) do
    if it.kind == "row" then
      local c = cells_of(it, now)
      c.name = truncate(it.row.name, NAME_MAX)
      c.project = it.show_project and ("  " .. it.row.label) or ""
      rendered[i] = c
      w.index = math.max(w.index, #tostring(it.index))
      w.name = math.max(w.name, width(c.name) + width(c.project))
      for _, k in ipairs { "uses", "last_used", "updated", "created" } do
        w[k] = math.max(w[k], width(c[k]))
      end
    end
  end
  local gutter = 2 + 2 -- cursor bar + active marker
  local content = gutter + w.index + #GAP
  for _, c in ipairs(COLUMNS) do
    content = content + w[c.key] + #GAP
  end
  -- The footer lives in the border: a window narrower than it would clip it.
  local footer = M.footer(state, opts)
  local footer_w = 2
  for _, chunk in ipairs(footer) do
    footer_w = footer_w + width(chunk[1])
  end
  content = math.max(content, footer_w, opts.min_width or 0)

  -- Row 0: scope tabs, with the match count right-aligned.
  local tabs = Line(0, out)
  tabs.add " "
  for _, tab in ipairs { { "project", " This project " }, { "all", " All projects " } } do
    local on = state.scope == tab[1]
    tabs.add(tab[2], on and "SessionMgrScopeOn" or "SessionMgrScopeOff", { kind = "scope", id = tab[1] })
    tabs.add " "
  end
  local counter = state.filter ~= "" and ("%d of %d"):format(count, total)
    or ("%d session%s"):format(total, total == 1 and "" or "s")
  tabs.add((" "):rep(math.max(1, content - width(tabs.text) - width(counter) - 1)))
  tabs.add(counter, "SessionMgrDim")
  tabs.done()

  -- Row 1: filter.
  local filter = Line(1, out)
  filter.add(" / ", state.filter_focused and "SessionMgrSortActive" or "SessionMgrDim")
  if state.filter ~= "" or state.filter_focused then
    filter.add(state.filter, "SessionMgrName")
    if state.filter_focused then
      filter.add("█", "SessionMgrSortActive")
    else
      filter.add("   <C-l> clears", "SessionMgrDim")
    end
  else
    filter.add("type / to filter by name", "SessionMgrDim")
  end
  filter.done()

  -- Row 2: clickable column header.
  local head = Line(2, out)
  head.add((" "):rep(gutter))
  head.cell("#", w.index, true, "SessionMgrHeader")
  for _, c in ipairs(COLUMNS) do
    head.add(GAP)
    local active = state.sort.key == c.key
    local title = c.title .. (active and ARROW[state.sort.dir] or "")
    head.cell(
      title,
      w[c.key],
      c.right,
      active and "SessionMgrSortActive" or "SessionMgrHeader",
      { kind = "sort", id = c.key }
    )
  end
  head.done()
  out.line_hl[2] = "SessionMgrHeaderLine"

  -- The list: only the visible window of items.
  local row = M.CHROME_LINES
  if #items == 0 then
    local msg = state.filter ~= "" and ("No session name matches %q"):format(state.filter)
      or (state.scope == "all" and "No sessions saved yet." or ("No sessions yet for %s."):format(state.project.label))
    Line(row, out).add("  " .. msg, "SessionMgrDim").done()
    if state.filter == "" then
      Line(row + 1, out).add("  Save one with :SessionMgr save", "SessionMgrDim").done()
    end
  end
  for i = state.scroll_top, math.min(#items, state.scroll_top + state.height - 1) do
    local it, line = items[i], Line(row, out)
    if it.kind == "group" then
      line.add " "
      line.add(it.label, "SessionMgrGroup")
      if it.root then
        line.add("  " .. paths.display_path(it.root, opts.home, 40), "SessionMgrGroupNote")
      end
      if not it.is_git then
        line.add("  (folder, not a git repo)", "SessionMgrGroupNote")
      end
      line.add " "
      line.add(("─"):rep(math.max(0, content - width(line.text) - 1)), "SessionMgrGroupNote")
      out.line_hl[row] = "SessionMgrGroupLine"
    else
      local c, r = rendered[i], it.row
      local selected = it.selectable == state.cursor
      local is_active = state.active and state.active.key == r.key and state.active.name == r.name
      local from = #line.text
      line.add(selected and "▌ " or "  ", selected and "SessionMgrCursorBar" or nil)
      line.add(is_active and "● " or "  ", is_active and "SessionMgrActive" or nil)
      line.cell(tostring(it.index), w.index, true, "SessionMgrIndex")
      line.add(GAP)
      -- Name: base highlight, then the matched characters on top of it.
      local name_at = #line.text
      local name_hl = r.name == state.default_name and "SessionMgrDefault" or "SessionMgrName"
      line.add(c.name, name_hl)
      for _, pos in ipairs(it.positions or {}) do
        if pos <= #c.name - (c.name ~= r.name and #ELLIPSIS or 0) then
          table.insert(
            out.spans,
            { row = row, col_start = name_at + pos - 1, col_end = name_at + pos, hl = "SessionMgrMatch" }
          )
        end
      end
      line.add(c.project, "SessionMgrDim")
      line.add((" "):rep(w.name - width(c.name) - width(c.project)))
      line.add(GAP).cell(c.uses, w.uses, true, r.uses > 0 and "SessionMgrName" or "SessionMgrDim")
      line.add(GAP).cell(c.last_used, w.last_used, false, r.last_used and "SessionMgrName" or "SessionMgrNever")
      line.add(GAP).cell(c.updated, w.updated, false, "SessionMgrName")
      line.add(GAP).cell(c.created, w.created, false, "SessionMgrDim")
      line.add((" "):rep(math.max(0, content - width(line.text))))
      table.insert(out.regions, { row = row, col_start = from, col_end = #line.text, kind = "row", id = it.selectable })
      if selected then
        out.line_hl[row] = "SessionMgrCursorLine"
        out.cursor_row = row
      end
    end
    line.done()
    row = row + 1
  end

  -- Outside git a project is just "this folder": say so where it is read,
  -- under the list, instead of stretching the footer.
  out.chrome_bottom = 0
  if not state.project.is_git and state.scope == "project" then
    local key = opts.all_key or ":SessionMgr all"
    Line(row, out).add("", nil).done()
    Line(row + 1, out)
      .add((" ! not a git repo: listed only from this folder (%s lists it anywhere)"):format(key), "SessionMgrWarn")
      .done()
    out.chrome_bottom = 2
    content = math.max(content, width(out.lines[row + 2]) + 1)
  end

  out.width = content
  out.list_lines = math.max(#items, #items == 0 and 2 or 0)
  out.title = M.title(state, opts)
  out.footer = footer
  return out
end

--- @return string
function M.title(state, opts)
  if state.scope == "all" then
    return " Showing your saved sessions for all projects "
  end
  local p = state.project
  local who = p.is_git and p.label or paths.display_path(p.root, opts and opts.home, 40)
  return (" Load a session for %s "):format(who)
end

--- Key hints as { text, hl } chunks, the shape nvim_open_win's `footer` takes.
--- @return string[][]
function M.footer(state, opts)
  local hints
  if state.filter_focused then
    hints = { { "⏎", "keep" }, { "esc", "clear" } }
  else
    hints = {
      { "⏎", "load" },
      { "/", "filter" },
      { "a", state.scope == "all" and "project" or "all" },
      { "r", "rename" },
      { "d", "delete" },
      { "p", "preview" },
      { "?", "help" },
    }
  end
  local chunks = { { " ", "SessionMgrFooter" } }
  for _, h in ipairs(hints) do
    chunks[#chunks + 1] = { h[1], "SessionMgrFooterKey" }
    chunks[#chunks + 1] = { " " .. h[2] .. "  ", "SessionMgrFooter" }
  end
  return chunks
end

--- Which region is at a mouse position? `column` is 1-based bytes, as in
--- vim.fn.getmousepos(); `line` is the 1-based buffer line.
--- @return { kind: string, id: any }|nil
function M.hit(regions, line, column)
  for _, r in ipairs(regions) do
    if r.row == line - 1 and column - 1 >= r.col_start and column - 1 < r.col_end then
      return r
    end
  end
end

return M
