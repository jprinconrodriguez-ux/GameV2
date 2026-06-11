-- joker_registry.lua
-- Data model: { id, name, rarity, jtype = "passive"|"active"|"triggered", effect = "effect_key" }
-- Rarity: "common","uncommon","rare","epic","legendary","mythic"

local R = {}

-- Minimal seed set to validate the core loop. Expand in 3.3.
-- TODO M2: fill remaining 20 jokers
R.all = {
  { id="bicycle",   name="Bicycle", rarity="common",    jtype="active",   effect="draw3" },
  { id="skull",     name="Skull",   rarity="uncommon",  jtype="active",   effect="cancel_attack" },
  -- Add more as you wire up 3.3: Flush, Acrobat, Architect, Eye, etc...
  -- { id="food",   name="Food",   rarity="legendary", jtype="passive", effect="hand_cap_plus1" },
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
