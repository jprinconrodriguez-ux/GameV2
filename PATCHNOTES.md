# Jokers' Gambit — Patch Notes

## Post-Milestone 4 Polish

### Global changes
- **Boss mode / punish level:** No boss-mode code or 30-turn punishment escalation existed in the
  current source — only a stale comment referencing a "boss system" on the Devil joker, now removed.
- **Devil Joker (1.2):** Kept in the registry but flagged `hidden=true, active=false`. Excluded from
  pool construction and never awarded; produces no effect.
- **Auto Use (1.4):** Fibonacci and Bee were already manually activated (no auto-fire). No auto-use
  behaviour remained to remove.
- **HAND_MAX = 14 (1.5):** Base card hand cap is now 14 everywhere via `effectiveHandMax()`.

### Joker fixes
- **The Eye (2.1):** Fixed the `pool` nil dereference by materializing an infinite pool buffer
  (`S.jokers.pool`, lazily filled by weighted draws). The overlay shows the next 10 upcoming pool
  jokers by index; swap-to-reorder writes the new order back to the front of the pool; Esc closes it.
- **Active-joker HUD (2.2):** Cybernetic, Purge, Galaxy, and Four of Clubs now appear in the
  active-effects panel (name + remaining turns where applicable), alongside Peacock/Anti-Joker.
- **Extra-turn counter (2.3):** Peacock's extra turn now shows `Turn: Extra`, announces no attack
  (`current_attack = nil`), and does not increment the counter (47 → Extra → 48).
- **Cute Joker (2.4):** Reworked to allow a single 6-card play that must be two separate
  three-of-a-kinds (a 6-of-a-kind is rejected; any 6-card play without the flag is rejected). Scores
  Three of a Kind twice.
- **Acrobat (2.5):** Overlay now toggles between the deck's top 10 and your current hand (H key).
  Taken cards bypass the cap; regeneration resumes once the hand is at/below the cap.
- **Angel Joker (2.6):** The copied joker is now always added, even above the joker cap (overflow
  bypass, same rule as Fibonacci).
- **Steal (2.7):** Draws 2 from the pool, fully closable (Esc cancels and returns both to the pool +
  the Steal joker to hand). The non-chosen joker is disabled for the threshold and re-enters the pool
  at the next threshold.
- **Purge (2.8):** Shown in the active panel with remaining turns; protected hands are marked with `*`
  in the checklist.
- **Food Joker (2.9):** Passive now raises the **card** HAND_MAX by 3 while in hand (immediate on
  acquire/loss). On use it permanently adds 3 cards to the deck and the cap reverts.
- **Golden Joker (2.10):** Rarity changed mythic → legendary.
- **The Architect (2.11):** Building site capped at 5 cards; "play" uses the highest valid poker
  category among the site cards (`Eval.best_category`); site cleared on threshold advance.
- **Four of Clubs (2.12):** Real dispatch wired (no more silent "No effect"); scoring bonus unchanged.
- **Fibonacci (2.13):** Records the marked-hand count at acquisition (shown as a corner badge); on use
  awards that many jokers (clamped 0–8) with cap bypass.

### Other fixes
- **Game Over (3.1):** Depletion overlay reworded to a distinct "Game Over" screen with Restart.
- **Clear selection (3.2):** C clears both cards and the active joker; card/joker selection is now
  mutually exclusive.
- **Joker lost (3.3):** A brief "Joker lost: [Name]" notice appears when an earned joker can't fit and
  isn't cap-bypass eligible.
- **Invisible (3.4):** Flagged `active=false, deferred=true` with a TODO; never awarded.
- **HUD (3.5):** Fixed 2×7 card grid; deck counter shows `Deck: N / T` (T tracked via
  `deck.total_cards`); setup-phase text constrained to the left column; background set to #486478.
- **Win condition (3.6):** `score >= target` already triggered completion; verified and tested.
- **Infinite pool (3.7):** Weighted draw uses the canonical spawn chances (29/24/18/13/10/6);
  hidden/deferred jokers excluded.

### Known issues / awaiting design input
- Cybernetic Joker rework (2.14): design not provided — implementation preserved with a TODO comment.
- Four of Clubs rework (2.15): design not provided — dispatch fixed, rework TODO added.
- The Flush rework (2.16): design not provided — TODO comment added; effect preserved.
- Endless mode (Step 4): deferred — TODO placeholder near the threshold-advance logic.
- Invisible Joker (3.4): deferred to a later milestone.
- T4+ probability/rarity changes (F.1): deferred — TODO comments in attacks.lua and jokers.lua.

