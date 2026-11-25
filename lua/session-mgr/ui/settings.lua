--- :SessionMgr settings. A popup.nvim list menu of the permanent options in
--- settings.json, each with its value and where the value comes from. The
--- keys are listed in the bottom border.
---
---   Enter  cycle the value and save it
---   x      reset the option: drop it from settings.json, setup() decides
---   e      open settings.json in a split for hand editing
---   q/Esc  close
local settings = require "session-mgr.settings"
local style = require "session-mgr.ui.style"

local M = {}

local HL = {
  title = "SessionMgrTitle",
  group = "SessionMgrGroup",
  label = "SessionMgrName",
  hint = "SessionMgrDim",
  mark = "SessionMgrActive",
  bullet = "SessionMgrFooterKey",
  key = "SessionMgrFooterKey",
  key_desc = "SessionMgrFooter",
  border = "SessionMgrBorder",
  warn = "SessionMgrWarn",
}

--- Where a row's value comes from, as text. Pure.
--- @param row { source: string, locked: string|nil }
--- @return string
function M.source_text(row)
  if row.locked then
    return ("setup, file ignored: %s"):format(row.locked)
  end
  return row.source == "settings" and "settings file" or "setup"
end

--- The list-menu spec for the current files. Pure given the files on disk.
--- @param pick string|nil option to start the cursor on
--- @param root string|nil
--- @return table spec without the callbacks
function M.spec(pick, root)
  local file = settings.read(root)
  local header = { require("session-mgr.paths").tilde(settings.file(root), vim.uv.os_homedir()) }
  if file.status == "error" then
    header[#header + 1] = { text = "settings.json is ignored: " .. file.err, level = "warn" }
  end
  local items = {}
  for _, row in ipairs(settings.rows(root)) do
    items[#items + 1] = {
      id = row.key,
      key = row.key,
      label = ("%-10s %s"):format(row.key, row.value),
      hint = M.source_text(row),
      level = row.locked and "warn" or nil,
      mark = row.key == pick or nil,
      row = row,
    }
  end
  return {
    title = "SessionMgr settings",
    header = header,
    groups = { { title = "Permanent options", hide_count = true, items = items } },
    select_desc = "cycle",
    keys = {
      { key = "x", desc = "reset" },
      { key = "e", desc = "edit file" },
    },
    border_legend = true,
    border = style.border() or "rounded",
    hl = HL,
  }
end

--- @param pick string|nil
--- @param root string|nil
--- @return { close: fun(), win: integer, buf: integer }|nil
function M.open(pick, root)
  require("session-mgr.hl").apply()
  local notify = require("session-mgr.session").notify
  local spec = M.spec(pick, root)

  local function reopen(key)
    vim.schedule(function()
      M.open(key, root)
    end)
  end
  local function failed(err)
    notify("Could not save the setting: " .. tostring(err), vim.log.levels.ERROR)
  end

  spec.on_select = function(item, close)
    close()
    if item.row.locked then
      notify(
        ("%s is set by setup() (%s), so settings.json cannot change it"):format(item.key, item.row.locked),
        vim.log.levels.WARN
      )
      return reopen(item.key)
    end
    local ok, err = settings.cycle(item.key, root)
    if not ok then
      failed(err)
    end
    reopen(item.key)
  end
  spec.keys[1].fn = function(item, close)
    close()
    local ok, err = settings.reset(item.key, root)
    if not ok then
      failed(err)
    end
    reopen(item.key)
  end
  spec.keys[2].fn = function(_, close)
    close()
    local path = settings.file(root)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.cmd.split(vim.fn.fnameescape(path))
  end
  return require("popup.list_menu").open(spec)
end

return M
