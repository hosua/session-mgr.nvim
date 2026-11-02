-- The Processes tab against real processes. It only ever signals processes
-- this test started, and checks they are its own descendants first.
local real = vim.fn.expand "~/.local/share/nvim"
assert(not vim.startswith(vim.fn.stdpath "data", real), "refusing to run against real data")

local picker = require "session-mgr.ui.picker"
local pm = require "session-mgr.ui.procs_model"

vim.notify = function() end

local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "x", false)
end
local function wait_for(fn, ms)
  ok(vim.wait(ms or 5000, fn, 20), "timed out")
end
local function alive(pid)
  return vim.uv.kill(pid, 0) == 0
end

if vim.fn.isdirectory "/proc/self" == 0 then
  return
end

describe("procs tab", function()
  require("session-mgr").setup { root = tmpdir(), picker = { refresh_ms = 0 }, procs = { refresh_ms = 0 } }
  -- A child nvim with a grandchild we can recognise by its argument.
  local marker = "31415" .. tostring(vim.fn.getpid() % 1000)
  local job = vim.fn.jobstart({
    "nvim",
    "--headless",
    "--clean",
    "--cmd",
    ("call jobstart(['sleep', '%s'])"):format(marker),
  }, { pty = false })
  local child = vim.fn.jobpid(job)
  local function grandchild()
    local out = vim.fn.system { "pgrep", "-P", tostring(child), "-f", "sleep " .. marker }
    return tonumber(vim.split(out, "\n")[1])
  end
  wait_for(function()
    return grandchild() ~= nil
  end)
  local gc = grandchild()

  local p = picker.open "procs"
  wait_for(function()
    return p.procs.forest ~= nil and p.procs.forest.by_id[tostring(child)] ~= nil
  end)

  it("nests the child nvim under us and its job under it, with memory", function()
    local f = p.procs.forest
    local node = f.by_id[tostring(child)]
    eq(vim.fn.getpid(), node.parent.pid)
    eq(gc, node.children[1].pid)
    ok(node.own > 0 and node.tree >= node.own)
    eq(true, node.own_session)
  end)

  it("renders the Processes tab with a fold box and the footer", function()
    local text = table.concat(vim.api.nvim_buf_get_lines(p.float.buf, 0, -1, false), "\n")
    ok(text:find "Processes", text)
    ok(text:find "%[[+-]%]nvim", text)
  end)

  it("X on a mark kills the whole subtree after the confirm", function()
    assert(vim.uv.os_getppid ~= nil)
    p.procs = pm.reduce(p.procs, { type = "clear_marks" })
    p.procs.marks[tostring(child)] = true
    keys "X"
    wait_for(function()
      return vim.bo[vim.api.nvim_get_current_buf()].filetype == "session-mgr"
        and vim.api.nvim_get_current_win() ~= p.float.win
    end)
    local confirm_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    ok(confirm_text:find(tostring(child), 1, true), confirm_text)
    ok(confirm_text:find("2 processes", 1, true), confirm_text)
    keys "X"
    wait_for(function()
      return not alive(child) and not alive(gc)
    end)
    vim.fn.jobwait({ job }, 1000)
  end)

  it("the tab survives a refresh after the kill and drops the dead mark", function()
    wait_for(function()
      return p.procs.forest and p.procs.forest.by_id[tostring(child)] == nil
    end)
    eq({}, p.procs.marks)
  end)

  it("Tab cycles back to the session tabs and stops sampling", function()
    keys "<Tab>"
    eq("project", p.tab)
    eq(nil, p.procs_timer)
  end)
  picker.close()
  pcall(vim.fn.jobstop, job)
end)
