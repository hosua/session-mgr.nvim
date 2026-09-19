--- fzf-style subsequence matching on session names. Pure.
---
--- Used two ways: the picker only asks "does it match, and where" (the
--- chosen sort column still orders the rows), while the save popup also
--- ranks candidates by score for Tab completion.
local M = {}

local BONUS_START = 8 -- match at the very start of the name
local BONUS_BOUNDARY = 6 -- match right after - _ . space, or at a lower->Upper step
local BONUS_CONSECUTIVE = 5
local PENALTY_GAP = 1 -- per skipped character between two matches

local function is_boundary(str, i)
  if i == 1 then
    return true
  end
  local prev, cur = str:sub(i - 1, i - 1), str:sub(i, i)
  return prev:find "[-_%. /]" ~= nil or (prev:find "%l" ~= nil and cur:find "%u" ~= nil)
end

--- Smartcase: an all-lowercase query ignores case, any uppercase makes it exact.
--- Greedy leftmost match, then pulled right-to-left so trailing characters
--- bind to the closest occurrence ("sm" in "session-mgr" -> s...m of "mgr").
--- @param query string
--- @param str string
--- @return integer[]|nil positions 1-based byte indexes into `str`, or nil
function M.match(query, str)
  if query == "" then
    return {}
  end
  local smart = query:find "%u" == nil
  local hay = smart and str:lower() or str
  local positions, from = {}, 1
  for i = 1, #query do
    local at = hay:find(query:sub(i, i), from, true)
    if not at then
      return nil
    end
    positions[i] = at
    from = at + 1
  end
  -- Backward pass: tighten each earlier match towards the one after it.
  for i = #query - 1, 1, -1 do
    local ch, limit, best = query:sub(i, i), positions[i + 1] - 1, positions[i]
    for j = limit, positions[i] + 1, -1 do
      if hay:sub(j, j) == ch then
        best = j
        break
      end
    end
    positions[i] = best
  end
  return positions
end

--- Higher is better. Only meaningful between candidates for the same query.
--- @param positions integer[]
--- @param str string
--- @return integer
function M.score(positions, str)
  if #positions == 0 then
    return 0 -- empty query: no ranking, the caller's order stands
  end
  local score = 0
  for i, pos in ipairs(positions) do
    if pos == 1 then
      score = score + BONUS_START
    elseif is_boundary(str, pos) then
      score = score + BONUS_BOUNDARY
    end
    if i > 1 then
      local gap = pos - positions[i - 1] - 1
      score = score + (gap == 0 and BONUS_CONSECUTIVE or -gap * PENALTY_GAP)
    end
  end
  return score - math.floor(#str / 8) -- among equals, prefer the shorter name
end

--- Filter and rank. Stable for equal scores (keeps the caller's order).
--- @generic T
--- @param query string
--- @param items T[]
--- @param key (fun(item: T): string)|nil defaults to identity
--- @return { item: T, positions: integer[], score: integer }[]
function M.filter(query, items, key)
  local out = {}
  for i, item in ipairs(items) do
    local str = key and key(item) or item
    local positions = M.match(query, str)
    if positions then
      out[#out + 1] = { item = item, positions = positions, score = M.score(positions, str), _i = i }
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a._i < b._i
  end)
  for _, o in ipairs(out) do
    o._i = nil
  end
  return out
end

return M
