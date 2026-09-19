--- Read facts out of a :mksession file without sourcing it: the directory it
--- was saved from, its files, and rough tab/window counts. Used by the
--- preview pane, the legacy migration, and index recovery.
local M = {}

local MAX_LINES = 2000

--- @class SessionMgrSessInfo
--- @field cwd string|nil absolute, `~` expanded
--- @field files string[] as written (relative to cwd unless absolute)
--- @field tabs integer
--- @field wins integer

--- @param lines string[]
--- @param home string|nil used to expand a leading ~
--- @return SessionMgrSessInfo
function M.parse_lines(lines, home)
  local info = { cwd = nil, files = {}, tabs = 1, wins = 1 }
  for i, line in ipairs(lines) do
    if i > MAX_LINES then
      break
    end
    local cd = not info.cwd and line:match "^cd%s+(.+)$"
    local file = line:match "^badd%s+%+%d+%s+(.+)$"
    if cd then
      -- mksession escapes spaces and specials with a backslash.
      cd = cd:gsub("\\(.)", "%1")
      if home and (cd == "~" or cd:sub(1, 2) == "~/") then
        cd = home .. cd:sub(2)
      end
      info.cwd = vim.fs.normalize(cd)
    elseif file then
      info.files[#info.files + 1] = (file:gsub("\\(.)", "%1"))
    elseif line:match "^tabnew" then
      info.tabs = info.tabs + 1
      info.wins = info.wins + 1
    elseif line:match "^v?split$" or line:match "^%d*v?split$" then
      info.wins = info.wins + 1
    end
  end
  return info
end

--- @param file string
--- @return SessionMgrSessInfo|nil info
--- @return string|nil err
function M.parse(file)
  local ok, lines = pcall(vim.fn.readfile, file, "", MAX_LINES)
  if not ok then
    return nil, "cannot read " .. file
  end
  return M.parse_lines(lines, vim.env.HOME)
end

return M
