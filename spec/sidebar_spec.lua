local fake = require("spec/support/fake_ui")
local fakeStore = require("spec/support/fake_store")
local samples = require("spec/support/samples")
local settings = require("src/settings")
local sidebar = require("src/sidebar")

local label = samples.label

-- What the group window shows: three icon buttons in strip 18, a tab in no strip, the group size and the Ready
-- button in strip 0.
local function buttons()
  return {
    { static = 20, sprite = 25853, strip = 18 },
    { static = 19, sprite = 25851, strip = 18 },
    { static = 27, sprite = 25860, strip = 18 },
    { static = 31, sprite = 6028 },
    { text = "2/50", plain = true },
    { static = 6, text = "Ready", strip = 0 },
  }
end

-- A sidebar on a root, its layer placed at 0, 300 as src/view places an element. Returns it, the root, the
-- settings and a table whose blocked field stops a build.
local function create()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local state = { blocked = false, changes = 0, roles = 0 }
  local s = sidebar.create(root, {
    saved = saved,
    openRoles = function()
      state.roles = state.roles + 1
    end,
    blocked = function()
      return state.blocked
    end,
    changed = function()
      state.changes = state.changes + 1
    end,
  })
  s.layer:SetPos(0, 300)
  return s, root, saved, state
end

-- The shown sprite component showing sprite, or nil.
local function icon(sprite)
  return fake.find(function(_, d)
    return d.sprite == sprite
  end)
end

-- The shown tab's arrow canvas, or nil.
local function arrow()
  return fake.find(function(_, d)
    return d.rects ~= nil
  end)
end

