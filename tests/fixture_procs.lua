--- A small, realistic process table: two TUI nvims with embedded servers and
--- LSPs, a headless nvim, a leaked bash-language-server with a child, and
--- unrelated noise (init, bash, a tmux server whose comm has a space).
local parse = require "session-mgr.procs.parse"
local F = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:gsub("^@", ""), ":p:h")
F.ps_text = table.concat(vim.fn.readfile(root .. "/fixtures/procs/ps.txt"), "\n")
F.mason = "/srv/u/.local/share/nvim/mason"

function F.sample(extra)
  return vim.tbl_extend("force", { t = 10, records = parse.ps(F.ps_text) }, extra or {})
end

function F.forest(opts, extra)
  return require("session-mgr.procs.tree").build(
    F.sample(extra),
    vim.tbl_extend("force", { mason = F.mason, memory = "rss" }, opts or {})
  )
end

return F
