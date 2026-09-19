--- session-mgr: public API.
---
--- setup() is optional: every entry point resolves the config on first use,
--- so the plugin works with `opts = {}` or with no setup call at all.
local M = {}

--- @param opts table|nil user overrides, merged over config.defaults
function M.setup(opts)
  require("session-mgr.config").resolve(opts)
end

return M
