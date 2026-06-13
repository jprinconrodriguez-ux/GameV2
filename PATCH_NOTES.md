# Jokers' Gambit — Patch Notes

## v4.2 — 2026-06-13

### New Rules
- **Score-based threshold win (1.2):** Threshold completion is now checked mid-turn
  from any scoring source (manual play, Golden/Flush auto-scores, streak bonuses).
  At T1/T2 reaching the target completes immediately; at T3 it also requires all 8
  hands marked. Implemented via `checkThresholdWin()` (called after each scoring
  event and once per frame in MAIN).
- **Turn resolution order (1.3):** The attack penalty is now deducted *before* the
  played hand's award is credited. The play handler calls `resolveAttackMsg()`
  (penalty) then `Scoring.apply_award` (award).
- **Attack-match streak (1.1):** Tracked on `S.meta.streak` and shown in the HUD.
  A scored hand matching the current attack increments it (once per turn); a missed
  attack resets it; every 3rd match grants a bonus joker. Extra turns are excluded
  from streak evaluation entirely.

### Joker Fixes & Reworks
- **Steal (2.1):** The two revealed jokers are now always different ids (drawn from
  different pool positions; falls back to 1 if the pool truly has a single unique
  id). The non-kept joker is shown greyed in the active-jokers corner, disabled for
  the threshold, and returns to the pool on threshold advance.
- **Food Joker (2.2):** Now activates on *acquisition* — shown active in the corner,
  draws 3 cards into hand, and raises the card hand cap by +3 (14→17). On *use* the
  +3 cap bonus is removed (cards already in hand stay and don't regenerate).
  `food_passive` applies +3 (not +1).
- **The Architect (2.3):** Playing the building site is now a one-time action — the
  site and the Architect itself are cleared immediately after.
- **Fibonacci (2.4 in v1 / 2.13):** Stores the marked-hand count at acquisition as a
  card badge; on use awards that many jokers (0–8), bypassing the joker hand cap.
- **Four of Clubs (2.5):** The +6/club-or-4 bonus (doubling per threshold) is inert
  until the joker is explicitly used; after use it shows as active in the corner and
  the bonus applies.
- **Galaxy Joker (2.6):** Now also resets the score to 0 (in addition to clearing the
  checklist) and applies ×1.5 for the rest of the threshold.
- **Peacock Joker (2.7):** Extra turns do not increment the turn counter (shows
  "Extra") and do not count toward the every-5-turns tally (extra turns leave
  `GS.turn` unchanged, so the modulo tally skips them).
- **Golden Joker (2.8):** Auto-score is now NORMAL points; a same-turn manual copy of
  the same hand scores DOUBLE (order swapped). The auto-score now counts toward the
  streak and triggers a mid-turn threshold win when applicable (handled even when
  Golden fires on acquisition, via a pending flag processed in `love.update`).
- **The Flush (2.9):** Reworked to instantly score a Flush's award at the current
  threshold on use (doubled if the current attack is also Flush) — no cards needed.
  Counts toward the streak and the threshold-win check; the joker is consumed.
- **Cybernetic (2.10):** Rebuilt. Each of its 3 turns randomly picks 2 *different*
  hand types and assigns Double/Protected/Lose at 40/40/20 (no "Normal"). Conditions
  re-roll every turn via a 3-turn schedule. Double = ×2 award; Protected = auto-block
  if it's the attack target; Lose = the hand loses its T1 base penalty in points when
  played. Colour-coded in the checklist; shown in the corner; does not carry across
  thresholds.

### Bug Fixes
- **Game Over (3.1):** Now triggers when the deck and discard are both empty and the
  hand can't be refilled (checked after a play refill, after discard/draw, and at
  turn start). Does not trigger while the discard pile still has cards.
- **Threshold-transition streak (3.2):** The streak (and any milestone joker) for the
  hand that completes a threshold is resolved before the transition, because the
  attack/streak now resolve before the mid-turn win check.
- **Eye Joker crash (3.3):** `resolve_eye` guards against a nil `pool` (`state.jokers.pool or {}`),
  and the pool is always materialized before the overlay opens.

### Balance Updates
- **T4+ attack probabilities (4.1):** T4 and all higher thresholds now share one
  table: High Card 11, Pair 12, Two Pair 12, Three of a Kind 13, Flush 14,
  Straight 13, Full House 14, Four of a Kind 11 (sums to 100).
- **Rarity draw weights (4.2):** T1–T3 use 29/24/18/13/10/6; T4+ uses the harder
  33/27/20/10/6/4. The weighted draw selects the table by current threshold.

### Tests
- Updated: Cybernetic (schedule/D-P-L), The Flush (instant score), Four of Clubs
  (activate-on-use), Golden (normal-then-double).
- Added: T4+ attack probabilities + sum, T4+ rarity weights, Steal distinct ids,
  Galaxy score reset, and a v4.2 save/load round-trip for the new state
  (`streak`, `fourofclubs_active`, `food_acquired`, `fib_counts`, `steal_disabled`,
  `pool`).

### Notes / Not Headless-Testable
- Peacock turn-loop sequencing (2.7) and the mid-turn win overlay (1.2) live in
  `main.lua`'s update/turn loop, which requires LÖVE and isn't exercised by the
  headless suite — verified by inspection (consistent with existing M4 notes).
- Food's +3 applies to the **card** hand cap (HAND_MAX), per 2.2/v1 §2.9.
