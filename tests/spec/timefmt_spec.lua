local timefmt = require "session-mgr.timefmt"
local NOW = os.time { year = 2026, month = 9, day = 19, hour = 12, min = 0, sec = 0 }

describe("timefmt.relative under a day", function()
  local cases = {
    { 0, "Just now" },
    { 59, "Just now" },
    { -30, "Just now" },
    { 60, "1m ago" },
    { 5 * 60 + 57, "5m 57s ago" },
    { 59 * 60 + 59, "59m 59s ago" },
    { 3600, "1h ago" },
    { 3600 + 32, "1h ago" }, -- never "1h 32s": no skipped units
    { 3600 + 5 * 60, "1h 5m ago" },
    { 23 * 3600 + 59 * 60 + 59, "23h 59m ago" },
  }
  for _, c in ipairs(cases) do
    it(("%ds -> %s"):format(c[1], c[2]), function()
      eq(c[2], timefmt.relative(NOW, NOW - c[1]))
    end)
  end
  it("nil -> Never", function()
    eq("Never", timefmt.relative(NOW, nil))
  end)
end)

describe("timefmt absolute", function()
  it("formats local date and datetime", function()
    eq("2026-09-19", timefmt.date(NOW))
    eq("2026-09-19 12:00", timefmt.datetime(NOW))
  end)
end)

describe("timefmt.relative from one day on", function()
  it("switches to the absolute local datetime at exactly 24h", function()
    eq("2026-09-18 12:00", timefmt.relative(NOW, NOW - 86400))
    eq("23h 59m ago", timefmt.relative(NOW, NOW - 86399))
  end)
  it("stays absolute for old timestamps", function()
    eq("2026-08-02 06:20", timefmt.relative(NOW, os.time { year = 2026, month = 8, day = 2, hour = 6, min = 20 }))
  end)
end)
