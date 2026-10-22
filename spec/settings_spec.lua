local presets = require("src/presets")
local settings = require("src/settings")

-- An in-memory stand-in for src/adapter's PersistentDB store that counts writes.
local function fakeStore(data)
  local store = { data = data or {}, writes = 0 }
  function store.get(key)
    return store.data[key]
  end
  function store.set(key, value)
    store.writes = store.writes + 1
    store.data[key] = value
  end
  return store
end

-- Saved data from this layout version, so positions and anchors in it are kept.
local CURRENT = { layout = settings.LAYOUT_VERSION }

-- Saved groups that every style and Utility have been seeded into from src/presets.
-- The position of key in list, or nil.
local function indexOfKey(list, key)
  for i, k in ipairs(list) do
    if k == key then
      return i
    end
  end
end

local SEEDED = { utility = true, defensives = true, necromancy = true, magic = true, ranged = true, melee = true }

-- A store whose seeded groups hold groups, { [name] = saved group }.
local function seededStore(groups)
  return fakeStore({ cooldownGroups = { seeded = SEEDED, groups = groups or {} } })
end

-- Magic's major holds X and Y and its rotation A, B and C; the shared utility holds U.
local function edited()
  return settings.load(seededStore({
    major = { styles = { magic = { "X", "Y" } } },
    rotation = { styles = { magic = { "A", "B", "C" } } },
    utility = { keys = { "U" } },
  }))
end

