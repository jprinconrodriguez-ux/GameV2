-- effects.lua
-- Timed effects engine (M4). Manages joker effects that persist across turns.
--
-- Schema: S.active_effects is a list of entries:
--   {
--     id              = "string",   -- effect type key, e.g. "attack_shield"
--     turns_remaining = N,          -- decremented each turn; removed when 0
--     payload         = {},         -- arbitrary data the effect needs
--     source          = "joker_id", -- which joker created it (debugging/UI)
--   }
-- Effects whose payload sets `no_carry = true` are stripped on threshold
-- advance via Effects.clear_tag(S, "no_carry").

local Effects = {}

-- Ensure the effects list exists on the state table.
function Effects.init(S)
  S.active_effects = S.active_effects or {}
end

-- Push a new timed effect entry.
function Effects.add(S, id, turns, payload, source)
  Effects.init(S)
  table.insert(S.active_effects, {
    id              = id,
    turns_remaining = turns,
    payload         = payload or {},
    source          = source,
  })
end

-- Decrement all effects by one turn; remove expired entries.
-- Cybernetic keeps a per-turn state schedule, so its payload.turn_index is
-- advanced here (before the decrement) to stay in sync for readers.
function Effects.tick(S)
  Effects.init(S)
  for i = #S.active_effects, 1, -1 do
    local e = S.active_effects[i]
    if e.id == "cybernetic" and e.payload then
      e.payload.turn_index = (e.payload.turn_index or 0) + 1
    end
    e.turns_remaining = (e.turns_remaining or 0) - 1
    if e.turns_remaining <= 0 then
      table.remove(S.active_effects, i)
    end
  end
end

-- True if any active entry has this id.
function Effects.has(S, id)
  for _, e in ipairs(S.active_effects or {}) do
    if e.id == id then return true end
  end
  return false
end

-- Payload of the first matching active entry, or nil.
function Effects.get(S, id)
  for _, e in ipairs(S.active_effects or {}) do
    if e.id == id then return e.payload end
  end
  return nil
end

-- Remove all entries flagged not to carry across thresholds
-- (payload.no_carry == true). Called on threshold advance.
function Effects.clear_tag(S, tag)
  for i = #(S.active_effects or {}), 1, -1 do
    local e = S.active_effects[i]
    if e.payload and e.payload.no_carry == true then
      table.remove(S.active_effects, i)
    end
  end
end

return Effects
