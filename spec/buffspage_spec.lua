local fake = require("spec/support/fake_ui")
local buffspage = require("src/buffspage")
local settings = require("src/settings")
local view = require("src/view")

local BONE_SHIELD = 30099
local ANTIFIRE = 30093
local BLOATED = 30098
local STUN_IMMUNE = 26104

local function fakeStore()
  local data = {}
  return {
    get = function(key)
      return data[key]
    end,
    set = function(key, value)
      data[key] = value
    end,
  }
end

-- The search's catalog: two boss debuffs on you, a buff on you and a debuff you inflict, none tracked by default.
local HOARY_CHILL = 41000
local SUNSHINE = 41002
local CATALOG = {
  { sprite = HOARY_CHILL, name = "Hoary Chill", struct = 41057, source = "Arch-Glacor", kind = "debuff" },
  { sprite = 41001, name = "Choking", struct = 41787, source = "Zamorak", kind = "debuff" },
  { sprite = SUNSHINE, name = "Sunshine", struct = 41700, source = "Abilities", kind = "buff" },
  { sprite = 41003, name = "Smoke Cloud", struct = 41800, source = "Magic", kind = "target", cause = "Smoke Cloud" },
}

-- Whether the search shows, by its field's placeholder.
local function searchShows(placeholder)
  return fake.find(function(_, d)
    return d.emptyText == placeholder
  end) ~= nil
end

