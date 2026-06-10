local Gamestate = {
  phase = "MAIN",
  turn  = 1,
  playedHands = {},           -- e.g., { ["Pair"] = true }
  limits = { discard_used = false }, -- per-turn discard flag
  meta   = { run_id = 1 }     -- placeholder; increments per restart if desired
}

function Gamestate:reset()
  self.phase = "MAIN"
  self.turn  = 1
  self.playedHands = {}
  self.limits = { discard_used = false }
  self.meta = self.meta or { run_id = 1 }
end

return Gamestate

