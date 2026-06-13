-- main.lua
local Deck = require("deck")
local Eval = require("evaluator")
local GS   = require("gamestate")  -- Gamestate
local Rules= require("rules")      -- NEW: sorting + categories
local Scoring = require("scoring")
local Attacks = require("attacks")
local Jokers = require("jokers")
local JokerReg = require("joker_registry")
local SaveLoad = require("saveload")
local Effects = require("effects")
local FX = require("joker_effects")

-- === CONSTANTS (safe defaults) ===
local HAND_START = HAND_START or 7    -- starting hand size
-- Card hand cap (max cards held). Separate from the joker hand cap (max 5, in jokers.lua).
-- 1.5: HAND_MAX is 14. Food Joker (2.9) raises the effective cap by +3 while in
-- hand — use effectiveHandMax() everywhere instead of HAND_MAX directly.
local HAND_MAX   = HAND_MAX   or 14   -- absolute base cap
local NUM_DECKS  = NUM_DECKS  or 2    -- SP default; MP later = players + 1

-- === STATE ===
local deck
local hand = {}          -- make sure 'hand' exists before helpers use it
local selected = {}
local selectedJoker = nil
local statusMsg = ""
local font

-- persistent sort mode in-session
local currentSort = "rank"

-- Buttons
local UI = { overlay = nil, jokerMenuOpen = false }

-- M4 joker choice overlays (Steal/Acrobat/Eye/Angel/Purge) transient UI state:
-- choiceSel = set of selected row indices (Acrobat picks, Purge picks),
-- eyeOrder = working reorder of the Eye's peeked pool ids, eyeFrom = pending swap source.
UI.choiceSel = {}
UI.eyeOrder = nil
UI.eyeFrom = nil

-- Button row sits in the strip between the joker row (ends at JOKER_Y+JOKER_H=340)
-- and the card hand (HAND_Y=380): y=344, h=30 → ends at 374, 6px above the cards.
local BTN_RESTART = {x=40,  y=344, w=100, h=30, label="Restart"}
local BTN_RANK    = {x=160, y=344, w=110, h=30, label="Sort: Rank"}
local BTN_SUIT    = {x=280, y=344, w=110, h=30, label="Sort: Suit"}
local BTN_SAVE   = {x=400, y=344, w=90,  h=30, label="Save"}
local BTN_LOAD   = {x=500, y=344, w=90,  h=30, label="Load"}
local BTN_SKIP       = {x=600, y=344, w=90,  h=30, label="Skip"}    -- DEBUG: playtesting skip
local BTN_JOKER_MENU = {x=700, y=344, w=110, h=30, label="Jokers"}  -- DEBUG: playtesting joker inject
local BTN_NEXT_T = {x=0, y=0, w=140, h=36, label="Next"}  -- overlay button; positioned relative to panel, untouched
local BTN_ENDLESS = {x=0, y=0, w=140, h=36, label="Endless Mode"} -- win overlay; positioned in love.draw
local BTN_START  = {x=0, y=0, w=160, h=44, label="Start"} -- title screen; positioned in love.draw

-- SAVE/LOAD
-- Bare filename (no leading "/" or "./"): love.filesystem resolves this to LÖVE's
-- persistent save directory (see love.filesystem.getSaveDirectory()), so the save
-- survives quit/relaunch across sessions.
local SAVE_SLOT = "save_slot_1.lua"  -- saved as Lua table (return { ... })

-- Tiny Lua serializer (acyclic tables with string/number/boolean/nil)
local function serializeLua(v, indent, seen)
  indent = indent or ""
  local t = type(v)
  if t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "string" then
    return string.format("%q", v)
  elseif v == nil then
    return "nil"
  elseif t == "table" then
    if seen and seen[v] then error("cycle detected in serialize") end
    seen = seen or {}; seen[v] = true
    -- detect array part
    local isArray, n = true, #v
    for k,_ in pairs(v) do
      if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isArray = false break end
    end
    local pieces = {}
    if isArray then
      for i = 1, n do table.insert(pieces, serializeLua(v[i], indent.."  ", seen)) end
      return "{ "..table.concat(pieces, ", ").." }"
    else
      for k,val in pairs(v) do
        local key
        if type(k) == "string" and k:match("^[_%a][_%w]*$") then
          key = k.." = "
        else
          key = "["..serializeLua(k, indent.."  ", seen).."] = "
        end
        table.insert(pieces, key..serializeLua(val, indent.."  ", seen))
      end
      return "{ "..table.concat(pieces, ", ").." }"
    end
  else
    error("unsupported type in serialize: "..t)
  end
end

local function setStatus(s) statusMsg = s or "" end

local S = {}

-- Effective card hand cap = HAND_MAX (+3 while Food Joker is in hand, 2.9).
local function effectiveHandMax()
  return Jokers.card_hand_max(S, HAND_MAX)
end

-- Forward declarations
local nextTurn
local restartGame

-- === SAFE HELPERS ===

-- Auto-reshuffle: when deck is empty, move all discard back to deck and shuffle
local function reshuffle_discard_into_deck()
  if not deck or not deck.cards or not deck.discard then return end
  if #deck.cards > 0 then return end
  if #deck.discard == 0 then return end
  for i = #deck.discard, 1, -1 do
    table.insert(deck.cards, table.remove(deck.discard, i))
  end
  for i = #deck.cards, 2, -1 do
    local j = love.math.random(i)
    deck.cards[i], deck.cards[j] = deck.cards[j], deck.cards[i]
  end
end

local function getHandSize()
  if type(hand) == "table" then return #hand else return 0 end
end

-- Losing mechanic (v3.1): the run ends in a loss if the main deck is fully
-- depleted with nothing left to reshuffle AND the player has not yet met the
-- score target AND played every hand category at least once.
-- 3.1: Game Over — deck, discard, and (locked) played pile are exhausted with
-- no cards left to draw into hand and the threshold target unmet. Distinct from
-- the win/threshold overlay; offers a Restart button.
local function triggerLoss()
  GS.phase = "LOSS"
  setStatus("Game Over — no cards left to draw.")
  UI.overlay = { kind = "loss", message = "Game Over\nNo cards left to draw and the target was not reached." }
end

-- Call after a draw could not be satisfied. If both the main deck and the
-- discard pile are empty (the played pile stays locked until threshold advance)
-- and neither win condition is met, end the run as a loss.
local function maybeTriggerDepletion()
  if not deck or not deck.cards or not deck.discard then return end
  if #deck.cards > 0 or #deck.discard > 0 then return end
  if GS.phase == "WIN" or GS.phase == "LOSS" or GS.phase == "THRESHOLD" then return end
  local won = Scoring and Scoring.is_threshold_complete and Scoring.is_threshold_complete(S)
              and Rules and Rules.isAllMarked and Rules.isAllMarked(GS)
  if not won then triggerLoss() end
end

local function can_draw(n)
  local hand_max = effectiveHandMax()
  local free = hand_max - getHandSize()
  if free < 0 then free = 0 end
  if n == nil or n < 0 then n = 0 end
  if free < n then return free else return n end
end

local function drawN(n)
  local effective_max = effectiveHandMax()
  local drawnCount = 0
  if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
  for _ = 1, (n or 0) do
    if getHandSize() >= effective_max then break end
    local d = deck:draw(1)
    if #d == 0 then break end
    table.insert(hand, d[1])
    drawnCount = drawnCount + 1
  end
  maybeTriggerDepletion()
  if drawnCount > 0 then
    if currentSort == "suit" and Rules and Rules.sortHandBySuit then
      Rules.sortHandBySuit(hand)
    elseif Rules and Rules.sortHandByRank then
      Rules.sortHandByRank(hand)
    end
  end
  return drawnCount
end

S.drawCards = drawN

-- Bicycle support: append temporary cards to the hand and track them so the
-- end-of-turn cleanup can remove any that were not played this turn.
S.addTempCards = function(cards)
  S.jokers = S.jokers or {}
  S.jokers.temp_cards = S.jokers.temp_cards or {}
  for _, c in ipairs(cards or {}) do
    table.insert(hand, c)
    table.insert(S.jokers.temp_cards, c)
  end
  if currentSort == "suit" and Rules and Rules.sortHandBySuit then
    Rules.sortHandBySuit(hand)
  elseif Rules and Rules.sortHandByRank then
    Rules.sortHandByRank(hand)
  end
end

local function drawUpTo(target)
  local effective_max = effectiveHandMax()
  target = math.min(target or HAND_START, effective_max)
  local total = 0
  while getHandSize() < target do
    if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
    local d = deck:draw(1)
    if #d == 0 then break end
    table.insert(hand, d[1])
    total = total + 1
  end
  maybeTriggerDepletion()
  if total > 0 then
    if currentSort == "suit" and Rules and Rules.sortHandBySuit then
      Rules.sortHandBySuit(hand)
    elseif Rules and Rules.sortHandByRank then
      Rules.sortHandByRank(hand)
    end
  end
  return total
