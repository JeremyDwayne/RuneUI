local fake = require("spec/support/fake_ui")
local cooldowns = require("src/cooldowns")
local options = require("src/options")
local settings = require("src/settings")
local view = require("src/view")

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- Edit mode over every HUD element with default settings, entered from the options window. Returns the
-- elements by name, the settings and the options window.
local function enterEditMode()
  local root = fake.component()
  root:SetSize(1710, 1041)
  local tooltip = view.tooltip(root)
  local elements = {
    player = view.playerFrame(root),
    target = view.targetFrame(root, tooltip, function() end),
    resource = view.resourceBar(root),
    rotation = view.cooldownGroup(root, view.TILE_STYLES.rotation, tooltip),
    cooldowns = view.cooldownGroup(root, view.TILE_STYLES.cooldowns, tooltip),
  }
  local saved = settings.load(fakeStore())
  local window = options.create(root, {
    saved = saved, tracker = cooldowns.tracker(), elements = elements, view = view, refresh = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  fake.press("Open RuneUI options")
  fake.press("Edit mode off")
  return elements, saved, window
end

-- Presses or releases Shift.
local function shift(down)
  fake.fire(down and "KeyDown" or "KeyUp", { gameKey = GameKey.SHIFT })
end

local function logicTick()
  fake.fire("Logic", { logicTick = 1 })
end

-- The overlay hit area over element.
local function overlayOf(element)
  return fake.find(function(c, d)
    return fake.hasHook(c, "ONRELEASE") and d.width == element.width and d.height == element.height
  end)
end

local function shows(content)
  return fake.find(function(_, d) return d.content == content end) ~= nil
end

-- Hovers each spot in the open anchor menu until its name reads label, then clicks it.
local function chooseSpot(label)
  for _, c in ipairs(fake.created) do
    if fake.shown(c) and fake.hasHook(c, "ONMOUSEOVER") and fake.hasHook(c, "ONCLICK") then
      fake.hook(c, "ONMOUSEOVER")
      if shows(label) then return fake.hook(c, "ONCLICK") end
    end
  end
  error("no spot " .. label)
end

-- Presses element's overlay with the cursor at 300, 300, holding Shift so the move ignores snapping.
local function grab(element)
  local tint = overlayOf(element)
  fake.mouse.x, fake.mouse.y = 300, 300
  shift(true)
  fake.hook(tint, "ONCLICK")
  return tint
end

describe("edit mode", function()
  before_each(fake.reset)

  it("resets positions only once the dialog is confirmed", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x = layer.x
    local tint = grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    fake.hook(tint, "ONRELEASE")

    fake.press("Reset positions")
    fake.press("Cancel")
    assert.are.equal(x + 50, layer.x)
    fake.press("Reset positions")
    fake.press("Reset positions", 3)
    assert.are.equal(x, layer.x)
    assert.is_nil(fake.find(function(_, d) return d.content == "Cancel" end))
  end)

  it("puts a moved element back on Esc", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x, y = layer.x, layer.y
    grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    assert.are.equal(x + 50, layer.x)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.same({ x, y }, { layer.x, layer.y })
    fake.writes = 0
    fake.mouse.x = 400
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("moves an element by the cursor's UI distance when the mouse reports physical pixels", function()
    local elements = enterEditMode()
    local layer = elements.player.layer
    local x = layer.x
    local tint = overlayOf(elements.player)
    tint.xyGlobal = { x = 150, y = 150 }
    fake.mouse.x, fake.mouse.y = 300, 300
    shift(true)
    fake.hook(tint, "ONCLICK")
    fake.mouse.x = 400
    logicTick()
    assert.are.equal(x + 50, layer.x)
  end)

  it("makes no client writes on an idle logic tick or while a move is held still", function()
    local elements = enterEditMode()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
    grab(elements.player)
    fake.mouse.x = 350
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("anchors an element to the side and alignment chosen in the pick, flush against it", function()
    local elements, saved = enterEditMode()
    fake.press("Rotation, left, bottom")
    fake.press("Anchor")
    assert.is_true(shows("Click the element to anchor Player to"))
    fake.hook(overlayOf(elements.rotation), "ONCLICK")
    assert.is_true(shows("Anchor Player to Rotation"))
    chooseSpot("Left side, top")

    assert.are.same({ target = "rotation", side = "left", align = "top", gap = 0, offset = 0 }, saved.anchors().player)
    local rotation = elements.rotation.layer
    assert.are.same({ rotation.x - 250, rotation.y }, { elements.player.layer.x, elements.player.layer.y })
    assert.is_true(shows("Rotation, left, top"))
    assert.is_false(shows("Anchor Player to Rotation"))
  end)

  it("cancels a pick on Esc and saves nothing", function()
    local elements, saved = enterEditMode()
    fake.press("Anchor")
    fake.hook(overlayOf(elements.player), "ONCLICK")
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_nil(saved.anchors().rotation)
    assert.is_false(shows("Anchor Rotation to Player"))
    assert.is_false(shows("Click the element to anchor Rotation to"))
    assert.is_true(shows("Edit mode"))
  end)

  it("refuses a target anchored to the picking element and says why", function()
    local elements, saved = enterEditMode()
    fake.press("Anchor")
    fake.hook(overlayOf(elements.cooldowns), "ONCLICK")
    assert.is_true(shows("Cooldowns is anchored to Rotation"))
    assert.is_false(shows("Anchor Rotation to Cooldowns"))
    assert.is_nil(saved.anchors().rotation)
  end)

  it("removes an anchor when its button is pressed, leaving the element where it is", function()
    local elements, saved = enterEditMode()
    local x, y = elements.player.layer.x, elements.player.layer.y
    fake.press("Rotation, left, bottom")
    assert.is_nil(saved.anchors().player)
    assert.are.same({ x = x, y = y, anchorX = 0.5, anchorY = 1 }, saved.positions().player)
    assert.are.same({ x, y }, { elements.player.layer.x, elements.player.layer.y })
    assert.is_false(shows("Rotation, left, bottom"))
  end)

  it("drags an element's whole chain and saves only the dragged position", function()
    local elements, saved = enterEditMode()
    local before = {}
    for name, element in pairs(elements) do before[name] = element.layer.x end
    local tint = grab(elements.rotation)
    fake.mouse.x = 350
    logicTick()
    for name, element in pairs(elements) do assert.are.equal(before[name] + 50, element.layer.x, name) end
    fake.hook(tint, "ONRELEASE")

    assert.are.equal(settings.DEFAULT_POSITIONS.rotation.x + 50, saved.positions().rotation.x)
    assert.are.same(settings.DEFAULT_POSITIONS.player, saved.positions().player)
    assert.are.same(settings.DEFAULT_ANCHORS, saved.anchors())
  end)

  it("saves a dragged anchored element's new gap and offset", function()
    local elements, saved = enterEditMode()
    local tint = grab(elements.player)
    fake.mouse.x, fake.mouse.y = 280, 310
    logicTick()
    fake.hook(tint, "ONRELEASE")
    assert.are.same({ target = "rotation", side = "left", align = "bottom", gap = 20, offset = 10 },
      saved.anchors().player)
  end)

  it("snaps a drop 4 px from the frames' shared bottom edge flush with it, unless Shift is held", function()
    for _, held in ipairs({ false, true }) do
      fake.reset()
      local elements, saved = enterEditMode()
      fake.press("Rotation, left, bottom")
      local tint = grab(elements.player)
      shift(held)
      fake.mouse.y = 296
      logicTick()
      fake.hook(tint, "ONRELEASE")
      local bottom = saved.positions().player.y + elements.player.height
      assert.are.equal(held and -353 or -349, bottom)
    end
  end)

  it("keeps a dragged element under the cursor when a row's tiles change mid-drag", function()
    local elements, _, window = enterEditMode()
    grab(elements.rotation)
    fake.mouse.x = 350
    logicTick()
    local x = elements.rotation.layer.x
    elements.rotation.update({ { key = "A", name = "A", initials = "A", ready = true } })
    window.placeAll()
    assert.are.equal(x, elements.rotation.layer.x)
  end)

  it("saves whole-unit positions when the cursor scale is fractional", function()
    local elements, saved = enterEditMode()
    fake.press("Rotation, left, bottom")
    local tint = overlayOf(elements.player)
    tint.xyGlobal = { x = 149, y = 150 }
    fake.mouse.x, fake.mouse.y = 300, 300
    shift(true)
    fake.hook(tint, "ONCLICK")
    fake.mouse.x = 401
    logicTick()
    fake.hook(tint, "ONRELEASE")
    assert.are.equal("integer", math.type(saved.positions().player.x))
  end)

  it("snaps a dragged group's center onto the window's center line before a nearer grid line", function()
    local elements = enterEditMode()
    local tint = overlayOf(elements.rotation)
    fake.mouse.x, fake.mouse.y = 300, 300
    fake.hook(tint, "ONCLICK")
    fake.mouse.x = 303
    logicTick()
    assert.are.equal(-219, elements.rotation.layer.x)
  end)
end)
