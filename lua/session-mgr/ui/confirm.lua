--- A small modal float: a few lines, and keys that answer it.
---
---   confirm.open {
---     title = "2 unsaved buffers", danger = true,
---     lines = { { { "  M  ", "SessionMgrWarn" }, { "init.lua" } }, ... },   -- chunks per line
---     choices = { { key = "w", label = "write all & load", value = "write" }, ... },
---     on_choice = function(value) end,   -- nil when cancelled (q / <Esc>)
---   }
local float = require "session-mgr.ui.float"

local M = {}

--- Pure: chunks -> lines + spans, plus the choice rows.
function M.build(opts)
  local lines, spans = {}, {}
  local function push(chunks)
    local text = ""
    for _, c in ipairs(chunks) do
      if c[2] and c[1] ~= "" then
        spans[#spans + 1] = { row = #lines, col_start = #text, col_end = #text + #c[1], hl = c[2] }
      end
      text = text .. c[1]
    end
    lines[#lines + 1] = text
  end
  for _, l in ipairs(opts.lines or {}) do
    push(l)
  end
  if #lines > 0 then
    push {}
  end
  for _, c in ipairs(opts.choices) do
    push { { "  " }, { c.key, c.danger and "SessionMgrDanger" or "SessionMgrFooterKey" }, { "  " .. c.label } }
  end
  local width = vim.fn.strdisplaywidth(opts.title or "") + 4
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 2)
  end
  return { lines = lines, spans = spans, line_hl = {}, width = width }
end

--- @return SessionMgrFloat
function M.open(opts)
  local out = M.build(opts)
  local f = float.open {
    rect = float.centered(math.max(out.width, 34), #out.lines),
    title = (" %s "):format(opts.title),
    footer = { { " q", "SessionMgrFooterKey" }, { " cancel ", "SessionMgrFooter" } },
    zindex = 80,
  }
  if opts.danger then
    vim.wo[f.win].winhighlight = vim.wo[f.win].winhighlight .. ",FloatTitle:SessionMgrDanger"
  end
  float.paint(f, out)
  vim.api.nvim_win_set_cursor(f.win, { #out.lines, 0 })

  local answered = false
  local function answer(value)
    if answered then
      return
    end
    answered = true
    float.close(f)
    vim.schedule(function()
      opts.on_choice(value)
    end)
  end
  local function map(lhs, value)
    vim.keymap.set("n", lhs, function()
      answer(value)
    end, { buffer = f.buf, nowait = true })
  end
  for _, c in ipairs(opts.choices) do
    map(c.key, c.value)
  end
  for _, lhs in ipairs { "q", "<Esc>", "<C-c>" } do
    map(lhs, nil)
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = f.buf,
    once = true,
    callback = function()
      answer(nil)
    end,
  })
  return f
end

return M
