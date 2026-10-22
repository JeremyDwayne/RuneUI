-- The Buffs page search over src/catalog: which sources list a query's matches, and the effects a source lists.
-- Rows are { sprite, name, struct, source, cause }, struct nil for an icon the catalog lacks. A boss's shared
-- effect is a second row for its struct, so All lists each struct once. Pure.
local search = {}

-- Sources listed before the bosses, in column order after All.
local GROUPS = { "General", "Prayers", "Curses", "Abilities", "Spells" }
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

-- The catalog with each seen sprite it lacks added to General, named by name(sprite) or "Unknown effect".
function search.withSeen(catalog, seen, name)
  local listed = {}
  for _, row in ipairs(catalog) do
    listed[row.sprite] = true
  end
  local rows = { table.unpack(catalog) }
  for _, sprite in ipairs(seen) do
    if not listed[sprite] then
      listed[sprite] = true
      rows[#rows + 1] = { sprite = sprite, name = name(sprite) or "Unknown effect", source = "General" }
    end
  end
  return rows
end

-- { name, count } for All, then each source with a row matching query, ignoring case, in column order: the
-- groups, then bosses by name.
function search.sources(rows, query)
  query = query:lower()
  local counts = {}
  local all = 0
  local inAll = {}
  for _, row in ipairs(rows) do
    if matches(row, query) then
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

-- The rows source lists that match query, ignoring case, sorted by name, each a copy with tracked set when
-- tracked, a { [sprite] = true } set, holds its sprite. "All" lists every source, each struct once.
function search.rows(rows, source, query, tracked)
  query = query:lower()
  local out = {}
  local inAll = {}
  for _, row in ipairs(rows) do
    local id = identity(row)
    if (source == "All" and not inAll[id] or row.source == source) and matches(row, query) then
      inAll[id] = true
      out[#out + 1] = {
        sprite = row.sprite,
        name = row.name,
        struct = row.struct,
        source = row.source,
        cause = row.cause,
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
