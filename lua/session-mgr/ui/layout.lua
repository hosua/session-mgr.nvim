--- Picker geometry. Pure: content size + editor size -> window rectangles.
local M = {}

local BORDER = 2

--- @param content { width: integer, list_lines: integer, chrome: integer }
--- @param editor { width: integer, height: integer } usable cells (columns, lines minus cmdline/statusline)
--- @param cfg { max_width: number, max_height: number, preview: boolean, preview_min_columns: integer, preview_width: number }
--- @return { list: table, preview: table|nil, list_height: integer }
function M.compute(content, editor, cfg)
  local max_w = math.max(20, math.floor(editor.width * cfg.max_width) - BORDER)
  local max_h = math.max(content.chrome + 1, math.floor(editor.height * cfg.max_height) - BORDER)

  local want_preview = cfg.preview and editor.width >= cfg.preview_min_columns
  local list_w = math.min(content.width, max_w)
  local preview_w = 0
  if want_preview then
    preview_w = math.max(30, math.floor(max_w * cfg.preview_width))
    -- The list keeps its natural width; the preview gives way first.
    if list_w + BORDER + preview_w > max_w then
      preview_w = max_w - BORDER - list_w
    end
    if preview_w < 30 then
      want_preview, preview_w = false, 0
    end
  end

  local height = math.min(content.chrome + math.max(content.list_lines, 1), max_h)
  local total_w = list_w + (want_preview and (BORDER + preview_w) or 0)
  local row = math.max(0, math.floor((editor.height - height - BORDER) / 2))
  local col = math.max(0, math.floor((editor.width - total_w - BORDER) / 2))

  return {
    list = { row = row, col = col, width = list_w, height = height },
    preview = want_preview and { row = row, col = col + list_w + BORDER, width = preview_w, height = height } or nil,
    list_height = height - content.chrome,
  }
end

return M
