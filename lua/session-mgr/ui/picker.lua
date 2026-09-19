--- The session picker: glue between the pure model/render and real windows.
--- All decisions live in ui/model and ui/render; this file turns keys and
--- mouse events into actions, repaints, and runs load / rename / delete.
local config = require "session-mgr.config"
local confirm = require "session-mgr.ui.confirm"
local float = require "session-mgr.ui.float"
local hints = require "session-mgr.hints"
local input = require "session-mgr.ui.input"
local layout = require "session-mgr.ui.layout"
local model = require "session-mgr.ui.model"
local preview = require "session-mgr.ui.preview"
local render = require "session-mgr.ui.render"
local session = require "session-mgr.session"
local sessfile = require "session-mgr.sessfile"
local state_mod = require "session-mgr.state"
local store = require "session-mgr.store"

local M = {}

--- The one open picker, if any. @type table|nil
local P

local function rows_for(scope, project)
  local root = config.get().root
  return scope == "all" and store.list_all(root) or store.list(root, project)
end

local function project_of(row)
  return { key = row.key, root = row.root or "", label = row.label, is_git = row.is_git }
end

function M.close()
  local p = P
  if not p then
    return
  end
  P = nil
  if p.timer then
    p.timer:stop()
    p.timer:close()
  end
  pcall(vim.api.nvim_del_augroup_by_id, p.augroup)
  if p.saved_mousemoveevent ~= nil then
    vim.o.mousemoveevent = p.saved_mousemoveevent
  end
  if p.filter_input then
    float.close(p.filter_input)
  end
  float.close(p.preview)
  float.close(p.float)
end

--- Render, size the window to the content, and paint.
local function redraw()
  local p = P
  if not p or not float.is_open(p.float) then
    return
  end
  local cfg = config.get().picker
  local opts = { home = vim.env.HOME, all_key = hints.key_for "all" }
  local out = render.render(p.state, os.time(), opts)
  local rects = layout.compute(
    { width = out.width, list_lines = out.list_lines, chrome = render.CHROME_LINES + out.chrome_bottom },
    float.editor(),
    vim.tbl_extend("force", cfg, { preview = cfg.preview and p.show_preview })
  )
  if rects.list_height ~= p.state.height then
    p.state = model.reduce(p.state, { type = "resize", height = rects.list_height })
    out = render.render(p.state, os.time(), opts)
  end
  float.configure(p.float, rects.list, out.title, out.footer)
  float.paint(p.float, out)
  p.out = out

  -- Preview pane: beside the list when the editor is wide enough, else gone.
  if rects.preview then
    if not float.is_open(p.preview) then
      p.preview = float.open { rect = rects.preview, title = "", enter = false, focusable = false, zindex = 59 }
    end
    local row = model.current(p.state)
    local info, err
    if row then
      -- Parse each file once per picker; the timer repaints every second.
      p.parsed[row.file] = p.parsed[row.file] or { sessfile.parse(row.file) }
      info, err = p.parsed[row.file][1], p.parsed[row.file][2]
    end
    local pv = preview.build(
      row,
      info,
      { width = rects.preview.width, height = rects.preview.height, home = vim.env.HOME, now = os.time(), err = err }
    )
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
  -- Park the real cursor on the selected row so screen readers, :norm and
  -- the terminal cursor all agree with the highlight.
  pcall(vim.api.nvim_win_set_cursor, p.float.win, { (out.cursor_row or render.CHROME_LINES) + 1, 0 })
  -- The model does the scrolling; the window itself must never scroll, or the
  -- fixed header (and the filter input laid over row 1) would drift.
  vim.api.nvim_win_call(p.float.win, function()
    vim.fn.winrestview { topline = 1, leftcol = 0 }
  end)
end
M.redraw = redraw

local function dispatch(action)
  if P then
    P.state = model.reduce(P.state, action)
    redraw()
  end
end
M.dispatch = dispatch

local function reload_rows(scope)
  if P then
    scope = scope or P.state.scope
    dispatch { type = "set_rows", rows = rows_for(scope, P.state.project), scope = scope }
  end
end

--- Run `fn` with a child float open: the picker must not close on WinLeave.
local function with_child(fn)
  if P then
    P.child = true
    fn(function()
      if P then
        P.child = false
        if float.is_open(P.float) then
          vim.api.nvim_set_current_win(P.float.win)
        end
      end
    end)
  end
end

local function load_current()
  local row = P and model.current(P.state)
  if not row then
    return
  end
  -- Close first, then load on the next tick: sourcing a session while this
  -- float is the current window would restore the layout around it.
  M.close()
  vim.schedule(function()
    session.load(project_of(row), row.name)
  end)
end

