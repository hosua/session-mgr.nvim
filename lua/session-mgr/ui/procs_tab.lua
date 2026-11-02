--- Glue for the Processes tab inside the picker: sampling on a timer,
--- painting, and the x / X kill flow. `p` is the picker's open state table
--- (ui/picker.lua); this module owns p.procs, p.procs_prev and p.procs_timer.
local collect = require "session-mgr.procs.collect"
local config = require "session-mgr.config"
local confirm = require "session-mgr.ui.confirm"
local float = require "session-mgr.ui.float"
local layout = require "session-mgr.ui.layout"
local parse = require "session-mgr.procs.parse"
local paths = require "session-mgr.paths"
local pm = require "session-mgr.ui.procs_model"
local preview = require "session-mgr.ui.procs_preview"
local render = require "session-mgr.ui.procs_render"
local signal = require "session-mgr.procs.signal"
local tree = require "session-mgr.procs.tree"

local M = {}

local function notify(msg, level)
  require("session-mgr.session").notify(msg, level)
end

local function build_opts()
  local cfg = config.get().procs
  return {
    own_pid = vim.fn.getpid(),
    mason = cfg.orphans and (vim.fn.stdpath "data" .. "/mason") or nil,
    orphans = cfg.orphans,
    memory = cfg.memory,
  }
end

--- Paint the tab into the picker's windows. Mirrors picker.redraw for the
--- session tabs.
function M.redraw(p)
  if not float.is_open(p.float) then
    return
  end
  local cfg = config.get()
  local pcfg = vim.tbl_extend("force", cfg.picker, { preview = cfg.picker.preview and p.show_preview })
  local editor = float.editor()
  -- Leave the preview its share before sizing the command column.
  local max_w = math.max(20, math.floor(editor.width * pcfg.max_width) - 2)
  local avail = max_w
  if pcfg.preview and editor.width >= pcfg.preview_min_columns then
    avail = max_w - 2 - math.max(30, math.floor(max_w * pcfg.preview_width))
  end
  local ropts = { home = vim.env.HOME, max_width = avail, big_kb = cfg.procs.big_mb * 1024 }
  local out = render.render(p.procs, ropts)
  local rects =
    layout.compute({ width = out.width, list_lines = out.list_lines, chrome = render.CHROME_LINES }, editor, pcfg)
  if rects.list_height ~= p.procs.height then
    p.procs = pm.reduce(p.procs, { type = "resize", height = rects.list_height })
    out = render.render(p.procs, ropts)
  end
  float.configure(p.float, rects.list, out.title, out.footer)
  float.paint(p.float, out)
  p.out = out

  if rects.preview then
    if not float.is_open(p.preview) then
      p.preview = float.open { rect = rects.preview, title = "", enter = false, focusable = false, zindex = 59 }
    end
    local pv = preview.build(pm.current(p.procs), {
      width = rects.preview.width,
      height = rects.preview.height,
      home = vim.env.HOME,
      memory = p.procs.forest and p.procs.forest.memory or cfg.procs.memory,
    })
    float.configure(p.preview, rects.preview, pv.title, nil)
    float.paint(p.preview, pv)
  elseif p.preview then
    float.close(p.preview)
    p.preview = nil
  end
  if p.hover_row and out.lines[p.hover_row + 1] and p.hover_row ~= out.cursor_row then
    vim.api.nvim_buf_set_extmark(
      p.float.buf,
      float.NS,
      p.hover_row,
      0,
      { line_hl_group = "SessionMgrHover", priority = 150 }
    )
  end
  pcall(vim.api.nvim_win_set_cursor, p.float.win, { (out.cursor_row or render.CHROME_LINES) + 1, 0 })
  vim.api.nvim_win_call(p.float.win, function()
    vim.fn.winrestview { topline = 1, leftcol = 0 }
  end)
end

--- Take a sample and repaint. Overlapping samples are dropped, not queued.
function M.refresh(p)
  if p.procs_busy then
    return
  end
  local ok, why = collect.supported()
  if not ok then
    p.procs = pm.reduce(p.procs, { type = "set_forest", error = why })
    return require("session-mgr.ui.picker").redraw()
  end
  p.procs_busy = true
  local opts = build_opts()
  collect.run(opts, function(sample, err)
    p.procs_busy = false
    local picker = require "session-mgr.ui.picker"
    if picker.current() ~= p or not float.is_open(p.float) then
      return
    end
    if not sample then
      p.procs = pm.reduce(p.procs, { type = "set_forest", error = err })
    else
      opts.prev = p.procs_prev
      p.procs_prev = sample
      p.procs = pm.reduce(p.procs, { type = "set_forest", forest = tree.build(sample, opts) })
    end
    if p.tab == "procs" then
      picker.redraw()
    end
  end)
end

