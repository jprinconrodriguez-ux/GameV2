-- joker_registry.lua
-- Data model: { id, name, rarity, jtype = "passive"|"active"|"triggered", effect = "effect_key" }
-- Rarity: "common","uncommon","rare","epic","legendary","mythic"

local R = {}

-- Full Rule Book joker set (22 distinct jokers). Effects not yet coded use "noop".
R.all = {
  { id="bicycle",     name="Bicycle",       rarity="common",    jtype="active",    effect="draw3"          },
  { id="skull",       name="Skull",         rarity="uncommon",  jtype="active",    effect="cancel_attack"  },
  { id="steal",       name="Steal",         rarity="rare",      jtype="active",    effect="steal"          },
  { id="purge",       name="Purge",         rarity="epic",      jtype="active",    effect="purge"          },
  { id="cute",        name="Cute Joker",    rarity="epic",      jtype="active",    effect="cute_joker"     },
  { id="flush",       name="The Flush",     rarity="legendary", jtype="active",    effect="flush_joker"    },
  { id="acrobat",     name="The Acrobat",   rarity="legendary", jtype="active",    effect="acrobat"        },
  { id="architect",   name="The Architect", rarity="legendary", jtype="active",    effect="architect"      },
  { id="eye",         name="The Eye",       rarity="legendary", jtype="active",    effect="eye"            },
  { id="cybernetic",  name="Cybernetic",    rarity="legendary", jtype="active",    effect="cybernetic"     },
  { id="trader",      name="The Trader",    rarity="legendary", jtype="active",    effect="trader"         },
  { id="bee",         name="The Bee",       rarity="legendary", jtype="active",    effect="bee"            },
  { id="food",        name="Food Joker",    rarity="legendary", jtype="passive",   effect="hand_cap_plus3" },
  { id="fibonacci",   name="Fibonacci",     rarity="mythic",    jtype="active",    effect="fibonacci"      },
  { id="invisible",   name="Invisible",     rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M5): needs deck-search UI overlay
  { id="devil",       name="Devil Joker",   rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M5): needs boss system
  { id="angel",       name="Angel Joker",   rarity="mythic",    jtype="active",    effect="angel"          },
  { id="fourofclubs", name="Four of Clubs", rarity="mythic",    jtype="triggered", effect="noop"           },  -- triggered passive; handled in scoring.lua
  { id="anti",        name="Anti-Joker",    rarity="mythic",    jtype="active",    effect="anti_joker"     },
  { id="golden",      name="Golden Joker",  rarity="mythic",    jtype="triggered", effect="golden"         },
  { id="galaxy",      name="Galaxy Joker",  rarity="mythic",    jtype="active",    effect="galaxy"         },
  { id="peacock",     name="Peacock Joker", rarity="mythic",    jtype="active",    effect="peacock"        },
}

-- Weighted draw probabilities per rarity. These are the *copy counts* of each
-- rarity in the full 84-card joker deck (Rule Book § Joker Deck Composition):
--   common 20, uncommon 15, rare 12, epic 12 (2 types × 6), legendary 16
--   (8 types × 2), mythic 9 (9 types × 1) → 84 total.
-- They are used directly as relative weights when picking a rarity, so the draw
-- probabilities match the deck distribution (e.g. common ≈ 20/84 ≈ 23.8%).
R.rarity_weights = {
  common    = 20,
  uncommon  = 15,
  rare      = 12,
  epic      = 12,
  legendary = 16,
  mythic    =  9,
}

-- Utility: list of IDs by rarity
function R.ids_by_rarity()
  local buckets = {common={},uncommon={},rare={},epic={},legendary={},mythic={}}
  for _,j in ipairs(R.all) do
    table.insert(buckets[j.rarity], j.id)
  end
  return buckets
end

-- Lookup by id
R.by_id = {}
for _,j in ipairs(R.all) do
  R.by_id[j.id] = j
end

return R
