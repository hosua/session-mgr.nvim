--- What would be lost if every buffer were wiped right now?
---
--- Only relevant for load.replace = true: an additive :source closes windows
--- but keeps hidden buffers, so it loses nothing.
local M = {}

--- @class SessionMgrLoss
--- @field modified { bufnr: integer, name: string }[] writable with :wall
--- @field unnamed { bufnr: integer, name: string }[] modified but have no file name
--- @field terminals { bufnr: integer, name: string }[] with a running job

--- @return SessionMgrLoss
function M.collect()
  local loss = { modified = {}, unnamed = {}, terminals = {} }
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local bt, name = vim.bo[b].buftype, vim.api.nvim_buf_get_name(b)
      if bt == "terminal" then
        local chan = vim.bo[b].channel
        if chan and chan > 0 and vim.fn.jobwait({ chan }, 0)[1] == -1 then
          table.insert(loss.terminals, { bufnr = b, name = name })
        end
      elseif vim.bo[b].modified and (bt == "" or bt == "acwrite") then
        local short = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
        table.insert(name ~= "" and loss.modified or loss.unnamed, { bufnr = b, name = short })
      end
    end
  end
  return loss
end

--- @param loss SessionMgrLoss
--- @return boolean
function M.is_clean(loss)
  return #loss.modified == 0 and #loss.unnamed == 0 and #loss.terminals == 0
end

--- Ask what to do. Calls back with "write", "discard" or nil (cancel).
--- Replaced by a float in ui/confirm; kept as a function field so tests can stub it.
--- @param loss SessionMgrLoss
--- @param cb fun(choice: "write"|"discard"|nil)
function M.ask(loss, cb)
  local lines = {}
  for _, b in ipairs(loss.modified) do
    lines[#lines + 1] = "  modified   " .. b.name
  end
  for _, b in ipairs(loss.unnamed) do
    lines[#lines + 1] = "  modified   [No Name] (cannot be written)"
  end
  for _, b in ipairs(loss.terminals) do
    lines[#lines + 1] = "  terminal   " .. b.name .. " (job will be killed)"
  end
  local can_write = #loss.unnamed == 0 and #loss.modified > 0
  local prompt = "Loading replaces every buffer:\n" .. table.concat(lines, "\n")
  local choices = can_write and "&Write all and load\n&Discard and load\n&Cancel" or "&Discard and load\n&Cancel"
  local n = vim.fn.confirm(prompt, choices, can_write and 3 or 2, "Warning")
  local map = can_write and { "write", "discard" } or { "discard" }
  cb(map[n])
end

return M
