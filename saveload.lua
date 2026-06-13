-- saveload.lua
-- Helper routines to snapshot and restore game state.

local M = {}

local function copy_hand(hand)
  local out = {}
  for i = 1, #hand do
    -- Preserve the Bicycle `temporary` flag so mid-turn temp cards survive a save.
    out[i] = { suit = hand[i].suit, rank = hand[i].rank, temporary = hand[i].temporary or nil }
  end
  return out
end

-- Deep copy for timed-effect entries (id/turns_remaining/payload/source).
local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deep_copy(val) end
  return out
end

function M.build_state(deck, hand, GS, S, UI)
  local deckState = deck:getState()
  local handCopy = copy_hand(hand)

  local gs = {
    phase = GS.phase,
    current_attack = (S and S.combat and S.combat.current_attack) or nil,
    correct_streak = (S and S.combat and S.combat.correct_streak) or 0,
    overlay = (UI and UI.overlay and UI.overlay.kind) or nil,
    turn  = GS.turn,
    endless = GS.endless or false,
    prep_turns_remaining = GS.prep_turns_remaining or 0,
    playedHands = {},
    limits = {
      discard_used = (GS.limits and GS.limits.discard_used) or false
    },
    meta   = GS.meta
  }
  for k,v in pairs(GS.playedHands) do gs.playedHands[k] = v and true or nil end

  local jokerState
  if S.jokers then
    jokerState = {
      hand = {},
      used_this_turn = S.jokers.used_this_turn,
      -- Number of Bicycle temporary cards live this turn (the cards themselves
      -- are restored from the hand, where they carry the `temporary` flag).
      temp_count = #(S.jokers.temp_cards or {}),
      -- M4 joker state flags
      flush_active          = S.jokers.flush_active or nil,
      trader_double         = S.jokers.trader_double or nil,
      peacock_active        = S.jokers.peacock_active or nil,
      peacock_extra_pending = S.jokers.peacock_extra_pending or nil,
      cute_active           = S.jokers.cute_active or nil,
      architect_active      = S.jokers.architect_active or nil,
      architect_site        = copy_hand(S.jokers.architect_site or {}),
      purge_pending         = S.jokers.purge_pending or nil,
      purge_selected        = deep_copy(S.jokers.purge_selected or nil),
      -- Post-M4 state
      pool                  = deep_copy(S.jokers.pool or nil),
      steal_disabled        = deep_copy(S.jokers.steal_disabled or nil),
      fib_counts            = deep_copy(S.jokers.fib_counts or nil),
      -- v4.2 state
      fourofclubs_active    = S.jokers.fourofclubs_active or nil,
      food_acquired         = S.jokers.food_acquired or nil,
    }
    for i,id in ipairs(S.jokers.hand or {}) do jokerState.hand[i] = id end
  end

  -- M4: timed effects (effects.lua) — deep copy each entry.
  local effects
  if S.active_effects then
    effects = {}
    for i, e in ipairs(S.active_effects) do effects[i] = deep_copy(e) end
  end

  local scoring
  if S.meta then
    scoring = {}
    for k,v in pairs(S.meta) do scoring[k] = v end
  end

  return {
    deck   = deckState,
    hand   = handCopy,
    gs     = gs,
    jokers = jokerState,
    scoring = scoring,
    active_effects = effects,
  }
end

function M.apply_state(state, deck, GS, S, UI, Scoring, Jokers)
  if deck and deck.loadState and state.deck then
    deck:loadState(state.deck)
  end

  local hand = {}
  for i = 1, #(state.hand or {}) do
    local c = state.hand[i]
    hand[i] = { suit = c.suit, rank = c.rank }
  end

  GS.phase = (state.gs and state.gs.phase) or "MAIN"
  GS.endless = (state.gs and state.gs.endless) or false
  GS.prep_turns_remaining = (state.gs and state.gs.prep_turns_remaining) or 0
  GS.turn  = (state.gs and state.gs.turn)  or 1
  GS.playedHands = {}
  if state.gs and state.gs.playedHands then
    for k,v in pairs(state.gs.playedHands) do GS.playedHands[k] = v and true or nil end
  end
  GS.limits = state.gs and state.gs.limits or { discard_used = false }
  if state.gs and state.gs.overlay then
    local k = state.gs.overlay
    UI.overlay = { kind = k, message = (k == "win") and "You Win!" or "Threshold completed" }
    GS.phase = "THRESHOLD"
  else
    UI.overlay = nil
  end
  GS.meta   = state.gs and state.gs.meta or { run_id = 1 }

  S.combat = S.combat or {}
  S.combat.current_attack = state.gs and state.gs.current_attack or S.combat.current_attack
  S.combat.correct_streak = (state.gs and state.gs.correct_streak) or 0

  if state.scoring then
    S.meta = {}
    for k,v in pairs(state.scoring) do S.meta[k] = v end
  else
    S.meta = nil
  end
  if Scoring then Scoring.init(S) end

  if Jokers then
    Jokers.init(S, love and love.math or math)
    if state.jokers then
      S.jokers.hand = {}
      for i,id in ipairs(state.jokers.hand or {}) do S.jokers.hand[i] = id end
      S.jokers.used_this_turn = state.jokers.used_this_turn
      -- M4 joker state flags
      S.jokers.flush_active          = state.jokers.flush_active or nil
      S.jokers.trader_double         = state.jokers.trader_double or nil
      S.jokers.peacock_active        = state.jokers.peacock_active or nil
      S.jokers.peacock_extra_pending = state.jokers.peacock_extra_pending or nil
      S.jokers.cute_active           = state.jokers.cute_active or nil
      S.jokers.architect_active      = state.jokers.architect_active or nil
      S.jokers.architect_site        = {}
      for i, c in ipairs(state.jokers.architect_site or {}) do
        S.jokers.architect_site[i] = { suit = c.suit, rank = c.rank, temporary = c.temporary or nil }
      end
      S.jokers.purge_pending  = state.jokers.purge_pending or nil
      S.jokers.purge_selected = deep_copy(state.jokers.purge_selected or nil)
      -- Post-M4 state
      S.jokers.pool           = deep_copy(state.jokers.pool or nil)
      S.jokers.steal_disabled = deep_copy(state.jokers.steal_disabled or nil)
      S.jokers.fib_counts     = deep_copy(state.jokers.fib_counts or nil)
      -- v4.2 state
      S.jokers.fourofclubs_active = state.jokers.fourofclubs_active or nil
      S.jokers.food_acquired      = state.jokers.food_acquired or nil
    end
    -- Rebuild temp_cards as references to the restored hand cards that still
    -- carry the `temporary` flag, so end-of-turn cleanup keeps working.
    S.jokers.temp_cards = {}
    for i = 1, #hand do
      if hand[i].temporary then table.insert(S.jokers.temp_cards, hand[i]) end
    end
  end

  -- M4: restore timed effects.
  S.active_effects = {}
  for i, e in ipairs(state.active_effects or {}) do
    S.active_effects[i] = deep_copy(e)
  end

  return hand
end

return M

