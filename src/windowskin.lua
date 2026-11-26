-- Restyles the game's window frames, listed by src/windowframes: every sprite under each open window's frame
-- background, border and tab strip in 1477 takes the appearance's frame or background colour. A window below 100
-- opacity, its own or else the appearance's windowOpacity, draws its background sprites at that share of their
-- own alpha and its tab strip halfway there, as the game's own chat transparency does. An alpha the game writes
-- over a faded sprite, such as for that setting, becomes the sprite's own. Locking or unlocking the
-- interface replaces every frame's sprites with new ones in the game's look, and a handle kept from before goes
-- on reading the old values, so every check looks a sprite up again. onFrame reads one restyled sprite and the
-- window layer of each open window with tabs each rendered frame, and restyles every open frame once the sprite
-- reads otherwise or one of those windows hides: a tab switch shows the next window on that same frame, with
-- some of its sprites new. A window that opens otherwise is restyled on the next server tick.
-- Game for both colours with every window at 100, or restore on shutdown, writes the game's look back.
-- Dynamic children of a frame static number fewer than this, so static * KEY + dynamic keys a sprite.
local KEY = 4096
local interfaces = require("src/interfaces")
local style = require("src/style")
local windowframes = require("src/windowframes")

local windowskin = {}

local read = interfaces.read
local write = interfaces.write
local component = interfaces.component
local WINDOWS = interfaces.WINDOWS
local NO_TINT = style.NO_TINT
-- How far an alpha may read from the one written: the client holds an alpha in a byte.
local EPSILON = 0.005

-- The tints wanted on frames and on backgrounds, NO_TINT for the game's own colours, every window's opacity in
-- percent, each window's own by name, and whether any window is below 100.
local frameTint, backgroundTint = NO_TINT, NO_TINT
local globalOpacity = 100
local opacities = {}
local fading = false
-- Frames restyled since load, by name, so a change repaints closed ones too.
local painted = {}
-- Each faded sprite's own alpha, and the alpha RuneUI last wrote on it, by static * KEY + dynamic.
local originals = {}
local written = {}
-- Each open frame's probe by name: { static, category, dynamic, rgb, alpha }, a sprite whose look says whether the
-- frame is still restyled, or false for a frame left in the game's look. nil until the frame is painted, and
-- while the client has built no sprite under it, so the next tick tries again.
local probes = {}
-- The probe of the first open frame that has one, which onFrame reads; nil while nothing is restyled.
local watch = nil
-- The open frames with tabs as paintOpen last found them, the first tabbedCount of them, whose windows onFrame
-- reads. Reused, so a tick allocates nothing.
local tabbed = {}
local tabbedCount = 0

-- What paintChild writes to one static's sprites: its rgb, and for a background or tab strip, fades, the static
-- and the share of each sprite's own alpha to draw at, nil to put each original back. Reused, so painting
-- allocates nothing per sprite.
local target = {}

-- Writes target's look to child when it is a sprite, which reads a number spriteID, -1 while a lock blanks it.
local function paintChild(_, child, _, dynamic)
  if type(read(child, "spriteID")) ~= "number" then
    return
  end
  if read(child, "rgb") ~= target.rgb then
    write(child, "rgb", target.rgb)
  end
  if not target.fades or math.type(dynamic) ~= "integer" then
    return
  end
  local key = target.static * KEY + dynamic
  local alpha = read(child, "alpha")
  local original, mine = originals[key], written[key]
  -- A sprite faded for the first time, or one the game wrote its own alpha on since, holds its own alpha now.
  if original == nil or (mine ~= nil and alpha ~= nil and math.abs(alpha - mine) > EPSILON) then
    original = alpha or 1
  end
  local want = original
  if target.alpha == nil then
    originals[key], written[key] = nil, nil
  else
    want = original * target.alpha
    originals[key], written[key] = original, want
  end
  if alpha == nil or math.abs(alpha - want) > EPSILON then
    write(child, "alpha", want)
  end
end

-- The first sprite child of staticID as a probe expecting rgb, and when faded the alpha it reads as just
-- painted, or nil while staticID has no sprite.
local function probeOf(staticID, rgb, faded)
  local found = nil
  interfaces.eachChild(component(WINDOWS, staticID), "", function(_, child, category, dynamic)
    if found == nil and type(read(child, "spriteID")) == "number" then
      local alpha = faded and read(child, "alpha") or nil
      found = { static = staticID, category = category, dynamic = dynamic, rgb = rgb, alpha = alpha }
    end
  end)
  return found
end

-- The share of its own alpha frame draws its background at, or nil for the game's own.
local function alphaOf(frame)
  local percent = not frame.held and (opacities[frame.name] or globalOpacity)
  return percent and percent < 100 and percent / 100 or nil
end

