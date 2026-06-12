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

-- Pick a rarity by weighted random using REG.rarity_weights (Rule Book §
-- Joker Rarity Draw Probabilities).
local function pick_rarity(rng)
  local total = 0
  for _, w in pairs(REG.rarity_weights) do total = total + w end
  local r = rand_int(rng, 1, total)
  local acc = 0
  for rarity, w in pairs(REG.rarity_weights) do
    acc = acc + w
    if r <= acc then return rarity end
  end
  -- fallback (shouldn't happen)
  for rarity, _ in pairs(REG.rarity_weights) do return rarity end
end

-- Draw a single joker ID at random from the infinite probability pool: pick a
-- rarity by weighted random (REG.rarity_weights), then a uniformly random joker
-- of that rarity from the registry. Returns nil if no joker of the chosen rarity
-- exists yet (safe fallback). Duplicates are allowed.
function J.draw_random_joker(rng)
  local rarity = pick_rarity(rng)
  local ids = REG.ids_by_rarity()[rarity]
  if not ids or #ids == 0 then return nil end
  return ids[rand_int(rng, 1, #ids)]
end

-- Returns the joker hand cap (base 5, extendable by modifiers).
-- This is separate from the card hand cap (HAND_MAX = 15 in main.lua).
local function current_hand_cap(state)
  local base = 5
  local bonus = 0
  if state.jokers and state.jokers.modifiers and state.jokers.modifiers.hand_cap_bonus then
    bonus = state.jokers.modifiers.hand_cap_bonus
  end
  return base + bonus
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

-- Gain a single joker by weighted random rarity draw. Respects the joker hand
-- cap (base 5 + bonuses); a draw made while at cap is dropped. Returns the joker
-- ID that was added, or nil if none was added (at cap, or empty rarity bucket).
-- Optional ctx is forwarded to auto-use triggered jokers (Golden fires the
-- moment it enters the hand).
function J.gain_joker(state, rng, ctx)
  if #state.jokers.hand >= current_hand_cap(state) then return nil end
  local jid = J.draw_random_joker(rng)
  if jid then
    table.insert(state.jokers.hand, jid)
    local def = REG.by_id[jid]
    if def and def.jtype == "triggered" and def.effect == "golden" then
      FX.golden(state, ctx or { rng = rng })
    end
  end
  return jid
end

-- Gain n jokers by weighted random rarity draw (Rule Book § Joker Rarity Draw
-- Probabilities). There is no physical pool: each draw picks a rarity by weight,
-- then a uniformly random joker of that rarity from the registry. Kept for
-- backward compatibility with callers that gain several jokers at once.
function J.gain_from_pool(state, n, rng, ctx)
  n = n or 1
  for _=1,n do
    if J.gain_joker(state, rng, ctx) == nil and #state.jokers.hand >= current_hand_cap(state) then
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
