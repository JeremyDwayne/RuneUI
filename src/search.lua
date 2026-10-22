-- The Buffs page search over src/catalog: which sources list a query's matches, and the effects a source lists.
-- Rows are { sprite, name, struct, source, kind, cause, info }, struct nil for an icon the catalog lacks, and kind
-- "buff" or "debuff" for one on you or "target" for one you inflict. Each call takes one kind. A boss's shared
-- effect is a second row for its struct, so All lists each struct once. Pure.
local search = {}

-- Sources listed before the bosses, in column order after All: the groups of effects on you, then the styles of
-- those you inflict.
local GROUPS = {
  "General",
  "Prayers",
  "Curses",
  "Abilities",
  "Magic",
  "Ranged",
  "Melee",
  "Necromancy",
  "Any style",
  "Weapons and items",
}
local GROUP_RANK = {}
for i, name in ipairs(GROUPS) do
  GROUP_RANK[name] = i
end

-- Whether row's effect, source or cause name holds query, a lowercase string, or query is "".
local function matches(row, query)
  if query == "" then
    return true
  end
  return row.name:lower():find(query, 1, true) ~= nil
    or row.source:lower():find(query, 1, true) ~= nil
    or (row.cause ~= nil and row.cause:lower():find(query, 1, true) ~= nil)
end

-- What identifies a row in All: its struct, or its sprite when it has none.
local function identity(row)
  return row.struct or -row.sprite
end

-- The catalog with each seen sprite it lacks for kind added to General, or to Any style for a debuff you
-- inflict, named by name(sprite) or "Unknown effect".
function search.withSeen(catalog, kind, seen, name)
  local listed = {}
  for _, row in ipairs(catalog) do
    if row.kind == kind then
      listed[row.sprite] = true
    end
  end
  local rows = { table.unpack(catalog) }
  local source = kind == "target" and "Any style" or "General"
  for _, sprite in ipairs(seen) do
    if not listed[sprite] then
      listed[sprite] = true
      rows[#rows + 1] = { sprite = sprite, name = name(sprite) or "Unknown effect", source = source, kind = kind }
    end
  end
  return rows
end

-- { name, count } for All, then each source with a row of kind matching query, ignoring case, in column order:
-- the groups, then bosses by name.
function search.sources(rows, kind, query)
  query = query:lower()
  local counts = {}
  local all = 0
  local inAll = {}
  for _, row in ipairs(rows) do
    if row.kind == kind and matches(row, query) then
      counts[row.source] = (counts[row.source] or 0) + 1
      local id = identity(row)
      if not inAll[id] then
        inAll[id] = true
        all = all + 1
      end
    end
  end
  local out = {}
  for source, count in pairs(counts) do
    out[#out + 1] = { name = source, count = count }
  end
  table.sort(out, function(a, b)
    local ra = GROUP_RANK[a.name] or #GROUPS + 1
    local rb = GROUP_RANK[b.name] or #GROUPS + 1
    if ra ~= rb then
      return ra < rb
    end
    return a.name < b.name
  end)
  table.insert(out, 1, { name = "All", count = all })
  return out
end

-- The rows of kind that source lists and that match query, ignoring case, sorted by name, each a copy with
-- tracked set when tracked, a { [sprite] = true } set, holds its sprite. "All" lists every source, each struct
-- once.
function search.rows(rows, kind, source, query, tracked)
  query = query:lower()
  local out = {}
  local inAll = {}
  for _, row in ipairs(rows) do
    local id = identity(row)
    local listed = source == "All" and not inAll[id] or row.source == source
    if row.kind == kind and listed and matches(row, query) then
      inAll[id] = true
      out[#out + 1] = {
        sprite = row.sprite,
        name = row.name,
        struct = row.struct,
        source = row.source,
        kind = row.kind,
        cause = row.cause,
        info = row.info,
        tracked = tracked[row.sprite] == true,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return identity(a) < identity(b)
  end)
  return out
end

return search
