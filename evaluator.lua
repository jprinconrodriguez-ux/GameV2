-- evaluator.lua
local Eval = {}

local rankValue = {
  ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10,
  ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14
}

local function countsByRank(cards)
  local counts = {}
  for _, c in ipairs(cards) do
    counts[c.rank] = (counts[c.rank] or 0) + 1
  end
  return counts
end

local function isFlush5(cards)
  local s = cards[1].suit
  for i = 2, 5 do
    if cards[i].suit ~= s then return false end
  end
  return true
end

local function isStraight5(cards)
  local valsMap = {}
  for _, c in ipairs(cards) do
    valsMap[ rankValue[c.rank] ] = true
  end
  local vals = {}
  for v,_ in pairs(valsMap) do table.insert(vals, v) end
  table.sort(vals)

  local function isAceLow()
    return valsMap[14] and valsMap[2] and valsMap[3] and valsMap[4] and valsMap[5]
  end

  if #vals ~= 5 then
    return isAceLow()
  end

  for i = 2, 5 do
    if vals[i] ~= vals[i-1] + 1 then
      return isAceLow()
    end
  end
  return true
end

-- Return a single exact/minimal category for 1–5 selected cards, or nil if invalid
function Eval.exact_category(cards)
  local n = #cards
  if n == 0 or n > 5 then return nil end

  if n == 1 then
    return "High Card"
  end

  local counts = countsByRank(cards)
  if n == 2 then
    for _, cnt in pairs(counts) do
      if cnt == 2 then return "Pair" end
    end
    return nil
  end

  if n == 3 then
    for _, cnt in pairs(counts) do
      if cnt == 3 then return "Three of a Kind" end
    end
    return nil
  end

  if n == 4 then
    local pairCount, four = 0, false
    for _, cnt in pairs(counts) do
      if cnt == 4 then four = true end
      if cnt == 2 then pairCount = pairCount + 1 end
    end
    if four then return "Four of a Kind" end
    if pairCount == 2 then return "Two Pair" end
    return nil
  end

  -- n == 5
  local has3, has2 = false, false
  for _, cnt in pairs(counts) do
    if cnt == 3 then has3 = true end
    if cnt == 2 then has2 = true end
  end
  if has3 and has2 then return "Full House" end
  if isFlush5(cards) then return "Flush" end
  if isStraight5(cards) then return "Straight" end
  return nil
end

return Eval