describe("settings", function()
  it("round-trips positions, groups, markers and known abilities through the store", function()
    local store = seededStore()
    local s = settings.load(store)
    s.setPosition("player", { x = 10, y = -20, anchorX = 0.5, anchorY = 1 })
    s.add("rotation", "magic", "MAGIC_DRAGON_BREATH")
    s.setMarker("threshold", 60)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)

    local reloaded = settings.load(store)
    assert.are.same({ x = 10, y = -20, anchorX = 0.5, anchorY = 1 }, reloaded.positions().player)
    assert.are.same({ "MAGIC_DRAGON_BREATH" }, reloaded.keys("rotation", "magic"))
    assert.are.same({}, reloaded.keys("rotation", "ranged"))
    assert.are.equal(60, reloaded.markers().threshold)
    assert.are.same({ name = "Dragon Breath", icon = 14730 }, reloaded.known().MAGIC_DRAGON_BREATH)
  end)

  it("loads a second charge's or recast stage's saved key as its ability's, keeping one of each", function()
    local s = settings.load(seededStore({
      utility = { keys = { "MAGIC_SURGE_CHARGE2", "MAGIC_SURGE", "RANGED_ESCAPE_CHARGE2" } },
    }))
    assert.are.same({ "MAGIC_SURGE", "RANGED_ESCAPE" }, s.keys("utility", "magic"))
  end)

  it("loads a name saved under a second charge as its ability's and drops one saved under a recast stage", function()
    local s = settings.load(fakeStore({
      known = {
        MAGIC_SURGE_CHARGE2 = { name = "Surge", icon = 14233 },
        MELEE_DISMEMBER_RECAST_2 = { name = "Slaughter", icon = 21362 },
      },
    }))
    assert.are.same({ MAGIC_SURGE = { name = "Surge", icon = 14233 } }, s.known())
  end)

  it("fills every style and Utility from the presets on the first load", function()
    local s = settings.load(fakeStore())
    for style, lists in pairs(presets.STYLES) do
      assert.are.same(lists.major, s.keys("major", style), style)
      assert.are.same(lists.rotation, s.keys("rotation", style), style)
    end
    assert.are.same(presets.UTILITY, s.keys("utility", "melee"))
  end)

  it("fills only styles with nothing in them, once, so a style emptied on purpose stays empty", function()
    local store = fakeStore({ cooldownGroups = { groups = { rotation = { styles = { magic = { "A" } } } } } })
    local s = settings.load(store)
    assert.are.same({ { "A" }, {} }, { s.keys("rotation", "magic"), s.keys("major", "magic") })
    assert.are.same(presets.STYLES.ranged.rotation, s.keys("rotation", "ranged"))
    for _, key in ipairs(presets.STYLES.ranged.rotation) do
      s.remove(key, "ranged")
    end
    assert.are.same({}, settings.load(store).keys("rotation", "ranged"))
  end)

  it("leaves a preset ability out of a style where another list already shows it", function()
    local s = settings.load(fakeStore({
      cooldownGroups = {
        seeded = { utility = true },
        groups = {
          utility = { keys = { "MAGIC_SUNSHINE" } },
        },
      },
    }))
    local major = { table.unpack(presets.STYLES.magic.major, 2) }
    assert.are.equal("MAGIC_SUNSHINE", presets.STYLES.magic.major[1])
    assert.are.same(major, s.keys("major", "magic"))
    assert.are.same({ "MAGIC_SUNSHINE" }, s.keys("utility", "magic"))
  end)

  it("shows a per-style group as empty until a style is known", function()
    assert.are.same({}, settings.load(fakeStore()).keys("major", nil))
  end)

  it("resets positions to the defaults and keeps groups", function()
    local s = edited()
    s.setPosition("player", { x = 1, y = 2, anchorX = 0, anchorY = 0 })
    s.resetPositions()
    assert.are.same(settings.DEFAULT_POSITIONS.player, s.positions().player)
    assert.are.same({ "A", "B", "C" }, s.keys("rotation", "magic"))
  end)

  it("drops positions and anchors saved for an older default layout once", function()
    local store = fakeStore({
      layout = { player = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 } },
      anchors = { player = { target = "target", side = "left", align = "top", gap = 0, offset = 0 } },
    })
    local s = settings.load(store)
    assert.are.same(settings.DEFAULT_ANCHORS, s.anchors())
    s.setPosition("target", { x = 7, y = 8, anchorX = 0.5, anchorY = 1 })
    assert.are.equal(7, settings.load(store).positions().target.x)
  end)

  it("round-trips anchors through the store, restoring floats as integers", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.setAnchor("player", { target = "target", side = "top", align = "left", gap = 4, offset = -3 })
    local saved = store.data.anchors.player
    saved.gap = 4.0
    saved.offset = -3.0
    local anchor = settings.load(store).anchors().player
    assert.are.same({ target = "target", side = "top", align = "left", gap = 4, offset = -3 }, anchor)
    assert.are.equal("integer", math.type(anchor.gap))
  end)

  it("anchors an element added since anchors were saved by its default, until it is placed", function()
    local store = fakeStore({
      anchors = { player = { target = "rotation", side = "left", align = "bottom", gap = 0, offset = 0 } },
      layout = { target = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 } },
      version = CURRENT,
    })
    local anchors = settings.load(store).anchors()
    assert.are.same(settings.DEFAULT_ANCHORS.playerDebuffs, anchors.playerDebuffs)
    assert.is_nil(anchors.target)
  end)

  it("removes an anchor, keeping it removed across loads", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.setPosition("player", { x = 1, y = 2, anchorX = 0.5, anchorY = 1 })
    s.removeAnchor("player")
    assert.is_nil(settings.load(store).anchors().player)
    assert.is_not_nil(settings.load(store).anchors().target)
  end)

  it("drops saved anchors with unknown elements, sides or alignments, and cycles", function()
    local s = settings.load(fakeStore({
      version = CURRENT,
      anchors = {
        player = { target = "rotation", side = "left", align = "left", gap = 0, offset = 0 },
        rotation = { target = "player", side = "under", align = "top", gap = 0, offset = 0 },
        target = { target = "target", side = "left", align = "top", gap = 0, offset = 0 },
        resource = { target = "nowhere", side = "top", align = "center", gap = 0, offset = 0 },
        major = { target = "resource", side = "top", align = "center", gap = 2.0, offset = 0 },
        bogus = { target = "player", side = "left", align = "top", gap = 0, offset = 0 },
      },
    }))
    local anchors = s.anchors()
    assert.are.same({ target = "resource", side = "top", align = "center", gap = 2, offset = 0 }, anchors.major)
    assert.is_nil(anchors.player or anchors.rotation or anchors.target or anchors.resource or anchors.bogus)
  end)

  it("resets anchors to the defaults along with positions", function()
    local s = settings.load(fakeStore())
    assert.are.same(settings.DEFAULT_ANCHORS, s.anchors())
    s.removeAnchor("player")
    s.setAnchor("target", { target = "player", side = "left", align = "top", gap = 0, offset = 0 })
    s.resetPositions()
    assert.are.same(settings.DEFAULT_ANCHORS, s.anchors())
  end)

  it("raises the default HUD to keep the major group 31.5% of the window height above its bottom", function()
    for height, majorY in pairs({ [1041] = -328, [1440] = -454 }) do
      local positions = settings.load(fakeStore(), height).positions()
      local shift = majorY - settings.DEFAULT_POSITIONS.major.y
      assert.are.equal(majorY, positions.major.y)
      assert.are.equal(settings.DEFAULT_POSITIONS.player.y + shift, positions.player.y)
      assert.are.equal(settings.DEFAULT_POSITIONS.major.x, positions.major.x)
    end
  end)

  it("snaps by default and saves turning it off", function()
    local store = fakeStore()
    assert.is_true(settings.load(store).snap())
    settings.load(store).setSnap(false)
    assert.is_false(settings.load(store).snap())
  end)

  it("adds to the end of a style's list, taking the ability out of every list shown with that style", function()
    local s = edited()
    s.add("rotation", "magic", "X")
    s.add("rotation", "magic", "U")
    assert.are.same({ "A", "B", "C", "X", "U" }, s.keys("rotation", "magic"))
    assert.are.same({ "Y" }, s.keys("major", "magic"))
    assert.are.same({}, s.keys("utility", "ranged"))
    assert.are.same({}, s.keys("rotation", "ranged"))
  end)

  it("refuses an ability once a list holds 20", function()
    local s = edited()
    for i = 1, 17 do
      assert.is_true(s.add("rotation", "magic", "K" .. i))
    end
    assert.is_false(s.add("rotation", "magic", "X"))
    assert.are.same({ "X", "Y" }, s.keys("major", "magic"))
  end)

  it("removes an ability from whichever list holds it for that style", function()
    local s = edited()
    s.remove("B", "magic")
    assert.are.same({ "A", "C" }, s.keys("rotation", "magic"))
  end)

  it("moves and swaps abilities within a group's list", function()
    local s = edited()
    s.move("C", "rotation", "magic", 1)
    assert.are.same({ "C", "A", "B" }, s.keys("rotation", "magic"))
    s.swap("C", "B", "rotation", "magic")
    assert.are.same({ "B", "A", "C" }, s.keys("rotation", "magic"))
  end)

  it("keeps both lists when a group switches between shared and per style", function()
    local s = edited()
    s.setGroup("rotation", "shared", true)
    assert.are.same({}, s.keys("rotation", "magic"))
    s.add("rotation", "magic", "S")
    s.setGroup("rotation", "shared", false)
    assert.are.same({ "A", "B", "C" }, s.keys("rotation", "magic"))
    s.setGroup("rotation", "shared", true)
    assert.are.same({ "S" }, s.keys("rotation", "ranged"))
  end)

  it("clamps display settings and restores them from the store as integers", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.setGroup("major", "size", 80)
    s.setGroup("major", "perRow", 0)
    s.setGroup("major", "grow", "sideways")
    s.setGroup("major", "grow", "left")
    store.data.cooldownGroups.groups.major.size = 56.0
    local major = settings.load(store).group("major")
    assert.are.same({ 56, 1, "left" }, { major.size, major.perRow, major.grow })
    assert.are.equal("integer", math.type(major.size))
  end)

  it("leaves out of Defensives a defensive another style's list already holds", function()
    local seeded = { utility = true, necromancy = true, magic = true, ranged = true, melee = true }
    local s = settings.load(fakeStore({
      version = CURRENT,
      cooldownGroups = {
        seeded = seeded,
        groups = {
          rotation = { styles = { magic = { "DEFENCE_FREEDOM" } } },
        },
      },
    }))
    assert.is_nil(indexOfKey(s.group("custom1").keys, "DEFENCE_FREEDOM"))
    assert.are.equal(#presets.DEFENSIVES - 1, #s.group("custom1").keys)
  end)

  it("starts with Defensives as the first custom group, adds up to three more, and deletes only custom ones", function()
    local store = fakeStore()
    local s = settings.load(store)
    assert.are.same({ "Defensives", presets.DEFENSIVES }, { s.group("custom1").title, s.group("custom1").keys })
    assert.are.same({ "custom2", "custom3", "custom4" }, { s.addGroup(), s.addGroup(), s.addGroup() })
    assert.is_nil(s.addGroup())
    s.setGroup("custom2", "title", "Defensives and more than twenty")
    s.deleteGroup("custom1")
    s.deleteGroup("major")
    local reloaded = settings.load(store)
    assert.are.same({ "major", "rotation", "utility", "custom2", "custom3", "custom4" }, reloaded.groupNames())
    assert.are.equal("Defensives and more", reloaded.group("custom2").title)
    assert.is_true(reloaded.group("custom2").shared)
    assert.are.equal("custom1", reloaded.addGroup())
  end)

  it("splits groups saved by the older version across styles", function()
    local store = fakeStore({
      groups = {
        rotation = { "MAGIC_WRACK", "NECROMANCY_TOUCH_OF_DEATH", "DEFENCE_FREEDOM" },
        cooldowns = { "MAGIC_SUNSHINE", "WEAPON_INSTABILITY" },
      },
    })
    local s = settings.load(store)
    assert.are.same({ "MAGIC_WRACK" }, s.keys("rotation", "magic"))
    assert.are.same({ "NECROMANCY_TOUCH_OF_DEATH" }, s.keys("rotation", "necromancy"))
    assert.are.same({ "MAGIC_SUNSHINE", "WEAPON_INSTABILITY" }, s.keys("major", "magic"))
    assert.are.same({ "WEAPON_INSTABILITY" }, s.keys("major", "ranged"))
    assert.are.same({ "DEFENCE_FREEDOM" }, s.keys("utility", "melee"))
    assert.is_not_nil(store.data.groups.cooldowns)
  end)

  it("fills a style the older version's groups left empty from the presets", function()
    local s = settings.load(fakeStore({ groups = { rotation = { "MAGIC_WRACK" }, cooldowns = {} } }))
    assert.are.same({ "MAGIC_WRACK" }, s.keys("rotation", "magic"))
    assert.are.same(presets.STYLES.melee.major, s.keys("major", "melee"))
    assert.are.same(presets.UTILITY, s.keys("utility", "magic"))
  end)

  it("keeps aura names with their struct id and unmatched icons across loads, dropping malformed entries", function()
    local store = fakeStore({
      namesVersion = { version = 3 },
      debuffs = { ["1"] = "broken", ["2"] = { name = "Old", struct = "x" } },
    })
    local saved = settings.load(store)
    saved.learnDebuff(30098, "Bloated", 5401.0)
    saved.learnDebuff(14766)
    assert.are.same({
      ["30098"] = { name = "Bloated", struct = 5401 },
      ["14766"] = { unmatched = true },
      ["2"] = { name = "Old" },
    }, settings.load(store).debuffs())
  end)

  it("saves a learned ability only when its name or icon changed", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    local writes = store.writes
    s.learn("MAGIC_DRAGON_BREATH", "Dragon Breath", 14730)
    assert.are.equal(writes, store.writes)
  end)

  it("clamps marker percents to 0 through 100", function()
    local s = settings.load(fakeStore())
    s.setMarker("ultimate", 150)
    s.setMarker("threshold", -5)
    assert.are.same({ threshold = 0, ultimate = 100 }, s.markers())
  end)

  it("keeps bars flat until a known texture is chosen, and saves the choice", function()
    local store = fakeStore()
    assert.are.equal("flat", settings.load(store).appearance().texture)
    settings.load(store).setAppearance("texture", "vertical")
    assert.are.equal("vertical", settings.load(store).appearance().texture)
    assert.are.equal("flat", settings.load(fakeStore({ appearance = { texture = "plaid" } })).appearance().texture)
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
    local s = settings.load(store)
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
      hideBarStats = false,
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
    }
    for field, value in pairs(chosen) do
      s.setAppearance(field, value)
    end
    local reloaded = settings.load(store).appearance()
    for field, value in pairs(chosen) do
      assert.are.equal(value, reloaded[field])
    end
  end)

  it("reads unknown and malformed appearance values as their defaults", function()
    local s = settings.load(fakeStore({
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

  it("saves the action bar fade settings and reads a bad opacity, flag or stats choice as its default", function()
    local store = fakeStore()
    local s = settings.load(store)
    s.setAppearance("barOpacity2", 40.0)
    s.setAppearance("fadeBar3", true)
    s.setAppearance("hoverBar5", false)
    s.setAppearance("hideBarStats", true)
    local reloaded = settings.load(store).appearance()
    assert.are.same({ 40, true, false, true }, {
      reloaded.barOpacity2,
      reloaded.fadeBar3,
      reloaded.hoverBar5,
      reloaded.hideBarStats,
    })
    assert.are.equal(math.type(40), math.type(reloaded.barOpacity2))
    for _, opacity in ipairs({ 37, -5, 105, "x" }) do
      assert.are.equal(
        25,
        settings.load(fakeStore({ appearance = { barOpacity1 = opacity } })).appearance().barOpacity1
      )
    end
    local bad = settings.load(fakeStore({ appearance = { fadeBar1 = "yes", hoverBar2 = 0, hideBarStats = "hide" } }))
    assert.are.same({ false, true, false }, {
      bad.appearance().fadeBar1,
      bad.appearance().hoverBar2,
      bad.appearance().hideBarStats,
    })
  end)

  it("reads a saved hex colour and size back as whole numbers, and counts appearance changes", function()
    local s = settings.load(fakeStore({ appearance = { playerColour = 1193046.0, frameWidth = 300.0 } }))
    assert.are.equal(math.type(1193046), math.type(s.appearance().playerColour))
    assert.are.equal(math.type(300), math.type(s.appearance().frameWidth))
    local start = s.appearanceVersion()
    s.setAppearance("edge", "outline")
    s.setAppearance("texture", "horizontal")
    assert.are.equal(start + 2, s.appearanceVersion())
  end)

  it("shows the default target panel until hiding is chosen, keeping the texture beside it", function()
    local store = fakeStore()
    assert.is_false(settings.load(store).appearance().hideTargetPanel)
    local s = settings.load(store)
    s.setAppearance("texture", "horizontal")
    s.setAppearance("hideTargetPanel", true)
    local reloaded = settings.load(store)
    assert.is_true(reloaded.appearance().hideTargetPanel)
    assert.are.equal("horizontal", reloaded.appearance().texture)
  end)

  it("keeps the first category learned for each buff icon across loads, dropping malformed entries", function()
    local store = fakeStore({ auras = { ["1"] = "sideways", ["2"] = 5 } })
    local s = settings.load(store)
    s.learnAura(30093, "upkeep")
    s.learnAura(30093, "combat")
    s.learnAura(26466, "hidden")
    assert.are.same({ ["30093"] = "upkeep", ["26466"] = "hidden" }, settings.load(store).auras())
  end)

  it("hides the game's cast bar until showing it is chosen", function()
    local store = fakeStore()
    assert.is_true(settings.load(store).appearance().hideCastBar)
    settings.load(store).setAppearance("hideCastBar", false)
    assert.is_false(settings.load(store).appearance().hideCastBar)
  end)

  it("moves a buff between rows and marks Keep up across loads, dropping malformed entries", function()
    local store = fakeStore({ keepUp = { ["1"] = "yes" } })
    local s = settings.load(store)
    s.learnAura(30099, "combat")
    s.setAuraCategory(30099, "hidden")
    s.setKeepUp(30093, true)
    s.setKeepUp(14695, true)
    s.setKeepUp(14695, false)
    local reloaded = settings.load(store)
    assert.are.same({ { ["30099"] = "hidden" }, { ["30093"] = true } }, { reloaded.auras(), reloaded.keepUp() })
  end)

  it("lists each debuff seen once and keeps tracked choices per kind, dropping malformed entries", function()
    local store = fakeStore({ trackedTarget = { ["1"] = 5 } })
    local s = settings.load(store)
    s.seeDebuff("target", 26104)
    local writes = store.writes
    s.seeDebuff("target", 26104)
    assert.are.equal(writes, store.writes)
    s.setTracked("target", 30098, false)
    s.seeDebuff("target", 30098)
    s.setTracked("player", 26103, true)
    local reloaded = settings.load(store)
    assert.are.same({ ["26104"] = "seen", ["30098"] = false }, reloaded.tracked("target"))
    assert.are.same({ ["26103"] = true }, reloaded.tracked("player"))
  end)

  it("drops icon keys that are not whole numbers from every icon map, keeping item icons", function()
    local s = settings.load(fakeStore({
      namesVersion = { version = 3 },
      debuffs = { abc = { name = "Broken" }, ["30098"] = { name = "Bloated" } },
      auras = { abc = "upkeep", ["-49039"] = "upkeep" },
      keepUp = { ["1.5"] = true, ["-49039"] = true },
      trackedTarget = { abc = true, ["30098"] = "seen" },
    }))
    assert.are.same({
      { ["30098"] = { name = "Bloated" } },
      { ["-49039"] = "upkeep" },
      { ["-49039"] = true },
      { ["30098"] = "seen" },
    }, { s.debuffs(), s.auras(), s.keepUp(), s.tracked("target") })
  end)

  it("keeps each kind's icon order across loads, dropping entries that are not whole numbers", function()
    local store = fakeStore({ orderTarget = { 30098.0, "x", 1.5, 14395 } })
    local s = settings.load(store)
    s.setOrder("buffs", { 27432, -49039 })
    local orders = settings.load(store).orders()
    assert.are.same({ { 27432, -49039 }, { 30098, 14395 }, {} }, { orders.buffs, orders.target, orders.player })
  end)

  it("counts each change to aura rows, tracking or order, and not a repeat of a known icon", function()
    local s = settings.load(fakeStore())
    local start = s.auraVersion()
    s.learnAura(30099, "combat")
    s.learnAura(30099, "upkeep")
    s.seeDebuff("target", 26104)
    s.seeDebuff("target", 26104)
    s.setAuraCategory(30099, "hidden")
    s.setTracked("target", 26104, true)
    s.setOrder("buffs", { 30099 })
    assert.are.equal(start + 5, s.auraVersion())
  end)

  it("drops aura names saved before the current naming rule once", function()
    local store = fakeStore({ namesVersion = { version = 2 }, debuffs = { ["30097"] = { name = "Delirium" } } })
    assert.are.same({}, settings.load(store).debuffs())
    settings.load(store).learnDebuff(30097, "Poisoned")
    assert.are.same({ ["30097"] = { name = "Poisoned" } }, settings.load(store).debuffs())
  end)

  it("shows the game's buff bars and plain aura icons until chosen otherwise", function()
    local store = fakeStore()
    local s = settings.load(store)
    assert.are.same({ false, false }, { s.appearance().hideBuffBars, s.appearance().auraBars })
    s.setAppearance("hideBuffBars", true)
    s.setAppearance("auraBars", true)
    local reloaded = settings.load(store)
    assert.are.same({ true, true }, { reloaded.appearance().hideBuffBars, reloaded.appearance().auraBars })
  end)

  it("restores whole numbers that PersistentDB returns as floats as integers", function()
    local s = settings.load(fakeStore({
      version = CURRENT,
      layout = { player = { x = -427.0, y = -429.0, anchorX = 0.5, anchorY = 1.0 } },
      known = { A = { name = "Alpha", icon = 34171.0 } },
      markers = { threshold = 55.0, ultimate = 100.0 },
    }))
    assert.are.equal("integer", math.type(s.positions().player.x))
    assert.are.equal("integer", math.type(s.known().A.icon))
    assert.are.equal("integer", math.type(s.markers().threshold))
    assert.are.equal(0.5, s.positions().player.anchorX)
  end)

  it("ignores unknown keys and malformed values in saved data", function()
    local s = settings.load(fakeStore({
      version = CURRENT,
      layout = { player = { x = "far", y = 0 }, target = { x = 5, y = 6, anchorX = 0.5, anchorY = 1 }, bogus = {} },
      cooldownGroups = {
        seeded = SEEDED,
        groups = {
          rotation = { styles = { magic = { "A", 7 }, ranged = "nope" }, size = "big", grow = "sideways" },
          major = "broken",
          custom2 = 5,
          extra = { keys = { "Z" } },
        },
      },
      markers = { threshold = "high", ultimate = 90 },
      known = { A = { name = "Alpha", icon = 1 }, B = "broken" },
      editMode = 5,
    }))
    assert.are.same(settings.DEFAULT_POSITIONS.player, s.positions().player)
    assert.are.equal(5, s.positions().target.x)
    assert.is_nil(s.positions().bogus)
    assert.are.same({ "A" }, s.keys("rotation", "magic"))
    assert.are.same({}, s.keys("rotation", "ranged"))
    assert.are.same({ 45, "down" }, { s.group("rotation").size, s.group("rotation").grow })
    assert.are.same({ "major", "rotation", "utility" }, s.groupNames())
    assert.are.same({ threshold = 50, ultimate = 90 }, s.markers())
    assert.are.same({ A = { name = "Alpha", icon = 1 } }, s.known())
    assert.is_true(s.snap())
  end)
end)
