-- The debuffs each debuff row tracks by default, and the Buffs page's groups. Pure: settings supplies the
-- saved choices.
local auralists = {}

-- Debuffs a player applies to the target and keeps up or times, by sprite.
auralists.TARGET_DEFAULTS = {
  [30100] = true, -- Death Mark
  [30098] = true, -- Bloated
  [30212] = true, -- Haunted
  [14771] = true, -- Smoke Cloud
  [14395] = true, -- Vulnerability
  [14371] = true, -- Enfeeble
  [21239] = true, -- Dismember
  [21362] = true, [14213] = true, -- Slaughter
  [21296] = true, [14217] = true, -- Massacre
  [23401] = true, -- Combust
  [19226] = true, -- Corruption Blast
  [17255] = true, -- Corruption Shot
  [30372] = true, -- Soulfire
  [26103] = true, -- Stunned
  [14392] = true, -- Bound
  [33146] = true, -- Shattering bones
  [14266] = true, -- Pulverised
  [34998] = true, -- Flamebound Rival
  [15038] = true, -- Greater Chain
  [15037] = true, -- Chain
  [14226] = true, -- Debilitate
  [30097] = true, -- Poisoned
  [19118] = true, -- Evolving Toxin
  [30335] = true, -- Punctured
}

-- Debuffs on the player that call for a reaction, by sprite.
auralists.PLAYER_DEFAULTS = {
  [26103] = true, -- Stunned
  [14392] = true, -- Bound
  [14415] = true, -- Frozen
  [26343] = true, -- Protection prayers disabled
  [33964] = true, -- Enervated
  [30097] = true, -- Poisoned
  [21239] = true, -- Bleeding and NPC bleeds
  [15922] = true, -- Freezing Blood
  [9881] = true, -- Hoary Chill, Frostbite
  [14235] = true, -- Flames of Zamorak, Shadow Tear
  [20293] = true, -- Choking
  [35063] = true, -- Apmeken's Burden
  [30722] = true, -- Corruption, Corrupted
  [800] = true, [1084] = true, [33040] = true, [9150] = true, -- Telos viruses
  [30024] = true, -- Drenched
  [30721] = true, -- Searing Pain, Soul drained
  [29249] = true, -- Blight
  [29251] = true, -- Withering
  [30096] = true, -- Geothermal Burn
  [9882] = true, -- Corrosion
  [25240] = true, -- Bitten
  [25241] = true, -- Fatigued
  [25831] = true, [25832] = true, [25833] = true, [25834] = true, [25836] = true, [25837] = true, -- Stat Reduced
  [30213] = true, -- Necromancy Stat Reduced
  [33976] = true, -- Resurrection Sickness
}

local DEFAULTS = { target = auralists.TARGET_DEFAULTS, player = auralists.PLAYER_DEFAULTS }
local CATEGORIES = { "combat", "upkeep", "hidden" }

-- Whether a debuff row of kind, "target" or "player", shows sprite. choices: settings' { [tostring(sprite)] =
-- true | false | "seen" }; a sprite seen but never chosen, or never seen, takes its default.
function auralists.tracked(kind, choices, sprite)
  local choice = choices[tostring(sprite)]
  if type(choice) == "boolean" then return choice end
  return DEFAULTS[kind][sprite] == true
end

local function sorted(set)
  local list = {}
  for sprite in pairs(set) do list[#list + 1] = sprite end
  table.sort(list)
  return list
end

-- The Buffs page's groups, each a list of sprites sorted by id. categories: settings' buff rows by
-- tostring(sprite). choices: { target, player }, each settings' tracked choices. Returns { combat, upkeep,
-- hidden, target = { tracked, untracked }, player = { tracked, untracked } }; a debuff kind lists every
-- sprite seen or on its defaults.
function auralists.groups(categories, choices)
  local groups = {}
  local buckets = {}
  for _, name in ipairs(CATEGORIES) do buckets[name] = {} end
  for key, category in pairs(categories) do
    if buckets[category] ~= nil then buckets[category][tonumber(key)] = true end
  end
  for _, name in ipairs(CATEGORIES) do groups[name] = sorted(buckets[name]) end
  for kind, defaults in pairs(DEFAULTS) do
    local tracked, untracked = {}, {}
    local function place(sprite)
      if auralists.tracked(kind, choices[kind], sprite) then tracked[sprite] = true else untracked[sprite] = true end
    end
    for sprite in pairs(defaults) do place(sprite) end
    for key in pairs(choices[kind]) do place(tonumber(key)) end
    groups[kind] = { tracked = sorted(tracked), untracked = sorted(untracked) }
  end
  return groups
end

return auralists
