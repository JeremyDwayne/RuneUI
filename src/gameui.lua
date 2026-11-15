-- Hides and restores the game's own interfaces: the target panel, buff bars and cast bar held transparent
-- while RuneUI replaces them, the group window while the party grid and the sidebar stand in for it, and the
-- action bars faded through src/actionbars. The client rebuilds parts of each between server ticks, so onFrame
-- reads a few watched components each rendered frame and writes them back, and nothing while no interface is
-- held. Every change has a restore path: apply with the option off, or restore on shutdown.
local actionbars = require("src/actionbars")
local interfaces = require("src/interfaces")

local gameui = {}

local read = interfaces.read
local write = interfaces.write
local component = interfaces.component
local BUFF_BARS = interfaces.BUFF_BARS
-- Rendered frames after each server tick in which a buff bar can fill a slot.
local FILL_FRAMES = 8

-- Whether c reads an alpha above 0.
local function opaque(c)
  if c == nil then
    return false
  end
  local alpha = read(c, "alpha")
  return alpha ~= nil and alpha > 0
end

-- An interface RuneUI can hold transparent with alpha 0, since hiding its components stops them updating.
-- Its statics run from firstStatic, 0 when nil, to lastStatic. watched lists { staticID, categoryID, dynamicID }
-- addresses, without the last two for a static, that read opaque once the client reloads or rebuilds the
-- interface. animated lists
-- static IDs whose alpha the client animates, which take hidden instead. Returns { hide(hidden), keep() }: hide
-- runs each server tick and false restores the original alphas and hidden states; keep runs on every rendered
-- frame, reading only the watched components while hidden and nothing while shown. It reads every frame, not
-- only the frames after a server tick as the buff bar watch does, because an interface can load or rebuild on
-- any frame, where a buff bar slot fills only after a tick.
local function transparency(interfaceID, lastStatic, watched, animated, firstStatic)
  -- Original alpha of each component while held transparent, keyed "static" or "static:category:dynamic".
  local originals = nil

  -- Calls fn(key, component) for every component, dynamic children included, since a component's alpha
  -- does not reach its children.
  local function each(fn)
    for staticID = firstStatic or 0, lastStatic do
      local c = component(interfaceID, staticID)
      if c ~= nil then
        fn(tostring(staticID), c)
        interfaces.eachChild(c, staticID, fn)
      end
    end
  end

  local function setAlpha(transparent)
    each(function(key, c)
      if transparent and originals[key] == nil then
        originals[key] = read(c, "alpha") or 1
      end
      local alpha = 0
      if not transparent then
        alpha = originals[key] or 1
      end
      write(c, "alpha", alpha)
    end)
    for _, staticID in ipairs(animated or {}) do
      local c = component(interfaceID, staticID)
      local key = "hidden " .. staticID
      if c ~= nil and (transparent or originals[key] ~= nil) then
        if transparent and originals[key] == nil then
          originals[key] = read(c, "hidden") == true
        end
        write(c, "hidden", transparent or originals[key])
      end
    end
  end

  local t = {}

  function t.keep()
    if originals == nil then
      return
    end
    for _, at in ipairs(watched) do
      if opaque(component(interfaceID, at[1], at[2], at[3])) then
        setAlpha(true)
        return
      end
    end
  end

  function t.hide(hidden)
    if hidden then
      originals = originals or {}
      t.keep()
    elseif originals ~= nil then
      setAlpha(false)
      originals = nil
    end
  end

  return t
end

-- The target panel, held transparent because hidden stops it filling its debuff slots, which src/adapter's
-- targetReads falls back to. It rebuilds its frame sprites opaque between server ticks. A visible name label
-- means the panel reloaded, and a visible background means its frame was rebuilt.
local targetPanel = transparency(
  interfaces.TARGET_PANEL,
  interfaces.TARGET_LAST_STATIC,
  { { interfaces.TARGET_NAME }, { interfaces.TARGET_BACKGROUND, 0, 0 } }
)

-- The game's cast bar, held transparent so the client's own showing and hiding of it is left alone and
-- restoring never shows a bar the client hid. A visible root or time label means the client rebuilt it. The
-- client fades the glow of the bar's moving spark in from opaque each tick, so the glow takes hidden.
local castBar = transparency(
  interfaces.CAST_BAR,
  interfaces.CAST_BAR_LAST_STATIC,
  { { 0 }, { interfaces.CAST_BAR_DURATION } },
  { interfaces.CAST_BAR_GLOW }
)

