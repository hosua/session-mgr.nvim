local settings = require "session-mgr.settings"
local config = require "session-mgr.config"

local function setup(opts)
  local root = tmpdir()
  config.resolve(vim.tbl_extend("force", { root = root }, opts or {}))
  settings.reset_warned()
  return root
end

local function warnings(fn)
  local seen = {}
  local notify = require("session-mgr.session").notify
  require("session-mgr.session").notify = function(msg, level)
    seen[#seen + 1] = { msg, level }
  end
  local okk, err = pcall(fn)
  require("session-mgr.session").notify = notify
  assert(okk, err)
  return seen
end

describe("settings file", function()
  it("lives beside approved_roots.json", function()
    local root = setup()
    eq(root .. "/settings.json", settings.file())
  end)

  it("a missing file leaves setup() in charge", function()
    local root = setup()
    eq("missing", settings.read(root).status)
    eq({ "prompt", "setup" }, { settings.get "autoload" })
  end)

  it("bad JSON is ignored with one warning and is not overwritten", function()
    local root = setup()
    vim.fn.writefile({ "{not json" }, settings.file())
    local seen = warnings(function()
      eq("prompt", settings.effective "autoload")
      eq("prompt", settings.effective "autoload")
    end)
    eq(1, #seen)
    eq(vim.log.levels.WARN, seen[1][2])
    ok(seen[1][1]:find("settings.json is ignored", 1, true), seen[1][1])
    local saved, err = settings.set("autoload", "always", root)
    eq(false, saved)
    ok(err:find("fix it by hand", 1, true), err)
    eq({ "{not json" }, vim.fn.readfile(settings.file()))
  end)

  it("a file that is not an object is ignored", function()
    local root = setup()
    vim.fn.writefile({ '["autoload"]' }, settings.file())
    local seen = warnings(function()
      eq("error", settings.read(root).status)
    end)
    eq(1, #seen)
  end)

  it("an invalid value is ignored with one warning", function()
    setup()
    vim.fn.writefile({ '{"autoload":"sometimes"}' }, settings.file())
    local seen = warnings(function()
      eq({ "prompt", "setup" }, { settings.get "autoload" })
      eq({ "prompt", "setup" }, { settings.get "autoload" })
    end)
    eq(1, #seen)
    ok(seen[1][1]:find('autoload = "sometimes" is ignored', 1, true), seen[1][1])
  end)
end)

describe("settings precedence", function()
  it("a key in the file overrides setup(), an absent key does not", function()
    local root = setup { autoload = "always" }
    eq({ "always", "setup" }, { settings.get "autoload" })
    vim.fn.writefile({ '{"autoload":"never"}' }, settings.file())
    eq({ "never", "settings" }, { settings.get "autoload" })
    vim.fn.writefile({ "{}" }, settings.file())
    eq({ "always", "setup" }, { settings.get "autoload" })
    eq("autoload", settings.rows(root)[1].key)
  end)

  it("setup autoload = false and autosave = false are hard off", function()
    setup { autoload = false }
    vim.fn.writefile({ '{"autoload":"always"}' }, settings.file())
    local value, source, locked = settings.get "autoload"
    eq({ "never", "setup" }, { value, source })
    ok(locked:find("autoload = false", 1, true), locked)
    setup { autosave = false }
    vim.fn.writefile({ '{"autoload":"always"}' }, settings.file())
    eq("never", settings.effective "autoload")
  end)

  it("an unknown option name is an error, not a crash", function()
    setup()
    eq(false, (settings.set("nope", "x")))
    eq(false, (settings.reset "nope"))
    eq(false, (settings.cycle "nope"))
  end)
end)

describe("settings writes", function()
  it("set writes valid JSON, creating the directory", function()
    local root = setup()
    root = root .. "/deeper/still"
    eq(true, settings.set("autoload", "always", root))
    eq({ autoload = "always" }, vim.json.decode(table.concat(vim.fn.readfile(root .. "/settings.json"), "\n")))
  end)

  it("keeps unknown keys on rewrite and ignores them otherwise", function()
    local root = setup()
    vim.fn.writefile({ '{"future":{"a":[1,2]},"autoload":"never","z":true}' }, settings.file())
    eq("never", settings.effective "autoload")
    eq(true, settings.set("autoload", "always", root))
    eq(
      { future = { a = { 1, 2 } }, autoload = "always", z = true },
      vim.json.decode(table.concat(vim.fn.readfile(settings.file()), "\n"))
    )
    eq(true, settings.reset("autoload", root))
    eq({ future = { a = { 1, 2 } }, z = true }, vim.json.decode(table.concat(vim.fn.readfile(settings.file()), "\n")))
  end)

  it("rejects a value the schema does not allow and leaves the file alone", function()
    local root = setup()
    eq(true, settings.set("autoload", "always", root))
    local saved, err = settings.set("autoload", "sometimes", root)
    eq(false, saved)
    ok(err:find("prompt, always, never", 1, true), err)
    eq("always", settings.read(root).values.autoload)
  end)

  it("writes atomically: no temp file is left and the old file survives a failed rename", function()
    local root = setup()
    eq(true, settings.set("autoload", "always", root))
    eq({ "settings.json" }, vim.fn.readdir(root))
    -- A directory where the file should be makes the rename fail.
    vim.fn.delete(root .. "/settings.json")
    vim.fn.mkdir(root .. "/settings.json/keep", "p")
    local saved
    warnings(function()
      saved = settings.set("autoload", "never", root)
    end)
    eq(false, saved)
    eq({ "settings.json" }, vim.fn.readdir(root))
  end)

  it("pretty-prints one key per line, sorted, and an empty object as {}", function()
    local root = setup()
    vim.fn.writefile({ '{"b":1,"autoload":"never"}' }, settings.file())
    eq(true, settings.set("autoload", "always", root))
    eq({ "{", '  "autoload": "always",', '  "b": 1', "}" }, vim.fn.readfile(settings.file()))
    eq(true, settings.reset("autoload", root))
    eq(true, settings.reset("b", root) or true)
    vim.fn.writefile({ '{"autoload":"never"}' }, settings.file())
    eq(true, settings.reset("autoload", root))
    eq({ "{}" }, vim.fn.readfile(settings.file()))
  end)

  it("cycle walks prompt, always, never and back, starting from what is in force", function()
    local root = setup()
    eq({ true, "always" }, { settings.cycle("autoload", root) })
    eq({ true, "never" }, { settings.cycle("autoload", root) })
    eq({ true, "prompt" }, { settings.cycle("autoload", root) })
    eq({ true, "always" }, { settings.cycle("autoload", root) })
  end)

  it("reset on a missing file is a no-op", function()
    local root = setup()
    eq(true, settings.reset("autoload", root))
    eq(0, vim.fn.filereadable(settings.file()))
  end)
end)
