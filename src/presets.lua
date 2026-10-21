-- Preset cooldown group lists: what each style's Major and Rotation groups, the shared Utility group and a new
-- install's Defensives group start with, and each preset ability's name and icon so its tile draws before the
-- ability first fires. Pure data.
local presets = {}

-- { [key] = { name, icon, forms } } for every preset key. The icon is the ability struct's sprite, which the
-- action bars also show, so a preset tile picks up its keybind before the ability fires. forms, when present,
-- lists { name, icon } for each form the ability's bar slot can show, its own first: upgrades such as Greater
-- Sunshine and recast stages, which share the ability's cooldown.
presets.INFO = {}

-- Keys from { key, name, icon, { { name, icon } } } entries, the last listing other forms, recording each
-- entry in INFO.
local function list(entries)
  local keys = {}
  for _, entry in ipairs(entries) do
    local info = { name = entry[2], icon = entry[3] }
    if entry[4] ~= nil then
      info.forms = { { name = entry[2], icon = entry[3] } }
      for _, form in ipairs(entry[4]) do
        info.forms[#info.forms + 1] = { name = form[1], icon = form[2] }
      end
    end
    keys[#keys + 1] = entry[1]
    presets.INFO[entry[1]] = info
  end
  return keys
end

-- Major and Rotation keys by combat style, in display order. Weapon specials depend on the weapon, so none.
presets.STYLES = {
  necromancy = {
    major = list({
      { "NECROMANCY_LIVING_DEATH", "Living Death", 30078 },
      { "NECROMANCY_DEATH_SKULLS", "Death Skulls", 30074 },
    }),
    rotation = list({
      { "NECROMANCY_SOUL_SAP", "Soul Sap", 30080 },
      { "NECROMANCY_DEATH_TOUCH", "Touch of Death", 30076 },
      { "NECROMANCY_FINGER_OF_DEATH", "Finger of Death", 30077 },
      { "NECROMANCY_VOLLEY_OF_SOULS", "Volley of Souls", 30088 },
      { "NECROMANCY_BLOAT", "Bloat", 30016 },
      { "NECROMANCY_COMMAND_VENGEFUL_GHOST", "Command Vengeful Ghost", 34166 },
    }),
  },
  magic = {
    major = list({
      { "MAGIC_SUNSHINE", "Sunshine", 20183, { { "Greater Sunshine", 20184 } } },
      { "MAGIC_TSUNAMI", "Tsunami", 14240 },
      { "MAGIC_OVERLOAD", "Omnipower", 14242 },
      { "MAGIC_METAMORPHOSIS", "Metamorphosis", 14241 },
    }),
    rotation = list({
      { "MAGIC_CONCENTRATED_BLAST", "Concentrated Blast", 13309, { { "Greater Concentrated Blast", 13310 } } },
      { "MAGIC_SONIC_BOOM", "Sonic Wave", 27430, { { "Greater Sonic Wave", 27432 } } },
      { "MAGIC_DRAGON_BREATH", "Dragon Breath", 14236 },
      { "MAGIC_MAGMA_TEMPEST", "Magma Tempest", 15033, { { "Magma Tempest", 4378 } } },
      { "MAGIC_WILD_MAGIC", "Wild Magic", 14239 },
      { "MAGIC_CHOKE", "Asphyxiate", 14237 },
    }),
  },
  ranged = {
    major = list({
      { "RANGED_DEATHS_SWIFTNESS", "Death's Swiftness", 20185, { { "Greater Death's Swiftness", 20186 } } },
      { "RANGED_HEADSHOT", "Deadshot", 23730 },
      { "RANGED_UNLOAD", "Unload", 14253 },
      { "RANGED_SHADOW_TENDRILS", "Shadow Tendrils", 20914 },
    }),
    rotation = list({
      { "RANGED_RAPID_FIRE", "Rapid Fire", 14250 },
      { "RANGED_SNAP_SHOT", "Snap Shot", 23728 },
      { "RANGED_RICOCHET", "Greater Ricochet", 15039 },
      { "RANGED_BOMBARDMENT", "Bombardment", 14251 },
      { "RANGED_CORRUPTION", "Corruption Shot", 17255 },
      { "RANGED_GALESHOT", "Galeshot", 23731 },
    }),
  },
  melee = {
    major = list({
      { "STRENGTH_BERSERK", "Berserk", 14264 },
      { "ATTACK_METEOR_STRIKE", "Meteor Strike", 21363 },
      { "ATTACK_OVERPOWER", "Overpower", 14216 },
      { "ATTACK_EVISCERATE", "Massacre", 14217 },
    }),
    rotation = list({
      { "STRENGTH_ASSAULT", "Assault", 14261 },
      { "ATTACK_WHIRLWIND", "Hurricane", 14215 },
      { "STRENGTH_DESTROY", "Destroy", 14263 },
      { "MELEE_DISMEMBER", "Dismember", 21239 },
      { "ATTACK_CHARGE", "Barge", 14208, { { "Greater Barge", 840 } } },
      { "ATTACK_FLURRY", "Flurry", 14214, { { "Greater Flurry", 841 } } },
    }),
  },
}

-- The shared Utility group's keys: movement and the weapon special, the same for every style.
presets.UTILITY = list({
  { "ATTACK_BLADED_DIVE", "Dive", 23714 },
  { "MAGIC_SURGE_CHARGE2", "Surge", 14233 },
  { "RANGED_ESCAPE_CHARGE2", "Escape", 14245 },
  { "WEAPON_INSTABILITY", "Weapon Special Attack", 26105 },
})

-- The Defensives group's keys, which a new install's first custom group starts with.
presets.DEFENSIVES = list({
  { "DEFENCE_FREEDOM", "Freedom", 14220 },
  { "DEFENCE_ANTICIPATION", "Anticipation", 14219 },
  { "DEFENCE_RESONANCE", "Resonance", 14222 },
  { "DEFENCE_DEVOTION", "Devotion", 21665 },
  { "DEFENCE_BARRICADE", "Barricade", 14228 },
  { "DEFENCE_REFLECT", "Reflect", 14225 },
  { "DEFENCE_DEBILITATE", "Debilitate", 14226 },
  { "DEFENCE_HEROISM", "Immortality", 14230 },
})

-- Abilities no group starts with, listed so the ability picker offers them before they are first used.
list({
  { "NECROMANCY_SPLIT_SOUL", "Split Soul", 30706 },
  { "NECROMANCY_CONJURE_UNDEAD_ARMY", "Conjure Undead Army", 32988 },
  { "NECROMANCY_INVOKE_DEATH", "Invoke Death", 30702 },
  { "NECROMANCY_THREADS_OF_FATE", "Threads of Fate", 30734 },
  { "NECROMANCY_COMMAND_SKELETON_WARRIOR", "Command Skeleton Warrior", 34165 },
  {
    "NECROMANCY_SPECTRAL_SCYTHE",
    "Spectral Scythe",
    30084,
    { { "Spectral Scythe", 30086 }, { "Spectral Scythe", 30087 } },
  },
  { "NECROMANCY_BLOOD_SIPHON", "Blood Siphon", 30017 },
  { "MAGIC_SMOKE_TENDRILS", "Smoke Tendrils", 17501 },
  { "MAGIC_COMBUST", "Combust", 23401 },
  { "MAGIC_CORRUPTION", "Corruption Blast", 19226 },
  { "MAGIC_IMPACT2", "Deep Impact", 22755 },
  { "RANGED_EXPLOSIVE_SHOT", "Incendiary Shot", 14252 },
  { "RANGED_BINDING_SHOT", "Binding Shot", 14244 },
  { "RANGED_FRAGMENTATION_SHOT", "Fragmentation Shot", 14247 },
  { "RANGED_PUNCTURE_ARROW", "Salt the Wound", 30334 },
  { "STRENGTH_PULVERISE", "Pulverise", 14266 },
  { "ATTACK_HAEMORRHAGE", "Slaughter", 14213 },
  { "STRENGTH_QUAKE", "Quake", 14262 },
})

return presets
