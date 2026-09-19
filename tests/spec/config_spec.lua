local config = require "session-mgr.config"

local function quiet(fn)
  local notify, msgs = vim.notify, {}
  vim.notify = function(m)
    msgs[#msgs + 1] = m
  end
  local ok, err = pcall(fn)
  vim.notify = notify
  if not ok then
    error(err, 0)
  end
  return msgs
end

describe("config", function()
  it("resolves defaults with no opts and no problems", function()
    local cfg, problems = config.resolve()
    eq({}, problems)
    eq("default", cfg.default_name)
    eq(true, cfg.load.replace)
    eq(vim.fs.normalize(vim.fn.stdpath "data" .. "/sessions"), cfg.root)
  end)

  it("reports unknown keys, nested too, instead of ignoring them", function()
    local problems
    local msgs = quiet(function()
      problems = select(2, config.resolve { autosav = true, picker = { previw = false } })
    end)
    eq({ "unknown key autosav", "unknown key picker.previw" }, problems)
    eq(1, #msgs)
  end)

  it("reports a wrong type with the dotted option name", function()
    local problems
    quiet(function()
      problems = select(2, config.resolve { load = { replace = "yes" } })
    end)
    eq({ "load.replace must be boolean, got string" }, problems)
  end)

  it("accepts the optional types for false-by-default options", function()
    local _, problems = config.resolve {
      sessionoptions = false,
      picker = { border = "single" },
      hints = { load_key = "<leader>sl" },
      hooks = { pre_save = function() end },
    }
    eq({}, problems)
  end)

  it("rejects fractions outside (0, 1] and falls back to the default", function()
    local cfg
    quiet(function()
      cfg = config.resolve { picker = { max_width = 40 } }
    end)
    eq(0.9, cfg.picker.max_width)
  end)

  it("rejects an unknown sort key", function()
    local cfg
    quiet(function()
      cfg = config.resolve { picker = { default_sort = { key = "size", dir = "asc" } } }
    end)
    eq({ key = "name", dir = "asc" }, cfg.picker.default_sort)
  end)

  it("deep-merges without mutating the defaults", function()
    local before = vim.deepcopy(config.defaults)
    local cfg = config.resolve { picker = { preview = false } }
    eq(false, cfg.picker.preview)
    eq(true, cfg.picker.hover)
    eq(before, config.defaults)
  end)

  it("normalises root (~ and trailing slash)", function()
    local cfg = config.resolve { root = "~/sess/" }
    eq(vim.fs.normalize "~/sess", cfg.root)
  end)
end)
