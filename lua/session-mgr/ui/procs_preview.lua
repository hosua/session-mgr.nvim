--- Preview pane for the Processes tab: everything we know about the process
--- under the cursor, and exactly what x and X would do to it. Pure.
local parse = require "session-mgr.procs.parse"
local paths = require "session-mgr.paths"
local tree = require "session-mgr.procs.tree"

local M = {}

local function elapsed(s)
  if not s then
    return "?"
  end
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then
    return ("%dd %dh"):format(d, h)
  elseif h > 0 then
    return ("%dh %dm"):format(h, m)
  end
  return ("%dm %ds"):format(m, s % 60)
end

--- Hard-wrap `text` to `w` cells.
local function wrap(text, w)
  local out = {}
  w = math.max(8, w)
  while vim.fn.strdisplaywidth(text) > w do
    out[#out + 1] = vim.fn.strcharpart(text, 0, w)
    text = vim.fn.strcharpart(text, w)
  end
  out[#out + 1] = text
  return out
end

--- @param node SessionMgrProcNode|nil
--- @param opts { width: integer, height: integer, home: string|nil, memory: "pss"|"rss" }
function M.build(node, opts)
  local out = { lines = {}, spans = {}, line_hl = {}, title = " process " }
  local entries = {}
  local function add(chunks)
    entries[#entries + 1] = chunks
  end
  local function field(key, value, hl)
    add { { " " .. key .. (" "):rep(9 - #key), "SessionMgrPreviewKey" }, { value, hl } }
  end
  local function finish()
    -- Never taller than the pane: cut the middle, keep the x / X lines.
    local keep_tail = 2
    if #entries > opts.height and opts.height > keep_tail + 1 then
      local head = vim.list_slice(entries, 1, opts.height - keep_tail - 1)
      head[#head + 1] = { { "  …", "SessionMgrDim" } }
      entries = vim.list_extend(head, vim.list_slice(entries, #entries - keep_tail + 1))
    end
    for _, chunks in ipairs(entries) do
      local text = ""
      for _, c in ipairs(chunks) do
        if c[2] and c[1] ~= "" then
          out.spans[#out.spans + 1] = { row = #out.lines, col_start = #text, col_end = #text + #c[1], hl = c[2] }
        end
        text = text .. c[1]
      end
      out.lines[#out.lines + 1] = text
    end
    return out
  end
  if not node then
    add { { "  nothing selected", "SessionMgrDim" } }
    return finish()
  end
  local inner = opts.width - 2

  if not node.pid then
    out.title = " orphaned LSPs "
    add { { " Language servers whose nvim is gone.", "SessionMgrName" } }
    add { { " Nothing will stop them but a signal.", "SessionMgrDim" } }
    add {}
    field("servers", tostring(#node.children))
    field("memory", parse.size(node.tree))
  else
    local p = node.proc
    out.title = (" %d %s "):format(node.pid, p.comm)
    field("pid", ("%d  (parent %d)"):format(node.pid, p.ppid))
    field("user", p.user)
    field("running", elapsed(p.elapsed))
    field("threads", tostring(p.threads))
    field("cpu", node.cpu and ("%.1f%%  (%ds total)"):format(node.cpu, p.cputime) or ("%ds total"):format(p.cputime))
    local mem = parse.size(node.own) .. (node.approx and "  RSS (PSS unreadable)" or "")
    field(opts.memory == "pss" and "pss" or "rss", mem)
    if opts.memory == "pss" then
      field("rss", parse.size(p.rss))
    end
    if node.swap and node.swap > 0 then
      field("swap", parse.size(node.swap), "SessionMgrWarn")
    end
    field("tree", ("%s  (%d below)"):format(parse.size(node.tree), node.descendants))
    if node.cwd then
      field("cwd", paths.display_path(node.cwd, opts.home, inner - 10), "SessionMgrPreviewPath")
    end
    if node.own_session then
      add { { " ● this nvim lives in this tree", "SessionMgrActive" } }
    end
    add {}
    add { { " command", "SessionMgrHeader" } }
    for _, l in ipairs(wrap(p.args, inner - 2)) do
      add { { "  " .. l, "SessionMgrName" } }
    end
  end

  add {}
  local kill = tree.subtree_pids(node)
  if node.pid then
    add { { " x", "SessionMgrDanger" }, { (" SIGTERM to %d only"):format(node.pid), "SessionMgrDim" } }
  end
  add {
    { " X", "SessionMgrDanger" },
    {
      (" SIGKILL to %d process%s, %s"):format(#kill, #kill == 1 and "" or "es", parse.size(node.tree)),
      "SessionMgrDim",
    },
  }
  return finish()
end

return M