-- The group window, held transparent while the party grid and the sidebar stand in for it, so its member rows
-- keep updating, which hidden would stop. The client sets a member's row opaque again as their
-- lifepoints change, so the watch is the window's base and each row's lifepoints label, which holdGroupWindow
-- keeps in step with the group.
local groupWatched = { { interfaces.GROUP_BASE } }
local groupWindow = transparency(interfaces.GROUP_WINDOW, interfaces.GROUP_LAST_STATIC, groupWatched)
-- Whether each of the window's button strips was hidden before the fold hid it, and each of its other parts and
-- of its frame's before the hold hid it, by static id. nil while they are as the client has them.
local stripsWere = nil
local partsWere = nil
local chromeWere = nil

-- Hides statics of interfaceID while on, and puts each back as it was once off. were is what an earlier call
-- returned, nil for none. Returns each one's hidden before the first call, by static id, or nil once off.
local function hideStatics(interfaceID, statics, were, on)
  if on then
    were = were or {}
    for _, staticID in ipairs(statics) do
      local c = component(interfaceID, staticID)
      local hidden = c ~= nil and read(c, "hidden") == true
      if c ~= nil and were[staticID] == nil then
        were[staticID] = hidden
      end
      if c ~= nil and not hidden then
        write(c, "hidden", true)
      end
    end
    return were
  end
  for staticID, was in pairs(were or {}) do
    local c = component(interfaceID, staticID)
    if c ~= nil then
      write(c, "hidden", was)
    end
  end
  return nil
end
-- The window frame the group window sits in, whose background and border show a rebuild.
local GROUP_FRAME = interfaces.GROUP_FRAME
local groupFrame = transparency(
  interfaces.WINDOWS,
  GROUP_FRAME.last,
  { { GROUP_FRAME.background }, { GROUP_FRAME.border } },
  nil,
  GROUP_FRAME.window
)

-- Original alpha of each buff bar component while RuneUI hides the bars, keyed "bar:static" or
-- "bar:static:category:dynamic", and the keys of the icons it set hidden.
local barAlpha = nil
local barHidden = nil
-- Rendered frames since the last server tick, counted up to FILL_FRAMES.
local framesSinceTick = FILL_FRAMES

-- Hides c, a buff bar component or, with its category and dynamic ids, a dynamic child of a slot's static when
-- slot is true: a slot's icon :0:0 and :0:2 take hidden, which the client undoes only when it fills the slot.
-- An icon already hidden is left alone, so restoring never shows one the client hid. Everything else takes
-- alpha 0, which the client resets every few frames on an icon but not on these.
local function hideBarComponent(key, c, category, dynamic, slot)
  if slot and category == 0 and (dynamic == 0 or dynamic == 2) then
    if read(c, "hidden") ~= false then
      return
    end
    barHidden[key] = true
    write(c, "hidden", true)
    return
  end
  if barAlpha[key] == nil then
    barAlpha[key] = read(c, "alpha") or 1
  end
  write(c, "alpha", 0)
end

-- Calls fn(key, component) for every component of both buff bars, and fn(key, child, category, dynamic, slot)
-- for their dynamic children, since a component's alpha does not reach its children. slot says whether the
-- child's static is one of the bar's slots.
local function eachBarComponent(fn)
  for _, bar in pairs(BUFF_BARS) do
    for staticID = 0, bar.lastStatic do
      local c = component(bar.id, staticID)
      if c ~= nil then
        local key = bar.id .. ":" .. staticID
        fn(key, c)
        interfaces.eachChild(c, key, fn, staticID >= bar.first and staticID <= bar.last)
      end
    end
  end
end

-- Runs on every rendered frame while the buff bars are hidden. For a few frames after each server tick it
-- reads the icon of each slot up to watchLast, and hides a slot again once the client fills it, which
-- shows its icon and makes its label and frame opaque. No reads otherwise.
local function keepBuffBarsHidden()
  if barAlpha == nil or framesSinceTick >= FILL_FRAMES then
    return
  end
  framesSinceTick = framesSinceTick + 1
  for _, bar in pairs(BUFF_BARS) do
    for staticID = bar.first, bar.watchLast or bar.last do
      if read(component(bar.id, staticID, 0, 0), "hidden") == false then
        interfaces.eachChild(component(bar.id, staticID), bar.id .. ":" .. staticID, hideBarComponent, true)
      end
    end
  end
end