### Breaking changes
- Food Joker now affects the **card** hand cap, not the joker hand cap (the Joker-hand-cap reference
  in the handoff said +3 to the joker cap; the detailed task 2.9 said +3 to HAND_MAX — implemented per
  2.9). Save format gained `deck.total_cards` and joker `pool` / `steal_disabled` / `fib_counts`
  (all optional/back-compatible). Joker hand-cap modifier key renamed `hand_cap_bonus` → `joker_cap_bonus`.

---

## v3.1 – Deck Depletion, Infinite Joker Pool, Hand Cap & Joker Corrections

### What's new
- **Losing condition:** The run now ends in a loss if the main deck and discard pile are both empty
  and the player has not yet met the score target **and** played all 8 hand categories. An overlay
  is shown and all input is blocked until the player restarts.
- **Infinite joker pool:** The finite shuffled joker pool has been replaced with a probability-based
  system. Each time a joker is drawn, a rarity is selected by weighted random (matching the full
  84-card deck distribution), then one joker of that rarity is chosen uniformly at random.
  Duplicates are allowed. The played-pile / reshuffle mechanic has been removed.
- **Reduced max hand cap:** Maximum hand size is now 15 (was 20).

### What changed
- **Bicycle joker** corrected: now draws 3 random cards that are **temporary** (marked with `*`)
  and only last the turn they were drawn in. If played, they are permanently added to the deck.
- **Skull joker** corrected: now **halves** the current attack's penalty instead of cancelling it
  entirely.
- **Food Joker hand cap** corrected: passive now grants +3 to hand cap (was +1).
- **Played pile** cards are locked for the duration of a threshold and are only returned to the
  deck on threshold advance. This was already the intended behaviour; it is now enforced by the
  depletion check.
- `saveload.lua` updated: joker pool and played-pile state removed; temporary card state added.
- `joker_registry.lua` rarity counts updated to per-type copy counts (used as probability weights).
- `tests.lua` updated: save/load test no longer checks played_pile; four new targeted tests added.

## v4.0 – Milestone 4: Timed Effects, Scoring Hooks, and Full Joker Content

### What's new
- **Timed effects engine:** New `effects.lua` module manages duration-based joker effects
  across turns (`Effects.add`, `Effects.tick`, `Effects.has`, `Effects.get`,
  `Effects.clear_tag`). Active effects snapshot and restore correctly through save/load.
- **Anti-Joker:** Disables all attack penalties for 3 turns. Shown as active in UI.
- **Purge:** Player selects 2 hand types to protect from attack penalties for 5 turns.
  Requires a hand-type selection overlay.
- **Cybernetic:** Randomly hacks 2 hand types for 3 turns with Normal/Double/Protected/Lose
  states. Coloured checklist hints indicate active hacks. Cannot carry across thresholds.
- **Peacock Joker:** Grants an extra turn every 5 turns for the rest of the threshold.
  Shown as active in UI.
- **The Flush:** Awards double points when a Flush is played and the current attack is also
  a Flush.
- **The Trader:** Unmarks one completed hand from the checklist; next hand scores double.
- **Four of Clubs:** Passive trigger — hands containing a Club or a 4-rank score a bonus
  (+6 at T1, doubling per threshold).
- **Golden Joker:** Auto-scores a random marked hand at double value on acquire.
- **Galaxy Joker:** Resets the checklist and applies a ×1.5 score multiplier for the rest
  of the threshold.
- **Cute Joker:** Allows playing two Three-of-a-Kind hands in a single turn.
- **The Architect:** Opens a persistent building site; player accumulates cards across turns
  ([A] adds selected cards, [P] plays the site as a bonus hand). Cleared on threshold advance.
- **Overlay resolution wired:** Steal, Acrobat, Eye, and Angel choice overlays are now
  fully interactive in `main.lua` (Escape cancels Acrobat and Eye; Steal and Angel are
  permanent commitments).

### What changed
- `scoring.lua`: `apply_award` now accepts an optional third argument `played_cards` for
  Four of Clubs passive trigger detection.
- `jokers.lua`: `gain_from_pool` and `gain_joker` accept an optional `ctx` argument
  forwarded to auto-use triggered jokers (Golden).
- `attacks.lua`: `resolve` checks for `attack_shield` (Anti-Joker), `purge_immunity`
  (Purge), and Cybernetic's Protected state before applying penalties.
- `saveload.lua`: snapshots and restores all new M4 state fields (`active_effects`,
  `flush_active`, `trader_double`, `peacock_active`/`peacock_extra_pending`,
  `cute_active`, `architect_active`/`architect_site`, `purge_pending`/`purge_selected`).
- `joker_registry.lua`: all 12 pending M4 jokers wired to real effects; Golden Joker is
  now `jtype="triggered"`; Invisible and Devil Joker remain noop, re-tagged `TODO(M5)`.
- `tests.lua`: 17 new tests added covering timed effects, scoring hooks, joker overlay
  resolution, and save/load round-trips for new state.
