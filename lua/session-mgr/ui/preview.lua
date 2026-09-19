--- Preview pane content: what is inside the session under the cursor, read
--- from the .vim file without sourcing it. `build` is pure.
local paths = require "session-mgr.paths"
local timefmt = require "session-mgr.timefmt"

local M = {}

local function plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

--- @param row SessionMgrRow|nil
--- @param info SessionMgrSessInfo|nil parsed session file
--- @param opts { width: integer, height: integer, home: string|nil, now: integer, err: string|nil }
--- @return { lines: string[], spans: table[], line_hl: table, title: string }
function M.build(row, info, opts)
  local out = { lines = {}, spans = {}, line_hl = {}, title = " preview " }
  local function add(chunks)
    local text = ""
    for _, c in ipairs(chunks) do
      if c[2] and c[1] ~= "" then
        out.spans[#out.spans + 1] = { row = #out.lines, col_start = #text, col_end = #text + #c[1], hl = c[2] }
      end
      text = text .. c[1]
    end
    out.lines[#out.lines + 1] = text
  end
  if not row then
    add { { "  nothing selected", "SessionMgrDim" } }
    return out
  end
  out.title = (" %s.vim "):format(row.name)
  if not info then
    add { { "  cannot read this session", "SessionMgrDanger" } }
    add { { "  " .. (opts.err or ""), "SessionMgrDim" } }
    return out
  end

  local inner = opts.width - 2
  local function field(key, value, hl)
    add { { " " .. key .. (" "):rep(9 - #key), "SessionMgrPreviewKey" }, { value, hl } }
  end
  field("project", row.label .. (row.is_git and "" or "  (not a git repo)"))
  field(
    "cwd",
    info.cwd and paths.display_path(info.cwd, opts.home, inner - 10) or "not recorded",
    "SessionMgrPreviewPath"
  )
  field("layout", plural(info.tabs, "tab") .. ", " .. plural(info.wins, "window"))
  field("saved", timefmt.relative(opts.now, row.updated))
  field(
    "loaded",
    row.last_used and (timefmt.relative(opts.now, row.last_used) .. ", " .. plural(row.uses, "time")) or "never"
  )
  add {}
  add { { " " .. plural(#info.files, "file"), "SessionMgrHeader" } }

  local room = opts.height - #out.lines
  local shown = #info.files > room and room - 1 or #info.files
  for i = 1, math.max(0, shown) do
    local f = paths.tilde(info.files[i], opts.home)
    local dir, base = f:match "^(.*/)([^/]*)$"
    dir, base = dir or "", base or f
    -- Keep the file name; shorten the directory from the left.
    local over = vim.fn.strdisplaywidth(dir .. base) - (inner - 2)
    if over > 0 and #dir > 0 then
      dir = "…" .. vim.fn.strcharpart(dir, math.min(vim.fn.strchars(dir), over + 1))
    end
    add { { "  " }, { dir, "SessionMgrDim" }, { base, "SessionMgrName" } }
  end
  if shown < #info.files and room > 0 then
    add { { ("  … and %d more"):format(#info.files - shown), "SessionMgrDim" } }
  end
  if #info.files == 0 then
    add { { "  no files (empty workspace)", "SessionMgrDim" } }
  end
  return out
end

return M
