-- joker_effects.lua
-- Pure functions that apply effects. Receive (state, ctx) and return a result table if needed.

local E = {}

-- Safe stub for jokers whose effects are not yet implemented.
function E.noop(state, ctx)
  return { ok=true, msg="(No effect yet.)" }
end

-- Bicycle (Common, Active) — Joker Index:
-- Draw 3 completely random cards (NOT from the main deck). They are added to the
-- hand ONLY for the turn the joker was used. Any of the 3 that are played this
-- turn become permanent deck cards; the rest are removed at end of turn.
-- Temporary cards are flagged `temporary=true` and shown with a `*` marker.
local SUITS = { "♠", "♥", "♦", "♣" }
local RANKS = { "A","2","3","4","5","6","7","8","9","10","J","Q","K" }

local function rand_index(rng, n)
  if rng and rng.random then
    if rng.random == (love and love.math and love.math.random) then
      return rng.random(1, n)
    else
      return rng:random(1, n)
    end
  end
  return math.random(1, n)
end

function E.bicycle(state, ctx)
  local rng = ctx and ctx.rng
  local cards = {}
  for _ = 1, 3 do
    local suit = SUITS[rand_index(rng, #SUITS)]
    local rank = RANKS[rand_index(rng, #RANKS)]
    table.insert(cards, { suit = suit, rank = rank, temporary = true })
  end
  state.jokers.temp_cards = state.jokers.temp_cards or {}
  for _, c in ipairs(cards) do table.insert(state.jokers.temp_cards, c) end
  if state.addTempCards then state.addTempCards(cards) end
  return { ok=true, msg="Drew 3 temporary cards." }
end
E.draw3 = E.bicycle  -- backward-compatible alias

-- Skull (Uncommon, Active) — Joker Index: halve the current attack's damage.
function E.skull(state, ctx)
  state.combat = state.combat or {}
  state.combat.halve_penalty = true
  return { ok=true, msg="Attack damage halved." }
end
E.cancel_attack = E.skull  -- backward-compatible alias

-- Food Joker (Legendary, Passive) — Post-M4 (2.9): while in hand the CARD hand
-- cap (HAND_MAX) is +3. The live value is computed by J.card_hand_max from hand
-- contents (immediate on acquire/loss); this passive refresh just records the
-- bonus in modifiers for any reader that wants it. On *use* the joker adds 3
-- permanent cards to the deck and the bonus is gone (handled in main.lua).
function E.food_passive(state, ctx)
  state.jokers.modifiers = state.jokers.modifiers or {}
  state.jokers.modifiers.card_cap_bonus = 3
  return { ok = true }
end
E.hand_cap_plus3 = E.food_passive  -- backward-compatible alias

-- Rarity ordering (least rare → most rare). Used by Bee to pick a discard.
local RARITY_ORDER = {
  common    = 1,
  uncommon  = 2,
  rare      = 3,
  epic      = 4,
  legendary = 5,
  mythic    = 6,
}

-- Lazy registry lookup so we avoid a circular require at module load time.
local function reg()
  return require("joker_registry")
end

local function hand_cap(state)
  local base = 5
  local bonus = 0
  if state.jokers and state.jokers.modifiers and state.jokers.modifiers.hand_cap_bonus then
    bonus = state.jokers.modifiers.hand_cap_bonus
  end
  return base + bonus
end

-- ── Steal (Rare) ─────────────────────────────────────────────────────────────
-- 2.7: Draw 2 jokers from the pool. Player keeps 1 (to hand); the other is
-- disabled for the current threshold (re-enters the pool at the next threshold,
-- via main.lua advanceThreshold). The overlay is fully closable; closing without
-- a pick cancels the use (handled by E.cancel_steal in main.lua).
function E.steal(state, ctx)
  local J = require("jokers")
  J.ensure_pool(state, ctx and ctx.rng, 2)
  local pool = state.jokers.pool or {}
  local revealed = {}
  -- 2.1: the two revealed jokers must be DIFFERENT ids (drawn from different
  -- positions). Take the top card, then the nearest card below it with a
  -- different id. If the pool offers only one unique id, reveal just that one.
  if #pool > 0 then
    table.insert(revealed, table.remove(pool))  -- top
    local pick_pos
    for i = #pool, 1, -1 do
      if pool[i] ~= revealed[1] then pick_pos = i break end
    end
    if pick_pos then
      table.insert(revealed, table.remove(pool, pick_pos))
    end
  end
  state.jokers.steal_pending = { ids = revealed }
  state.jokers.steal_choice_pending = true
  return { ok=true, msg="Steal: choose a joker to keep.", pending=true }
end

-- Resolve a Steal selection: keep ids[chosen_index] (to hand); the other is
-- disabled until the next threshold (queued in steal_disabled, re-added to the
-- pool on threshold advance).
function E.resolve_steal(state, chosen_index)
  local pending = state.jokers.steal_pending
  if not pending then return { ok=false, msg="Steal: nothing pending." } end
  local kept = pending.ids[chosen_index]
  if kept then
    table.insert(state.jokers.hand, kept)
  end
  state.jokers.steal_disabled = state.jokers.steal_disabled or {}
  for i, id in ipairs(pending.ids) do
    if i ~= chosen_index then table.insert(state.jokers.steal_disabled, id) end
  end
  state.jokers.steal_pending = nil
  state.jokers.steal_choice_pending = nil
  return { ok=true, msg="Steal: kept a joker." }
end

-- Cancel a Steal without choosing: both revealed jokers return to the pool.
-- main.lua additionally restores the Steal joker to hand and clears used_this_turn.
function E.cancel_steal(state)
  local pending = state.jokers.steal_pending
  if pending then
    state.jokers.pool = state.jokers.pool or {}
    for _, id in ipairs(pending.ids) do table.insert(state.jokers.pool, id) end
  end
  state.jokers.steal_pending = nil
  state.jokers.steal_choice_pending = nil
  return { ok=true, msg="Steal: cancelled." }
end

-- ── The Acrobat (Legendary) ──────────────────────────────────────────────────
-- TODO(main.lua): handle acrobat_choice_pending UI (call E.resolve_acrobat on pick).
-- Look at the top 10 cards of the deck. Take up to 4 into your hand.
function E.acrobat(state, ctx)
  local deck = ctx and ctx.deck
  local cards, indices = {}, {}
  if deck and deck.cards then
    local n = #deck.cards
    -- "Top" of the deck is the end of the array (where draws come from).
    local count = 0
    for i = n, math.max(1, n - 9), -1 do
      count = count + 1
      table.insert(cards, deck.cards[i])
      table.insert(indices, i)
      if count >= 10 then break end
    end
  end
  state.jokers.acrobat_pending = { cards = cards, indices = indices }
  state.jokers.acrobat_choice_pending = true
  return { ok=true, msg="Acrobat: choose up to 4 cards to take.", pending=true }
end

-- Resolve an Acrobat selection. chosen_indices are positions (1-based) into the
-- pending.cards/pending.indices arrays. Removes those cards from the deck and
-- adds them to ctx.hand.
function E.resolve_acrobat(state, ctx, chosen_indices)
  local pending = state.jokers.acrobat_pending
  if not pending then return { ok=false, msg="Acrobat: nothing pending." } end
  local deck = ctx and ctx.deck
  local hand = ctx and ctx.hand

  -- Resolve the deck indices we need to pull, then remove largest-first so the
  -- earlier indices stay valid while we splice.
  local deck_idx = {}
  for _, pi in ipairs(chosen_indices or {}) do
    if pending.indices[pi] then
      table.insert(deck_idx, pending.indices[pi])
    end
  end
  table.sort(deck_idx, function(a, b) return a > b end)
  for _, di in ipairs(deck_idx) do
    if deck and deck.cards then
      local card = table.remove(deck.cards, di)
      if hand and card then table.insert(hand, card) end
    end
  end

  state.jokers.acrobat_pending = nil
  state.jokers.acrobat_choice_pending = nil
  return { ok=true, msg="Acrobat: took "..#deck_idx.." card(s)." }
end

-- ── The Eye (Legendary) ──────────────────────────────────────────────────────
-- TODO(main.lua): handle eye_choice_pending UI (call E.resolve_eye on confirm).
-- Look at the next 10 jokers in the pool and rearrange them in any order.
function E.eye(state, ctx)
  -- 2.1: materialize the infinite pool so there are real upcoming jokers to show
  -- (this is the fix for the `pool` nil dereference). Show the next 10 by index.
  local J = require("jokers")
  J.ensure_pool(state, ctx and ctx.rng, 10)
  local pool = state.jokers.pool or {}
  local n = #pool
  local ids = {}
  local start_index = math.max(1, n - 9)
  -- Peek from the top of the pool (#pool down to #pool-9).
  for i = n, start_index, -1 do
    table.insert(ids, pool[i])
  end
  state.jokers.eye_pending = { ids = ids, start_index = start_index }
  state.jokers.eye_choice_pending = true
  return { ok=true, msg="Eye: rearrange the top jokers in the pool.", pending=true }
end

-- Resolve an Eye rearrange. new_order is the reordered list of ids (top-first,
-- same orientation as eye_pending.ids). Writes them back into the same slots.
function E.resolve_eye(state, new_order)
  local pending = state.jokers.eye_pending
  if not pending then return { ok=false, msg="Eye: nothing pending." } end
  local pool = state.jokers.pool or {}  -- 2.1: never dereference a nil pool
  local n = #pool
  -- ids[1] corresponds to pool[n], ids[2] to pool[n-1], ... down to start_index.
  for k, id in ipairs(new_order or {}) do
    local pool_index = n - (k - 1)
    if pool_index >= pending.start_index then
      pool[pool_index] = id
    end
  end
  state.jokers.eye_pending = nil
  state.jokers.eye_choice_pending = nil
  return { ok=true, msg="Eye: rearranged the pool." }
end

-- ── The Bee (Legendary) ──────────────────────────────────────────────────────
-- Discard the least rare joker in hand, then draw 2 new jokers from the pool.
function E.bee(state, ctx)
  local hand = state.jokers.hand
  if #hand == 0 then
    return { ok=false, msg="Bee: no jokers to discard." }
  end
  local by_id = reg().by_id
  local worst_pos, worst_rank, worst_id = nil, math.huge, nil
  for i, jid in ipairs(hand) do
    local def = by_id[jid]
    local rank = (def and RARITY_ORDER[def.rarity]) or 0
    if rank < worst_rank then
      worst_rank, worst_pos, worst_id = rank, i, jid
    end
  end
  table.remove(hand, worst_pos)  -- permanently discarded (not recycled)
  if ctx and ctx.gain_from_pool then ctx.gain_from_pool(2) end
  local name = (by_id[worst_id] and by_id[worst_id].name) or worst_id
  return { ok=true, msg="Bee: discarded "..tostring(name)..", drew 2 jokers." }
end

-- ── Fibonacci (Mythic) — reworked (2.13) ─────────────────────────────────────
-- No Auto Use (1.4): manually activated. The number of jokers it awards is the
-- count of hands that were already marked on the checklist *at the moment the
-- Fibonacci was acquired* (shown as a badge on the card). On use it awards that
-- many jokers from the pool (clamped 0..8). Awards bypass the joker hand cap
-- (overflow held but not regenerated until the hand drops to ≤ 5).
function E.fibonacci(state, ctx)
  -- Acquisition-time count comes from ctx.fib_count (set by main.lua). Fall back
  -- to the live checklist count if it was not supplied.
  local count = ctx and ctx.fib_count
  if count == nil and ctx and ctx.playedHands then
    count = 0
    for _, v in pairs(ctx.playedHands) do
      if v then count = count + 1 end
    end
  end
  count = math.max(0, math.min(8, count or 0))
  if ctx and ctx.gain_from_pool then ctx.gain_from_pool(count, { allow_overflow = true }) end
  return { ok=true, msg="Fibonacci: gained "..count.." jokers." }
end

-- ── Angel (Mythic) ───────────────────────────────────────────────────────────
-- TODO(main.lua): handle angel_choice_pending UI (call E.resolve_angel on pick).
-- Copy any joker you currently own; add a second copy to your hand.
function E.angel(state, ctx)
  local hand = state.jokers.hand
  if #hand == 0 then
    return { ok=false, msg="Angel: no jokers to copy." }
  end
  local ids = {}
  for i, jid in ipairs(hand) do ids[i] = jid end
  state.jokers.angel_pending = { ids = ids }
  state.jokers.angel_choice_pending = true
  return { ok=true, msg="Angel: choose a joker to copy.", pending=true }
end

-- Resolve an Angel copy (2.6): duplicate the chosen joker into hand. The copy is
-- added even when the hand is at cap (cap bypass, same rule as Fibonacci — the
-- overflow copy is held but will not regenerate until the hand drops to ≤ 5).
function E.resolve_angel(state, chosen_index)
  local pending = state.jokers.angel_pending
  if not pending then return { ok=false, msg="Angel: nothing pending." } end
  local id = pending.ids[chosen_index]
  if id then
    table.insert(state.jokers.hand, id)
  end
  state.jokers.angel_pending = nil
  state.jokers.angel_choice_pending = nil
  return { ok=true, msg="Angel: copied a joker." }
end

-- ── Anti-Joker (Mythic) ──────────────────────────────────────────────────────
-- Disable attacks for 3 turns: no penalty, no resolution. Shown active in UI.
function E.anti_joker(state, ctx)
  local Effects = require("effects")
  Effects.add(state, "attack_shield", 3, { no_carry = true }, "anti")
  return { ok=true, msg="Attacks disabled for 3 turns." }
end

-- ── Purge (Epic) ─────────────────────────────────────────────────────────────
-- Player picks 2 hand types; for 5 turns those hands neither award nor deduct
-- points when they are the attack target. Selection happens in an overlay in
-- main.lua; resolve_purge fires once both picks are stored in purge_selected.
function E.purge(state, ctx)
  state.jokers.purge_pending = true
  state.jokers.purge_selected = {}
  return { ok=true, msg="Purge: choose 2 hand types to protect.", pending=true }
end

function E.resolve_purge(state)
  local Effects = require("effects")
  local hands = state.jokers.purge_selected or {}
  Effects.add(state, "purge_immunity", 5, { hands = hands, no_carry = false }, "purge")
  state.jokers.purge_pending = nil
  state.jokers.purge_selected = nil
  local label = table.concat(hands, " & ")
  return { ok=true, msg="Purge: "..label.." protected for 5 turns." }
end

-- ── Cybernetic (Legendary) ───────────────────────────────────────────────────
-- Randomly hacks 2 hand types for 3 turns. Each turn each hacked hand gets one
-- of 4 states: Normal 35% ("n"), Double 20% ("d"), Protected 30% ("p"),
-- Lose 15% ("l"). Cannot carry across thresholds.
-- ── Cybernetic (Legendary) — reworked (2.10) ─────────────────────────────────
-- On use, builds a 3-turn schedule. Each turn picks 2 DIFFERENT hand types and
-- assigns each one of three conditions — Double "d", Protected "p", Lose "l" —
-- with probabilities 40% / 40% / 20% (no "Normal"). Hands re-roll every turn and
-- do not carry between thresholds (no_carry). Effects:
--   d → that hand scores double if played this turn (scoring.lua)
--   p → if that hand is the attack target, it auto-blocks (attacks.lua)
--   l → if that hand is played, it loses its T1 base penalty in points (scoring.lua)
function E.cybernetic(state, ctx)
  local Effects = require("effects")
  local Rules = require("rules")
  local rng = ctx and ctx.rng
  local function roll_cond()
    local r = rand_index(rng, 100)
    if r <= 40 then return "d"
    elseif r <= 80 then return "p"
    else return "l" end
  end
  local function pick_two()
    local i1 = rand_index(rng, #Rules.CATEGORIES)
    local i2 = rand_index(rng, #Rules.CATEGORIES - 1)
    if i2 >= i1 then i2 = i2 + 1 end  -- two distinct hands
    return { Rules.CATEGORIES[i1], Rules.CATEGORIES[i2] }
  end
  local schedule = {}
  for turn = 1, 3 do
    schedule[turn] = { hands = pick_two(), cond = { roll_cond(), roll_cond() } }
  end
  -- turn_index starts at 1 (the use turn is turn 1); effects.tick advances it.
  Effects.add(state, "cybernetic", 3,
    { schedule = schedule, turn_index = 1, no_carry = true }, "cybernetic")
  local h = schedule[1].hands
  return { ok=true, msg="Cybernetic: hacked "..h[1].." & "..h[2].." (re-rolls each turn, 3 turns)." }
end

-- ── The Flush (Legendary) ────────────────────────────────────────────────────
-- The next Flush played scores double, but only if the current attacking hand
-- is also a Flush. Consumed (flag cleared) by scoring.lua when a Flush is played.
-- The Flush (2.9, reworked): on use it immediately scores a Flush's award at the
-- current threshold — no cards need to be played. Doubled if the current attack
-- is also Flush. Returns auto_score so main.lua can run the streak (1.1) and
-- threshold-win (1.2) checks. The joker is consumed by J.use.
function E.flush_joker(state, ctx)
  local Scoring = require("scoring")
  state.meta = state.meta or {}
  local t = state.meta.threshold or 1
  local pts = Scoring.get_award(t, "Flush")
  local doubled = false
  if state.combat and state.combat.current_attack == "Flush" then
    pts = pts * 2
    doubled = true
  end
  state.meta.score = (state.meta.score or 0) + pts
  state.jokers.flush_active = nil  -- legacy flag, no longer used
  return {
    ok = true,
    msg = "The Flush: +"..pts.." pts"..(doubled and " (×2 vs Flush attack)" or "")..".",
    auto_score = "Flush",
    points = pts,
  }
end

-- ── The Trader (Legendary) ───────────────────────────────────────────────────
-- Lose a random completed hand (unmark it from the checklist); the next played
-- hand scores double points.
function E.trader(state, ctx)
  local played = ctx and ctx.playedHands
  local marked = {}
  if played then
    for k, v in pairs(played) do
      if v then table.insert(marked, k) end
    end
  end
  if #marked == 0 then return { ok=false, msg="No completed hands to lose." } end
  table.sort(marked)  -- deterministic iteration order before the random pick
  local chosen = marked[rand_index(ctx and ctx.rng, #marked)]
  played[chosen] = nil
  state.jokers.trader_double = true
  return { ok=true, msg="Trader: lost "..chosen..", next hand scores double." }
end

-- ── Golden Joker (Mythic, auto-use on acquire) ───────────────────────────────
-- Auto-scores a random already-marked hand at double its award value the moment
-- it enters the joker hand (wired in jokers.lua J.gain_joker).
-- Golden Joker (2.8, reworked): auto-scores a random marked hand at its NORMAL
-- award (was double). It also flags that hand so that if the player MANUALLY
-- plays the same hand type on the same turn, that copy scores double (handled in
-- main.lua). Returns auto_score so main.lua can run the streak (2.8.2) and
-- threshold-win (2.8.1) checks.
function E.golden(state, ctx)
  local Scoring = require("scoring")
  local played = ctx and ctx.playedHands
  local marked = {}
  if played then
    for k, v in pairs(played) do
      if v then table.insert(marked, k) end
    end
  end
  if #marked == 0 then return { ok=true, msg="Golden Joker: no completed hands yet." } end
  table.sort(marked)
  local chosen = marked[rand_index(ctx and ctx.rng, #marked)]
  Scoring.apply_award(state, chosen)  -- 2.8.3: NORMAL points (single award)
  -- Mark this hand type for a same-turn manual-play double, and flag the
  -- auto-score so main.lua can run the streak (2.8.2) + win (2.8.1) checks even
  -- when Golden fires on acquisition (inside gain_joker, not via the J key).
  state.combat = state.combat or {}
  state.combat.golden_double = chosen
  state.combat.golden_streak_pending = chosen
  return { ok=true, msg="Golden Joker: auto-scored "..chosen..". Replay it this turn for ×2.",
           auto_score = chosen }
end

-- ── Galaxy Joker (Mythic) ────────────────────────────────────────────────────
-- Resets the checklist; every hand scores ×1.5 for the rest of this threshold.
-- 999 turns ≈ rest of threshold; clear_tag on threshold advance removes it.
function E.galaxy(state, ctx)
  local Effects = require("effects")
  if ctx and ctx.playedHands then
    local keys = {}
    for k in pairs(ctx.playedHands) do table.insert(keys, k) end
    for _, k in ipairs(keys) do ctx.playedHands[k] = nil end
  end
  -- 2.6: Galaxy also resets the score to 0.
  state.meta = state.meta or {}
  state.meta.score = 0
  Effects.add(state, "score_multiplier", 999, { mult = 1.5, no_carry = true }, "galaxy")
  return { ok=true, msg="Galaxy: checklist & score reset. All hands score ×1.5 this threshold." }
end

-- ── Peacock Joker (Mythic) ───────────────────────────────────────────────────
-- Grants an extra turn every 5 turns for the rest of the threshold. The turn
-- scheduling lives in main.lua (nextTurn/love.update); cleared on threshold advance.
function E.peacock(state, ctx)
  state.jokers.peacock_active = true
  return { ok=true, msg="Peacock: extra turn every 5 turns this threshold." }
end

-- ── Four of Clubs (Mythic, triggered) — activate-on-use (2.5) ────────────────
-- The "+6 per hand containing a Club or a 4 (doubling per threshold)" bonus is
-- INERT until the player explicitly uses the joker. On use it sets an active flag
-- that scoring.lua reads; before use it does nothing.
function E.fourofclubs(state, ctx)
  state.jokers.fourofclubs_active = true
  return { ok=true, msg="Four of Clubs: activated — Club/4 hands now score extra." }
end

-- ── Cute Joker (Epic) — reworked (2.4) ───────────────────────────────────────
-- Sets a flag that lets the play handler in main.lua accept exactly 6 cards when
-- they form two valid, separate three-of-a-kinds (a 6-of-a-kind is rejected).
-- The play flow consumes the flag; nextTurn clears it as a safety net.
function E.cute_joker(state, ctx)
  state.jokers.cute_active = true
  return { ok=true, msg="Cute Joker: play 6 cards as two three-of-a-kinds this turn." }
end

-- ── The Architect (Legendary) ────────────────────────────────────────────────
-- Opens a persistent building site. The player moves cards onto it across
-- turns ([A] key) and plays it as a bonus hand ([P] key) — both in main.lua.
-- Site and flag are cleared on threshold advance.
function E.architect(state, ctx)
  state.jokers.architect_active = true
  state.jokers.architect_site = {}
  return { ok=true, msg="Architect: building site opened. Add cards from hand each turn." }
end

return E
