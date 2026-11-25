-- Hermetic init for the autoload and new-session tapes: this checkout, an empty
-- sessions store under DEMO_ROOT, no seeded sessions. Set by docs/tapes/capture.sh.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
for _, p in ipairs {
  vim.env.POPUP_DIR or "",
  vim.fn.expand "~/dev/hosua/nvim/submodules/popup.nvim",
  vim.fn.expand "~/dev/hosua/nvim/popup.nvim",
} do
  if p ~= "" and vim.uv.fs_stat(p) then
    vim.opt.runtimepath:append(p)
    break
  end
end
for _, p in ipairs {
  vim.env.PLENARY_DIR or "",
  vim.fn.stdpath "data" .. "/lazy/plenary.nvim",
  vim.fn.expand "~/.local/share/nvim/lazy/plenary.nvim",
  root .. "/.tests/plenary.nvim",
} do
  if p ~= "" and vim.uv.fs_stat(p) then
    vim.opt.runtimepath:append(p)
    break
  end
end
vim.o.swapfile = false
vim.g.mapleader = " "
require("session-mgr").setup {
  root = vim.env.DEMO_ROOT .. "/sessions",
  keymaps = true,
  migrate_legacy = false,
  picker = { refresh_ms = 0 },
}
