--- A one-line text input in a float, with an optional fixed suffix (".vim")
--- drawn as virtual text: visible, never editable.
---
--- A scratch buffer in insert mode rather than buftype=prompt, so <C-w>,
--- <C-u>, pasting and the user's insert-mode habits all work.
local float = require "session-mgr.ui.float"

local M = {}

--- @param opts { rect: table, title: string|nil, footer: any, text: string|nil, suffix: string|nil, border: any, relative_win: integer|nil, zindex: integer|nil, on_change: fun(text: string)|nil, on_submit: fun(text: string), on_cancel: fun()|nil, keys: table<string, fun(text: string)>|nil }
--- @return SessionMgrFloat
function M.open(opts)
  local f = float.open {
    rect = opts.rect,
    title = opts.title,
    footer = opts.footer,
    border = opts.border,
    relative_win = opts.relative_win,
    zindex = opts.zindex or 90,
    filetype = "session-mgr-input",
  }
  vim.bo[f.buf].buftype = "nofile"
  vim.bo[f.buf].modifiable = true
  vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, { opts.text or "" })

  local suffix_id
  local function text()
    return vim.api.nvim_buf_get_lines(f.buf, 0, 1, false)[1] or ""
  end
  local function draw_suffix()
    if opts.suffix then
      suffix_id = vim.api.nvim_buf_set_extmark(f.buf, float.NS, 0, #text(), {
        id = suffix_id,
        virt_text = { { opts.suffix, "SessionMgrSuffix" } },
        virt_text_pos = "inline",
        right_gravity = true,
      })
    end
  end
  draw_suffix()

  local done = false
  local function finish(cb, ...)
    if done then
      return
    end
    done = true
    vim.cmd.stopinsert()
    float.close(f)
    if cb then
      local args = { ... }
      vim.schedule(function()
        cb(unpack(args))
      end)
    end
  end

  f.set_text = function(new)
    vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, { new })
    draw_suffix()
    if vim.api.nvim_win_is_valid(f.win) then
      vim.api.nvim_win_set_cursor(f.win, { 1, #new })
    end
  end
  f.text = text
  f.cancel = function()
    finish(opts.on_cancel)
  end

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = f.buf,
    callback = function()
      -- A paste can bring newlines: keep one line.
      if vim.api.nvim_buf_line_count(f.buf) > 1 then
        local joined = table.concat(vim.api.nvim_buf_get_lines(f.buf, 0, -1, false), " ")
        vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, { joined })
      end
      draw_suffix()
      if opts.on_change and not f.silent then
        opts.on_change(text())
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = f.buf,
    once = true,
    callback = function()
      finish(opts.on_cancel)
    end,
  })

  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = f.buf, nowait = true })
  end
  map({ "i", "n" }, "<CR>", function()
    finish(opts.on_submit, text())
  end)
  map({ "i", "n" }, "<C-c>", f.cancel)
  map({ "i", "n" }, "<Esc>", f.cancel)
  for lhs, fn in pairs(opts.keys or {}) do
    map({ "i", "n" }, lhs, function()
      fn(text())
    end)
  end

  vim.api.nvim_win_set_cursor(f.win, { 1, #text() })
  vim.cmd "startinsert!"
  return f
end

return M
