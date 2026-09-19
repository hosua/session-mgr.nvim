local layout = require "session-mgr.ui.layout"
local CFG = { max_width = 0.9, max_height = 0.8, preview = true, preview_min_columns = 120, preview_width = 0.4 }
local function content(w, lines)
  return { width = w, list_lines = lines, chrome = 3 }
end

describe("layout.compute", function()
  it("fits the content and centres it", function()
    local l = layout.compute(content(72, 5), { width = 100, height = 40 }, CFG)
    eq({ row = 15, col = 13, width = 72, height = 8 }, l.list)
    eq(nil, l.preview)
    eq(5, l.list_height)
  end)
  it("clamps tall lists to max_height and reports the list height", function()
    local l = layout.compute(content(72, 500), { width = 100, height = 40 }, CFG)
    eq(30, l.list.height)
    eq(27, l.list_height)
  end)
  it("clamps wide content to max_width", function()
    eq(70, layout.compute(content(200, 5), { width = 80, height = 24 }, CFG).list.width)
  end)
  it("adds a preview on wide editors, beside the list", function()
    local l = layout.compute(content(72, 5), { width = 160, height = 40 }, CFG)
    eq(56, l.preview.width)
    eq(l.list.col + 72 + 2, l.preview.col)
    eq(l.list.height, l.preview.height)
  end)
  it("drops the preview below preview_min_columns, when disabled, or when squeezed under 30 columns", function()
    eq(nil, layout.compute(content(72, 5), { width = 119, height = 40 }, CFG).preview)
    eq(
      nil,
      layout.compute(content(72, 5), { width = 160, height = 40 }, vim.tbl_extend("force", CFG, { preview = false })).preview
    )
    eq(nil, layout.compute(content(100, 5), { width = 125, height = 40 }, CFG).preview)
  end)
  it("stays on screen at 80x24 and in a tiny editor", function()
    for _, e in ipairs { { width = 80, height = 24 }, { width = 30, height = 6 } } do
      local l = layout.compute(content(72, 50), e, CFG)
      ok(l.list.row >= 0 and l.list.col >= 0)
      ok(l.list.width + 2 <= math.max(e.width, 22), "width")
      ok(l.list_height >= 1)
    end
  end)
end)
