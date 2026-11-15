local fake = require("spec/support/fake_ui")
local fakeStore = require("spec/support/fake_store")
local samples = require("spec/support/samples")
local settings = require("src/settings")
local sidebar = require("src/sidebar")

local label = samples.label

local READS = {
  open = true,
  title = "Oakhelm's group",
  rows = {
    { name = "Oakhelm", rank = 25847, lifepoints = "9400/12000" },
    { name = "Mirelle", rank = 25848, lifepoints = "6000/12000" },
  },
}

-- The group window at 100, 200 with its content from y 220 and its list from y 250: a set status button, the
-- group size and the Ready button, and both members' rows.
local function layout()
  return {
    open = true,
    x = 100,
    y = 200,
    w = 265,
    h = 290,
    top = 220,
    listX = 104,
    listY = 250,
    listW = 257,
    listH = 168,
    tiles = {
      { x = 107, y = 223, w = 24, h = 24, sprite = 25853 },
      { x = 295, y = 223, w = 26, h = 24, text = "2/50", plain = true },
      { x = 114, y = 453, w = 237, h = 27, text = "Ready" },
    },
    rows = { { x = 109, y = 267, w = 247, h = 38 }, { x = 109, y = 305, w = 247, h = 38 } },
  }
end

-- A sidebar on a root. Returns it, the root, the settings and a table whose blocked field stops a build.
local function create()
  local root = fake.component()
  local saved = settings.load(fakeStore())
  local state = { blocked = false, changes = 0 }
  local s = sidebar.create(root, {
    saved = saved,
    blocked = function()
      return state.blocked
    end,
    changed = function()
      state.changes = state.changes + 1
    end,
  })
  return s, root, saved, state
end

-- The shown sprite component showing sprite, or nil.
local function icon(sprite)
  return fake.find(function(_, d)
    return d.sprite == sprite
  end)
end

describe("sidebar", function()
  before_each(fake.reset)

  it(
    "draws the title, a tile at each button's place and a row at each member's, and writes nothing on a steady tick",
    function()
      local s = create()
      s.update(layout(), READS)
      assert.is_truthy(label("Oakhelm's group"))
      assert.are.same({ 339, 200 }, { label("x").x, label("x").y })
      assert.are.same({ 109, 225 }, { icon(25853).x, icon(25853).y })
      assert.are.same({ 114, 453 }, { label("Ready").x, label("Ready").y })
      assert.is_truthy(label("2/50"))
      assert.are.same({ 117, 270 }, { label("Oakhelm").x, label("Oakhelm").y })
      assert.are.equal(308, label("Mirelle").y)
      assert.is_truthy(label("6,000"))
      assert.is_truthy(icon(25847))
      assert.is_nil(icon(25848))
      fake.writes = 0
      s.update(layout(), READS)
      assert.are.equal(0, fake.writes)
    end
  )

  it("follows the window when it moves and hides a tile whose button the game hides", function()
    local s = create()
    s.update(layout(), READS)
    local moved = layout()
    moved.tiles = { { x = 207, y = 223, w = 24, h = 24, sprite = 25853 } }
    s.update(moved, READS)
    assert.are.equal(209, icon(25853).x)
    assert.is_nil(label("Ready"))
  end)

  it("keeps its header on the window's own title strip, inside the screen at its top edge", function()
    local s = create()
    local docked = layout()
    docked.y, docked.top = 0, 18
    s.update(docked, READS)
    local title = label("Oakhelm's group")
    assert.are.same({ 0, 18 }, { title.y, title.height })
    assert.are.same({ 2, 14 }, { label("Hide").y, label("Hide").height })
    assert.is_truthy(s.layout())
  end)

  it("is the buttons under the list with a tab on their edge while the party grid stands in for the list", function()
    local s, _, saved = create()
    s.update(layout(), READS, true)
    assert.is_nil(label("Oakhelm's group"))
    assert.is_nil(label("Hide"))
    assert.is_nil(label("Oakhelm"))
    assert.is_truthy(label("Ready"))
    assert.are.same({ 365, 436 }, { label("<").x, label("<").y })
    fake.press("<")
    assert.is_true(saved.sidebar().collapsed)
  end)

  it("folds to a bar with the tab and no hit area while the party grid stands in", function()
    local s, _, saved = create()
    saved.setSidebar("collapsed", true)
    s.update(layout(), READS, true)
    assert.is_nil(label("Ready"))
    assert.are.same({ 108, 436 }, { label(">").x, label(">").y })
    assert.is_nil(fake.find(function(_, d)
      return d.enabled == true and d.clickthrough == false and d.alpha == 0
    end))
    fake.press(">")
    assert.is_false(saved.sidebar().collapsed)
    s.update(layout(), READS, false)
    assert.is_truthy(label("Oakhelm's group"))
    assert.is_nil(label("<"))
  end)

  it("leaves the list to the game when the rows have no places", function()
    local s = create()
    local scrolled = layout()
    scrolled.rows = nil
    s.update(scrolled, READS)
    assert.is_nil(label("Oakhelm"))
    assert.is_truthy(label("Ready"))
  end)

  it("leaves nothing on the layer once the window closes or the sidebar is turned off", function()
    local s, root, saved = create()
    s.update(layout(), READS)
    assert.is_true(fake.live(root) > 0)
    s.update({ open = false }, { open = false })
    assert.are.equal(0, fake.live(root))
    s.update(layout(), READS)
    saved.setSidebar("on", false)
    s.update(layout(), READS)
    assert.are.equal(0, fake.live(root))
    s.update(nil, READS)
    assert.are.equal(0, fake.live(root))
  end)

  it("does not build while the options window is open, and stays once built", function()
    local s, root, _, state = create()
    state.blocked = true
    s.update(layout(), READS)
    assert.are.equal(0, fake.live(root))
    state.blocked = false
    s.update(layout(), READS)
    local built = fake.live(root)
    state.blocked = true
    s.update(layout(), READS)
    assert.are.equal(built, fake.live(root))
  end)

  it("folds to its header over a hit area on Hide, saves that, and unfolds on Show", function()
    local s, _, saved, state = create()
    s.update(layout(), READS)
    fake.press("Hide")
    assert.is_true(saved.sidebar().collapsed)
    assert.are.equal(1, state.changes)
    s.update(layout(), READS)
    assert.is_truthy(label("Oakhelm's group"))
    assert.is_nil(label("Ready"))
    assert.is_nil(label("x"))
    assert.is_nil(label("Oakhelm"))
    local block = fake.find(function(_, d)
      return d.enabled == true and d.clickthrough == false and d.alpha == 0
    end)
    assert.are.same({ 100, 220, 265, 270 }, { block.x, block.y, block.width, block.height })
    fake.press("Show")
    s.update(layout(), READS)
    assert.is_truthy(label("Ready"))
  end)
end)
