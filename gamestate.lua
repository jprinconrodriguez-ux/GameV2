-- Phases: "TITLE", "PREP", "MAIN", "END", "THRESHOLD", "WIN", "LOSS"
--   LOSS  → the run ended in a loss (deck depleted before win conditions met).
local Gamestate = {
  phase = "MAIN",
  turn  = 1,
  playedHands = {},           -- e.g., { ["Pair"] = true }
  limits = { discard_used = false }, -- per-turn discard flag
  meta   = { run_id = 1 },    -- placeholder; increments per restart if desired
  endless = false,            -- set true when the player continues past T3
  prep_turns_remaining = 0    -- setup turns left while phase == "PREP"
}

function Gamestate:reset()
  self.phase = "MAIN"
  self.turn  = 1
  self.playedHands = {}
  self.limits = { discard_used = false }
  self.meta = self.meta or { run_id = 1 }
  self.endless = false
  self.prep_turns_remaining = 0
end

return Gamestate

