-- RuneUI's panel on the plugin ribbon: the Options button, and switches for out of combat fading and action bar
-- fading, so a player can turn either off, such as while skilling, without opening the options window. src/options
-- builds it each time the client builds the ribbon's content layer.
local draw = require("src/draw")

local ribbon = {}

-- The Options button's spot, and the switches under it: each a small label, then a PrettyUI checkbox.
local OPTIONS_X = 10
local OPTIONS_Y = 10
local SWITCHES_Y = 46
local LABEL_H = 14
local LABEL_W = 160
local CHECKBOX_GAP = 2
local CHECKBOX_H = 22
local SWITCH_GAP = 10

-- The value of each checkbox's one choice, "Enabled", ticked while the switch is on.
local ENABLED = "on"

-- The switches top down: each label, whether it is on for an appearance, and set(saved, on) saving it.
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
    label = "Action bar fading",
    on = function(appearance)
      return appearance.fadeBars
    end,
    set = function(saved, on)
      saved.setAppearance("fadeBars", on)
    end,
  },
}

-- Builds the panel on layer, the ribbon's content layer. deps: { saved = src/settings, open = function opening the
-- options window, changed = function run after a switch saves }. Returns show(), which ticks each checkbox from
-- the settings.
function ribbon.create(layer, deps)
  prettyui.FancyButton.new(layer, "Options", deps.open, { x = OPTIONS_X, y = OPTIONS_Y })
  local boxes = {}

  local function show()
    local appearance = deps.saved.appearance()
    for i, switch in ipairs(ribbon.SWITCHES) do
      boxes[i]:SetSelected(ENABLED, switch.on(appearance) == true, false)
    end
  end

  for i, switch in ipairs(ribbon.SWITCHES) do
    local y = SWITCHES_Y + (i - 1) * (LABEL_H + CHECKBOX_GAP + CHECKBOX_H + SWITCH_GAP)
    local label = draw.text(layer, draw.FONTS.small, ui.AlignMode.TOPLEFT, OPTIONS_X, y, LABEL_W, LABEL_H)
    draw.set(label, "rgb", draw.WINDOW.accent)
    draw.set(label, "content", switch.label)
    boxes[i] = prettyui.CheckboxButton.new(layer, { { text = "Enabled", value = ENABLED } }, {
      x = OPTIONS_X,
      y = y + LABEL_H + CHECKBOX_GAP,
      onChange = function(_, _, _, selected)
        switch.set(deps.saved, selected)
        deps.changed()
      end,
    })
  end
  show()
  return show
end

return ribbon
