-- The README's configuration block must BE the defaults, not resemble them.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local readme = table.concat(vim.fn.readfile(root .. "/README.md"), "\n")

describe("README", function()
  it("config block evaluates to exactly config.defaults", function()
    local block = readme:match "<!%-%- config:start %-%->\n```lua\n(.-)\n```\n<!%-%- config:end %-%->"
    ok(block, "config block markers not found")
    local chunk = assert(loadstring((block:gsub('^require%("session%-mgr"%)%.setup', "return"))))
    eq(require("session-mgr.config").defaults, chunk())
  end)
  it("documents every highlight group and every subcommand", function()
    for name in pairs(require("session-mgr.hl").LINKS) do
      ok(readme:find("`" .. name .. "`", 1, true), name .. " missing from README")
    end
    for sub in pairs(require("session-mgr.commands").subcommands) do
      ok(readme:find(":SessionMgr " .. sub, 1, true), sub .. " missing from README")
    end
  end)
  it("contains no literal home directory and its image exists", function()
    ok(not readme:find("/home/" .. (vim.env.USER or "nobody") .. "/", 1, true))
    ok(vim.uv.fs_stat(root .. "/assets/picker.png"), "assets/picker.png missing")
  end)
end)
