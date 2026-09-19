--- :SessionMgr <sub> [args] dispatcher and its completion.
local M = {}

--- @type table<string, fun(args: string[], bang: boolean)>
M.subcommands = {}

--- @param fargs string[]
--- @param bang boolean
function M.dispatch(fargs, bang)
  local sub = fargs[1]
  local fn = sub and M.subcommands[sub]
  if not fn then
    local names = vim.tbl_keys(M.subcommands)
    table.sort(names)
    vim.notify(
      ("session-mgr: unknown subcommand %q (have: %s)"):format(tostring(sub), table.concat(names, ", ")),
      vim.log.levels.ERROR
    )
    return
  end
  fn(vim.list_slice(fargs, 2), bang)
end

--- @return string[]
function M.complete(arglead, cmdline, _)
  local words = vim.split(cmdline, "%s+")
  if #words > 2 then
    return {}
  end
  local names = vim.tbl_keys(M.subcommands)
  table.sort(names)
  return vim.tbl_filter(function(n)
    return vim.startswith(n, arglead)
  end, names)
end

return M
