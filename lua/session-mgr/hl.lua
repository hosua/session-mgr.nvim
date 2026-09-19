--- Highlight groups. Every group is a `default` link to a semantic group, so
--- any colorscheme works and a user override always wins.
local M = {}

M.LINKS = {
  SessionMgrNormal = "NormalFloat",
  SessionMgrBorder = "FloatBorder",
  SessionMgrTitle = "FloatTitle",
  SessionMgrFooter = "Comment",
  SessionMgrFooterKey = "Special",
  SessionMgrHeader = "Title",
  SessionMgrHeaderLine = "SessionMgrNormal",
  SessionMgrSortActive = "Function",
  SessionMgrGroup = "Directory",
  SessionMgrGroupNote = "Comment",
  SessionMgrGroupLine = "SessionMgrNormal",
  SessionMgrIndex = "LineNr",
  SessionMgrName = "NormalFloat",
  SessionMgrDefault = "Constant",
  SessionMgrActive = "DiagnosticOk",
  SessionMgrDim = "Comment",
  SessionMgrNever = "NonText",
  SessionMgrMatch = "Search",
  SessionMgrCursorLine = "CursorLine",
  SessionMgrCursorBar = "Function",
  SessionMgrHover = "Visual",
  SessionMgrScopeOn = "TabLineSel",
  SessionMgrScopeOff = "TabLine",
  SessionMgrSuffix = "Comment",
  SessionMgrWarn = "DiagnosticWarn",
  SessionMgrDanger = "DiagnosticError",
  SessionMgrPreviewKey = "Identifier",
  SessionMgrPreviewPath = "Directory",
}

M.WINHL =
  "NormalFloat:SessionMgrNormal,FloatBorder:SessionMgrBorder,FloatTitle:SessionMgrTitle,FloatFooter:SessionMgrFooter"

--- Idempotent. Called whenever a window opens, not only on ColorScheme:
--- NvChad's base46 switches themes without firing that autocmd.
function M.apply()
  for name, target in pairs(M.LINKS) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

return M
