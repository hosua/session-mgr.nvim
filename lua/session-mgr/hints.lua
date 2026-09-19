--- Find the key the user actually mapped to a :SessionMgr subcommand, so
--- messages can say "or <leader>sl" and be right. Works for command-string
--- maps ("<cmd>SessionMgr load<cr>"); a Lua-callback map has no inspectable
--- rhs, which is why the README suggests the string form.
local M = {}

--- @param maps table[] as returned by nvim_get_keymap
--- @param sub string subcommand, e.g. "load"
--- @param leader string|nil vim.g.mapleader
--- @return string|nil lhs in <leader> notation
function M.find(maps, sub, leader)
  local want = ("<cmd>sessionmgr %s<cr>"):format(sub:lower())
  local hits = {}
  for _, m in ipairs(maps) do
    local rhs = type(m.rhs) == "string" and m.rhs:lower():gsub("^:", "<cmd>"):gsub("%s+", " ") or ""
    if rhs == want then
      -- `lhs` from nvim_get_keymap is already printable ("<F5>", " sl");
      -- only the leader prefix needs rewriting. A space leader can show up
      -- either literally or as <Space>.
      local lhs = m.lhs
      local spelled = leader == " " and "<Space>" or nil
      if leader and leader ~= "" and vim.startswith(lhs, leader) then
        lhs = "<leader>" .. lhs:sub(#leader + 1)
      elseif spelled and vim.startswith(lhs, spelled) then
        lhs = "<leader>" .. lhs:sub(#spelled + 1)
      end
      hits[#hits + 1] = lhs
    end
  end
  table.sort(hits, function(a, b)
    return #a == #b and a < b or #a < #b
  end)
  return hits[1]
end

--- @param sub string
--- @return string|nil
function M.key_for(sub)
  local cfg = require("session-mgr.config").get()
  if sub == "load" and cfg.hints.load_key then
    return cfg.hints.load_key
  end
  return M.find(vim.api.nvim_get_keymap "n", sub, vim.g.mapleader)
end

return M
