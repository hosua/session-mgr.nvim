--- Save-popup model. Pure.
---
--- Two strings, like Vim's wildmenu: `query` is what the user typed and is
--- what narrows the list; `text` is what the input shows. Tab cycling changes
--- only `text`, otherwise the first Tab would narrow the list to one row and
--- there would be nothing left to cycle through.
local fuzzy = require "session-mgr.fuzzy"
local timefmt = require "session-mgr.timefmt"

local M = {}

--- @param opts { rows: SessionMgrRow[], text: string|nil, default_name: string, height: integer|nil }
function M.new(opts)
  local rows = vim.deepcopy(opts.rows)
  table.sort(rows, function(a, b)
    if (a.name == opts.default_name) ~= (b.name == opts.default_name) then
      return a.name == opts.default_name
    end
    return a.name:lower() < b.name:lower()
  end)
  -- A pre-filled name does not narrow: the whole list is visible until the user types.
  return {
    rows = rows,
    query = "",
    text = opts.text or "",
    index = 0,
    height = opts.height or 10,
    default_name = opts.default_name,
  }
end

--- @return { item: SessionMgrRow, positions: integer[] }[]
function M.candidates(state)
  return fuzzy.filter(state.query, state.rows, function(r)
    return r.name
  end)
end

--- @return SessionMgrRow|nil the existing session `text` would overwrite
function M.existing(state)
  local typed = vim.trim(state.text):gsub("%.[vV][iI][mM]$", "")
  for _, r in ipairs(state.rows) do
    if r.name == typed then
      return r
    end
  end
end

function M.reduce(state, action)
  local s = vim.deepcopy(state)
  if action.type == "type" then
    s.text, s.query, s.index = action.text, action.text, 0
  elseif action.type == "cycle" then
    local c = M.candidates(s)
    if #c > 0 then
      -- From "nothing selected", Tab goes to the first and S-Tab to the last.
      s.index = s.index == 0 and (action.delta > 0 and 1 or #c) or ((s.index - 1 + action.delta) % #c + 1)
      s.text = c[s.index].item.name
    end
  end
  return s
end

--- @return { lines: string[], spans: table[], line_hl: table, status: string[][] }
function M.render(state, now, width)
  local out = { lines = {}, spans = {}, line_hl = {} }
  local c = M.candidates(state)
  local top = math.max(1, math.min(state.index - state.height + 1, #c - state.height + 1))
  if state.index > 0 and state.index < top then
    top = state.index
  end
  top = math.max(1, state.index == 0 and 1 or math.max(top, state.index - state.height + 1))
  for i = top, math.min(#c, top + state.height - 1) do
    local r, row = c[i].item, #out.lines
    local when = timefmt.relative(now, r.updated)
    local name = r.name
    local room = width - 4 - vim.fn.strdisplaywidth(when) - 2
    if vim.fn.strdisplaywidth(name) > room then
      name = vim.fn.strcharpart(name, 0, math.max(1, room - 1)) .. "…"
    end
    local selected = i == state.index
    local line = (selected and " ▌ " or "   ") .. name
    local pad = math.max(1, width - vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(when) - 1)
    out.lines[#out.lines + 1] = line .. (" "):rep(pad) .. when
    local at = #(selected and " ▌ " or "   ")
    out.spans[#out.spans + 1] = {
      row = row,
      col_start = at,
      col_end = at + #name,
      hl = r.name == state.default_name and "SessionMgrDefault" or "SessionMgrName",
    }
    for _, pos in ipairs(c[i].positions) do
      if pos <= #name and name == r.name then
        out.spans[#out.spans + 1] = { row = row, col_start = at + pos - 1, col_end = at + pos, hl = "SessionMgrMatch" }
      end
    end
    out.spans[#out.spans + 1] =
      { row = row, col_start = #line + pad, col_end = #line + pad + #when, hl = "SessionMgrDim" }
    if selected then
      out.line_hl[row] = "SessionMgrCursorLine"
      out.spans[#out.spans + 1] = { row = row, col_start = 1, col_end = 1 + #"▌", hl = "SessionMgrCursorBar" }
    end
  end
  if #c == 0 then
    local msg = #state.rows == 0 and "  no sessions saved for this project yet"
      or "  no existing session matches: this will be a new one"
    out.lines[1] = msg
    out.spans[1] = { row = 0, col_start = 0, col_end = #msg, hl = "SessionMgrDim" }
  end

  local existing = M.existing(state)
  out.status = existing and { { " overwrites ", "SessionMgrWarn" }, { existing.name .. ".vim ", "SessionMgrWarn" } }
    or { { vim.trim(state.text) == "" and " type a name " or " new session ", "SessionMgrFooter" } }
  out.count = #c
  return out
end

return M
