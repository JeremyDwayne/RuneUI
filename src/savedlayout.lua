-- Saved HUD layout: each element's position and anchor, and whether edit mode snaps. Pure: reads and writes
-- go through a store with get(key) and set(key, table), so specs use a fake.
local layout = require("src/layout")
local util = require("src/util")

local savedlayout = {}

local whole = util.whole

-- Offsets from the bottom center of the game window with full first rows: 6 major, 6 rotation, 8 utility and 8
-- Defensives tiles, and no spender rows. The major group sits on top, the rotation row under it with a frame either
-- side, then the adrenaline bar, the cast bar, utility and the custom groups stack centred below.
savedlayout.DEFAULT_POSITIONS = {
  major = { x = -110, y = -396, anchorX = 0.5, anchorY = 1 },
  rotation = { x = -140, y = -357, anchorX = 0.5, anchorY = 1 },
  player = { x = -390, y = -362, anchorX = 0.5, anchorY = 1 },
  target = { x = 140, y = -362, anchorX = 0.5, anchorY = 1 },
  resource = { x = -139, y = -332, anchorX = 0.5, anchorY = 1 },
  castbar = { x = -139, y = -292, anchorX = 0.5, anchorY = 1 },
  utility = { x = -127, y = -254, anchorX = 0.5, anchorY = 1 },
  custom1 = { x = -127, y = -224, anchorX = 0.5, anchorY = 1 },
  custom2 = { x = -151, y = -188, anchorX = 0.5, anchorY = 1 },
  custom3 = { x = -151, y = -146, anchorX = 0.5, anchorY = 1 },
  custom4 = { x = -151, y = -104, anchorX = 0.5, anchorY = 1 },
  targetDebuffs = { x = 109, y = -395, anchorX = 0.5, anchorY = 1 },
  playerDebuffs = { x = -393, y = -395, anchorX = 0.5, anchorY = 1 },
  upkeepBuffs = { x = -393, y = -308, anchorX = 0.5, anchorY = 1 },
  combatBuffs = { x = -192, y = -445, anchorX = 0.5, anchorY = 1 },
}
-- src/layout anchors matching DEFAULT_POSITIONS with full rows: everything hangs off the major group, so
-- dragging it moves them all. Utility hangs under the cast bar, so spender rows below the adrenaline bar push it
-- and the custom groups down.
savedlayout.DEFAULT_ANCHORS = {
  rotation = { target = "major", side = "bottom", align = "center", gap = 4, offset = 0 },
  player = { target = "rotation", side = "left", align = "center", gap = 0, offset = 0 },
  target = { target = "rotation", side = "right", align = "center", gap = 0, offset = 0 },
  resource = { target = "rotation", side = "bottom", align = "center", gap = 0, offset = 0 },
  castbar = { target = "resource", side = "bottom", align = "center", gap = 0, offset = 0 },
  utility = { target = "castbar", side = "bottom", align = "center", gap = 16, offset = 0 },
  custom1 = { target = "utility", side = "bottom", align = "center", gap = 0, offset = 0 },
  custom2 = { target = "custom1", side = "bottom", align = "center", gap = 6, offset = 0 },
  custom3 = { target = "custom2", side = "bottom", align = "center", gap = 6, offset = 0 },
  custom4 = { target = "custom3", side = "bottom", align = "center", gap = 6, offset = 0 },
  targetDebuffs = { target = "target", side = "top", align = "right", gap = 4, offset = 0 },
  playerDebuffs = { target = "player", side = "top", align = "left", gap = 4, offset = 0 },
  upkeepBuffs = { target = "player", side = "bottom", align = "left", gap = 2, offset = 0 },
  combatBuffs = { target = "major", side = "top", align = "center", gap = 10, offset = 0 },
}
-- The default major group's top sits this fraction of the window height above its bottom, below the
-- player's character, which the camera keeps near the middle of the window at any size.
local MAJOR_HEIGHT = 0.315
local POSITION_FIELDS = { "x", "y", "anchorX", "anchorY" }

-- A saved position with every field a number, as integers, or nil.
local function copyPosition(pos)
  if type(pos) ~= "table" then
    return nil
  end
  local copy = {}
  for _, field in ipairs(POSITION_FIELDS) do
    if type(pos[field]) ~= "number" then
      return nil
    end
    copy[field] = whole(pos[field])
  end
  return copy
end

