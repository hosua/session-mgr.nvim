--- :SessionMgr <sub>[!] [args] dispatcher and its completion.
---
--- `!` may follow the subcommand (`:SessionMgr save!`) or the command
--- (`:SessionMgr! save`); both mean "the default session, no questions".
local M = {}

local function notify(msg, level)
  require("session-mgr.session").notify(msg, level)
end

local function report(ok, err, done)
  if ok then
    notify(done)
  else
    notify(tostring(err), vim.log.levels.ERROR)
  end
end

--- @type table<string, fun(args: string[], bang: boolean)>
M.subcommands = {
  save = function(args, bang)
    local sm = require "session-mgr"
    if bang or #args > 0 then
      return sm.save(table.concat(args, " "))
    end
    vim.ui.input(
      { prompt = "Save session as (.vim): ", default = sm.active() and sm.active().name or "" },
      function(name)
        if name and name ~= "" then
          sm.save(name)
        end
      end
    )
  end,
  load = function(args, bang)
    local sm = require "session-mgr"
    if bang or #args > 0 then
      return sm.load(table.concat(args, " "))
    end
    require("session-mgr.ui.picker").open "project"
  end,
  all = function()
    require("session-mgr.ui.picker").open "all"
  end,
  delete = function(args)
    if #args ~= 1 then
      return notify("Usage: :SessionMgr delete {name}", vim.log.levels.ERROR)
    end
    local ok, err = require("session-mgr").delete(args[1])
    report(ok, err, "Deleted " .. args[1])
  end,
}

M.subcommands.rename = function(args)
  if #args ~= 2 then
    return notify("Usage: :SessionMgr rename {old} {new}", vim.log.levels.ERROR)
  end
  local ok, err = require("session-mgr").rename(args[1], args[2])
  report(ok, err, ("Renamed %s to %s"):format(args[1], args[2]))
end

local BANG_OK = { save = true, load = true }
local TAKES_NAME = { save = true, load = true, rename = true, delete = true }

--- @param fargs string[]
--- @param bang boolean
function M.dispatch(fargs, bang)
  local sub = fargs[1] or ""
  if sub:sub(-1) == "!" then
    sub, bang = sub:sub(1, -2), true
  end
  local fn = M.subcommands[sub]
  if not fn then
    local names = vim.tbl_keys(M.subcommands)
    table.sort(names)
    return notify(
      ("Unknown subcommand %q (have: %s)"):format(fargs[1] or "", table.concat(names, ", ")),
      vim.log.levels.ERROR
    )
  end
  if bang and not BANG_OK[sub] then
    return notify(("%s does not take !"):format(sub), vim.log.levels.ERROR)
  end
  fn(vim.list_slice(fargs, 2), bang)
end

local function starting_with(list, lead)
  return vim.tbl_filter(function(n)
    return vim.startswith(n, lead)
  end, list)
end

--- @return string[]
function M.complete(arglead, cmdline, _)
  local words = vim.split(vim.trim(cmdline), "%s+")
  local n = #words + (cmdline:match "%s$" and 1 or 0) -- index of the word being completed
  if n <= 2 then
    local subs = vim.tbl_keys(M.subcommands)
    vim.list_extend(subs, { "save!", "load!" })
    table.sort(subs)
    return starting_with(subs, arglead)
  end
  local sub = (words[2] or ""):gsub("!$", "")
  if TAKES_NAME[sub] and (n == 3) then
    return starting_with(require("session-mgr").names(), arglead)
  end
  return {}
end

return M
