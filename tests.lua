-- tests.lua
-- Basic automated checks for Jokers Gambit

love = { math = { random = math.random } }

local Deck = require("deck")
local Jokers = require("jokers")
local Attacks = require("attacks")
local SaveLoad = require("saveload")
local Scoring = require("scoring")
local GS = require("gamestate")

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k,v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k,v in pairs(b) do if not deep_eq(v, a[k]) then return false end end
  return true
end

-- Turn flow: joker use capped at 1
do
  local S = {}
  Jokers.init(S, love.math)
  Jokers.gain_from_pool(S, 2, love.math)
  assert(#S.jokers.hand >= 2, "need two jokers for test")
  local r1 = Jokers.use(S, 1, {})
  assert(r1.ok, "first joker should succeed")
  local r2 = Jokers.use(S, 1, {})
  assert(not r2.ok, "second joker should be blocked")
end
print("Turn flow test: passed")

-- Attack scaling probabilities snapshot (Rule Book values)
do
  local expected = {
    [1] = { ["High Card"]=21,["Pair"]=18,["Two Pair"]=16,["Three of a Kind"]=14,["Flush"]=12,["Straight"]=8,["Full House"]=7,["Four of a Kind"]=4 },
    [2] = { ["High Card"]=19,["Pair"]=16,["Two Pair"]=14,["Three of a Kind"]=12,["Flush"]=14,["Straight"]=10,["Full House"]=9,["Four of a Kind"]=6 },
    [3] = { ["High Card"]=17,["Pair"]=14,["Two Pair"]=12,["Three of a Kind"]=10,["Flush"]=16,["Straight"]=12,["Full House"]=11,["Four of a Kind"]=8 },
    [4] = { ["High Card"]=15,["Pair"]=12,["Two Pair"]=10,["Three of a Kind"]=8,["Flush"]=18,["Straight"]=14,["Full House"]=13,["Four of a Kind"]=10 },
    [5] = { ["High Card"]=13,["Pair"]=10,["Two Pair"]=8,["Three of a Kind"]=6,["Flush"]=20,["Straight"]=16,["Full House"]=15,["Four of a Kind"]=12 },
  }
  for t=1,5 do
    local probs = Attacks.probs_for_threshold(t)
    assert(deep_eq(probs, expected[t]), "Attack table mismatch at T"..t)
    -- Verify weights sum to 100
    local sum = 0
    for _,w in pairs(probs) do sum = sum + w end
    assert(sum == 100, "Attack weights do not sum to 100 at T"..t.." (got "..sum..")")
  end
end
print("Attack scaling test: passed")

-- Penalty values (Rule Book: T1 = 2×T1award, T2 = ceil(T1×2.25), T3 = ceil(T2×2.25))
do
  local expected = {
    ["High Card"]      = { [1]=2,  [2]=5,  [3]=12  },
    ["Pair"]           = { [1]=4,  [2]=9,  [3]=21  },
    ["Two Pair"]       = { [1]=8,  [2]=18, [3]=41  },
    ["Three of a Kind"]= { [1]=12, [2]=27, [3]=61  },
    ["Flush"]          = { [1]=16, [2]=36, [3]=81  },
    ["Straight"]       = { [1]=16, [2]=36, [3]=81  },
    ["Full House"]     = { [1]=16, [2]=36, [3]=81  },
    ["Four of a Kind"] = { [1]=32, [2]=72, [3]=162 },
  }
  for hand, tiers in pairs(expected) do
    for t, pen in pairs(tiers) do
      local S = { meta = { threshold = t, score = 0 } }
      local before = S.meta.score
      Scoring.apply_penalty(S, hand)
      local got = before - S.meta.score
      assert(got == pen, "Penalty mismatch "..hand.." T"..t..": expected "..pen.." got "..got)
    end
  end
end
print("Penalty test: passed")

-- Save/Load round trip
do
  local deck = Deck.new(1)
  GS:reset()
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  Jokers.gain_from_pool(S, 2, love.math)
  local hand = deck:draw(5)
  S.meta.score = 42
  S.meta.threshold = 2
  GS.playedHands["Pair"] = true
  deck:discardCards({deck.cards[#deck.cards]})
  Attacks.announce(S, love.math)
  GS.turn = 3
  GS.limits.discard_used = true
  local UI = {}

  local saved = SaveLoad.build_state(deck, hand, GS, S, UI)

  -- mutate everything
  deck = Deck.new(1)
  hand = deck:draw(3)
  GS:reset()
  S.meta = {}
  S.jokers = nil
  UI = {}

  hand = SaveLoad.apply_state(saved, deck, GS, S, UI, Scoring, Jokers)

  assert(S.meta.score == 42, "score mismatch")
  assert(S.meta.threshold == 2, "threshold mismatch")
  assert(GS.turn == 3, "turn mismatch")
  assert(GS.playedHands["Pair"], "played hand lost")
  assert(GS.limits.discard_used == true, "discard flag lost")
  assert(#deck.discard == 1, "discard pile mismatch")
  assert(S.combat.current_attack == saved.gs.current_attack, "attack mismatch")
  assert(#S.jokers.hand == #saved.jokers.hand, "joker hand mismatch")
  assert(#hand == #saved.hand, "hand size mismatch")
end
print("Save/Load round trip test: passed")

print("All tests passed.")

