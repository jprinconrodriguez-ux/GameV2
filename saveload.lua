-- saveload.lua
-- Helper routines to snapshot and restore game state.

local M = {}

local function copy_hand(hand)
  local out = {}
  for i = 1, #hand do
    out[i] = { suit = hand[i].suit, rank = hand[i].rank }
  end
  return out
end

function M.build_state(deck, hand, GS, S, UI)
  local deckState = deck:getState()
  local handCopy = copy_hand(hand)

  local gs = {
    phase = GS.phase,
    current_attack = (S and S.combat and S.combat.current_attack) or nil,
    overlay = (UI and UI.overlay and UI.overlay.kind) or nil,
    turn  = GS.turn,
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
      pool = {},
      hand = {},
      played_pile = {},
      used_this_turn = S.jokers.used_this_turn
    }
    for i,id in ipairs(S.jokers.pool or {}) do jokerState.pool[i] = id end
    for i,id in ipairs(S.jokers.hand or {}) do jokerState.hand[i] = id end
    for i,id in ipairs(S.jokers.played_pile or {}) do jokerState.played_pile[i] = id end
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
      S.jokers.pool = {}
      S.jokers.hand = {}
      S.jokers.played_pile = {}
      for i,id in ipairs(state.jokers.pool or {}) do S.jokers.pool[i] = id end
      for i,id in ipairs(state.jokers.hand or {}) do S.jokers.hand[i] = id end
      for i,id in ipairs(state.jokers.played_pile or {}) do S.jokers.played_pile[i] = id end
      S.jokers.used_this_turn = state.jokers.used_this_turn
    end
  end

  return hand
end

return M

