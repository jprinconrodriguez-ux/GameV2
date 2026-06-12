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

-- === CONSTANTS (safe defaults) ===
local HAND_START = HAND_START or 10   -- starting hand size
local HAND_MAX   = HAND_MAX   or 20   -- absolute cap
local NUM_DECKS  = NUM_DECKS  or 2    -- SP default; MP later = players + 1

-- === STATE ===
local deck
local hand = {}          -- make sure 'hand' exists before helpers use it
local selected = {}
local selectedJoker = nil
local lastResult = nil
local statusMsg = ""
local font

-- persistent sort mode in-session
local currentSort = "rank"

-- Buttons
local UI = { overlay = nil }

-- NOTE: the .y of these five buttons is recomputed every frame in love.draw()
-- (see BTN_Y = math.max(210, hud_y + 8)); the 210 below is just a safe default
-- so they never collide with the joker row (JOKER_Y=250) before the first draw.
local BTN_RESTART = {x=40,  y=210, w=100, h=30, label="Restart"}
local BTN_RANK    = {x=160, y=210, w=110, h=30, label="Sort: Rank"}
local BTN_SUIT    = {x=280, y=210, w=110, h=30, label="Sort: Suit"}
local BTN_SAVE   = {x=400, y=210, w=90,  h=30, label="Save"}
local BTN_LOAD   = {x=500, y=210, w=90,  h=30, label="Load"}
local BTN_NEXT_T = {x=0, y=0, w=140, h=36, label="Next"}  -- overlay button; positioned relative to panel, untouched

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

-- Forward declaration
local nextTurn

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

local function can_draw(n)
  local hand_max = HAND_MAX or 20
  local free = hand_max - getHandSize()
  if free < 0 then free = 0 end
  if n == nil or n < 0 then n = 0 end
  if free < n then return free else return n end
end

local function drawN(n)
  local drawnCount = 0
  if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
  for _ = 1, (n or 0) do
    if getHandSize() >= (HAND_MAX or 20) then break end
    local d = deck:draw(1)
    if #d == 0 then break end
    table.insert(hand, d[1])
    drawnCount = drawnCount + 1
  end
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

local function drawUpTo(target)
  target = math.min(target or HAND_START, HAND_MAX)
  local total = 0
  while getHandSize() < target do
    if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
    local d = deck:draw(1)
    if #d == 0 then break end
    table.insert(hand, d[1])
    total = total + 1
  end
  if total > 0 then
    if currentSort == "suit" and Rules and Rules.sortHandBySuit then
      Rules.sortHandBySuit(hand)
    elseif Rules and Rules.sortHandByRank then
      Rules.sortHandByRank(hand)
    end
  end
  return total
end


-- Threshold advance: bump threshold (cap 5), reset score, keep hand/jokers, recycle piles,
-- announce next attack and start next turn.
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

local function advanceThreshold()
  if not S.meta then return end
  local cur = S.meta.threshold or 1
  local nextT = math.min(5, cur + 1)
  S.meta.threshold = nextT
  if Scoring and Scoring.reset_for_next_threshold then Scoring.reset_for_next_threshold(S) end
  mergePilesIntoDeck()
  UI.overlay = nil
  GS.phase = "MAIN"
  nextTurn()
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

local function drawJoker(jid, i)
  local x, y = jokerPos(i)
  local def = JokerReg.by_id[jid]
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("fill", x, y, JOKER_W, JOKER_H, 8, 8)
  love.graphics.setColor(0,0,0)
  love.graphics.rectangle("line", x, y, JOKER_W, JOKER_H, 8, 8)
  local label = def and def.name or tostring(jid)
  love.graphics.printf(label, x+4, y + JOKER_H/2 - 8, JOKER_W-8, "center")
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

-- === CHECKLIST HELPER ===
local function isAllMarked()
  for _, name in ipairs(Rules.CATEGORIES) do
    if not GS.playedHands[name] then return false end
  end
  return true
end

-- === TURN HELPERS ===

local function enterEndPhase()
  -- Resolve attack then auto-advance
  if Attacks and Scoring then
    local res = Attacks.resolve(S, Scoring)
    if res and res.penalized then
      setStatus("Attack: "..res.target.." ⚠  -" .. tostring(res.penalty) .. " pts")
    elseif res and res.canceled then
      setStatus("Attack canceled.")
    elseif res and res.protected then
      setStatus("Attack avoided by playing "..res.target..".")
    end
  end
  nextTurn()
end

nextTurn = function()
  GS.phase = "MAIN"
  GS.turn = (GS.turn or 1) + 1
  setStatus("Your turn.")
  if Scoring and Scoring.on_turn_advanced then Scoring.on_turn_advanced(S) end
    GS.limits = GS.limits or {}
  GS.limits.discard_used = false
  selected = {}  -- ensure clean state
  selectedJoker = nil
  if Scoring and not S.meta then Scoring.init(S) end
  if Attacks then Attacks.announce(S, love.math) end
  if Jokers then Jokers.start_turn(S) end
end