-- A Buffs page with Bone Shield in combat buffs, an antifire in upkeep, and Stun Immune seen on a target.
-- info names every icon "Icon" unless given, and the search lists catalog, CATALOG unless given. Returns the
-- page, the settings, a count of HUD refreshes, the icons the search named, and the page layer.
local function open(info, catalog)
  local saved = settings.load(fakeStore())
  saved.learnAura(BONE_SHIELD, "combat")
  saved.learnAura(ANTIFIRE, "upkeep")
  saved.seeDebuff("target", STUN_IMMUNE)
  local root = fake.component()
  local layer = fake.component(root)
  local refreshed = { count = 0 }
  local learned = {}
  local page = buffspage.create(layer, 698, 498, {
    saved = saved,
    catalog = catalog or CATALOG,
    describe = function()
      return "Chills you.<br>More."
    end,
    learn = function(sprite, name, struct)
      learned[#learned + 1] = { sprite, name, struct }
      return true
    end,
    info = info or function()
      return { name = "Icon" }
    end,
    tooltip = view.tooltip(root),
    toScreen = function(x, y)
      return x, y
    end,
    refresh = function()
      refreshed.count = refreshed.count + 1
    end,
  })
  page.redraw()
  return page, saved, refreshed, learned, layer
end

local function shows(content)
  return fake.find(function(_, d)
    return d.content == content
  end) ~= nil
end

-- The hit area under the shown icon of sprite.
local function tileEdge(sprite)
  local icon = fake.find(function(_, d)
    return d.sprite == sprite
  end)
  return fake.find(function(c, d)
    return fake.hasHook(c, "ONRELEASE") and d.x == icon.x - 1 and d.y == icon.y - 1
  end)
end

-- Drags the icon of sprite from its middle to page position (x, y) and lets go.
local function dragTo(page, sprite, x, y)
  local edge = tileEdge(sprite)
  fake.mouse.x = edge.x + 15
  fake.mouse.y = edge.y + 15
  fake.hook(edge, "ONCLICK", 15, 15)
  fake.mouse.x = x
  fake.mouse.y = y
  page.follow()
  fake.hook(edge, "ONRELEASE")
end

local function click(edge)
  fake.mouse.x = 100
  fake.mouse.y = 100
  fake.hook(edge, "ONCLICK", 5, 5)
  fake.hook(edge, "ONRELEASE")
end

describe("buffspage", function()
  before_each(fake.reset)

  it("moves a buff to the group it is dragged onto", function()
    local page, saved, refreshed = open()
    local edge = tileEdge(BONE_SHIELD)
    local hidden = fake.find(function(_, d)
      return d.content == "Hidden"
    end)
    fake.mouse.x = edge.x + 5
    fake.mouse.y = edge.y + 5
    fake.hook(edge, "ONCLICK", 5, 5)
    fake.mouse.y = hidden.y + 30
    page.follow()
    fake.hook(edge, "ONRELEASE")
    assert.are.equal("hidden", saved.auras()[tostring(BONE_SHIELD)])
    assert.are.equal(1, refreshed.count)
  end)

  it("keeps a dragged icon's grab area under the cursor when the page redraws", function()
    local page = open()
    local edge = tileEdge(BONE_SHIELD)
    fake.mouse.x = edge.x + 5
    fake.mouse.y = edge.y + 5
    fake.hook(edge, "ONCLICK", 5, 5)
    fake.mouse.y = edge.y + 45
    page.follow()
    local at = { edge.x, edge.y, edge.width }
    page.redraw()
    assert.are.same(at, { edge.x, edge.y, edge.width })
  end)

  it("inserts a dragged icon between two others in its group, in the saved order", function()
    local page, saved = open()
    saved.learnAura(34177, "combat")
    saved.learnAura(34178, "combat")
    page.redraw()
    local after = tileEdge(34178)
    dragTo(page, BONE_SHIELD, after.x - 1, after.y + 15)
    assert.are.same({ ANTIFIRE, 34177, BONE_SHIELD, 34178 }, saved.orders().buffs)
  end)

  it("swaps a dragged icon with the one it lands on, trading groups", function()
    local page, saved = open()
    local other = tileEdge(ANTIFIRE)
    dragTo(page, BONE_SHIELD, other.x + 15, other.y + 15)
    assert.are.same({ "upkeep", "combat" }, { saved.auras()[tostring(BONE_SHIELD)], saved.auras()[tostring(ANTIFIRE)] })
    assert.are.same({ BONE_SHIELD, ANTIFIRE }, saved.orders().buffs)
  end)

  it("stops tracking a target debuff from the menu a click opens", function()
    local _, saved = open()
    fake.press("Debuffs you inflict")
    click(tileEdge(BLOATED))
    fake.press("Stop tracking")
    assert.is_false(saved.tracked("target")[tostring(BLOATED)])
    assert.are.equal(
      0.38,
      fake.find(function(_, d)
        return d.sprite == BLOATED
      end).alpha
    )
  end)

  it("marks an upkeep buff Keep up from its menu", function()
    local _, saved = open()
    assert.is_nil(fake.find(function(_, d)
      return d.content == "K"
    end))
    click(tileEdge(ANTIFIRE))
    fake.press("Keep up: off")
    assert.is_true(saved.keepUp()[tostring(ANTIFIRE)])
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "K"
    end))
  end)

  it("says a name is being looked up in an icon's tooltip until it loads", function()
    open(function()
      return nil
    end)
    fake.hook(tileEdge(BONE_SHIELD), "ONMOUSEOVER")
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Looking up name"
    end))
  end)

  it("makes no client writes when redrawn unchanged", function()
    local page = open()
    fake.writes = 0
    page.redraw()
    assert.are.equal(0, fake.writes)
  end)

  it("tracks a debuff from the search, naming it at once, and stops tracking it from Tracked", function()
    local _, saved, _, learned, layer = open()
    fake.press("Debuffs on you")
    fake.press("Find debuffs")
    assert.is_true(searchShows("Find a debuff or boss"))
    assert.is_false(shows("Smoke Cloud"))
    assert.is_true(shows("Chills you."))
    fake.press("Track", 2)
    assert.is_true(saved.tracked("player")[tostring(HOARY_CHILL)])
    assert.are.same({ { HOARY_CHILL, "Hoary Chill", 41057 } }, learned)
    assert.are.equal("Hoary Chill", saved.debuffs()[tostring(HOARY_CHILL)].name)
    assert.is_not_nil(fake.find(function(_, d)
      return d.parent == layer and d.sprite == HOARY_CHILL
    end))
    assert.is_true(shows("1 of 2 tracked"))
    -- The first "Tracked" is the group heading; the second is the row's button.
    fake.press("Tracked", 2)
    assert.is_false(saved.tracked("player")[tostring(HOARY_CHILL)])
  end)

  it("tracks a buff from the search into combat buffs, listing no debuff", function()
    local _, saved = open()
    fake.press("Find buffs")
    assert.is_false(shows("Hoary Chill"))
    fake.press("Track")
    assert.are.equal("combat", saved.auras()[tostring(SUNSHINE)])
  end)

  it("lists only debuffs you inflict on the target tab, by combat style", function()
    local _, saved = open()
    fake.press("Debuffs you inflict")
    fake.press("Find debuffs")
    assert.is_true(searchShows("Find a debuff or ability"))
    assert.are.same({ true, false }, { shows("From Smoke Cloud"), shows("Hoary Chill") })
    fake.press("Magic")
    fake.press("Track")
    assert.is_true(saved.tracked("target")["41003"])
  end)

  it("closes the search by its X, and with the page's popups", function()
    local page = open()
    fake.press("Find buffs")
    assert.is_true(page.popupOpen())
    fake.hook(
      fake.find(function(c, d)
        return fake.hasHook(c, "ONCLICK") and d.width == 22 and d.height == 22
      end),
      "ONCLICK"
    )
    assert.is_false(searchShows("Find a buff or boss"))
    fake.press("Find buffs")
    page.close()
    assert.is_false(page.popupOpen())
    assert.is_false(searchShows("Find a buff or boss"))
  end)

  it("closes the search on a click on an icon beside it, opening no menu", function()
    local page = open()
    fake.press("Find buffs")
    click(tileEdge(BONE_SHIELD))
    assert.is_false(page.popupOpen())
  end)

  it("scrolls the effect list by the wheel, hiding rows out of view", function()
    local catalog = {}
    for i = 1, 20 do
      catalog[i] =
        { sprite = 50000 + i, name = string.format("Effect %02d", i), struct = i, source = "General", kind = "buff" }
    end
    open(nil, catalog)
    fake.press("Find buffs")
    local first = fake.find(function(_, d)
      return d.content == "Effect 01"
    end)
    local bg = fake.find(function(c, d)
      return d.parent == first.parent and fake.hasHook(c, "ONSCROLLWHEEL")
    end)
    for _ = 1, 200 do
      fake.hook(bg, "ONSCROLLWHEEL", -1)
    end
    assert.is_false(shows("Effect 01"))
    assert.is_true(shows("Effect 20"))
  end)

  it("makes no client writes on a steady redraw with the search open", function()
    local page = open()
    fake.press("Find buffs")
    fake.writes = 0
    page.redraw()
    assert.are.equal(0, fake.writes)
  end)
end)
