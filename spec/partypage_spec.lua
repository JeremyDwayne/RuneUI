local fake = require("spec/support/fake_ui")
local fakeStore = require("spec/support/fake_store")
local samples = require("spec/support/samples")
local party = require("src/party")
local partypage = require("src/partypage")
local settings = require("src/settings")

local label = samples.label
local MEMBERS = { { name = "Oakhelm", leader = 25847 }, { name = "Mirelle" }, { name = "Brunt" } }

-- A Party page over members, MEMBERS unless given. Returns the page, the settings and a count of HUD refreshes.
local function open(members)
  local saved = settings.load(fakeStore())
  local refreshed = { count = 0 }
  local page = partypage.create(fake.component(fake.component()), 884, 552, {
    saved = saved,
    members = function()
      return members or MEMBERS
    end,
    refresh = function()
      refreshed.count = refreshed.count + 1
    end,
  })
  return page, saved, refreshed
end

-- The nth shown text field holding content, in the order built.
local function field(content, nth)
  local seen = 0
  return fake.find(function(c, d)
    if fake.hasHook(c, "ONCONTENTCHANGED") and (d.content or "") == content then
      seen = seen + 1
      return seen == (nth or 1)
    end
  end)
end

local function typeIn(c, contents)
  fake.hook(c, "ONCONTENTCHANGED", ui.InputFieldActionResult.CONTENT_CHANGE, contents)
end

describe("partypage", function()
  before_each(fake.reset)

  it("saves a member's Base tank button and typed tag as their default, and redraws the HUD", function()
    local _, saved, refreshed = open()
    fake.press("Base tank", 1)
    -- The preset name field comes first, then a tag field per member.
    typeIn(field("", 4), "T2")
    assert.are.same({ oakhelm = "BT", brunt = "T2" }, saved.roles().defaults)
    assert.are.equal(2, refreshed.count)
    fake.press("Base tank", 1)
    assert.is_nil(party.tag(saved.roles(), "Oakhelm"))
  end)

  it("adds a preset as the active one, saves tags to it, and removes it on a second click", function()
    local _, saved = open()
    typeIn(field(""), "Amascut")
    fake.press("Add")
    assert.are.same({ { slot = 1, name = "Amascut" } }, saved.rolePresets())
    assert.are.equal(1, saved.activeRolePreset())
    assert.is_truthy(label("Other names keep their default tag."))
    fake.press("Base tank", 2)
    assert.are.same({}, saved.roles().defaults)
    assert.are.equal("BT", party.tag(saved.roles(), "Mirelle"))
    fake.press("Defaults")
    assert.is_nil(saved.activeRolePreset())
    fake.press("Amascut")
    fake.press("Remove")
    assert.are.equal(1, #saved.rolePresets())
    fake.press("Click to remove")
    assert.are.same({}, saved.rolePresets())
  end)

  it("saves a tier's size from its stepper and its Show my frame box, and the sidebar's switch", function()
    local _, saved = open()
    -- Steppers run Duo's width, height and columns, then the next tier's.
    fake.press("+", 1)
    fake.press("-", 6)
    assert.are.equal(113, saved.partyTiers().duo.w)
    assert.are.equal(4, saved.partyTiers().party.columns)
    fake.press("Show my frame", 1)
    assert.is_true(saved.partyTiers().duo.showSelf)
    fake.press("Group sidebar")
    assert.is_false(saved.sidebar().on)
    fake.press("Click and cast on party cells")
    assert.is_true(saved.partyClicks())
  end)

  it("saves how the grid fills and grows, and steps the limit of the fill in use", function()
    local _, saved = open()
    assert.is_truthy(label("Max per row"))
    fake.press("Columns")
    fake.press("Up")
    fake.press("Left")
    assert.are.same({ fill = "columns", growX = "left", growY = "up" }, saved.partyGrid())
    assert.is_nil(label("Max per row"))
    assert.is_truthy(label("Max per col"))
    -- The third stepper is Duo's limit.
    fake.press("+", 3)
    assert.are.same({ 2, 3 }, { saved.partyTiers().duo.columns, saved.partyTiers().duo.rows })
  end)

  it("pages a group of more than ten and says when there is no group", function()
    local big = {}
    for i = 1, 23 do
      big[i] = { name = "Member" .. i }
    end
    open(big)
    assert.is_truthy(label("1 to 10 of 23"))
    assert.is_nil(label("Member11"))
    fake.press(">")
    fake.press(">")
    assert.is_truthy(label("21 to 23 of 23"))
    assert.is_truthy(label("Member23"))
    assert.is_nil(label("Member20"))
    fake.reset()
    open({})
    assert.is_truthy(label("Join a group to tag its members."))
  end)

  it("writes nothing on a tick where the group is unchanged", function()
    local page = open()
    fake.press("Base tank", 1)
    fake.writes = 0
    page.follow()
    assert.are.equal(0, fake.writes)
  end)
end)