-- Discard (up to 5) and redraw same amount (respect HAND_MAX)
local function discardSelected()
  if GS.limits and GS.limits.discard_used then
    setStatus("Discard already used this turn.")
    return
  end
  if GS.phase == "WIN" then
    setStatus("Game won—press R to restart.")
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
  setStatus("Discarded "..#toDiscard..", drew "..tostring(drew)..".")
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
  lastResult = nil
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
local function restartGame()
  deck = Deck.new(NUM_DECKS)
  S.meta = nil
  S.jokers = nil
  selectedJoker = nil
  if Scoring then Scoring.init(S) end
  if Jokers then
    Jokers.init(S, love.math)
    Jokers.start_turn(S)
  end
  if Attacks then Attacks.announce(S, love.math) end
  hand = {}
  selected = {}
  lastResult = nil
  GS:reset()
  setStatus("")
  drawUpTo(HAND_START)
end

-- Layout: wrap cards to new rows
local function handPos(i)
  local ww, _ = love.graphics.getDimensions()
  local perRow = math.max(1, math.floor((ww - HAND_X*2 + GAP) / (CARD_W + GAP)))
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
  for _, name in ipairs(Rules.CATEGORIES) do
    local done = GS.playedHands[name]
    local box = done and "[x] " or "[ ] "
    love.graphics.setColor(done and 0.2 or 0, done and 0.6 or 0, done and 0.2 or 0)
    love.graphics.print(box .. name, x, y)
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

-- LOVE callbacks
function love.load()
  love.window.setTitle("Jokers' Gambit - Prototype (Milestone 2)")
  love.math.setRandomSeed(os.time())
  font = love.graphics.newFont(16)
  love.graphics.setFont(font)

  restartGame()
end

function love.mousepressed(x, y, b)
  if b ~= 1 then return end
  if UI and UI.overlay then
    if pointInRect(x, y, BTN_NEXT_T) then advanceThreshold() end
    return
  end

  -- Buttons first so clicks don't toggle a card underneath them
  if pointInRect(x, y, BTN_RESTART) then
    restartGame()
    setStatus("Restarted.")
    return
  end

  if GS.phase ~= "WIN" then
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
  end

  if pointInRect(x, y, BTN_SAVE) then
    saveToSlot(SAVE_SLOT)
    return
  elseif pointInRect(x, y, BTN_LOAD) then
    loadFromSlot(SAVE_SLOT)
    return
  end

  if GS.phase == "WIN" then
    -- lock inputs except Restart
    return
  end
  if GS.phase == "END" then
    setStatus("Turn advanced automatically.")
    return
  end

  local ji = jokerAtPosition(x, y)
  if ji then
    selectedJoker = (selectedJoker == ji) and nil or ji
    return
  end

  local i = cardAtPosition(x, y)
  if i then
    selected[i] = not selected[i]
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

  if UI and UI.overlay then
    if key == "return" or key == "kpenter" then advanceThreshold() end
    return
  end
  if key == "return" or key == "kpenter" then
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
      return
    end
    if GS.phase == "END" then
      setStatus("Turn advanced automatically.")
      return
    end
    -- PLAY (1–5)
    local idxs = selectedIndices()
    if #idxs >= 1 and #idxs <= 5 then
      local chosen = cardsFromIndices(idxs)
      local cat = Eval.exact_category(chosen)
      if not cat then
        setStatus("Invalid selection for a minimal hand.")
        return
      end
      lastResult = { exact = cat }

      -- remove selected from hand
      local toPlayed = {}
      table.sort(idxs, function(a,b) return a>b end)
      for _, i in ipairs(idxs) do
        table.insert(toPlayed, hand[i])
        table.remove(hand, i)
      end

      -- played → Played pile (permanent)
      if deck and deck.commitPlayed then
        deck:commitPlayed(toPlayed)
      else
        if deck and deck.discardCards then deck:discardCards(toPlayed) end
      end
      selected = {}

      -- top-up same count (respect HAND_MAX)
      local need = can_draw(#toPlayed)
      if deck and deck.cards and #deck.cards == 0 then reshuffle_discard_into_deck() end
      local drawn = deck:drawNoReshuffle(need)
      for i = 1, #drawn do table.insert(hand, drawn[i]) end
      local got = #drawn
            if currentSort == "suit" and Rules and Rules.sortHandBySuit then Rules.sortHandBySuit(hand) elseif Rules and Rules.sortHandByRank then Rules.sortHandByRank(hand) end

      -- Mark the category & count a move
      GS.playedHands[cat] = true
      -- Award score & mark for attack resolution
      local msg = "Played: "..cat.."  |  Drew "..tostring(got)
      if Scoring then
        local gained = Scoring.apply_award(S, cat)
        msg = "Played: "..cat.."  |  +"..tostring(gained).." pts  |  Drew "..tostring(got)
      end
      setStatus(msg)
      if Attacks then Attacks.note_played_this_turn(S, cat) end
      if Jokers then Jokers.on_hand_played(S, love.math) end

      -- Threshold completion check (T1–T3)
      -- Win requires BOTH reaching the score target AND completing all 8 categories (T3 only).
      local scoreReached = Scoring and Scoring.is_threshold_complete and Scoring.is_threshold_complete(S)
      local isT3Win = scoreReached and (S.meta.threshold == 3) and isAllMarked()
      local completed = scoreReached and ((S.meta.threshold ~= 3) or isT3Win)
      if isT3Win then
        GS.phase = "THRESHOLD"
        UI.overlay = { kind = "win", message = "You Win!" }
      elseif completed then
        GS.phase = "THRESHOLD"
        UI.overlay = { kind = "threshold", message = "Threshold completed" }
      else
        enterEndPhase()
      end
    else
      setStatus("Select 1–5 cards to play.")
    end

  elseif key == "x" then
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
      return
    end
    if GS.phase == "END" then
      setStatus("Turn advanced automatically.")
      return
    end
    -- DISCARD (1–5) and redraw same amount
    discardSelected()

  elseif key == "r" then
    restartGame()
    setStatus("Restarted.")

  elseif key == "d" then
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
      return
    end
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
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
      return
    end
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
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
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
      local ctx = {
        source         = "key",
        rng            = love.math,
        deck           = deck,
        hand           = hand,
        playedHands    = GS.playedHands,
        gain_from_pool = function(n) Jokers.gain_from_pool(S, n, love.math) end,
      }
      local res = Jokers.use(S, idx, ctx)
      selectedJoker = nil
      if res and res.msg then
        setStatus(res.msg)
      else
        setStatus("Used joker.")
      end
    end

  elseif key == "c" then
    if GS.phase == "WIN" then
      setStatus("Game won—press R to restart.")
      return
    end
    -- CLEAR selection
    selected = {}
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
  -- HUD line 1: ~y=60  (Deck / Discard / Played counts)
  love.graphics.print("Deck: "..deckCount.."  Discard: "..discardCount.."  Played: "..playedCount, 40, hud_y)
  hud_y = hud_y + 20
  -- HUD line 2: ~y=80  (Score / threshold target) — only when S.meta exists
  if S and S.meta then
    local t = (S.meta and S.meta.threshold) or 1
    local tgt = Scoring and Scoring.target_for and Scoring.target_for(t) or nil
    if tgt then
      love.graphics.print("Score: "..tostring(S.meta.score).." / "..tostring(tgt).."   (T"..tostring(t)..")", 40, hud_y)
    else
      love.graphics.print("Score: "..tostring(S.meta.score).."   (T"..tostring(t).." — Endless)", 40, hud_y)
    end
    hud_y = hud_y + 20
  end
  -- HUD line 3: ~y=100 (Current attack) — only when an attack is announced
  if S and S.combat and S.combat.current_attack then
    love.graphics.print("Attack → "..S.combat.current_attack, 40, hud_y)
    hud_y = hud_y + 20
  end
  -- HUD line 4: ~y=120 (Hand size / max)
  love.graphics.print("Hand size: "..tostring(#hand).." (max "..HAND_MAX..")", 40, hud_y)
  hud_y = hud_y + 30
  -- HUD line 5: ~y=150 (Jokers in hand vs base cap of 5; Food Joker may extend at runtime)
  love.graphics.print("Jokers: " .. tostring(#(S.jokers and S.jokers.hand or {})) .. "/5", 40, hud_y)
  hud_y = hud_y + 20
  -- HUD line 6: ~y=170 (Turn / phase — single shared line)
  love.graphics.print("Turn: "..tostring(GS.turn or 1).."   Phase: "..GS.phase, 40, hud_y)
  hud_y = hud_y + 20
  local lastPlayedY = hud_y + 25
  -- After the HUD audit, hud_y is final. Anchor the button row below the last HUD
  -- line, clamped to a minimum of y=210 so it always sits between the HUD and the
  -- joker row (JOKER_Y=250). Worst-case hud_y≈190 → BTN_Y=210 → buttons span 210–240.
  local BTN_Y = math.max(210, hud_y + 8)
  BTN_RESTART.y = BTN_Y
  BTN_RANK.y    = BTN_Y
  BTN_SUIT.y    = BTN_Y
  BTN_SAVE.y    = BTN_Y
  BTN_LOAD.y    = BTN_Y

  -- Buttons
  drawButton(BTN_RESTART)
  drawButton(BTN_RANK)
  drawButton(BTN_SUIT)
  drawButton(BTN_SAVE)
  drawButton(BTN_LOAD)
-- Checklist UI (2.2) + win / end banners
  drawChecklistUI()

  -- Jokers row
  if S.jokers and S.jokers.hand and #S.jokers.hand > 0 then
    love.graphics.print("Jokers:", JOKER_X, JOKER_Y - 20)
    for i, jid in ipairs(S.jokers.hand) do
      drawJoker(jid, i)
    end
  end

  
  -- Hand
  for i, c in ipairs(hand) do
    drawCard(c, i)
  end

  if lastResult and lastResult.exact then
          love.graphics.print("Last Played: "..lastResult.exact, 40, lastPlayedY)
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
    BTN_NEXT_T.x = px + math.floor((pw-140)/2)
    BTN_NEXT_T.y = py + ph - 50
    drawButton(BTN_NEXT_T)
    love.graphics.setColor(1,1,1)
  end
end
