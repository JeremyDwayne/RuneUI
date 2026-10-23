-- RuneUI's panel on the plugin ribbon: the Options button, and switches for out of combat fading and action bar
-- fading, so a player can turn either off, such as while skilling, without opening the options window. src/options
-- builds it each time the client builds the ribbon's content layer.
local controls = require("src/controls")
local draw = require("src/draw")

local ribbon = {}

-- The Options button's spot, and the switch rows under it: each label, then its On or Off button.
local OPTIONS_X = 10
local OPTIONS_Y = 10
local ROWS_Y = 46
local ROW_H = 28
local ROW_GAP = 8
local LABEL_W = 108
local BUTTON_W = 56

-- The switches top down: each label, whether it reads On for an appearance, and set(saved, on) saving it.
ribbon.SWITCHES = {
  {
    label = "Out of combat",
    on = function(appearance)
      return appearance.outOfCombat ~= "show"
    end,
    set = function(saved, on)
      saved.setOutOfCombat(on)
    end,
  },
  {
    label = "Bar fading",
    on = function(appearance)
      return appearance.fadeBars
    end,
    set = function(saved, on)
      saved.setAppearance("fadeBars", on)
    end,
  },
}

-- Builds the panel on layer, the ribbon's content layer. deps: { saved = src/settings, open = function opening the
-- options window, changed = function run after a switch saves }. Returns show(), which redraws each switch from
-- the settings.
function ribbon.create(layer, deps)
  prettyui.FancyButton.new(layer, "Options", deps.open, { x = OPTIONS_X, y = OPTIONS_Y })
  local buttons = {}

  local function show()
    local appearance = deps.saved.appearance()
    for i, switch in ipairs(ribbon.SWITCHES) do
      local on = switch.on(appearance)
      controls.showOption(buttons[i], on)
      draw.set(buttons[i].label, "content", on and "On" or "Off")
    end
  end

  for i, switch in ipairs(ribbon.SWITCHES) do
    local y = ROWS_Y + (i - 1) * (ROW_H + ROW_GAP)
    local label = draw.windowText(layer, draw.FONTS.body, ui.AlignMode.TOPLEFT, OPTIONS_X, y, LABEL_W, ROW_H)
    draw.set(label, "content", switch.label)
    buttons[i] = controls.option(layer, "Off", OPTIONS_X + LABEL_W, y, BUTTON_W, ROW_H, function()
      switch.set(deps.saved, not switch.on(deps.saved.appearance()))
      show()
      deps.changed()
    end)
  end
  show()
  return show
end

return ribbon
