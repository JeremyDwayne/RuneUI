-- Builds the party grid's display model from the game's group window, the players in view and the saved roles
-- and tier settings. Pure: no client calls, so specs drive it with fake reads from src/adapter's shape.
local frames = require("src/frames")
local util = require("src/util")

local party = {}

-- Group size tiers, smallest first, each with the largest group it covers and its name on the Party page.
party.TIERS = {
  { id = "duo", label = "Duo", upTo = 2 },
  { id = "party", label = "Party", upTo = 5 },
  { id = "large", label = "Large", upTo = 7 },
  { id = "raid", label = "Raid" },
}
-- Each tier's cell width and height, cells per row, and whether the player's own cell shows.
party.TIER_DEFAULTS = {
  duo = { w = 112, h = 46, columns = 2, showSelf = false },
  party = { w = 84, h = 40, columns = 5, showSelf = false },
  large = { w = 80, h = 38, columns = 4, showSelf = false },
  raid = { w = 66, h = 22, columns = 5, showSelf = true },
}
-- The most cells the grid shows, and the space between two.
party.MAX_CELLS = 30
party.GAP = 2
-- The tag that marks the base tank, and its name on a cell's hover.
party.BASE_TANK = "BT"
-- A cell under this share of its lifepoints is low.
local LOW = 0.3

-- name as roles and the players in view are matched by: lower case, with the game's other spaces as a space.
function party.key(name)
  return (name:gsub("\u{A0}", " "):gsub("[\xA0_]", " "):lower())
end

-- The id of the tier a group of size members falls in.
function party.tier(size)
  for _, tier in ipairs(party.TIERS) do
    if tier.upTo == nil or size <= tier.upTo then
      return tier.id
    end
  end
end

-- tiers with every tier showing the player's own cell.
function party.withSelf(tiers)
  local out = {}
  for id, tier in pairs(tiers) do
    out[id] = { w = tier.w, h = tier.h, columns = tier.columns, showSelf = true }
  end
  return out
end

-- The tag roles gives name: the active preset's, or the name's default. roles: { defaults, preset }, each
-- { [party.key(name)] = tag }, with preset nil while none is active.
function party.tag(roles, name)
  local key = party.key(name)
  return roles.preset and roles.preset[key] or roles.defaults[key]
end

-- Current and maximum lifepoints from a row's "current/max" text, or nil.
local function parse(text)
  local current, max = (text or ""):match("^(%d+)/(%d+)$")
  current, max = tonumber(current), tonumber(max)
  if max ~= nil and max > 0 then
    return current, max
  end
end

-- Tracks the group between server ticks. near(name, inView) follows a player entering or leaving view, and
-- read(reads) takes each tick's src/adapter groupReads, keeping the last roster while the window is closed.
-- members() lists that roster.
-- model(own, tiers, roles) returns the grid: own is { name, lifepoints, max } for the player, tiers is
-- { [tier id] = { w, h, columns, showSelf } } and roles is as party.tag takes. The model is { hidden } with
-- nothing to show, else { tier, raid, closed, w, h, columns, width, height, cells }, with cells a list of
-- { name, x, y, tag, role, leader, fill, text, state, far, lifepoints }: fill is nil for a member whose
-- lifepoints are unknown, text is nil in a Raid cell, state is "low", "dead" or nil, leader is the rank sprite
-- of the group's leader, and role and lifepoints are the hover's lines.
function party.tracker()
  local t = {}
  local rows = {}
  local leader = nil
  local open = false
  -- How many entities in view carry each name, by party.key.
  local inView = {}

  function t.near(name, isNear)
    if name == nil then
      return
    end
    local key = party.key(name)
    inView[key] = math.max(0, (inView[key] or 0) + (isNear and 1 or -1))
  end

  function t.read(reads)
    open = reads.open
    if open then
      rows = reads.rows
      local name = reads.title and reads.title:match("^(.*)'s group$")
      leader = name and party.key(name)
    end
  end

  -- The members in the window's order as { name, leader }, leader being the leader's rank sprite, for the
  -- Party page.
  function t.members()
    local out = {}
    for i, row in ipairs(rows) do
      out[i] = { name = row.name, leader = party.key(row.name) == leader and row.rank or nil }
    end
    return out
  end

  local function cell(row, own, roles, raid)
    local key = party.key(row.name)
    local isSelf = own.name ~= nil and key == party.key(own.name)
    local current, max = parse(row.lifepoints)
    if isSelf and own.lifepoints ~= nil then
      current, max = own.lifepoints, own.max or max
    elseif not open then
      current = nil
    end
    local known = current ~= nil and max ~= nil
    local tag = party.tag(roles, row.name)
    local c = {
      name = row.name,
      tag = tag,
      role = tag == party.BASE_TANK and "Base tank" or tag,
      leader = key == leader and row.rank or nil,
      far = not isSelf and (inView[key] or 0) == 0,
    }
    if known then
      c.fill = util.clamp(current / max, 0, 1)
      c.lifepoints = frames.withCommas(current) .. " / " .. frames.withCommas(max)
      c.state = current == 0 and "dead" or current / max < LOW and "low" or nil
    end
    if not raid then
      c.text = c.far and "Far" or not known and "" or c.state == "dead" and "Dead" or frames.formatAmount(current)
    end
    return c, isSelf
  end

  function t.model(own, tiers, roles)
    local id = party.tier(#rows)
    local tier = tiers[id]
    local raid = id == "raid"
    local cells = {}
    for _, row in ipairs(rows) do
      local c, isSelf = cell(row, own, roles, raid)
      if (tier.showSelf or not isSelf) and #cells < party.MAX_CELLS then
        cells[#cells + 1] = c
      end
    end
    if #cells == 0 then
      return { hidden = true }
    end
    local columns = math.min(tier.columns, #cells)
    for i, c in ipairs(cells) do
      c.x = (i - 1) % columns * (tier.w + party.GAP)
      c.y = (i - 1) // columns * (tier.h + party.GAP)
    end
    local lines = (#cells - 1) // columns + 1
    return {
      hidden = false,
      tier = id,
      raid = raid,
      closed = not open,
      w = tier.w,
      h = tier.h,
      columns = columns,
      width = columns * (tier.w + party.GAP) - party.GAP,
      height = lines * (tier.h + party.GAP) - party.GAP,
      cells = cells,
    }
  end

  return t
end

return party
