--- Binds session-mgr's look (groups, border rule, priorities, z-order) to
--- popup.nvim. Every window is opened by popup.float; this file only fills in
--- the options so the call sites stay short.
local borders = require "popup.borders"
local float = require "popup.float"
local geometry = require "popup.geometry"
local hl = require "session-mgr.hl"

local M = {}
M.NS = vim.api.nvim_create_namespace "session-mgr"

local PAINT = { line_priority = 100, span_priority = 200 }

--- The environment the layout reads. Tests replace this to fake a small or
--- wide editor.
--- @return PopupEnv
function M.env()
  return geometry.env()
end

--- Usable editor area (the floats are laid out inside it).
--- @return { width: integer, height: integer }
function M.editor()
  return geometry.editor(M.env())
end

--- Centre a box of the given size in the editor.
function M.centered(width, height)
  return geometry.centered(M.env(), width, height)
end

--- The configured picker border, else popup.nvim's rule (winborder, with
--- "none" treated as unset, else rounded).
function M.border()
  return require("session-mgr.config").get().picker.border
end

--- @param opts { rect: table, title: string|nil, footer: table|string|nil, enter: boolean|nil, zindex: integer|nil, border: any, relative_win: integer|nil, focusable: boolean|nil, filetype: string|nil }
--- @return PopupFloat
function M.open(opts)
  hl.apply()
  return float.open {
    rect = opts.rect,
    title = opts.title,
    footer = opts.footer,
    enter = opts.enter,
    border = opts.border == nil and M.border() or opts.border,
    relative_win = opts.relative_win,
    focusable = opts.focusable,
    zindex = opts.zindex or 60,
    noautocmd = true,
    none_is_rounded = true,
    filetype = opts.filetype or "session-mgr",
    winhl = hl.WINHL,
    wo = { sidescrolloff = 0, scrolloff = 0 },
    ns = M.NS,
  }
end

--- Replace the buffer content with a render result (lines + spans + line_hl).
--- @param f PopupFloat
--- @param out { lines: string[], spans: table[], line_hl: table<integer, string> }
function M.paint(f, out)
  float.paint(f, out, PAINT)
end

--- @param f PopupFloat
function M.has_border(f)
  return borders.visible(vim.api.nvim_win_get_config(f.win).border)
end

--- popup.confirm with session-mgr's groups. The border and filetype are put
--- back afterwards because popup.confirm does not take them.
--- @return PopupFloat
function M.confirm(opts)
  hl.apply()
  local f = require("popup.confirm").open(vim.tbl_extend("force", opts, {
    winhl = hl.WINHL,
    hl = { key = "SessionMgrFooterKey", danger = "SessionMgrDanger", footer = "SessionMgrFooter" },
  }))
  vim.bo[f.buf].filetype = "session-mgr"
  local border = M.border()
  if border then
    vim.api.nvim_win_set_config(f.win, { border = border })
  end
  return f
end

return M
