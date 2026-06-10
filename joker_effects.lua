-- joker_effects.lua
-- Pure functions that apply effects. Receive (state, ctx) and return a result table if needed.

local E = {}

-- Example: Bicycle (Draw 3)
function E.draw3(state, ctx)
  if state.drawCards then state.drawCards(3) end
  return { ok=true, msg="Drew 3 cards." }
end

-- Example: Skull (Cancel current attack)
function E.cancel_attack(state, ctx)
  -- Expect your attack resolver to check: state.combat.cancel_current_attack == true
  state.combat = state.combat or {}
  state.combat.cancel_current_attack = true
  return { ok=true, msg="Canceled the current attack." }
end

-- Example hook for Food Joker passive (hand cap +1 while in hand)
function E.hand_cap_plus1(state, ctx)
  state.jokers.modifiers = state.jokers.modifiers or {}
  state.jokers.modifiers.hand_cap_bonus = (state.jokers.modifiers.hand_cap_bonus or 0) + 1
  return { ok=true }
end

return E
