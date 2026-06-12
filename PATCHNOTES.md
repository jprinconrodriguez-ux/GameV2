# Jokers' Gambit — Patch Notes

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
