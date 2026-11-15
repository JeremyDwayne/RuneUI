local fake = require("spec/support/fake_ui")
local samples = require("spec/support/samples")
local nameplates = require("src/nameplates")

local label = samples.label

-- Names on a 1000 by 800 root, shown, with each entity's screen point taken from its at field.
local function create()
  local root = fake.component()
  root.width, root.height = 1000, 800
  local n = nameplates.create(root, {
    position = function(entity)
      if entity.at ~= nil then
        return entity.at[1], entity.at[2]
      end
    end,
  })
  n.setShown(true)
  return n, root
end

local function player(name, uid, x, y)
  return { entity = { at = x and { x, y } }, name = name, uid = uid }
end

describe("nameplates", function()
  before_each(fake.reset)

  it("draws each player's name centred over their head and writes nothing while nobody moves", function()
    local n = create()
    local oakhelm = player("Oakhelm", 1, 400, 300)
    n.add(oakhelm)
    n.add(player("Mirelle", 2, 600, 500))
    n.frame()
    assert.are.same({ 320, 286 }, { label("Oakhelm").x, label("Oakhelm").y })
    assert.is_truthy(label("Mirelle"))
    fake.writes = 0
    n.frame()
    assert.are.equal(0, fake.writes)
    oakhelm.entity.at = { 410, 300 }
    n.frame()
    assert.are.equal(330, label("Oakhelm").x)
  end)

  it("gives no name to the player, to one off screen or to one whose head cannot be placed", function()
    local n = create()
    n.setSelf("Mirelle")
    n.add(player("Mirelle", 1, 500, 400))
    n.add(player("Brunt", 2, 1200, 400))
    n.add(player("Ysolde", 3))
    n.frame()
    assert.is_nil(label("Mirelle"))
    assert.is_nil(label("Brunt"))
    assert.is_nil(label("Ysolde"))
  end)

  it("colours a name by the first list it is on, whatever its case", function()
    local n = create()
    n.add(player("Oakhelm", 1, 100, 100))
    n.add(player("Brunt", 2, 200, 100))
    n.add(player("Tamsin", 3, 300, 100))
    n.setRelations({ friend = { "oakhelm" }, clan = { "Oakhelm", "Brunt" }, friendsChat = {}, guest = {} })
    n.frame()
    assert.are.equal(nameplates.COLOURS.friend, label("Oakhelm").rgb)
    assert.are.equal(nameplates.COLOURS.clan, label("Brunt").rgb)
    n.setRelations({})
    n.frame()
    assert.are.equal(label("Tamsin").rgb, label("Brunt").rgb)
  end)

  it("hides a player's name as they leave, returns it, and reuses the label for the next player", function()
    local n, root = create()
    n.add(player("Oakhelm", 1, 100, 100))
    n.add(player("Brunt", 2, 200, 100))
    n.frame()
    local built = fake.live(root)
    assert.are.equal("Oakhelm", n.remove(1))
    assert.is_nil(n.remove(1))
    assert.is_nil(label("Oakhelm"))
    n.add(player("Tamsin", 3, 300, 100))
    n.frame()
    assert.is_truthy(label("Tamsin"))
    assert.is_truthy(label("Brunt"))
    assert.are.equal(built, fake.live(root))
  end)

  it("reads no positions while hidden, and takes positions in the pointer's pixels", function()
    local n = create()
    local reads = 0
    local entity = setmetatable({}, {
      __index = function(_, key)
        if key == "at" then
          reads = reads + 1
          return { 800, 600 }
        end
      end,
    })
    n.add({ entity = entity, name = "Oakhelm", uid = 1 })
    n.setShown(false)
    n.frame()
    assert.are.equal(0, reads)
    n.setShown(true)
    -- A hover 200 units in with the mouse at 400 pixels: two pixels to a unit.
    fake.mouse.x = 400
    local sheet = fake.find(function(_, d)
      return d.hooks.ONMOUSEOVER ~= nil
    end)
    sheet.xyGlobal = { x = 0, y = 0 }
    fake.hook(sheet, "ONMOUSEOVER", 200, 0)
    n.frame()
    assert.are.same({ 320, 286 }, { label("Oakhelm").x, label("Oakhelm").y })
  end)
end)
