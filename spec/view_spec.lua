local fake = require("spec/support/fake_ui")
local draw = require("src/draw")
local savedgroups = require("src/savedgroups")
local savedappearance = require("src/savedappearance")
local settings = require("src/settings")
local style = require("src/style")
local view = require("src/view")

-- n ready tiles for a cooldown group.
local function readyTiles(n)
  local out = {}
  for i = 1, n do
    out[i] = { key = "K" .. i, name = "Tile " .. i, initials = "T" .. i, ready = true }
  end
  return out
end

-- A cooldown group with display settings of size px tiles, perRow to a row, growing in grow.
local function group(size, perRow, grow, root, tooltip)
  local g = view.cooldownGroup(root or fake.component(), tooltip or view.tooltip(fake.component()))
  g.configure({ size = size or 36, perRow = perRow or 7, grow = grow or "down" })
  return g
end

-- Every HUD element on one root, with the built-in groups at their default display settings.
local function hud()
  local root = fake.component()
  local tooltip = view.tooltip(root)
  local elements = {
    player = view.playerFrame(root),
    target = view.targetFrame(root),
    resource = view.resourceBar(root),
    castbar = view.castBar(root),
  }
  for _, default in ipairs(savedgroups.GROUPS) do
    elements[default.name] = group(default.size, default.perRow, default.grow, root, tooltip)
  end
  return elements
end

-- The src/channel model of Asphyxiate, 7 ticks long, with ticksLeft of them left.
local function asphyxiate(start, ticksLeft)
  return {
    start = start or 227269,
    name = "Asphyxiate",
    icon = 14660,
    duration = 4.2,
    ticksLeft = ticksLeft or 7,
    hits = { 0, 1.2, 2.4, 3.6 },
  }
end

-- Shown 1px bar marks on bar, as tall as the cast bar's fill unless height is given: { dark ones over the fill,
-- light ones ahead of it }.
local function marks(bar, height)
  local dark = 0
  local light = 0
  for _, c in ipairs(fake.created) do
    if fake.shown(c) and c.parent == bar.layer and c.width == 1 and c.height == (height or 20) then
      if c.rgb == draw.COLOURS.border then
        dark = dark + 1
      end
      if c.rgb == draw.COLOURS.highlight then
        light = light + 1
      end
    end
  end
  return { dark, light }
end