end


-- === PREPARATION PHASE (M3) ===
-- 3 setup turns at game start and each threshold transition.
-- Only discard/draw allowed; no attack announced; skipping awards a scaled bonus.

local function endPrepPhase()
  GS.prep_turns_remaining = 0
  GS.phase = "MAIN"
  nextTurn()  -- announces first attack, resets discard flag, etc.
  setStatus("Your turn.")
end

local function usePrepTurn()
  GS.prep_turns_remaining = GS.prep_turns_remaining - 1
  if GS.prep_turns_remaining <= 0 then
    endPrepPhase()
  else
    setStatus("Setup Phase — " .. GS.prep_turns_remaining .. " turn(s) remaining. (Skip: S key)")
  end
end

local function enterPrepPhase()
  GS.phase = "PREP"
  GS.prep_turns_remaining = 3
  selected = {}
  selectedJoker = nil
  setStatus("Setup Phase — " .. GS.prep_turns_remaining .. " turns remaining. (Skip: S key)")
end

-- Threshold advance: bump threshold, reset score, keep hand/jokers, recycle piles,
-- then enter the preparation phase (the first attack fires when prep ends).
local function mergePilesIntoDeck()
  if not deck then return end
  deck.cards = deck.cards or {}
  deck.discard = deck.discard or {}
  deck.played = deck.played or {}
  for i = #deck.discard, 1, -1 do
    table.insert(deck.cards, table.remove(deck.discard, i))
  end
  for i = #deck.played, 1, -1 do
    table.insert(deck.cards, table.remove(deck.played, i))
  end
  for i = #deck.cards, 2, -1 do
    local j = love.math.random(i)
    deck.cards[i], deck.cards[j] = deck.cards[j], deck.cards[i]
  end
end

-- TODO: ENDLESS MODE REWORK — scope to be defined in a separate session (Step 4).
local function advanceThreshold()
  if not S.meta then return end
  local cur = S.meta.threshold or 1
  if cur >= 3 and not GS.endless then
    -- Safety guard: past T3 only Endless Mode may advance. (The unified win
    -- check in the play flow is the canonical trigger for the win overlay.)
    GS.phase = "WIN"
    UI.overlay = { kind = "win", message = "You Win! Continue to Endless?" }
    return
  end
  S.meta.threshold = cur + 1
  if Scoring and Scoring.reset_for_next_threshold then Scoring.reset_for_next_threshold(S) end
  -- Joker hand intentionally NOT reset here; jokers carry over between thresholds per the rules.
  GS.playedHands = {}  -- clear the checklist for the new tier
  mergePilesIntoDeck()
  -- M4: strip timed effects that don't carry across thresholds, and close out
  -- per-threshold joker state (Peacock, Architect).
  Effects.clear_tag(S, "no_carry")
  if S.jokers then
    S.jokers.peacock_active = nil
    S.jokers.peacock_extra_pending = nil
    S.jokers.architect_site = {}      -- 2.11: building site does not carry over
    S.jokers.architect_active = false
    -- 2.7: jokers disabled by Steal re-enter the pool at the next threshold.
    if S.jokers.steal_disabled and #S.jokers.steal_disabled > 0 then
      S.jokers.pool = S.jokers.pool or {}
      for _, id in ipairs(S.jokers.steal_disabled) do
        table.insert(S.jokers.pool, id)
      end
      S.jokers.steal_disabled = {}
    end
  end
  drawUpTo(HAND_START)
  UI.overlay = nil
  enterPrepPhase()  -- nextTurn() fires when prep ends
end

-- Overlay confirm (Enter key): "Next" advances the threshold; on the win
-- overlay Enter defaults to Endless Mode (R / Restart button restarts).
local function confirmOverlay()
  if not (UI and UI.overlay) then return end
  if UI.overlay.kind == "win" then
    GS.endless = true
    UI.overlay = nil
    advanceThreshold()
  else
    advanceThreshold()
  end
end

-- Layout

local CARD_W, CARD_H = 80, 110
local HAND_X, HAND_Y = 40, 380
local GAP = 12

-- Joker layout
local JOKER_W, JOKER_H = 60, 90
local JOKER_X, JOKER_Y = 40, 250
local JOKER_GAP = 10

-- Selection helpers
local function selectedIndices()
  local idxs = {}
  for i = 1, #hand do
    if selected[i] then table.insert(idxs, i) end
  end
  return idxs
end

local function cardsFromIndices(idxs)
  local t = {}
  for _, i in ipairs(idxs) do table.insert(t, hand[i]) end
  return t
end

local function jokerPos(i)
  local x = JOKER_X + (i-1) * (JOKER_W + JOKER_GAP)
  local y = JOKER_Y
  return x, y
end

-- 2.13: ordinal of the k-th Fibonacci in hand → its stored acquisition count,
-- shown as a small badge. Returns nil for non-Fibonacci jokers.
local function fibBadgeFor(handIndex)
  if not (S.jokers and S.jokers.hand and S.jokers.hand[handIndex] == "fibonacci") then
    return nil
  end
  local ordinal = 0
  for i = 1, handIndex do
    if S.jokers.hand[i] == "fibonacci" then ordinal = ordinal + 1 end
  end
  local counts = S.jokers.fib_counts or {}
  return counts[ordinal]
end

local function drawJoker(jid, i)
  local x, y = jokerPos(i)
  local def = JokerReg.by_id[jid]
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("fill", x, y, JOKER_W, JOKER_H, 8, 8)
  love.graphics.setColor(0,0,0)
  love.graphics.rectangle("line", x, y, JOKER_W, JOKER_H, 8, 8)
  local label = def and def.name or tostring(jid)
  love.graphics.printf(label, x+4, y + JOKER_H/2 - 8, JOKER_W-8, "center")
  -- 2.13: Fibonacci acquisition-count badge in the top-right corner.
  local badge = fibBadgeFor(i)
  if badge ~= nil then
    love.graphics.setColor(0.95, 0.85, 0.2)
    love.graphics.rectangle("fill", x + JOKER_W - 18, y + 2, 16, 16, 3, 3)
    love.graphics.setColor(0, 0, 0)
    love.graphics.printf(tostring(badge), x + JOKER_W - 18, y + 3, 16, "center")
    love.graphics.setColor(1, 1, 1)
  end
  if selectedJoker == i then
    love.graphics.setColor(1, 0.9, 0.3, 0.35)
    love.graphics.rectangle("fill", x, y, JOKER_W, JOKER_H, 8, 8)
    love.graphics.setColor(0.8,0.5,0)
    love.graphics.rectangle("line", x+2, y+2, JOKER_W-4, JOKER_H-4, 8, 8)
  end
  love.graphics.setColor(1,1,1)
end

local function jokerAtPosition(x, y)
  if not S.jokers or not S.jokers.hand then return nil end
  for i = 1, #S.jokers.hand do
    local jx, jy = jokerPos(i)
    if x >= jx and x <= jx + JOKER_W and y >= jy and y <= jy + JOKER_H then
      return i
    end
  end
  return nil
end

-- === TURN HELPERS ===

-- Shared ctx for joker effects (used by J.use and forwarded to auto-use
-- triggered jokers like Golden via gain_from_pool).
local function buildJokerCtx()
  local ctx
  ctx = {
    source         = "key",
    rng            = love.math,
    deck           = deck,
    hand           = hand,
    playedHands    = GS.playedHands,
    gain_from_pool = function(n, opts) Jokers.gain_from_pool(S, n, love.math, ctx, opts) end,
  }
  return ctx
end

-- 1.2: mid-turn threshold/win check. Call after any scoring event. Returns true
-- if a threshold/win overlay was triggered (caller should stop processing).
local function checkThresholdWin()
  if not (S and S.meta) then return false end
  if not (Scoring and Scoring.is_threshold_complete and Scoring.is_threshold_complete(S)) then
    return false
  end
  if S.meta.threshold == 3 then
    if Rules.isAllMarked(GS) then
      GS.phase = "WIN"
      UI.overlay = { kind = "win", message = "You Win! Continue to Endless?" }
      return true
    end
    return false  -- T3 score met but not all 8 hands → no win yet
  end
  GS.phase = "THRESHOLD"
  UI.overlay = { kind = "threshold", message = "Threshold completed" }
  return true
end

-- 1.1 / 3.2: register a scored hand for the attack-match streak (S.meta.streak).
-- Extra turns are excluded entirely. Every 3rd match grants a bonus joker. Called
-- for manual plays AND joker auto-scores (Golden 2.8.2, The Flush 2.9), so the
-- streak (and any milestone joker) resolves before a threshold transition.
local function noteScoredHand(handName)
  if GS.extra_turn then return end                         -- 1.1: skip extra turns
  if not (S.combat and S.combat.current_attack) then return end
  if handName ~= S.combat.current_attack then return end
  if S.combat.streak_counted_this_turn then return end     -- one count per turn
  S.combat.streak_counted_this_turn = true
  S.meta.streak = (S.meta.streak or 0) + 1
  if S.meta.streak % 3 == 0 then
    if Jokers then Jokers.gain_from_pool(S, 1, love.math, buildJokerCtx()) end
  end
