-- Fades the game's action bars to a chosen opacity and restores them. The client resets keybind labels and
-- sets each window frame opaque between server ticks, so keepFaded reads a few watched components each rendered
-- frame and writes them back, and nothing while no bar is faded. Every change has a restore path: fade with the
-- option off, or restore on shutdown.
local barfade = require("src/barfade")
local interfaces = require("src/interfaces")

local actionbars = {}

local read = interfaces.read
local component = interfaces.component
local MAIN_BAR = interfaces.MAIN_BAR
local ACTION_BARS = interfaces.ACTION_BARS
local SLOTS_PER_BAR = interfaces.SLOTS_PER_BAR
local SLOT_STRIDE = interfaces.SLOT_STRIDE
local SLOT_BUTTON = interfaces.SLOT_BUTTON
local SLOT_KEYBIND = interfaces.SLOT_KEYBIND
local WINDOWS = interfaces.WINDOWS
local STAT_BARS = interfaces.STAT_BARS
local MAIN_LOCK = interfaces.MAIN_LOCK

-- The rendered frames after each server tick in which the client resets keybind labels, the name RuneUI's
-- hooks on game components go by, and how far an alpha may drift from the one written before it counts as the
-- client's own change: the client holds an alpha in a byte, so a read differs from the write by under 1/255.
local KEEP_FRAMES = 2
local FADE_HOOK = "runeuiFade"
local EPSILON = 0.005
-- Server ticks a bar stays shown after a press on one of its slots, so a drag off the bar finishes before it
-- fades: the client gives no sign of a drag ending.
local HOLD_TICKS = 3
-- Each bar's root key and keybind labels as { static, key }, built once so the handlers allocate nothing, and the
-- statics that take its hover: the root, each slot's button and the main bar's lock, which reach past the layers
-- whose hover reaches the root.
for _, bar in ipairs(ACTION_BARS) do
  bar.rootKey = bar.id .. ":0"
  bar.keybinds = {}
  bar.hoverStatics = { 0 }
  for slot = 0, SLOTS_PER_BAR - 1 do
    local base = bar.first + slot * SLOT_STRIDE
    bar.keybinds[slot + 1] = { base + SLOT_KEYBIND, bar.id .. ":" .. (base + SLOT_KEYBIND) }
    bar.hoverStatics[slot + 2] = base + SLOT_BUTTON
  end
  if bar.id == MAIN_BAR then
    table.move(MAIN_LOCK, 1, #MAIN_LOCK, #bar.hoverStatics + 1, bar.hoverStatics)
  end
end

-- Fade of each action bar RuneUI changes, by its number: { level, base, written, hidden, watch, away }. base
-- holds each component's alpha as the client last set it, written the alpha RuneUI wrote, and hidden whether
-- each component RuneUI hid was hidden before, each keyed "interface:static" or
-- "interface:static:category:dynamic". away marks a bar whose interface could not be read on the last tick.
-- watch lists the components read each frame for the client resetting the window frame and stat bars, as
-- { interface, static, category, dynamic, key }.
local fades = {}
-- The hover statics of each faded bar the mouse is over, as { [static] = true }, the appearance fadeActionBars
-- last ran with, rendered frames since the last server tick, whether the window resized since the last frame, and
-- the plugin layer while its resize hook is on.
local hovered = {}
-- Ticks left in each bar's hold after a press on one of its slots, by bar number.
local held = {}
local fadeLook = nil
local fadeFrames = KEEP_FRAMES
local resized = false
local resizeLayer = nil

local function assign(c, field, value)
  c[field] = value
end

-- The part a static of bar is, as src/barfade names them.
local function barPart(bar, staticID)
  local offset = staticID - bar.first + 2
  if offset >= 0 and offset < SLOTS_PER_BAR * SLOT_STRIDE then
    return barfade.SLOT_PARTS[offset % SLOT_STRIDE - 2] or "other"
  end
  return "other"
end

-- Gives c the hidden state and alpha of part at the fade's level, writing only what changed. A component the
-- client hid stays hidden, and one whose alpha scale is back to 1 gets the client's alpha back. With check set,
-- as after the client rebuilt part of the bar, a component the client showed or set since RuneUI wrote it is
-- hidden again or fades from that alpha; the rest keep the alpha first read from them, so a bar never fades
-- from its own faded alphas.
local function fadeComponent(fade, key, c, part, check)
  local hidden, scale = barfade.state(part, fade.level)
  if hidden then
    if fade.hidden[key] == nil then
      fade.hidden[key] = read(c, "hidden") == true
      if not fade.hidden[key] then
        pcall(assign, c, "hidden", true)
      end
    elseif check and not fade.hidden[key] and read(c, "hidden") ~= true then
      pcall(assign, c, "hidden", true)
    end
  elseif fade.hidden[key] ~= nil then
    if not fade.hidden[key] then
      pcall(assign, c, "hidden", false)
    end
    fade.hidden[key] = nil
  end
  local written = fade.written[key]
  local reset = false
  if written == nil then
    if scale == 1 then
      return
    end
    fade.base[key] = read(c, "alpha") or 1
  elseif check then
    local current = read(c, "alpha")
    if current ~= nil and math.abs(current - written) > EPSILON then
      fade.base[key] = current
      reset = true
    end
  end
  local alpha = fade.base[key] * scale
  if reset or written ~= alpha then
    pcall(assign, c, "alpha", alpha)
    fade.written[key] = alpha
  end
  if scale == 1 then
    fade.base[key] = nil
    fade.written[key] = nil
  end
end

-- Takes c's alpha as its new base when the client changed it since RuneUI wrote it, and writes base x scale.
local function refade(fade, key, c, scale)
  local alpha = read(c, "alpha")
  local written = fade.written[key]
  if alpha == nil or (written ~= nil and math.abs(alpha - written) <= EPSILON) then
    return
  end
  fade.base[key] = alpha
  fade.written[key] = alpha * scale
  pcall(assign, c, "alpha", alpha * scale)
end

-- Calls fn(key, child, category, dynamic) for each dynamic child of c.
local function eachChild(interfaceID, staticID, c, fn)
  pcall(function()
    c:IterateDynamicComponents(function(child)
      local category = read(child, "categoryID")
      local dynamic = read(child, "dynamicID")
      fn(
        interfaceID .. ":" .. staticID .. ":" .. tostring(category) .. ":" .. tostring(dynamic),
        child,
        category,
        dynamic
      )
      return false
    end)
  end)
end

-- The background, border and settings button statics of the window in 1477 holding the bar whose root is root,
-- or nil.
local function windowStatics(root)
  local content = read(root, "parentStatic")
  local contentID = content and read(content, "interfaceID") == WINDOWS and read(content, "staticID")
  return contentID and { contentID - 2, contentID - 1, contentID + 1 }
end

-- Fades every component of bar at its fade's level: each static and, under a static of no slot part, its
-- dynamic children, then the background, border and settings button of the window holding it. Watches the
-- first child of the window's background and of the main bar's first stat bar. check passes to fadeComponent.
local function fadeBar(bar, fade, root, check)
  fade.watch = {}
  local function fadeChildren(interfaceID, staticID, c, watched)
    eachChild(interfaceID, staticID, c, function(key, child, category, dynamic)
      fadeComponent(fade, key, child, "other", check)
      if watched then
        fade.watch[#fade.watch + 1] = { interfaceID, staticID, category, dynamic, key }
        watched = false
      end
    end)
  end
  for staticID = 0, bar.last do
    local c = component(bar.id, staticID)
    if c ~= nil then
      local part = barPart(bar, staticID)
      fadeComponent(fade, bar.id .. ":" .. staticID, c, part, check)
      if part == "other" then
        fadeChildren(bar.id, staticID, c, bar.id == MAIN_BAR and staticID == STAT_BARS[1])
      end
    end
  end
  for i, staticID in ipairs(windowStatics(root) or {}) do
    local c = component(WINDOWS, staticID)
    if c ~= nil then
      fadeComponent(fade, WINDOWS .. ":" .. staticID, c, "other", check)
      fadeChildren(WINDOWS, staticID, c, i == 1)
    end
  end
end

-- Whether the client rebuilt bar since RuneUI faded it, which shows its root again.
local function rebuilt(bar, fade, root)
  local written = fade.written[bar.rootKey]
  return written ~= nil and math.abs((read(root, "alpha") or 1) - written) > EPSILON
end

-- Whether the client set the alpha of a component the fade watches since RuneUI wrote it, as locking or
-- unlocking the interface does to the window frame.
local function shellsChanged(fade)
  for _, w in ipairs(fade.watch) do
    local written = fade.written[w[5]]
    local alpha = written and read(component(w[1], w[2], w[3], w[4]), "alpha")
    if alpha and math.abs(alpha - written) > EPSILON then
      return true
    end
  end
  return false
end

-- Fades the window frame of a faded bar again, and the main bar's stat bars, from the alpha the client gave
-- each component it changed.
local function refadeShells(bar, fade, root)
  local _, scale = barfade.state("other", fade.level)
  local function refadeStatic(interfaceID, staticID)
    local c = component(interfaceID, staticID)
    if c ~= nil then
      refade(fade, interfaceID .. ":" .. staticID, c, scale)
      eachChild(interfaceID, staticID, c, function(key, child)
        refade(fade, key, child, scale)
      end)
    end
  end
  if bar.id == MAIN_BAR then
    for _, staticID in ipairs(STAT_BARS) do
      refadeStatic(MAIN_BAR, staticID)
    end
  end
  for _, staticID in ipairs(windowStatics(root) or {}) do
    refadeStatic(WINDOWS, staticID)
  end
end

-- Drops each static of bar number i that the mouse left without RuneUI seeing its ONMOUSELEAVE, or that closed.
local function dropLeft(i)
  local bar = ACTION_BARS[i]
  for staticID in pairs(hovered[i]) do
    if read(component(bar.id, staticID), "isMouseOver") ~= true then
      hovered[i][staticID] = nil
    end
  end
end

-- Whether the mouse is over any faded bar.
local function anyHovered()
  for _, statics in pairs(hovered) do
    if next(statics) ~= nil then
      return true
    end
  end
  return false
end

-- Records the mouse entering or leaving static of bar number i, and moves each faded bar to the level it draws at
-- once the mouse is over any of bar i's hover statics or none. A leave during the bar's hold is left for the
-- tick the hold ends on.
local function hover(i, staticID, over)
  if fades[i] == nil or (not over and (held[i] or 0) > 0) then
    return
  end
  local was = next(hovered[i]) ~= nil
  hovered[i][staticID] = over or nil
  if (next(hovered[i]) ~= nil) == was then
    return
  end
  local any = anyHovered()
  for j, fade in pairs(fades) do
    local level = barfade.level(fadeLook, j, next(hovered[j]) ~= nil, any)
    if level ~= fade.level then
      fade.level = level
      local root = component(ACTION_BARS[j].id, 0)
      if root ~= nil then
        fadeBar(ACTION_BARS[j], fade, root)
      end
    end
  end
end

-- Subscribes or unsubscribes the mouse over, leave and press hooks on bar number i's hover statics. A press
-- starts the bar's hold.
local function hoverHooks(i, on)
  local bar = ACTION_BARS[i]
  hovered[i] = {}
  held[i] = nil
  for _, staticID in ipairs(bar.hoverStatics) do
    local c = component(bar.id, staticID)
    for hook, over in pairs({ ONMOUSEOVER = true, ONMOUSELEAVE = false, ONCLICK = "press" }) do
      pcall(function()
        if on then
          c:Subscribe(ui.Hook[hook], FADE_HOOK, function()
            if over == "press" then
              held[i] = HOLD_TICKS
            else
              hover(i, staticID, over)
            end
          end)
        else
          c:Unsubscribe(ui.Hook[hook], FADE_HOOK)
        end
      end)
    end
  end
end

-- Keeps the plugin layer's resize hook on while any bar is faded.
local function resizeHook()
  if next(fades) ~= nil and resizeLayer == nil then
    resizeLayer = component(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    pcall(function()
      resizeLayer:Subscribe(ui.Hook.ONRESIZE, FADE_HOOK, function()
        resized = true
      end)
    end)
  elseif next(fades) == nil and resizeLayer ~= nil then
    pcall(function()
      resizeLayer:Unsubscribe(ui.Hook.ONRESIZE, FADE_HOOK)
    end)
    resizeLayer = nil
  end
end

-- Runs each server tick with the appearance settings, fading each open action bar to its barOpacity while its
-- fadeBar is on. A bar the player has not opened is skipped. A faded bar whose interface cannot be read this
-- tick keeps its record and is faded or restored again once it reads. One the client rebuilt is faded again from
-- the alphas the client gave it. A bar the mouse left unseen fades again. A bar whose settings are off gets every
-- component back as the client drew it. Reads each faded bar's root and each hovered static when nothing changed.
function actionbars.fade(appearance)
  fadeLook = appearance
  fadeFrames = 0
  for i in pairs(fades) do
    if (held[i] or 0) > 0 then
      held[i] = held[i] - 1
    else
      dropLeft(i)
    end
  end
  local any = anyHovered()
  for i, bar in ipairs(ACTION_BARS) do
    local wanted = barfade.level(appearance, i, false) < 100
    local fade = fades[i]
    local root = (wanted or fade ~= nil) and component(bar.id, 0) or nil
    if root == nil then
      if fade ~= nil then
        fade.away = true
      end
    else
      local again = fade ~= nil and (fade.away or rebuilt(bar, fade, root))
      if fade == nil then
        fade = { level = 100, base = {}, written = {}, hidden = {} }
        fades[i] = fade
        hoverHooks(i, true)
      elseif again then
        hoverHooks(i, true)
      end
      local level = barfade.level(appearance, i, next(hovered[i]) ~= nil, any)
      if fade.level ~= level or again then
        fade.level = level
        fade.away = nil
        fadeBar(bar, fade, root, again)
      end
      if not wanted then
        hoverHooks(i, false)
        fades[i] = nil
      end
    end
  end
  resizeHook()
end

-- Runs on every rendered frame. Reads each faded bar's watched components, and fades its window frame and the main
-- bar's stat bars again once the client resets one, as locking or unlocking the interface does. For a few frames
-- after each server tick it reads the keybind labels of each bar between 5% and 95%, and fades a label again once
-- the client resets its alpha. After a window resize it fades the main bar's rebuilt stat bars again. No reads
-- while no bar fades.
function actionbars.keepFaded()
  for i, fade in pairs(fades) do
    if fade.level < 100 and shellsChanged(fade) then
      local root = component(ACTION_BARS[i].id, 0)
      if root ~= nil then
        refadeShells(ACTION_BARS[i], fade, root)
      end
    end
  end
  if resized then
    resized = false
    local main = fades[1]
    local root = main ~= nil and main.level < 100 and component(MAIN_BAR, 0)
    if root then
      refadeShells(ACTION_BARS[1], main, root)
    end
  end
  if fadeFrames >= KEEP_FRAMES then
    return
  end
  fadeFrames = fadeFrames + 1
  for i, fade in pairs(fades) do
    if fade.level > 0 and fade.level < 100 then
      local bar = ACTION_BARS[i]
      for _, label in ipairs(bar.keybinds) do
        local c = component(bar.id, label[1])
        if c ~= nil then
          refade(fade, label[2], c, fade.level / 100)
        end
      end
    end
  end
end

-- Puts every action bar back as the client drew it and drops RuneUI's hooks, on shutdown.
function actionbars.restore()
  for i, fade in pairs(fades) do
    local root = component(ACTION_BARS[i].id, 0)
    if root ~= nil then
      fade.level = 100
      fadeBar(ACTION_BARS[i], fade, root)
      hoverHooks(i, false)
    end
  end
  fades = {}
  hovered = {}
  held = {}
  resizeHook()
end

return actionbars
