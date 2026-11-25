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

-- popup.nvim and plenary.nvim: an explicit *_DIR, then the dev checkout (so a
-- popup.nvim branch under test wins over a stale lazy copy), then the
-- lazy.nvim install, then a git-ignored clone under .tests/ (CI).
local function dep(env, name, dev, url)
  local candidates = {
    vim.env[env] or "",
    dev or "",
    vim.fn.stdpath "data" .. "/lazy/" .. name,
    vim.fn.expand "~/.local/share/nvim/lazy/" .. name,
    root .. "/.tests/" .. name,
  }
  for _, p in ipairs(candidates) do
    if p and p ~= "" and vim.uv.fs_stat(p) then
      vim.opt.runtimepath:append(p)
      return
    end
  end
  local dest = root .. "/.tests/" .. name
  local res = vim.system({ "git", "clone", "--depth=1", url, dest }):wait()
  if res.code ~= 0 then
    io.stderr:write(("FATAL: %s not found; set %s or clone %s\n"):format(name, env, url))
    os.exit(2)
  end
  vim.opt.runtimepath:append(dest)
end
dep("PLENARY_DIR", "plenary.nvim", nil, "https://github.com/nvim-lua/plenary.nvim")
dep(
  "POPUP_DIR",
  "popup.nvim",
  vim.fn.expand "~/dev/hosua/nvim/submodules/popup.nvim",
  "https://github.com/hosua/popup.nvim"
)
package.path = root .. "/tests/?.lua;" .. package.path

local src = debug.getinfo(require("session-mgr").setup, "S").source:gsub("^@", "")
if vim.fn.fnamemodify(src, ":p"):sub(1, #root) ~= root then
  io.stderr:write(("FATAL: testing %s, not this checkout (%s)\n"):format(src, root))
  os.exit(2)
end

local H = require "harness"
_G.describe, _G.it, _G.eq, _G.ok, _G.tmpdir = H.describe, H.it, H.eq, H.ok, H.tmpdir

-- Assigning to a name before its `local` declaration silently creates a
-- global and leaves the local untouched. Nothing else catches that, so
-- snapshot the globals and fail the run if the plugin added any.
local known_globals = {}
for k in pairs(_G) do
  known_globals[k] = true
end

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

for k in pairs(_G) do
  if not known_globals[k] then
    H.failed = H.failed + 1
    table.insert(
      H.failures,
      ("leaked global %q: assigned before its `local` declaration, or a missing `local`"):format(k)
    )
  end
end

for _, f in ipairs(H.failures) do
  io.stdout:write("FAIL  " .. f .. "\n")
end
io.stdout:write(("%d passed, %d failed (%d spec files)\n"):format(H.passed, H.failed, #specs))
os.exit(H.failed == 0 and 0 or 1)
