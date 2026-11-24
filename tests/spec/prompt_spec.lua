local prompt = require "session-mgr.prompt"
local project = require "session-mgr.project"

local function text(lines)
  local out = {}
  for _, chunks in ipairs(lines) do
    out[#out + 1] = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, chunks))
  end
  return out
end

describe("autoload question", function()
  local now = 1800000000
  it("states the project, why, the session and when it was saved", function()
    local p = project.from_root("/home/me/dev/foo", true)
    local lines =
      text(prompt.autoload_lines { project = p, name = "autosave", saved = now - 300, now = now, home = "/home/me" })
    eq("  Project ~/dev/foo", lines[1])
    eq("  Why     git root", lines[2])
    eq("  Session autosave.vim", lines[3])
    ok(lines[4]:find("5m ago", 1, true) and lines[4]:find("(", 1, true), lines[4])
  end)
  it("names the marker, the home fallback and the approved directory", function()
    local function why(p)
      return text(prompt.autoload_lines { project = p, name = "autosave", now = now, home = "/home/me" })[2]
    end
    eq("  Why     marker .hg", why(project.from_root("/home/me/x", false, "marker", ".hg")))
    eq("  Why     home fallback", why(project.from_root("/home/me", false, "home")))
    eq("  Why     approved directory", why(project.from_root("/", false, "approved")))
  end)
  it("shows the full date for an old save and copes with an unknown one", function()
    local p = project.from_root("/home/me", false, "home")
    local old = text(prompt.autoload_lines { project = p, name = "autosave", saved = now - 3 * 86400, now = now })[4]
    ok(old:find "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d", old)
    ok(text(prompt.autoload_lines { project = p, name = "autosave", now = now })[4]:find "unknown")
  end)
end)

describe("approval question", function()
  it("warns that the session lives under this user's data dir", function()
    local p = project.from_root("/", false, "ancestor_pending")
    local body = table.concat(
      text(
        prompt.approve_lines { project = p, sessions_root = "/home/me/.local/share/nvim/sessions", home = "/home/me" }
      ),
      "\n"
    )
    ok(body:find("/ is a parent of your home", 1, true), body)
    ok(body:find("THIS user's data dir", 1, true), body)
    ok(body:find("~/.local/share/nvim/sessions", 1, true), body)
    ok(body:find("root and sudo", 1, true), body)
  end)
end)

describe("prompt keys", function()
  it("Enter, Esc and n all answer no; y answers yes", function()
    require("session-mgr.config").resolve()
    local function ask(keys)
      local answer
      prompt.ask_autoload({
        project = project.from_root("/home/me", false, "home"),
        name = "autosave",
        now = os.time(),
      }, function(yes)
        answer = yes
      end)
      vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
      vim.wait(200, function()
        return answer ~= nil
      end)
      return answer
    end
    eq(false, ask "<CR>")
    eq(false, ask "<Esc>")
    eq(false, ask "n")
    eq(true, ask "y")
  end)
end)
