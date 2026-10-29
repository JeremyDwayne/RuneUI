local fake = require("spec/support/fake_ui")
local pretty = require("spec/support/fake_prettyui")
local cooldowns = require("src/cooldowns")
local options = require("src/options")
local presets = require("src/presets")
local savedgroups = require("src/savedgroups")
local settings = require("src/settings")
local view = require("src/view")

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

-- The options window over a player frame and a major group, with groups filled from src/presets, after
-- Sunshine, Soul Sap and then Wild Magic fired, so magic is the current style unless mainhand gives the worn
-- weapon's style. Opened from the ribbon, then on the Cooldown manager's Major group unless page names another
-- page tab to stay on. Returns the settings.
local function openWindow(mainhand, page)
  local root = fake.component()
  local tracker = cooldowns.tracker()
  if mainhand ~= nil then
    tracker.onVar("COMBATV2_MAINHAND_STYLE", nil, mainhand)
  end
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_START", 0, 1000)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_SUNSHINE_END", 0, 1100)
  tracker.onVar("COMBATV2_COOLDOWN_NECROMANCY_SOUL_SAP_START", 0, 1000)
  tracker.onVar("COMBATV2_COOLDOWN_NECROMANCY_SOUL_SAP_END", 0, 1005)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_WILD_MAGIC_START", 0, 1001)
  tracker.onVar("COMBATV2_COOLDOWN_MAGIC_WILD_MAGIC_END", 0, 1010)
  local elements = {
    player = view.playerFrame(root),
    major = view.cooldownGroup(root, view.tooltip(root)),
  }
  local saved = settings.load(fakeStore())
  options.create(root, {
    saved = saved,
    tracker = tracker,
    elements = elements,
    view = view,
    refresh = function() end,
    configured = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  pretty.button("Options")
  pretty.fire(pretty.find("Tabs"), page or "Cooldown manager")
  return saved
end

-- Options over a player frame on a new root, with the ribbon built and the window not yet opened. Returns the
-- root, the window and the number of HUD components on the root.
local function optionsOnRoot()
  local root = fake.component()
  local elements = { player = view.playerFrame(root) }
  local hud = fake.live(root)
  local window = options.create(root, {
    saved = settings.load(fakeStore()),
    tracker = cooldowns.tracker(),
    elements = elements,
    view = view,
    refresh = function() end,
    configured = function() end,
  })
  fake.fire("ContentLayerReady", { component = fake.component() })
  return root, window, hud
end

-- Opens the ability picker from the "+" tile, the third "+" after the two steppers'.
local function openPicker()
  fake.press("+", 3)
end

local function logicTick()
  fake.fire("Logic", { logicTick = 1 })
end

local function editorTile()
  return fake.find(function(c)
    return fake.hasHook(c, "ONRELEASE")
  end)
end

-- The number of ability tiles the chosen group shows.
local function tileCount()
  local count = 0
  for _, c in ipairs(fake.created) do
    if fake.shown(c) and fake.hasHook(c, "ONRELEASE") then
      count = count + 1
    end
  end
  return count
end

local function shows(content)
  return fake.find(function(_, d)
    return d.content == content
  end) ~= nil
end

describe("options", function()
  before_each(pretty.reset)

  it("reports the window and edit mode open as configuring, telling main.lua as each opens or closes", function()
    local root = fake.component()
    local seen = {}
    local window
    window = options.create(root, {
      saved = settings.load(fakeStore()),
      tracker = cooldowns.tracker(),
      elements = { player = view.playerFrame(root) },
      view = view,
      refresh = function() end,
      configured = function()
        seen[#seen + 1] = window.configuring()
      end,
    })
    assert.is_false(window.configuring())
    fake.fire("ContentLayerReady", { component = fake.component() })
    pretty.button("Options")
    pretty.button("Edit mode")
    assert.is_true(window.configuring())
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_false(window.configuring())
    assert.are.same({ true, false, true, false }, seen)
  end)

  it("switches out of combat fading and action bar fading from the ribbon, saving and redrawing", function()
    local root = fake.component()
    local saved = settings.load(fakeStore())
    local refreshed = 0
    options.create(root, {
      saved = saved,
      tracker = cooldowns.tracker(),
      elements = { player = view.playerFrame(root) },
      view = view,
      refresh = function()
        refreshed = refreshed + 1
      end,
      configured = function() end,
    })
    local layer = fake.component()
    fake.fire("ContentLayerReady", { component = layer })
    -- The checkbox under a switch's label, and whether it is ticked.
    local function switch(label)
      local row = fake.find(function(_, d)
        return d.parent == layer and d.content == label
      end)
      return pretty.find("CheckboxButton", function(c)
        return c.root.parent == layer and c.options.y > row.y and c.options.y < row.y + 30
      end)
    end
    local function ticked(label)
      return switch(label):IsSelected(switch(label).choices[1].value)
    end
    assert.are.same({ false, true }, { ticked("Out of combat"), ticked("Action bar fading") })
    assert.are.equal("Enabled", switch("Out of combat").choices[1].text)
    pretty.fire(switch("Out of combat"))
    assert.are.same({ "fade", true, 1 }, { saved.appearance().outOfCombat, ticked("Out of combat"), refreshed })
    pretty.fire(switch("Action bar fading"))
    assert.are.same({ false, false }, { saved.appearance().fadeBars, ticked("Action bar fading") })
    -- A ribbon built again shows the saved switches.
    layer = fake.component()
    fake.fire("ContentLayerReady", { component = layer })
    assert.are.same({ true, false }, { ticked("Out of combat"), ticked("Action bar fading") })
    pretty.fire(switch("Out of combat"))
    assert.are.equal("show", saved.appearance().outOfCombat)
    assert.is_not_nil(pretty.find("FancyButton", function(c)
      return c.options.y == 10
    end))
  end)

  it("builds nothing on the root until the first press of Options, with the HUD placed before it", function()
    local root = fake.component()
    local saved = settings.load(fakeStore())
    local elements = { player = view.playerFrame(root) }
    local hud = fake.live(root)
    options.create(root, {
      saved = saved,
      tracker = cooldowns.tracker(),
      elements = elements,
      view = view,
      refresh = function() end,
      configured = function() end,
    })
    assert.are.equal(hud, fake.live(root))
    assert.is_nil(pretty.find("Window"))
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    fake.fire("Draw", {})
    fake.fire("ContentLayerReady", { component = fake.component() })
    pretty.button("Options")
    assert.is_not_nil(pretty.find("Window"))
    assert.is_not_nil(pretty.find("Tabs"))
  end)

  it("lists Appearance first in the page tabs and opens on it", function()
    openWindow(nil, "Bars")
    pretty.button("Done")
    pretty.button("Options")
    local tabs = pretty.find("Tabs")
    local labels = {}
    for i, v in ipairs(tabs.values) do
      labels[i] = v.text
    end
    assert.are.same({ "Appearance", "Cooldown manager", "Buffs", "Bars" }, labels)
    assert.are.equal(1, tabs:GetActiveIndex())
    assert.is_true(shows("Font"))
    assert.is_false(shows("New group"))
  end)

  it("draws every page, popup and spare tile again when the window opens a second time", function()
    openWindow()
    openPicker()
    pretty.button("Done")
    pretty.button("Options")
    for _, page in ipairs({ "Appearance", "Cooldown manager", "Buffs", "Bars" }) do
      pretty.fire(pretty.find("Tabs"), page)
    end
    pretty.fire(pretty.find("Tabs"), "Cooldown manager")
    openPicker()
    pretty.fire(pretty.find("Tabs"), "Buffs")
    assert.is_nil(fake.find(function(_, d)
      return d.undrawn
    end))
    assert.is_true(shows("Buffs on you"))
  end)

  it("saves the debuff border colour from the Buffs page's Display tab", function()
    local saved = openWindow(nil, "Buffs")
    fake.press("Display")
    fake.press("White")
    assert.are.equal("white", saved.appearance().debuffEdge)
  end)

  it("saves a page change when the closed ribbon's checkboxes no longer take writes", function()
    local saved = openWindow(nil, "Buffs")
    for _, c in ipairs(pretty.made) do
      if c.kind == "CheckboxButton" then
        c.SetSelected = function()
          error("component destroyed")
        end
      end
    end
    fake.press("Display")
    fake.press("White")
    assert.are.equal("white", saved.appearance().debuffEdge)
  end)

  it("closes the reset confirm on Esc, then the window on a second Esc", function()
    local saved = openWindow()
    saved.setPosition("player", { x = 10, y = 20, anchorX = 0, anchorY = 0 })
    pretty.button("Reset positions")
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_nil(pretty.find("Confirm"))
    assert.is_true(shows("New group"))
    assert.are.equal(10, saved.positions().player.x)
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_false(shows("New group"))
  end)

  it("resets positions only once the confirm is accepted", function()
    local saved = openWindow()
    saved.setPosition("player", { x = 10, y = 20, anchorX = 0, anchorY = 0 })
    pretty.button("Reset positions")
    pretty.fire(pretty.find("Confirm"), "cancel")
    assert.are.equal(10, saved.positions().player.x)
    pretty.button("Reset positions")
    pretty.fire(pretty.find("Confirm"), "confirm")
    assert.are_not.equal(10, saved.positions().player.x)
  end)

  it("makes no writes or PrettyUI calls on a steady tick with the window closed", function()
    openWindow()
    pretty.button("Done")
    fake.writes = 0
    pretty.calls = 0
    fake.fire("Draw", {})
    logicTick()
    assert.are.same({ 0, 0 }, { fake.writes, pretty.calls })
  end)

  it("steps the adrenaline bar width by 1 px on the Bars page and takes a typed one", function()
    local saved = openWindow(nil, "Bars")
    fake.press("+", 3)
    assert.are.equal(279, saved.appearance().barWidth)
    local field = fake.find(function(_, d)
      return d.content == "279"
    end)
    fake.hook(field, "ONCONTENTCHANGED", ui.InputFieldActionResult.SUBMIT, "300")
    assert.are.equal(300, saved.appearance().barWidth)
  end)

  it("makes no writes on a steady tick with the Appearance or Bars page open", function()
    for _, page in ipairs({ "Appearance", "Bars" }) do
      pretty.reset()
      openWindow(nil, page)
      fake.writes = 0
      pretty.calls = 0
      fake.fire("Draw", {})
      logicTick()
      assert.are.same({ 0, 0 }, { fake.writes, pretty.calls })
    end
  end)

  it("cancels a tile drag on Esc, restoring the tile and leaving the logic tick idle", function()
    openWindow()
    local tile = editorTile()
    fake.mouse.x = 500
    fake.mouse.y = 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.x = 540
    logicTick()
    assert.are.equal(0, tile.alpha)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.equal(1, tile.alpha)
    fake.writes = 0
    fake.mouse.x = 600
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("keeps the pressed tile under the cursor during a drag so the client does not release it", function()
    openWindow()
    local tile = editorTile()
    local x = tile.x
    local y = tile.y
    fake.mouse.x = 500
    fake.mouse.y = 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.x = 540
    fake.mouse.y = 310
    logicTick()
    local cx = x + 45
    local cy = y + 15
    assert.is_true(tile.x <= cx - 60 and tile.x + tile.width >= cx + 60)
    assert.is_true(tile.y <= cy - 60 and tile.y + tile.height >= cy + 60)

    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.are.same({ x, y }, { tile.x, tile.y })
  end)

  it("swaps a tile with the one it is dropped on", function()
    local saved = openWindow()
    local first, second = table.unpack(saved.keys("major", "magic"))
    local tile = editorTile()
    fake.mouse.x = 500
    fake.mouse.y = 300
    fake.hook(tile, "ONCLICK", 5, 5)
    fake.mouse.x = 500 + 38 + 13
    fake.mouse.y = 300 + 13
    logicTick()
    fake.hook(tile, "ONRELEASE")
    local keys = saved.keys("major", "magic")
    assert.are.same({ second, first }, { keys[1], keys[2] })
  end)

  it("opens the picker on the current combat style's tab and switches style by tab", function()
    openWindow()
    openPicker()
    local function listed(name)
      return fake.find(function(_, d)
        return d.content == name
      end) ~= nil
    end
    assert.are.same({ true, false }, { listed("Wild Magic"), listed("Soul Sap") })
    fake.press("Necromancy", 2)
    assert.are.same({ false, true }, { listed("Wild Magic"), listed("Soul Sap") })
  end)

  it("counts the abilities past the picker's last row and points to the search box", function()
    openWindow()
    openPicker()
    fake.press("All")
    local note = fake.find(function(_, d)
      return type(d.content) == "string" and d.content:find(" more. Search")
    end)
    local hidden = tonumber(note.content:match("^(%d+) more"))
    assert.is_true(hidden > 0)
  end)

  it("lists abilities matching the picker search from every style, leaving the All tab chosen", function()
    openWindow()
    openPicker()
    local search = fake.find(function(_, d)
      return d.emptyText == "Find an ability"
    end)
    local function listed(name)
      return fake.find(function(_, d)
        return d.content == name
      end) ~= nil
    end
    fake.hook(search, "ONCONTENTCHANGED", 0, "soul")
    assert.are.same({ false, true }, { listed("Wild Magic"), listed("Soul Sap") })
    fake.hook(search, "ONCONTENTCHANGED", 0, "wild")
    assert.are.same({ true, false }, { listed("Wild Magic"), listed("Soul Sap") })
  end)

  it("says when no ability matches the picker search", function()
    openWindow()
    openPicker()
    local search = fake.find(function(_, d)
      return d.emptyText == "Find an ability"
    end)
    fake.hook(search, "ONCONTENTCHANGED", 0, "zzz")
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "No ability matches"
    end))
  end)

  it("closes the picker when the reset dialog opens", function()
    openWindow()
    openPicker()
    pretty.button("Reset positions")
    assert.is_nil(fake.find(function(_, d)
      return d.content == "Wild Magic"
    end))
  end)

  it("ignores a search event that arrives after the picker closed", function()
    openWindow()
    openPicker()
    local search = fake.find(function(_, d)
      return d.emptyText == "Find an ability"
    end)
    fake.hook(search, "ONCONTENTCHANGED", 0, "soul")
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.has_no.errors(function()
      fake.hook(search, "ONCONTENTCHANGED", 4, "soul")
    end)
  end)

  it("closes the picker by its X, leaving the window open", function()
    openWindow()
    openPicker()
    local x = fake.find(function(c, d)
      return fake.hasHook(c, "ONCLICK") and d.sprite == "RS3_BTN_MODAL_WINDOW_1_CLOSE_NML"
    end)
    fake.hook(x, "ONCLICK")
    assert.is_false(shows("Wild Magic"))
    assert.is_true(shows("New group"))
  end)

  it("closes the picker on Esc, then the window on a second Esc", function()
    openWindow()
    openPicker()
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_false(shows("Wild Magic"))
    assert.is_true(shows("New group"))
    fake.fire("KeyDown", { gameKey = GameKey.ESCAPE })
    assert.is_false(shows("New group"))
  end)

  it("closes the picker on a click on the page's background, leaving the window open", function()
    openWindow()
    openPicker()
    local background = fake.find(function(c, d)
      return fake.hasHook(c, "ONCLICK") and d.width == 884 and d.height == 552
    end)
    fake.hook(background, "ONCLICK")
    assert.is_false(shows("Wild Magic"))
    assert.is_true(shows("New group"))
  end)

  it("opens on the worn weapon's style tab, marked Equipped, and switches style by tab", function()
    openWindow(37)
    local equipped = fake.find(function(_, d)
      return d.content == "Equipped"
    end)
    local necromancy = fake.find(function(_, d)
      return d.content == "Necromancy"
    end)
    assert.are.equal(necromancy.x, equipped.x)
    assert.are.equal(#presets.STYLES.necromancy.major, tileCount())
    fake.press("Magic")
    assert.are.equal(#presets.STYLES.magic.major, tileCount())
  end)

  it("saves the chosen group's icon size, grow and abilities setting, and names the limit by grow", function()
    local saved = openWindow()
    fake.press("+")
    fake.press("Right")
    fake.press("Every style", 3)
    local major = saved.group("major")
    assert.are.same({ 36, "right", true }, { major.size, major.grow, major.shared })
    assert.is_true(shows("Icons per column"))
    assert.is_false(shows("Icons per row"))
  end)

  it("switches a group to every style and back, keeping its abilities for the style", function()
    local saved = openWindow()
    fake.press("Every style", 3)
    assert.are.same({}, saved.keys("major", "magic"))
    fake.press("Per style")
    assert.are.same(presets.STYLES.magic.major, saved.keys("major", "magic"))
  end)

  it("moves an ability picked from another group's section into the chosen group", function()
    local saved = openWindow()
    openPicker()
    assert.is_true(shows("In Rotation"))
    fake.press("Wild Magic")
    local major = { table.unpack(presets.STYLES.magic.major) }
    major[#major + 1] = "MAGIC_WILD_MAGIC"
    assert.are.same(major, saved.keys("major", "magic"))
    assert.is_false(saved.keys("rotation", "magic")[2] == "MAGIC_WILD_MAGIC")
    assert.are.equal(#presets.STYLES.magic.rotation - 1, #saved.keys("rotation", "magic"))
  end)

  it("adds new groups after Defensives and hides New group once all four are in use", function()
    local saved = openWindow()
    for _ = 1, 3 do
      fake.press("New group")
    end
    assert.are.equal(#savedgroups.GROUPS + 4, #saved.groupNames())
    assert.is_false(shows("New group"))
  end)

  it("renames a new group from its name field", function()
    local saved = openWindow()
    fake.press("New group")
    local field = fake.find(function(c)
      return fake.hasHook(c, "ONCONTENTCHANGED")
    end)
    fake.hook(field, "ONCONTENTCHANGED", 0, "Bombs")
    assert.are.equal("Bombs", saved.group("custom2").title)
    assert.is_true(shows("Bombs"))
  end)

  it("deletes a new group only on a second click", function()
    local saved = openWindow()
    fake.press("New group")
    fake.press("Delete")
    assert.is_not_nil(saved.group("custom2"))
    fake.press("Click to delete")
    assert.is_nil(saved.group("custom2"))
    assert.is_false(shows("Delete"))
  end)

  it("makes no client writes while a tile drag is held still", function()
    openWindow()
    fake.mouse.x = 500
    fake.mouse.y = 300
    fake.hook(editorTile(), "ONCLICK", 5, 5)
    fake.mouse.x = 540
    logicTick()
    fake.writes = 0
    logicTick()
    assert.are.equal(0, fake.writes)
  end)

  it("destroys the window and its pages on closing, and an idle tick after reopening writes nothing", function()
    local root, _, hud = optionsOnRoot()
    pretty.button("Options")
    for _, page in ipairs({ "Cooldown manager", "Buffs", "Bars" }) do
      pretty.fire(pretty.find("Tabs"), page)
    end
    pretty.button("Done")
    assert.are.equal(hud, fake.live(root))
    pretty.button("Options")
    assert.is_true(shows("Font"))
    fake.writes = 0
    logicTick()
    fake.fire("Draw", {})
    assert.are.equal(0, fake.writes)
  end)

  it("builds Appearance as the window opens and each other page once, on the first visit to its tab", function()
    local root = optionsOnRoot()
    pretty.button("Options")
    local opened = fake.live(root)
    pretty.fire(pretty.find("Tabs"), "Cooldown manager")
    local visited = fake.live(root)
    assert.is_true(visited > opened)
    pretty.fire(pretty.find("Tabs"), "Appearance")
    pretty.fire(pretty.find("Tabs"), "Cooldown manager")
    assert.are.equal(visited, fake.live(root))
  end)

  it("leaves nothing on the root and the window closed while the plugin layer is full", function()
    local root, window, hud = optionsOnRoot()
    fake.limit = hud + 40
    pretty.button("Options")
    assert.are.equal(hud, fake.live(root))
    assert.is_false(window.configuring())
    fake.limit = nil
    pretty.button("Options")
    assert.is_true(window.configuring())
    assert.is_true(shows("Font"))
  end)
end)
