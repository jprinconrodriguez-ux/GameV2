-- scoring.lua
-- Thresholded scoring and penalties for Solo mode.
-- Awards double each threshold; penalties scale 2x at T1 then ×2.25 per threshold.

local M = {}

local BASE_AWARD_T1 = {
  ["High Card"]      = 1,
  ["Pair"]           = 2,
  ["Two Pair"]       = 4,
  ["Three of a Kind"]= 6,
  ["Flush"]          = 8,
  ["Straight"]       = 8,
  ["Full House"]     = 8,
  ["Four of a Kind"] = 16,
}

local function clamp_threshold(t) return math.max(1, math.floor(t or 1)) end

function M.init(S)
  S.meta = S.meta or {}
  if S.meta.threshold == nil then S.meta.threshold = 1 end
  S.meta.turns = S.meta.turns or 0
  if S.meta.score == nil then S.meta.score = 0 end
end

function M.get_award(threshold, hand_name)
  local base = BASE_AWARD_T1[hand_name] or 0
  local mult = 2 ^ (clamp_threshold(threshold) - 1) -- x1 at T1, x2 at T2, x4 at T3
  return base * mult
end

-- Canonical formula (Rule Book § Penalties):
--   T1 = 2 × (T1 award). Each subsequent threshold = ceil(previous × 2.25).
--   Always compounds from T1 base, NOT from the current threshold's award.
local function penalty_for_threshold(t, hand_name)
  t = math.min(3, clamp_threshold(t)) -- game ends at T3; cap for safety
  -- T1 base: always 2 × T1 award (Rule Book canonical formula)
  local base = M.get_award(1, hand_name) * 2
  if t == 1 then return base end
  local cur = base
  for k = 2, t do
    cur = math.ceil(cur * 2.25)
  end
  return cur
end

function M.apply_award(S, hand_name)
  local t = clamp_threshold(S.meta.threshold)
  local pts = M.get_award(t, hand_name)
  S.meta.score = (S.meta.score or 0) + pts
  return pts
end

function M.apply_penalty(S, hand_name)
  local t = clamp_threshold(S.meta.threshold)
  local pts = penalty_for_threshold(t, hand_name)
  S.meta.score = (S.meta.score or 0) - pts
  return pts
end

-- Threshold targets (win scores) for core mode
function M.target_for(t)
  t = math.max(1, math.floor(t or 1))
  if t == 1 then return 80
  elseif t == 2 then return 150
  elseif t == 3 then return 300
  end
  return nil -- safety guard; thresholds beyond T3 do not occur in normal play
end

function M.is_threshold_complete(S)
  if not S or not S.meta then return false end
  local tgt = M.target_for(S.meta.threshold or 1)
  return tgt and (S.meta.score or 0) >= tgt
end

-- Preparation-phase skip bonus (Instruction Book):
-- base 5/10/15 pts for 1/2/3 turns skipped, multiplied by the threshold
-- multiplier (×1 at T1, ×2 at T2, ×4 at T3, ×6 at T4+).
function M.prep_skip_bonus(turns_skipped, threshold)
  local base = turns_skipped * 5  -- 1→5, 2→10, 3→15
  local mult = ({[1]=1,[2]=2,[3]=4})[threshold] or 6  -- T4+ = ×6
  return base * mult
end

function M.reset_for_next_threshold(S)
  if not S or not S.meta then return end
  S.meta.score = 0
end

function M.on_turn_advanced(S)
  if not S or not S.meta then return end
  S.meta.turns = (S.meta.turns or 0) + 1
end

return M