-- Whether the tab's arrow narrows to a point on its left.
local function pointsLeft()
  local rects = arrow().rects
  return rects[1].x < rects[#rects].x
end

-- Clicks the tab under its arrow.
local function pressTab()
  local a = arrow()
  fake.hook(
    fake.find(function(_, d)
      return d.hooks.ONCLICK ~= nil and d.x == a.x and d.y == a.y
    end),
    "ONCLICK"
  )
end

describe("sidebar.column", function()
  it(
    "stacks the label, each strip's buttons two wide and its text buttons with a band per strip, then Roles",
    function()
      local column = sidebar.column(buttons(), 0, 300)
      assert.are.same({ 0, 300, 64, 164 }, { column.x, column.y, column.w, column.h })
      assert.are.same({ x = 6, y = 436, w = 52, h = 22 }, column.roles)
      assert.are.same({
        { x = 6, y = 306, w = 52, h = 16, text = "2/50", plain = true },
        { x = 6, y = 326, w = 24, h = 24, sprite = 25853, static = 20 },
        { x = 34, y = 326, w = 24, h = 24, sprite = 25851, static = 19 },
        { x = 6, y = 354, w = 24, h = 24, sprite = 25860, static = 27 },
        { x = 6, y = 382, w = 24, h = 24, sprite = 6028, static = 31 },
        { x = 6, y = 410, w = 52, h = 22, text = "Ready", static = 6 },
      }, column.tiles)
      assert.are.same({
        { strip = 18, x = 0, y = 326, w = 64, h = 56 },
        { strip = 0, x = 0, y = 410, w = 64, h = 26 },
      }, column.bands)
    end
  )
end)

describe("sidebar", function()
  before_each(fake.reset)

  it("draws the column at its layer with the tab inside its bounds, and writes nothing on a steady tick", function()
    local s = create()
    local column, moved = s.update(true, buttons())
    assert.are.same({ 0, 300, 64 }, { column.x, column.y, column.w })
    assert.is_true(moved)
    assert.are.same({ x = 0, y = 0, w = 80, h = 164 }, s.bounds)
    assert.are.same({ 8, 28 }, { icon(25853).x, icon(25853).y })
    assert.are.same({ 6, 110 }, { label("Ready").x, label("Ready").y })
    assert.is_truthy(label("2/50"))
    assert.are.same({ 64, 64 }, { arrow().x, arrow().y })
    assert.is_true(pointsLeft())
    fake.writes = 0
    local _, again = s.update(true, buttons())
    assert.is_false(again)
    assert.are.equal(0, fake.writes)
  end)

  it("follows its layer, giving the column in screen places", function()
    local s = create()
    s.layer:SetPos(900, 120)
    local column = s.update(true, buttons())
    assert.are.same({ 900, 120 }, { column.x, column.y })
    assert.are.same({ 906, 146 }, { column.tiles[2].x, column.tiles[2].y })
    assert.are.same({ 8, 28 }, { icon(25853).x, icon(25853).y })
  end)

  it("hides a tile whose button the game stops showing", function()
    local s = create()
    s.update(true, buttons())
    s.update(true, { { static = 20, sprite = 25853, strip = 18 } })
    assert.is_truthy(icon(25853))
    assert.is_nil(icon(25851))
    assert.is_nil(label("Ready"))
  end)

  it("folds to a bar with the tab from a press on it, saves that, gives no column, and unfolds", function()
    local s, _, saved, state = create()
    s.update(true, buttons())
    pressTab()
    assert.is_true(saved.sidebar().collapsed)
    assert.are.equal(1, state.changes)
    assert.is_nil(s.update(true, nil))
    assert.is_nil(label("Ready"))
    assert.is_nil(icon(25853))
    assert.are.same({ 8, 64 }, { arrow().x, arrow().y })
    assert.is_false(pointsLeft())
    assert.are.same({ x = 0, y = 0, w = 24, h = 164 }, s.bounds)
    pressTab()
    assert.is_false(saved.sidebar().collapsed)
    assert.is_truthy(s.update(true, buttons()))
    assert.is_truthy(label("Ready"))
  end)

  it("opens the Party page from its Roles button under the game's buttons, and hides it while folded", function()
    local s, _, _, state = create()
    s.update(true, buttons())
    assert.are.same({ 6, 136 }, { label("Roles").x, label("Roles").y })
    assert.are.equal(label("Ready").font, label("Roles").font)
    fake.press("Roles")
    assert.are.equal(1, state.roles)
    pressTab()
    s.update(true, nil)
    assert.is_nil(label("Roles"))
  end)

  it("says the cursor is on it while it rests on the game's buttons, redrawing as that changes", function()
    local s, _, _, state = create()
    s.update(true, buttons())
    local cover = fake.find(function(_, d)
      return d.hooks.ONMOUSEOVER ~= nil and d.width == 64 and d.height == 136
    end)
    assert.is_false(s.hovered)
    fake.hook(cover, "ONMOUSEOVER")
    assert.is_true(s.hovered)
    assert.are.equal(1, state.changes)
    fake.hook(cover, "ONMOUSELEAVE")
    assert.is_false(s.hovered)
    assert.are.equal(2, state.changes)
    fake.hook(cover, "ONMOUSEOVER")
    s.update(false, nil)
    assert.is_false(s.hovered)
  end)

  it("keeps only its layer while the window is not shown or the sidebar is off, when edit mode leaves it be", function()
    local s, root, saved = create()
    s.update(true, buttons())
    assert.is_true(fake.live(root) > 1)
    assert.is_true(s.inUse)
    assert.is_nil(s.update(false, nil))
    assert.are.equal(1, fake.live(root))
    s.update(true, buttons())
    saved.setSidebar("on", false)
    assert.is_nil(s.update(true, buttons()))
    assert.are.equal(1, fake.live(root))
    assert.is_false(s.inUse)
  end)

  it("does not build while the options window is open, and stays once built", function()
    local s, root, _, state = create()
    state.blocked = true
    assert.is_false(s.canDraw())
    s.update(true, buttons())
    assert.are.equal(1, fake.live(root))
    state.blocked = false
    s.update(true, buttons())
    local built = fake.live(root)
    state.blocked = true
    assert.is_true(s.canDraw())
    s.update(true, buttons())
    assert.are.equal(built, fake.live(root))
  end)
end)
