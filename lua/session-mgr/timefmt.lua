--- Human time formatting for the picker. Pure: `now` is always passed in.
---
---   < 1 min      Just now
---   < 1 day      largest unit + the next one down, dropped when zero:
---                5min 57s ago, 1hr 5min ago, 1hr ago   (seconds only under an hour)
---   >= 1 day     2026-09-19 07:59 (local time)
local M = {}

local MIN, HOUR, DAY = 60, 3600, 86400

--- @param now integer
--- @param ts integer|nil nil means it never happened
--- @return string
function M.relative(now, ts)
  if not ts then
    return "Never"
  end
  local d = now - ts
  if d < MIN then
    return "Just now" -- also covers small negative skews between machines
  end
  if d < HOUR then
    local m, s = math.floor(d / MIN), d % MIN
    return s > 0 and ("%dmin %ds ago"):format(m, s) or ("%dmin ago"):format(m)
  end
  if d < DAY then
    local h, m = math.floor(d / HOUR), math.floor(d % HOUR / MIN)
    return m > 0 and ("%dhr %dmin ago"):format(h, m) or ("%dhr ago"):format(h)
  end
  -- A day or older: the exact local time says more than "3 days ago".
  return M.datetime(ts)
end

--- @return string "2026-09-19 06:20", local time
function M.datetime(ts)
  return os.date("%Y-%m-%d %H:%M", ts) --[[@as string]]
end

--- @return string "2026-09-19", local time
function M.date(ts)
  return os.date("%Y-%m-%d", ts) --[[@as string]]
end

return M
