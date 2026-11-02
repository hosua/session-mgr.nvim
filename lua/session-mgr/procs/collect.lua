--- Take one process sample without blocking the editor: `ps` runs through
--- vim.system, and the /proc reads for the pids we show go through libuv's
--- async fs calls. Only pids inside an nvim tree (or an orphaned LSP) are
--- read, a few dozen out of every process on the box.
local parse = require "session-mgr.procs.parse"
local tree = require "session-mgr.procs.tree"

local M = {}

local READ_BYTES = 16384 -- /proc files report size 0; these are all well under this

local hz
--- Clock ticks per second for /proc/<pid>/stat. Asked once; 100 on every
--- Linux build in practice.
local function clock_hz()
  if not hz then
    local ok, res = pcall(function()
      return vim.system({ "getconf", "CLK_TCK" }, { text = true }):wait(1000)
    end)
    hz = ok and res.code == 0 and tonumber(vim.trim(res.stdout or "")) or 100
  end
  return hz
end

--- @return boolean ok, string|nil why not
function M.supported()
  if vim.fn.isdirectory "/proc/self" == 0 then
    return false, "the Processes tab needs /proc (Linux)"
  end
  if vim.fn.executable "ps" == 0 then
    return false, "the Processes tab needs `ps` (procps-ng)"
  end
  return true
end

local function read_file(path, cb)
  vim.uv.fs_open(path, "r", 438, function(err, fd)
    if err or not fd then
      return cb(nil)
    end
    vim.uv.fs_read(fd, READ_BYTES, 0, function(rerr, data)
      vim.uv.fs_close(fd)
      cb(not rerr and data or nil)
    end)
  end)
end

--- @param opts { mason: string|nil, orphans: boolean|nil, memory: "pss"|"rss" }
--- @param cb fun(sample: SessionMgrSample|nil, err: string|nil) called on the main loop
function M.run(opts, cb)
  local done = vim.schedule_wrap(cb)
  local ticks_per_s = clock_hz()
  local proc
  local ok, err = pcall(function()
    proc = vim.system(parse.PS_ARGS, { text = true }, function(res)
      if res.code ~= 0 then
        return done(nil, ("ps failed (exit %d): %s"):format(res.code, vim.trim(res.stderr or "")))
      end
      local sample = {
        t = vim.uv.hrtime() / 1e9,
        -- Our own `ps` is a child of this nvim; it is gone by now, so leave it out.
        records = vim.tbl_filter(function(r)
          return not (proc and r.pid == proc.pid)
        end, parse.ps(res.stdout or "")),
        pss = opts.memory ~= "rss" and {} or nil,
        swap = {},
        cwd = {},
        stat = {},
        hz = ticks_per_s,
      }
      -- A records-only build tells us which pids are worth reading.
      local shape = tree.build(sample, { mason = opts.mason, orphans = opts.orphans, memory = "rss" })
      local pids = {}
      for _, node in pairs(shape.by_id) do
        if node.pid then
          pids[#pids + 1] = node.pid
        end
      end
      local pending = #pids * 3
      if pending == 0 then
        return done(sample)
      end
      local function one()
        pending = pending - 1
        if pending == 0 then
          done(sample)
        end
      end
      for _, pid in ipairs(pids) do
        local dir = "/proc/" .. pid
        -- A pid can exit between ps and these reads: each read just comes back
        -- nil and the node falls back to its ps numbers.
        if sample.pss then
          read_file(dir .. "/smaps_rollup", function(text)
            local m = text and parse.smaps_rollup(text)
            if m then
              sample.pss[pid], sample.swap[pid] = m.pss, m.swap
            end
            one()
          end)
        else
          one()
        end
        read_file(dir .. "/stat", function(text)
          sample.stat[pid] = text and parse.stat(text) or nil
          one()
        end)
        vim.uv.fs_readlink(dir .. "/cwd", function(_, path)
          sample.cwd[pid] = path
          one()
        end)
      end
    end)
  end)
  if not ok then
    done(nil, "could not run ps: " .. tostring(err))
  end
end

return M
