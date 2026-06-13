-- joker_registry.lua
-- Data model: { id, name, rarity, jtype = "passive"|"active"|"triggered", effect = "effect_key" }
-- Rarity: "common","uncommon","rare","epic","legendary","mythic"
-- Optional flags: hidden=true (never shown/awarded), active=false (no effect),
--                 deferred=true (implementation pending; never awarded).

local R = {}

-- Full Rule Book joker set. Effects not yet coded use "noop".
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
  { id="food",        name="Food Joker",    rarity="legendary", jtype="passive",   effect="food_passive"   },
  { id="golden",      name="Golden Joker",  rarity="legendary", jtype="triggered", effect="golden"         },  -- 2.10: legendary (was mythic)
  { id="fibonacci",   name="Fibonacci",     rarity="mythic",    jtype="active",    effect="fibonacci"      },
  -- Invisible: deferred to a later milestone (3.4) — never awarded.
  { id="invisible",   name="Invisible",     rarity="mythic",    jtype="active",    effect="noop", active=false, deferred=true },
  -- Devil: kept in the registry but hidden and inactive (1.2) — never awarded, no effect.
  { id="devil",       name="Devil Joker",   rarity="mythic",    jtype="active",    effect="noop", active=false, hidden=true },
  { id="angel",       name="Angel Joker",   rarity="mythic",    jtype="active",    effect="angel"          },
  { id="fourofclubs", name="Four of Clubs", rarity="mythic",    jtype="triggered", effect="fourofclubs"    },  -- 2.12: real dispatch; scoring bonus still in scoring.lua
  { id="anti",        name="Anti-Joker",    rarity="mythic",    jtype="active",    effect="anti_joker"     },
  { id="galaxy",      name="Galaxy Joker",  rarity="mythic",    jtype="active",    effect="galaxy"         },
  { id="peacock",     name="Peacock Joker", rarity="mythic",    jtype="active",    effect="peacock"        },
}

-- Joker rarity spawn chances (infinite pool — Post-M4 canonical numbers).
-- Used as relative weights when picking a rarity for a pool draw. They sum to
-- 100 so each weight reads directly as a percentage.
R.rarity_weights = {
  common    = 29,
  uncommon  = 24,
  rare      = 18,
  epic      = 13,
  legendary = 10,
  mythic    =  6,
}

-- True if a joker should never be drawn/awarded (hidden, inactive, or deferred).
function R.is_excluded(def)
  if not def then return true end
  return def.hidden == true or def.active == false or def.deferred == true
end

-- Utility: list of *drawable* IDs by rarity (excludes hidden/inactive/deferred,
-- e.g. Devil and Invisible). The pool draw relies on this so those jokers are
-- never awarded.
function R.ids_by_rarity()
  local buckets = {common={},uncommon={},rare={},epic={},legendary={},mythic={}}
  for _,j in ipairs(R.all) do
    if not R.is_excluded(j) then
      table.insert(buckets[j.rarity], j.id)
    end
  end
  return buckets
end

-- Lookup by id
R.by_id = {}
for _,j in ipairs(R.all) do
  R.by_id[j.id] = j
end

return R
