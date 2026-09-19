--- Shared picker fixture: the user's mockup as data. NOW is fixed so every
--- relative time in a golden render is deterministic.
local F = {}
F.NOW = os.time { year = 2026, month = 9, day = 19, hour = 12, min = 0, sec = 0 }
local D = 86400
local function row(key, label, name, uses, last_used, updated, created, is_git)
  return {
    key = key,
    label = label,
    root = "/home/me/dev/" .. label,
    is_git = is_git ~= false,
    name = name,
    file = "/s/" .. key .. "/" .. name .. ".vim",
    uses = uses,
    last_used = last_used and (F.NOW - last_used) or nil,
    updated = F.NOW - updated,
    created = F.NOW - created,
  }
end
F.project_a = { key = "%a", root = "/home/me/dev/repo-a", label = "repo-a", is_git = true }
function F.rows_a()
  return {
    row("%a", "repo-a", "cool", 42, 8 * D, 6 * 3600, 30 * D),
    row("%a", "repo-a", "abc", 2, 60, 1 * D + 3600, 3 * D),
    row("%a", "repo-a", "default", 125, 5 * 60 + 57, 3600 + 32, 40 * D),
    row("%a", "repo-a", "coolio", 7, 10, 20, 2 * D),
    row("%a", "repo-a", "cooli", 0, nil, 14 * D, 14 * D),
  }
end
function F.rows_all()
  local rows = F.rows_a()
  vim.list_extend(rows, {
    row("%b", "repo-b", "cooli", 1, 14 * D, 14 * D, 20 * D),
    row("%b", "repo-b", "cool", 42, 7 * D, 5 * D, 25 * D),
    row("%z", "Notes", "default", 3, 3600, 7200, 9 * D, false),
  })
  return rows
end
return F
