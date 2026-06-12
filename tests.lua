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
  for t = 1, 3 do
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

-- ── 2.1: Attack probability tables match spec ────────────────────────────────
do
  local expected = {
    [2] = { ["High Card"]=19,["Pair"]=16,["Two Pair"]=14,["Three of a Kind"]=12,["Flush"]=14,["Straight"]=10,["Full House"]=9,["Four of a Kind"]=6 },
    [3] = { ["High Card"]=17,["Pair"]=14,["Two Pair"]=12,["Three of a Kind"]=10,["Flush"]=16,["Straight"]=12,["Full House"]=11,["Four of a Kind"]=8 },
  }
  for t,exp in pairs(expected) do
    local probs = Attacks.probs_for_threshold(t)
    for hand,v in pairs(exp) do
      assert(probs[hand] == v, "T"..t.." mismatch on "..hand..": expected "..v.." got "..tostring(probs[hand]))
    end
  end
end
print("2.1 Attack probability tables: passed")

-- ── 2.2: Penalty formula matches spec ────────────────────────────────────────
do
  local S = {}
  Scoring.init(S)
  local cases = {
    { hand="High Card",      t=1, expected=2  },
    { hand="High Card",      t=2, expected=5  },
    { hand="High Card",      t=3, expected=12 },
    { hand="Pair",           t=1, expected=4  },
    { hand="Pair",           t=2, expected=9  },
    { hand="Pair",           t=3, expected=21 },
    { hand="Four of a Kind", t=1, expected=32 },
    { hand="Four of a Kind", t=2, expected=72 },
    { hand="Four of a Kind", t=3, expected=162},
  }
  for _, c in ipairs(cases) do
    S.meta.threshold = c.t
    S.meta.score = 0
    local pts = Scoring.apply_penalty(S, c.hand)
    assert(pts == c.expected, "Penalty mismatch "..c.hand.." T"..c.t..": expected "..c.expected.." got "..tostring(pts))
    S.meta.score = 0
  end
end
print("2.2 Penalty formula: passed")