describe("view", function()
  before_each(fake.reset)

  it("makes no client writes when a cooldown group redraws unchanged tiles", function()
    local tiles = readyTiles(9)
    tiles[5].global = { remaining = 1.2, length = 1.8 }
    tiles[6].queued = true
    tiles[2] = { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", remaining = 3.6 }
    tiles[3].count = "8"
    tiles[3].stacks = { key = "necrosis", count = 8, max = 12, gold = 6, notch = 6 }
    tiles[4].count = "1"
    tiles[4].charges = 1
    tiles[4].recharge = { remaining = 6, length = 10.2 }
    tiles[5].count = "2/3"
    for _, grow in ipairs(savedgroups.GROWS) do
      local g = group(36, 7, grow)
      g.update(tiles)
      fake.writes = 0
      assert.is_false(g.configure({ size = 36, perRow = 7, grow = grow }))
      g.update(tiles)
      assert.are.equal(0, fake.writes, grow)
    end
  end)

  it("fades a held cooldown group by each part's own alpha, and redraws unchanged tiles with no writes", function()
    local tiles = readyTiles(3)
    tiles[2] = { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, keybind = "Q", remaining = 3.6 }
    local g = group()
    view.holdable({ g })
    g.update(tiles)
    local alphas = {}
    for _, c in ipairs(fake.created) do
      alphas[c] = c.alpha or 1
    end
    view.fade(0.3)
    g.update(tiles)
    fake.writes = 0
    g.update(tiles)
    view.fade(0.3)
    assert.are.equal(0, fake.writes)
    local faded = 0
    for c, alpha in pairs(alphas) do
      if c.parent == g.layer then
        assert.is_near(alpha * 0.3, c.alpha, 1e-9)
        faded = faded + 1
      end
    end
    assert.is_true(faded > 10)
    view.fade(1)
    for c, alpha in pairs(alphas) do
      if c.parent == g.layer then
        assert.is_near(alpha, c.alpha, 1e-9)
      end
    end
  end)

  it("counts a cooling tile's whole seconds down between server ticks, writing only when they change", function()
    local g = group()
    g.update({ { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, remaining = 4.2 } }, 0)
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "5"
    end))
    g.step(0.2)
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "4"
    end))
    fake.writes = 0
    g.step(0.58)
    assert.are.equal(0, fake.writes)
  end)

  it("writes a tile's count once when it changes", function()
    local g = group()
    local tile =
      { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "2", charges = 2 }
    g.update({ tile })
    tile.count = "1"
    fake.writes = 0
    g.update({ tile })
    local writes = fake.writes
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "1"
    end))
    assert.is_true(writes > 0)
    fake.writes = 0
    g.update({ tile })
    assert.are.equal(0, fake.writes)
  end)

  it("writes a tile's count in the 13 pt body font on a small tile", function()
    local g = group(30)
    g.update({
      { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "1", charges = 1 },
    })
    local look = style.look(savedappearance.defaults(), nil)
    local body = look.outline and style.outlineFont(look.fonts.body) or look.fonts.body
    local count = fake.find(function(_, d)
      return d.content == "1"
    end)
    assert.are.equal(body, count.font)
  end)

  it("fills a spender's tile bar to its count in the row colour, growing it with whole casts gold", function()
    local g = group(36)
    local tile = { key = "NECROMANCY_FINGER_OF_DEATH", name = "Finger of Death", initials = "FOD", icon = 30077 }
    tile.ready = true
    tile.count = "5"
    tile.stacks = { key = "necrosis", count = 5, max = 12, gold = 0, notch = 6 }
    g.update({ tile })
    local function shownRect(rgb)
      return fake.find(function(_, d)
        return d.rgb == rgb and d.height ~= nil and d.height <= 8
      end)
    end
    local fill = shownRect(draw.COLOURS.necrosis)
    assert.are.same({ 14, 3 }, { fill.width, fill.height })
    assert.is_nil(shownRect(draw.WINDOW.accent))
    local notch = shownRect(draw.COLOURS.highlight)
    assert.are.same({ 2, 3 }, { notch.width, notch.height })
    tile.count = "6"
    tile.stacks = { key = "necrosis", count = 6, max = 12, gold = 6, notch = 6 }
    g.update({ tile })
    local gold = shownRect(draw.WINDOW.accent)
    assert.are.same({ 17, 5, 5, 5 }, { gold.width, gold.height, fill.height, notch.height })
    fake.writes = 0
    g.update({ tile })
    assert.are.equal(0, fake.writes)
  end)

  it("moves a charge's white recharge bar between server ticks, writing only when its width changes", function()
    local g = group(36)
    local tile = { key = "MAGIC_SURGE", name = "Surge", initials = "S", icon = 14233, ready = true, count = "1" }
    tile.charges = 1
    tile.recharge = { remaining = 6, length = 10.2 }
    g.update({ tile }, 0)
    local fill = fake.find(function(_, d)
      return d.rgb == draw.COLOURS.highlight and d.height == 3
    end)
    assert.is_true(fill.width < 15)
    g.step(0.45)
    assert.are.equal(15, fill.width)
    fake.writes = 0
    g.step(0.46)
    assert.are.equal(0, fake.writes)
    tile.charges = 2
    tile.count = "2"
    tile.recharge = nil
    g.update({ tile }, 0)
    assert.is_false(fake.shown(fill))
  end)

  it("turns a spender row's whole casts gold, redrawing its canvas once per change", function()
    local bar = view.resourceBar(fake.component())
    local canvas = nil
    for _, c in ipairs(fake.created) do
      if canvas == nil and c.parent == bar.layer then
        canvas = c
      end
    end
    local fills = {}
    local clears = 0
    canvas.AddRectangle = function(_, _, _, _, _, rgba)
      fills[#fills + 1] = rgba
    end
    canvas.Clear = function()
      clears = clears + 1
      fills = {}
    end
    local function blocks(rgb)
      local n = 0
      for i = 2, #fills, 2 do
        if fills[i] == draw.opaque(rgb) then
          n = n + 1
        end
      end
      return n
    end
    local necrosis = { key = "necrosis", count = 8, max = 12, gold = 6, notch = 6 }
    local model = { hidden = false, fill = 0.4, text = "40%", markers = {}, spenders = { necrosis } }
    bar.update(model)
    assert.are.same({ 6, 2, 1 }, { blocks(draw.WINDOW.accent), blocks(draw.COLOURS.necrosis), clears })
    bar.update(model)
    assert.are.equal(1, clears)
    necrosis.gold = 0
    bar.update(model)
    assert.are.same({ 0, 8, 2 }, { blocks(draw.WINDOW.accent), blocks(draw.COLOURS.necrosis), clears })
  end)

  it("wipes a ready tile's shade down through the global cooldown, writing only when it moves", function()
    local g = group(38)
    local tile = readyTiles(1)[1]
    tile.global = { remaining = 1.8, length = 1.8 }
    g.update({ tile }, 0)
    local shade = fake.find(function(_, d)
      return d.rgb == draw.COLOURS.border and d.alpha == 0.55
    end)
    local function tickMarks()
      local n = 0
      for _, c in ipairs(fake.created) do
        if fake.shown(c) and c.width == 4 and c.height == 1 then
          n = n + 1
        end
      end
      return n
    end
    assert.are.same({ 1, 36, 2 }, { shade.y, shade.height, tickMarks() })
    g.step(0.9)
    assert.are.same({ 19, 18, 1 }, { shade.y, shade.height, tickMarks() })
    fake.writes = 0
    g.step(0.91)
    assert.are.equal(0, fake.writes)
    g.step(1.8)
    assert.are.same({ false, 0 }, { fake.shown(shade), tickMarks() })
    fake.writes = 0
    g.step(1.9)
    assert.are.equal(0, fake.writes)
  end)

  it("draws no wipe on a cooling tile through the global cooldown", function()
    local g = group(38)
    local tile = { key = "MAGIC_BLAST", name = "Blast", initials = "BLA", icon = 13309, remaining = 4.2 }
    tile.global = { remaining = 1.8, length = 1.8 }
    g.update({ tile }, 0)
    assert.is_nil(fake.find(function(_, d)
      return d.alpha == 0.55
    end))
  end)

  it("borders the queued tile in gold with a light segment once round each tick, and drops it once fired", function()
    local g = group(38)
    local tiles = readyTiles(2)
    g.update(tiles, 0)
    local built = #fake.created
    tiles[2].queued = true
    g.update(tiles, 0)
    assert.are.equal(built + 7, #fake.created)
    local function shownOf(rgb)
      local list = {}
      for _, c in ipairs(fake.created) do
        if fake.shown(c) and c.rgb == rgb then
          list[#list + 1] = c
        end
      end
      return list
    end
    local band = shownOf(draw.WINDOW.accent)
    local x = band[1].x
    local firstEdge = fake.find(function(_, d)
      return d.width == 38 and d.rgb == draw.COLOURS.border
    end)
    assert.are.same({ 4, 40 }, { #band, x - firstEdge.x })
    -- At the tick the segment, 30% of the way round, covers the top and the first 7 px of the right side.
    local chase = shownOf(0xfff1c4)
    assert.are.same({ x, 0, 38, 2 }, { chase[1].x, chase[1].y, chase[1].width, chase[1].height })
    assert.are.same({ x + 36, 0, 2, 9 }, { chase[2].x, chase[2].y, chase[2].width, chase[2].height })
    -- A quarter of a tick later it covers the right side and the first 7 px of the bottom.
    g.step(0.15)
    chase = shownOf(0xfff1c4)
    assert.are.same({ x + 36, 0, 2, 38 }, { chase[1].x, chase[1].y, chase[1].width, chase[1].height })
    assert.are.same({ x + 29, 36, 9, 2 }, { chase[2].x, chase[2].y, chase[2].width, chase[2].height })
    fake.writes = 0
    g.step(0.151)
    assert.are.equal(0, fake.writes)
    tiles[2].queued = false
    g.update(tiles, 0)
    assert.are.same({ 0, 0 }, { #shownOf(draw.WINDOW.accent), #shownOf(0xfff1c4) })
    fake.writes = 0
    g.step(0.3)
    assert.are.equal(0, fake.writes)
    tiles[2].queued = true
    built = #fake.created
    g.update(tiles, 0)
    assert.are.same({ built, 4 }, { #fake.created, #shownOf(draw.WINDOW.accent) })
  end)

  it("makes no writes stepping a group with no cooling tile", function()
    local g = group()
    g.update(readyTiles(3))
    fake.writes = 0
    g.step(0.3)
    assert.are.equal(0, fake.writes)
  end)

  it("tints a tile's icon and keybind as the native bar does while its ability can't be cast", function()
    local g = group()
    local tile = {
      key = "MAGIC_WILD_MAGIC",
      name = "Wild Magic",
      initials = "WM",
      icon = 14385,
      keybind = "W",
      ready = true,
      usable = false,
    }
    g.update({ tile })
    local icon = fake.find(function(_, d)
      return d.sprite == 14385
    end)
    local keybind = fake.find(function(_, d)
      return d.content == "W"
    end)
    assert.are.same({ 0x333333, 0xa5a5a5, 0.6 }, { icon.rgb, keybind.rgb, keybind.alpha })
    tile.usable = true
    g.update({ tile })
    assert.are.same({ 0xffffff, 1 }, { icon.rgb, keybind.alpha })
  end)

  -- The shown label reading content, or nil.
  local function label(content)
    return fake.find(function(_, d)
      return d.content == content
    end)
  end

  -- The tooltip's panel layer: the shown component on root 240 wide.
  local function tooltipLayer(root)
    return fake.find(function(_, d)
      return d.parent == root and d.width == 240
    end)
  end

  it("splits a tooltip's description into paragraphs at <br>, sized to their lines", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    local first = "The power of Zamorak's flames causes a delayed eruption of chaos fire."
    tooltip.show(
      { title = "Flames of Zamorak", left = "Debuff on you", info = first .. "<br>Melts shields." },
      0,
      300,
      42
    )
    local a = label(first)
    local b = label("Melts shields.")
    assert.is_true(b.y >= a.y + 2 * 14)
    local twoParagraphs = tooltipLayer(root).height
    tooltip.show({ title = "Flames of Zamorak", left = "Debuff on you", info = "Melts shields." }, 0, 300, 42)
    assert.is_nil(label(first))
    assert.are.equal(twoParagraphs - 2 * 14 - 4, tooltipLayer(root).height)
  end)

  it("shows only the name and the status row for an effect with no description", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    tooltip.show({ title = "Stunned", left = "Debuff on you", right = "4s", info = "Stuck." }, 0, 300, 42)
    tooltip.show({ title = "Stunned", left = "Debuff on you", right = "4s" }, 0, 300, 42)
    assert.is_nil(label("Stuck."))
    assert.are.equal(40, tooltipLayer(root).height)
  end)

  it("leaves out the status row when it has neither end", function()
    local root = fake.component()
    local tooltip = view.tooltip(root)
    tooltip.show({ title = "Command Skeleton Warrior", info = "Rage.", foot = "Ready" }, 0, 300, 42)
    assert.are.equal(24 + 4, label("Rage.").y)
    tooltip.show(
      { title = "Command Skeleton Warrior", left = "Cooldown 30s", info = "Rage.", foot = "Ready" },
      0,
      300,
      42
    )
    assert.are.equal(24 + 14 + 4, label("Rage.").y)
  end)

  it("adds an ability's description to its cooldown tooltip, ending with Ready", function()
    local tooltip = view.tooltip(fake.component())
    local g = view.cooldownGroup(fake.component(), tooltip, function(key)
      return key == "K1" and "Inflict searing pain on the target." or nil
    end)
    g.configure({ size = 36, perRow = 7, grow = "down" })
    g.update(readyTiles(1))
    fake.hook(
      fake.find(function(c)
        return fake.hasHook(c, "ONMOUSEOVER")
      end),
      "ONMOUSEOVER"
    )
    local info = label("Inflict searing pain on the target.")
    assert.is_true(label("Ready").y > info.y)
  end)

  it("makes no client writes when the tooltip is shown again at the same icon", function()
    local tooltip = view.tooltip(fake.component())
    local content = { title = "Sunshine", left = "Cooldown 60s", info = "Boosts damage.<br>Lasts 30s.", foot = "Ready" }
    tooltip.show(content, 100, 300, 42)
    fake.writes = 0
    tooltip.show(content, 100, 300, 42)
    assert.are.equal(0, fake.writes)
  end)

  it("hides a debuff's tooltip when the target debuffs row empties under it", function()
    local tooltip = view.tooltip(fake.component())
    local looked = {}
    local row = view.auraRow(fake.component(), view.AURA_STYLES.targetDebuffs, tooltip, function(sprite)
      looked[#looked + 1] = sprite
      return { name = "Bloated" }
    end)
    row.update({ { sprite = 30098 } }, false)
    fake.hook(
      fake.find(function(c)
        return fake.hasHook(c, "ONMOUSEOVER")
      end),
      "ONMOUSEOVER"
    )
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Bloated"
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Debuff on target"
    end))

    row.update({}, false)
    assert.is_nil(fake.find(function(_, d)
      return d.content == "Bloated" or d.content == "Unknown debuff"
    end))
    assert.are.same({ 30098 }, looked)
  end)

  -- A combat buffs row, and the src/auras model of a 20 s buff with left seconds left.
  local function auraRow()
    return view.auraRow(fake.component(), view.AURA_STYLES.combatBuffs, view.tooltip(fake.component()), function()
      return {}
    end)
  end
  local function incite(left)
    return {
      {
        sprite = 14766,
        text = tostring(left),
        stacks = "5",
        left = left,
        full = 20,
        fill = left / 20,
        highlight = left <= 2,
      },
    }
  end

  it("builds an aura row's tiles as auras appear and keeps them hidden once gone", function()
    local row = auraRow()
    local empty = #fake.created
    row.update({}, false)
    assert.are.equal(empty, #fake.created)
    row.update({ incite(12)[1], incite(12)[1] }, false)
    local two = #fake.created
    assert.is_true(two > empty)
    row.update({}, false)
    row.update({ incite(12)[1] }, false)
    assert.are.equal(two, #fake.created)
  end)

  it("makes no client writes when an aura row redraws unchanged icons, with or without bars", function()
    for _, bars in ipairs({ false, true }) do
      local row = auraRow()
      row.update(incite(12), bars)
      fake.writes = 0
      row.update(incite(12), bars)
      assert.are.equal(0, fake.writes)
    end
  end)

  it("draws a missing Keep up tile dim with a dashed outline and no time, steady after", function()
    local row = auraRow()
    local missing = { { sprite = 30093, missing = true, highlight = false } }
    row.update(missing, false)
    local icon = fake.find(function(_, d)
      return d.sprite == 30093
    end)
    assert.are.equal(0.35, icon.alpha)
    assert.is_not_nil(fake.find(function(_, d)
      return d.width == 42 and d.height == 42
    end))
    assert.is_nil(fake.find(function(_, d)
      return d.parent == row.layer and (d.content or "") ~= ""
    end))
    fake.writes = 0
    row.update(missing, false)
    assert.are.equal(0, fake.writes)
  end)

  it("bounds an aura row by its shown icons and at least one, reporting when they change", function()
    local row = auraRow()
    assert.are.same({ x = 174, y = 3, w = 36, h = 36 }, row.bounds)
    assert.is_false(row.update(incite(12), false))
    local two = incite(12)
    two[2] = { sprite = 30093, text = "6m" }
    assert.is_true(row.update(two, false))
    assert.are.same({ x = 155, y = 3, w = 74, h = 36 }, row.bounds)
    assert.is_true(row.update({}, true))
    assert.are.same({ x = 174, y = 3, w = 36, h = 41 }, row.bounds)
  end)

  it("sizes an aura row's tiles and text from its look, reporting the bounds that moved", function()
    local row = auraRow()
    row.update(incite(12), false)
    local appearance = savedappearance.defaults()
    appearance.combatBuffsIcon = 48
    appearance.combatBuffsText = 16
    local look = style.look(appearance, nil)
    assert.is_true(row.setLook(look))
    assert.are.same({ x = 228, y = 3, w = 48, h = 48 }, row.bounds)
    assert.is_not_nil(fake.find(function(_, d)
      return d.sprite == 14766 and d.width == 46 and d.height == 46
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "12" and d.width == 48 and d.height == 18 and d.font == id.Font.MUSEO_SANS_17PT_BOLD
    end))
    fake.writes = 0
    assert.is_false(row.setLook(look))
    row.update(incite(12), false)
    assert.are.equal(0, fake.writes)
  end)

  it("draws aura icons over the game's dark slot, edging debuffs in the look's colour", function()
    local row = view.auraRow(
      fake.component(),
      view.AURA_STYLES.targetDebuffs,
      view.tooltip(fake.component()),
      function() end
    )
    local appearance = savedappearance.defaults()
    appearance.debuffEdge = "white"
    row.setLook(style.look(appearance, nil))
    row.update({ { sprite = 30098 } }, false)
    assert.is_not_nil(fake.find(function(_, d)
      return d.parent == row.layer and d.rgb == draw.COLOURS.slot and d.width == 24 and d.height == 24
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.parent == row.layer and d.rgb == 0xffffff and d.width == 26 and d.height == 26
    end))
  end)

  it("moves the tooltip to the front once shown, never while hidden", function()
    local tooltip = view.tooltip(fake.component())
    tooltip.show({ title = "Sunshine" }, 100, 300, 42)
    assert.is_nil(fake.find(function(_, d)
      return d.undrawn
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.fronted and d.width == 240
    end))
  end)

  it("draws a cooldown's Ready line after an aura's tooltip showed first", function()
    local tooltip = view.tooltip(fake.component())
    tooltip.show({ title = "Sunshine", left = "Buff", right = "20s" }, 100, 300, 42)
    tooltip.show({ title = "Finger of Death", right = "Key 4", foot = "Ready" }, 100, 300, 42)
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Ready" and not d.undrawn
    end))
  end)

  it("keeps the tooltip inside the screen's side edges", function()
    local root = fake.component()
    root:SetSize(1000, 800)
    local tooltip = view.tooltip(root)
    local function layerX()
      return fake.find(function(_, d)
        return d.parent == root and d.width == 240
      end).x
    end
    tooltip.show({ title = "Sunshine" }, 950, 300, 42)
    assert.are.equal(760, layerX())
    tooltip.show({ title = "Sunshine" }, -20, 300, 42)
    assert.are.equal(0, layerX())
  end)

  it("draws the player and target frames the same height, with or without a prayer bar", function()
    local elements = hud()
    -- A frame's box is the tallest full-width component on its layer: its black border.
    local function boxHeight(frame)
      local tallest = 0
      fake.find(function(_, d)
        if d.parent == frame.layer and d.width == frame.width then
          tallest = math.max(tallest, d.height or 0)
        end
      end)
      return tallest
    end
    elements.player.update({ hidden = false, name = "Jeremy", valueText = "", fill = 1 })
    elements.target.update({ hidden = false, name = "Aviansie", valueText = "", fill = 1, debuffs = {} })
    assert.are.equal(boxHeight(elements.player), boxHeight(elements.target))
  end)

  it("bounds a cooldown group by its shown tiles, meeting at its axis when empty", function()
    local g = group(36, 7, "down")
    assert.is_true(g.update(readyTiles(9)))
    assert.are.same({ x = 0, y = 0, w = 264, h = 74 }, g.bounds)
    assert.is_false(g.update(readyTiles(9)))
    g.update({})
    assert.are.same({ x = 132, y = 0, w = 0, h = 36 }, g.bounds)
  end)

  it("keeps an up group's last tile on its bottom row and a left group's on its right column", function()
    local up = group(36, 7, "up")
    local left = group(30, 2, "left")
    up.update(readyTiles(3))
    left.update(readyTiles(3))
    assert.are.same({ x = 76, y = 76, w = 112, h = 36 }, up.bounds)
    assert.are.same({ x = 256, y = 0, w = 62, h = 62 }, left.bounds)
  end)

  it("resizes its tiles in place, building more only as the group grows", function()
    local g = group(36, 7, "down")
    g.update(readyTiles(3))
    local built = #fake.created
    assert.is_true(g.configure({ size = 44, perRow = 7, grow = "down" }))
    g.update(readyTiles(3))
    assert.are.equal(built, #fake.created)
    assert.is_not_nil(fake.find(function(_, d)
      return d.width == 44 and d.height == 44
    end))
    g.update(readyTiles(20))
    g.update(readyTiles(25))
    local full = #fake.created
    g.update(readyTiles(2))
    assert.are.equal(full, #fake.created)
  end)

  it("hides a group not in use and collapses its bounds", function()
    local g = group()
    g.update(readyTiles(3))
    g.setInUse(false)
    assert.is_true(g.update(readyTiles(3)))
    assert.are.same({ 0, 0 }, { g.bounds.w, g.bounds.h })
    assert.is_true(g.layer.hidden)
  end)

  it("updates a custom group that was never configured while it is not in use", function()
    local g = view.cooldownGroup(fake.component(), view.tooltip(fake.component()))
    g.setInUse(false)
    assert.has_no.errors(function()
      g.update({})
    end)
    assert.are.same({ 0, 0 }, { g.bounds.w, g.bounds.h })
  end)

  it("shows the channel's name and length, hides between channels, and makes no writes when steady", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Asphyxiate"
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "4.2s"
    end))
    fake.writes = 0
    bar.update(asphyxiate())
    assert.are.equal(0, fake.writes)
    bar.update(nil)
    assert.is_true(bar.layer.hidden)
    fake.writes = 0
    bar.update(nil)
    assert.are.equal(0, fake.writes)
    assert.are.same({ x = 0, y = 0, w = 278, h = 22 }, bar.bounds)
  end)

  it("fills each step up to the next tick, steps its time with the ticks as the game does, and ends at 0", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    local fill = fake.find(function(_, d)
      return d.rgb == style.CAST_COLOUR
    end)
    local width = fill.width
    bar.step(0.3)
    bar.update(asphyxiate())
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "4.2s"
    end))
    assert.is_true(fill.width > width)
    bar.update(asphyxiate(nil, 5))
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "3s"
    end))
    bar.step(5)
    assert.is_false(bar.layer.hidden)
    bar.update(asphyxiate(nil, 1))
    bar.step(0.7)
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate())
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate(227280))
    assert.is_false(bar.layer.hidden)
  end)

  it("shows Cancelled for a cancelled channel, then fades the bar out and hides it", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    local name = fake.find(function(_, d)
      return d.content == "Asphyxiate"
    end)
    bar.update({ start = 227269, cancelled = true })
    assert.is_not_nil(fake.find(function(_, d)
      return d.content == "Cancelled"
    end))
    assert.are.same({ 0, 0 }, marks(bar))
    bar.update(nil)
    bar.step(0.6)
    assert.are.same({ false, 1 }, { bar.layer.hidden, name.alpha or 1 })
    bar.step(0.2)
    assert.is_true(name.alpha > 0 and name.alpha < 1)
    bar.step(0.3)
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate())
    assert.is_true(bar.layer.hidden)
    bar.update(asphyxiate(227280))
    assert.are.same({ false, 1 }, { bar.layer.hidden, name.alpha })
  end)

  it("colours the fill by the channel's combat style, and teal when it has none", function()
    local bar = view.castBar(fake.component())
    local model = asphyxiate()
    model.style = "necromancy"
    bar.update(model)
    assert.is_not_nil(fake.find(function(_, d)
      return d.rgb == style.STYLE_COLOURS.necromancy
    end))
    bar.update(asphyxiate(227280))
    assert.is_nil(fake.find(function(_, d)
      return d.rgb == style.STYLE_COLOURS.necromancy
    end))
    assert.is_not_nil(fake.find(function(_, d)
      return d.rgb == style.CAST_COLOUR
    end))
  end)

  it("keeps a spark at the fill's edge whose glow flashes on each server tick", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    bar.step(0.3)
    local core = fake.find(function(_, d)
      return d.rgb == draw.COLOURS.highlight and d.width == 2 and d.height == 20
    end)
    local x = core.parent.x
    bar.step(0.2)
    assert.is_true(core.parent.x > x)
    local function glow(alpha)
      return fake.find(function(_, d)
        return d.width == 1 and d.height == 20 and d.alpha == alpha
      end)
    end
    bar.update(asphyxiate(nil, 6))
    assert.is_not_nil(glow(0.9))
    bar.step(0.3)
    assert.are.same({ false, true }, { glow(0.9) ~= nil, glow(0.45) ~= nil })
  end)

  it("ignores a cancelled channel it never showed", function()
    local bar = view.castBar(fake.component())
    bar.update({ start = 227269, cancelled = true })
    assert.is_true(bar.layer.hidden)
  end)

  it("marks each hit inside the cast bar but not at its ends, dark once the fill passes it", function()
    local bar = view.castBar(fake.component())
    bar.update(asphyxiate())
    assert.are.same({ 0, 3 }, marks(bar))
    bar.update(asphyxiate(nil, 5))
    assert.are.same({ 1, 2 }, marks(bar))
    fake.writes = 0
    bar.step(0.02)
    assert.are.equal(2, fake.writes, "the fill and the spark")
    bar.update({ start = 1, name = "Greater Concentrated Blast", duration = 1.8, hits = { 0, 0.6, 1.2 } })
    assert.are.same({ 0, 2 }, marks(bar))
    bar.update({ start = 2, name = "Asphyxiate", duration = 3.6 })
    assert.are.same({ 0, 0 }, marks(bar))
  end)

  it("draws each adrenaline marker as a faint line across the bar, dark once the fill reaches it", function()
    local bar = view.resourceBar(fake.component())
    bar.update({ hidden = false, fill = 0.6, text = "60%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.are.same({ 1, 1 }, marks(bar, 18))
    bar.update({ hidden = false, fill = 1, text = "100%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.are.same({ 2, 0 }, marks(bar, 18))
  end)

  it("makes no writes stepping between channels", function()
    local bar = view.castBar(fake.component())
    bar.update(nil)
    fake.writes = 0
    bar.step(0.02)
    assert.are.equal(0, fake.writes)
  end)

  it("moves anchored frames on the tick the rotation group gains a tile, and makes no writes when steady", function()
    local elements = hud()
    local saved = settings.load({ get = function() end, set = function() end })
    local function tick(count)
      local moved = elements.rotation.update(readyTiles(count))
      if moved then
        view.arrange(elements, saved.positions(), saved.anchors())
      end
    end
    view.arrange(elements, saved.positions(), saved.anchors())
    tick(4)
    local x = elements.player.layer.x
    tick(5)
    assert.are.equal(x - 24, elements.player.layer.x)
    fake.writes = 0
    tick(5)
    assert.are.equal(0, fake.writes)
  end)

  -- A src/style look from the default appearance with changes.
  local function look(changes)
    local appearance = {}
    for k, v in pairs(savedappearance.defaults()) do
      appearance[k] = v
    end
    for k, v in pairs(changes or {}) do
      appearance[k] = v
    end
    return style.look(appearance, nil)
  end

  local setLook = view.setLook

  -- Every HUD element and a combat buffs row, each showing text, styled with the default look.
  local function shownHud()
    local elements = hud()
    elements.combatBuffs = auraRow()
    setLook(elements, look())
    local tiles = readyTiles(3)
    tiles[1].keybind = "V"
    tiles[2].remaining = 7.2
    tiles[2].ready = false
    local function tick()
      elements.player.update({
        hidden = false,
        name = "Jeremy",
        valueText = "13.1K | 78%",
        fill = 0.78,
        prayerText = "960",
        prayerFill = 0.9,
      })
      elements.target.update({ hidden = false, name = "Aviansie", valueText = "6,800 | 58%", fill = 0.58 })
      elements.resource.update({ hidden = false, fill = 0.8, text = "80%", markers = {}, spenders = {} })
      elements.castbar.update(asphyxiate())
      elements.major.update(tiles, 0)
      elements.combatBuffs.update(incite(10), false)
    end
    tick()
    return elements, tick
  end

  -- Shown components reading content.
  local function shownWith(content)
    local n = 0
    for _, c in ipairs(fake.created) do
      if c.content == content and fake.shown(c) then
        n = n + 1
      end
    end
    return n
  end

  it("writes each HUD label's font once when the font changes, and nothing else", function()
    local elements = shownHud()
    fake.writes = 0
    setLook(elements, look({ font = "noto" }))
    local changed = 0
    for _, c in ipairs(fake.created) do
      local font = c.font
      if font == "NOTOSANS_BOLD_13" or font == "NOTOSANS_BOLD_15" or font == "NOTOSANS_BOLD_17" then
        changed = changed + 1
      end
    end
    assert.are.equal(changed, fake.writes)
    assert.are.equal(
      "NOTOSANS_BOLD_13",
      fake.find(function(_, d)
        return d.content == "Jeremy"
      end).font
    )
    assert.are.equal(
      "NOTOSANS_BOLD_15",
      fake.find(function(_, d)
        return d.content == "8"
      end).font
    )
  end)

  it("shows four outline copies under each label while Outline is on, or the native outline font", function()
    local elements = shownHud()
    setLook(elements, look({ edge = "outline" }))
    assert.are.same({ 5, 5, 5 }, { shownWith("Jeremy"), shownWith("V"), shownWith("10") })
    setLook(elements, look({ edge = "none" }))
    assert.are.same({ 1, 1, 1 }, { shownWith("Jeremy"), shownWith("V"), shownWith("10") })
    setLook(elements, look({ edge = "outline", font = "noto" }))
    assert.are.equal(1, shownWith("Jeremy"))
    assert.are.equal(
      "NOTO_SANS_13PT_BOLD_OUTLINE",
      fake.find(function(_, d)
        return d.content == "Jeremy"
      end).font
    )
  end)

  it("makes no writes on a steady tick with Outline on", function()
    local elements, tick = shownHud()
    local outlined = look({ edge = "outlineShadow" })
    setLook(elements, outlined)
    tick()
    fake.writes = 0
    setLook(elements, outlined)
    tick()
    assert.are.equal(0, fake.writes)
  end)

  it("resizes both unit frames and their bounds, reporting the change once", function()
    local elements = shownHud()
    local big = look({ frameWidth = 400, frameHeight = 80 })
    assert.is_true(setLook(elements, big))
    for _, name in ipairs({ "player", "target" }) do
      local frame = elements[name]
      assert.are.same({ 400, 400, 80 }, { frame.layer.width, frame.bounds.w, frame.bounds.h })
    end
    fake.writes = 0
    assert.is_false(setLook(elements, big))
    assert.are.equal(0, fake.writes)
  end)

  it("resizes the adrenaline bar, placing its markers across the new width", function()
    local elements = shownHud()
    local bar = elements.resource
    bar.update({ hidden = false, fill = 0.4, text = "40%", markers = { { at = 0.5 }, { at = 1 } }, spenders = {} })
    assert.is_true(setLook(elements, look({ barWidth = 402, barHeight = 30 })))
    assert.are.same({ 402, 402, 30 }, { bar.layer.width, bar.bounds.w, bar.bounds.h })
    local xs = {}
    for _, c in ipairs(fake.created) do
      if c.parent == bar.layer and c.width == 1 and c.height == 28 then
        xs[#xs + 1] = c.x
      end
    end
    assert.are.same({ 201, 400 }, xs)
  end)

  it("resizes the cast bar, keeping its icon and its backing a square as tall as the bar inside its border", function()
    local elements = shownHud()
    local bar = elements.castbar
    assert.is_true(setLook(elements, look({ castWidth = 400, castHeight = 34 })))
    assert.are.same({ 400, 34, 400, 34 }, { bar.layer.width, bar.layer.height, bar.bounds.w, bar.bounds.h })
    local squares = 0
    for _, c in ipairs(fake.created) do
      if c.parent == bar.layer and c.width == 32 and c.height == 32 then
        squares = squares + 1
      end
    end
    assert.are.equal(2, squares)
  end)

  it("fills the cast bar in a chosen colour over its ability's colour, and back", function()
    local elements = shownHud()
    local function filled(rgb)
      return fake.find(function(c, d)
        return c.parent == elements.castbar.layer and d.rgb == rgb
      end) ~= nil
    end
    assert.is_true(filled(style.CAST_COLOUR))
    setLook(elements, look({ castColour = 0x123456 }))
    assert.are.same({ true, false }, { filled(0x123456), filled(style.CAST_COLOUR) })
    setLook(elements, look({ castColour = "ability" }))
    assert.is_true(filled(style.CAST_COLOUR))
  end)

  it("grows the adrenaline bar's bounds by its spender rows below or above it, or the player frame's", function()
    local elements = shownHud()
    local bar = elements.resource
    local player = elements.player
    local spenders =
      { { key = "souls", count = 1, max = 3, gold = 0 }, { key = "necrosis", count = 4, max = 12, gold = 0 } }
    local model = { hidden = false, fill = 0.4, text = "40%", markers = {}, spenders = spenders }
    local function boxes()
      return { bar.bounds.y, bar.bounds.h, player.bounds.h }
    end
    local barY = bar.bounds.y
    local barH = bar.bounds.h
    assert.is_true(bar.update(model))
    player.showSpenders(spenders)
    assert.are.same({ barY, barH + 20, 55 }, boxes())
    setLook(elements, look({ spenders = "above" }))
    assert.are.same({ barY - 20, barH + 20, 55 }, boxes())
    setLook(elements, look({ spenders = "player" }))
    assert.are.same({ barY, barH, 75 }, boxes())
    fake.writes = 0
    assert.are.same({ false, false }, { bar.update(model), player.showSpenders(spenders) })
    assert.are.equal(0, fake.writes)
  end)

  it("draws Auto text dark over a bright fill only", function()
    local elements = shownHud()
    setLook(elements, look({ targetColour = 0xffea00 }))
    elements.target.update({ hidden = false, name = "Aviansie", valueText = "6,800 | 100%", fill = 1 })
    local function rgb(content)
      return fake.find(function(_, d)
        return d.content == content
      end).rgb
    end
    assert.are.same(
      { style.DARK_TEXT, style.DARK_TEXT, 0xffffff },
      { rgb("Aviansie"), rgb("6,800 | 100%"), rgb("Jeremy") }
    )
    setLook(elements, look({ targetColour = 0xffea00, textColour = "white" }))
    assert.are.equal(0xffffff, rgb("Aviansie"))
  end)

  it("draws the game's window border round both unit frames for Game frame, and no edge for None", function()
    local elements = shownHud()
    local function shownSprites(frame)
      local n = 0
      for _, c in ipairs(fake.created) do
        if c.parent == frame.layer and c.isTiling ~= nil and fake.shown(c) then
          n = n + 1
        end
      end
      return n
    end
    local function edgeShown(frame)
      return fake.find(function(c, d)
        return c.parent == frame.layer and d.rgb == draw.COLOURS.border
      end) ~= nil
    end
    assert.are.same({ 0, true }, { shownSprites(elements.player), edgeShown(elements.player) })
    setLook(elements, look({ border = "game" }))
    assert.are.same({ 8, 8 }, { shownSprites(elements.player), shownSprites(elements.target) })
    setLook(elements, look({ border = "none" }))
    assert.are.same({ 0, false }, { shownSprites(elements.target), edgeShown(elements.target) })
  end)
end)
