--- Text in, tables out: `ps` output, /proc/<pid>/smaps_rollup, and memory
--- sizes for display. Pure, so every format quirk is a plain string test.
local M = {}

--- The exact `ps` invocation parse.ps() understands. `comm:16` pins comm to
--- a fixed width: comm may contain spaces ("tmux: server"), so it cannot be
--- split on whitespace, but a fixed column can be cut by position.
M.PS_ARGS = {
  "ps",
  "-eo",
  "pid=,ppid=,rss=,nlwp=,times=,etimes=,user:32=,comm:16=,args=",
}
local COMM_WIDTH = 16

--- @class SessionMgrProc
--- @field pid integer
--- @field ppid integer
--- @field rss integer kB
--- @field threads integer
--- @field cputime integer cumulative CPU seconds (user + system)
--- @field elapsed integer seconds since the process started
--- @field user string
--- @field comm string
--- @field args string

--- @param text string
--- @return SessionMgrProc[]
function M.ps(text)
  local out = {}
  for line in text:gmatch "[^\n]+" do
    local pid, ppid, rss, nlwp, times, etimes, user, rest =
      line:match "^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s+()"
    if rest then
      local comm = vim.trim(line:sub(rest, rest + COMM_WIDTH - 1))
      local args = vim.trim(line:sub(rest + COMM_WIDTH + 1))
      out[#out + 1] = {
        pid = tonumber(pid),
        ppid = tonumber(ppid),
        rss = tonumber(rss),
        threads = tonumber(nlwp),
        cputime = tonumber(times),
        elapsed = tonumber(etimes),
        user = user,
        comm = comm,
        args = args ~= "" and args or comm,
      }
    end
  end
  return out
end

--- @param text string contents of /proc/<pid>/smaps_rollup
--- @return { pss: integer, rss: integer, swap: integer }|nil kB, nil when Pss is missing
function M.smaps_rollup(text)
  local function field(name)
    return tonumber(text:match("\n" .. name .. ":%s+(%d+) kB") or text:match("^" .. name .. ":%s+(%d+) kB"))
  end
  local pss = field "Pss"
  if not pss then
    return nil
  end
  return { pss = pss, rss = field "Rss" or 0, swap = field "Swap" or 0 }
end

--- @param text string contents of /proc/<pid>/stat
--- @return { ticks: integer, start: integer }|nil CPU ticks used (utime + stime) and start time in ticks since boot
function M.stat(text)
  -- comm sits in parentheses and may itself contain ") ", so cut after the LAST one.
  local tail = text:match ".*%)%s+(.*)"
  if not tail then
    return nil
  end
  local f = vim.split(vim.trim(tail), "%s+")
  -- f[1] is field 3 (state), so field n is f[n - 2].
  local utime, stime, start = tonumber(f[12]), tonumber(f[13]), tonumber(f[20])
  if not (utime and stime and start) then
    return nil
  end
  return { ticks = utime + stime, start = start }
end

--- kB -> "9.3G", "283M", "4.0K". Two significant digits below 10, so a
--- column of sizes stays at most 4 cells wide.
--- @param kb integer|nil
--- @return string
function M.size(kb)
  if not kb then
    return "?"
  end
  local units = { "K", "M", "G", "T" }
  local v, i = kb, 1
  while v >= 999.5 and i < #units do
    v, i = v / 1024, i + 1
  end
  if v < 10 then
    return ("%.1f%s"):format(v, units[i])
  end
  return ("%d%s"):format(math.floor(v + 0.5), units[i])
end

return M