-- ── 2.3: Joker rarity distribution matches draw weights (smoke test) ─────────
do
  local REG = require("joker_registry")
  local S = {}
  Jokers.init(S, love.math)
  local N = 1000
  local counts = {}
  for _ = 1, N do
    S.jokers.hand = {}  -- keep clear of the hand cap so every draw lands
    Jokers.gain_from_pool(S, 1, love.math)
    assert(#S.jokers.hand == 1, "gain_from_pool should add exactly 1 joker")
    local def = REG.by_id[S.jokers.hand[1]]
    assert(def, "Unknown joker id drawn: "..tostring(S.jokers.hand[1]))
    counts[def.rarity] = (counts[def.rarity] or 0) + 1
  end
  -- Each rarity's observed share must be within ±8 percentage points of its
  -- expected probability (weight / total weight; weights need not sum to 100).
  local total_w = 0
  for _, w in pairs(REG.rarity_weights) do total_w = total_w + w end
  for rarity, weight in pairs(REG.rarity_weights) do
    local expected_pct = (weight / total_w) * 100
    local share = ((counts[rarity] or 0) / N) * 100
    assert(math.abs(share - expected_pct) <= 8,
      string.format("Rarity %s share %.1f%% deviates more than 8pp from expected %.1f%%",
        rarity, share, expected_pct))
  end
end
print("2.3 Joker rarity distribution: passed")

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
  GS.endless = true
  GS.prep_turns_remaining = 2
  local UI = {}

  local saved = SaveLoad.build_state(deck, hand, GS, S, UI)

  -- Record exact joker hand contents before applying state.
  local saved_joker_hand = {}
  for i = 1, #saved.jokers.hand do saved_joker_hand[i] = saved.jokers.hand[i] end
  local saved_used_this_turn = saved.jokers.used_this_turn

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
  assert(#S.jokers.hand == #saved_joker_hand, "joker hand size mismatch")
  for i = 1, #saved_joker_hand do
    assert(S.jokers.hand[i] == saved_joker_hand[i], "joker hand[" .. i .. "] mismatch")
  end
  assert(S.jokers.used_this_turn == saved_used_this_turn, "used_this_turn mismatch")
  assert(#hand == #saved.hand,             "hand size mismatch")
  -- M3 fields: endless flag and prep turn counter must survive the round trip
  assert(GS.endless == true,               "endless flag lost")
  assert(GS.prep_turns_remaining == 2,     "prep_turns_remaining lost")
  assert(GS.phase == "MAIN",               "phase mismatch (expected MAIN)")

  -- Variant: a save taken during the PREP phase must restore as PREP
  GS.phase = "PREP"
  GS.prep_turns_remaining = 3
  local saved_prep = SaveLoad.build_state(deck, hand, GS, S, UI)
  GS:reset()
  S.meta = {}
  S.jokers = nil
  UI = {}
  hand = SaveLoad.apply_state(saved_prep, deck, GS, S, UI, Scoring, Jokers)
  assert(GS.phase == "PREP",               "PREP phase not restored")
  assert(GS.prep_turns_remaining == 3,     "PREP turn counter not restored")
end
print("Save/Load round trip test: passed")

-- ── M3: Win condition test ────────────────────────────────────────────────────
do
  local Rules = require("rules")

  local function win_checks(S, GS)
    local t3_win = (S.meta.threshold == 3)
                 and Scoring.is_threshold_complete(S)
                 and Rules.isAllMarked(GS)
    local threshold_done = (S.meta.threshold ~= 3)
                         and Scoring.is_threshold_complete(S)
    return t3_win, threshold_done
  end

  -- Scenario A: T3, score >= 300, all 8 hands marked → win
  local S = {}
  Scoring.init(S)
  S.meta.threshold = 3
  S.meta.score = 300
  GS:reset()
  for _, name in ipairs(Rules.CATEGORIES) do GS.playedHands[name] = true end
  local t3_win, threshold_done = win_checks(S, GS)
  assert(t3_win == true,         "Scenario A: t3_win should be true")
  assert(threshold_done == false,"Scenario A: threshold_done should be false at T3")

  -- Scenario B: T3, score >= 300, only 7 hands marked → no win
  GS:reset()
  for i = 1, 7 do GS.playedHands[Rules.CATEGORIES[i]] = true end
  assert(Scoring.is_threshold_complete(S) == true, "Scenario B: score target reached")
  assert(Rules.isAllMarked(GS) == false,           "Scenario B: checklist incomplete")
  t3_win, threshold_done = win_checks(S, GS)
  assert(t3_win == false,         "Scenario B: win must not trigger")
  assert(threshold_done == false, "Scenario B: threshold_done must be false at T3")

  -- Scenario C: T2, score >= 150 → threshold completes, no win
  S.meta.threshold = 2
  S.meta.score = 150
  GS:reset()
  t3_win, threshold_done = win_checks(S, GS)
  assert(t3_win == false,        "Scenario C: not a win at T2")
  assert(threshold_done == true, "Scenario C: threshold_done should be true")
end
print("Win condition test: passed")

-- ── M3: Prep phase test ───────────────────────────────────────────────────────
do
  -- Skip bonus: base 5/10/15 × threshold multiplier (×1 T1, ×2 T2, ×4 T3, ×6 T4+)
  assert(Scoring.prep_skip_bonus(1, 1) == 5,  "prep_skip_bonus(1,1) ~= 5")
  assert(Scoring.prep_skip_bonus(3, 1) == 15, "prep_skip_bonus(3,1) ~= 15")
  assert(Scoring.prep_skip_bonus(1, 2) == 10, "prep_skip_bonus(1,2) ~= 10")
  assert(Scoring.prep_skip_bonus(3, 2) == 30, "prep_skip_bonus(3,2) ~= 30")
  assert(Scoring.prep_skip_bonus(2, 3) == 40, "prep_skip_bonus(2,3) ~= 40")
  assert(Scoring.prep_skip_bonus(3, 4) == 90, "prep_skip_bonus(3,4) ~= 90")
end
print("Prep phase test: passed")

-- 2.4: Joker effects
local FX = require("joker_effects")
local JReg = require("joker_registry")

-- bee: removes least rare joker, hand shrinks by 1
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.hand = { "bicycle", "skull" }  -- common, uncommon
  local gained = {}
  local ctx = { rng = love.math, gain_from_pool = function(n)
    for i=1,n do table.insert(gained, "test_joker") end
  end }
  local r = FX.bee(S, ctx)
  assert(r.ok, "bee should succeed")
  -- bicycle (common) should be discarded; skull remains
  assert(S.jokers.hand[1] == "skull", "bee should discard least rare (bicycle)")
  assert(#gained == 2, "bee should draw 2 jokers")
end
print("2.4 bee effect: passed")

-- fibonacci: gains jokers equal to checklist count
do
  local S = {}
  Jokers.init(S, love.math)
  local gained = {}
  local ctx = {
    rng = love.math,
    playedHands = { ["Pair"]=true, ["Flush"]=true, ["High Card"]=true },
    gain_from_pool = function(n)
      for i=1,n do table.insert(gained, "x") end
    end
  }
  local r = FX.fibonacci(S, ctx)
  assert(r.ok, "fibonacci should succeed")
  assert(#gained == 3, "fibonacci should gain 3 jokers (one per marked hand)")
end
print("2.4 fibonacci effect: passed")

-- steal: sets pending state correctly
do
  local S = {}
  Jokers.init(S, love.math)
  Jokers.gain_from_pool(S, 0, love.math)  -- ensure pool exists
  -- manually seed the pool with known ids
  S.jokers.pool = { "bicycle", "skull", "steal" }
  local r = FX.steal(S, {})
  assert(r.ok, "steal should succeed")
  assert(S.jokers.steal_choice_pending == true, "steal should set pending flag")
  assert(#S.jokers.steal_pending.ids == 2, "steal should reveal 2 jokers")
  assert(#S.jokers.pool == 1, "steal should remove 2 from pool")
end
print("2.4 steal effect: passed")

-- angel: sets pending state correctly
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.hand = { "bicycle", "skull" }
  local r = FX.angel(S, {})
  assert(r.ok, "angel should succeed")
  assert(S.jokers.angel_choice_pending == true, "angel should set pending flag")
  assert(#S.jokers.angel_pending.ids == 2, "angel should store current hand")
end
print("2.4 angel effect: passed")

-- ── Joker cap overflow test ──────────────────────────────────────────────────
-- Rule Book: max 5 jokers in hand; draws while at cap must NOT grow the hand.
do
  local S = {}
  Jokers.init(S, love.math)
  -- Force the hand to already sit at the cap of 5.
  S.jokers.hand = { "bicycle", "bicycle", "bicycle", "bicycle", "bicycle" }
  -- Attempt to gain a 6th joker.
  Jokers.gain_from_pool(S, 1, love.math)
  assert(#S.jokers.hand == 5, "joker hand grew past cap: got "..#S.jokers.hand)
end
print("Joker cap overflow test: passed")

-- ── v3.1 Area 1: Deck depletion loss condition ───────────────────────────────
do
  local Rules = require("rules")
  local deck = Deck.new(1)
  -- Empty both the main deck and discard pile (nothing left to reshuffle).
  deck.cards = {}
  deck.discard = {}
  assert(#deck.cards == 0 and #deck.discard == 0,
    "depletion: main deck and discard must both be empty")

  local S = {}
  Scoring.init(S)
  S.meta.score = 0
  GS:reset()  -- GS.playedHands starts empty
  local score_met   = Scoring.is_threshold_complete(S)
  local all_marked  = Rules.isAllMarked(GS)
  assert(score_met == false,  "depletion: score target must be unmet")
  assert(all_marked == false, "depletion: not all categories marked")
  -- Either win condition unmet → the run would end in a loss.
  assert(not (score_met and all_marked), "depletion: loss should trigger")
end
print("Depletion condition test: passed")

-- ── v3.1 Area 2: Infinite joker pool draws valid, varied jokers ──────────────
do
  local REG = require("joker_registry")
  local S = {}
  Jokers.init(S, love.math)
  local seen = {}
  for _ = 1, 100 do
    S.jokers.hand = {}  -- keep clear of the cap so every draw lands
    local jid = Jokers.gain_joker(S, love.math)
    assert(jid and REG.by_id[jid], "gain_joker returned an invalid id: "..tostring(jid))
    seen[jid] = true
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  assert(distinct >= 2, "expected at least 2 distinct joker ids across 100 draws")
end
print("Joker pool probability test: passed")

-- ── v3.1 Area 3: Food Joker passive grants +3 hand cap ───────────────────────
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.hand = { "food" }   -- Food Joker passive in hand
  Jokers.start_turn(S)         -- refreshes passives
  assert(S.jokers.modifiers.hand_cap_bonus == 3,
    "Food Joker should grant +3 hand cap bonus, got "..tostring(S.jokers.modifiers.hand_cap_bonus))
end
print("Food Joker hand cap test: passed")

-- ── v3.1 Area 4: Skull halves the current attack's penalty ───────────────────
do
  local S = {}
  Scoring.init(S)
  S.meta.threshold = 1
  S.meta.score = 0
  S.combat = { current_attack = "Four of a Kind" }  -- full T1 penalty = 32
  -- Full penalty (without the Skull flag) for reference.
  local full = Scoring.apply_penalty(S, "Four of a Kind")
  S.meta.score = 0
  -- Now with Skull active, the applied penalty must be ceil(full / 2).
  S.combat = { current_attack = "Four of a Kind" }
  FX.skull(S, {})
  local res = Attacks.resolve(S, Scoring)
  assert(res.penalized, "Skull test: attack should still penalize")
  assert(res.halved, "Skull test: result should be flagged halved")
  assert(res.penalty == math.ceil(full / 2),
    string.format("Skull test: penalty %d != ceil(%d/2)=%d", res.penalty, full, math.ceil(full/2)))
  assert(S.meta.score == -math.ceil(full / 2),
    "Skull test: score should drop by the halved penalty only")
end
print("Skull halve test: passed")

print("\nAll tests passed.")
