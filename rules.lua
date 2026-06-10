-- rules.lua
-- Central place for categories and sorting rules/helpers
local Rules = {}

-- Categories used by the "played-once" board
Rules.CATEGORIES = {
  "High Card",
  "Pair",
  "Two Pair",
  "Three of a Kind",
  "Straight",
  "Flush",
  "Full House",
  "Four of a Kind"
}

-- Check if all categories are marked in the given gamestate
function Rules.isAllMarked(gs)
  for _, name in ipairs(Rules.CATEGORIES) do
    if not gs.playedHands[name] then return false end
  end
  return true
end

-- Sort orders
Rules.SUIT_ORDER = { ["♠"]=1, ["♥"]=2, ["♦"]=3, ["♣"]=4 } -- left→right (spades → hearts → diamonds → clubs)
Rules.RANK_ORDER = {
  ["A"]=14, ["K"]=13, ["Q"]=12, ["J"]=11, ["10"]=10,
  ["9"]=9, ["8"]=8, ["7"]=7, ["6"]=6, ["5"]=5, ["4"]=4, ["3"]=3, ["2"]=2
}

-- Sort by rank: A-high → 2-low; tie-break by suit order ♠ ♥ ♦ ♣
function Rules.sortHandByRank(hand)
  table.sort(hand, function(a,b)
    local ra = Rules.RANK_ORDER[tostring(a.rank)] or -math.huge
    local rb = Rules.RANK_ORDER[tostring(b.rank)] or -math.huge
    if ra ~= rb then return ra > rb end
    local sa = Rules.SUIT_ORDER[a.suit] or 99
    local sb = Rules.SUIT_ORDER[b.suit] or 99
    return sa < sb
  end)
end

-- Sort by suit: ♠ ♥ ♦ ♣ left→right; within each suit ranks A-high → 2-low
function Rules.sortHandBySuit(hand)
  table.sort(hand, function(a,b)
    local sa = Rules.SUIT_ORDER[a.suit] or 99
    local sb = Rules.SUIT_ORDER[b.suit] or 99
    if sa ~= sb then return sa < sb end
    local ra = Rules.RANK_ORDER[tostring(a.rank)] or -math.huge
    local rb = Rules.RANK_ORDER[tostring(b.rank)] or -math.huge
    return ra > rb
  end)
end

return Rules
