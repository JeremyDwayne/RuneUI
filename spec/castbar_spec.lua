local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local style = require("src/style")
local view = require("src/view")

local asphyxiate = samples.asphyxiate
local marks = samples.marks
local look = samples.look
local label = samples.label

describe("castbar", function()
  before_each(fake.reset)

  it("shows the channel's name and length, hides between channels, and makes no writes when steady", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    assert.is_not_nil(label("Asphyxiate"))
    assert.is_not_nil(label("4.2s"))
    fake.writes = 0
    bar.update(asphyxiate())
    assert.are.equal(0, fake.writes)
    bar.update(nil)
    assert.is_true(bar.layer.hidden)
    fake.writes = 0
    bar.update(nil)
    assert.are.equal(0, fake.writes)
    assert.are.same({ x = 0, y = 0, w = 278, h = 22 }, bar.bounds)
  end)

  it("fills each step up to the next tick, steps its time with the ticks as the game does, and ends at 0", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    local fill = fake.find(function(_, d)
      return d.rgb == style.CAST_COLOUR
    end)
    local width = fill.width
    bar.step(0.3)
    bar.update(asphyxiate())
    assert.is_not_nil(label("4.2s"))
    assert.is_true(fill.width > width)
    bar.update(asphyxiate(nil, 5))
    assert.is_not_nil(label("3s"))
    bar.step(5)
    assert.is_false(bar.layer.hidden)
    bar.update(asphyxiate(nil, 1))
    bar.step(0.7)
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate())
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate(227280))
    assert.is_false(bar.layer.hidden)
  end)

  it("shows Cancelled for a cancelled channel, then fades the bar out and hides it", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    local name = label("Asphyxiate")
    bar.update({ start = 227269, cancelled = true })
    assert.is_not_nil(label("Cancelled"))
    assert.are.same({ 0, 0 }, marks(bar))
    bar.update(nil)
    bar.step(0.6)
    assert.are.same({ false, 1 }, { bar.layer.hidden, name.alpha or 1 })
    bar.step(0.2)
    assert.is_true(name.alpha > 0 and name.alpha < 1)
    bar.step(0.3)
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate())
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate(227280))
    assert.are.same({ false, 1 }, { bar.layer.hidden, name.alpha })
  end)

  it("colours the fill by the channel's combat style, and teal when it has none", function()
    local bar = view.castBar(fake.component())
    local model = asphyxiate()
    model.style = "necromancy"
    bar.update(model)
    assert.is_not_nil(fake.find(function(_, d)
      return d.rgb == style.STYLE_COLOURS.necromancy
    end))
    bar.update(asphyxiate(227280))
    assert.is_nil(fake.find(function(_, d)
      return d.rgb == style.STYLE_COLOURS.necromancy
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.rgb == style.CAST_COLOUR
    end))
  end)

  it("fills in a chosen colour over its ability's colour, and back", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    local function filled(rgb)
      return fake.find(function(c, d)
        return c.parent == bar.layer and d.rgb == rgb
      end) ~= nil
    end
    assert.is_true(filled(style.CAST_COLOUR))
    bar.setLook(look({ castColour = 0x123456 }))
    assert.are.same({ true, false }, { filled(0x123456), filled(style.CAST_COLOUR) })
    bar.setLook(look({ castColour = "ability" }))
    assert.is_true(filled(style.CAST_COLOUR))
  end)

  it("keeps a spark at the fill's edge whose glow flashes on each server tick", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    bar.step(0.3)
    local core = fake.find(function(_, d)
      return d.rgb == draw.COLOURS.highlight and d.width == 2 and d.height == 20
    end)
    local x = core.parent.x
    bar.step(0.2)
    assert.is_true(core.parent.x > x)
    local function glow(alpha)
      return fake.find(function(_, d)
        return d.width == 1 and d.height == 20 and d.alpha == alpha
      end)
    end
    bar.update(asphyxiate(nil, 6))
    assert.is_not_nil(glow(0.9))
    bar.step(0.3)
    assert.are.same({ false, true }, { glow(0.9) ~= nil, glow(0.45) ~= nil })
  end)

  it("ignores a cancelled channel it never showed", function()
    local bar = view.castBar(fake.component())
    bar.update({ start = 227269, cancelled = true })
    assert.is_true(bar.layer.hidden)
  end)

  it("marks each hit inside the cast bar but not at its ends, dark once the fill passes it", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    assert.are.same({ 0, 3 }, marks(bar))
    bar.update(asphyxiate(nil, 5))
    assert.are.same({ 1, 2 }, marks(bar))
    fake.writes = 0
    bar.step(0.02)
    assert.are.equal(2, fake.writes, "the fill and the spark")
    bar.update({ start = 1, name = "Greater Concentrated Blast", duration = 1.8, hits = { 0, 0.6, 1.2 } })
    assert.are.same({ 0, 2 }, marks(bar))
    bar.update({ start = 2, name = "Asphyxiate", duration = 3.6 })
    assert.are.same({ 0, 0 }, marks(bar))
  end)

  it("resizes the bar, keeping its icon and its backing a square as tall as the bar inside its border", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    assert.is_true(bar.setLook(look({ castWidth = 400, castHeight = 34 })))
    assert.are.same({ 400, 34, 400, 34 }, { bar.layer.width, bar.layer.height, bar.bounds.w, bar.bounds.h })
    local squares = 0
    for _, c in ipairs(fake.created) do
      if c.parent == bar.layer and c.width == 32 and c.height == 32 then
        squares = squares + 1
      end
    end
    assert.are.equal(2, squares)
  end)

  it("makes no writes stepping between channels", function()
    local bar = view.castBar(fake.component())
    bar.update(nil)
    fake.writes = 0
    bar.step(0.02)
    assert.are.equal(0, fake.writes)
  end)
end)
