local F = require "fixture_procs"
local parse = require "session-mgr.procs.parse"

describe("procs.parse.ps", function()
  local recs = parse.ps(F.ps_text)
  local by = {}
  for _, r in ipairs(recs) do
    by[r.pid] = r
  end
  it("reads every line", function()
    eq(13, #recs)
  end)
  it("reads numbers and the fixed-width comm", function()
    eq({
      pid = 201,
      ppid = 200,
      rss = 9805404,
      threads = 5,
      cputime = 1446,
      elapsed = 524794,
      user = "hoswoo",
      comm = "nvim",
      args = "nvim --embed",
    }, by[201])
  end)
  it("keeps a comm with a space apart from args", function()
    eq("tmux: server", by[500].comm)
    eq("tmux new -s x", by[500].args)
  end)
  it("skips junk lines", function()
    eq({}, parse.ps "garbage\n\n  12 nope")
  end)
end)

describe("procs.parse.smaps_rollup", function()
  it("reads Pss, Rss and Swap in kB", function()
    local text =
      "5555-7fff ---p 00000000 00:00 0  [rollup]\nRss:  4236 kB\nPss:  4232 kB\nPss_Dirty: 552 kB\nSwap:  8 kB\n"
    eq({ pss = 4232, rss = 4236, swap = 8 }, parse.smaps_rollup(text))
  end)
  it("returns nil without a Pss line", function()
    eq(nil, parse.smaps_rollup "")
  end)
end)

describe("procs.parse.stat", function()
  it("finds utime+stime and starttime after a comm with ') ' in it", function()
    local text = "42 (a) b) R 1 42 1 0 -1 4194304 98 0 0 0 7 3 0 0 20 0 1 0 188326852 6610944 589"
    eq({ ticks = 10, start = 188326852 }, parse.stat(text))
  end)
  it("returns nil on garbage", function()
    eq(nil, parse.stat "nope")
  end)
end)

describe("procs.parse.size", function()
  it("formats kB in at most four cells", function()
    eq("4.0K", parse.size(4))
    eq("283M", parse.size(283000 * 1.024))
    eq("9.4G", parse.size(9805404))
    eq("1.0M", parse.size(1023))
    eq("?", parse.size(nil))
  end)
end)
