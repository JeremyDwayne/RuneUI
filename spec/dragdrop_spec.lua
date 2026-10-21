local fake = require("spec/support/fake_ui")
local dragdrop = require("src/dragdrop")

-- A drag helper over one 30px icon at 100, 50, recording what it reports.
local function setup()
  local layer = fake.component()
  local seen = { finished = 0 }
  local drag = dragdrop.create(layer, 15, {
    press = function() return true end,
    ghost = function(item) return { icon = item.icon, initials = "" } end,
    start = function() seen.started = true end,
    move = function(_, x, y) seen.at = { x, y } end,
    drop = function(_, x, y) seen.dropped = { x, y } end,
    click = function() seen.clicked = true end,
    finish = function() seen.finished = seen.finished + 1 end,
  })
  local item = { edge = fake.component(layer), x = 100, y = 50, size = 30, icon = 13309 }
  item.edge:SetPos(100, 50)
  item.edge:SetSize(30, 30)
  drag.attach(item)
  fake.mouse.x, fake.mouse.y = 105, 55
  fake.hook(item.edge, "ONCLICK", 5, 5)
  return drag, item, seen
end

describe("dragdrop", function()
  before_each(fake.reset)

  it("reports a click when released without moving", function()
    local _, item, seen = setup()
    fake.hook(item.edge, "ONRELEASE")
    assert.are.same({ true, nil, false }, { seen.clicked, seen.dropped, seen.started == true })
    assert.are.equal(1, seen.finished)
  end)

  it("keeps a grab area far larger than the icon centred under the cursor while dragging", function()
    local drag, item, seen = setup()
    fake.mouse.x = 145
    drag.follow()
    assert.is_true(seen.started)
    assert.are.same({ 145, 55 }, seen.at)
    local e = item.edge
    assert.are.equal(0, e.alpha)
    assert.is_true(e.x <= 145 - 60 and e.x + e.width >= 145 + 60)
    assert.is_true(e.y <= 55 - 60 and e.y + e.height >= 55 + 60)
    assert.is_not_nil(fake.find(function(_, d) return d.sprite == 13309 end))
  end)

  it("drops at the cursor and puts the icon's hit area back", function()
    local drag, item, seen = setup()
    fake.mouse.x, fake.mouse.y = 145, 90
    drag.follow()
    fake.hook(item.edge, "ONRELEASE")
    assert.are.same({ 145, 90 }, seen.dropped)
    assert.are.same({ 100, 50, 30, 30, 1 }, { item.edge.x, item.edge.y, item.edge.width, item.edge.height,
      item.edge.alpha })
    assert.are.equal(1, seen.finished)
    assert.is_nil(fake.find(function(_, d) return d.sprite == 13309 end))
  end)

  it("cancels without dropping and makes no writes while idle or held still", function()
    local drag, item, seen = setup()
    fake.mouse.x = 145
    drag.follow()
    fake.writes = 0
    drag.follow()
    assert.are.equal(0, fake.writes)
    drag.cancel()
    assert.are.same({ nil, 1, 100 }, { seen.dropped, seen.finished, item.edge.x })
    fake.writes = 0
    drag.follow()
    assert.are.equal(0, fake.writes)
  end)
end)
