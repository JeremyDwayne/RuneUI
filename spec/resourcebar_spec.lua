local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local view = require("src/view")

local marks = samples.marks
local strip = samples.strip
local look = samples.look

describe("resourcebar", function()
  before_each(fake.reset)

  it("turns a spender row's whole casts gold, redrawing its canvas once per change", function()
    local bar = view.resourceBar(fake.component())
    local canvas = nil
    for _, c in ipairs(fake.created) do
      if canvas == nil and c.parent == bar.layer then
        canvas = c
      end
    end
    local fills = {}
    local clears = 0
    canvas.AddRectangle = function(_, _, _, _, _, rgba)
      fills[#fills + 1] = rgba
    end
    canvas.Clear = function()
      clears = clears + 1
      fills = {}
    end
    local function blocks(rgb)
      local n = 0
      for i = 2, #fills, 2 do
        if fills[i] == draw.opaque(rgb) then
          n = n + 1
        end
      end
      return n
    end
    local necrosis = { key = "necrosis", count = 8, max = 12, gold = 6, notch = 6 }
    local model = { hidden = false, fill = 0.4, text = "40%", markers = {}, spenders = { necrosis } }
    bar.update(model)
    assert.are.same({ 6, 2, 1 }, { blocks(draw.WINDOW.accent), blocks(draw.COLOURS.necrosis), clears })
    bar.update(model)
    assert.are.equal(1, clears)
    necrosis.gold = 0
    bar.update(model)
    assert.are.same({ 0, 8, 2 }, { blocks(draw.WINDOW.accent), blocks(draw.COLOURS.necrosis), clears })
  end)

  it("draws each adrenaline marker as a faint line across the bar, dark once the fill reaches it", function()
    local bar = view.resourceBar(fake.component())
    bar.update({ hidden = false, fill = 0.6, text = "60%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.are.same({ 1, 1 }, marks(bar, 18))
    bar.update({ hidden = false, fill = 1, text = "100%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.are.same({ 2, 0 }, marks(bar, 18))
  end)

  it("fills the adrenaline bar's strip once over the global cooldown, and hides it after", function()
    local bar = view.resourceBar(fake.component())
    bar.update({ hidden = false, fill = 0.6, text = "60%", markers = {}, spenders = {} })
    local track, gold = strip(bar)
    local inner = bar.bounds.w - 2
    assert.is_false(fake.shown(gold))
    fake.writes = 0
    bar.step(0.3)
    assert.are.equal(0, fake.writes)
    bar.setGlobal(0, 1.8, 1.8)
    assert.are.same({ true, bar.bounds.y + 2, bar.bounds.w, 0 }, { fake.shown(gold), track.y, track.width, gold.width })
    bar.step(0.6)
    assert.are.equal(math.floor(inner / 3 + 0.5), gold.width)
    fake.writes = 0
    bar.step(0.6)
    assert.are.equal(0, fake.writes)
    bar.setGlobal(0, 1.2, 1.8)
    assert.are.equal(math.floor(inner / 3 + 0.5), gold.width, "the next tick carries on where the last left off")
    bar.step(0.9)
    assert.are.equal(math.floor(inner * 5 / 6 + 0.5), gold.width)
    bar.setGlobal(0.6, 0.6, 1.8)
    assert.are.equal(inner, gold.width)
    bar.setGlobal(0, nil)
    assert.is_false(fake.shown(gold))
    fake.writes = 0
    bar.step(0.3)
    assert.are.equal(0, fake.writes)
  end)

  it("resizes the adrenaline bar, placing its markers across the new width", function()
    local bar = view.resourceBar(fake.component())
    bar.update({ hidden = false, fill = 0.4, text = "40%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.is_true(bar.setLook(look({ barWidth = 402, barHeight = 30 })))
    assert.are.same({ 402, 402, 30 + 9 }, { bar.layer.width, bar.bounds.w, bar.bounds.h }, "with the strip's room")
    local xs = {}
    for _, c in ipairs(fake.created) do
      if c.parent == bar.layer and c.width == 1 and c.height == 28 then
        xs[#xs + 1] = c.x
      end
    end
    assert.are.same({ 201, 400 }, xs)
  end)
end)
