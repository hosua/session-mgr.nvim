--- Send a signal to a list of processes, each checked first against the
--- start time we sampled, so a pid the kernel has since handed to some other
--- process is skipped instead of killed.
local parse = require "session-mgr.procs.parse"

local M = {}

local function start_of(pid)
  local f = io.open("/proc/" .. pid .. "/stat", "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  local st = parse.stat(text)
  return st and st.start
end

--- @param targets { pid: integer, start: integer|nil }[]
--- @param sig "sigterm"|"sigkill"
--- @return { sent: integer[], gone: integer[], failed: { pid: integer, err: string }[] }
function M.send(targets, sig)
  local res = { sent = {}, gone = {}, failed = {} }
  for _, t in ipairs(targets) do
    local now = start_of(t.pid)
    if not now then
      table.insert(res.gone, t.pid)
    elseif t.start and now ~= t.start then
      table.insert(res.failed, { pid = t.pid, err = "pid now belongs to another process, skipped" })
    else
      local ok, err, name = vim.uv.kill(t.pid, sig)
      if ok == 0 then
        table.insert(res.sent, t.pid)
      elseif name == "ESRCH" then
        table.insert(res.gone, t.pid)
      else
        table.insert(res.failed, { pid = t.pid, err = name or tostring(err) })
      end
    end
  end
  return res
end

return M
