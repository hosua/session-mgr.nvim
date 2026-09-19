--- `?` in the picker: every key, grouped.
local float = require "session-mgr.ui.float"

local M = {}

M.SECTIONS = {
  {
    "Move",
    {
      { "j k  ↑ ↓", "up / down" },
      { "gg G  Home End", "first / last ({count}G jumps to row #)" },
      { "^d ^u", "half a page" },
      { "PgDn PgUp", "a page" },
      { "wheel", "scroll" },
    },
  },
  {
    "Sort",
    {
      { "h l  ← →", "previous / next column" },
      { "1-5", "name, uses, last used, updated, created" },
      { "o", "reverse" },
      { "click a header", "sort by it; again to reverse" },
    },
  },
  {
    "Find",
    {
      { "/", "filter by name (live)" },
      { "⏎ / esc", "in the filter: keep / clear" },
      { "^l", "clear the filter" },
      { "a  Tab", "this project <-> all projects" },
      { "p", "show / hide the preview pane" },
    },
  },
  { "Act", { { "⏎  double-click", "load" }, { "r", "rename" }, { "d", "delete" }, { "q  esc", "close" } } },
}

function M.build()
  local out = { lines = {}, spans = {}, line_hl = {} }
  local keyw = 0
  for _, s in ipairs(M.SECTIONS) do
    for _, k in ipairs(s[2]) do
      keyw = math.max(keyw, vim.fn.strdisplaywidth(k[1]))
    end
  end
  for i, s in ipairs(M.SECTIONS) do
    if i > 1 then
      out.lines[#out.lines + 1] = ""
    end
    out.lines[#out.lines + 1] = " " .. s[1]
    out.spans[#out.spans + 1] = { row = #out.lines - 1, col_start = 1, col_end = 1 + #s[1], hl = "SessionMgrHeader" }
    for _, k in ipairs(s[2]) do
      local pad = (" "):rep(keyw - vim.fn.strdisplaywidth(k[1]))
      out.lines[#out.lines + 1] = "   " .. k[1] .. pad .. "   " .. k[2]
      out.spans[#out.spans + 1] =
        { row = #out.lines - 1, col_start = 3, col_end = 3 + #k[1], hl = "SessionMgrFooterKey" }
    end
  end
  out.width = 0
  for _, l in ipairs(out.lines) do
    out.width = math.max(out.width, vim.fn.strdisplaywidth(l) + 2)
  end
  return out
end

function M.open(on_close)
  local out = M.build()
  local f = float.open { rect = float.centered(out.width, #out.lines), title = " session-mgr keys ", zindex = 80 }
  float.paint(f, out)
  local closed = false
  local function close()
    if not closed then
      closed = true
      float.close(f)
      vim.schedule(on_close)
    end
  end
  for _, lhs in ipairs { "q", "<Esc>", "?", "<CR>" } do
    vim.keymap.set("n", lhs, close, { buffer = f.buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = f.buf, once = true, callback = close })
  return f
end

return M