local function rename_current()
  local row = P and model.current(P.state)
  if not row then
    return
  end
  with_child(function(done)
    input.open {
      rect = float.centered(math.max(40, #row.name + 12), 1),
      title = (" Rename %s "):format(row.name),
      footer = {
        { " ⏎", "SessionMgrFooterKey" },
        { " rename  ", "SessionMgrFooter" },
        { "esc", "SessionMgrFooterKey" },
        { " cancel ", "SessionMgrFooter" },
      },
      text = row.name,
      suffix = ".vim",
      on_cancel = done,
      on_submit = function(text)
        local clean, err = require("session-mgr.validate").name(text)
        local ok = clean ~= nil
        if ok and clean ~= row.name then
          ok, err = store.rename(config.get().root, project_of(row), row.name, clean)
          if ok and state_mod.active_in(project_of(row)) == row.name then
            state_mod.set_active(project_of(row), clean)
          end
        end
        if not ok then
          session.notify("Not renamed: " .. tostring(err), vim.log.levels.ERROR)
        end
        done()
        if P then
          P.state = model.reduce(P.state, { type = "set_active", active = state_mod.active() })
        end
        reload_rows()
      end,
    }
  end)
end

local function delete_current()
  local row = P and model.current(P.state)
  if not row then
    return
  end
  local cfg = config.get()
  local function ask(title, extra, on_yes, done)
    confirm.open {
      title = title,
      danger = true,
      lines = vim.list_extend({
        { { "  " }, { row.name .. ".vim", "SessionMgrDefault" }, { "  in " .. row.label, "SessionMgrDim" } },
        { { "  " .. vim.fn.fnamemodify(row.file, ":~"), "SessionMgrDim" } },
      }, extra),
      choices = { { key = "d", label = "delete it", value = true, danger = true } },
      on_choice = function(yes)
        if yes then
          on_yes()
        else
          done()
        end
      end,
    }
  end
  with_child(function(done)
    local function really()
      local ok, err = store.remove(cfg.root, project_of(row), row.name)
      if ok and state_mod.active_in(project_of(row)) == row.name then
        state_mod.clear()
      end
      if not ok then
        session.notify("Not deleted: " .. tostring(err), vim.log.levels.ERROR)
      end
      done()
      if P then
        P.state = model.reduce(P.state, { type = "set_active", active = state_mod.active() })
      end
      reload_rows()
    end
    ask("Delete session?", {}, function()
      if row.name == cfg.default_name and cfg.confirm.delete_default_twice then
        ask(
          "Really delete the DEFAULT session?",
          { { { "  <leader>sL / :SessionMgr load! will have nothing to load.", "SessionMgrWarn" } } },
          really,
          done
        )
      else
        really()
      end
    end, done)
  end)
end

--- `/`: a borderless one-line input laid exactly over the filter row, so the
--- text is really edited (cursor keys, <C-w>, paste) while the list narrows live.
local function focus_filter()
  if not P then
    return
  end
  local p = P
  dispatch { type = "focus_filter", focused = true }
  p.child = true
  local function leave(keep)
    p.filter_input = nil
    if P ~= p then
      return
    end
    p.child = false
    p.state = model.reduce(p.state, { type = "focus_filter", focused = false })
    if not keep then
      p.state = model.reduce(p.state, { type = "set_filter", text = "" })
    end
    if float.is_open(p.float) then
      vim.api.nvim_set_current_win(p.float.win)
    end
    redraw()
  end
  p.filter_input = input.open {
    rect = { row = 1, col = 3, width = math.max(10, vim.api.nvim_win_get_width(p.float.win) - 4), height = 1 },
    relative_win = p.float.win,
    border = "none",
    text = p.state.filter,
    on_change = function(text)
      dispatch { type = "set_filter", text = text }
    end,
    on_submit = function()
      leave(true)
    end,
    on_cancel = function()
      leave(false)
    end,
    keys = {
      ["<Down>"] = function()
        dispatch { type = "move", delta = 1 }
      end,
      ["<Up>"] = function()
        dispatch { type = "move", delta = -1 }
      end,
      ["<C-n>"] = function()
        dispatch { type = "move", delta = 1 }
      end,
      ["<C-p>"] = function()
        dispatch { type = "move", delta = -1 }
      end,
    },
  }
end

local function show_help()
  with_child(function(done)
    require("session-mgr.ui.help").open(done)
  end)
end

--- Mouse: resolve the position against the last render's hit regions.
local function mouse_region()
  local pos = vim.fn.getmousepos()
  if not P or pos.winid ~= P.float.win or not P.out then
    return nil
  end
  return render.hit(P.out.regions, pos.line, pos.column), pos
end

local function on_click(double)
  local region = mouse_region()
  if not region then
    return
  end
  if region.kind == "sort" then
    dispatch { type = "set_sort", key = region.id }
  elseif region.kind == "scope" then
    if region.id ~= P.state.scope then
      reload_rows(region.id)
    end
  elseif region.kind == "row" then
    dispatch { type = "goto", index = region.id }
    if double then
      load_current()
    end
  end
end

local function on_mouse_move()
  if not P then
    return
  end
  local region, pos = mouse_region()
  local row = region and region.kind == "row" and (pos.line - 1) or nil
  if row ~= P.hover_row then -- repaint only when the hovered row changes
    P.hover_row = row
    redraw()
  end
end

local function set_keymaps(buf)
  local function map(lhs, fn)
    for _, l in ipairs(type(lhs) == "table" and lhs or { lhs }) do
      vim.keymap.set("n", l, fn, { buffer = buf, nowait = true, silent = true })
    end
  end
  local function act(action)
    return function()
      dispatch(action)
    end
  end
  map({ "j", "<Down>", "<C-n>" }, act { type = "move", delta = 1 })
  map({ "k", "<Up>", "<C-p>" }, act { type = "move", delta = -1 })
  map({ "gg", "<Home>" }, act { type = "first" })
  map("G", function()
    dispatch(vim.v.count > 0 and { type = "goto", index = vim.v.count } or { type = "last" })
  end)
  map("<End>", act { type = "last" })
  map("<C-d>", act { type = "half_page", delta = 1 })
  map("<C-u>", act { type = "half_page", delta = -1 })
  map({ "<PageDown>", "<C-f>" }, act { type = "page", delta = 1 })
  map({ "<PageUp>", "<C-b>" }, act { type = "page", delta = -1 })
  map({ "l", "<Right>" }, act { type = "cycle_sort", delta = 1 })
  map({ "h", "<Left>" }, act { type = "cycle_sort", delta = -1 })
  map("o", act { type = "reverse" })
  for i, key in ipairs(model.SORT_KEYS) do
    map(tostring(i), act { type = "set_sort", key = key })
  end
  map("a", function()
    reload_rows(P.state.scope == "all" and "project" or "all")
  end)
  map("<Tab>", function()
    reload_rows(P.state.scope == "all" and "project" or "all")
  end)
  map("/", focus_filter)
  map("<C-l>", act { type = "set_filter", text = "" })
  map("<CR>", load_current)
  map("r", rename_current)
  map("d", delete_current)
  map("p", function()
    P.show_preview = not P.show_preview
    redraw()
  end)
  map("?", show_help)
  map({ "q", "<Esc>" }, function()
    if P and P.state.filter ~= "" then
      dispatch { type = "set_filter", text = "" } -- first <Esc> clears the filter
    else
      M.close()
    end
  end)
  if config.get().picker.mouse then
    map("<LeftMouse>", function()
      on_click(false)
    end)
    map("<2-LeftMouse>", function()
      on_click(true)
    end)
    map("<ScrollWheelDown>", act { type = "scroll", delta = 3 })
    map("<ScrollWheelUp>", act { type = "scroll", delta = -3 })
    map("<MouseMove>", on_mouse_move)
  end
end

--- @param scope "project"|"all"
function M.open(scope)
  M.close()
  require("session-mgr").ensure_migrated()
  local cfg = config.get()
  local project = require("session-mgr.project").detect()
  local f = float.open { rect = float.centered(60, 8), title = "", footer = "" }
  P = {
    float = f,
    state = model.new {
      scope = scope,
      project = project,
      rows = rows_for(scope, project),
      sort = cfg.picker.default_sort,
      default_name = cfg.default_name,
      active = state_mod.active(),
    },
    augroup = vim.api.nvim_create_augroup("session-mgr-picker", { clear = true }),
    show_preview = true,
    parsed = {},
  }
  local p = P
  set_keymaps(f.buf)

  if cfg.picker.mouse and cfg.picker.hover then
    p.saved_mousemoveevent = vim.o.mousemoveevent
    vim.o.mousemoveevent = true -- only while the picker is open
  end
  vim.api.nvim_create_autocmd("VimResized", { group = p.augroup, callback = redraw })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = p.augroup,
    buffer = f.buf,
    callback = function()
      if P == p and not p.child then
        vim.schedule(M.close)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = p.augroup,
    pattern = tostring(f.win),
    callback = function()
      if P == p then
        vim.schedule(M.close)
      end
    end,
  })
  if cfg.picker.refresh_ms > 0 then
    p.timer = vim.uv.new_timer()
    p.timer:start(
      cfg.picker.refresh_ms,
      cfg.picker.refresh_ms,
      vim.schedule_wrap(function()
        if P == p and not p.child then
          redraw()
        end
      end)
    )
  end
  redraw()
  return p
end

--- For tests. @return table|nil
function M.current()
  return P
end

return M
