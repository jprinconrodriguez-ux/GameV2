-- deck.lua
local Deck = {}

local SUITS = {"♠","♥","♦","♣"}
local RANKS = {"A","2","3","4","5","6","7","8","9","10","J","Q","K"}

local function makeDecks(numDecks)
  local cards = {}
  for d = 1, (numDecks or 2) do
    for _, s in ipairs(SUITS) do
      for _, r in ipairs(RANKS) do
        table.insert(cards, { suit = s, rank = r })
      end
    end
  end
  return cards
end

local function shuffle(t)
  for i = #t, 2, -1 do
    local j = love.math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

function Deck.new(numDecks)
  local cards = makeDecks(numDecks or 2)
  local self = {
    cards = cards,                      -- main deck
    discard = {},                       -- discard pile
    played = {},                        -- permanent played pile
    -- 3.5.2: total cards that have ever existed in this run (104 for 2 decks).
    -- Increases whenever cards are permanently added (Food Joker, Bicycle).
    total_cards = #cards
  }
  shuffle(self.cards)
  return setmetatable(self, { __index = Deck })
end

-- 3.5.2: register newly created permanent cards so the "Deck: N / T" counter's
-- total grows when Food Joker / Bicycle add cards to the run.
function Deck:addPermanentTotal(n)
  self.total_cards = (self.total_cards or 0) + (n or 0)
end

-- Draw n cards; reshuffle only when main empty
function Deck:draw(n)
  local drawn = {}
  n = n or 1
  for _ = 1, n do
    if #self.cards == 0 then
      if #self.discard > 0 then
        -- reshuffle discard into main
        for i = #self.discard, 1, -1 do
          table.insert(self.cards, self.discard[i])
          table.remove(self.discard, i)
        end
        shuffle(self.cards)
      else
        break  -- nothing left to draw
      end
    end
    if #self.cards == 0 then break end
    table.insert(drawn, table.remove(self.cards))
  end
  return drawn
end

function Deck:discardCards(cards)
  for _, c in ipairs(cards or {}) do
    table.insert(self.discard, c)
  end
end

function Deck:commitPlayed(cards)
  for _, c in ipairs(cards or {}) do
    table.insert(self.played, c)
  end
end


        -- Draw only from main deck; DO NOT reshuffle discard during this call.
        function Deck:drawNoReshuffle(n)
          local drawn = {}
          n = n or 1
          for _ = 1, n do
            if #self.cards == 0 then break end
            table.insert(drawn, table.remove(self.cards))
          end
          return drawn
        end


-- === SAVE/LOAD HELPERS ===
local function _copyCard(c) return { suit = c.suit, rank = c.rank } end

function Deck:getState()
  local function copyList(src)
    local out = {}
    for i = 1, #src do out[i] = _copyCard(src[i]) end
    return out
  end
  return {
    cards   = copyList(self.cards),
    discard = copyList(self.discard),
    played  = copyList(self.played),
    total_cards = self.total_cards or (#self.cards + #self.discard + #self.played)
  }
end

function Deck:loadState(state)
  local function copyList(src)
    local out = {}
    for i = 1, #src do out[i] = _copyCard(src[i]) end
    return out
  end
  self.cards   = copyList((state and state.cards)   or {})
  self.discard = copyList((state and state.discard) or {})
  self.played  = copyList((state and state.played)  or {})
  self.total_cards = (state and state.total_cards)
                     or (#self.cards + #self.discard + #self.played)
end

return Deck
