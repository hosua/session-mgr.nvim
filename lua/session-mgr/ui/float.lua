--- The only module that creates windows. Everything it shows was computed
--- elsewhere; it just puts lines, highlights and geometry on screen.
local hl = require "session-mgr.hl"

local M = {}
local NS = vim.api.nvim_create_namespace "session-mgr"
M.NS = NS

--- Border to use: the configured one, else the user's 'winborder', else rounded.
function M.border()
  local cfg = require("session-mgr.config").get().picker.border
  if cfg then
    return cfg
  end
  local ok, wb = pcall(function()
    return vim.o.winborder
  end)
  return (ok and wb ~= "" and wb ~= "none") and wb or "rounded"
end

--- Usable editor area (the floats are laid out inside it).
--- @return { width: integer, height: integer }
function M.editor()
  local status = vim.o.laststatus > 0 and 1 or 0
  local tabline = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
  return { width = vim.o.columns, height = math.max(3, vim.o.lines - vim.o.cmdheight - status - tabline) }
end

--- @class SessionMgrFloat
--- @field buf integer
--- @field win integer

--- @param opts { rect: table, title: string|nil, footer: table|string|nil, enter: boolean|nil, zindex: integer|nil, border: any, relative_win: integer|nil, focusable: boolean|nil }
--- @return SessionMgrFloat
function M.open(opts)
  hl.apply()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = opts.filetype or "session-mgr"
  local border = opts.border == nil and M.border() or opts.border
  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, {
    relative = opts.relative_win and "win" or "editor",
    win = opts.relative_win,
    row = opts.rect.row,
    col = opts.rect.col,
    width = math.max(1, opts.rect.width),
    height = math.max(1, opts.rect.height),
    style = "minimal",
    border = border,
    title = border ~= "none" and opts.title or nil,
    title_pos = border ~= "none" and opts.title and "center" or nil,
    footer = border ~= "none" and opts.footer or nil,
    footer_pos = border ~= "none" and opts.footer and "left" or nil,
    zindex = opts.zindex or 60,
    focusable = opts.focusable,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = hl.WINHL
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].sidescrolloff = 0
  vim.wo[win].scrolloff = 0
  return { buf = buf, win = win }
end

--- @param f SessionMgrFloat
function M.is_open(f)
  return f ~= nil and vim.api.nvim_win_is_valid(f.win) and vim.api.nvim_buf_is_valid(f.buf)
end

--- Move / resize / retitle without recreating the window.
function M.configure(f, rect, title, footer)
  if not M.is_open(f) then
    return
  end
  local cfg = {
    relative = "editor",
    row = rect.row,
    col = rect.col,
    width = math.max(1, rect.width),
    height = math.max(1, rect.height),
  }
  if M.has_border(f) then
    cfg.title, cfg.title_pos = title, title and "center" or nil
    cfg.footer, cfg.footer_pos = footer, footer and "left" or nil
  end
  vim.api.nvim_win_set_config(f.win, cfg)
end

function M.has_border(f)
  local b = vim.api.nvim_win_get_config(f.win).border
  return b ~= nil and b ~= "none"
end

--- Replace the buffer content with a render result (lines + spans + line_hl).
--- @param f SessionMgrFloat
--- @param out { lines: string[], spans: table[], line_hl: table<integer, string> }
function M.paint(f, out)
  if not M.is_open(f) then
    return
  end
  vim.bo[f.buf].modifiable = true
  vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, out.lines)
  vim.bo[f.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(f.buf, NS, 0, -1)
  for row, group in pairs(out.line_hl or {}) do
    if out.lines[row + 1] then
      vim.api.nvim_buf_set_extmark(f.buf, NS, row, 0, { line_hl_group = group, priority = 100 })
    end
  end
  for _, s in ipairs(out.spans or {}) do
    vim.api.nvim_buf_set_extmark(
      f.buf,
      NS,
      s.row,
      s.col_start,
      { end_col = s.col_end, hl_group = s.hl, priority = 200 }
    )
  end
end

function M.close(f)
  if f and vim.api.nvim_win_is_valid(f.win) then
    pcall(vim.api.nvim_win_close, f.win, true)
  end
end

--- Centre a box of the given size in the editor.
function M.centered(width, height)
  local e = M.editor()
  width, height = math.min(width, e.width - 4), math.min(height, e.height - 2)
  return {
    row = math.max(0, math.floor((e.height - height - 2) / 2)),
    col = math.max(0, math.floor((e.width - width - 2) / 2)),
    width = width,
    height = height,
  }
end

return M
