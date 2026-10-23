local fakeStore = require("spec/support/fake_store")
local savedappearance = require("src/savedappearance")

describe("savedappearance", function()
  it("clamps marker percents to 0 through 100", function()
    local s = savedappearance.load(fakeStore())
    s.setMarker("ultimate", 150)
    s.setMarker("threshold", -5)
    assert.are.same({ threshold = 0, ultimate = 100 }, s.markers())
  end)

  it("keeps bars flat until a known texture is chosen, and saves the choice", function()
    local store = fakeStore()
    assert.are.equal("flat", savedappearance.load(store).appearance().texture)
    savedappearance.load(store).setAppearance("texture", "vertical")
    assert.are.equal("vertical", savedappearance.load(store).appearance().texture)
    assert.are.equal(
      "flat",
      savedappearance.load(fakeStore({ appearance = { texture = "plaid" } })).appearance().texture
    )
  end)

  it("reads today's look until the new appearance fields are chosen, and saves each one", function()
    local store = fakeStore({
      appearance = {
        texture = "vertical",
        hideTargetPanel = true,
        hideCastBar = false,
        hideBuffBars = true,
        auraBars = true,
      },
    })
    local s = savedappearance.load(store)
    assert.are.same({
      texture = "vertical",
      hideTargetPanel = true,
      hideCastBar = false,
      hideBuffBars = true,
      auraBars = true,
      font = "museo",
      textStep = 0,
      edge = "shadow",
      textColour = "auto",
      playerColour = "runeui",
      targetColour = "runeui",
      border = "runeui",
      lifepoints = "short",
      frameWidth = 250,
      frameHeight = 55,
      barWidth = 278,
      barHeight = 20,
      castWidth = 278,
      castHeight = 22,
      castMatchWidth = false,
      castColour = "ability",
      castFont = "hud",
      castTextSize = "hud",
      spenders = "below",
      barOpacity1 = 25,
      barOpacity2 = 25,
      barOpacity3 = 25,
      barOpacity4 = 25,
      barOpacity5 = 25,
      fadeBar1 = false,
      fadeBar2 = false,
      fadeBar3 = false,
      fadeBar4 = false,
      fadeBar5 = false,
      hoverBar1 = true,
      hoverBar2 = true,
      hoverBar3 = true,
      hoverBar4 = true,
      hoverBar5 = true,
      hoverAllBars = false,
      combatBuffsIcon = 36,
      combatBuffsText = "hud",
      upkeepBuffsIcon = 26,
      upkeepBuffsText = "hud",
      playerDebuffsIcon = 26,
      playerDebuffsText = "hud",
      targetDebuffsIcon = 26,
      targetDebuffsText = "hud",
      debuffEdge = "orange",
      outOfCombat = "show",
      outOfCombatOpacity = 30,
      showWithTarget = true,
      outOfCombatPick = "fade",
      fadeBars = true,
    }, s.appearance())
    local chosen = {
      font = "cinzel",
      textStep = -3,
      edge = "outlineShadow",
      textColour = "yellow",
      playerColour = 0x123456,
      targetColour = "equipped",
      border = "game",
      lifepoints = "percent",
      frameWidth = 400,
      frameHeight = 30,
      barWidth = 333,
      barHeight = 13,
      castWidth = 410,
      castHeight = 30,
      castMatchWidth = true,
      castColour = "necro",
      castFont = "cinzel",
      castTextSize = 16,
      outOfCombat = "fade",
      outOfCombatOpacity = 55,
      showWithTarget = false,
    }
    for field, value in pairs(chosen) do
      s.setAppearance(field, value)
    end
    local reloaded = savedappearance.load(store).appearance()
    for field, value in pairs(chosen) do
      assert.are.equal(value, reloaded[field])
    end
  end)

  it("reads unknown and malformed appearance values as their defaults", function()
    local s = savedappearance.load(fakeStore({
      appearance = {
        font = "comic",
        textStep = 7,
        edge = 2,
        textColour = "plaid",
        playerColour = "teal",
        targetColour = 0x1000000,
        border = "gold",
        lifepoints = "all",
        frameWidth = 175,
        frameHeight = 100,
      },
    }))
    local a = s.appearance()
    assert.are.same({ "museo", 0, "shadow", "auto", "runeui", "runeui", "runeui", "short", 250, 55 }, {
      a.font,
      a.textStep,
      a.edge,
      a.textColour,
      a.playerColour,
      a.targetColour,
      a.border,
      a.lifepoints,
      a.frameWidth,
      a.frameHeight,
    })
  end)

  it("saves the action bar fade settings and reads a bad opacity or flag as its default", function()
    local store = fakeStore()
    local s = savedappearance.load(store)
    s.setAppearance("barOpacity2", 40.0)
    s.setAppearance("fadeBar3", true)
    s.setAppearance("hoverBar5", false)
    local reloaded = savedappearance.load(store).appearance()
    assert.are.same({ 40, true, false }, { reloaded.barOpacity2, reloaded.fadeBar3, reloaded.hoverBar5 })
    assert.are.equal(math.type(40), math.type(reloaded.barOpacity2))
    for _, opacity in ipairs({ 37, -5, 105, "x" }) do
      assert.are.equal(
        25,
        savedappearance.load(fakeStore({ appearance = { barOpacity1 = opacity } })).appearance().barOpacity1
      )
    end
    local bad = savedappearance.load(fakeStore({ appearance = { fadeBar1 = "yes", hoverBar2 = 0 } }))
    assert.are.same({ false, true }, { bad.appearance().fadeBar1, bad.appearance().hoverBar2 })
  end)

  it("reads an out of combat opacity off its 5 percent steps, below 10 or above 90 as 30", function()
    for _, opacity in ipairs({ 0, 5, 33, 95, 100, "x" }) do
      local a = savedappearance.load(fakeStore({ appearance = { outOfCombatOpacity = opacity } })).appearance()
      assert.are.equal(30, a.outOfCombatOpacity, tostring(opacity))
    end
    local store = fakeStore({ appearance = { outOfCombatOpacity = 10.0, outOfCombat = "vanish" } })
    local a = savedappearance.load(store).appearance()
    assert.are.same({ 10, "show" }, { a.outOfCombatOpacity, a.outOfCombat })
  end)

  it("turns out of combat fading off to Show and back on to the last Fade or Hide picked", function()
    local store = fakeStore()
    local s = savedappearance.load(store)
    s.setOutOfCombat(true)
    assert.are.equal("fade", s.appearance().outOfCombat)
    s.setAppearance("outOfCombat", "hide")
    s.setOutOfCombat(false)
    assert.are.equal("show", s.appearance().outOfCombat)
    s.setOutOfCombat(true)
    assert.are.equal("hide", savedappearance.load(store).appearance().outOfCombat)
  end)

  it("saves each aura row's icon and text size and reads a bad one as its default", function()
    local store = fakeStore()
    local s = savedappearance.load(store)
    s.setAppearance("upkeepBuffsIcon", 40.0)
    s.setAppearance("targetDebuffsText", 15)
    local reloaded = savedappearance.load(store).appearance()
    assert.are.same({ 40, 15 }, { reloaded.upkeepBuffsIcon, reloaded.targetDebuffsText })
    assert.are.equal(math.type(40), math.type(reloaded.upkeepBuffsIcon))
    local bad = savedappearance
      .load(fakeStore({
        appearance = {
          combatBuffsIcon = 17,
          playerDebuffsIcon = 30.5,
          upkeepBuffsText = 20,
          combatBuffsText = "big",
          debuffEdge = "red",
        },
      }))
      .appearance()
    assert.are.same(
      { 36, 26, "hud", "hud", "orange" },
      { bad.combatBuffsIcon, bad.playerDebuffsIcon, bad.upkeepBuffsText, bad.combatBuffsText, bad.debuffEdge }
    )
  end)

  it("reads a saved hex colour and size back as whole numbers, and counts appearance changes", function()
    local s = savedappearance.load(fakeStore({ appearance = { playerColour = 1193046.0, frameWidth = 300.0 } }))
    assert.are.equal(math.type(1193046), math.type(s.appearance().playerColour))
    assert.are.equal(math.type(300), math.type(s.appearance().frameWidth))
    local start = s.appearanceVersion()
    s.setAppearance("edge", "outline")
    s.setAppearance("texture", "horizontal")
    assert.are.equal(start + 2, s.appearanceVersion())
  end)

  it("shows the default target panel until hiding is chosen, keeping the texture beside it", function()
    local store = fakeStore()
    assert.is_false(savedappearance.load(store).appearance().hideTargetPanel)
    local s = savedappearance.load(store)
    s.setAppearance("texture", "horizontal")
    s.setAppearance("hideTargetPanel", true)
    local reloaded = savedappearance.load(store)
    assert.is_true(reloaded.appearance().hideTargetPanel)
    assert.are.equal("horizontal", reloaded.appearance().texture)
  end)

  it("hides the game's cast bar until showing it is chosen", function()
    local store = fakeStore()
    assert.is_true(savedappearance.load(store).appearance().hideCastBar)
    savedappearance.load(store).setAppearance("hideCastBar", false)
    assert.is_false(savedappearance.load(store).appearance().hideCastBar)
  end)

  it("shows the game's buff bars and plain aura icons until chosen otherwise", function()
    local store = fakeStore()
    local s = savedappearance.load(store)
    assert.are.same({ false, false }, { s.appearance().hideBuffBars, s.appearance().auraBars })
    s.setAppearance("hideBuffBars", true)
    s.setAppearance("auraBars", true)
    local reloaded = savedappearance.load(store)
    assert.are.same({ true, true }, { reloaded.appearance().hideBuffBars, reloaded.appearance().auraBars })
  end)
end)