-- Runs each server tick with whether the native buff and debuff bars should be hidden. Their labels keep
-- counting and their slots keep filling while hidden, which auraReads relies on. A bar whose first static
-- reads opaque reloaded, so it is hidden again whole. false restores what RuneUI changed.
local function hideBuffBars(hidden)
  if hidden then
    framesSinceTick = 0
    if barAlpha == nil then
      barAlpha = {}
      barHidden = {}
      eachBarComponent(hideBarComponent)
      return
    end
    for _, bar in pairs(BUFF_BARS) do
      if opaque(component(bar.id, 0)) then
        eachBarComponent(hideBarComponent)
        return
      end
    end
  elseif barAlpha ~= nil then
    eachBarComponent(function(key, c)
      if barHidden[key] then
        write(c, "hidden", false)
      end
      if barAlpha[key] ~= nil then
        write(c, "alpha", barAlpha[key])
      end
    end)
    barAlpha = nil
    barHidden = nil
  end
end

-- Runs each server tick with the appearance settings, hiding or showing each game interface as they say.
function gameui.apply(appearance)
  targetPanel.hide(appearance.hideTargetPanel)
  hideBuffBars(appearance.hideBuffBars)
  castBar.hide(appearance.hideCastBar)
  actionbars.fade(appearance)
end

-- The parts whose clickthrough the click pass wrote, as true by key: "frame", a strip's static id, or minus a
-- member row. nil while clicks do not pass the window. passedRows is the most rows it has covered.
local passed = nil
local passedRows = 0

-- Holds c's clickthrough at want while passing, and puts back the one it wrote once not.
local function passPart(pass, key, c, want)
  if c == nil then
    return
  end
  if pass then
    if read(c, "clickthrough") == not want then
      passed[key] = true
      write(c, "clickthrough", want)
    end
  elseif passed[key] then
    write(c, "clickthrough", not want)
  end
end

-- Lets clicks pass the transparent group window to the world. The window's frame is all that stops them, so it
-- alone turns clickthrough on. Each member row's click area and each strip around buttons turns it off, so a
-- click on a party cell or a button stops there. Runs each server tick, as the client makes click areas as the group
-- grows, and writes only a part that is out of place. false puts every part back.
local function passGroupClicks(pass, rows)
  if not pass and passed == nil then
    return
  end
  passed = passed or {}
  if pass then
    passedRows = math.max(passedRows, rows)
  end
  passPart(pass, "frame", component(interfaces.WINDOWS, GROUP_FRAME.window), true)
  for _, staticID in ipairs(interfaces.GROUP_CLICK_STRIPS) do
    passPart(pass, staticID, component(interfaces.GROUP_WINDOW, staticID), false)
  end
  for row = 1, passedRows do
    passPart(pass, -row, component(interfaces.GROUP_WINDOW, interfaces.GROUP_CLICK_AREA, 0, row - 1), false)
  end
  if not pass then
    passed, passedRows = nil, 0
  end
end

-- Runs each server tick with whether the group window and its frame are held transparent, the number of
-- member rows it lists, whether its button strips are hidden too, and whether clicks pass it to the world. Its
-- list tabs and scrollbar and its frame's parts beside the content are hidden throughout. false restores
-- everything.
function gameui.holdGroupWindow(held, rows, folded, pass)
  if held then
    for i = 1, rows do
      local dynamic = (i - 1) * interfaces.GROUP_ROW_STRIDE + interfaces.GROUP_ROW_LIFEPOINTS
      groupWatched[i + 1] = groupWatched[i + 1] or { interfaces.GROUP_LIST, 0, dynamic }
    end
    for i = #groupWatched, rows + 2, -1 do
      groupWatched[i] = nil
    end
  end
  groupWindow.hide(held)
  groupFrame.hide(held)
  -- A hidden strip takes no clicks, and alpha 0 does not hold on a button. The list tabs would sit over the
  -- icon buttons wherever strip 10 is put, and the scrollbar and the frame's border, close button and edit block
  -- over the edge of whatever the frame is sized round.
  local window = interfaces.GROUP_WINDOW
  stripsWere = hideStatics(window, interfaces.GROUP_BUTTON_STRIPS, stripsWere, held and folded == true)
  partsWere = hideStatics(window, interfaces.GROUP_HIDDEN, partsWere, held)
  chromeWere = hideStatics(interfaces.WINDOWS, interfaces.GROUP_FRAME_CHROME, chromeWere, held)
  passGroupClicks(held and pass == true, rows)
end

-- Puts game component c at x, y in its parent, sized w by h, unless it is there already.
local function setBox(c, x, y, w, h)
  if read(c, "x") ~= x or read(c, "y") ~= y or read(c, "width") ~= w or read(c, "height") ~= h then
    c:SetPos(x, y)
    c:SetSize(w, h)
  end
end