end

-- Resolve the current attack and return a short status fragment. Applies the
-- penalty (resets the streak on a miss). Does NOT advance the turn.
local function resolveAttackMsg()
  if not (Attacks and Scoring) then return "" end
  local res = Attacks.resolve(S, Scoring)
  if not (res and res.resolved) then return "" end
  if res.penalized then
    S.meta.streak = 0  -- 1.1: a missed attack breaks the streak
    if res.halved then
      return "Attack "..res.target.." ⚡ -"..tostring(res.penalty).." (halved)"
    end
    return "Attack "..res.target.." ⚠ -"..tostring(res.penalty)
  elseif res.canceled then
    return "Attack canceled."
  elseif res.shielded then
    return "Anti-Joker shielded "..res.target.."."
  elseif res.purged then
    return "Purge nullified "..res.target.."."
  elseif res.protected then
    return "Blocked "..res.target.."!"
  end
  return ""
end

-- End-of-turn path used by the DEBUG skip (and any non-play turn end): resolve
-- the attack, run the win check, then advance.
local function enterEndPhase()
  local atkMsg = resolveAttackMsg()
  if atkMsg ~= "" then setStatus(atkMsg) end
  if checkThresholdWin() then return end
  nextTurn()
end

-- Remove any Bicycle temporary cards still in hand (i.e. not played this turn).
-- Played temporary cards have had their `temporary` flag cleared and were moved
-- into the deck, so only unplayed ones remain flagged here.
local function cleanupTempCards()
  if not (S.jokers and S.jokers.temp_cards) then return end
  for i = #hand, 1, -1 do
    if hand[i] and hand[i].temporary then table.remove(hand, i) end
  end
  S.jokers.temp_cards = {}
end

-- 2.3: extra-turn support. An extra turn (Peacock) does NOT advance the turn
-- counter — it shows "Extra" instead — and announces no attack. The main counter
-- resumes from where it left off on the following normal turn.
nextTurn = function(isExtra)
  cleanupTempCards()
  GS.phase = "MAIN"
  if isExtra then
    GS.extra_turn = true
  else
    GS.extra_turn = false
    GS.turn = (GS.turn or 1) + 1
  end
  setStatus(isExtra and "Peacock bonus: extra turn!" or "Your turn.")
  -- Peacock: grant an extra turn every 5 turns while active (never on an extra
  -- turn itself, to avoid chaining). Deferred via a flag that love.update checks.
  if not isExtra and S.jokers and S.jokers.peacock_active and GS.turn % 5 == 0 then
    S.jokers.peacock_extra_pending = true
  end
  -- Cute Joker safety cleanup: the 6-card two-trips play only lasts the turn
  -- the joker was used.
  if S.jokers then S.jokers.cute_active = nil end
  if Scoring and Scoring.on_turn_advanced then Scoring.on_turn_advanced(S) end
    GS.limits = GS.limits or {}
  GS.limits.discard_used = false
  selected = {}  -- ensure clean state
  selectedJoker = nil
  if Scoring and not S.meta then Scoring.init(S) end
  Effects.tick(S)
  -- 2.3: no attack is announced on an extra turn — current_attack stays nil.
  if isExtra then
    S.combat = S.combat or {}
    S.combat.current_attack = nil
  elseif Attacks then
    Attacks.announce(S, love.math)
  end
  if Jokers then Jokers.start_turn(S) end
  -- 3.1: at turn start, if the hand is empty and nothing can be drawn, end the run.
  if getHandSize() == 0 then maybeTriggerDepletion() end
end

