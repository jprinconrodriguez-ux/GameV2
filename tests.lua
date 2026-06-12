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

-- ═══════════════════════════ M4 TESTS ═══════════════════════════
local Effects = require("effects")
local Eval    = require("evaluator")
local Rules   = require("rules")

-- ── M4 4.1: resolve_steal places the chosen id in hand, clears the flag ──────
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.pool = { "bicycle", "skull", "steal" }
  FX.steal(S, {})
  local ids = S.jokers.steal_pending.ids
  local r = FX.resolve_steal(S, 1)
  assert(r.ok, "resolve_steal should succeed")
  assert(S.jokers.hand[#S.jokers.hand] == ids[1], "chosen joker should be in hand")
  assert(not S.jokers.steal_choice_pending, "steal pending flag should clear")
  assert(S.jokers.steal_pending == nil, "steal pending data should clear")
end
print("M4 resolve_steal: passed")

-- ── M4 4.1: resolve_acrobat removes chosen cards from deck, clears the flag ──
do
  local deck = Deck.new(1)
  local hand = {}
  local S = {}
  Jokers.init(S, love.math)
  local before = #deck.cards
  FX.acrobat(S, { deck = deck })
  assert(S.jokers.acrobat_choice_pending == true, "acrobat should set pending flag")
  assert(#S.jokers.acrobat_pending.cards == 10, "acrobat should peek 10 cards")
  local picked = { S.jokers.acrobat_pending.cards[1], S.jokers.acrobat_pending.cards[3] }
  local r = FX.resolve_acrobat(S, { deck = deck, hand = hand }, { 1, 3 })
  assert(r.ok, "resolve_acrobat should succeed")
  assert(#deck.cards == before - 2, "two cards should leave the deck")
  assert(#hand == 2, "two cards should join the hand")
  for _, p in ipairs(picked) do
    local found = false
    for _, c in ipairs(hand) do if c == p then found = true end end
    assert(found, "picked card missing from hand")
  end
  assert(not S.jokers.acrobat_choice_pending, "acrobat pending flag should clear")
end
print("M4 resolve_acrobat: passed")

-- ── M4 4.1: resolve_eye writes the new order back into the pool ──────────────
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.pool = { "p1","p2","p3","p4","p5","p6","p7","p8","p9","p10","p11","p12" }
  FX.eye(S, {})
  assert(#S.jokers.eye_pending.ids == 10, "eye should peek 10 jokers")
  local new_order = {}
  for i = #S.jokers.eye_pending.ids, 1, -1 do
    table.insert(new_order, S.jokers.eye_pending.ids[i])
  end
  local r = FX.resolve_eye(S, new_order)
  assert(r.ok, "resolve_eye should succeed")
  local n = #S.jokers.pool
  for k, id in ipairs(new_order) do
    assert(S.jokers.pool[n - (k - 1)] == id,
      "pool slot "..(n - (k - 1)).." should hold "..id)
  end
  assert(not S.jokers.eye_choice_pending, "eye pending flag should clear")
end
print("M4 resolve_eye: passed")

-- ── M4 4.1: resolve_angel copies the chosen joker (respects cap) ─────────────
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.hand = { "bicycle", "skull" }
  FX.angel(S, {})
  local r = FX.resolve_angel(S, 2)
  assert(r.ok, "resolve_angel should succeed")
  assert(#S.jokers.hand == 3 and S.jokers.hand[3] == "skull", "copy should land in hand")
  assert(not S.jokers.angel_choice_pending, "angel pending flag should clear")
  -- At the cap, the copy is dropped.
  S.jokers.hand = { "bicycle", "bicycle", "bicycle", "bicycle", "bicycle" }
  FX.angel(S, {})
  FX.resolve_angel(S, 1)
  assert(#S.jokers.hand == 5, "angel must not grow the hand past the cap")
end
print("M4 resolve_angel: passed")

-- ── M4 4.2: Effects engine round-trip, tick, coexistence, clear_tag ──────────
do
  local S = {}
  Effects.add(S, "attack_shield", 3, { no_carry = true }, "anti")
  assert(Effects.has(S, "attack_shield"), "add+has round trip")
  assert(Effects.get(S, "attack_shield").no_carry == true, "add+get round trip")
  Effects.add(S, "score_multiplier", 2, { mult = 1.5 }, "galaxy")
  assert(Effects.has(S, "attack_shield") and Effects.has(S, "score_multiplier"),
    "two effects with different ids must coexist")
  assert(Effects.get(S, "score_multiplier").mult == 1.5, "payloads must not interfere")
  Effects.tick(S)  -- shield→2, mult→1
  Effects.tick(S)  -- shield→1, mult expired
  assert(Effects.has(S, "attack_shield"), "shield should survive 2 ticks")
  assert(not Effects.has(S, "score_multiplier"), "multiplier should expire after 2 ticks")
  Effects.tick(S)  -- shield expired
  assert(not Effects.has(S, "attack_shield"), "shield should expire after 3 ticks")

  local S2 = {}
  Effects.add(S2, "a", 5, { no_carry = true }, "x")
  Effects.add(S2, "b", 5, { no_carry = false }, "y")
  Effects.clear_tag(S2, "no_carry")
  assert(not Effects.has(S2, "a"), "no_carry effect must be removed by clear_tag")
  assert(Effects.has(S2, "b"), "carrying effect must survive clear_tag")

  -- Cybernetic tick keeps turn_index in sync (incremented before the decrement).
  local S3 = {}
  Effects.add(S3, "cybernetic", 3, { hacks = {}, turn_index = 0, no_carry = true }, "cybernetic")
  Effects.tick(S3)
  assert(Effects.get(S3, "cybernetic").turn_index == 1, "tick should advance cybernetic turn_index")
  assert(S3.active_effects[1].turns_remaining == 2, "tick should decrement turns_remaining")
end
print("M4 effects engine: passed")

-- ── M4 4.3: Anti-Joker shields attacks for 3 turns then expires ──────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  FX.anti_joker(S, {})
  assert(Effects.has(S, "attack_shield"), "anti_joker should add attack_shield")
  assert(Effects.get(S, "attack_shield").no_carry == true, "shield must not carry thresholds")
  S.combat = { current_attack = "Pair" }
  local res = Attacks.resolve(S, Scoring)
  assert(res.shielded and res.target == "Pair", "resolve should report shielded")
  assert(S.meta.score == 0, "shielded attack must not change score")
  Effects.tick(S); Effects.tick(S); Effects.tick(S)
  assert(not Effects.has(S, "attack_shield"), "shield should expire after 3 turns")
  S.combat = { current_attack = "Pair" }
  res = Attacks.resolve(S, Scoring)
  assert(res.penalized and res.penalty == 4, "attacks must penalize again after expiry")
end
print("M4 anti-joker: passed")

-- ── M4 4.3: Purge protects selected hands; others still penalize ─────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  FX.purge(S, {})
  assert(S.jokers.purge_pending == true, "purge should open the selection")
  S.jokers.purge_selected = { "Pair", "Flush" }
  local r = FX.resolve_purge(S)
  assert(r.ok and not S.jokers.purge_pending, "resolve_purge should clear pending state")
  local p = Effects.get(S, "purge_immunity")
  assert(p and p.hands[1] == "Pair" and p.hands[2] == "Flush",
    "purge payload must contain the selected hands")
  S.combat = { current_attack = "Pair" }
  local res = Attacks.resolve(S, Scoring)
  assert(res.purged and S.meta.score == 0, "purged hand must take no penalty")
  S.combat = { current_attack = "High Card" }
  res = Attacks.resolve(S, Scoring)
  assert(res.penalized and res.penalty == 2, "non-purged hand must still penalize")
end
print("M4 purge: passed")

-- ── M4 4.4: Cybernetic states (per-turn read, double, protected, lose) ───────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  Effects.add(S, "cybernetic", 3,
    { hacks = { ["Pair"] = { "d", "p", "l" } }, turn_index = 1, no_carry = true },
    "cybernetic")
  -- turn 1: "d" doubles the award (Pair T1 = 2 → 4)
  assert(Scoring.apply_award(S, "Pair") == 4, "double state should double the award")
  S.meta.score = 0
  -- turn 2: "p" protects against the attack
  Effects.get(S, "cybernetic").turn_index = 2
  S.combat = { current_attack = "Pair" }
  local res = Attacks.resolve(S, Scoring)
  assert(res.protected, "protected state should block the attack")
  assert(S.meta.score == 0, "protected attack must not change score")
  -- turn 3: "l" zeroes the award
  Effects.get(S, "cybernetic").turn_index = 3
  assert(Scoring.apply_award(S, "Pair") == 0, "lose state should award 0 points")
  -- no_carry removal on threshold advance
  Effects.clear_tag(S, "no_carry")
  assert(not Effects.has(S, "cybernetic"), "cybernetic must not carry thresholds")

  -- Generated payload shape: 2 distinct hands × 3 valid per-turn states.
  local S2 = {}
  Jokers.init(S2, love.math)
  FX.cybernetic(S2, { rng = love.math })
  local pay = Effects.get(S2, "cybernetic")
  assert(pay.no_carry == true and pay.turn_index == 0, "cybernetic payload defaults")
  local hands = 0
  for h, sts in pairs(pay.hacks) do
    hands = hands + 1
    assert(#sts == 3, "each hacked hand needs 3 turn states")
    for _, st in ipairs(sts) do
      assert(st == "n" or st == "d" or st == "p" or st == "l", "invalid state key "..tostring(st))
    end
  end
  assert(hands == 2, "cybernetic must hack exactly 2 hands")
end
print("M4 cybernetic: passed")

-- ── M4 4.5: The Flush doubles only when the attack is also a Flush ───────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  FX.flush_joker(S, {})
  assert(S.jokers.flush_active == true, "flush joker should arm the flag")
  S.combat = { current_attack = "Flush" }
  assert(Scoring.apply_award(S, "Flush") == 16, "Flush vs Flush attack should double (T1: 8→16)")
  assert(S.jokers.flush_active == nil, "flag consumed after a Flush play")
  S.meta.score = 0
  FX.flush_joker(S, {})
  S.combat = { current_attack = "Pair" }
  assert(Scoring.apply_award(S, "Flush") == 8, "no double when attack is not a Flush")
  assert(S.jokers.flush_active == nil, "flag consumed even without doubling")
end
print("M4 the flush: passed")

-- ── M4 4.5: The Trader unmarks a hand; next hand scores double ───────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local played = { ["Pair"] = true }
  local r = FX.trader(S, { rng = love.math, playedHands = played })
  assert(r.ok, "trader should succeed with a marked hand")
  assert(played["Pair"] == nil, "trader must unmark the chosen hand")
  assert(S.jokers.trader_double == true, "trader must arm the double")
  assert(Scoring.apply_award(S, "Pair") == 4, "next hand doubles (T1 Pair: 2→4)")
  assert(S.jokers.trader_double == false, "double consumed after one hand")
  S.meta.score = 0
  assert(Scoring.apply_award(S, "Pair") == 2, "subsequent hands score normally")
  local r2 = FX.trader(S, { rng = love.math, playedHands = {} })
  assert(r2.ok == false, "trader must fail with no completed hands")
end
print("M4 the trader: passed")

-- ── M4 4.5: Four of Clubs bonus (+6 at T1, doubling per threshold) ───────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  S.jokers.hand = { "fourofclubs" }
  local club_cards = { {suit="♣", rank="9"}, {suit="♥", rank="9"} }
  local four_cards = { {suit="♥", rank="4"}, {suit="♦", rank="4"} }
  local plain      = { {suit="♥", rank="9"}, {suit="♦", rank="9"} }
  assert(Scoring.apply_award(S, "Pair", club_cards) == 2 + 6,  "T1 club bonus = +6")
  S.meta.threshold = 2
  assert(Scoring.apply_award(S, "Pair", four_cards) == 4 + 12, "T2 four-rank bonus = +12")
  S.meta.threshold = 3
  assert(Scoring.apply_award(S, "Pair", four_cards) == 8 + 24, "T3 bonus = +24")
  S.meta.threshold = 1
  assert(Scoring.apply_award(S, "Pair", plain) == 2, "no club/4 → no bonus")
  S.jokers.hand = {}
  assert(Scoring.apply_award(S, "Pair", club_cards) == 2, "no bonus without the joker in hand")
end
print("M4 four of clubs: passed")

-- ── M4 4.5: Golden Joker auto-scores a marked hand at double value ───────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local r = FX.golden(S, { rng = love.math, playedHands = { ["Pair"] = true } })
  assert(r.ok, "golden should succeed")
  assert(S.meta.score == 4, "golden scores the marked hand twice (T1 Pair: 2×2=4)")
  S.meta.score = 0
  r = FX.golden(S, { rng = love.math, playedHands = {} })
  assert(r.ok and S.meta.score == 0, "golden with empty checklist scores nothing")
end
print("M4 golden joker: passed")

-- ── M4 4.5: Galaxy resets the checklist and applies ×1.5 ─────────────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local played = { ["Pair"] = true, ["Flush"] = true }
  local r = FX.galaxy(S, { playedHands = played })
  assert(r.ok, "galaxy should succeed")
  assert(next(played) == nil, "galaxy must reset the checklist")
  local p = Effects.get(S, "score_multiplier")
  assert(p and p.mult == 1.5 and p.no_carry == true, "galaxy multiplier payload")
  assert(Scoring.apply_award(S, "Pair") == 3,   "Pair ×1.5: ceil(2×1.5)=3")
  S.meta.score = 0
  assert(Scoring.apply_award(S, "Flush") == 12, "Flush ×1.5: 8×1.5=12")
  Effects.clear_tag(S, "no_carry")
  assert(not Effects.has(S, "score_multiplier"), "galaxy must not carry thresholds")
end
print("M4 galaxy joker: passed")

-- ── M4 4.6/4.7: Peacock and Cute Joker flags ─────────────────────────────────
-- (advanceThreshold() in main.lua clears peacock_active/peacock_extra_pending;
-- nextTurn() clears cute_active — UI-loop behaviour, not testable headless.)
do
  local S = {}
  Jokers.init(S, love.math)
  assert(FX.peacock(S, {}).ok and S.jokers.peacock_active == true,
    "peacock should arm its flag")
  assert(FX.cute_joker(S, {}).ok and S.jokers.cute_active == true,
    "cute joker should arm its flag")
end
print("M4 peacock & cute flags: passed")

-- ── M4 4.7: Architect site opens, evaluates, and scores correctly ────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  assert(FX.architect(S, {}).ok, "architect should succeed")
  assert(S.jokers.architect_active == true and #S.jokers.architect_site == 0,
    "architect should open an empty site")
  -- Simulate the main.lua [A] key: move cards from hand onto the site.
  local hand = { {suit="♠",rank="9"}, {suit="♥",rank="9"}, {suit="♦",rank="2"} }
  table.insert(S.jokers.architect_site, table.remove(hand, 2))
  table.insert(S.jokers.architect_site, table.remove(hand, 1))
  assert(#hand == 1, "cards moved to the site must leave the hand")
  local cat = Eval.exact_category(S.jokers.architect_site)
  assert(cat == "Pair", "site should evaluate as Pair, got "..tostring(cat))
  assert(Scoring.apply_award(S, cat, S.jokers.architect_site) == 2,
    "site hand should score the Rule Book award (T1 Pair = 2)")
end
print("M4 architect: passed")

-- ── M4 4.8: Save/Load round trip covers new M4 state ─────────────────────────
do
  local deck = Deck.new(1)
  GS:reset()
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local hand = deck:draw(5)
  Effects.add(S, "purge_immunity", 4, { hands = { "Pair", "Flush" } }, "purge")
  S.jokers.flush_active = true
  S.jokers.peacock_active = true
  S.jokers.architect_active = true
  S.jokers.architect_site = { {suit="♣", rank="4"}, {suit="♣", rank="9"} }

  local saved = SaveLoad.build_state(deck, hand, GS, S, {})

  local S2 = {}
  GS:reset()
  hand = SaveLoad.apply_state(saved, Deck.new(1), GS, S2, {}, Scoring, Jokers)

  assert(Effects.has(S2, "purge_immunity"), "active effect lost in round trip")
  local entry
  for _, e in ipairs(S2.active_effects) do
    if e.id == "purge_immunity" then entry = e end
  end
  assert(entry.turns_remaining == 4, "turns_remaining lost in round trip")
  assert(entry.payload.hands[1] == "Pair" and entry.payload.hands[2] == "Flush",
    "effect payload lost in round trip")
  assert(S2.jokers.flush_active == true,     "flush_active lost in round trip")
  assert(S2.jokers.peacock_active == true,   "peacock_active lost in round trip")
  assert(S2.jokers.architect_active == true, "architect_active lost in round trip")
  assert(#S2.jokers.architect_site == 2,     "architect_site lost in round trip")
  assert(S2.jokers.architect_site[1].suit == "♣" and S2.jokers.architect_site[1].rank == "4",
    "architect_site card data lost in round trip")
end
print("M4 save/load round trip: passed")

-- ── M4 4.9: registry sanity — only M5 jokers remain noop ─────────────────────
do
  for _, def in ipairs(JReg.all) do
    if def.effect == "noop" then
      assert(def.id == "invisible" or def.id == "devil" or def.id == "fourofclubs",
        "unexpected noop joker after M4: "..def.id)
    else
      assert(FX[def.effect], "registry references missing effect function: "..tostring(def.effect))
    end
  end
  assert(JReg.by_id["golden"].jtype == "triggered", "golden must be a triggered joker")
end
print("M4 registry sanity: passed")

print("\nAll tests passed.")
