local sessfile = require "session-mgr.sessfile"
local FIX = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/legacy/"

describe("sessfile", function()
  it("reads cwd, files, tabs and windows from a real mksession shape", function()
    local info = sessfile.parse_lines(vim.fn.readfile(FIX .. "root.vim"), "/home/me")
    eq("/home/me/proj/demo", info.cwd)
    eq({ "src/deployer.js", "src/deployer.spec.js", "docs/with space.md" }, info.files)
    eq(2, info.tabs)
    eq(3, info.wins)
  end)
  it("handles an absolute, escaped cd and a file without one", function()
    eq("/srv/my proj", sessfile.parse_lines({ "cd /srv/my\\ proj" }, "/home/me").cwd)
    eq(nil, sessfile.parse_lines({ "badd +1 a" }, "/home/me").cwd)
  end)
  it("returns an error for an unreadable file", function()
    local info, err = sessfile.parse "/nonexistent/x.vim"
    eq(nil, info)
    ok(err)
  end)
end)
