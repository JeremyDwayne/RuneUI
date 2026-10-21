-- Preset cooldown group lists: what each style's Major and Rotation groups and the shared Utility group start
-- with, and each preset ability's name and icon so its tile draws before the ability first fires. Pure data.
local presets = {}

-- { [key] = { name, icon } } for every preset key. The icon is the ability struct's sprite, which the action
-- bars also show, so a preset tile picks up its keybind before the ability fires.
presets.INFO = {}

-- Keys from { key, name, icon } entries, recording each entry in INFO.
local function list(entries)
  local keys = {}
  for _, entry in ipairs(entries) do
    keys[#keys + 1] = entry[1]
    presets.INFO[entry[1]] = { name = entry[2], icon = entry[3] }
  end
  return keys
end

-- Major and Rotation keys by combat style, in display order. Weapon specials depend on the weapon, so none.
presets.STYLES = {
  necromancy = {
    major = list({
      { "NECROMANCY_LIVING_DEATH", "Living Death", 30078 },
      { "NECROMANCY_DEATH_SKULLS", "Death Skulls", 30074 },
      { "NECROMANCY_SPLIT_SOUL", "Split Soul", 30706 },
      { "NECROMANCY_CONJURE_UNDEAD_ARMY", "Conjure Undead Army", 32988 },
      { "NECROMANCY_INVOKE_DEATH", "Invoke Death", 30702 },
      { "NECROMANCY_THREADS_OF_FATE", "Threads of Fate", 30734 },
    }),
    rotation = list({
      { "NECROMANCY_DEATH_TOUCH", "Touch of Death", 30076 },
      { "NECROMANCY_SOUL_SAP", "Soul Sap", 30080 },
      { "NECROMANCY_BLOAT", "Bloat", 30016 },
      { "NECROMANCY_COMMAND_VENGEFUL_GHOST", "Command Vengeful Ghost", 34166 },
      { "NECROMANCY_COMMAND_SKELETON_WARRIOR", "Command Skeleton Warrior", 34165 },
      { "NECROMANCY_SPECTRAL_SCYTHE", "Spectral Scythe", 30084 },
      { "NECROMANCY_BLOOD_SIPHON", "Blood Siphon", 30017 },
    }),
  },
  magic = {
    major = list({
      { "MAGIC_SUNSHINE", "Sunshine", 20183 },
      { "MAGIC_TSUNAMI", "Tsunami", 14240 },
      { "MAGIC_OVERLOAD", "Omnipower", 14242 },
      { "MAGIC_METAMORPHOSIS", "Metamorphosis", 14241 },
      { "MAGIC_SMOKE_TENDRILS", "Smoke Tendrils", 17501 },
    }),
    rotation = list({
      { "MAGIC_CHOKE", "Asphyxiate", 14237 },
      { "MAGIC_WILD_MAGIC", "Wild Magic", 14239 },
      { "MAGIC_DRAGON_BREATH", "Dragon Breath", 14236 },
      { "MAGIC_COMBUST", "Combust", 23401 },
      { "MAGIC_CORRUPTION", "Corruption Blast", 19226 },
      { "MAGIC_SONIC_BOOM", "Sonic Wave", 27430 },
      { "MAGIC_CONCENTRATED_BLAST", "Concentrated Blast", 13309 },
      { "MAGIC_MAGMA_TEMPEST", "Magma Tempest", 15033 },
      { "MAGIC_IMPACT2", "Deep Impact", 22755 },
    }),
  },
  ranged = {
    major = list({
      { "RANGED_DEATHS_SWIFTNESS", "Death's Swiftness", 20185 },
      { "RANGED_UNLOAD", "Unload", 14253 },
      { "RANGED_HEADSHOT", "Deadshot", 23730 },
      { "RANGED_SHADOW_TENDRILS", "Shadow Tendrils", 20914 },
      { "RANGED_EXPLOSIVE_SHOT", "Incendiary Shot", 14252 },
    }),
    rotation = list({
      { "RANGED_RAPID_FIRE", "Rapid Fire", 14250 },
      { "RANGED_SNAP_SHOT", "Snap Shot", 23728 },
      { "RANGED_BOMBARDMENT", "Bombardment", 14251 },
      { "RANGED_CORRUPTION", "Corruption Shot", 17255 },
      { "RANGED_BINDING_SHOT", "Binding Shot", 14244 },
      { "RANGED_FRAGMENTATION_SHOT", "Fragmentation Shot", 14247 },
      { "RANGED_PUNCTURE_ARROW", "Salt the Wound", 30334 },
      { "RANGED_GALESHOT", "Galeshot", 23731 },
    }),
  },
  melee = {
    major = list({
      { "STRENGTH_BERSERK", "Berserk", 14264 },
      { "ATTACK_OVERPOWER", "Overpower", 14216 },
      { "ATTACK_METEOR_STRIKE", "Meteor Strike", 21363 },
      { "STRENGTH_PULVERISE", "Pulverise", 14266 },
      { "ATTACK_EVISCERATE", "Massacre", 14217 },
    }),
    rotation = list({
      { "STRENGTH_ASSAULT", "Assault", 14261 },
      { "ATTACK_WHIRLWIND", "Hurricane", 14215 },
      { "STRENGTH_DESTROY", "Destroy", 14263 },
      { "MELEE_DISMEMBER", "Dismember", 21239 },
      { "ATTACK_HAEMORRHAGE", "Slaughter", 14213 },
      { "ATTACK_CHARGE", "Barge", 14208 },
      { "ATTACK_FLURRY", "Flurry", 14214 },
      { "STRENGTH_QUAKE", "Quake", 14262 },
    }),
  },
}

-- The shared Utility group's keys, the same for every style.
presets.UTILITY = list({
  { "DEFENCE_FREEDOM", "Freedom", 14220 },
  { "DEFENCE_ANTICIPATION", "Anticipation", 14219 },
  { "DEFENCE_RESONANCE", "Resonance", 14222 },
  { "DEFENCE_DEVOTION", "Devotion", 21665 },
  { "DEFENCE_BARRICADE", "Barricade", 14228 },
  { "DEFENCE_REFLECT", "Reflect", 14225 },
  { "DEFENCE_DEBILITATE", "Debilitate", 14226 },
  { "DEFENCE_HEROISM", "Immortality", 14230 },
})

return presets
