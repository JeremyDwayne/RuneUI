-- Tints the game's window frames: every sprite under each open window's frame background, border and tab strip
-- in 1477, listed by src/windowframes, takes the appearance's frame or background colour. Locking or unlocking
-- the interface replaces every frame's sprites with new untinted ones, and a handle kept from before goes on
-- reading the old tint, so every check looks a sprite up again. onFrame reads one tinted sprite each rendered
-- frame and retints every open frame once it reads untinted; a window that opens takes its tint on the next
-- server tick. Game for both colours, or restore on shutdown, writes the game's own untinted look back.
local interfaces = require("src/interfaces")
local style = require("src/style")
local windowframes = require("src/windowframes")

local windowskin = {}

local read = interfaces.read
local write = interfaces.write
local component = interfaces.component
local WINDOWS = interfaces.WINDOWS
local NO_TINT = style.NO_TINT

-- The tints wanted on frames and on backgrounds, NO_TINT for the game's own colours.
local frameTint, backgroundTint = NO_TINT, NO_TINT
-- Frames tinted since load, by name, so going back to Game repaints only those.
local painted = {}
-- Each open frame's probe by name: { static, category, dynamic, tint }, a sprite whose rgb says whether the frame
-- still holds its tint, or false for a frame with no sprite to tint. nil until the frame is painted.
local probes = {}
-- The probe of the first open frame that has one, which onFrame reads; nil while nothing is tinted.
local watch = nil

-- Writes tint to child when it is a sprite, which reads a number spriteID, -1 while a lock blanks it.
local function tintChild(_, child, _, _, tint)
  if type(read(child, "spriteID")) == "number" and read(child, "rgb") ~= tint then
    write(child, "rgb", tint)
  end
end

-- The first sprite child of staticID as a probe holding tint, or false.
local function probeOf(staticID, tint)
  local found = false
  interfaces.eachChild(component(WINDOWS, staticID), "", function(_, child, category, dynamic)
    if not found and type(read(child, "spriteID")) == "number" then
      found = { static = staticID, category = category, dynamic = dynamic, tint = tint }
    end
  end)
  return found
end

-- Tints every sprite of frame and returns its probe: a border sprite while the frame takes a tint, since a
-- background left at the game's colours reads the same before and after a lock, or else a background sprite.
local function paint(frame)
  for _, staticID in ipairs({ frame.background, frame.border, frame.tabs }) do
    local c = component(WINDOWS, staticID)
    if c ~= nil then
      interfaces.eachChild(c, "", tintChild, staticID == frame.background and backgroundTint or frameTint)
    end
  end
  painted[frame.name] = frame
  if frameTint ~= NO_TINT then
    return probeOf(frame.border, frameTint)
  end
  return probeOf(frame.background, backgroundTint)
end

-- Whether probe's sprite, looked up again, reads another rgb than its tint.
local function stale(probe)
  local c = component(WINDOWS, probe.static, probe.category, probe.dynamic)
  return c == nil or read(c, "rgb") ~= probe.tint
end

-- Paints every open frame not painted since it opened, or whose probe reads untinted, and watches the first
-- probe. Reads each frame's window layer, about 90 lookups.
local function paintOpen()
  watch = nil
  for _, frame in ipairs(windowframes) do
    if read(component(WINDOWS, frame.window), "visibleGlobal") == true then
      local probe = probes[frame.name]
      if probe == nil or (probe and stale(probe)) then
        probe = paint(frame)
        probes[frame.name] = probe
      end
      watch = watch or probe or nil
    else
      probes[frame.name] = nil
    end
  end
end

-- Runs each server tick with the appearance settings. A colour change repaints every frame tinted so far; with
-- both at Game nothing more is read until one changes.
function windowskin.apply(appearance)
  local frame = style.windowTint(style.WINDOW_FRAME_PRESETS, appearance.windowFrameColour)
  local background = style.windowTint(style.WINDOW_BACKGROUND_PRESETS, appearance.windowBackgroundColour)
  if frame ~= frameTint or background ~= backgroundTint then
    frameTint, backgroundTint = frame, background
    for _, f in pairs(painted) do
      paint(f)
    end
    probes = {}
  end
  if frameTint == NO_TINT and backgroundTint == NO_TINT then
    painted = {}
    watch = nil
    return
  end
  paintOpen()
end

-- Runs on every rendered frame: one lookup and one read while a frame is tinted, and nothing otherwise. Locking
-- the interface replaces every frame's sprites at once, so one untinted probe repaints every open frame.
function windowskin.onFrame()
  if watch ~= nil and stale(watch) then
    paintOpen()
  end
end

-- Writes the game's untinted look back to every frame tinted, on shutdown.
function windowskin.restore()
  windowskin.apply({})
end

return windowskin
