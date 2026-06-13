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

-- Cute Joker (2.4): exactly 6 cards forming two valid, SEPARATE three-of-a-kinds.
-- Valid only when the 6 cards split into two distinct ranks, each appearing
-- exactly 3 times. A 6-of-a-kind (all one rank) is explicitly rejected.
function Eval.is_two_trips(cards)
  if not cards or #cards ~= 6 then return false end
  local counts = countsByRank(cards)
  local trips = 0
  local distinct = 0
  for _, cnt in pairs(counts) do
    distinct = distinct + 1
    if cnt == 3 then trips = trips + 1 end
  end
  -- Two ranks, each exactly three → two separate trips. (Six of a kind would be
  -- a single rank with count 6, so distinct == 1 and is rejected here.)
  return distinct == 2 and trips == 2
end

-- The Architect (2.11): from up to 5 cards, return the HIGHEST valid poker
-- category present (considering both rank and suit). Unlike exact_category (which
-- is minimal), this scans best→worst so e.g. a flush beats a contained pair.
local CATEGORY_RANK = {
  ["Four of a Kind"]=8, ["Full House"]=7, ["Flush"]=6, ["Straight"]=5,
  ["Three of a Kind"]=4, ["Two Pair"]=3, ["Pair"]=2, ["High Card"]=1,
}

function Eval.best_category(cards)
  if not cards or #cards == 0 or #cards > 5 then return nil end
  local counts = countsByRank(cards)
  local pairs_, trips, quads = 0, 0, 0
  for _, cnt in pairs(counts) do
    if cnt == 4 then quads = quads + 1
    elseif cnt == 3 then trips = trips + 1
    elseif cnt == 2 then pairs_ = pairs_ + 1 end
  end
  local best = nil
  local function consider(cat)
    if not best or CATEGORY_RANK[cat] > CATEGORY_RANK[best] then best = cat end
  end
  if quads >= 1 then consider("Four of a Kind") end
  if trips >= 1 and pairs_ >= 1 then consider("Full House") end
  if #cards == 5 and isFlush5(cards) then consider("Flush") end
  if #cards == 5 and isStraight5(cards) then consider("Straight") end
  if trips >= 1 then consider("Three of a Kind") end
  if pairs_ >= 2 then consider("Two Pair") end
  if pairs_ >= 1 then consider("Pair") end
  consider("High Card")
  return best
end

return Eval