-- Puts game component c at x, y on screen, sized w by h, unless it is there already. A component whose parent
-- moved this tick may land a tick late, as its screen place is read.
local function setScreenBox(c, x, y, w, h)
  local at = read(c, "xyGlobal")
  local gx, gy = at and read(at, "x"), at and read(at, "y")
  if gx ~= nil and gy ~= nil and (gx ~= x or gy ~= y or read(c, "width") ~= w or read(c, "height") ~= h) then
    c:SetPos(math.floor(read(c, "x") + x - gx + 0.5), math.floor(read(c, "y") + y - gy + 0.5))
    c:SetSize(w, h)
  end
end

-- The fields of a game component's position and size: offsets, and shares of its parent's size and of its own.
local LAYOUT_FIELDS = {
  position = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" },
  size = { "width", "height", "widthParentPc", "heightParentPc" },
}

-- How the client lays c out, as its position's and size's fields by name, or nil when one does not read. A
-- part laid out by a share of its parent follows the parent, which the box it resolves to does not say.
local function layoutOf(c)
  local layout = {}
  for property, fields in pairs(LAYOUT_FIELDS) do
    local value = read(c, property)
    for _, field in ipairs(fields) do
      local n = value ~= nil and read(value, field)
      if type(n) ~= "number" then
        return nil
      end
      layout[field] = n
    end
  end
  return layout
end

-- Lays c out as layoutOf read it.
local function setLayout(c, layout)
  c:SetPos(layout.x, layout.y, layout.xParentPc, layout.yParentPc, layout.xSelfPc, layout.ySelfPc)
  c:SetSize(layout.width, layout.height, layout.widthParentPc, layout.heightParentPc)
end

-- How the client laid out each part before spreadGroupWindow sized the first: layers holds each GROUP_SPREAD
-- layer's layoutOf by its place in that list, and buttons each strip's and button's by static id. nil while the
-- window is not spread.
local groupHomes = nil

