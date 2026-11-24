local ignore = require "session-mgr.ignore"
local cfg = require("session-mgr.config").defaults.ignore

describe("ignore.matches", function()
  it("ignores git's message editors by file name", function()
    for _, name in ipairs {
      "/r/.git/COMMIT_EDITMSG",
      "/r/.git/MERGE_MSG",
      "/r/.git/TAG_EDITMSG",
      "/r/.git/rebase-merge/git-rebase-todo",
      "/r/.git/addp-hunk-edit.diff",
      "/r/.git/anything",
    } do
      eq(true, ignore.matches(name, "", cfg), name)
    end
  end)
  it("ignores by filetype", function()
    for _, ft in ipairs { "gitcommit", "gitrebase", "hgcommit", "crontab" } do
      eq(true, ignore.matches("", ft, cfg), ft)
    end
  end)
  it("keeps ordinary files", function()
    eq(false, ignore.matches("/r/src/main.lua", "lua", cfg))
    eq(false, ignore.matches("/r/gitcommit.txt", "text", cfg))
    eq(false, ignore.matches("", "", cfg))
  end)
  it("takes the lists from the arguments", function()
    eq(true, ignore.matches("/x/NOTES.tmp", "", { filetypes = {}, patterns = { "%.tmp$" } }))
  end)
end)

describe("ignore.is_ignored", function()
  it("reads the buffer name and filetype", function()
    require("session-mgr.config").resolve()
    local buf = vim.api.nvim_create_buf(true, false)
    eq(false, ignore.is_ignored(buf))
    vim.api.nvim_buf_set_name(buf, "/tmp/zz/.git/COMMIT_EDITMSG")
    eq(true, ignore.is_ignored(buf))
    local other = vim.api.nvim_create_buf(true, false)
    vim.bo[other].filetype = "gitcommit"
    eq(true, ignore.is_ignored(other))
    eq(false, ignore.is_ignored(99999))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_buf_delete(other, { force = true })
  end)
end)
