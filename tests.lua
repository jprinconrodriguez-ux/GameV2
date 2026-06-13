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

-- ── 3.7: Rarity-weighted draw distribution (10,000 sample, ±3% tolerance) ─────
do
  local REG = require("joker_registry")
  local S = {}
  Jokers.init(S, love.math)
  local N = 10000
  local counts = {}
  for _ = 1, N do
    S.jokers.hand = {}  -- keep clear of the hand cap so every draw lands
    Jokers.gain_from_pool(S, 1, love.math)
    assert(#S.jokers.hand == 1, "gain_from_pool should add exactly 1 joker")
    local def = REG.by_id[S.jokers.hand[1]]
    assert(def, "Unknown joker id drawn: "..tostring(S.jokers.hand[1]))
    counts[def.rarity] = (counts[def.rarity] or 0) + 1
  end
  -- Weights sum to 100, so each weight reads directly as its expected percentage.
  for rarity, weight in pairs(REG.rarity_weights) do
    local share = ((counts[rarity] or 0) / N) * 100
    assert(math.abs(share - weight) <= 3,
      string.format("Rarity %s share %.1f%% deviates more than 3pp from expected %d%%",
        rarity, share, weight))
  end
end
print("3.7 Rarity-weighted draw distribution: passed")

-- ── 1.2/3.4/3.7: hidden/inactive/deferred jokers are never drawn ─────────────
do
  local REG = require("joker_registry")
  local S = {}
  Jokers.init(S, love.math)
  for _ = 1, 5000 do
    S.jokers.hand = {}
    local jid = Jokers.gain_joker(S, love.math)
    assert(jid ~= "devil" and jid ~= "invisible",
      "hidden/deferred joker must never be drawn, got "..tostring(jid))
  end
  -- ids_by_rarity must also exclude them.
  for _, ids in pairs(REG.ids_by_rarity()) do
    for _, id in ipairs(ids) do
      assert(id ~= "devil" and id ~= "invisible", "excluded joker leaked into ids_by_rarity: "..id)
    end
  end
end
print("Hidden joker exclusion test: passed")

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

-- ── 2.9: Food Joker passive raises the CARD hand cap (HAND_MAX) by 3 ──────────
do
  local S = {}
  Jokers.init(S, love.math)
  -- Without Food in hand the effective card cap equals the base (14).
  assert(Jokers.card_hand_max(S, 14) == 14,
    "no Food → card cap should equal base 14, got "..tostring(Jokers.card_hand_max(S, 14)))
  S.jokers.hand = { "food" }   -- Food Joker passive in hand
  -- Immediate on acquire (no start_turn needed): +3 to the card cap.
  assert(Jokers.card_hand_max(S, 14) == 17,
    "Food in hand → card cap 14+3=17, got "..tostring(Jokers.card_hand_max(S, 14)))
  Jokers.start_turn(S)         -- refreshes passives → records the bonus too
  assert(S.jokers.modifiers.card_cap_bonus == 3,
    "Food Joker should record +3 card cap bonus, got "..tostring(S.jokers.modifiers.card_cap_bonus))
  -- Reverts immediately when Food leaves the hand.
  S.jokers.hand = {}
  assert(Jokers.card_hand_max(S, 14) == 14, "card cap should revert to base when Food is gone")
end
print("Food Joker card cap test: passed")

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
  -- 2.6: at the cap, the copy is STILL added (cap bypass, same rule as Fibonacci).
  S.jokers.hand = { "bicycle", "bicycle", "bicycle", "bicycle", "bicycle" }
  FX.angel(S, {})
  FX.resolve_angel(S, 1)
  assert(#S.jokers.hand == 6, "angel must add the copy even past the cap (overflow bypass)")
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

-- ── 2.10: Cybernetic rework (schedule of 3 turns; D/P/L conditions) ──────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  -- Hand-built schedule: turn 1 Pair=d, turn 2 Pair=p, turn 3 Pair=l.
  Effects.add(S, "cybernetic", 3, {
    schedule = {
      { hands = { "Pair", "Flush" }, cond = { "d", "p" } },
      { hands = { "Pair", "Flush" }, cond = { "p", "d" } },
      { hands = { "Pair", "Flush" }, cond = { "l", "d" } },
    },
    turn_index = 1, no_carry = true,
  }, "cybernetic")
  -- turn 1: Pair "d" doubles the award (Pair T1 = 2 → 4)
  assert(Scoring.apply_award(S, "Pair") == 4, "Double should double the award")
  S.meta.score = 0
  -- turn 2: Pair "p" protects against the attack
  Effects.get(S, "cybernetic").turn_index = 2
  S.combat = { current_attack = "Pair" }
  local res = Attacks.resolve(S, Scoring)
  assert(res.protected, "Protected should block the attack")
  assert(S.meta.score == 0, "protected attack must not change score")
  -- turn 3: Pair "l" loses its T1 base penalty (4) → award 2 - 4 = -2
  Effects.get(S, "cybernetic").turn_index = 3
  assert(Scoring.apply_award(S, "Pair") == 2 - 4, "Lose should subtract the T1 penalty (4)")
  Effects.clear_tag(S, "no_carry")
  assert(not Effects.has(S, "cybernetic"), "cybernetic must not carry thresholds")

  -- Generated payload: 3-turn schedule, 2 different hands/turn, conditions ∈ {d,p,l}.
  for _ = 1, 50 do
    local S2 = {}
    Jokers.init(S2, love.math)
    FX.cybernetic(S2, { rng = love.math })
    local pay = Effects.get(S2, "cybernetic")
    assert(pay.no_carry == true and pay.turn_index == 1, "cybernetic payload defaults")
    assert(#pay.schedule == 3, "cybernetic schedule must cover 3 turns")
    for _, entry in ipairs(pay.schedule) do
      assert(#entry.hands == 2 and entry.hands[1] ~= entry.hands[2],
        "each turn must hack two DIFFERENT hands")
      for _, c in ipairs(entry.cond) do
        assert(c == "d" or c == "p" or c == "l", "condition must be one of d/p/l (no Normal), got "..tostring(c))
      end
    end
  end
end
print("2.10 cybernetic rework: passed")

-- ── 2.9: The Flush rework — instant score on use (doubled vs Flush attack) ───
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  -- No attack / non-flush attack → flush award at threshold (T1 = 8), no doubling.
  S.combat = { current_attack = "Pair" }
  local r = FX.flush_joker(S, {})
  assert(r.ok and r.auto_score == "Flush", "flush joker should report an auto_score")
  assert(S.meta.score == 8, "The Flush should instantly score the T1 flush award (8)")
  assert(r.points == 8, "result points should be 8")
  -- Attack is Flush → doubled.
  S.meta.score = 0
  S.combat = { current_attack = "Flush" }
  FX.flush_joker(S, {})
  assert(S.meta.score == 16, "vs a Flush attack the score should double (8→16)")
  -- Threshold scaling: T2 = 16.
  S.meta.score = 0
  S.meta.threshold = 2
  S.combat = { current_attack = "Pair" }
  FX.flush_joker(S, {})
  assert(S.meta.score == 16, "T2 flush award should be 16")
end
print("2.9 the flush rework: passed")

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

-- ── 2.5: Four of Clubs bonus only after the joker is USED ────────────────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  S.jokers.hand = { "fourofclubs" }
  local club_cards = { {suit="♣", rank="9"}, {suit="♥", rank="9"} }
  local four_cards = { {suit="♥", rank="4"}, {suit="♦", rank="4"} }
  local plain      = { {suit="♥", rank="9"}, {suit="♦", rank="9"} }
  -- Inert before use: no bonus even though the joker is in hand.
  assert(Scoring.apply_award(S, "Pair", club_cards) == 2, "no bonus before the joker is used")
  -- Activate via use.
  FX.fourofclubs(S, {})
  assert(S.jokers.fourofclubs_active == true, "using Four of Clubs should activate it")
  S.meta.score = 0
  assert(Scoring.apply_award(S, "Pair", club_cards) == 2 + 6,  "T1 club bonus = +6 after use")
  S.meta.threshold = 2; S.meta.score = 0
  assert(Scoring.apply_award(S, "Pair", four_cards) == 4 + 12, "T2 four-rank bonus = +12")
  S.meta.threshold = 3; S.meta.score = 0
  assert(Scoring.apply_award(S, "Pair", four_cards) == 8 + 24, "T3 bonus = +24")
  S.meta.threshold = 1; S.meta.score = 0
  assert(Scoring.apply_award(S, "Pair", plain) == 2, "no club/4 → no bonus")
end
print("2.5 four of clubs activate-on-use: passed")

-- ── 2.8: Golden auto-score = NORMAL; same-turn manual copy = DOUBLE ───────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local r = FX.golden(S, { rng = love.math, playedHands = { ["Pair"] = true } })
  assert(r.ok, "golden should succeed")
  -- 2.8.3: auto-score is NORMAL points (T1 Pair = 2), not double.
  assert(S.meta.score == 2, "golden auto-score should be normal points (2), got "..S.meta.score)
  assert(r.auto_score == "Pair", "golden should report its auto-scored hand")
  assert(S.combat.golden_double == "Pair", "golden should flag the hand for a same-turn double")
  -- A subsequent manual Pair would score double (the doubling itself lives in main.lua,
  -- but the flag is the contract). Empty checklist → nothing scored.
  S.meta.score = 0; S.combat.golden_double = nil
  r = FX.golden(S, { rng = love.math, playedHands = {} })
  assert(r.ok and S.meta.score == 0, "golden with empty checklist scores nothing")
end
print("2.8 golden joker order: passed")

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

-- ═══════════════════════ POST-M4 POLISH TESTS ═══════════════════════

-- ── 3.6: is_threshold_complete returns true when score == target ─────────────
do
  local S = {}
  Scoring.init(S)
  S.meta.threshold = 1
  S.meta.score = 80   -- exactly the T1 target
  assert(Scoring.is_threshold_complete(S) == true, "score == target should complete (T1=80)")
  S.meta.score = 79
  assert(Scoring.is_threshold_complete(S) == false, "score below target must not complete")
  S.meta.threshold = 3
  S.meta.score = 300  -- exactly the T3 target
  assert(Scoring.is_threshold_complete(S) == true, "score == target should complete (T3=300)")
end
print("3.6 equal-to-target completion: passed")

-- ── 2.13: Fibonacci awards jokers equal to marked hands at acquisition time ───
do
  local S = {}
  Jokers.init(S, love.math)
  -- Acquisition-time count is supplied via ctx.fib_count and overrides the live
  -- checklist; awards bypass the joker cap (overflow allowed).
  local gained = 0
  local ctx = {
    rng = love.math,
    fib_count = 5,
    playedHands = { ["Pair"] = true },  -- live checklist (should be ignored)
    gain_from_pool = function(n) gained = gained + n end,
  }
  local r = FX.fibonacci(S, ctx)
  assert(r.ok and gained == 5, "fibonacci should award the acquisition-time count (5), got "..gained)
  -- Clamp to a maximum of 8.
  gained = 0; ctx.fib_count = 12
  FX.fibonacci(S, ctx)
  assert(gained == 8, "fibonacci award must clamp to max 8, got "..gained)
  -- Recording at acquisition: gaining a Fibonacci stores the current marked count.
  local S2 = {}
  Jokers.init(S2, love.math)
  S2.jokers.pool = { "fibonacci" }  -- force the next pool draw to be Fibonacci
  Jokers.gain_joker(S2, love.math, { playedHands = { ["Pair"]=true, ["Flush"]=true } })
  assert(S2.jokers.fib_counts and S2.jokers.fib_counts[1] == 2,
    "acquiring Fibonacci should record the marked-hand count (2)")
end
print("2.13 fibonacci acquisition count: passed")

-- ── 2.4: Cute Joker 6-card play = two three-of-a-kinds; 6-of-a-kind rejected ──
do
  local two_trips = {
    {suit="♠",rank="9"},{suit="♥",rank="9"},{suit="♦",rank="9"},
    {suit="♠",rank="4"},{suit="♥",rank="4"},{suit="♦",rank="4"},
  }
  local six_kind = {
    {suit="♠",rank="9"},{suit="♥",rank="9"},{suit="♦",rank="9"},
    {suit="♣",rank="9"},{suit="♠",rank="9"},{suit="♥",rank="9"},
  }
  local trip_plus_pair = {
    {suit="♠",rank="9"},{suit="♥",rank="9"},{suit="♦",rank="9"},
    {suit="♠",rank="4"},{suit="♥",rank="4"},{suit="♦",rank="2"},
  }
  assert(Eval.is_two_trips(two_trips) == true, "two separate trips must be accepted")
  assert(Eval.is_two_trips(six_kind) == false, "six-of-a-kind must be rejected")
  assert(Eval.is_two_trips(trip_plus_pair) == false, "trips + pair is not two trips")
  -- exact_category still rejects any 6-card hand (the flag gate lives in main.lua).
  assert(Eval.exact_category(two_trips) == nil, "exact_category must reject 6-card hands")
end
print("2.4 cute two-trips evaluator: passed")

-- ── 2.11: Architect best_category picks the highest valid hand among ≤5 cards ─
do
  local flush5 = {
    {suit="♠",rank="2"},{suit="♠",rank="9"},{suit="♠",rank="4"},
    {suit="♠",rank="K"},{suit="♠",rank="7"},
  }
  assert(Eval.best_category(flush5) == "Flush", "five same-suit cards → Flush")
  local pair_in_5 = {
    {suit="♠",rank="9"},{suit="♥",rank="9"},{suit="♦",rank="2"},
    {suit="♣",rank="5"},{suit="♠",rank="K"},
  }
  assert(Eval.best_category(pair_in_5) == "Pair", "a contained pair → Pair (best)")
  local full_house = {
    {suit="♠",rank="9"},{suit="♥",rank="9"},{suit="♦",rank="9"},
    {suit="♣",rank="5"},{suit="♠",rank="5"},
  }
  assert(Eval.best_category(full_house) == "Full House", "trips+pair → Full House")
end
print("2.11 architect best_category: passed")

-- ── 2.7: Steal disables the non-chosen joker (re-enters pool next threshold) ──
do
  local S = {}
  Jokers.init(S, love.math)
  S.jokers.pool = { "bicycle", "skull", "steal" }
  FX.steal(S, { rng = love.math })
  local ids = S.jokers.steal_pending.ids
  FX.resolve_steal(S, 1)  -- keep ids[1]; ids[2] becomes disabled
  assert(S.jokers.steal_disabled and #S.jokers.steal_disabled == 1,
    "non-chosen joker should be queued as disabled")
  assert(S.jokers.steal_disabled[1] == ids[2], "the disabled joker must be the non-chosen one")
  -- Cancel path returns both revealed jokers to the pool.
  local S2 = {}
  Jokers.init(S2, love.math)
  S2.jokers.pool = { "bicycle", "skull", "steal" }
  FX.steal(S2, { rng = love.math })
  FX.cancel_steal(S2)
  assert(#S2.jokers.pool == 3, "cancel_steal should return both jokers to the pool")
  assert(not S2.jokers.steal_choice_pending, "cancel_steal should clear the pending flag")
end
print("2.7 steal disable/cancel: passed")

-- ── 4.1 / 5.1: T4+ attack probability table (T4 and T5 share it; sums to 100) ─
do
  local expected = {
    ["High Card"]=11, ["Pair"]=12, ["Two Pair"]=12, ["Three of a Kind"]=13,
    ["Flush"]=14, ["Straight"]=13, ["Full House"]=14, ["Four of a Kind"]=11,
  }
  for _, t in ipairs({ 4, 5, 9 }) do
    local probs = Attacks.probs_for_threshold(t)
    local sum = 0
    for hand, v in pairs(expected) do
      assert(probs[hand] == v, "T4+ mismatch ("..t..") on "..hand..": expected "..v.." got "..tostring(probs[hand]))
    end
    for _, w in pairs(probs) do sum = sum + w end
    assert(sum == 100, "T4+ probabilities must sum to 100, got "..sum)
  end
end
print("4.1 T4+ attack probabilities: passed")

-- ── 4.2: T4+ rarity weights differ from the base table and sum to 100 ────────
do
  local REG = require("joker_registry")
  local base = REG.weights_for_threshold(1)
  local t4   = REG.weights_for_threshold(4)
  assert(base.common == 29 and t4.common == 33, "weights_for_threshold must switch tables at T4")
  local s = 0
  for _, w in pairs(t4) do s = s + w end
  assert(s == 100, "T4+ rarity weights must sum to 100, got "..s)
end
print("4.2 T4+ rarity weights: passed")

-- ── 5.6: Steal always reveals two DIFFERENT joker ids ────────────────────────
do
  local REG = require("joker_registry")
  for _ = 1, 200 do
    local S = {}
    Jokers.init(S, love.math)
    Jokers.ensure_pool(S, love.math, 12)
    FX.steal(S, { rng = love.math })
    local ids = S.jokers.steal_pending.ids
    assert(#ids == 2, "steal should reveal 2 jokers from a varied pool")
    assert(ids[1] ~= ids[2], "the two revealed jokers must have different ids ("..ids[1]..")")
  end
end
print("5.6 steal distinct ids: passed")

-- ── 2.6: Galaxy resets the score to 0 in addition to the checklist ───────────
do
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  S.meta.score = 137
  local played = { ["Pair"] = true, ["Flush"] = true }
  FX.galaxy(S, { playedHands = played })
  assert(S.meta.score == 0, "Galaxy must reset the score to 0, got "..S.meta.score)
  assert(next(played) == nil, "Galaxy must also reset the checklist")
end
print("2.6 galaxy score reset: passed")

-- ── v4.2 save/load: new joker state round-trips ──────────────────────────────
do
  local deck = Deck.new(1)
  GS:reset()
  local S = {}
  Scoring.init(S)
  Jokers.init(S, love.math)
  local hand = deck:draw(5)
  S.meta.streak = 4
  S.jokers.fourofclubs_active = true
  S.jokers.food_acquired = true
  S.jokers.fib_counts = { 2, 5 }
  S.jokers.steal_disabled = { "bicycle" }
  S.jokers.pool = { "skull", "bee" }

  local saved = SaveLoad.build_state(deck, hand, GS, S, {})
  local S2 = {}
  GS:reset()
  SaveLoad.apply_state(saved, Deck.new(1), GS, S2, {}, Scoring, Jokers)

  assert(S2.meta.streak == 4, "streak lost in round trip")
  assert(S2.jokers.fourofclubs_active == true, "fourofclubs_active lost in round trip")
  assert(S2.jokers.food_acquired == true, "food_acquired lost in round trip")
  assert(S2.jokers.fib_counts[1] == 2 and S2.jokers.fib_counts[2] == 5, "fib_counts lost")
  assert(S2.jokers.steal_disabled[1] == "bicycle", "steal_disabled lost")
  assert(S2.jokers.pool[1] == "skull" and S2.jokers.pool[2] == "bee", "pool lost")
end
print("v4.2 save/load round trip: passed")

print("\nAll tests passed.")
