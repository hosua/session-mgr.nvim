--- Process records -> the nvim forest shown on the Processes tab. Pure: a
--- sample goes in, nodes with own and subtree memory come out.
---
--- A root is an `nvim` whose parent is not an `nvim` (the TUI client, or a
--- headless/embedded server started by something else). Everything below it
--- is its tree. Language servers whose nvim died get reparented to init or
--- systemd --user; they are found by their mason path and gathered under one
--- synthetic "orphaned LSPs" root.
local M = {}

--- @class SessionMgrSample
--- @field t number wall clock, seconds (vim.uv.hrtime() / 1e9)
--- @field records SessionMgrProc[]
--- @field pss table<integer, integer>|nil pid -> kB from smaps_rollup
--- @field swap table<integer, integer>|nil pid -> kB
--- @field cwd table<integer, string>|nil pid -> working directory
--- @field stat table<integer, { ticks: integer, start: integer }>|nil
--- @field hz integer|nil clock ticks per second (getconf CLK_TCK)

--- @class SessionMgrProcNode
--- @field id string stable key: the pid, or "orphans"
--- @field pid integer|nil nil for the synthetic orphans root
--- @field proc SessionMgrProc|nil
--- @field label string|nil synthetic root only
--- @field own integer kB, this process alone
--- @field tree integer kB, this process plus every descendant
--- @field approx boolean own is RSS because PSS was unreadable
--- @field cpu number|nil percent of one core since the previous sample
--- @field cwd string|nil
--- @field swap integer|nil kB
--- @field start integer|nil start time in clock ticks since boot, to spot pid reuse
--- @field children SessionMgrProcNode[]
--- @field parent SessionMgrProcNode|nil
--- @field depth integer 0 for roots
--- @field own_session boolean this tree holds the nvim running the picker
--- @field descendants integer

M.ORPHANS_ID = "orphans"

--- @param sample SessionMgrSample
--- @param opts { own_pid: integer|nil, mason: string|nil, orphans: boolean|nil, memory: "pss"|"rss"|nil, prev: SessionMgrSample|nil }
--- @return { roots: SessionMgrProcNode[], by_id: table<string, SessionMgrProcNode>, total: integer, count: integer, memory: "pss"|"rss" }
function M.build(sample, opts)
  opts = opts or {}
  local by_pid, kids = {}, {}
  for _, r in ipairs(sample.records) do
    by_pid[r.pid] = r
  end
  for _, r in ipairs(sample.records) do
    if by_pid[r.ppid] and r.ppid ~= r.pid then
      kids[r.ppid] = kids[r.ppid] or {}
      table.insert(kids[r.ppid], r)
    end
  end

  local use_pss = opts.memory ~= "rss" and sample.pss ~= nil
  local any_pss = false
  local prev = opts.prev
  local hz = sample.hz or 100
  local by_id, count = {}, 0

  local function cpu_of(pid)
    local now, before = sample.stat and sample.stat[pid], prev and prev.stat and prev.stat[pid]
    -- Same pid but a different start time is a new process: no history.
    if not (now and before and before.start == now.start) or sample.t <= prev.t then
      return nil
    end
    return math.max(0, (now.ticks - before.ticks) / hz / (sample.t - prev.t) * 100)
  end

  local function make(r, parent)
    local pss = use_pss and sample.pss[r.pid] or nil
    any_pss = any_pss or pss ~= nil
    local node = {
      id = tostring(r.pid),
      pid = r.pid,
      proc = r,
      own = pss or r.rss,
      approx = use_pss and pss == nil,
      cpu = cpu_of(r.pid),
      cwd = sample.cwd and sample.cwd[r.pid] or nil,
      swap = sample.swap and sample.swap[r.pid] or nil,
      start = sample.stat and sample.stat[r.pid] and sample.stat[r.pid].start or nil,
      children = {},
      parent = parent,
      depth = parent and parent.depth + 1 or 0,
      own_session = false,
    }
    by_id[node.id] = node
    count = count + 1
    for _, k in ipairs(kids[r.pid] or {}) do
      table.insert(node.children, make(k, node))
    end
    return node
  end

  local roots = {}
  for _, r in ipairs(sample.records) do
    local parent = by_pid[r.ppid]
    if r.comm == "nvim" and not (parent and parent.comm == "nvim") then
      table.insert(roots, make(r, nil))
    end
  end

  if opts.orphans ~= false and opts.mason and opts.mason ~= "" then
    local function under_nvim(r)
      local seen = {}
      while r and not seen[r.pid] do
        if r.comm == "nvim" then
          return true
        end
        seen[r.pid] = true
        r = by_pid[r.ppid]
      end
      return false
    end
    local function is_lsp(r)
      return r and r.args:find(opts.mason, 1, true) ~= nil
    end
    local group = {
      id = M.ORPHANS_ID,
      label = "orphaned LSPs",
      own = 0,
      approx = false,
      children = {},
      depth = 0,
      own_session = false,
    }
    for _, r in ipairs(sample.records) do
      -- Topmost orphan only: its children come along through make().
      if is_lsp(r) and not is_lsp(by_pid[r.ppid]) and not under_nvim(r) then
        local node = make(r, group)
        table.insert(group.children, node)
      end
    end
    if #group.children > 0 then
      by_id[group.id] = group
      table.insert(roots, group)
    end
  end

  -- Totals bottom-up, and flag the tree this nvim lives in.
  local function finish(node)
    node.tree, node.descendants = node.own, 0
    for _, c in ipairs(node.children) do
      finish(c)
      node.tree = node.tree + c.tree
      node.descendants = node.descendants + 1 + c.descendants
    end
    return node
  end
  local total = 0
  for _, root in ipairs(roots) do
    total = total + finish(root).tree
  end
  local mine = opts.own_pid and by_id[tostring(opts.own_pid)]
  if mine then
    local top = mine
    while top.parent do
      top = top.parent
    end
    local function flag(n)
      n.own_session = true
      for _, c in ipairs(n.children) do
        flag(c)
      end
    end
    flag(top)
  end

  return { roots = roots, by_id = by_id, total = total, count = count, memory = any_pss and "pss" or "rss" }
end

--- Every pid in a node's subtree, children before parents, so a SIGKILL
--- sweep never leaves a child a window to be reparented and respawned.
--- @param node SessionMgrProcNode
--- @return integer[]
function M.subtree_pids(node)
  local out = {}
  local function walk(n)
    for _, c in ipairs(n.children) do
      walk(c)
    end
    if n.pid then
      out[#out + 1] = n.pid
    end
  end
  walk(node)
  return out
end

return M
