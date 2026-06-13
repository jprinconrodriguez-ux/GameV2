-- jokers.lua
local REG = require("joker_registry")
local FX  = require("joker_effects")

local J = {}

-- `love.math` exposes `random` as a plain function, while `RandomGenerator`
-- objects expect a method call. Detect which form we received so both work.
local function rand_int(rng, lo, hi)
  if rng and rng.random then
    if rng.random == love.math.random then
      return rng.random(lo, hi)
    else
      return rng:random(lo, hi)
    end
  end
  return love.math.random(lo, hi)
end

-- Pick a rarity by weighted random using REG.rarity_weights (Post-M4 canonical
-- joker rarity spawn chances). Iterate in a fixed order so the weighting is
-- deterministic with respect to the RNG (pairs() order is unspecified in Lua).
-- TODO: FUTURE — apply T4+ prob tables and rarity spawn changes (harder
-- distribution at T4+: Common 33 / Uncommon 27 / Rare 20 / Epic 10 / Legendary 6
-- / Mythic 4). Not part of this patch.
local RARITY_ORDER = { "common", "uncommon", "rare", "epic", "legendary", "mythic" }

local function pick_rarity(rng)
  local total = 0
  for _, r in ipairs(RARITY_ORDER) do total = total + (REG.rarity_weights[r] or 0) end
  local r = rand_int(rng, 1, total)
  local acc = 0
  for _, rarity in ipairs(RARITY_ORDER) do
    acc = acc + (REG.rarity_weights[rarity] or 0)
    if r <= acc then return rarity end
  end
  return RARITY_ORDER[1]  -- fallback (shouldn't happen)
end

-- Draw a single joker ID at random from the infinite probability pool: pick a
-- rarity by weighted random (REG.rarity_weights), then a uniformly random joker
-- of that rarity from the registry. Hidden/inactive/deferred jokers (Devil,
-- Invisible) are already excluded by REG.ids_by_rarity(). Returns nil only if no
-- drawable joker of the chosen rarity exists. Duplicates are allowed.
function J.draw_random_joker(rng)
  local buckets = REG.ids_by_rarity()
  -- Try the weighted rarity first; if it has no drawable jokers, fall back to
  -- any rarity that does (keeps the infinite pool from ever stalling).
  for _ = 1, 8 do
    local rarity = pick_rarity(rng)
    local ids = buckets[rarity]
    if ids and #ids > 0 then
      return ids[rand_int(rng, 1, #ids)]
    end
  end
  for _, rarity in ipairs(RARITY_ORDER) do
    local ids = buckets[rarity]
    if ids and #ids > 0 then return ids[rand_int(rng, 1, #ids)] end
  end
  return nil
end

-- ── Materialized pool buffer (infinite, lazily filled) ───────────────────────
-- The pool is conceptually infinite, but The Eye / Steal need a concrete,
-- inspectable list of upcoming jokers. We keep `state.jokers.pool` as a buffer
-- of pre-drawn ids. Draws consume from the END of the array (the "top"); top-ups
-- append weighted-random ids to the end. The Eye reorders the top 10.
local POOL_TARGET = 12  -- keep at least this many ids ready for Eye/Steal peeks

function J.ensure_pool(state, rng, n)
  state.jokers = state.jokers or {}
  state.jokers.pool = state.jokers.pool or {}
  n = n or POOL_TARGET
  local guard = 0
  while #state.jokers.pool < n and guard < 1000 do
    local jid = J.draw_random_joker(rng)
    if not jid then break end
    table.insert(state.jokers.pool, jid)
    guard = guard + 1
  end
  return state.jokers.pool
end

-- Draw one joker id from the pool buffer (refilling first). Returns nil only if
-- the registry has no drawable jokers at all.
function J.draw_from_pool(state, rng)
  J.ensure_pool(state, rng, 1)
  local pool = state.jokers.pool
  if #pool == 0 then return nil end
  return table.remove(pool)
end

-- Returns the joker hand cap (base 5). Per the Post-M4 spec the Food Joker now
-- raises the CARD hand cap (HAND_MAX in main.lua), not this joker hand cap, so
-- the joker cap stays at 5. Fibonacci/Angel award overflow may temporarily
-- exceed it (handled at the call sites).
local function current_hand_cap(state)
  local base = 5
  local bonus = 0
  if state.jokers and state.jokers.modifiers and state.jokers.modifiers.joker_cap_bonus then
    bonus = state.jokers.modifiers.joker_cap_bonus
  end
  return base + bonus
end
J.current_hand_cap = current_hand_cap

-- Food Joker (2.9): while it is in hand the CARD hand cap (HAND_MAX) is +3.
-- Computed live from hand contents so it applies the instant Food is acquired and
-- reverts the instant it is used/lost. `base` is main.lua's HAND_MAX (14).
function J.food_in_hand(state)
  if not (state.jokers and state.jokers.hand) then return false end
  for _, jid in ipairs(state.jokers.hand) do
    if jid == "food" then return true end
  end
  return false
end

function J.card_hand_max(state, base)
  base = base or 14
  if J.food_in_hand(state) then return base + 3 end
  return base
end

function J.init(state, rng)
  state.jokers = state.jokers or {}
  state.jokers.hand        = state.jokers.hand        or {}
  state.jokers.used_this_turn = false
  state.jokers.modifiers   = state.jokers.modifiers   or {}
end

-- Call at turn start
function J.start_turn(state)
  state.jokers.used_this_turn = false
  -- Recompute passives each turn (e.g., Food hand-cap bonus if it's in hand)
  state.jokers.modifiers = {}
  for _,jid in ipairs(state.jokers.hand) do
    local def = REG.by_id[jid]
    if def and def.jtype == "passive" and def.effect and FX[def.effect] then
      FX[def.effect](state, {source="passive_refresh"})
    end
  end
end

function J.can_use(state)
  return not state.jokers.used_this_turn and #state.jokers.hand > 0
end

-- Use a joker in hand by index; triggers its effect; sets limiter.
function J.use(state, hand_index, ctx)
  assert(hand_index and state.jokers.hand[hand_index], "Invalid joker index")
  if state.jokers.used_this_turn then return { ok=false, err="Only one joker per turn." } end

  local jid = table.remove(state.jokers.hand, hand_index)
  local def = REG.by_id[jid]
  local result = { ok=true }

  if def and def.effect and FX[def.effect] then
    result = FX[def.effect](state, ctx or {source="joker"})
  end

  state.jokers.used_this_turn = true
  return result
end

-- Gain a single joker from the pool buffer. Respects the joker hand cap (base 5)
-- unless opts.allow_overflow is set (Fibonacci/Angel award bypass). Returns the
-- joker ID that was added, or nil if none was added (at cap without overflow, or
-- the registry has no drawable jokers). When the hand is full and overflow is not
-- allowed, sets state.jokers.last_lost to the would-be id so the UI can show a
-- "Joker lost" notice (3.3).
-- Optional ctx is forwarded to auto-use triggered jokers (Golden fires the
-- moment it enters the hand).
function J.gain_joker(state, rng, ctx, opts)
  opts = opts or {}
  local at_cap = #state.jokers.hand >= current_hand_cap(state)
  if at_cap and not opts.allow_overflow then
    -- Peek what would have been drawn so the caller can report it, then leave it
    -- on the pool (it is not consumed — the draw simply did not land).
    J.ensure_pool(state, rng, 1)
    local pool = state.jokers.pool
    state.jokers.last_lost = pool[#pool]
    return nil
  end
  local jid = J.draw_from_pool(state, rng)
  if jid then
    table.insert(state.jokers.hand, jid)
    local def = REG.by_id[jid]
    if def and def.jtype == "triggered" and def.effect == "golden" then
      FX.golden(state, ctx or { rng = rng })
    end
    -- 2.13: Fibonacci records the number of marked hands at acquisition time
    -- (FIFO; consumed on use). ctx.playedHands is supplied by main.lua.
    if jid == "fibonacci" then
      local count = 0
      if ctx and ctx.playedHands then
        for _, v in pairs(ctx.playedHands) do if v then count = count + 1 end end
      end
      state.jokers.fib_counts = state.jokers.fib_counts or {}
      table.insert(state.jokers.fib_counts, count)
    end
  end
  return jid
end

-- Gain n jokers from the pool buffer. Kept for callers that gain several jokers
-- at once. opts.allow_overflow lets the whole batch bypass the cap.
function J.gain_from_pool(state, n, rng, ctx, opts)
  n = n or 1
  opts = opts or {}
  for _=1,n do
    local added = J.gain_joker(state, rng, ctx, opts)
    if added == nil and not opts.allow_overflow
       and #state.jokers.hand >= current_hand_cap(state) then
      break  -- stop early once the hand is full
    end
  end
end

-- Convenience for UI/debug: returns shallow copies
function J.snapshot(state)
  local function copy(t) local r={} for i,v in ipairs(t) do r[i]=v end return r end
  return {
    hand = copy(state.jokers.hand),
    used_this_turn = state.jokers.used_this_turn,
    cap = current_hand_cap(state),
  }
end

return J
