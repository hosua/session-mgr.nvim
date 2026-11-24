-- Minimal init for tests/smoke/autoload.sh: this checkout, a throwaway store,
-- and a project of its own (the .session-root marker the script writes).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
for _, p in ipairs {
  vim.env.POPUP_DIR or "",
  vim.fn.expand "~/dev/hosua/nvim/submodules/popup.nvim",
  vim.fn.expand "~/dev/hosua/nvim/popup.nvim",
  vim.fn.expand "~/dev/popup.nvim",
} do
  if p and p ~= "" and vim.uv.fs_stat(p) then
    vim.opt.runtimepath:append(p)
    break
  end
end
vim.o.swapfile = false
vim.g.mapleader = " "
require("session-mgr").setup {
  root = vim.env.SMOKE_ROOT .. "/sessions",
  keymaps = true,
  migrate_legacy = false,
  autosave_interval = 0,
}
