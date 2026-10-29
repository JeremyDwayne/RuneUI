-- The debuffs each debuff row tracks by default, and the Buffs page's groups. Pure: settings supplies the
-- saved choices.
local editor = require("src/editor")
local util = require("src/util")

local auralists = {}

local indexOf = util.indexOf

-- Debuffs a player applies to the target and keeps up or times, by sprite, most important first.
auralists.TARGET_DEFAULTS = {
  14395, -- Vulnerability
  30100, -- Death Mark
  30098, -- Bloated
  14771, -- Smoke Cloud
  30212, -- Haunted
  21239, -- Dismember
  21362, -- Slaughter
  14213, -- Slaughter
  21296, -- Massacre
  14217, -- Massacre
  23401, -- Combust
  19226, -- Corruption Blast
  17255, -- Corruption Shot
  30372, -- Soulfire
  26103, -- Stunned
  14392, -- Bound
  33146, -- Shattering bones
  14266, -- Pulverised
  14371, -- Enfeeble
  34998, -- Flamebound Rival
  15038, -- Greater Chain
  15037, -- Chain
  14226, -- Debilitate
  30097, -- Poisoned
  19118, -- Evolving Toxin
  30335, -- Punctured
}

-- Debuffs on the player that call for a reaction, by sprite, most important first.
auralists.PLAYER_DEFAULTS = {
  26103, -- Stunned
  14392, -- Bound
  14415, -- Frozen
  26343, -- Protection prayers disabled
  33964, -- Enervated
  30097, -- Poisoned
  21239, -- Bleeding and NPC bleeds
  15922, -- Freezing Blood
  9881, -- Hoary Chill, Frostbite
  14235, -- Flames of Zamorak, Shadow Tear
  20293, -- Choking
  35063, -- Apmeken's Burden
  30722, -- Corruption, Corrupted
  800, -- Red virus
  1084, -- Green virus
  33040, -- Blue virus
  9150, -- Telos viruses
  30024, -- Drenched
  30721, -- Searing Pain, Soul drained
  29249, -- Blight
  29251, -- Withering
  30096, -- Geothermal Burn
  9882, -- Corrosion
  25240, -- Bitten
  25241, -- Fatigued
  25831, -- Attack Stat Reduced
  25832, -- Strength Stat Reduced
  25833, -- Defence Stat Reduced
  25834, -- Ranged Stat Reduced
  25836, -- Magic Stat Reduced
  25837, -- Stat Reduced
  30213, -- Necromancy Stat Reduced
  33976, -- Resurrection Sickness
}

-- { [sprite] = position } for a list of sprites.
local function positions(list)
  local out = {}
  for i, sprite in ipairs(list) do
    out[sprite] = i
  end
  return out
end

-- Each debuff kind's defaults as { [sprite] = importance }.
local DEFAULTS = { target = positions(auralists.TARGET_DEFAULTS), player = positions(auralists.PLAYER_DEFAULTS) }
local CATEGORIES = { "combat", "upkeep", "hidden" }

-- Whether a debuff row of kind, "target" or "player", shows sprite. choices: settings' { [tostring(sprite)] =
-- true | false | "seen" }; a sprite seen but never chosen, or never seen, takes its default.
function auralists.tracked(kind, choices, sprite)
  local choice = choices[tostring(sprite)]
  if type(choice) == "boolean" then
    return choice
  end
  return DEFAULTS[kind][sprite] ~= nil
end

-- The sprites of set in display order: by position in saved, then by position in defaults, then by id.
local function ordered(set, saved, defaults)
  local savedAt = positions(saved or {})
  local list = {}
  for sprite in pairs(set) do
    list[#list + 1] = sprite
  end
  local huge = math.huge
  table.sort(list, function(a, b)
    local sa = savedAt[a] or huge
    local sb = savedAt[b] or huge
    if sa ~= sb then
      return sa < sb
    end
    local da = defaults[a] or huge
    local db = defaults[b] or huge
    if da ~= db then
      return da < db
    end
    return a < b
  end)
  return list
end

-- The sprites of order that set holds, in order.
local function filter(order, set)
  local list = {}
  for _, sprite in ipairs(order) do
    if set[sprite] then
      list[#list + 1] = sprite
    end
  end
  return list
end

-- The Buffs page's groups, each a list of sprites in display order. categories: settings' buff rows by
-- tostring(sprite). choices: { target, player }, each settings' tracked choices. orders: { buffs, target,
-- player }, each a kind's saved order, any of them nil. Returns { combat, upkeep, hidden, target = { tracked,
-- untracked }, player = { tracked, untracked }, order = { buffs, target, player } }: a debuff kind lists every
-- sprite seen or on its defaults, and order holds each kind's full display order.
function auralists.groups(categories, choices, orders)
  local groups = { order = {} }
  local members = {}
  local all = {}
  for _, name in ipairs(CATEGORIES) do
    members[name] = {}
  end
  for key, category in pairs(categories) do
    local sprite = tonumber(key)
    members[category][sprite] = true
    all[sprite] = true
  end
  groups.order.buffs = ordered(all, orders.buffs, {})
  for _, name in ipairs(CATEGORIES) do
    groups[name] = filter(groups.order.buffs, members[name])
  end
  for kind, defaults in pairs(DEFAULTS) do
    local tracked = {}
    local untracked = {}
    local seen = {}
    local function place(sprite)
      seen[sprite] = true
      if auralists.tracked(kind, choices[kind], sprite) then
        tracked[sprite] = true
      else
        untracked[sprite] = true
      end
    end
    for sprite in pairs(defaults) do
      place(sprite)
    end
    for key in pairs(choices[kind]) do
      place(tonumber(key))
    end
    local order = ordered(seen, orders[kind], defaults)
    groups.order[kind] = order
    groups[kind] = { tracked = filter(order, tracked), untracked = filter(order, untracked) }
  end
  return groups
end

-- { buffs, target, player }, each { [sprite] = position } in that kind's display order, from groups(...).
function auralists.ranks(groups)
  return {
    buffs = positions(groups.order.buffs),
    target = positions(groups.order.target),
    player = positions(groups.order.player),
  }
end

-- Dropping sprite on target, a src/editor dropTarget result, in list, the group under the cursor in display
-- order. order is the kind's full display order. Returns { order, other }: the kind's new order, and for a
-- swap the sprite it traded places with, which takes sprite's old group. Returns nil for a drop that leaves
-- sprite where it is or lands on no icon.
function auralists.drop(order, list, sprite, target)
  local action = editor.dropAction(list, sprite, target)
  if action == nil then
    return nil
  end
  local out = {}
  for i, s in ipairs(order) do
    out[i] = s
  end
  if action.op == "swap" then
    local a = indexOf(out, sprite)
    local b = indexOf(out, action.other)
    out[a], out[b] = action.other, sprite
    return { order = out, other = action.other }
  end
  local rest = {}
  for _, s in ipairs(list) do
    if s ~= sprite then
      rest[#rest + 1] = s
    end
  end
  if #rest == 0 then
    return { order = out }
  end
  table.remove(out, indexOf(out, sprite))
  local before = rest[action.index]
  if before ~= nil then
    table.insert(out, indexOf(out, before), sprite)
  else
    table.insert(out, indexOf(out, rest[#rest]) + 1, sprite)
  end
  return { order = out }
end

return auralists
