local style = require("src/style")

local DEFAULTS = {
  font = "museo", textStep = 0, edge = "shadow", textColour = "auto", playerColour = "runeui",
  targetColour = "runeui", border = "runeui", texture = "flat", frameWidth = 250, frameHeight = 55,
}

local function appearance(changes)
  local out = {}
  for k, v in pairs(DEFAULTS) do out[k] = v end
  for k, v in pairs(changes or {}) do out[k] = v end
  return out
end

describe("style.font", function()
  it("keeps today's fonts at step 0 and moves every role by the step", function()
    assert.are.equal("MUSEO_SANS_13PT_BOLD", style.font("museo", "body", 0))
    assert.are.equal("NOTOSANS_BOLD_10", style.font("museo", "small", 0))
    assert.are.equal("MUSEO_SANS_17PT_BOLD", style.font("museo", "seconds", 0))
    assert.are.equal("MUSEO_SANS_15PT_BOLD", style.font("museo", "smallSeconds", 0))
    assert.are.equal("NOTOSANS_BOLD_16", style.font("noto", "body", 3))
    assert.are.equal("NOTOSANS_BOLD_13", style.font("noto", "small", 3))
  end)

  it("snaps to the nearest size the family has, toward the step on a tie", function()
    assert.are.equal("MUSEO_SANS_15PT_BOLD", style.font("museo", "body", 1))
    assert.are.equal("MUSEO_SANS_24PT_BOLD", style.font("museo", "seconds", 6))
    assert.are.equal("VERDANA_13PT_BOLD", style.font("verdana", "body", 6))
    assert.are.equal("VERDANA_11PT_BOLD", style.font("verdana", "small", 0))
    assert.are.equal("CINZEL_12PT_BOLD", style.font("cinzel", "small", -3))
    assert.are.equal("CINZEL_15PT_BOLD", style.font("cinzel", "body", 1))
    assert.are.equal("CINZEL_13PT_BOLD", style.font("cinzel", "seconds", -3))
  end)
end)

describe("style.outlineFont", function()
  it("finds the native outline font for Noto Sans Bold at 11, 13 and 21 only", function()
    assert.are.equal("NOTO_SANS_11PT_BOLD_OUTLINE", style.outlineFont("NOTOSANS_BOLD_11"))
    assert.are.equal("NOTO_SANS_13PT_BOLD_OUTLINE", style.outlineFont("NOTOSANS_BOLD_13"))
    assert.are.equal("NOTO_SANS_21PT_BOLD_OUTLINE", style.outlineFont("NOTOSANS_BOLD_21"))
    assert.is_nil(style.outlineFont("NOTOSANS_BOLD_10"))
    assert.is_nil(style.outlineFont("MUSEO_SANS_13PT_BOLD"))
  end)
end)

describe("style hex", function()
  it("parses #RRGGBB in either case, with or without the hash, and formats it back", function()
    assert.are.equal(0x2f63a8, style.parseHex("#2F63A8"))
    assert.are.equal(0x2f63a8, style.parseHex(" 2f63a8 "))
    assert.are.equal("#2F63A8", style.formatHex(0x2f63a8))
    assert.are.equal("#000000", style.formatHex(0))
  end)

  it("rejects anything that is not six hex digits", function()
    for _, bad in ipairs({ "#2f63a", "#2f63a8f", "#2g63a8", "", "blue" }) do assert.is_nil(style.parseHex(bad)) end
  end)
end)

describe("style hsv", function()
  it("round-trips a colour through hue, saturation and value", function()
    for _, rgb in ipairs({ 0x2f63a8, 0xa4511c, 0xffffff, 0x000000, 0xff0000, 0x6b3fa0 }) do
      assert.are.equal(rgb, style.rgb(style.hsv(rgb)))
    end
    local h, s, v = style.hsv(0x00ff00)
    assert.are.same({ 120, 1, 1 }, { h, s, v })
  end)
end)

describe("style.dark", function()
  it("wants dark text over a fill above the luminance cut", function()
    assert.is_true(style.dark(0xffb000))
    assert.is_true(style.dark(0xdfe4ea))
    assert.is_false(style.dark(0x2f63a8))
    assert.is_false(style.dark(0xa4511c))
  end)
end)

describe("style.look", function()
  it("resolves today's look from the defaults", function()
    local look = style.look(appearance(), nil)
    assert.are.same({ body = "MUSEO_SANS_13PT_BOLD", small = "NOTOSANS_BOLD_10", seconds = "MUSEO_SANS_17PT_BOLD",
      smallSeconds = "MUSEO_SANS_15PT_BOLD" }, look.fonts)
    assert.are.same({ 0x2f63a8, 0xa4511c }, { look.player, look.target })
    assert.is_true(look.shadow)
    assert.is_false(look.outline)
    assert.is_true(look.auto)
    assert.are.equal(0xffffff, look.text)
  end)

  it("colours a frame from a preset, the equipped style or a hex number", function()
    local look = style.look(appearance({ playerColour = "gameGreen", targetColour = 0x123456 }), nil)
    assert.are.same({ 0x2b8a1e, 0x123456 }, { look.player, look.target })
    local equipped = style.look(appearance({ playerColour = "equipped", targetColour = "equipped" }), "necromancy")
    assert.are.same({ 0x6b3fa0, 0x6b3fa0 }, { equipped.player, equipped.target })
    local unknown = style.look(appearance({ playerColour = "equipped" }), nil)
    assert.are.equal(0x2f63a8, unknown.player)
  end)

  it("reads the edge and text colour", function()
    local look = style.look(appearance({ edge = "outlineShadow", textColour = "yellow" }), nil)
    assert.are.same({ true, true, false, 0xffea00 }, { look.outline, look.shadow, look.auto, look.text })
  end)
end)
