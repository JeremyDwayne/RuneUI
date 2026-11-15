local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local draw = require("src/draw")
local party = require("src/party")
local view = require("src/view")

local label = samples.label
local ME = { name = "Mirelle", lifepoints = 9372, max = 13200 }
local TIERS = party.withSelf(party.TIER_DEFAULTS)
local ROLES = { defaults = { oakhelm = "BT" } }

-- The grid on a root with its tooltip, and a src/party tracker with every listed name in view.
local function grid()
  local root = fake.component()
  return view.partyGrid(root, view.tooltip(root)), party.tracker()
end

-- A group window read of names, the first as leader, with lifepoints by name, 9400 unless given.
local function reads(names, lifepoints)
  local rows = {}
  for i, name in ipairs(names) do
    rows[i] = { name = name, rank = 25847, lifepoints = ((lifepoints or {})[name] or 9400) .. "/12000" }
  end
  return { open = true, title = names[1] .. "'s group", rows = rows }
end

-- Reads group into tracker with its members in view and draws the model on element. Returns update's result.
local function draws(element, tracker, group)
  for _, row in ipairs(group.rows or {}) do
    tracker.near(row.name, true)
    tracker.near(row.name, false)
    tracker.near(row.name, true)
  end
  tracker.read(group)
  return element.update(tracker.model(ME, TIERS, ROLES))
end

local PARTY = { "Oakhelm", "Mirelle", "Brunt" }

describe("partyframe", function()
  before_each(fake.reset)

  it("makes no writes on a tick where nothing changed", function()
    local element, tracker = grid()
    draws(element, tracker, reads(PARTY, { Brunt = 0 }))
    fake.writes = 0
    draws(element, tracker, reads(PARTY, { Brunt = 0 }))
    assert.are.equal(0, fake.writes)
  end)

  it("builds a cell the first time the group reaches it, and hides it when the group shrinks", function()
    local element, tracker = grid()
    local empty = fake.live(element.layer)
    draws(element, tracker, reads({ "Oakhelm", "Mirelle" }))
    local two = fake.live(element.layer)
    assert.is_true(two > empty)
    draws(element, tracker, reads(PARTY))
    local three = fake.live(element.layer)
    assert.are.equal((two - empty) / 2, three - two)
    assert.is_truthy(label("Brunt"))
    draws(element, tracker, reads({ "Oakhelm", "Mirelle" }))
    assert.are.equal(three, fake.live(element.layer))
    assert.is_nil(label("Brunt"))
  end)

  it("sizes its bounds to the tier's grid, reports the change once and keeps them while hidden", function()
    local element, tracker = grid()
    assert.are.same({ 428, 40 }, { element.bounds.w, element.bounds.h })
    assert.is_true(draws(element, tracker, reads(PARTY)))
    assert.are.same({ 256, 40 }, { element.bounds.w, element.bounds.h })
    assert.is_false(draws(element, tracker, reads(PARTY)))
    assert.is_true(draws(element, tracker, reads({ "A", "B", "C", "D", "E", "F", "G", "Mirelle" })))
    assert.are.same({ 338, 46 }, { element.bounds.w, element.bounds.h })
    assert.is_false(draws(element, tracker, { open = true, rows = {} }))
    assert.is_true(element.layer.hidden)
    assert.are.same({ 338, 46 }, { element.bounds.w, element.bounds.h })
  end)

  it("gives each cell's screen box by its member's row, with no box for a row that shows no cell", function()
    local element, tracker = grid()
    assert.is_nil(element.rowBoxes())
    element.layer:SetPos(300, 500)
    tracker.read(reads({ "Oakhelm", "Mirelle", "Brunt" }))
    element.update(tracker.model(ME, party.TIER_DEFAULTS, ROLES))
    assert.are.same(
      { { x = 300, y = 500, w = 84, h = 40 }, false, { x = 386, y = 500, w = 84, h = 40 } },
      element.rowBoxes()
    )
  end)

  it("keeps its bottom right corner in place as a grid growing up and left gains members", function()
    local element, tracker = grid()
    local grow = { fill = "rows", growX = "left", growY = "up" }
    local function corner(group)
      tracker.read(reads(group))
      element.update(tracker.model(ME, TIERS, ROLES, grow))
      local b = element.bounds
      return { b.x + b.w, b.y + b.h }
    end
    assert.are.same(corner({ "Oakhelm", "Mirelle" }), corner({ "A", "B", "C", "D", "E", "F", "G", "Mirelle" }))
  end)

  it("shows name, number, tag and leader icon, a dashed edge on a dead cell and a dimmed far cell", function()
    local element, tracker = grid()
    draws(element, tracker, reads(PARTY, { Brunt = 0 }))
    tracker.near("Oakhelm", false)
    element.update(tracker.model(ME, TIERS, ROLES))
    assert.is_truthy(label("Far"))
    assert.are.equal(0.45, label("Oakhelm").alpha)
    assert.are.equal(1, label("Brunt").alpha)
    assert.is_truthy(label("9,372"))
    assert.is_truthy(label("Dead"))
    assert.are.equal(
      1,
      fake.find(function(_, d)
        return d.parent == element.layer and (d.clears or 0) > 0
      end).clears
    )
    assert.are.equal(
      draw.COLOURS.adrenaline,
      fake.find(function(_, d)
        return d.parent == element.layer and d.width == 20 and d.height == 13 and d.rgb ~= draw.COLOURS.text
      end).rgb
    )
    assert.are.equal(
      25847,
      fake.find(function(_, d)
        return d.parent == element.layer and d.sprite ~= nil
      end).sprite
    )
  end)

  it("shows flat cells and the closed line while the group window is closed", function()
    local element, tracker = grid()
    draws(element, tracker, reads(PARTY))
    assert.is_nil(label("Group window closed"))
    tracker.read({ open = false })
    element.update(tracker.model(ME, TIERS, ROLES))
    assert.is_truthy(label("Group window closed"))
    assert.is_nil(label("9,400"))
    assert.is_truthy(label("9,372"))
  end)

  it("shows a member's name, role and lifepoints on hover, and no tooltip once the grid hides", function()
    local element, tracker = grid()
    draws(element, tracker, reads(PARTY))
    local cover = fake.find(function(_, d)
      return d.parent == element.layer and d.hooks.ONMOUSEOVER ~= nil
    end)
    fake.hook(cover, "ONMOUSEOVER")
    assert.is_truthy(label("Base tank"))
    assert.is_truthy(label("9,400 / 12,000"))
    draws(element, tracker, { open = true, rows = {} })
    assert.is_nil(label("Base tank"))
  end)
end)
