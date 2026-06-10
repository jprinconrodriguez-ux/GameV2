-- attacks.lua
-- Announces a random target hand each turn and resolves penalty if missed.

local M = {}

-- T1 probabilities (Rule Book)
local T1 = {
  ["High Card"] = 21,
  ["Pair"] = 18,
  ["Two Pair"] = 16,
  ["Three of a Kind"] = 14,
  ["Flush"] = 12,
  ["Straight"] = 8,
  ["Full House"] = 7,
  ["Four of a Kind"] = 4,
}

local function pick_weighted(tbl, rng)
  local total = 0
  for _,w in pairs(tbl) do total = total + w end
  local r = (rng and rng.random or math.random)() * total
  local acc = 0
  for k,w in pairs(tbl) do
    acc = acc + w
    if r <= acc then return k end
  end
  -- fallback
  for k,_ in pairs(tbl) do return k end
end

function M.announce(S, rng, probs)
  S.combat = S.combat or {}
  local t = (S and S.meta and S.meta.threshold) or 1
  local pool = probs or M.probs_for_threshold(t)
  local target = pick_weighted(pool, rng or math)
  S.combat.current_attack = target
  S.combat.cancel_current_attack = false
  S.combat.just_played = nil
  return target
end

function M.note_played_this_turn(S, hand_name)
  S.combat = S.combat or {}
  S.combat.just_played = hand_name
end

function M.resolve(S, scoring)
  S.combat = S.combat or {}
  local target = S.combat.current_attack
  if not target then return {resolved=false} end
  if S.combat.cancel_current_attack then
    -- cleared by Skull or similar
    local res = { resolved=true, canceled=true, target=target }
    -- reset flags for next turn
    S.combat.current_attack = nil
    S.combat.cancel_current_attack = false
    S.combat.just_played = nil
    return res
  end
  if S.combat.just_played == target then
    local res = { resolved=true, protected=true, target=target }
    S.combat.current_attack = nil
    S.combat.just_played = nil
    return res
  end
  -- penalty
  local pts = 0
  if scoring and scoring.apply_penalty then
    pts = scoring.apply_penalty(S, target)
  end
  local res = { resolved=true, penalized=true, target=target, penalty=pts }
  S.combat.current_attack = nil
  S.combat.just_played = nil
  return res
end

-- T2–T5 probabilities (Rule Book; each shifts low tiers −2, high tiers +2 vs. previous; sum to 100)
local T2 = {
  ["High Card"] = 19, ["Pair"] = 16, ["Two Pair"] = 14, ["Three of a Kind"] = 12,
  ["Flush"] = 14, ["Straight"] = 10, ["Full House"] = 9, ["Four of a Kind"] = 6,
}
local T3 = {
  ["High Card"] = 17, ["Pair"] = 14, ["Two Pair"] = 12, ["Three of a Kind"] = 10,
  ["Flush"] = 16, ["Straight"] = 12, ["Full House"] = 11, ["Four of a Kind"] = 8,
}
local T4 = {
  ["High Card"] = 15, ["Pair"] = 12, ["Two Pair"] = 10, ["Three of a Kind"] = 8,
  ["Flush"] = 18, ["Straight"] = 14, ["Full House"] = 13, ["Four of a Kind"] = 10,
}
local T5 = {
  ["High Card"] = 13, ["Pair"] = 10, ["Two Pair"] = 8, ["Three of a Kind"] = 6,
  ["Flush"] = 20, ["Straight"] = 16, ["Full House"] = 15, ["Four of a Kind"] = 12,
}

function M.probs_for_threshold(t)
  if not t or t <= 1 then return T1
  elseif t == 2 then return T2
  elseif t == 3 then return T3
  elseif t == 4 then return T4
  else return T5 end
end

return M
