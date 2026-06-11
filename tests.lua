-- tests.lua
-- Specification-asserting tests for Jokers' Gambit.
-- Source of truth: Rule Book. These tests FAIL if anyone introduces an off-spec number.
-- Run headless: lua tests.lua

love = { math = { random = math.random } }

local Deck    = require("deck")
local Jokers  = require("jokers")
local Attacks = require("attacks")
local SaveLoad = require("saveload")
local Scoring = require("scoring")
local GS      = require("gamestate")

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k,v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k,v in pairs(b) do if not deep_eq(v, a[k]) then return false end end
  return true
end

-- ── 1. Turn flow: joker use capped at 1 per turn ─────────────────────────────
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

-- ── 2. Attack probability tables (canonical Rule Book values) ─────────────────
do
  local expected = {
    [1] = { ["High Card"]=21,["Pair"]=18,["Two Pair"]=16,["Three of a Kind"]=14,
            ["Flush"]=12,["Straight"]=8,["Full House"]=7,["Four of a Kind"]=4 },
    [2] = { ["High Card"]=19,["Pair"]=16,["Two Pair"]=14,["Three of a Kind"]=12,
            ["Flush"]=14,["Straight"]=10,["Full House"]=9,["Four of a Kind"]=6 },
    [3] = { ["High Card"]=17,["Pair"]=14,["Two Pair"]=12,["Three of a Kind"]=10,
            ["Flush"]=16,["Straight"]=12,["Full House"]=11,["Four of a Kind"]=8 },
  }
  for t = 1, 3 do
    local probs = Attacks.probs_for_threshold(t)
    assert(deep_eq(probs, expected[t]), "Attack table mismatch at T"..t)
  end
end
print("Attack scaling test (spec): passed")

-- ── 3. Probability sum sanity: every threshold must sum to 100 ───────────────
do
  for t = 1, 5 do
    local probs = Attacks.probs_for_threshold(t)
    local sum = 0
    for _, w in pairs(probs) do sum = sum + w end
    assert(sum == 100, "Attack weights at T"..t.." sum to "..sum..", expected 100")
  end
end
print("Probability sum test: passed")

-- ── 4. Award values (canonical Rule Book table) ──────────────────────────────
do
  local cases = {
    { t=1, hand="High Card",       expected=1  },
    { t=1, hand="Pair",            expected=2  },
    { t=1, hand="Two Pair",        expected=4  },
    { t=1, hand="Three of a Kind", expected=6  },
    { t=1, hand="Flush",           expected=8  },
    { t=1, hand="Straight",        expected=8  },
    { t=1, hand="Full House",      expected=8  },
    { t=1, hand="Four of a Kind",  expected=16 },
    { t=2, hand="High Card",       expected=2  },
    { t=2, hand="Four of a Kind",  expected=32 },
    { t=3, hand="Pair",            expected=8  },
    { t=3, hand="Four of a Kind",  expected=64 },
  }
  for _, c in ipairs(cases) do
    local got = Scoring.get_award(c.t, c.hand)
    assert(got == c.expected,
      string.format("Award mismatch: T%d %s → got %d, expected %d",
        c.t, c.hand, got, c.expected))
  end
end
print("Award values test: passed")

-- ── 5. Penalty values (canonical Rule Book formula) ──────────────────────────
do
  -- Rule Book: T1 = 2×(T1 award). T2 = ceil(T1 penalty × 2.25). T3 = ceil(T2 penalty × 2.25).
  local cases = {
    { t=1, hand="High Card",       expected=2   },
    { t=1, hand="Pair",            expected=4   },
    { t=1, hand="Two Pair",        expected=8   },
    { t=1, hand="Three of a Kind", expected=12  },
    { t=1, hand="Flush",           expected=16  },
    { t=1, hand="Straight",        expected=16  },
    { t=1, hand="Full House",      expected=16  },
    { t=1, hand="Four of a Kind",  expected=32  },
    { t=2, hand="High Card",       expected=5   },
    { t=2, hand="Pair",            expected=9   },
    { t=2, hand="Four of a Kind",  expected=72  },
    { t=3, hand="High Card",       expected=12  },
    { t=3, hand="Pair",            expected=21  },
    { t=3, hand="Two Pair",        expected=41  },
    { t=3, hand="Three of a Kind", expected=61  },
    { t=3, hand="Flush",           expected=81  },
    { t=3, hand="Four of a Kind",  expected=162 },
  }
  local S = {}
  Scoring.init(S)
  for _, c in ipairs(cases) do
    S.meta.threshold = c.t
    local got = Scoring.apply_penalty(S, c.hand)
    -- undo the side-effect so cases are independent
    S.meta.score = 0
    assert(got == c.expected,
      string.format("Penalty mismatch: T%d %s → got %d, expected %d",
        c.t, c.hand, got, c.expected))
  end
end
print("Penalty values test: passed")

-- ── 6. Joker pool composition ─────────────────────────────────────────────────
-- NOTE: This test will FAIL until Milestone 2 fills all 22 jokers.
-- It is here to document the target. Comment it out to run M1 cleanly,
-- then uncomment when M2 is complete.
--[[
do
  local REG = require("joker_registry")
  local S = {}
  Jokers.init(S, love.math)
  -- Full Rule Book pool: 20 common + 15 uncommon + 12 rare + 12 epic + 16 legendary + 9 mythic = 84
  assert(#S.jokers.pool == 84,
    "Pool size mismatch: got "..#S.jokers.pool..", expected 84")
  -- Count by rarity
  local counts = {}
  for _, id in ipairs(S.jokers.pool) do
    local def = REG.by_id[id]
    local r = def and def.rarity or "unknown"
    counts[r] = (counts[r] or 0) + 1
  end
  assert(counts.common    == 20, "common mismatch: "..tostring(counts.common))
  assert(counts.uncommon  == 15, "uncommon mismatch: "..tostring(counts.uncommon))
  assert(counts.rare      == 12, "rare mismatch: "..tostring(counts.rare))
  assert(counts.epic      == 12, "epic mismatch: "..tostring(counts.epic))
  assert(counts.legendary == 16, "legendary mismatch: "..tostring(counts.legendary))
  assert(counts.mythic    ==  9, "mythic mismatch: "..tostring(counts.mythic))
end
print("Joker pool composition test: passed")
--]]
print("Joker pool composition test: SKIPPED (uncomment after M2)")

-- ── 7. Save/Load round trip ───────────────────────────────────────────────────
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

  deck = Deck.new(1)
  hand = deck:draw(3)
  GS:reset()
  S.meta = {}
  S.jokers = nil
  UI = {}

  hand = SaveLoad.apply_state(saved, deck, GS, S, UI, Scoring, Jokers)

  assert(S.meta.score == 42,               "score mismatch")
  assert(S.meta.threshold == 2,            "threshold mismatch")
  assert(GS.turn == 3,                     "turn mismatch")
  assert(GS.playedHands["Pair"],           "played hand lost")
  assert(GS.limits.discard_used == true,   "discard flag lost")
  assert(#deck.discard == 1,               "discard pile mismatch")
  assert(S.combat.current_attack == saved.gs.current_attack, "attack mismatch")
  assert(#S.jokers.hand == #saved.jokers.hand, "joker hand mismatch")
  assert(#hand == #saved.hand,             "hand size mismatch")
end
print("Save/Load round trip test: passed")

print("\nAll M1 tests passed.")
