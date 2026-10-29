-- Writes src/catalog.lua from a struct dump and tools/catalog_sources.lua. Run from the repo root:
--
--   lua5.4 tools/catalog.lua <dump.tsv>
--
-- The dump is tab separated with a header row naming at least id, configName, icon, spriteName and name: one
-- row per COMBATV2_ or MAGIC_ struct with an icon and a name. Warnings go to stderr: a boss token no struct
-- matches, a shared or inflicted effect naming a struct the dump lacks, and names still too long to read as a
-- name. The output keeps one row per line, so .styluaignore leaves it unformatted.
local icons = require("src/icons")
local sources = require("tools/catalog_sources")

local OUTPUT = "src/catalog.lua"
-- A name longer than this after splitting reads as a sentence and wants a hand name.
local LONG_NAME = 36

local function warn(...)
  io.stderr:write(table.concat({ ... }, " "), "\n")
end

-- The fields of one tab separated line, empty ones included.
local function fields(line)
  local out = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do
    out[#out + 1] = field
  end
  return out
end

-- Every dump row as { struct, configName, icon, spriteName, name }, skipping rows with no icon or name.
local function readDump(path)
  local file = assert(io.open(path, "r"))
  local columns = {}
  for i, column in ipairs(fields(file:read("l"))) do
    columns[column] = i
  end
  for _, column in ipairs({ "id", "configName", "icon", "spriteName", "name" }) do
    assert(columns[column], "the dump has no " .. column .. " column")
  end
  local rows = {}
  for line in file:lines() do
    local f = fields(line)
    local icon = tonumber(f[columns.icon])
    local name = f[columns.name]
    if icon ~= nil and icon > 0 and name ~= nil and name ~= "" then
      rows[#rows + 1] = {
        struct = tonumber(f[columns.id]),
        configName = f[columns.configName],
        icon = icon,
        spriteName = f[columns.spriteName],
        name = name,
      }
    end
  end
  file:close()
  return rows
end

-- Whether configName holds any of tokens.
local function holds(configName, tokens)
  for _, token in ipairs(tokens) do
    if configName:find(token, 1, true) then
      return true
    end
  end
  return false
end

-- The source and kind a struct lists under, or nil when it is left out, counting each boss token it matches
-- in hits. A boss's struct is a debuff on you unless it names a boss buff; any other is a buff on you unless
-- it names a debuff.
local function sourceOf(configName, hits)
  if holds(configName, sources.left) then
    return nil
  end
  if configName:sub(1, 6) == "MAGIC_" then
    if sources.spells[configName] then
      return "General", "buff"
    end
    return nil
  end
  local kind = holds(configName, sources.debuffs) and "debuff" or "buff"
  if holds(configName, sources.general) then
    return "General", kind
  end
  for _, rule in ipairs(sources.bosses) do
    if configName:find(rule.token, 1, true) then
      hits[rule.token] = (hits[rule.token] or 0) + 1
      return rule.boss, holds(configName, sources.bossBuffs) and "buff" or "debuff"
    end
  end
  for _, group in ipairs(sources.groups) do
    if configName:sub(1, #group.prefix) == group.prefix then
      return group.source, kind
    end
  end
  return "General", kind
end

-- The rows of debuffs you inflict, by their struct's config name.
local function inflictedRows()
  local out = {}
  for _, row in ipairs(sources.inflicted) do
    out[row.effect] = row
  end
  return out
end

-- How well a dump row names its icon, lower is better: 1 when every word of its name is a word of the sprite's
-- config name, as "Poisoned" for DEBUFF_ICON_POISONED, 2 for a debuff struct, 3 for a struct the catalog lists
-- and 4 for the rest. Ties go to the lowest struct id.
local function rank(d, name, listed)
  local words = {}
  for word in d.spriteName:lower():gmatch("[^_]+") do
    words[word] = true
  end
  local any = false
  local all = true
  for word in name:lower():gmatch("%a+") do
    any = true
    if not words[word] then
      all = false
    end
  end
  if any and all then
    return 1
  end
  if d.configName:sub(1, 16) == "COMBATV2_DEBUFF_" then
    return 2
  end
  return listed[d.struct] and 3 or 4
end

-- The best name and struct for every icon in the dump, { [sprite] = { name, struct } }, preferring the struct
-- rank puts first. names holds each struct's display name and listed the structs the catalog rows list.
local function bestNames(dump, names, listed)
  local best = {}
  for _, d in ipairs(dump) do
    local r = rank(d, names[d.struct], listed)
    local held = best[d.icon]
    if held == nil or r < held.rank or (r == held.rank and d.struct < held.struct) then
      best[d.icon] = { name = names[d.struct], struct = d.struct, rank = r }
    end
  end
  return best
end

local function build(dump)
  local rows = {}
  local seen = {}
  local hits = {}
  local inflicted = inflictedRows()
  -- Each struct's row by config name, for the shared and inflicted effects, its display name by id, and the
  -- structs a row lists.
  local byName = {}
  local nameOf = {}
  local listed = {}
  for _, d in ipairs(dump) do
    local hand = sources.names[d.configName]
    local name = (hand or icons.split(d.name)):match("^%s*(.-)%s*$")
    nameOf[d.struct] = name
    -- A struct named by a sentence keeps the sentence as its description.
    local info = hand ~= nil and hand ~= d.name and d.name or nil
    local source, kind = sourceOf(d.configName, hits)
    byName[d.configName] = { sprite = d.icon, name = name, struct = d.struct, info = info }
    -- A debuff you inflict lists on you too only when players suffer it as well, as Stunned.
    if inflicted[d.configName] and not inflicted[d.configName].onYou then
      source = nil
    end
    local key = source and table.concat({ d.icon, name, source, kind }, "\t")
    if key and not seen[key] then
      seen[key] = true
      listed[d.struct] = true
      rows[#rows + 1] = { sprite = d.icon, name = name, struct = d.struct, source = source, kind = kind, info = info }
      if #name > LONG_NAME then
        warn("long name:", d.configName, name)
      end
    end
  end
  for _, rule in ipairs(sources.bosses) do
    if hits[rule.token] == nil then
      warn("no struct matches boss token", rule.token)
    end
  end
  for _, shared in ipairs(sources.shared) do
    local own = byName[shared.effect]
    if own == nil then
      warn("no struct", shared.effect, "for", shared.boss)
    else
      rows[#rows + 1] = {
        sprite = own.sprite,
        name = own.name,
        struct = own.struct,
        source = shared.boss,
        kind = "debuff",
        cause = shared.cause,
      }
    end
  end
  for _, row in ipairs(sources.inflicted) do
    local own = byName[row.effect]
    if own == nil then
      warn("no struct", row.effect, "inflicted by", row.cause)
    else
      rows[#rows + 1] = {
        sprite = own.sprite,
        name = own.name,
        struct = own.struct,
        source = row.style,
        kind = "target",
        cause = row.cause,
        info = own.info,
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    if a.source ~= b.source then
      return a.source < b.source
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.struct < b.struct
  end)
  return rows, bestNames(dump, nameOf, listed)
end

local function write(rows, names)
  local out = {
    "-- Plain data, no logic: the names and icons of the game's buff and debuff structs, read from the game's own",
    "-- configs. Generated by tools/catalog.lua in the source repository from a dump of those structs and the",
    "-- hand-kept boss and ability lists in tools/catalog_sources.lua. Edit those, not this.",
    "-- rows lists every buff and debuff struct with an icon and a name for the Buffs page search, as { sprite,",
    "-- name, struct, source, kind, cause, info }: kind is buff or debuff on you, or target for a debuff you",
    "-- inflict. Source is General, Prayers, Curses, Abilities or a boss on you, and a combat style or Weapons and",
    "-- items on a target. Cause is the attack behind a boss's shared effect or the ability, spell or item that",
    "-- inflicts one, and info the sentence a struct is named by in the game, when it has a short name here.",
    "-- names gives each icon the name and struct id of the struct that best names it, for tooltips.",
    "return {",
    "  rows = {",
  }
  for _, r in ipairs(rows) do
    local cause = r.cause and string.format(", cause = %q", r.cause) or ""
    local info = r.info and string.format(", info = %q", r.info) or ""
    out[#out + 1] = string.format(
      "    { sprite = %d, name = %q, struct = %d, source = %q, kind = %q%s%s },",
      r.sprite,
      r.name,
      r.struct,
      r.source,
      r.kind,
      cause,
      info
    )
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "  names = {"
  local sprites = {}
  for sprite in pairs(names) do
    sprites[#sprites + 1] = sprite
  end
  table.sort(sprites)
  for _, sprite in ipairs(sprites) do
    local n = names[sprite]
    out[#out + 1] = string.format("    [%d] = { name = %q, struct = %d },", sprite, n.name, n.struct)
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  local file = assert(io.open(OUTPUT, "w"))
  file:write(table.concat(out, "\n"), "\n")
  file:close()
end

local path = arg[1]
assert(path, "usage: lua5.4 tools/catalog.lua <dump.tsv>")
local rows, names = build(readDump(path))
write(rows, names)
local count = 0
for _ in pairs(names) do
  count = count + 1
end
print(string.format("wrote %d rows and %d names to %s", #rows, count, OUTPUT))
