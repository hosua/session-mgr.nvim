--- `<leader>ss`: name a session. An input with a fixed `.vim` suffix over a
--- live list of this project's sessions; Tab cycles matches into the input.
local config = require "session-mgr.config"
local confirm = require "session-mgr.ui.confirm"
local float = require "session-mgr.ui.float"
local input = require "session-mgr.ui.input"
local save_model = require "session-mgr.ui.save_model"
local session = require "session-mgr.session"
local state_mod = require "session-mgr.state"
local store = require "session-mgr.store"
local validate = require "session-mgr.validate"

local M = {}

local FOOTER = {
  { " ⏎", "SessionMgrFooterKey" },
  { " save  ", "SessionMgrFooter" },
  { "tab", "SessionMgrFooterKey" },
  { " complete  ", "SessionMgrFooter" },
  { "esc", "SessionMgrFooterKey" },
  { " cancel ", "SessionMgrFooter" },
}

--- @type table|nil
local S

function M.close()
  local s = S
  S = nil
  if s then
    float.close(s.list)
    if s.input then
      s.input.cancel()
    end
  end
end

function M.open()
  M.close()
  require("session-mgr").ensure_migrated()
  local cfg = config.get()
  local project = require("session-mgr.project").detect()
  local rows = store.list(cfg.root, project)
  local prefill = cfg.save_prompt.prefill_active and state_mod.active_in(project) or ""
  local width = math.min(cfg.save_prompt.width, float.editor().width - 6)
  local list_h = math.max(1, math.min(cfg.save_prompt.max_list_height, math.max(#rows, 1)))
  local box = float.centered(width, list_h + 3) -- input (1) + its border share (2) + list

  local s = { state = save_model.new { rows = rows, text = prefill, default_name = cfg.default_name, height = list_h } }
  S = s
  s.list = float.open {
    rect = { row = box.row + 3, col = box.col, width = width, height = list_h },
    title = (" %d saved for %s "):format(#rows, project.label),
    footer = FOOTER,
    enter = false,
    focusable = false,
    zindex = 70,
  }

  local function repaint()
    if S ~= s or not float.is_open(s.list) then
      return
    end
    local out = save_model.render(s.state, os.time(), width)
    float.paint(s.list, out)
    local title = s.state.query == "" and (" %d saved for %s "):format(#rows, project.label)
      or (" %d of %d saved for %s "):format(out.count, #rows, project.label)
    vim.api.nvim_win_set_config(s.list.win, { title = title, title_pos = "center" })
    if s.input and float.is_open(s.input) and float.has_border(s.input) then
      vim.api.nvim_win_set_config(s.input.win, { footer = out.status, footer_pos = "right" })
    end
  end

  local function cycle(delta)
    s.state = save_model.reduce(s.state, { type = "cycle", delta = delta })
    -- set_text fires TextChanged; that must not be mistaken for typing.
    s.input.silent = true
    s.input.set_text(s.state.text)
    vim.schedule(function()
      if s.input then
        s.input.silent = false
      end
    end)
    repaint()
  end

  local function finish_save(name)
    M.close()
    session.save(project, name)
  end

  s.input = input.open {
    rect = { row = box.row, col = box.col, width = width, height = 1 },
    title = (" Save session for %s "):format(project.label),
    text = prefill,
    suffix = ".vim",
    zindex = 75,
    on_change = function(text)
      s.state = save_model.reduce(s.state, { type = "type", text = text })
      repaint()
    end,
    on_cancel = function()
      if S == s and not s.confirming then
        s.input = nil
        M.close()
      end
    end,
    on_submit = function(text)
      s.input = nil
      local name, err = validate.name(text)
      if not name then
        M.close()
        return session.notify("Not saved: " .. err, vim.log.levels.ERROR)
      end
      if not store.exists(cfg.root, project.key, name) then
        return finish_save(name)
      end
      s.confirming = true
      confirm.open {
        title = "Overwrite session?",
        danger = true,
        lines = {
          {
            { "  " },
            { name .. ".vim", "SessionMgrDefault" },
            { "  already exists in " .. project.label, "SessionMgrDim" },
          },
        },
        choices = { { key = "o", label = "overwrite it", value = true, danger = true } },
        on_choice = function(yes)
          if yes then
            finish_save(name)
          else
            M.close()
          end
        end,
      }
    end,
    keys = {
      ["<Tab>"] = function()
        cycle(1)
      end,
      ["<S-Tab>"] = function()
        cycle(-1)
      end,
      ["<C-n>"] = function()
        cycle(1)
      end,
      ["<C-p>"] = function()
        cycle(-1)
      end,
      ["<Down>"] = function()
        cycle(1)
      end,
      ["<Up>"] = function()
        cycle(-1)
      end,
    },
  }
  repaint()
  return s
end

function M.current()
  return S
end

return M
