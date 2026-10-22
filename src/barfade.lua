-- How the game's action bars draw while faded: each bar's opacity from the appearance settings, and each
-- component's hidden state and alpha scale from its part. src/adapter writes the result to the client.
local barfade = {}

-- A slot's parts by static ID offset from its background sprite. Any other offset is "other".
barfade.SLOT_PARTS = { [-1] = "frame", [4] = "flash", [6] = "queue", [8] = "highlight", [9] = "keybind" }

-- Parts hidden at any opacity below 100: the client animates their alpha, so a fade cannot hold on them.
local ANIMATED = { flash = true, queue = true, highlight = true }
-- Parts hidden as well at 0: the client resets their alpha, which a hidden component does not need.
local RESET = { frame = true, keybind = true }

-- Percent opacity bar, 1 for the main bar to 5, draws at: 100 while unfaded, or hovered with Show on hover on.
function barfade.level(appearance, bar, hovered)
  if not appearance["fadeBar" .. bar] or (hovered and appearance["hoverBar" .. bar]) then
    return 100
  end
  return appearance.barOpacity
end

-- Whether a component of part, a SLOT_PARTS value, "stats" for the main bar's stats strip or "other", is
-- hidden at level percent, and the scale for the alpha the client gave it. hideStats hides the stats strip at
-- every level. At 100 nothing else is hidden and the scale is 1.
function barfade.state(part, level, hideStats)
  if part == "stats" and hideStats then
    return true, 1
  end
  if level >= 100 then
    return false, 1
  end
  if ANIMATED[part] or (level == 0 and RESET[part]) then
    return true, 1
  end
  return false, level / 100
end

return barfade
