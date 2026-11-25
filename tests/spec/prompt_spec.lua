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
    local p = project.from_root("/", false, "pending")
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

describe("approval question reasons", function()
  local function body(reason, owner)
    local p = project.from_root("/etc/gitea", false, "pending", nil, reason)
    return table.concat(
      text(prompt.approve_lines {
        project = p,
        sessions_root = "/home/me/.local/share/nvim/sessions",
        home = "/home/me",
        owner = owner,
      }),
      "\n"
    )
  end

  it("says why, with the owner and group", function()
    local owner = { user = "root", group = "gitea" }
    ok(body("no_write", owner):find("You have no write access to /etc/gitea (owner root, group gitea).", 1, true))
    ok(body("no_read", owner):find("You have no read access to /etc/gitea (owner root, group gitea).", 1, true))
    ok(body("no_access", owner):find("You have no read or write access to /etc/gitea", 1, true))
    ok(body("no_write"):find("You have no write access to /etc/gitea.", 1, true))
  end)

  it("keeps the sudo warning for every reason", function()
    for _, r in ipairs { "home_parent", "no_read", "no_write", "no_access" } do
      local b = body(r)
      ok(b:find("root and sudo", 1, true), r)
      ok(b:find("THIS user's data dir", 1, true), r)
    end
  end)
end)

describe("autoload question layout", function()
  it("ends with a blank line and the remember hint in the dim group", function()
    local p = project.from_root("/home/me/dev/foo", true)
    local lines = prompt.autoload_lines { project = p, name = "autosave", now = 1800000000, home = "/home/me" }
    eq(6, #lines)
    eq({}, lines[5])
    eq({ { prompt.AUTOLOAD_HINT, "SessionMgrDim" } }, lines[6])
    eq("  Shift+Enter, Y or N picks and never asks again (:SessionMgr settings to change).", text(lines)[6])
  end)

  it("lists every working key in the border legend, keys bright and text grey", function()
    local chunks, width = prompt.autoload_footer()
    local line = table.concat(vim.tbl_map(function(c)
      return c[1]
    end, chunks))
    eq(" j/k move  ⏎ pick  ⇧⏎ pick+remember  y load  n skip  Y always  N never  q/Esc cancel ", line)
    eq(vim.fn.strdisplaywidth(line), width)
    for _, c in ipairs(chunks) do
      ok(c[2] == "SessionMgrFooterKey" or c[2] == "SessionMgrFooter", c[2])
    end
  end)
end)

describe("prompt keys", function()
  require("session-mgr.config").resolve()
  local function ask(keys)
    local got
    prompt.ask_autoload({
      project = project.from_root("/home/me", false, "home"),
      name = "autosave",
      now = os.time(),
    }, function(yes, remember)
      got = { yes, remember }
    end)
    vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
    vim.wait(200, function()
      return got ~= nil
    end)
    return got
  end

  it("starts on Start empty, so Enter answers no and does not remember", function()
    eq({ false, false }, ask "<CR>")
  end)
  it("k then Enter picks Load it; j and k stop at the ends", function()
    eq({ true, false }, ask "k<CR>")
    eq({ true, false }, ask "kkk<CR>")
    eq({ false, false }, ask "kj<CR>")
    eq({ false, false }, ask "jjj<CR>")
  end)
  it("y and n answer for this start only", function()
    eq({ true, false }, ask "y")
    eq({ false, false }, ask "n")
  end)
  it("Y and N answer and remember", function()
    eq({ true, true }, ask "Y")
    eq({ false, true }, ask "N")
  end)
  it("Shift+Enter picks the highlighted row and remembers", function()
    eq({ false, true }, ask "<S-CR>")
    eq({ true, true }, ask "k<S-CR>")
  end)
  it("q and Esc cancel without remembering", function()
    eq({ false, false }, ask "q")
    eq({ false, false }, ask "<Esc>")
  end)
  it("gg, G and the arrows do not move the selection", function()
    eq({ false, false }, ask "gg<CR>")
    eq({ false, false }, ask "<Up><Up><CR>")
  end)
end)

describe("approval question keys", function()
  it("Enter, Esc and n answer no; y answers yes", function()
    require("session-mgr.config").resolve()
    local function ask(keys)
      local answer
      prompt.ask_approve({
        project = project.from_root("/", false, "pending"),
        sessions_root = "/tmp/x",
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
