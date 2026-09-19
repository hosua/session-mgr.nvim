--- Short-lived, non-focusable message float in the top-right corner.
---
--- Why not vim.notify: the save message is two lines, and with the default
--- cmdheight=1 a two-line message stops the editor at "Press ENTER".
local float = require "session-mgr.ui.float"

local M = {}

local LEVEL_HL = { [vim.log.levels.WARN] = "SessionMgrWarn", [vim.log.levels.ERROR] = "SessionMgrDanger" }
local open = {} --- @type SessionMgrFloat[]

local function restack()
  local row = 1
  for _, f in ipairs(open) do
    if float.is_open(f) then
      local cfg = vim.api.nvim_win_get_config(f.win)
      vim.api.nvim_win_set_config(f.win, { relative = "editor", row = row, col = vim.o.columns - cfg.width - 3 })
      row = row + cfg.height + 2
    end
  end
end

--- @param msg string may contain newlines
--- @param level integer|nil vim.log.levels
--- @param timeout_ms integer|nil
function M.show(msg, level, timeout_ms)
  level = level or vim.log.levels.INFO
  local lines = vim.split(msg, "\n", { plain = true })
  local max = math.max(20, vim.o.columns - 8)
  local width = 0
  for i, l in ipairs(lines) do
    lines[i] = " " .. l .. " "
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  width = math.min(width, max)
  local f = float.open {
    rect = { row = 1, col = vim.o.columns - width - 3, width = width, height = #lines },
    title = " session-mgr ",
    enter = false,
    focusable = false,
    zindex = 200,
    filetype = "session-mgr-toast",
  }
  local spans = {}
  if LEVEL_HL[level] then
    vim.wo[f.win].winhighlight = vim.wo[f.win].winhighlight
      .. ",FloatBorder:"
      .. LEVEL_HL[level]
      .. ",FloatTitle:"
      .. LEVEL_HL[level]
  end
  for i = 2, #lines do
    spans[#spans + 1] = { row = i - 1, col_start = 0, col_end = #lines[i], hl = "SessionMgrDim" }
  end
  float.paint(f, { lines = lines, spans = spans })
  table.insert(open, f)
  restack()
  vim.defer_fn(function()
    float.close(f)
    open = vim.tbl_filter(function(o)
      return o ~= f and float.is_open(o)
    end, open)
    restack()
  end, timeout_ms or (level >= vim.log.levels.WARN and 7000 or 4500))
  return f
end

return M
