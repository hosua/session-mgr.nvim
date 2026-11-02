-- Hermetic init for the autoload and new-session tapes: this checkout, an empty
-- sessions store under DEMO_ROOT, no seeded sessions. Set by docs/tapes/capture.sh.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.g.mapleader = " "
require("session-mgr").setup {
  root = vim.env.DEMO_ROOT .. "/sessions",
  keymaps = true,
  migrate_legacy = false,
  picker = { refresh_ms = 0 },
}
