--- :checkhealth session-mgr
local M = {}

function M.check()
  local h = vim.health
  h.start "session-mgr"
  if vim.fn.has "nvim-0.11" == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error "Neovim >= 0.11 is required"
  end
  -- Which copy is loaded matters when a dev checkout and a lazy clone coexist.
  local src = debug.getinfo(require("session-mgr").setup, "S").source:gsub("^@", "")
  h.info("loaded from " .. vim.fn.fnamemodify(src, ":~"))
end

return M
