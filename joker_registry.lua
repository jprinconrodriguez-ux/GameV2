-- joker_registry.lua
-- Data model: { id, name, rarity, jtype = "passive"|"active"|"triggered", effect = "effect_key" }
-- Rarity: "common","uncommon","rare","epic","legendary","mythic"

local R = {}

-- Full Rule Book joker set (22 distinct jokers). Effects not yet coded use "noop".
R.all = {
  { id="bicycle",     name="Bicycle",       rarity="common",    jtype="active",    effect="draw3"          },
  { id="skull",       name="Skull",         rarity="uncommon",  jtype="active",    effect="cancel_attack"  },
  { id="steal",       name="Steal",         rarity="rare",      jtype="active",    effect="steal"          },
  { id="purge",       name="Purge",         rarity="epic",      jtype="active",    effect="noop"           },  -- TODO(M4): needs timed effect system
  { id="cute",        name="Cute Joker",    rarity="epic",      jtype="active",    effect="noop"           },  -- TODO(M4): needs hand stacking system
  { id="flush",       name="The Flush",     rarity="legendary", jtype="active",    effect="noop"           },  -- TODO(M4): needs hand-override hook
  { id="acrobat",     name="The Acrobat",   rarity="legendary", jtype="active",    effect="acrobat"        },
  { id="architect",   name="The Architect", rarity="legendary", jtype="active",    effect="noop"           },  -- TODO(M4): needs hand stacking system
  { id="eye",         name="The Eye",       rarity="legendary", jtype="active",    effect="eye"            },
  { id="cybernetic",  name="Cybernetic",    rarity="legendary", jtype="active",    effect="noop"           },  -- TODO(M4): needs timed effect system
  { id="trader",      name="The Trader",    rarity="legendary", jtype="active",    effect="noop"           },  -- TODO(M4): needs scoring hook
  { id="bee",         name="The Bee",       rarity="legendary", jtype="active",    effect="bee"            },
  { id="food",        name="Food Joker",    rarity="legendary", jtype="passive",   effect="food_passive"   },
  { id="fibonacci",   name="Fibonacci",     rarity="mythic",    jtype="active",    effect="fibonacci"      },
  { id="invisible",   name="Invisible",     rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs deck-search UI hook
  { id="devil",       name="Devil Joker",   rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs boss system
  { id="angel",       name="Angel Joker",   rarity="mythic",    jtype="active",    effect="angel"          },
  { id="fourofclubs", name="Four of Clubs", rarity="mythic",    jtype="triggered", effect="noop"           },  -- TODO(M4): needs scoring hook
  { id="anti",        name="Anti-Joker",    rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs timed effect system
  { id="golden",      name="Golden Joker",  rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs scoring hook
  { id="galaxy",      name="Galaxy Joker",  rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs scoring hook
  { id="peacock",     name="Peacock Joker", rarity="mythic",    jtype="active",    effect="noop"           },  -- TODO(M4): needs timed effect system
}

-- How many copies of each rarity (per distinct type) enter the pool.
-- Source of truth: Rule Book — Joker Deck Composition (copies per type).
R.rarity_counts = {
  common    = 20,
  uncommon  = 15,
  rare      = 12,
  epic      =  6,
  legendary =  2,
  mythic    =  1,
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