-- Reads how the client lays out every loaded layer, strip and button, or nil when one does not read.
local function readGroupHomes()
  local homes = { layers = {}, buttons = {} }
  local function home(into, key, c)
    into[key] = c ~= nil and layoutOf(c)
    return c == nil or into[key] ~= nil
  end
  for i, ids in ipairs(interfaces.GROUP_SPREAD) do
    if not home(homes.layers, i, component(ids[1], ids[2])) then
      return nil
    end
  end
  local buttons = { interfaces.GROUP_READY.layer, interfaces.GROUP_ICON_STRIP.holder }
  for _, staticID in ipairs(interfaces.GROUP_CLICK_STRIPS) do
    buttons[#buttons + 1] = staticID
  end
  for _, ids in ipairs(interfaces.GROUP_ICON_BUTTONS) do
    buttons[#buttons + 1] = ids[1]
  end
  for _, staticID in ipairs(buttons) do
    if not home(homes.buttons, staticID, component(interfaces.GROUP_WINDOW, staticID)) then
      return nil
    end
  end
  return homes
end

-- The box round the first rows of boxes, each a { x, y, w, h } or false, as x, y, w, h. It takes column in
-- too when wide is true or there is no box. boxes and column may each be nil. nil when there is nothing to go
-- round.
local function around(boxes, rows, column, wide)
  local x1, y1, x2, y2
  for row = boxes and rows or 0, 0, -1 do
    local box = boxes and boxes[row]
    if row == 0 then
      box = (wide or x1 == nil) and column
    end
    if box then
      x1, y1 = math.min(x1 or box.x, box.x), math.min(y1 or box.y, box.y)
      x2, y2 = math.max(x2 or box.x, box.x + box.w), math.max(y2 or box.y, box.y + box.h)
    end
  end
  if x1 ~= nil then
    return x1, y1, x2 - x1, y2 - y1
  end
end

-- Sizes every layer above the group window's click areas and button strips round the party cells, so each row
-- takes clicks where it is put and the window covers no more of the screen than that. boxes is each member
-- row's cell as a { x, y, w, h } screen box or false, for the first rows rows. column is the sidebar's box, which
-- the layers take in only while hovered is true, when its buttons are wanted, or while there is no cell. The
-- frame reaches GROUP_SPREAD_MARGIN past them. Runs each server tick, and as the hover changes, and writes only
-- a layer that is out of place. It sizes nothing while a part's layout does not read, as that part could not be
-- put back. With neither cells nor a column every layer, strip and button goes back to the layout the client
-- gave it.
function gameui.spreadGroupWindow(boxes, rows, column, hovered)
  local x, y, width, height = around(boxes, rows, column, hovered)
  groupHomes = groupHomes or width ~= nil and readGroupHomes() or nil
  if groupHomes == nil then
    return
  end
  local margin = interfaces.GROUP_SPREAD_MARGIN
  for i, ids in ipairs(interfaces.GROUP_SPREAD) do
    local c = component(ids[1], ids[2])
    local home = groupHomes.layers[i]
    if c ~= nil and home and width ~= nil then
      local frame = i == 1
      pcall(setBox, c, frame and x - margin or 0, frame and y - margin or 0, width + 2 * margin, height + 2 * margin)
    elseif c ~= nil and home then
      pcall(setLayout, c, home)
    end
  end
  if width == nil then
    for staticID, home in pairs(groupHomes.buttons) do
      local c = component(interfaces.GROUP_WINDOW, staticID)
      if c ~= nil and home then
        pcall(setLayout, c, home)
      end
    end
    groupHomes = nil
  end
end

-- Puts the group window's static staticID on the screen box at, when its layout was read to put it back by.
local function placeButton(staticID, at)
  local c = component(interfaces.GROUP_WINDOW, staticID)
  if c ~= nil and groupHomes.buttons[staticID] then
    pcall(setScreenBox, c, at.x, at.y, at.w, at.h)
  end
end

-- Moves the group window's button strips and buttons onto a src/sidebar column, only while the window is spread:
-- each band's strip onto the band, and each tile's button onto the tile, so a click on the column lands on the
-- game's own button. The icon strip keeps the width the client shows it at, with its right end on the band and
-- the rest cut off by the strip that holds it, so the row the client puts the buttons back in lies outside the
-- column. Runs each server tick and writes only a part that is out of place. spreadGroupWindow puts them back.
function gameui.placeGroupButtons(column)
  if groupHomes == nil then
    return
  end
  local icons = interfaces.GROUP_ICON_STRIP
  for _, band in ipairs(column.bands) do
    if band.strip == icons.strip then
      placeButton(icons.holder, band)
      local c = component(interfaces.GROUP_WINDOW, icons.strip)
      if c ~= nil and groupHomes.buttons[icons.strip] then
        pcall(setBox, c, band.w - icons.width, 0, icons.width, band.h)
      end
    else
      placeButton(band.strip, band)
    end
  end
  for _, tile in ipairs(column.tiles) do
    if tile.static ~= nil then
      placeButton(tile.static, tile)
    end
  end
end

-- Where the client had each member row's click area that placeGroupRows moved, as { x, y, w, h } by row, false
-- for a row left alone, and the highest row moved.
local rowHomes = {}
local rowsMoved = 0

-- Moves the click area of each of the group window's first rows member rows onto boxes[row], a { x, y, w, h }
-- screen box, so a click, right click or hover there lands on the game's own row. A row with no box, and every
-- row when boxes is nil, goes back where the client had it. Runs each server tick: it reads nothing while no
-- row is moved or wanted, and writes only a click area that is out of place.
function gameui.placeGroupRows(boxes, rows)
  if boxes == nil and rowsMoved == 0 then
    return
  end
  local area = component(interfaces.GROUP_WINDOW, interfaces.GROUP_CLICK_AREA)
  local at = area and read(area, "xyGlobal")
  local left, top = at and read(at, "x"), at and read(at, "y")
  local last = math.max(boxes and rows or 0, rowsMoved)
  rowsMoved = 0
  for row = 1, last do
    local c = component(interfaces.GROUP_WINDOW, interfaces.GROUP_CLICK_AREA, 0, row - 1)
    local box = left ~= nil and top ~= nil and boxes and boxes[row] or nil
    local home = rowHomes[row]
    if c ~= nil and box then
      rowHomes[row] = home or { x = read(c, "x"), y = read(c, "y"), w = read(c, "width"), h = read(c, "height") }
      rowsMoved = row
      pcall(setBox, c, math.floor(box.x - left + 0.5), math.floor(box.y - top + 0.5), box.w, box.h)
    elseif c ~= nil and home then
      rowHomes[row] = false
      pcall(setBox, c, home.x, home.y, home.w, home.h)
    elseif home then
      -- The row is unloaded: keep its home for a later tick.
      rowsMoved = row
    end
  end
end

-- Runs on every rendered frame, putting back whatever the client rebuilt on a held interface.
function gameui.onFrame()
  targetPanel.keep()
  keepBuffBarsHidden()
  castBar.keep()
  groupWindow.keep()
  groupFrame.keep()
  actionbars.keepFaded()
end

-- Puts every game interface back as the client drew it, on shutdown.
function gameui.restore()
  targetPanel.hide(false)
  hideBuffBars(false)
  castBar.hide(false)
  gameui.holdGroupWindow(false)
  gameui.spreadGroupWindow(nil)
  gameui.placeGroupRows(nil)
  actionbars.restore()
end

return gameui
