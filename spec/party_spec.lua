local party = require("src/party")

local TIERS = party.TIER_DEFAULTS
local NO_ROLES = { defaults = {} }
local ME = { name = "Mirelle", lifepoints = 9372, max = 13200 }

-- A group window read listing names, the first as leader, each at 9400 of 12000 lifepoints with rank sprite 25847.
local function reads(...)
  local rows = {}
  for i, name in ipairs({ ... }) do
    rows[i] = { name = name, rank = 25847, lifepoints = "9400/12000" }
  end
  return { open = true, title = rows[1] and rows[1].name .. "'s group", rows = rows }
end

-- A tracker that read group with every member in view, and its model with every tier showing the player's cell.
local function shown(group, tiers)
  local tracker = party.tracker()
  for _, row in ipairs(group.rows or {}) do
    tracker.near(row.name, true)
  end
  tracker.read(group)
  return tracker.model(ME, tiers or party.withSelf(TIERS), NO_ROLES), tracker
end

local function names(model)
  local out = {}
  for i, cell in ipairs(model.cells) do
    out[i] = cell.name
  end
  return out
end

describe("party.tier", function()
  it("is Duo up to 2 members, Party to 5, Large to 7 and Raid above", function()
    local tiers = {}
    for _, size in ipairs({ 1, 2, 3, 5, 6, 7, 8, 30 }) do
      tiers[#tiers + 1] = party.tier(size)
    end
    assert.are.same({ "duo", "duo", "party", "party", "large", "large", "raid", "raid" }, tiers)
  end)
end)

describe("party model", function()
  it("shows one cell per member in the window's order, laid out in the tier's columns", function()
    local model = shown(reads("Oakhelm", "Mirelle", "Brunt", "Ysolde", "Tamsin", "Corwin"))
    assert.are.equal("large", model.tier)
    assert.are.same({ "Oakhelm", "Mirelle", "Brunt", "Ysolde", "Tamsin", "Corwin" }, names(model))
    assert.are.same({ 80, 38 }, { model.w, model.h })
    assert.are.same({ 0, 0 }, { model.cells[1].x, model.cells[1].y })
    assert.are.same({ 246, 0 }, { model.cells[4].x, model.cells[4].y })
    assert.are.same({ 0, 40 }, { model.cells[5].x, model.cells[5].y })
    assert.are.same({ 326, 78 }, { model.width, model.height })
    assert.are.same({ 0, 0, 428, 142 }, { model.x, model.y, model.boxW, model.boxH })
  end)

  it("fills columns and grows left and up from the far corner of a box that fits every tier", function()
    local tracker = party.tracker()
    tracker.read(reads("Oakhelm", "Mirelle", "Brunt", "Ysolde", "Tamsin", "Corwin"))
    local grid = { fill = "columns", growX = "left", growY = "up" }
    local model = tracker.model(ME, party.withSelf(TIERS), NO_ROLES, grid)
    assert.are.same({ 406, 208 }, { model.boxW, model.boxH })
    assert.are.same({ 326, 170 }, { model.cells[1].x, model.cells[1].y })
    assert.are.same({ 326, 130 }, { model.cells[2].x, model.cells[2].y })
    assert.are.same({ 244, 170 }, { model.cells[5].x, model.cells[5].y })
    assert.are.same({ 244, 50, 162, 158 }, { model.x, model.y, model.width, model.height })
  end)

  it("hides with no members listed, and with only the player's own cell turned off", function()
    assert.is_true(shown(reads()).hidden)
    assert.is_true(shown(reads("Mirelle"), TIERS).hidden)
    assert.is_false(shown(reads("Mirelle")).hidden)
  end)

  it("leaves the player's own cell out of a tier whose Show my frame is off, keeping the tier", function()
    local model = shown(reads("Oakhelm", "Mirelle", "Brunt"), TIERS)
    assert.are.equal("party", model.tier)
    assert.are.same({ "Oakhelm", "Brunt" }, names(model))
    local raid = shown(reads("A", "B", "C", "D", "E", "F", "G", "Mirelle"), TIERS)
    assert.are.equal("raid", raid.tier)
    assert.are.equal(8, #raid.cells)
  end)

  it("shows a member's lifepoints from their row and the player's own from their own reads", function()
    local model = shown(reads("Oakhelm", "Mirelle"))
    local other, own = model.cells[1], model.cells[2]
    assert.is_near(9400 / 12000, other.fill, 1e-9)
    assert.are.equal("9,400", other.text)
    assert.are.equal("9,400 / 12,000", other.lifepoints)
    assert.is_near(9372 / 13200, own.fill, 1e-9)
    assert.are.equal("9,372", own.text)
  end)

  it("keeps the roster while the window is closed, with flat cells for everyone but the player", function()
    local model, tracker = shown(reads("Oakhelm", "Mirelle", "Brunt"))
    assert.is_false(model.closed)
    tracker.read({ open = false })
    model = tracker.model(ME, party.withSelf(TIERS), NO_ROLES)
    assert.is_true(model.closed)
    assert.are.same({ "Oakhelm", "Mirelle", "Brunt" }, names(model))
    assert.is_nil(model.cells[1].fill)
    assert.are.equal("", model.cells[1].text)
    assert.is_nil(model.cells[1].lifepoints)
    assert.are.equal("9,372", model.cells[2].text)
    tracker.read(reads("Oakhelm", "Mirelle"))
    assert.are.same({ "Oakhelm", "Mirelle" }, names(tracker.model(ME, party.withSelf(TIERS), NO_ROLES)))
  end)

  it("marks a cell low under 30%, dead at 0 and far when its member is not in view", function()
    local group = reads("Oakhelm", "Brunt", "Ysolde", "Mirelle")
    group.rows[1].lifepoints = "3599/12000"
    group.rows[2].lifepoints = "0/12000"
    local tracker = party.tracker()
    tracker.near("Oakhelm", true)
    tracker.near("brunt", true)
    tracker.near("Ysolde", true)
    tracker.near("Ysolde", false)
    tracker.read(group)
    local cells = tracker.model(ME, party.withSelf(TIERS), NO_ROLES).cells
    assert.are.same({ "low", "3,599", false }, { cells[1].state, cells[1].text, cells[1].far })
    assert.are.same({ "dead", "Dead", false }, { cells[2].state, cells[2].text, cells[2].far })
    assert.are.same({ "Far", true }, { cells[3].text, cells[3].far })
    assert.is_false(cells[4].far)
  end)

  it("gives Raid cells no number", function()
    local model = shown(reads("A", "B", "C", "D", "E", "F", "G", "Mirelle"))
    assert.is_true(model.raid)
    assert.is_nil(model.cells[1].text)
    assert.is_near(9400 / 12000, model.cells[1].fill, 1e-9)
  end)

  it("marks the member the title names as leader with their row's rank sprite", function()
    local group = reads("Oakhelm", "Mirelle", "Brunt")
    group.title = "Brunt's group"
    group.rows[3].rank = 25850
    local cells = shown(group).cells
    assert.are.same({ nil, nil, 25850 }, { cells[1].leader, cells[2].leader, cells[3].leader })
  end)

  it("tags a name from the active preset, falling back to its default", function()
    local tracker = party.tracker()
    tracker.read(reads("Oakhelm", "Mirelle", "Brunt"))
    local roles = { defaults = { oakhelm = "BT", brunt = "DPS" }, preset = { brunt = "T2" } }
    local cells = tracker.model(ME, party.withSelf(TIERS), roles).cells
    assert.are.same({ "BT", "Base tank" }, { cells[1].tag, cells[1].role })
    assert.is_nil(cells[2].tag)
    assert.are.same({ "T2", "T2" }, { cells[3].tag, cells[3].role })
  end)

  it("stops at 30 cells", function()
    local list = {}
    for i = 1, 34 do
      list[i] = "Member" .. i
    end
    assert.are.equal(30, #shown(reads(table.unpack(list))).cells)
  end)
end)

describe("party.rows", function()
  it("lists each member's name, lifepoints and fill, with the leader's rank sprite", function()
    local group = reads("Oakhelm", "Mirelle", "Brunt")
    group.rows[2].lifepoints = "0/12000"
    group.rows[3].lifepoints = nil
    assert.are.same({
      { name = "Oakhelm", leader = 25847, fill = 9400 / 12000, text = "9,400" },
      { name = "Mirelle", fill = 0, text = "Dead" },
      { name = "Brunt", text = "" },
    }, party.rows(group))
  end)
end)

describe("party.key", function()
  it("matches a name whatever its case or kind of space", function()
    assert.are.equal(party.key("Iron Oak"), party.key("iron\u{A0}oak"))
    assert.are.equal(party.key("Iron Oak"), party.key("IRON\xA0OAK"))
    assert.are.equal(party.key("Iron Oak"), party.key("Iron_Oak"))
  end)
end)
