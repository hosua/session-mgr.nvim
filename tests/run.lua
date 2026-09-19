-- Run every tests/**/*_spec.lua:
--
--   nvim --headless -u NONE -l tests/run.lua [dir]      (`-l` must be last)
--
-- `-u NONE` still leaves ~/.config/nvim on the runtimepath, and the rtp
-- loader beats package.path, so a copy of this plugin installed elsewhere
-- would be tested instead of this checkout. Prepend the repo and then PROVE
-- which file was loaded.
local this = debug.getinfo(1, "S").source:gsub("^@", "")
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

local src = debug.getinfo(require("session-mgr").setup, "S").source:gsub("^@", "")
if vim.fn.fnamemodify(src, ":p"):sub(1, #root) ~= root then
  io.stderr:write(("FATAL: testing %s, not this checkout (%s)\n"):format(src, root))
  os.exit(2)
end

local H = require "harness"
_G.describe, _G.it, _G.eq, _G.ok, _G.tmpdir = H.describe, H.it, H.eq, H.ok, H.tmpdir

local dir = root .. "/tests/" .. (arg[1] or "spec")
local specs = vim.fn.globpath(dir, "**/*_spec.lua", false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
  local ok, err = pcall(dofile, spec)
  if not ok then
    H.failed = H.failed + 1
    table.insert(H.failures, spec .. " failed to load\n    " .. tostring(err))
  end
end
H.cleanup()

for _, f in ipairs(H.failures) do
  io.stdout:write("FAIL  " .. f .. "\n")
end
io.stdout:write(("%d passed, %d failed (%d spec files)\n"):format(H.passed, H.failed, #specs))
os.exit(H.failed == 0 and 0 or 1)
