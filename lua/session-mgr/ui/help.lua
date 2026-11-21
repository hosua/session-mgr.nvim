--- `?` in the picker: every key, grouped.
local float = require "popup.float"
local ui = require "session-mgr.ui.style"

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
      { "1-5", "name, uses, last used, updated, created", tab = "sessions" },
      { "1-6", "pid, tree, own memory, threads, cpu, command", tab = "procs" },
      { "o", "reverse" },
      { "click a header", "sort by it; again to reverse" },
    },
  },
  {
    "Find",
    {
      { "/", "filter by name (live)", tab = "sessions" },
      { "/", "filter by command or cwd (live)", tab = "procs" },
      { "⏎ / esc", "in the filter: keep / clear" },
      { "^l", "clear the filter" },
      { "p", "show / hide the preview pane" },
    },
  },
  {
    "Sessions",
    tab = "sessions",
    {
      { "⏎  double-click", "load" },
      { "r", "rename" },
      { "d", "delete" },
      { "a", "this project <-> all projects" },
      { "s", "autosave on / off for this nvim (footer shows which)" },
    },
  },
  {
    "Processes",
    tab = "procs",
    {
      { "⏎  za  click [+]", "fold / unfold" },
      { "zo zc  zR zM", "open / close, all open / all closed" },
      { "␣", "mark (x / X then act on every mark)" },
      { "x", "SIGTERM the process (nvim stops its own LSPs)" },
      { "X", "SIGKILL the process and everything below it" },
      { "r", "refresh now" },
      { "^l", "clear the filter and the marks" },
    },
  },
  {
    "Tabs and close",
    { { "Tab  S-Tab", "next / previous tab (click a tab too)" }, { "q  esc", "close (esc clears a filter first)" } },
  },
}

--- Only the symbols that the shown keys use. All keys are normal mode and
--- local to the picker.
M.LEGEND = {
  sessions = { { "^x", "Ctrl+x" }, { "⏎  esc", "Enter, Escape" }, { "S-Tab", "Shift+Tab" } },
  procs = { { "^x", "Ctrl+x" }, { "⏎  esc", "Enter, Escape" }, { "␣", "Space" }, { "S-Tab", "Shift+Tab" } },
  all = { { "^x", "Ctrl+x" }, { "⏎  esc", "Enter, Escape" }, { "␣", "Space" }, { "S-Tab", "Shift+Tab" } },
}

--- Only the keys for the tab you are on, so the list fits a small screen.
--- @param tab "sessions"|"procs"|nil nil = everything
function M.sections(tab)
  local out = {}
  for _, s in ipairs(M.SECTIONS) do
    if not (tab and s.tab and s.tab ~= tab) then
      local rows = vim.tbl_filter(function(k)
        return not (tab and k.tab and k.tab ~= tab)
      end, s[2])
      out[#out + 1] = { s[1], rows }
    end
  end
  return out
end

function M.build(tab)
  local sections = M.sections(tab)
  -- What the symbols in the key column mean.
  sections[#sections + 1] = { "How to read this list", M.LEGEND[tab or "all"] or M.LEGEND.all }
  local lines, spans = require("popup.legend").help(sections, {
    title_hl = "SessionMgrHeader",
    key_hl = "SessionMgrFooterKey",
    desc_hl = "SessionMgrFooter",
  })
  return { lines = lines, spans = spans, line_hl = {}, width = require("popup.legend").width(lines, 2) }
end

function M.open(on_close, tab)
  local out = M.build(tab)
  local f = ui.open { rect = ui.centered(out.width, #out.lines), title = " session-mgr keys ", zindex = 80 }
  ui.paint(f, out)
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
