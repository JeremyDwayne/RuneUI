local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local savedgroups = require("src/savedgroups")
local settings = require("src/settings")
local view = require("src/view")

local readyTiles = samples.readyTiles
local group = samples.group
local look = samples.look
local label = samples.label
local setLook = view.setLook

-- Every HUD element on one root, with the built-in groups at their default display settings.
local function hud()
  local root = fake.component()
  local tooltip = view.tooltip(root)
  local elements = {
    player = view.playerFrame(root),
    target = view.targetFrame(root),
    resource = view.resourceBar(root),
    castbar = view.castBar(root),
  }
  for _, default in ipairs(savedgroups.GROUPS) do
    elements[default.name] = group(default.size, default.perRow, default.grow, root, tooltip)
  end
  return elements
end

-- Every HUD element and a combat buffs row, each showing text, styled with the default look. Returns them and
-- a tick that redraws each from the same models.
local function shownHud()
  local elements = hud()
  elements.combatBuffs = samples.auraRow()
  setLook(elements, look())
  local tiles = readyTiles(3)
  tiles[1].keybind = "V"
  tiles[2].remaining = 7.2
  tiles[2].ready = false
  local function tick()
    elements.player.update({
      hidden = false,
      name = "Jeremy",
      valueText = "13.1K | 78%",
      fill = 0.78,
      prayerText = "960",
      prayerFill = 0.9,
    })
    elements.target.update({ hidden = false, name = "Aviansie", valueText = "6,800 | 58%", fill = 0.58 })
    elements.resource.update({ hidden = false, fill = 0.8, text = "80%", markers = {}, spenders = {} })
    elements.castbar.update(samples.asphyxiate())
    elements.major.update(tiles, 0)
    elements.combatBuffs.update(samples.incite(10), false)
  end
  tick()
  return elements, tick
end

-- Shown components reading content.
local function shownWith(content)
  local n = 0
  for _, c in ipairs(fake.created) do
    if c.content == content and fake.shown(c) then
      n = n + 1
    end
  end
  return n
end

describe("view", function()
  before_each(fake.reset)

  it("turns the adrenaline bar's strip toward the nearest cooldown group, keeping anchors flush", function()
    local bar = view.resourceBar(fake.component())
    bar.update({ hidden = false, fill = 0.6, text = "60%", markers = {}, spenders = {} })
    local rotation = group(36)
    rotation.update(readyTiles(5))
    local elements = { resource = bar, rotation = rotation }
    local track = samples.strip(bar)
    local function at(x, y)
      return { x = x, y = y, anchorX = 0.5, anchorY = 1 }
    end
    view.arrange(elements, { rotation = at(-100, -400), resource = at(-139, -300) }, {})
    assert.are.equal(bar.bounds.y + 2, track.y)
    view.arrange(elements, { rotation = at(-100, -200), resource = at(-139, -300) }, {})
    assert.are.equal(bar.bounds.y + bar.bounds.h - 7, track.y)
    view.arrange(elements, { rotation = at(-100, -400), resource = at(-139, -300) }, {})
    local anchor = { target = "rotation", side = "top", align = "center", gap = 0, offset = 0 }
    view.arrange(elements, { rotation = at(-100, -400) }, { resource = anchor })
    assert.are.equal(bar.bounds.y + bar.bounds.h - 7, track.y)
    local barBottom = bar.layer.y + bar.bounds.y + bar.bounds.h
    assert.are.equal(rotation.layer.y + rotation.bounds.y, barBottom)
  end)

  it("moves anchored frames on the tick the rotation group gains a tile, and makes no writes when steady", function()
    local elements = hud()
    local saved = settings.load({ get = function() end, set = function() end })
    local function tick(count)
      local moved = elements.rotation.update(readyTiles(count))
      if moved then
        view.arrange(elements, saved.positions(), saved.anchors())
      end
    end
    view.arrange(elements, saved.positions(), saved.anchors())
    tick(4)
    local x = elements.player.layer.x
    tick(5)
    assert.are.equal(x - 24, elements.player.layer.x)
    fake.writes = 0
    tick(5)
    assert.are.equal(0, fake.writes)
  end)

  it("writes each HUD label's font once when the font changes, and nothing else", function()
    local elements = shownHud()
    fake.writes = 0
    setLook(elements, look({ font = "noto" }))
    local changed = 0
    for _, c in ipairs(fake.created) do
      local font = c.font
      if font == "NOTOSANS_BOLD_13" or font == "NOTOSANS_BOLD_15" or font == "NOTOSANS_BOLD_17" then
        changed = changed + 1
      end
    end
    assert.are.equal(changed, fake.writes)
    assert.are.equal("NOTOSANS_BOLD_13", label("Jeremy").font)
    assert.are.equal("NOTOSANS_BOLD_15", label("8").font)
  end)

  it("shows four outline copies under each label while Outline is on, or the native outline font", function()
    local elements = shownHud()
    setLook(elements, look({ edge = "outline" }))
    assert.are.same({ 5, 5, 5 }, { shownWith("Jeremy"), shownWith("V"), shownWith("10") })
    setLook(elements, look({ edge = "none" }))
    assert.are.same({ 1, 1, 1 }, { shownWith("Jeremy"), shownWith("V"), shownWith("10") })
    setLook(elements, look({ edge = "outline", font = "noto" }))
    assert.are.equal(1, shownWith("Jeremy"))
    assert.are.equal("NOTO_SANS_13PT_BOLD_OUTLINE", label("Jeremy").font)
  end)

  it("makes no writes on a steady tick with Outline on", function()
    local elements, tick = shownHud()
    local outlined = look({ edge = "outlineShadow" })
    setLook(elements, outlined)
    tick()
    fake.writes = 0
    setLook(elements, outlined)
    tick()
    assert.are.equal(0, fake.writes)
  end)

  it("grows the adrenaline bar's bounds by its spender rows below or above it, or the player frame's", function()
    local elements = shownHud()
    local bar = elements.resource
    local player = elements.player
    local spenders =
      { { key = "souls", count = 1, max = 3, gold = 0 }, { key = "necrosis", count = 4, max = 12, gold = 0 } }
    local model = { hidden = false, fill = 0.4, text = "40%", markers = {}, spenders = spenders }
    local function boxes()
      return { bar.bounds.y, bar.bounds.h, player.bounds.h }
    end
    local barY = bar.bounds.y
    local barH = bar.bounds.h
    assert.is_true(bar.update(model))
    player.showSpenders(spenders)
    assert.are.same({ barY, barH + 20, 55 }, boxes())
    setLook(elements, look({ spenders = "above" }))
    assert.are.same({ barY - 20, barH + 20, 55 }, boxes())
    setLook(elements, look({ spenders = "player" }))
    assert.are.same({ barY, barH, 75 }, boxes())
    fake.writes = 0
    assert.are.same({ false, false }, { bar.update(model), player.showSpenders(spenders) })
    assert.are.equal(0, fake.writes)
  end)
end)