-- A saved anchor naming a known element, side and alignment, or nil.
local function copyAnchor(anchor)
  if type(anchor) ~= "table" or savedlayout.DEFAULT_POSITIONS[anchor.target] == nil then
    return nil
  end
  local aligns = layout.ALIGNS[anchor.side]
  if aligns == nil or util.indexOf(aligns, anchor.align) == nil then
    return nil
  end
  if type(anchor.gap) ~= "number" or type(anchor.offset) ~= "number" then
    return nil
  end
  return {
    target = anchor.target,
    side = anchor.side,
    align = anchor.align,
    gap = whole(anchor.gap),
    offset = whole(anchor.offset),
  }
end

local function copyAnchors(saved)
  local anchors = {}
  for name in pairs(savedlayout.DEFAULT_POSITIONS) do
    anchors[name] = copyAnchor(saved[name])
  end
  return anchors
end

-- Whether following targets from name leads back to name.
local function cyclic(anchors, name)
  local seen = {}
  local at = anchors[name]
  while at ~= nil and not seen[at.target] do
    if at.target == name then
      return true
    end
    seen[at.target] = true
    at = anchors[at.target]
  end
  return false
end

-- Saved anchors without malformed entries or cycles, or the defaults when none were ever saved. An element
-- with neither a saved anchor nor a saved position has never been placed, such as one added since anchors
-- were saved, so it takes its default anchor; removing an anchor saves a position.
local function readAnchors(saved, positions)
  if type(saved) ~= "table" then
    return copyAnchors(savedlayout.DEFAULT_ANCHORS)
  end
  local anchors = copyAnchors(saved)
  for name, default in pairs(savedlayout.DEFAULT_ANCHORS) do
    if saved[name] == nil and positions[name] == nil then
      anchors[name] = copyAnchor(default)
    end
  end
  local looped = {}
  for name in pairs(anchors) do
    looped[name] = cyclic(anchors, name)
  end
  for name, dropped in pairs(looped) do
    if dropped then
      anchors[name] = nil
    end
  end
  return anchors
end

local function readPositions(saved)
  local positions = {}
  if type(saved) ~= "table" then
    return positions
  end
  for name in pairs(savedlayout.DEFAULT_POSITIONS) do
    positions[name] = copyPosition(saved[name])
  end
  return positions
end

-- DEFAULT_POSITIONS raised or lowered together so the major group sits MAJOR_HEIGHT of windowHeight above the
-- bottom. With no windowHeight they are DEFAULT_POSITIONS as written.
local function defaultPositions(windowHeight)
  if windowHeight == nil then
    return savedlayout.DEFAULT_POSITIONS
  end
  local shift = -math.floor(windowHeight * MAJOR_HEIGHT + 0.5) - savedlayout.DEFAULT_POSITIONS.major.y
  local out = {}
  for name, pos in pairs(savedlayout.DEFAULT_POSITIONS) do
    out[name] = { x = pos.x, y = pos.y + shift, anchorX = pos.anchorX, anchorY = pos.anchorY }
  end
  return out
end

-- Loads the layout from store, dropping malformed values. windowHeight, the game window's height in UI units,
-- places the default HUD; specs leave it out.
function savedlayout.load(store, windowHeight)
  local defaults = defaultPositions(windowHeight)
  local positions = readPositions(store.get("layout"))
  local anchors = readAnchors(store.get("anchors"), positions)
  local savedEditMode = store.get("editMode")
  local editMode = { snap = type(savedEditMode) ~= "table" or savedEditMode.snap ~= false }

  local s = {}

  -- Every element's position, saved or default.
  function s.positions()
    local out = {}
    for name, default in pairs(defaults) do
      out[name] = positions[name] or default
    end
    return out
  end

  function s.setPosition(name, pos)
    positions[name] = copyPosition(pos)
    store.set("layout", positions)
  end

  -- Restores the default positions and anchors.
  function s.resetPositions()
    positions = {}
    anchors = copyAnchors(savedlayout.DEFAULT_ANCHORS)
    store.set("layout", positions)
    store.set("anchors", anchors)
  end

  -- { [name] = src/layout anchor } for every anchored element.
  function s.anchors()
    return anchors
  end

  -- Anchors name by a src/layout anchor, or unanchors it when anchor is nil. The caller checks
  -- layout.canAnchor first.
  function s.setAnchor(name, anchor)
    anchors[name] = copyAnchor(anchor)
    store.set("anchors", anchors)
  end

  -- Whether edit mode snaps drags and draws its grid.
  function s.snap()
    return editMode.snap
  end

  function s.setSnap(on)
    editMode.snap = on
    store.set("editMode", editMode)
  end

  return s
end

return savedlayout
