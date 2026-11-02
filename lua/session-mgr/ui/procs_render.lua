--- Processes tab rendering. Pure, same output shape as ui/render.lua:
--- lines, spans, regions (kinds "scope", "sort", "row", "fold"), line_hl,
--- cursor_row, width, list_lines, title, footer.
local parse = require "session-mgr.procs.parse"
local paths = require "session-mgr.paths"
local pm = require "session-mgr.ui.procs_model"
local render = require "session-mgr.ui.render"

local M = {}

M.CHROME_LINES = render.CHROME_LINES
local GAP = "  "
local ARROW = { asc = " ▲", desc = " ▼" }
local CMD_MIN = 24

local width = vim.fn.strdisplaywidth

local function columns(memory)
  return {
    { key = "pid", title = "PID", right = true },
    { key = "tree", title = "Tree", right = true },
    { key = "own", title = memory == "pss" and "PSS" or "RSS", right = true },
    { key = "threads", title = "Thr", right = true },
    { key = "cpu", title = "CPU%", right = true },
    { key = "command", title = "Command" },
  }
end

local function cpu_text(cpu)
  if not cpu then
    return "…"
  end
  return ("%.1f"):format(cpu)
end

--- @param state SessionMgrProcsState
--- @param opts { home: string|nil, max_width: integer|nil, big_kb: integer|nil }|nil
function M.render(state, opts)
  opts = opts or {}
  local out = { lines = {}, spans = {}, regions = {}, line_hl = {} }
  local rows = pm.visible(state)
  local forest = state.forest
  local cols = columns(forest and forest.memory)

  -- Numeric widths over every row, so the table does not jitter on scroll.
  local w = {}
  for _, c in ipairs(cols) do
    w[c.key] = width(c.title) + 2
  end
  local cells = {}
  for i, r in ipairs(rows) do
    local n = r.node
    local c = {
      pid = n.pid and tostring(n.pid) or "",
      tree = parse.size(n.tree),
      own = n.pid and (parse.size(n.own) .. (n.approx and "*" or "")) or "",
      threads = n.proc and tostring(n.proc.threads) or "",
      cpu = n.pid and cpu_text(n.cpu) or "",
    }
    cells[i] = c
    for _, k in ipairs { "pid", "tree", "own", "threads", "cpu" } do
      w[k] = math.max(w[k], width(c[k]))
    end
  end
  local gutter = 4 -- cursor bar, mark, own-session dot, space
  local fixed = gutter
  for _, c in ipairs(cols) do
    if c.key ~= "command" then
      fixed = fixed + w[c.key] + #GAP
    end
  end

  -- Command takes what is left, up to its widest line.
  local cmd_texts, cmd_w = {}, w.command
  for i, r in ipairs(rows) do
    local n = r.node
    local box = r.has_children and (r.expanded and "[-]" or "[+]") or ""
    local cmd = n.proc and n.proc.args or n.label
    local cwd = (n.depth == 0 and n.cwd) and ("  " .. paths.display_path(n.cwd, opts.home, 40)) or ""
    cmd_texts[i] = { prefix = r.prefix, box = box, cmd = cmd, cwd = cwd }
    cmd_w = math.max(cmd_w, width(r.prefix .. box .. cmd .. cwd))
  end
  local footer = M.footer(state)
  local footer_w = 2
  for _, chunk in ipairs(footer) do
    footer_w = footer_w + width(chunk[1])
  end
  local floor_w = math.max(footer_w, render.tabs_width() + 22)
  local max_w = opts.max_width or math.huge
  cmd_w = math.max(CMD_MIN, math.min(cmd_w, max_w - fixed))
  local content = math.max(fixed + cmd_w, floor_w)
  cmd_w = content - fixed

  local count = forest and forest.count or 0
  local counter = forest and ("%d proc%s  %s"):format(count, count == 1 and "" or "s", parse.size(forest.total)) or ""
  render.tabs(out, "procs", content, counter)

  local filter = render.Line(1, out)
  filter.add(" / ", state.filter_focused and "SessionMgrSortActive" or "SessionMgrDim")
  local marks = vim.tbl_count(state.marks)
  if state.filter ~= "" or state.filter_focused then
    filter.add(state.filter, "SessionMgrName")
    if state.filter_focused then
      filter.add("█", "SessionMgrSortActive")
    else
      filter.add("   <C-l> clears", "SessionMgrDim")
    end
    if marks > 0 then
      filter.add(("   %d marked"):format(marks), "SessionMgrMarked")
    end
  else
    local n = vim.tbl_count(state.marks)
    filter.add(
      n > 0 and ("%d marked   x / X act on all of them, <C-l> clears"):format(n) or "type / to filter by command or cwd",
      n > 0 and "SessionMgrMarked" or "SessionMgrDim"
    )
  end
  filter.done()

  local head = render.Line(2, out)
  head.add((" "):rep(gutter))
  for i, c in ipairs(cols) do
    if i > 1 then
      head.add(GAP)
    end
    local active = state.sort.key == c.key
    local title = c.title .. (active and ARROW[state.sort.dir] or "")
    head.cell(
      title,
      c.key == "command" and math.min(cmd_w, width(title)) or w[c.key],
      c.right,
      active and "SessionMgrSortActive" or "SessionMgrHeader",
      { kind = "sort", id = c.key }
    )
  end
  head.done()
  out.line_hl[2] = "SessionMgrHeaderLine"

  local row = M.CHROME_LINES
  if #rows == 0 then
    local msg, hl
    if state.error then
      msg, hl = state.error, "SessionMgrDanger"
    elseif not forest then
      msg, hl = "reading processes…", "SessionMgrDim"
    elseif state.filter ~= "" then
      msg, hl = ("No process matches %q"):format(state.filter), "SessionMgrDim"
    else
      msg, hl = "No nvim processes found.", "SessionMgrDim"
    end
    render.Line(row, out).add("  " .. msg, hl).done()
  end

  local big = opts.big_kb or math.huge
  for i = state.scroll_top, math.min(#rows, state.scroll_top + state.height - 1) do
    local r, c, t = rows[i], cells[i], cmd_texts[i]
    local n = r.node
    local line = render.Line(row, out)
    local selected = i == state.cursor
    local marked = state.marks[n.id]
    line.add(selected and "▌" or " ", selected and "SessionMgrCursorBar" or nil)
    line.add(marked and "+" or " ", marked and "SessionMgrMarked" or nil)
    line.add(n.own_session and "●" or " ", n.own_session and "SessionMgrActive" or nil)
    line.add " "
    line.cell(c.pid, w.pid, true, "SessionMgrIndex")
    line.add(GAP).cell(c.tree, w.tree, true, n.tree >= big and "SessionMgrProcBig" or "SessionMgrName")
    line.add(GAP).cell(c.own, w.own, true, n.own >= big and "SessionMgrProcBig" or "SessionMgrDim")
    line.add(GAP).cell(c.threads, w.threads, true, "SessionMgrDim")
    line.add(GAP).cell(c.cpu, w.cpu, true, (n.cpu or 0) >= 50 and "SessionMgrWarn" or "SessionMgrDim")
    line.add(GAP)
    local room = cmd_w
    line.add(t.prefix, "SessionMgrProcTree")
    room = room - width(t.prefix)
    if t.box ~= "" then
      line.add(t.box, "SessionMgrProcTree", { kind = "fold", id = i })
      room = room - width(t.box)
    end
    local cmd = render.truncate(t.cmd, math.max(1, room))
    local cmd_hl = n.pid == nil and "SessionMgrGroup"
      or (r.matched and "SessionMgrMatch")
      or (n.proc.comm == "nvim" and "SessionMgrName" or "SessionMgrProcCmd")
    line.add(cmd, cmd_hl)
    room = room - width(cmd)
    if t.cwd ~= "" and room > 4 then
      line.add(render.truncate(t.cwd, room), "SessionMgrPreviewPath")
    end
    line.add((" "):rep(math.max(0, content - width(line.text))))
    table.insert(out.regions, { row = row, col_start = 0, col_end = #line.text, kind = "row", id = i })
    if selected then
      out.line_hl[row] = "SessionMgrCursorLine"
      out.cursor_row = row
    elseif marked then
      out.line_hl[row] = "SessionMgrMarkedLine"
    end
    line.done()
    row = row + 1
  end

  out.chrome_bottom = 0
  out.width = content
  out.list_lines = math.max(#rows, 1)
  out.title = M.title(state)
  out.footer = footer
  return out
end

function M.title(state)
  if state.forest and state.forest.memory == "rss" then
    return " nvim processes (RSS: shared memory counted in every process) "
  end
  return " nvim processes "
end

function M.footer(state)
  local hints
  if state.filter_focused then
    hints = { { "⏎", "keep" }, { "esc", "clear" } }
  else
    hints = {
      { "x", "term" },
      { "X", "kill tree" },
      { "␣", "mark" },
      { "⏎", "fold" },
      { "/", "filter" },
      { "r", "refresh" },
      { "?", "help" },
    }
  end
  local chunks = { { " ", "SessionMgrFooter" } }
  for _, h in ipairs(hints) do
    chunks[#chunks + 1] = { h[1], h[1]:lower() == "x" and "SessionMgrDanger" or "SessionMgrFooterKey" }
    chunks[#chunks + 1] = { " " .. h[2] .. "  ", "SessionMgrFooter" }
  end
  return chunks
end

return M
