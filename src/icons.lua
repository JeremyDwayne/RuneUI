-- Names buff and debuff icons for tooltips and the Buffs page. A sprite takes the name and struct the catalog
-- gives it, an item icon, minus its item id, takes the item's name, and a sprite the catalog lacks takes a label
-- made from its sprite config name. A named icon's description is read from its struct the first time it is
-- asked for. Pure: src/adapter supplies the client lookups.
local icons = {}

-- Combat style words that spriteLabel drops from the start of a label.
local STYLES = {
  ATTACK = true,
  COMBAT = true,
  CONSTITUTION = true,
  DEFENCE = true,
  MAGIC = true,
  MELEE = true,
  NECROMANCY = true,
  RANGED = true,
  STRENGTH = true,
}

-- A sprite config name as a title case label of the words after its first ICON, or nil when nothing is
-- left: DEBUFF_ICON_NECROMANCY_HAUNTED becomes "Haunted" and SPELL_ANCIENT_MAGICKS_ICON_SMOKE_CLOUD
-- becomes "Smoke Cloud".
function icons.spriteLabel(configName)
  local rest = configName:match("_ICON_(.*)$") or configName
  local words = {}
  for word in rest:gmatch("[^_]+") do
    if #words > 0 or not STYLES[word] then
      words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower()
    end
  end
  return #words > 0 and table.concat(words, " ") or nil
end

-- A struct name of the form "Name<br>text", "Name - text" or "Name: text" as the name and the text, or the
-- whole name alone: "Drenched - Each stack slows you." gives "Drenched" and "Each stack slows you.". The text
-- starts with a capital. A colon splits only before text of four words or more, so "Imbue: Shadows" stays whole.
-- A <nbsp> tag reads as a space.
function icons.split(name)
  name = name:gsub("<nbsp>", " ")
  local short, rest = name:match("^(.-)<br>(.+)$")
  if short ~= nil then
    while rest:sub(1, 4) == "<br>" do
      rest = rest:sub(5)
    end
  else
    short, rest = name:match("^(.-) %- (.+)$")
  end
  if short == nil then
    short, rest = name:match("^(.-): (.+)$")
    if short ~= nil and select(2, rest:gsub("%S+", "")) < 4 then
      short = nil
    end
  end
  if short == nil or short == "" or rest == "" then
    return name
  end
  return short, (rest:gsub("^%l", string.upper))
end

-- names: the catalog's { [sprite] = { name, struct } }. client: { spriteName(sprite), itemName(objID),
-- describe(structID) }, each returning a string or nil. Returns { info }: info(sprite) gives { name, info }, each
-- nil when nothing supplies it, and the same table on every ask.
function icons.index(names, client)
  local cache = {}
  local index = {}

  function index.info(sprite)
    local entry = cache[sprite]
    if entry ~= nil then
      return entry
    end
    entry = {}
    local known = names[sprite]
    if sprite < 0 then
      local item = client.itemName(-sprite)
      entry.name = item and (item:gsub(" %(%d+%)$", "")) or nil
    elseif known ~= nil then
      entry.name = known.name
      entry.info = client.describe(known.struct)
    else
      entry.name = icons.spriteLabel(client.spriteName(sprite) or "")
    end
    cache[sprite] = entry
    return entry
  end

  return index
end

return icons