-- Discard (up to 5) and redraw same amount (respect HAND_MAX)
local function discardSelected()
  -- PREP: each discard/draw consumes one setup turn; the per-turn discard
  -- limit does not apply (it resets when MAIN begins via nextTurn()).
  if GS.phase ~= "PREP" and GS.limits and GS.limits.discard_used then
    setStatus("Discard already used this turn.")
    return
  end
  if GS.phase == "END" then
    setStatus("Turn advanced automatically.")
    return
  end

  local idxs = selectedIndices()
  if #idxs == 0 or #idxs > 5 then
    setStatus("Select 1–5 cards to discard.")
    return
  end

  local toDiscard = {}
  table.sort(idxs, function(a,b) return a>b end)
  for _, i in ipairs(idxs) do
    table.insert(toDiscard, hand[i])
    table.remove(hand, i)
  end
  deck:discardCards(toDiscard)
  selected = {}

  local need = can_draw(#toDiscard)
  if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
  local drawn = deck:drawNoReshuffle(need)
  for i = 1, #drawn do table.insert(hand, drawn[i]) end
  local drew = #drawn
  if currentSort == "suit" and Rules and Rules.sortHandBySuit then
    Rules.sortHandBySuit(hand)
  elseif Rules and Rules.sortHandByRank then
    Rules.sortHandByRank(hand)
  end
  maybeTriggerDepletion()  -- 3.1 (no-op while the discard pile still has cards)
  setStatus("Discarded "..#toDiscard..", drew "..tostring(drew)..".")
  if GS.phase == "PREP" then
    usePrepTurn()
    return
  end
  -- stay in MAIN phase; you can still play a hand this turn
  GS.limits = GS.limits or {}
  GS.limits.discard_used = true
end

-- === SAVE/LOAD CORE ===
local function buildSaveState()
  return SaveLoad.build_state(deck, hand, GS, S, UI)
end

local function applyLoadedState(state)
  hand = SaveLoad.apply_state(state, deck, GS, S, UI, Scoring, Jokers)
  selected = {}
  selectedJoker = nil
  setStatus("Loaded game. Phase: "..GS.phase..", Turn "..tostring(GS.turn))
  currentSort = (state.gs and (state.gs.sortPref or state.gs.sortMode)) or currentSort or "rank"
  if currentSort == "suit" and Rules and Rules.sortHandBySuit then
    Rules.sortHandBySuit(hand)
  elseif Rules and Rules.sortHandByRank then
    Rules.sortHandByRank(hand)
  end
end

local function saveToSlot(path)
  local ok, err = pcall(function()
    local data = "return " .. serializeLua(buildSaveState())
    love.filesystem.write(path or SAVE_SLOT, data)
  end)
  if ok then
    setStatus("Game saved.")
  else
    setStatus("Save failed: "..tostring(err))
  end
end

local function loadFromSlot(path)
  local chunk, err = love.filesystem.load(path or SAVE_SLOT)
  if not chunk then
    setStatus("No save found.")
    return
  end
  local ok, state = pcall(chunk)
  if not ok then
    setStatus("Corrupt save.")
    return
  end
  applyLoadedState(state)
end

-- Restart
restartGame = function()
  deck = Deck.new(NUM_DECKS)
  S.meta = nil
  S.jokers = nil
  S.combat = nil
  S.active_effects = nil
  selectedJoker = nil
  UI.jokerMenuOpen = false
  UI.choiceSel = {}
  UI.eyeOrder = nil
  UI.eyeFrom = nil
  if Scoring then Scoring.init(S) end
  if Jokers then
    Jokers.init(S, love.math)
    Jokers.start_turn(S)
  end
  -- No attack announce here: the run opens in PREP (no attacks during setup);
  -- the first attack is announced by nextTurn() when prep ends.
  hand = {}
  selected = {}
  GS:reset()
  setStatus("")
  enterPrepPhase()
  drawUpTo(HAND_START)
end

-- 3.5.1: fixed 2×7 grid (14 cards max). Cards fill left-to-right, top row first.
local function handPos(i)
  local perRow = 7  -- row 1: cards 1–7, row 2: cards 8–14
  local row = math.floor((i-1) / perRow)
  local col = (i-1) % perRow
  local x = HAND_X + col * (CARD_W + GAP)
  local y = HAND_Y + row * (CARD_H + 10)
  return x, y
end

local function cardAtPosition(x, y)
  for i = 1, #hand do
    local cx, cy = handPos(i)
    if x >= cx and x <= cx + CARD_W and y >= cy and y <= cy + CARD_H then
      return i
    end
  end
  return nil
end

local function pointInRect(x, y, r)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function drawButton(rect)
  love.graphics.setColor(0.9,0.95,1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)
  love.graphics.setColor(0,0,0)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6, 6)
  love.graphics.printf(rect.label, rect.x, rect.y + 6, rect.w, "center")
  love.graphics.setColor(1,1,1)
end

-- === M4: Joker choice overlays (Steal / Acrobat / Eye / Angel / Purge) ===

-- Which choice overlay (if any) is currently pending. While one is pending all
-- other mouse/keyboard input is blocked.
local function pendingChoiceKind()
  local j = S.jokers
  if not j then return nil end
  if j.steal_choice_pending then return "steal" end
  if j.acrobat_choice_pending then return "acrobat" end
  if j.eye_choice_pending then return "eye" end
  if j.angel_choice_pending then return "angel" end
  if j.purge_pending then return "purge" end
  return nil
end

local function resetChoiceUI()
  UI.choiceSel = {}
  UI.eyeOrder = nil
  UI.eyeFrom = nil
  UI.acrobatViewHand = nil
end

-- Returns title, row labels, and whether the overlay has a Confirm button.
local function buildChoiceRows(kind)
  local j = S.jokers
  if kind == "steal" then
    local rows = {}
    for i, jid in ipairs((j.steal_pending and j.steal_pending.ids) or {}) do
      local def = JokerReg.by_id[jid]
      rows[i] = "Keep " .. ((def and def.name) or tostring(jid))
    end
    return "Steal: choose a joker to keep — the other is disabled this threshold (Esc cancels)", rows, false
  elseif kind == "acrobat" then
    -- 2.5: H toggles between the deck's top 10 (pickable) and your current hand
    -- (read-only) so you can make an informed choice before confirming.
    if UI.acrobatViewHand then
      local rows = {}
      for i, c in ipairs(hand) do
        local r = (c.rank == "T") and "10" or tostring(c.rank)
        rows[i] = r .. " " .. c.suit
      end
      return "Acrobat — your hand (H: back to deck, Esc cancels)", rows, true
    end
    local rows = {}
    for i, c in ipairs((j.acrobat_pending and j.acrobat_pending.cards) or {}) do
      local r = (c.rank == "T") and "10" or tostring(c.rank)
      rows[i] = (UI.choiceSel[i] and "[x] " or "[ ] ") .. r .. " " .. c.suit
    end
    return "Acrobat: pick up to 4 cards (H: view hand, Esc cancels), then Confirm", rows, true
  elseif kind == "eye" then
    if not UI.eyeOrder then
      UI.eyeOrder = {}
      for i, id in ipairs((j.eye_pending and j.eye_pending.ids) or {}) do
        UI.eyeOrder[i] = id
      end
    end
    local rows = {}
    for i, jid in ipairs(UI.eyeOrder) do
      local def = JokerReg.by_id[jid]
      local mark = (UI.eyeFrom == i) and "→ " or ""
      rows[i] = mark .. i .. ". " .. ((def and def.name) or tostring(jid))
    end
    return "Eye: click two positions to swap, then Confirm (Esc cancels)", rows, true
  elseif kind == "angel" then
    local rows = {}
    for i, jid in ipairs((j.angel_pending and j.angel_pending.ids) or {}) do
      local def = JokerReg.by_id[jid]
      rows[i] = "Copy " .. ((def and def.name) or tostring(jid))
    end
    return "Angel: choose a joker to copy", rows, false
  elseif kind == "purge" then
    local rows = {}
    for i, name in ipairs(Rules.CATEGORIES) do
      rows[i] = (UI.choiceSel[i] and "[x] " or "[ ] ") .. name
    end
    return "Purge: choose 2 hand types to protect (5 turns)", rows, false
  end
  return "", {}, false
end

local function choicePanelRect(rows)
  local ww, wh = love.graphics.getDimensions()
  local pw = 460
  local ph = 58 + rows * 32 + 50
  local px = math.floor((ww - pw) / 2)
  local py = math.floor((wh - ph) / 2)
  return px, py, pw, ph
end

local function choiceRowRect(px, py, i)
  return { x = px + 20, y = py + 48 + (i - 1) * 32, w = 420, h = 28 }
end

local function choiceConfirmRect(px, py, pw, ph)
  return { x = px + math.floor(pw / 2) - 60, y = py + ph - 42, w = 120, h = 32 }
end

local function drawChoiceOverlay(kind)
  local title, rows, hasConfirm = buildChoiceRows(kind)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  local px, py, pw, ph = choicePanelRect(#rows)
  love.graphics.setColor(0.12, 0.12, 0.18, 0.97)
  love.graphics.rectangle("fill", px, py, pw, ph, 10, 10)
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", px, py, pw, ph, 10, 10)
  love.graphics.printf(title, px + 16, py + 14, pw - 32, "center")
  for i, label in ipairs(rows) do
    local r = choiceRowRect(px, py, i)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 4, 4)
    love.graphics.printf(label, r.x, r.y + 5, r.w, "center")
  end
  if hasConfirm then
    local cr = choiceConfirmRect(px, py, pw, ph)
    love.graphics.rectangle("line", cr.x, cr.y, cr.w, cr.h, 6, 6)
    love.graphics.printf("Confirm", cr.x, cr.y + 7, cr.w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

-- Handles a click while a choice overlay is pending. Consumes the click entirely.
local function choiceOverlayClick(kind, x, y)
  local _, rows, hasConfirm = buildChoiceRows(kind)
  local px, py, pw, ph = choicePanelRect(#rows)
  local hit = nil
  for i = 1, #rows do
    if pointInRect(x, y, choiceRowRect(px, py, i)) then hit = i break end
  end
  local confirmed = hasConfirm and pointInRect(x, y, choiceConfirmRect(px, py, pw, ph))

  if kind == "steal" then
    if hit then
      local res = FX.resolve_steal(S, hit)
      UI.pendingChoiceJoker = nil
      resetChoiceUI()
      setStatus((res and res.msg) or "Steal resolved.")
    end
  elseif kind == "acrobat" then
    if UI.acrobatViewHand then
      -- Read-only hand view: only Confirm acts; row clicks are ignored.
      if confirmed then
        local chosen = {}
        for i in pairs(UI.choiceSel) do table.insert(chosen, i) end
        table.sort(chosen)
        local res = FX.resolve_acrobat(S, { deck = deck, hand = hand }, chosen)
        resetChoiceUI()
        if currentSort == "suit" and Rules.sortHandBySuit then Rules.sortHandBySuit(hand)
        elseif Rules.sortHandByRank then Rules.sortHandByRank(hand) end
        setStatus((res and res.msg) or "Acrobat resolved.")
      end
      return
    end
    if hit then
      if UI.choiceSel[hit] then
        UI.choiceSel[hit] = nil
      else
        local count = 0
        for _ in pairs(UI.choiceSel) do count = count + 1 end
        if count < 4 then UI.choiceSel[hit] = true end
      end
    elseif confirmed then
      local chosen = {}
      for i in pairs(UI.choiceSel) do table.insert(chosen, i) end
      table.sort(chosen)
      local res = FX.resolve_acrobat(S, { deck = deck, hand = hand }, chosen)
      resetChoiceUI()
      if currentSort == "suit" and Rules.sortHandBySuit then Rules.sortHandBySuit(hand)
      elseif Rules.sortHandByRank then Rules.sortHandByRank(hand) end
      setStatus((res and res.msg) or "Acrobat resolved.")
    end
  elseif kind == "eye" then
    if hit then
      if UI.eyeFrom == nil then
        UI.eyeFrom = hit
      else
        UI.eyeOrder[UI.eyeFrom], UI.eyeOrder[hit] = UI.eyeOrder[hit], UI.eyeOrder[UI.eyeFrom]
        UI.eyeFrom = nil
      end
    elseif confirmed then
      local res = FX.resolve_eye(S, UI.eyeOrder)
      resetChoiceUI()
      setStatus((res and res.msg) or "Eye resolved.")
    end
  elseif kind == "angel" then
    if hit then
      local res = FX.resolve_angel(S, hit)
      resetChoiceUI()
      setStatus((res and res.msg) or "Angel resolved.")
    end
  elseif kind == "purge" then
    if hit then
      UI.choiceSel[hit] = not UI.choiceSel[hit] or nil
      local picks = {}
      for i in pairs(UI.choiceSel) do table.insert(picks, Rules.CATEGORIES[i]) end
      table.sort(picks)
      S.jokers.purge_selected = picks
      if #picks >= 2 then
        local res = FX.resolve_purge(S)
        resetChoiceUI()
        setStatus((res and res.msg) or "Purge resolved.")
      end
    end
  end
end

-- Escape cancels Acrobat, Eye, and Steal (2.7) — nothing was committed yet.
-- Angel and Purge are commitments and cannot be canceled.
local function choiceOverlayCancel(kind)
  if kind == "acrobat" then
    S.jokers.acrobat_pending = nil
    S.jokers.acrobat_choice_pending = nil
    resetChoiceUI()
    setStatus("Acrobat: canceled.")
  elseif kind == "eye" then
    S.jokers.eye_pending = nil
    S.jokers.eye_choice_pending = nil
    resetChoiceUI()
    setStatus("Eye: canceled.")
  elseif kind == "steal" then
    -- 2.7: revealed jokers return to the pool; the Steal joker returns to hand
    -- and the turn's joker use is undone.
    FX.cancel_steal(S)
    if UI.pendingChoiceJoker then
      table.insert(S.jokers.hand, UI.pendingChoiceJoker)
      UI.pendingChoiceJoker = nil
    end
    S.jokers.used_this_turn = false
    resetChoiceUI()
    setStatus("Steal: canceled.")
  end
end

local function drawCard(card, i)
  local x, y = handPos(i)
  local isSel = selected[i]

  -- suit styling
  local suit = card.suit
  local suitColor = {1,1,1}
  local suitName  = "?"
  if suit == "♠" then suitColor = {0,0,0};   suitName = "Spades"
  elseif suit == "♣" then suitColor = {0,0.5,0}; suitName = "Clubs"
  elseif suit == "♥" then suitColor = {0.8,0,0}; suitName = "Hearts"
  elseif suit == "♦" then suitColor = {0,0.35,0.9}; suitName = "Diamonds"
  end

  -- card background
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("fill", x, y, CARD_W, CARD_H, 8, 8)
  love.graphics.setColor(0,0,0)
  love.graphics.rectangle("line", x, y, CARD_W, CARD_H, 8, 8)

  -- rank + suit big
  love.graphics.setColor(suitColor)
  local displayRank = (card.rank == "T") and "10" or tostring(card.rank)
  if card.temporary then displayRank = displayRank .. " *" end  -- Bicycle temp marker
  love.graphics.printf(displayRank .. " " .. suit, x, y + 8, CARD_W, "center")

  -- small corner suit label
  love.graphics.setColor(0,0,0)
  love.graphics.print(suitName, x + 6, y + CARD_H - 20)

  -- selection overlay
  if isSel then
    love.graphics.setColor(1, 0.9, 0.3, 0.35)
    love.graphics.rectangle("fill", x, y, CARD_W, CARD_H, 8, 8)
    love.graphics.setColor(0.8,0.5,0)
    love.graphics.rectangle("line", x+2, y+2, CARD_W-4, CARD_H-4, 8, 8)
  end

  love.graphics.setColor(1,1,1)
end

-- === Checklist UI ===
local function drawChecklistUI()
  -- anchored at x=400; safe for window width >= 800 (leaves 400px for the right column)
  local x, y = 400, 60
  love.graphics.setColor(1,1,1)
  love.graphics.print("Categories (played at least once):", x, y)
  y = y + 20
  -- Cybernetic (2.10): colour the two hacked hands for THIS turn — yellow for
  -- Double (d), blue for Protected (p), red for Lose (l).
  local cyber = Effects.get(S, "cybernetic")
  local cyber_cond = {}
  if cyber and cyber.schedule then
    local idx = math.max(1, math.min(3, cyber.turn_index or 1))
    local entry = cyber.schedule[idx]
    if entry then
      for i, h in ipairs(entry.hands) do cyber_cond[h] = entry.cond[i] end
    end
  end
  -- 2.8: hands protected by Purge get an asterisk for the effect's duration.
  local purge = Effects.get(S, "purge_immunity")
  local protected_set = {}
  if purge and purge.hands then
    for _, h in ipairs(purge.hands) do protected_set[h] = true end
  end
  for _, name in ipairs(Rules.CATEGORIES) do
    local st = cyber_cond[name]
    if st then
      local tint = (st == "d" and {0.6, 0.6, 0.1, 0.35})
                or (st == "p" and {0.2, 0.35, 0.8, 0.35})
                or (st == "l" and {0.8, 0.15, 0.15, 0.35})
      if tint then
        love.graphics.setColor(tint)
        love.graphics.rectangle("fill", x - 4, y - 2, 220, 22, 4, 4)
      end
    end
    local done = GS.playedHands[name]
    local box = done and "[x] " or "[ ] "
    local star = protected_set[name] and " *" or ""  -- 2.8 Purge marker
    love.graphics.setColor(done and 0.2 or 0, done and 0.6 or 0, done and 0.2 or 0)
    love.graphics.print(box .. name .. star, x, y)
    y = y + 22
  end
  love.graphics.setColor(1,1,1)
  if GS.phase == "WIN" then
    love.graphics.setColor(0.1,0.7,0.2)
    love.graphics.print("🎉 WIN! Press R to restart.", x, y + 6)
    love.graphics.setColor(1,1,1)
  elseif GS.phase == "END" then
    love.graphics.setColor(0.1,0.1,0.7)
    love.graphics.print("End Phase: Next turn starts automatically.", x, y + 6)
    love.graphics.setColor(1,1,1)
  end
end

-- === Joker debug menu (DEBUG: playtesting joker inject) ===
local JMENU_ROW_H = 22
local function jokerMenuPanelRect()
  local ww = love.graphics.getWidth()
  local pw = 300
  local ph = 40 + (#JokerReg.all * JMENU_ROW_H) + 10
  local px = ww - pw - 10
  local py = 10
  return px, py, pw, ph
end

local function drawJokerMenu()
  local px, py, pw, ph = jokerMenuPanelRect()
  love.graphics.setColor(0.12,0.12,0.18,0.95)
  love.graphics.rectangle("fill", px, py, pw, ph, 8, 8)
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("line", px, py, pw, ph, 8, 8)
  love.graphics.print("Joker Menu (debug)", px+10, py+10)
  -- Close button (top-right of panel)
  love.graphics.rectangle("line", px+pw-70, py+8, 60, 22, 4, 4)
  love.graphics.printf("Close", px+pw-70, py+11, 60, "center")
  local ry = py + 40
  for _, def in ipairs(JokerReg.all) do
    love.graphics.print(def.name.."  ("..def.rarity..")", px+14, ry+2)
    ry = ry + JMENU_ROW_H
  end
  love.graphics.setColor(1,1,1)
end

-- Returns true if the click was consumed by the joker menu.
local function jokerMenuClick(x, y)
  local px, py, pw, ph = jokerMenuPanelRect()
  if pointInRect(x, y, {x=px+pw-70, y=py+8, w=60, h=22}) then
    UI.jokerMenuOpen = false
    return true
  end
  local ry = py + 40
  for _, def in ipairs(JokerReg.all) do
    if pointInRect(x, y, {x=px+10, y=ry, w=pw-20, h=JMENU_ROW_H}) then
      -- DEBUG: playtesting joker inject (bypasses the joker hand cap)
      table.insert(S.jokers.hand, def.id)
      UI.jokerMenuOpen = false
      setStatus("DEBUG: added "..def.name.." to joker hand.")
      return true
    end
    ry = ry + JMENU_ROW_H
  end
  return pointInRect(x, y, {x=px, y=py, w=pw, h=ph})
end

-- LOVE callbacks
function love.load()
  love.window.setTitle("Jokers' Gambit - Prototype (Milestone 2)")
  love.math.setRandomSeed(os.time())
  font = love.graphics.newFont(16)
  love.graphics.setFont(font)
  -- 3.5.4: background colour #486478 ≈ (0.282, 0.392, 0.471).
  love.graphics.setBackgroundColor(0.282, 0.392, 0.471)

  -- Show the title screen first; restartGame() runs when the player clicks Start.
  GS.phase = "TITLE"
end

function love.update(dt)
  -- Peacock: a bonus turn scheduled by nextTurn() fires once the current turn
  -- has settled (avoids recursive nextTurn calls).
  if S.jokers and S.jokers.peacock_extra_pending then
    S.jokers.peacock_extra_pending = nil
    nextTurn(true)  -- 2.3: extra turn — counter shows "Extra", no attack
  end
  -- 3.3: a joker was earned but the hand was full and it was not cap-bypass
  -- eligible — inform the player (the draw was not consumed; it stays in pool).
  if S.jokers and S.jokers.last_lost then
    local def = JokerReg.by_id[S.jokers.last_lost]
    setStatus("Joker lost: " .. ((def and def.name) or tostring(S.jokers.last_lost)))
    S.jokers.last_lost = nil
  end

  -- 2.2: Food Joker activates the moment it lands in hand — draw 3 cards into the
  -- hand (the cap is already +3 via effectiveHandMax while Food is in hand). When
  -- Food later leaves the hand the flag resets; the extra cards stay (they simply
  -- don't regenerate, since can_draw returns 0 above the lowered cap).
  if S.jokers and S.jokers.hand then
    local hasFood = Jokers.food_in_hand(S)
    if hasFood and not S.jokers.food_acquired then
      S.jokers.food_acquired = true
      if GS.phase == "MAIN" or GS.phase == "PREP" then
        local drew = drawN(3)
        setStatus("Food Joker acquired: +"..tostring(drew).." cards, hand cap +3.")
      end
    elseif (not hasFood) and S.jokers.food_acquired then
      S.jokers.food_acquired = false
    end
  end

  -- 2.8.1/2.8.2: Golden fired on acquisition (inside gain_joker) — process its
  -- pending streak credit and a possible mid-turn threshold win.
  if S.combat and S.combat.golden_streak_pending then
    local h = S.combat.golden_streak_pending
    S.combat.golden_streak_pending = nil
    noteScoredHand(h)
  end

  -- 1.2: catch a mid-turn threshold/win from ANY scoring source (auto-scores,
  -- streak bonuses, etc.) while a turn is in progress.
  if (GS.phase == "MAIN") and not (UI and UI.overlay) then
    checkThresholdWin()
  end
end

function love.mousepressed(x, y, b)
  if b ~= 1 then return end

  if GS.phase == "TITLE" then
    if pointInRect(x, y, BTN_START) then restartGame() end
    return
  end

  -- M4: while a joker choice overlay is pending, the click belongs to it
  -- entirely — never falls through to card/joker selection.
  local pendingKind = pendingChoiceKind()
  if pendingKind then
    choiceOverlayClick(pendingKind, x, y)
    return
  end

  if UI and UI.overlay then
    if UI.overlay.kind == "win" then
      if pointInRect(x, y, BTN_ENDLESS) then
        GS.endless = true
        UI.overlay = nil
        advanceThreshold()
      elseif pointInRect(x, y, BTN_NEXT_T) then
        UI.overlay = nil
        restartGame()
      end
    elseif UI.overlay.kind == "loss" then
      if pointInRect(x, y, BTN_NEXT_T) then
        UI.overlay = nil
        restartGame()
      end
    elseif pointInRect(x, y, BTN_NEXT_T) then
      confirmOverlay()
    end
    return
  end

  -- Joker debug menu sits above everything except the win/threshold overlay
  if UI.jokerMenuOpen then
    if jokerMenuClick(x, y) then return end
    UI.jokerMenuOpen = false
    return
  end

  -- Buttons first so clicks don't toggle a card underneath them
  if pointInRect(x, y, BTN_RESTART) then
    restartGame()
    setStatus("Restarted.")
    return
  end

  if pointInRect(x, y, BTN_RANK) then
    currentSort = "rank"
    if Rules and Rules.sortHandByRank then
      Rules.sortHandByRank(hand)
    end
    selected = {}
    setStatus("Sorted by rank (A-high left).")
    return
  elseif pointInRect(x, y, BTN_SUIT) then
    currentSort = "suit"
    if Rules and Rules.sortHandBySuit then
      Rules.sortHandBySuit(hand)
    end
    selected = {}
    setStatus("Sorted by suit (♠ ♥ ♦ ♣; A-high within).")
    return
  end

  if pointInRect(x, y, BTN_SAVE) then
    saveToSlot(SAVE_SLOT)
    return
  elseif pointInRect(x, y, BTN_LOAD) then
    loadFromSlot(SAVE_SLOT)
    return
  elseif pointInRect(x, y, BTN_SKIP) then
    -- DEBUG: playtesting skip — meet the current threshold target instantly.
    if GS.phase == "MAIN" and S.meta then
      S.meta.score = Scoring.target_for(S.meta.threshold) or S.meta.score
      for _, name in ipairs(Rules.CATEGORIES) do GS.playedHands[name] = true end
      setStatus("DEBUG: skipped to threshold target.")
      enterEndPhase()
    end
    return
  elseif pointInRect(x, y, BTN_JOKER_MENU) then
    -- DEBUG: playtesting joker inject
    UI.jokerMenuOpen = not UI.jokerMenuOpen
    return
  end

  -- (Old WIN-phase input lock removed: the win overlay now gates input globally
  -- via the UI.overlay check above.)
  if GS.phase == "END" then
    setStatus("Turn advanced automatically.")
    return
  end

  -- 3.2: card and joker selection are mutually exclusive — selecting one clears
  -- the other so both can never be active simultaneously.
  local ji = jokerAtPosition(x, y)
  if ji then
    selectedJoker = (selectedJoker == ji) and nil or ji
    if selectedJoker then selected = {} end
    return
  end

  local i = cardAtPosition(x, y)
  if i then
    selected[i] = not selected[i]
    selectedJoker = nil
  end
end

function love.keypressed(key)
  -- F11 fullscreen toggle: kept above ALL guards (overlay + GS.phase) so it always
  -- fires, in every phase (MAIN/WIN/END/THRESHOLD) and even while an overlay is up.
  if key == "f11" then
    local fs = love.window.getFullscreen()
    love.window.setFullscreen(not fs)
    return
  end

  if GS.phase == "TITLE" then
    if key == "return" or key == "kpenter" then restartGame() end
    return
  end

  -- M4: block all key actions while a joker choice overlay is pending.
  -- Escape cancels where it makes sense (Acrobat, Eye).
  local pendingKind = pendingChoiceKind()
  if pendingKind then
    if key == "escape" then
      choiceOverlayCancel(pendingKind)
    elseif key == "h" and pendingKind == "acrobat" then
      UI.acrobatViewHand = not UI.acrobatViewHand  -- 2.5: toggle deck/hand view
    end
    return
  end

  if UI and UI.overlay then
    -- Win overlay: Enter defaults to Endless Mode (via confirmOverlay); R restarts.
    -- Loss overlay: Enter or R restarts the run.
    if key == "return" or key == "kpenter" then
      if UI.overlay.kind == "loss" then
        UI.overlay = nil
        restartGame()
      else
        confirmOverlay()
      end
    elseif key == "r" and (UI.overlay.kind == "win" or UI.overlay.kind == "loss") then
      UI.overlay = nil
      restartGame()
    end
    return
  end
  if key == "return" or key == "kpenter" then
    if GS.phase == "PREP" then
      setStatus("Setup phase — discard only.")
      return
    end
    if GS.phase == "END" then
      setStatus("Turn advanced automatically.")
      return
    end
    -- PLAY (1–5, or 6 cards as two three-of-a-kinds while Cute Joker is active)
    local idxs = selectedIndices()
    -- 2.4: a 6-card play is only accepted when Cute Joker is active AND the cards
    -- form two valid, separate three-of-a-kinds (a 6-of-a-kind is rejected).
    local cuteSix = (#idxs == 6) and S.jokers and S.jokers.cute_active
                    and Eval.is_two_trips(cardsFromIndices(idxs))
    if (#idxs >= 1 and #idxs <= 5) or cuteSix then
      local chosen = cardsFromIndices(idxs)
      local cat
      if cuteSix then
        cat = "Three of a Kind"
      else
        if #idxs == 6 then
          setStatus("6 cards only play as two three-of-a-kinds (Cute Joker).")
          return
        end
        cat = Eval.exact_category(chosen)
      end
      if not cat then
        setStatus("Invalid selection for a minimal hand.")
        return
      end
      -- remove selected from hand
      local toPlayed = {}
      table.sort(idxs, function(a,b) return a>b end)
      for _, i in ipairs(idxs) do
        table.insert(toPlayed, hand[i])
        table.remove(hand, i)
      end

      -- Bicycle: temporary cards that get played become permanent deck cards
      -- (added to the main deck) rather than going to the Played pile.
      local toCommit = {}
      for _, c in ipairs(toPlayed) do
        if c.temporary then
          c.temporary = nil
          if deck and deck.cards then
            table.insert(deck.cards, c)
            -- 3.5.2: a Bicycle temp card that is played becomes permanent — the
            -- run's total card count grows.
            if deck.addPermanentTotal then deck:addPermanentTotal(1) end
          end
        else
          table.insert(toCommit, c)
        end
      end

      -- played → Played pile (permanent)
      if deck and deck.commitPlayed then
        deck:commitPlayed(toCommit)
      else
        if deck and deck.discardCards then deck:discardCards(toCommit) end
      end
      selected = {}

      -- top-up same count (respect HAND_MAX)
      local need = can_draw(#toPlayed)
      if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
      local drawn = deck:drawNoReshuffle(need)
      for i = 1, #drawn do table.insert(hand, drawn[i]) end
      local got = #drawn
            if currentSort == "suit" and Rules and Rules.sortHandBySuit then Rules.sortHandBySuit(hand) elseif Rules and Rules.sortHandByRank then Rules.sortHandByRank(hand) end
      maybeTriggerDepletion()  -- 3.1: out of cards to refill → Game Over
      if GS.phase == "LOSS" then
        GS.playedHands[cat] = true
        return  -- run is over; do not advance the turn
      end

      -- Mark the category & note it for attack blocking + streak.
      GS.playedHands[cat] = true
      if Attacks then Attacks.note_played_this_turn(S, cat) end
      noteScoredHand(cat)                       -- 1.1: attack-match streak

      -- 1.3: attack resolves (penalty) FIRST, then the hand's award is credited.
      local atkMsg = resolveAttackMsg()

      local gained = 0
      if Scoring then
        gained = Scoring.apply_award(S, cat, toPlayed)
        -- 2.4: Cute 6-card play is two three-of-a-kinds → score it twice.
        if cuteSix then gained = gained + Scoring.apply_award(S, cat, toPlayed) end
        -- 2.8.3: Golden auto-scored this hand earlier this turn → manual copy doubles.
        if S.combat and S.combat.golden_double == cat then
          gained = gained + Scoring.apply_award(S, cat, toPlayed)
          S.combat.golden_double = nil
        end
      end
      if cuteSix and S.jokers then S.jokers.cute_active = nil end

      local label = cuteSix and "Cute: two Three of a Kinds" or ("Played "..cat)
      local msg = label.."  |  +"..tostring(gained).." pts  |  Drew "..tostring(got)
      if atkMsg ~= "" then msg = msg.."   ||   "..atkMsg end
      setStatus(msg)

      -- 1.2: mid-turn threshold/win check, then advance if play continues.
      if checkThresholdWin() then return end
      nextTurn()
    else
      setStatus("Select 1–5 cards to play.")
    end

  elseif key == "x" then
    if GS.phase == "END" then
      setStatus("Turn advanced automatically.")
      return
    end
    -- DISCARD (1–5) and redraw same amount
    discardSelected()

  elseif key == "s" then
    -- PREP: skip remaining setup turns for a scaled bonus
    if GS.phase ~= "PREP" then return end
    local skipped = GS.prep_turns_remaining
    if skipped <= 0 then endPrepPhase() return end
    local bonus = Scoring.prep_skip_bonus(skipped, S.meta.threshold or 1)
    S.meta.score = (S.meta.score or 0) + bonus
    endPrepPhase()
    setStatus("Skipped setup. +" .. bonus .. " pts bonus!")

  elseif key == "r" then
    restartGame()
    setStatus("Restarted.")

  elseif key == "d" then
    -- DEBUG draw 1 (does NOT end the turn)
    local need = can_draw(1)
    if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
    local drawn = deck:drawNoReshuffle(need)
  for i = 1, #drawn do table.insert(hand, drawn[i]) end
  local drew = #drawn
  if currentSort == "suit" and Rules and Rules.sortHandBySuit then Rules.sortHandBySuit(hand) elseif Rules and Rules.sortHandByRank then Rules.sortHandByRank(hand) end

    if drew > 0 then      setStatus("Drew "..tostring(drew)..".")
    else
      setStatus("No draw (deck empty or at max hand).")
    end

  elseif key == "t" then
    -- DEBUG top-up to HAND_START (does NOT end the turn)
    local added = 0
    while #hand < (HAND_START or 10) do
      local got = drawN(can_draw(1))
      if (got or 0) == 0 then break end
      added = added + got
    end
    if added > 0 then      setStatus("Topped up +"..tostring(added)..".")
    else
      setStatus("No top-up needed.")
    end

    elseif key == "j" then
    if GS.phase == "PREP" then
      setStatus("Setup phase — discard only.")
      return
    end
    if GS.phase == "END" then
      setStatus("Turn advanced automatically.")
      return
    end
    local idx = selectedJoker or 1
    if not S.jokers or #S.jokers.hand == 0 then
      setStatus("No joker ready.")
    elseif S.jokers.used_this_turn then
      setStatus("Joker already used this turn.")
    else
      local jid = S.jokers.hand[idx]
      local ctx = buildJokerCtx()
      -- 2.13: Fibonacci uses its acquisition-time count (matched by ordinal).
      if jid == "fibonacci" then
        local ordinal = 0
        for i = 1, idx do if S.jokers.hand[i] == "fibonacci" then ordinal = ordinal + 1 end end
        S.jokers.fib_counts = S.jokers.fib_counts or {}
        ctx.fib_count = table.remove(S.jokers.fib_counts, ordinal) or 0
      end
      local res = Jokers.use(S, idx, ctx)
      selectedJoker = nil
      -- 2.7: remember the joker that opened a choice overlay so Steal can be
      -- cancelled (joker returns to hand, the use is undone).
      if res and res.pending then UI.pendingChoiceJoker = jid end
      if res and res.msg then
        setStatus(res.msg)
      else
        setStatus("Used joker.")
      end
      -- 2.2: Food Joker — on use the +3 hand-cap bonus is removed (cards already
      -- in hand stay). The bonus reverts automatically because Food has left the
      -- hand (effectiveHandMax checks hand contents); clear the acquire flag.
      if jid == "food" and S.jokers then S.jokers.food_acquired = false end
      -- 2.8.2 / 2.9: a joker auto-score (Golden, The Flush) counts toward the
      -- attack-match streak and can complete the threshold mid-turn.
      if res and res.auto_score then
        noteScoredHand(res.auto_score)
        checkThresholdWin()  -- 1.2 / 2.8.1: may set the win/threshold overlay
      end
    end

  elseif key == "a" then
    -- Architect: move selected cards from hand onto the building site
    if GS.phase == "MAIN" and S.jokers and S.jokers.architect_active then
      local idxs = selectedIndices()
      if #idxs == 0 then
        setStatus("Architect: select cards to add to the site.")
        return
      end
      S.jokers.architect_site = S.jokers.architect_site or {}
      -- 2.11: building site maximum is 5 cards.
      local room = 5 - #S.jokers.architect_site
      if room <= 0 then
        setStatus("Architect: site is full (max 5 cards).")
        return
      end
      table.sort(idxs, function(a,b) return a>b end)
      local moved = 0
      for _, i in ipairs(idxs) do
        if moved >= room then break end
        table.insert(S.jokers.architect_site, hand[i])
        table.remove(hand, i)
        moved = moved + 1
      end
      selected = {}
      -- draw replacements (same logic as discard/redraw)
      local need = can_draw(moved)
      if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
      local drawn = deck:drawNoReshuffle(need)
      for i = 1, #drawn do table.insert(hand, drawn[i]) end
      if currentSort == "suit" and Rules.sortHandBySuit then Rules.sortHandBySuit(hand)
      elseif Rules.sortHandByRank then Rules.sortHandByRank(hand) end
      setStatus("Architect: "..#S.jokers.architect_site.." card(s) on site.")
    end

  elseif key == "p" then
    -- Architect: play the building site as a bonus hand (does NOT end the turn)
    if GS.phase == "MAIN" and S.jokers and S.jokers.architect_active
       and S.jokers.architect_site and #S.jokers.architect_site >= 1 then
      local site = S.jokers.architect_site
      -- 2.11: evaluate the HIGHEST valid poker category among the site cards
      -- (rank + suit; a flush beats a contained pair).
      local cat = Eval.best_category(site)
      if not cat then
        setStatus("Architect: site is not a valid hand yet.")
        return
      end
      local gained = Scoring.apply_award(S, cat, site)
      GS.playedHands[cat] = true
      if Attacks then Attacks.note_played_this_turn(S, cat) end
      noteScoredHand(cat)
      if deck and deck.commitPlayed then deck:commitPlayed(site) end
      -- 2.3: the building site is a one-time action — clear the site AND close the
      -- Architect entirely after playing it.
      S.jokers.architect_site = {}
      S.jokers.architect_active = false
      setStatus("Architect: played "..cat.." from building site.  +"..tostring(gained).." pts")
      checkThresholdWin()  -- 1.2: a site play can complete the threshold
    end

  elseif key == "c" then
    -- 3.2: CLEAR both card selection and the active joker selection.
    selected = {}
    selectedJoker = nil
    setStatus("Selection cleared.")
  end

  if key == "f5" then
    saveToSlot(SAVE_SLOT)
    return
  elseif key == "f9" then
    loadFromSlot(SAVE_SLOT)
    return
  end
end

function love.draw()
  -- Title screen: draw only the game name and the Start button.
  if GS.phase == "TITLE" then
    local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0.08,0.08,0.14)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    love.graphics.setColor(1,1,1)
    love.graphics.printf("Jokers' Gambit", 0, math.floor(wh*0.40), ww, "center")
    BTN_START.x = math.floor((ww - BTN_START.w)/2)
    BTN_START.y = math.floor(wh*0.40) + 60
    drawButton(BTN_START)
    return
  end

   if statusMsg and statusMsg ~= "" then
    local sx, sy = 40, 10
    local sw = math.min(font:getWidth(statusMsg) + 20, love.graphics.getWidth() - 80)
    local sh = 28
    love.graphics.setColor(0,0,0,0.45)
    love.graphics.rectangle("fill", sx, sy, sw, sh, 6, 6)
    love.graphics.setColor(1,1,1,1)
    love.graphics.print(statusMsg, sx + 10, sy + 6)
  end

  love.graphics.setColor(1,1,1)
  local deckCount    = (deck and deck.cards)   and #deck.cards   or 0
  local discardCount = (deck and deck.discard) and #deck.discard or 0
  local playedCount  = (deck and deck.played)  and #deck.played  or 0
  -- ── HUD line audit (worst case: all optional lines visible) ───────────────
  -- Layout budget: HUD must finish above the button row (>=210) and well above
  -- the joker row (JOKER_Y=250). Worst-case final hud_y below is ~190, leaving a
  -- safe gap. If lines are ever added past y=220, tighten the +20 increments to +18.
  local hud_y = 60
  -- HUD line 1: ~y=60  (Deck N / Total ever existed, Discard / Played counts)
  local deckTotal = (deck and deck.total_cards) or (deckCount + discardCount + playedCount)
  love.graphics.print("Deck: "..deckCount.." / "..deckTotal.."  Discard: "..discardCount.."  Played: "..playedCount, 40, hud_y)
  hud_y = hud_y + 20
  -- HUD line 2: ~y=80  (Score / threshold target) — only when S.meta exists
  if S and S.meta then
    local t = (S.meta and S.meta.threshold) or 1
    local tgt = Scoring and Scoring.target_for and Scoring.target_for(t) or nil
    love.graphics.print("Score: "..tostring(S.meta.score).." / "..tostring(tgt or "—").."   (T"..tostring(t)..")", 40, hud_y)
    hud_y = hud_y + 20
  end
  -- HUD line 3: ~y=100 (Current attack) — only when an attack is announced
  if S and S.combat and S.combat.current_attack then
    love.graphics.print("Attack → "..S.combat.current_attack, 40, hud_y)
    hud_y = hud_y + 20
  end
  -- HUD: attack-match streak (1.1) — every 3 in a row grants a joker.
  local streak = (S and S.meta and S.meta.streak) or 0
  if streak > 0 then
    love.graphics.print("Streak: "..tostring(streak).."  (next joker at "..tostring((math.floor(streak/3)+1)*3)..")", 40, hud_y)
    hud_y = hud_y + 20
  end
  -- HUD line 4: ~y=120 (Hand size / max)
  love.graphics.print("Hand size: "..tostring(#hand).." (max "..effectiveHandMax()..")", 40, hud_y)
  hud_y = hud_y + 30
  -- HUD line 5: ~y=150 (Jokers in hand vs base cap of 5; Food Joker may extend at runtime)
  love.graphics.print("Jokers: " .. tostring(#(S.jokers and S.jokers.hand or {})) .. "/5", 40, hud_y)
  hud_y = hud_y + 20
  -- HUD line 6: ~y=170 (Turn / phase — single shared line; Endless tag when active)
  -- 2.3: an extra turn shows "Extra" instead of a number.
  local turnLabel = GS.extra_turn and "Extra" or tostring(GS.turn or 1)
  love.graphics.print("Turn: "..turnLabel.."   Phase: "..GS.phase..(GS.endless and "   [Endless]" or ""), 40, hud_y)
  hud_y = hud_y + 20
  -- HUD line 7: ~y=190 (PREP indicator — visible during setup turns only)
  -- 3.5.3: keep the yellow setup text inside the left column (width 340) so it
  -- never overlaps the checklist entries (e.g. "[ ] Straight") anchored at x=400.
  if GS.phase == "PREP" then
    love.graphics.setColor(0.9, 0.8, 0.3)
    love.graphics.printf("⚙ SETUP PHASE — " .. GS.prep_turns_remaining .. " turn(s) left  [S = Skip for bonus]", 40, hud_y, 340, "left")
    hud_y = hud_y + 40
    love.graphics.setColor(1, 1, 1)
  end

  -- Buttons (fixed in the red strip at y=344; see BTN_* definitions above)
  drawButton(BTN_RESTART)
  drawButton(BTN_RANK)
  drawButton(BTN_SUIT)
  drawButton(BTN_SAVE)
  drawButton(BTN_LOAD)
  drawButton(BTN_SKIP)        -- DEBUG: playtesting skip
  drawButton(BTN_JOKER_MENU)  -- DEBUG: playtesting joker inject
-- Checklist UI (2.2) + win / end banners
  drawChecklistUI()

  -- Jokers row
  if S.jokers and S.jokers.hand and #S.jokers.hand > 0 then
    love.graphics.print("Jokers:", JOKER_X, JOKER_Y - 20)
    for i, jid in ipairs(S.jokers.hand) do
      drawJoker(jid, i)
    end
  end

  -- M4: active-effect labels (right column, under the checklist)
  local fx_y = 285
  if S.jokers and S.jokers.architect_active then
    local site = S.jokers.architect_site or {}
    local labels = {}
    for _, c in ipairs(site) do
      local r = (c.rank == "T") and "10" or tostring(c.rank)
      table.insert(labels, r..c.suit)
    end
    love.graphics.setColor(0.85, 0.85, 0.6)
    love.graphics.print("🏗 Site: "..(#site > 0 and table.concat(labels, " ") or "(empty)")
      .."   [A] add selected cards  [P] play site", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  if Effects.has(S, "attack_shield") then
    love.graphics.setColor(0.95, 0.75, 0.2)
    love.graphics.print("🛡 Anti-Joker: attacks shielded", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  if S.jokers and S.jokers.peacock_active then
    love.graphics.setColor(0.2, 0.8, 0.75)
    love.graphics.print("🦚 Peacock: extra turn every 5 turns", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  -- 2.2 / 2.8: active multi-turn joker effects (name + remaining turns).
  -- Helper: remaining turns for the first active effect entry with this id.
  local function effectTurns(id)
    for _, e in ipairs(S.active_effects or {}) do
      if e.id == id then return e.turns_remaining end
    end
    return nil
  end
  -- Cybernetic (running effect)
  local cyberT = effectTurns("cybernetic")
  if cyberT then
    love.graphics.setColor(0.7, 0.7, 0.9)
    love.graphics.print("🤖 Cybernetic: hacked hands ("..cyberT.." turn(s))", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  -- Purge (2.8) — show remaining turns and the two protected hands
  local purgeT = effectTurns("purge_immunity")
  if purgeT then
    local p = Effects.get(S, "purge_immunity")
    local label = (p and p.hands and table.concat(p.hands, " & ")) or ""
    love.graphics.setColor(0.6, 0.85, 0.6)
    love.graphics.print("🧪 Purge: "..label.." protected ("..purgeT.." turn(s))", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  -- Galaxy (score multiplier) — runs for the rest of the threshold
  if Effects.has(S, "score_multiplier") then
    local p = Effects.get(S, "score_multiplier")
    love.graphics.setColor(0.8, 0.7, 0.95)
    love.graphics.print("🌌 Galaxy: all hands ×"..tostring((p and p.mult) or 1.5).." this threshold", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  -- Four of Clubs (2.5) — shown active only AFTER it has been used.
  if S.jokers and S.jokers.fourofclubs_active then
    love.graphics.setColor(0.6, 0.8, 0.6)
    love.graphics.print("♣ Four of Clubs: Club/4 hands score extra", 400, fx_y)
    love.graphics.setColor(1, 1, 1)
    fx_y = fx_y + 18
  end
  -- Steal (2.1) — jokers disabled for this threshold, greyed in the corner.
  if S.jokers and S.jokers.steal_disabled and #S.jokers.steal_disabled > 0 then
    for _, jid in ipairs(S.jokers.steal_disabled) do
      local def = JokerReg.by_id[jid]
      love.graphics.setColor(0.5, 0.5, 0.5)
      love.graphics.print("✖ "..((def and def.name) or jid).." (disabled this threshold)", 400, fx_y)
      love.graphics.setColor(1, 1, 1)
      fx_y = fx_y + 18
    end
  end


  -- Hand
  for i, c in ipairs(hand) do
    drawCard(c, i)
  end

  -- Joker debug menu (on top of everything except the win/threshold overlay)
  if UI.jokerMenuOpen then
    drawJokerMenu()
  end

  -- M4: joker choice overlay (Steal/Acrobat/Eye/Angel/Purge) — on top of
  -- everything while a choice is pending.
  local pendingKind = pendingChoiceKind()
  if pendingKind then
    drawChoiceOverlay(pendingKind)
  end

  -- Threshold/Win overlay (draw last so it appears above other elements)
  if UI and UI.overlay then
    local msg = UI.overlay.message or "Threshold completed"
    local ww, wh = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0,0,0,0.55)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    local pw, ph = math.min(420, ww-80), 140
    local px = math.floor((ww - pw)/2)
    local py = math.floor((wh - ph)/2)
    love.graphics.setColor(0.95,0.98,1)
    love.graphics.rectangle("fill", px, py, pw, ph, 10, 10)
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle("line", px, py, pw, ph, 10, 10)
    love.graphics.printf(msg, px+20, py+20, pw-40, "center")
    if UI.overlay.kind == "win" then
      -- Two buttons side by side: Endless Mode (Enter) and Restart (R)
      BTN_ENDLESS.x = px + math.floor(pw/2) - BTN_ENDLESS.w - 10
      BTN_ENDLESS.y = py + ph - 50
      BTN_NEXT_T.x = px + math.floor(pw/2) + 10
      BTN_NEXT_T.y = py + ph - 50
      BTN_NEXT_T.label = "Restart"
      drawButton(BTN_ENDLESS)
      drawButton(BTN_NEXT_T)
    else
      BTN_NEXT_T.x = px + math.floor((pw-140)/2)
      BTN_NEXT_T.y = py + ph - 50
      BTN_NEXT_T.label = (UI.overlay.kind == "loss") and "Restart" or "Next"
      drawButton(BTN_NEXT_T)
    end
    love.graphics.setColor(1,1,1)
  end
end
