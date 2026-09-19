local hints = require "session-mgr.hints"

describe("hints.find", function()
  local maps = {
    { lhs = " sl", rhs = "<Cmd>SessionMgr load<CR>" },
    { lhs = " sL", rhs = "<Cmd>SessionMgr load!<CR>" },
    { lhs = " xx", callback = function() end },
    { lhs = "<F5>", rhs = ":SessionMgr  save<CR>" },
  }
  it("finds a command-string map and writes it in <leader> notation", function()
    eq("<leader>sl", hints.find(maps, "load", " "))
  end)
  it("does not confuse load with load!", function()
    eq("<leader>sL", hints.find(maps, "load!", " "))
  end)
  it("accepts the :cmd<CR> form and non-leader keys", function()
    eq("<F5>", hints.find(maps, "save", " "))
  end)
  it("returns nil when nothing is mapped (Lua callbacks are invisible)", function()
    eq(nil, hints.find(maps, "all", " "))
  end)
  it("prefers the shortest key when several exist", function()
    local two = { { lhs = " sll", rhs = "<cmd>SessionMgr load<cr>" }, { lhs = " l", rhs = "<cmd>SessionMgr load<cr>" } }
    eq("<leader>l", hints.find(two, "load", " "))
  end)
end)

describe("hints.key_for", function()
  it("discovers a real mapping set with vim.keymap.set", function()
    vim.g.mapleader = " "
    vim.keymap.set("n", "<leader>zl", "<cmd>SessionMgr load<cr>")
    require("session-mgr.config").resolve {}
    eq("<leader>zl", hints.key_for "load")
    vim.keymap.del("n", "<leader>zl")
  end)
  it("prefers hints.load_key when configured", function()
    require("session-mgr.config").resolve { hints = { load_key = "gl" } }
    eq("gl", hints.key_for "load")
    require("session-mgr.config").resolve {}
  end)
end)