function M.activate(p)
  local cfg = config.get().procs
  p.procs = p.procs or pm.new { sort = cfg.default_sort }
  M.refresh(p)
  if cfg.refresh_ms > 0 and not p.procs_timer then
    p.procs_timer = vim.uv.new_timer()
    p.procs_timer:start(
      cfg.refresh_ms,
      cfg.refresh_ms,
      vim.schedule_wrap(function()
        -- Paused under a confirm, so the rows do not shift while you read it.
        if require("session-mgr.ui.picker").current() == p and p.tab == "procs" and not p.child then
          M.refresh(p)
        end
      end)
    )
  end
end

function M.deactivate(p)
  if p.procs_timer then
    p.procs_timer:stop()
    p.procs_timer:close()
    p.procs_timer = nil
  end
end

--- pids that would take this editor down with them: our own pid and every
--- ancestor inside the forest (the TUI client above an --embed server).
local function lifeline(forest)
  local set = {}
  local n = forest and forest.by_id[tostring(vim.fn.getpid())]
  while n do
    if n.pid then
      set[n.pid] = true
    end
    n = n.parent
  end
  return set
end

local MAX_LISTED = 8

--- x / X: confirm, then signal.
--- @param mode "term"|"kill_tree"
function M.kill(p, mode)
  local picker = require "session-mgr.ui.picker"
  local state = p.procs
  local nodes, pids, kb = pm.targets(state, mode)
  if #pids == 0 then
    return notify("Nothing to signal on this row", vim.log.levels.WARN)
  end
  local sig = mode == "term" and "SIGTERM" or "SIGKILL"
  local key = mode == "term" and "x" or "X"
  local forest = state.forest
  local self_pids = lifeline(forest)
  local suicide = false
  for _, pid in ipairs(pids) do
    suicide = suicide or self_pids[pid] == true
  end

  local lines = {}
  for i, n in ipairs(nodes) do
    if i > MAX_LISTED then
      lines[#lines + 1] = { { ("  … and %d more"):format(#nodes - MAX_LISTED), "SessionMgrDim" } }
      break
    end
    local extra = mode == "kill_tree" and n.descendants > 0 and ("  +%d below"):format(n.descendants) or ""
    local where = n.depth == 0 and n.cwd and ("  " .. paths.display_path(n.cwd, vim.env.HOME, 30)) or ""
    lines[#lines + 1] = {
      { ("  %7d  "):format(n.pid), "SessionMgrIndex" },
      { vim.fn.strcharpart(n.proc.args, 0, 40), "SessionMgrName" },
      { where, "SessionMgrPreviewPath" },
      { extra, "SessionMgrDim" },
      { "  " .. parse.size(mode == "kill_tree" and n.tree or n.own), "SessionMgrWarn" },
    }
  end
  lines[#lines + 1] = {}
  lines[#lines + 1] = {
    { ("  %d process%s, about %s freed"):format(#pids, #pids == 1 and "" or "es", parse.size(kb)), "SessionMgrDim" },
  }
  if mode == "term" then
    lines[#lines + 1] = { { "  nvim exits cleanly and stops its own language servers", "SessionMgrDim" } }
  else
    lines[#lines + 1] = { { "  SIGKILL: unsaved buffers in these nvims are lost", "SessionMgrDanger" } }
  end
  if suicide then
    lines[#lines + 1] = { { "  ! this includes the nvim you are typing in", "SessionMgrDanger" } }
  end

  local function fire()
    local targets = {}
    for _, pid in ipairs(pids) do
      local n = forest and forest.by_id[tostring(pid)]
      targets[#targets + 1] = { pid = pid, start = n and n.start }
    end
    local res = signal.send(targets, sig:lower())
    local msg = ("Sent %s to %d process%s"):format(sig, #res.sent, #res.sent == 1 and "" or "es")
    if #res.gone > 0 then
      msg = msg .. (" (%d already gone)"):format(#res.gone)
    end
    notify(msg)
    for _, f in ipairs(res.failed) do
      notify(("Not signalled %d: %s"):format(f.pid, f.err), vim.log.levels.ERROR)
    end
    if picker.current() == p then
      p.procs = pm.reduce(p.procs, { type = "clear_marks" })
      M.refresh(p)
      -- Processes take a moment to exit after SIGTERM.
      vim.defer_fn(function()
        if picker.current() == p and p.tab == "procs" then
          M.refresh(p)
        end
      end, 700)
    end
  end

  picker.with_child(function(done)
    confirm.open {
      title = ("Send %s?"):format(sig),
      danger = true,
      lines = lines,
      choices = { { key = key, label = "send " .. sig, value = true, danger = true } },
      on_choice = function(yes)
        if not yes then
          return done()
        end
        if not suicide then
          done()
          return fire()
        end
        confirm.open {
          title = "Really kill this nvim?",
          danger = true,
          lines = { { { "  Your current editor will close. Unsaved work here is lost.", "SessionMgrDanger" } } },
          choices = { { key = "y", label = "yes, kill it", value = true, danger = true } },
          on_choice = function(really)
            done()
            if really then
              fire()
            end
          end,
        }
      end,
    }
  end)
end

return M
