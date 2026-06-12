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
