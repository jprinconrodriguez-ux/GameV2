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

-- Food Joker (Legendary, Passive) — Joker Index: hand cap +3 while in hand.
-- Applied each turn by J.start_turn (modifiers are recomputed from scratch).
function E.hand_cap_plus3(state, ctx)
  state.jokers.modifiers = state.jokers.modifiers or {}
  state.jokers.modifiers.hand_cap_bonus = (state.jokers.modifiers.hand_cap_bonus or 0) + 3
  return { ok = true }
end
E.food_passive = E.hand_cap_plus3  -- backward-compatible alias

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
-- TODO(main.lua): handle steal_choice_pending UI (call E.resolve_steal on pick).
-- Reveal 2 jokers from the pool. Player keeps 1; the other is permanently removed.
function E.steal(state, ctx)
  local pool = state.jokers.pool or {}
  local revealed = {}
  for _=1,2 do
    if #pool == 0 then break end
    table.insert(revealed, table.remove(pool))
  end
  state.jokers.steal_pending = { ids = revealed }
  state.jokers.steal_choice_pending = true
  return { ok=true, msg="Steal: choose a joker to keep.", pending=true }
end

-- Resolve a Steal selection: keep ids[chosen_index] (to hand), discard the other.
function E.resolve_steal(state, chosen_index)
  local pending = state.jokers.steal_pending
  if not pending then return { ok=false, msg="Steal: nothing pending." } end
  local kept = pending.ids[chosen_index]
  if kept then
    table.insert(state.jokers.hand, kept)
  end
  -- The non-chosen ids are discarded permanently.
  state.jokers.steal_pending = nil
  state.jokers.steal_choice_pending = nil
  return { ok=true, msg="Steal: kept a joker." }
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
  local pool = state.jokers.pool
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

-- ── Fibonacci (Mythic) ───────────────────────────────────────────────────────
-- Gain 1 joker from the pool for each category already marked on the checklist.
function E.fibonacci(state, ctx)
  local count = 0
  if ctx and ctx.playedHands then
    for _, v in pairs(ctx.playedHands) do
      if v then count = count + 1 end
    end
  end
  if ctx and ctx.gain_from_pool then ctx.gain_from_pool(count) end
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

-- Resolve an Angel copy: duplicate the chosen joker into hand (respecting the
-- hand cap — overflow copies are dropped).
function E.resolve_angel(state, chosen_index)
  local pending = state.jokers.angel_pending
  if not pending then return { ok=false, msg="Angel: nothing pending." } end
  local id = pending.ids[chosen_index]
  if id and #state.jokers.hand < hand_cap(state) then
    table.insert(state.jokers.hand, id)
  end
  state.jokers.angel_pending = nil
  state.jokers.angel_choice_pending = nil
  return { ok=true, msg="Angel: copied a joker." }
end

return E
