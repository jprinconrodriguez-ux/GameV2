-- attacks.lua
-- Announces a random target hand each turn and resolves penalty if missed.

local Effects = require("effects")

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
  S.combat.halve_penalty = false
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
  -- Anti-Joker: while the shield is up, attacks are nullified entirely
  -- (no penalty, no score change). Expiry is handled by Effects.tick.
  if Effects.has(S, "attack_shield") then
    local res = { resolved=true, shielded=true, target=target }
    S.combat.current_attack = nil
    S.combat.just_played = nil
    return res
  end
  if S.combat.cancel_current_attack then
    -- cleared by Skull or similar
    local res = { resolved=true, canceled=true, target=target }
    -- reset flags for next turn
    S.combat.current_attack = nil
    S.combat.cancel_current_attack = false
    S.combat.just_played = nil
    return res
  end
  -- Purge: attacks targeting a purged hand neither award nor deduct points.
  if Effects.has(S, "purge_immunity") then
    local p = Effects.get(S, "purge_immunity")
    for _, h in ipairs((p and p.hands) or {}) do
      if h == target then
        local res = { resolved=true, purged=true, target=target }
        S.combat.current_attack = nil
        S.combat.just_played = nil
        return res
      end
    end
  end
  if S.combat.just_played == target then
    local res = { resolved=true, protected=true, target=target }
    S.combat.current_attack = nil
    S.combat.just_played = nil
    return res
  end
  -- Cybernetic: a hacked hand in the Protected ("p") state this turn takes no penalty.
  if Effects.has(S, "cybernetic") then
    local p = Effects.get(S, "cybernetic")
    local states = p and p.hacks and p.hacks[target]
    if states then
      local idx = math.max(1, math.min(3, p.turn_index or 1))
      if states[idx] == "p" then
        local res = { resolved=true, protected=true, target=target }
        S.combat.current_attack = nil
        S.combat.just_played = nil
        return res
      end
    end
  end
  -- penalty
  local pts = 0
  if scoring and scoring.apply_penalty then
    pts = scoring.apply_penalty(S, target)  -- applies the full penalty to the score
  end
  -- Skull: halve the penalty. apply_penalty already subtracted the full amount,
  -- so refund the difference and keep the halved (ceil) value.
  local halved = false
  if S.combat.halve_penalty then
    local half = math.ceil(pts / 2)
    if S.meta then S.meta.score = (S.meta.score or 0) + (pts - half) end
    pts = half
    halved = true
    S.combat.halve_penalty = false
  end
  local res = { resolved=true, penalized=true, target=target, penalty=pts, halved=halved or nil }
  S.combat.current_attack = nil
  S.combat.just_played = nil
  return res
end

-- Canonical source: Rule Book § Attack Probabilities. Tests in tests.lua assert these exact values.
-- T2–T3 probabilities (Rule Book; each shifts low tiers −2, high tiers +2 vs. previous; sum to 100)
local T2 = {
  ["High Card"] = 19, ["Pair"] = 16, ["Two Pair"] = 14, ["Three of a Kind"] = 12,
  ["Flush"] = 14, ["Straight"] = 10, ["Full House"] = 9, ["Four of a Kind"] = 6,
}
local T3 = {
  ["High Card"] = 17, ["Pair"] = 14, ["Two Pair"] = 12, ["Three of a Kind"] = 10,
  ["Flush"] = 16, ["Straight"] = 12, ["Full House"] = 11, ["Four of a Kind"] = 8,
}

function M.probs_for_threshold(t)
  if not t or t <= 1 then return T1
  elseif t == 2 then return T2
  else return T3 end
end

return M