-- Restyles every sprite of frame and returns its probe: a background sprite while the background is tinted or
-- faded, a border sprite while only the frame is tinted, and false for a frame left in the game's look, since a
-- part in the game's look reads the same before and after a lock.
local function paint(frame)
  local alpha = alphaOf(frame)
  for _, staticID in ipairs({ frame.background, frame.border, frame.tabs }) do
    local c = component(WINDOWS, staticID)
    if c ~= nil then
      local background = staticID == frame.background
      target.rgb = background and backgroundTint or frameTint
      target.static = staticID
      target.fades = staticID ~= frame.border
      target.alpha = alpha and (background and alpha or (1 + alpha) / 2)
      interfaces.eachChild(c, "", paintChild)
    end
  end
  painted[frame.name] = frame
  if backgroundTint ~= NO_TINT or alpha ~= nil then
    return probeOf(frame.background, backgroundTint, alpha ~= nil)
  end
  return frameTint ~= NO_TINT and probeOf(frame.border, frameTint)
end

-- Whether probe's sprite, looked up again, reads another look than it expects.
local function stale(probe)
  local c = component(WINDOWS, probe.static, probe.category, probe.dynamic)
  if c == nil or read(c, "rgb") ~= probe.rgb then
    return true
  end
  if probe.alpha == nil then
    return false
  end
  local alpha = read(c, "alpha")
  return alpha ~= nil and math.abs(alpha - probe.alpha) > EPSILON
end

-- Paints every open frame not painted since it opened, or whose probe reads otherwise, watches the first
-- probe and lists the open frames with tabs. Reads each frame's window layer, about 90 lookups.
local function paintOpen()
  watch = nil
  tabbedCount = 0
  for _, frame in ipairs(windowframes) do
    if read(component(WINDOWS, frame.window), "visibleGlobal") == true then
      local probe = probes[frame.name]
      if probe == nil or (probe and stale(probe)) then
        probe = paint(frame)
        probes[frame.name] = probe
      end
      watch = watch or probe or nil
      if frame.tabs ~= nil then
        tabbedCount = tabbedCount + 1
        tabbed[tabbedCount] = frame
      end
    else
      probes[frame.name] = nil
    end
  end
end

-- Whether an open window with tabs has hidden since paintOpen listed it.
local function tabHidden()
  for i = 1, tabbedCount do
    if read(component(WINDOWS, tabbed[i].window), "visibleGlobal") ~= true then
      return true
    end
  end
  return false
end

-- Whether saved, { [name] = percent }, differs from the windows' own opacities in use.
local function opacitiesChanged(saved)
  for name, percent in pairs(saved) do
    if opacities[name] ~= percent then
      return true
    end
  end
  for name in pairs(opacities) do
    if saved[name] == nil then
      return true
    end
  end
  return false
end

-- Runs each server tick with the appearance settings and the windows given their own opacity, { [name] =
-- percent }. A change repaints every frame restyled so far; with nothing to restyle nothing more is read until a
-- setting changes.
function windowskin.apply(appearance, saved)
  saved = saved or {}
  local frame = style.windowTint(style.WINDOW_FRAME_PRESETS, appearance.windowFrameColour)
  local background = style.windowTint(style.WINDOW_BACKGROUND_PRESETS, appearance.windowBackgroundColour)
  local global = appearance.windowOpacity or 100
  if frame ~= frameTint or background ~= backgroundTint or global ~= globalOpacity or opacitiesChanged(saved) then
    frameTint, backgroundTint, globalOpacity = frame, background, global
    opacities = {}
    fading = global < 100
    for name, percent in pairs(saved) do
      opacities[name] = percent
      fading = fading or percent < 100
    end
    for _, f in pairs(painted) do
      paint(f)
    end
    probes = {}
    watch = nil
    tabbedCount = 0
    if frameTint == NO_TINT and backgroundTint == NO_TINT and not fading then
      painted = {}
    end
  end
  if frameTint == NO_TINT and backgroundTint == NO_TINT and not fading then
    return
  end
  paintOpen()
end

-- Runs on every rendered frame: one lookup and two reads for the probe while a frame is restyled, one of each per
-- open window with tabs while anything is, and nothing otherwise. Locking the interface replaces every frame's
-- sprites at once, so one probe reading otherwise repaints every open frame.
function windowskin.onFrame()
  if (watch ~= nil and stale(watch)) or tabHidden() then
    paintOpen()
  end
end

-- The frames the Windows page lists, every one whose alpha RuneUI does not hold elsewhere, in src/windowframes
-- order: { open, closed }, split by whether each window is open now. Reads each window's layer, so it runs only
-- as the page asks.
function windowskin.windows()
  local split = { open = {}, closed = {} }
  for _, frame in ipairs(windowframes) do
    if not frame.held then
      local list = read(component(WINDOWS, frame.window), "visibleGlobal") == true and split.open or split.closed
      list[#list + 1] = frame
    end
  end
  return split
end

-- Writes the game's look back to every frame restyled, on shutdown.
function windowskin.restore()
  windowskin.apply({}, {})
end

return windowskin
