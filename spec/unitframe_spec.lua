local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local style = require("src/style")
local view = require("src/view")

local look = samples.look
local label = samples.label

-- The player and target frames on one root, styled with the default look and showing a name and value each.
local function frames()
  local root = fake.component()
  local elements = { player = view.playerFrame(root), target = view.targetFrame(root) }
  view.setLook(elements, look())
  elements.player.update({
    hidden = false,
    name = "Jeremy",
    valueText = "13.1K | 78%",
    fill = 0.78,
    prayerText = "960",
    prayerFill = 0.9,
  })
  elements.target.update({ hidden = false, name = "Aviansie", valueText = "6,800 | 58%", fill = 0.58 })
  return elements
end

describe("unitframe", function()
  before_each(fake.reset)

  it("draws the player and target frames the same height, with or without a prayer bar", function()
    local elements = frames()
    -- A frame's box is the tallest full-width component on its layer: its black border.
    local function boxHeight(frame)
      local tallest = 0
      fake.find(function(_, d)
        if d.parent == frame.layer and d.width == frame.width then
          tallest = math.max(tallest, d.height or 0)
        end
      end)
      return tallest
    end
    assert.are.equal(boxHeight(elements.player), boxHeight(elements.target))
  end)

  it("resizes both unit frames and their bounds, reporting the change once", function()
    local elements = frames()
    local big = look({ frameWidth = 400, frameHeight = 80 })
    assert.is_true(view.setLook(elements, big))
    for _, name in ipairs({ "player", "target" }) do
      local frame = elements[name]
      assert.are.same({ 400, 400, 80 }, { frame.layer.width, frame.bounds.w, frame.bounds.h })
    end
    fake.writes = 0
    assert.is_false(view.setLook(elements, big))
    assert.are.equal(0, fake.writes)
  end)

  it("draws Auto text dark over a bright fill only", function()
    local elements = frames()
    view.setLook(elements, look({ targetColour = 0xffea00 }))
    elements.target.update({ hidden = false, name = "Aviansie", valueText = "6,800 | 100%", fill = 1 })
    local function rgb(content)
      return label(content).rgb
    end
    assert.are.same(
      { style.DARK_TEXT, style.DARK_TEXT, 0xffffff },
      { rgb("Aviansie"), rgb("6,800 | 100%"), rgb("Jeremy") }
    )
    view.setLook(elements, look({ targetColour = 0xffea00, textColour = "white" }))
    assert.are.equal(0xffffff, rgb("Aviansie"))
  end)

  it("draws the game's window border round both unit frames for Game frame, and no edge for None", function()
    local elements = frames()
    local function shownSprites(frame)
      local n = 0
      for _, c in ipairs(fake.created) do
        if c.parent == frame.layer and c.isTiling ~= nil and fake.shown(c) then
          n = n + 1
        end
      end
      return n
    end
    local function edgeShown(frame)
      return fake.find(function(c, d)
        return c.parent == frame.layer and d.rgb == draw.COLOURS.border
      end) ~= nil
    end
    assert.are.same({ 0, true }, { shownSprites(elements.player), edgeShown(elements.player) })
    view.setLook(elements, look({ border = "game" }))
    assert.are.same({ 8, 8 }, { shownSprites(elements.player), shownSprites(elements.target) })
    view.setLook(elements, look({ border = "none" }))
    assert.are.same({ 0, false }, { shownSprites(elements.target), edgeShown(elements.target) })
  end)
end)
