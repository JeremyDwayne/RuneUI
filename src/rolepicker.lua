-- The role picker: a popup that sets one group member's tag. A field for a typed tag sits at the top, then Base
-- tank and None, then each boss's tags as tiles under its name. It sits on the plugin layer that draws over
-- game windows, builds as it opens and is destroyed on the tick after it closes, so it holds none of that
-- layer's ids while closed.
local controls = require("src/controls")
local draw = require("src/draw")
local party = require("src/party")
local savedparty = require("src/savedparty")
local util = require("src/util")

local rolepicker = {}

local PAD = 8
local GAP = 4
local COLUMNS = 4
local TILE_W = 42
local TILE_H = 20
local INNER = COLUMNS * TILE_W + (COLUMNS - 1) * GAP
local TITLE_H = 20
local FIELD_H = 24
local HEAD_H = 16

-- Lays the picker out for bosses, a list of { name, tags }. Returns { w, h, field, tiles, heads }: field is the
-- tag field's box, tiles each { x, y, w, h, label, tag } with tag false for None, and heads each boss name's
-- { text, x, y, w, h }.
function rolepicker.layout(bosses)
  local tiles, heads = {}, {}
  local y = PAD + TITLE_H + GAP
  local field = { x = PAD, y = y, w = INNER, h = FIELD_H }
  y = y + FIELD_H + GAP
  -- Adds a tile per tag, COLUMNS to a row, and moves y below them.
  local function rows(tags)
    for i, tag in ipairs(tags) do
      local column = (i - 1) % COLUMNS
      if i > 1 and column == 0 then
        y = y + TILE_H + GAP
      end
      local x = PAD + column * (TILE_W + GAP)
      tiles[#tiles + 1] = { x = x, y = y, w = TILE_W, h = TILE_H, label = tag or "None", tag = tag }
    end
    y = y + TILE_H + GAP
  end
  rows({ party.BASE_TANK, false })
  for _, boss in ipairs(bosses) do
    heads[#heads + 1] = { text = boss.name, x = PAD, y = y, w = INNER, h = HEAD_H }
    y = y + HEAD_H
    rows(boss.tags)
  end
  return { w = INNER + 2 * PAD, h = y - GAP + PAD, field = field, tiles = tiles, heads = heads }
end

-- root is the plugin layer that draws over game windows. deps: { saved = src/settings, bosses = the list
-- rolepicker.layout takes, refresh = function redrawing the HUD }. Returns { open(name, x, y), close(), isOpen(),
-- tick() }: open shows the picker for the member called name with its corner at x, y on the screen, moved to
-- stay on it. A click on a tile saves that tag as the Party page does and closes it. A typed tag is saved as it
-- is typed, and Enter closes it, as does its X or a click anywhere else. close hides it, since it runs inside
-- the picker's own hooks, and tick, run each server tick, destroys what close hid.
function rolepicker.create(root, deps)
  local saved = deps.saved
  local layout = rolepicker.layout(deps.bosses)
  local W = draw.WINDOW
  -- The open picker's layer and the screen-wide hit area under it, or nil, and the closed one's until a tick
  -- destroys them.
  local shown = nil
  local closed = nil
  local picker = {}

  function picker.isOpen()
    return shown ~= nil
  end

  function picker.tick()
    if closed ~= nil then
      closed.layer:Destroy()
      closed.catcher:Destroy()
      closed = nil
    end
  end

  function picker.close()
    if shown ~= nil then
      draw.set(shown.layer, "hidden", true)
      draw.set(shown.catcher, "hidden", true)
      picker.tick()
      closed, shown = shown, nil
    end
  end

  function picker.open(name, x, y)
    picker.close()
    picker.tick()
    local rootW, rootH = tonumber(root.width) or 0, tonumber(root.height) or 0
    local catcher = draw.hitArea(draw.rect(root, W.border, 0, 0, rootW, rootH))
    draw.set(catcher, "alpha", 0)
    draw.on(catcher, "ONCLICK", picker.close)
    local layer = draw.new(ui.Layer, root)
    draw.pos(layer, util.clamp(x, 0, math.max(0, rootW - layout.w)), util.clamp(y, 0, math.max(0, rootH - layout.h)))
    draw.size(layer, layout.w, layout.h)
    shown = { layer = layer, catcher = catcher }
    -- The edge takes the clicks between tiles, so they do not close the picker.
    draw.hitArea(draw.rect(layer, W.bronze, 0, 0, layout.w, layout.h))
    draw.rect(layer, W.popup, 1, 1, layout.w - 2, layout.h - 2)
    local title = draw.windowText(layer, draw.FONTS.body, ui.AlignMode.TOPLEFT, PAD, PAD, INNER, TITLE_H)
    draw.set(title, "content", name)
    controls.closeButton(layer, layout.w - PAD - controls.CLOSE_SIZE, PAD, picker.close)
    for _, head in ipairs(layout.heads) do
      local text = draw.windowText(layer, draw.FONTS.small, ui.AlignMode.TOPLEFT, head.x, head.y, head.w, head.h)
      draw.set(text, "content", head.text)
    end

    local group = controls.optionGroup(layer)
    local options = {}
    -- Marks the tiles reading the member's tag, or None when they have none.
    local function mark()
      local tag = party.tag(saved.roles(), name) or false
      for i, tile in ipairs(layout.tiles) do
        controls.showOption(options[i], tile.tag == tag)
      end
    end
    for i, tile in ipairs(layout.tiles) do
      options[i] = controls.option(layer, tile.label, tile.x, tile.y, tile.w, tile.h, function()
        saved.setRole(name, tile.tag or nil)
        deps.refresh()
        picker.close()
      end, group)
    end
    mark()

    local f = layout.field
    local field = controls.inputField(layer, f.x, f.y, f.w, f.h, savedparty.MAX_TAG)
    draw.on(field, "ONCONTENTCHANGED", function(_, reason, contents)
      local results = ui.InputFieldActionResult
      if reason == results.CONTENT_CHANGE then
        saved.setRole(name, contents)
        deps.refresh()
        mark()
      elseif reason == results.SUBMIT then
        picker.close()
      end
    end)
  end

  return picker
end

return rolepicker
