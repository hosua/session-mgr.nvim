-- Minimal init for tmux smoke tests: this checkout, a seeded throwaway store.
-- SMOKE_ROOT (a temp dir) is set by the calling script.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.g.mapleader = " "
local sessions = vim.env.SMOKE_ROOT .. "/sessions"
require("session-mgr").setup { root = sessions, keymaps = true, migrate_legacy = false, picker = { refresh_ms = 0 } }

local store, project = require "session-mgr.store", require "session-mgr.project"
local now = os.time()
local function seed(dir, names, is_git)
  local p = project.from_root(dir, is_git)
  vim.fn.mkdir(sessions .. "/" .. p.key, "p")
  for i, name in ipairs(names) do
    vim.fn.writefile({ "cd " .. dir, "badd +1 a.txt", "edit a.txt" }, sessions .. "/" .. p.key .. "/" .. name .. ".vim")
    store.touch_saved(sessions, p, name, now - i * 4000)
    if i % 2 == 0 then
      store.touch_loaded(sessions, p, name, now - i * 50)
    end
  end
end
local here = vim.uv.fs_realpath(vim.env.SMOKE_ROOT .. "/work")
seed(here, { "default", "abc", "cool", "cooli", "coolio" }, false)
seed("/srv/other-repo", { "cool", "zeta" }, true)
vim.cmd.cd(here)
vim.cmd "edit a.txt"
