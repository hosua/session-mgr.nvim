-- Defines :SessionMgr at startup without loading the plugin's Lua modules.
-- Everything heavy is required inside the callbacks, so a lazy.nvim
-- `cmd = { "SessionMgr" }` stub and this file agree on the same entry point.
if vim.g.loaded_session_mgr then
  return
end
vim.g.loaded_session_mgr = true

vim.api.nvim_create_user_command("SessionMgr", function(args)
  require("session-mgr.commands").dispatch(args.fargs, args.bang)
end, {
  nargs = "*",
  bang = true,
  desc = "session-mgr",
  complete = function(arglead, cmdline, pos)
    return require("session-mgr.commands").complete(arglead, cmdline, pos)
  end,
})
