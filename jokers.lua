-- jokers.lua
local REG = require("joker_registry")
local FX  = require("joker_effects")

local J = {}

local function shuffle(t, rng)
  for i = #t, 2, -1 do
    local j
    if rng then
      -- `love.math` exposes `random` as a plain function, while
      -- `RandomGenerator` objects expect a method call. Detect which form
      -- we received so both cases work.
      if rng.random == love.math.random then
        j = rng.random(1, i)
      else
        j = rng:random(1, i)
      end
    else
      j = love.math.random(1, i)
    end
    t[i], t[j] = t[j], t[i]
  end
end

local function build_pool_from_registry(rng)
  local by_r = REG.ids_by_rarity()
  local counts = REG.rarity_counts
  local pool = {}

  local function add_many(list, n_each)
    for _,id in ipairs(list) do
      for _=1,n_each do table.insert(pool, id) end
    end
  end

  if #by_r.common     > 0 then add_many(by_r.common,     counts.common    or 0) end
  if #by_r.uncommon   > 0 then add_many(by_r.uncommon,   counts.uncommon  or 0) end
  if #by_r.rare       > 0 then add_many(by_r.rare,       counts.rare      or 0) end
  if #by_r.epic       > 0 then add_many(by_r.epic,       counts.epic      or 0) end
  if #by_r.legendary  > 0 then add_many(by_r.legendary,  counts.legendary or 0) end
  if #by_r.mythic     > 0 then add_many(by_r.mythic,     counts.mythic    or 0) end

  shuffle(pool, rng)
  return pool
end

local function current_hand_cap(state)
  local base = 5
  local bonus = 0
  if state.jokers and state.jokers.modifiers and state.jokers.modifiers.hand_cap_bonus then
    bonus = state.jokers.modifiers.hand_cap_bonus
  end
  return base + bonus
end

local function reshuffle_if_needed(state, rng)
  if #state.jokers.pool == 0 and #state.jokers.played_pile > 0 then
    -- recycle played jokers back into pool
    for i=#state.jokers.played_pile,1,-1 do
      table.insert(state.jokers.pool, table.remove(state.jokers.played_pile, i))
    end
    shuffle(state.jokers.pool, rng)
  end
end

function J.init(state, rng)
  state.jokers = state.jokers or {}
  state.jokers.pool        = state.jokers.pool        or build_pool_from_registry(rng)
  state.jokers.hand        = state.jokers.hand        or {}
  state.jokers.played_pile = state.jokers.played_pile or {}
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

-- Use a joker in hand by index; triggers its effect; moves joker to played pile; sets limiter.
function J.use(state, hand_index, ctx)
  assert(hand_index and state.jokers.hand[hand_index], "Invalid joker index")
  if state.jokers.used_this_turn then return { ok=false, err="Only one joker per turn." } end

  local jid = table.remove(state.jokers.hand, hand_index)
  local def = REG.by_id[jid]
  local result = { ok=true }

  if def and def.effect and FX[def.effect] then
    result = FX[def.effect](state, ctx or {source="joker"})
  end

  table.insert(state.jokers.played_pile, jid)
  state.jokers.used_this_turn = true
  return result
end

-- Gain n jokers from pool (called after a hand is successfully played)
function J.gain_from_pool(state, n, rng)
  n = n or 1
  for _=1,n do
    reshuffle_if_needed(state, rng)
    if #state.jokers.pool == 0 then break end

    local jid = table.remove(state.jokers.pool)
    -- Respect (cap + bonuses). If cap reached, send to played_pile as overflow (optional rule), or drop.
    local cap = current_hand_cap(state)
    if #state.jokers.hand < cap then
      table.insert(state.jokers.hand, jid)
    else
      -- Overflow rule: by default, overflow goes to played_pile so it can recycle later.
      table.insert(state.jokers.played_pile, jid)
    end
  end
end

-- Call when a full poker hand is played/resolved to grant 1 joker
function J.on_hand_played(state, rng)
  J.gain_from_pool(state, 1, rng)
end

-- Convenience for UI/debug: returns shallow copies
function J.snapshot(state)
  local function copy(t) local r={} for i,v in ipairs(t) do r[i]=v end return r end
  return {
    hand = copy(state.jokers.hand),
    pool = #state.jokers.pool,
    played = #state.jokers.played_pile,
    used_this_turn = state.jokers.used_this_turn,
    cap = current_hand_cap(state),
  }
end

return J
