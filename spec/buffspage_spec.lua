local fake = require("spec/support/fake_ui")
local buffspage = require("src/buffspage")
local settings = require("src/settings")
local view = require("src/view")

local BONE_SHIELD, ANTIFIRE, BLOATED, STUN_IMMUNE = 30099, 30093, 30098, 26104

local function fakeStore()
  local data = {}
  return { get = function(key) return data[key] end, set = function(key, value) data[key] = value end }
end

-- A Buffs page with Bone Shield in combat buffs, an antifire in upkeep, and Stun Immune seen on a target.
-- info names every icon "Icon" unless given.
local function open(info)
  local saved = settings.load(fakeStore())
  saved.learnAura(BONE_SHIELD, "combat")
  saved.learnAura(ANTIFIRE, "upkeep")
  saved.seeDebuff("target", STUN_IMMUNE)
  local root = fake.component()
  local refreshed = { count = 0 }
  local page = buffspage.create(fake.component(root), 698, 498, {
    saved = saved,
    info = info or function() return { name = "Icon" } end,
    tooltip = view.tooltip(root),
    toScreen = function(x, y) return x, y end,
    refresh = function() refreshed.count = refreshed.count + 1 end,
  })
  page.redraw()
  return page, saved, refreshed
end

-- The hit area under the shown icon of sprite.
local function tileEdge(sprite)
  local icon = fake.find(function(_, d) return d.sprite == sprite end)
  return fake.find(function(c, d) return fake.hasHook(c, "ONRELEASE") and d.x == icon.x - 1 and d.y == icon.y - 1 end)
end

local function click(edge)
  fake.mouse.x, fake.mouse.y = 100, 100
  fake.hook(edge, "ONCLICK", 5, 5)
  fake.hook(edge, "ONRELEASE")
end

describe("buffspage", function()
  before_each(fake.reset)

  it("moves a buff to the group it is dragged onto", function()
    local page, saved, refreshed = open()
    local edge = tileEdge(BONE_SHIELD)
    local hidden = fake.find(function(_, d) return d.content == "Hidden" end)
    fake.mouse.x, fake.mouse.y = edge.x + 5, edge.y + 5
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
    fake.mouse.x, fake.mouse.y = edge.x + 5, edge.y + 5
    fake.hook(edge, "ONCLICK", 5, 5)
    fake.mouse.y = edge.y + 45
    page.follow()
    local at = { edge.x, edge.y, edge.width }
    page.redraw()
    assert.are.same(at, { edge.x, edge.y, edge.width })
  end)

  it("stops tracking a target debuff from the menu a click opens", function()
    local _, saved = open()
    fake.press("Target debuffs")
    click(tileEdge(BLOATED))
    fake.press("Stop tracking")
    assert.is_false(saved.tracked("target")[tostring(BLOATED)])
    assert.are.equal(0.38, fake.find(function(_, d) return d.sprite == BLOATED end).alpha)
  end)

  it("marks an upkeep buff Keep up from its menu", function()
    local _, saved = open()
    assert.is_nil(fake.find(function(_, d) return d.content == "K" end))
    click(tileEdge(ANTIFIRE))
    fake.press("Keep up: off")
    assert.is_true(saved.keepUp()[tostring(ANTIFIRE)])
    assert.is_not_nil(fake.find(function(_, d) return d.content == "K" end))
  end)

  it("says a name is being looked up in an icon's tooltip until it loads", function()
    open(function() return nil end)
    fake.hook(tileEdge(BONE_SHIELD), "ONMOUSEOVER")
    assert.is_not_nil(fake.find(function(_, d) return d.content == "Looking up name" end))
  end)

  it("makes no client writes when redrawn unchanged", function()
    local page = open()
    fake.writes = 0
    page.redraw()
    assert.are.equal(0, fake.writes)
  end)
end)
