--- The timer behind `autosave_interval`. Each tick writes autosave.vim via
--- session.autosave(). A tick that lands while you type, run a command or
--- have a float focused (the picker, a confirm) waits RETRY_MS and tries
--- again, so a save never runs in the middle of something.
local M = {}

local RETRY_MS = 5000

--- @type uv.uv_timer_t|nil
local timer
local retrying = false

local function busy()
  if vim.api.nvim_get_mode().mode ~= "n" or vim.fn.getcmdwintype() ~= "" then
    return true
  end
  return vim.api.nvim_win_get_config(0).relative ~= ""
end

local function tick()
  if busy() then
    if not retrying then
      retrying = true
      vim.defer_fn(function()
        retrying = false
        if timer then
          tick()
        end
      end, RETRY_MS)
    end
    return
  end
  require("session-mgr.session").autosave()
end

--- @param every_ms integer
function M.start(every_ms)
  M.stop()
  timer = assert(vim.uv.new_timer())
  timer:start(every_ms, every_ms, vim.schedule_wrap(tick))
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

--- @return boolean
function M.running()
  return timer ~= nil
end

return M
