-- One tooltip for every HUD icon and the options window's icons: a dark panel above the hovered icon, below
-- it when there is no room, kept inside the side edges, with a white outline on the icon.
local tooltip = {}

local draw = require("src/draw")

local set = draw.set
local rect = draw.rect
local text = draw.text
local FONTS = draw.FONTS
local COLOURS = draw.COLOURS
local TOOLTIP_WIDTH = 240
local TOOLTIP_PAD = 8
local TOOLTIP_GAP = 6
local TOOLTIP_LINE = 14
-- Space above each description paragraph and the foot.
local TOOLTIP_SPACE = 4
-- Characters of info that surely fit one tooltip line in the small font; 224 px holds 37 to 41 of prose.
local TOOLTIP_LINE_CHARS = 36

-- Description paragraphs at its <br> tags, each { text, lines }, with lines its wrapped line count. Tags such
-- as <col=ffffff> stay in the text and count for nothing.
local function paragraphs(info)
  local out = {}
  for part in (info .. "<br>"):gmatch("(.-)<br>") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then
      local lines = 1
      local width = 0
      for word in part:gsub("<[^>]*>", ""):gmatch("%S+") do
        if width == 0 then
          width = #word
        elseif width + 1 + #word > TOOLTIP_LINE_CHARS then
          lines = lines + 1
          width = #word
        else
          width = width + 1 + #word
        end
      end
      out[#out + 1] = { text = part, lines = lines }
    end
  end
  return out
end

-- The tooltip on root. show(content, x, y, size) takes the icon's screen position and { title, left, right,
-- info, foot }: the name, a status row with left and right ends when either is given, the description split
-- into paragraphs at <br>, and a last line; hide() clears it and destroy() removes it. It draws above the HUD
-- from its first show. hover(items, show) wires each item's edge to the tooltip.
function tooltip.create(root)
  local layer = draw.new(ui.Layer, root)
  local edge = rect(layer, COLOURS.border, 0, 0, TOOLTIP_WIDTH, 0)
  local inner = rect(layer, COLOURS.tooltipEdge, 1, 1, TOOLTIP_WIDTH - 2, 0)
  local panel = rect(layer, COLOURS.panel, 2, 2, TOOLTIP_WIDTH - 4, 0)
  local textWidth = TOOLTIP_WIDTH - 2 * TOOLTIP_PAD
  local title = text(layer, FONTS.body, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 6, textWidth, 16)
  local left = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 24, textWidth, TOOLTIP_LINE)
  local right = text(layer, FONTS.small, ui.AlignMode.BOTTOMRIGHT, TOOLTIP_PAD, 24, textWidth, TOOLTIP_LINE)
  local foot = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 0, textWidth, TOOLTIP_LINE)
  set(left, "rgb", COLOURS.dimText)
  set(right, "rgb", COLOURS.dimText)
  -- Paragraph labels, built as a longer description first needs them.
  local lines = {}
  local highlight = draw.outline(root, COLOURS.highlight, 2)
  local height = nil
  local raised = false
  local tip = {}

  local function setHidden(hidden)
    set(layer, "hidden", hidden)
    draw.hideAll(highlight, hidden)
  end
  setHidden(true)

  function tip.show(content, x, y, size)
    set(title, "content", content.title)
    set(left, "content", content.left or "")
    set(right, "content", content.right or "")
    -- The status row takes a line only when it has an end to show.
    local h = 24 + ((content.left or content.right) and TOOLTIP_LINE or 0)
    local parts = content.info and paragraphs(content.info) or {}
    for i = 1, math.max(#parts, #lines) do
      local part = parts[i]
      if lines[i] == nil then
        lines[i] = text(layer, FONTS.small, ui.AlignMode.TOPLEFT, TOOLTIP_PAD, 0, textWidth, TOOLTIP_LINE)
        set(lines[i], "rgb", COLOURS.dimText)
      end
      set(lines[i], "hidden", part == nil)
      if part ~= nil then
        h = h + TOOLTIP_SPACE
        set(lines[i], "content", part.text)
        draw.pos(lines[i], TOOLTIP_PAD, h)
        draw.size(lines[i], textWidth, part.lines * TOOLTIP_LINE)
        h = h + part.lines * TOOLTIP_LINE
      end
    end
    -- An empty foot stays shown, since the first show's MoveToFront would stop a hidden one drawing for good.
    set(foot, "content", content.foot or "")
    if content.foot ~= nil then
      h = h + TOOLTIP_SPACE
      draw.pos(foot, TOOLTIP_PAD, h)
      h = h + TOOLTIP_LINE
    end
    h = h + ((#parts > 0 or content.foot ~= nil) and 6 or 2)
    if h ~= height then
      height = h
      layer:SetSize(TOOLTIP_WIDTH, h)
      edge:SetHeight(h)
      inner:SetHeight(h - 2)
      panel:SetHeight(h - 4)
    end
    local top = y - h - TOOLTIP_GAP
    if top < 0 then
      top = y + size + TOOLTIP_GAP
    end
    local screenWidth = tonumber(root.width)
    local panelX = x
    if screenWidth ~= nil and screenWidth > TOOLTIP_WIDTH then
      panelX = math.max(0, math.min(x, screenWidth - TOOLTIP_WIDTH))
    end
    draw.pos(layer, panelX, top)
    draw.placeOutline(highlight, x + 2, y + 2, size - 4, size - 4)
    setHidden(false)
    -- The client stops drawing a component moved to the front while hidden, so this waits for the first show.
    if not raised then
      raised = true
      layer:MoveToFront()
      for _, side in ipairs(highlight) do
        side:MoveToFront()
      end
    end
  end

  function tip.hide()
    setHidden(true)
  end

  function tip.destroy()
    layer:Destroy()
    for _, side in ipairs(highlight) do
      side:Destroy()
    end
  end

  -- Entering item i's edge calls show(i) and leaving the hovered edge hides the tooltip. Returns a table
  -- whose index is the hovered item's, or nil, so an update can redraw the tooltip it shows, and whose
  -- add(item) wires one more item as the next index.
  function tip.hover(items, show)
    local hover = {}
    local count = 0

    function hover.add(item)
      count = count + 1
      local i = count
      item.edge:Subscribe(ui.Hook.ONMOUSEOVER, function()
        hover.index = i
        show(i)
      end)
      item.edge:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if hover.index == i then
          hover.index = nil
          tip.hide()
        end
      end)
    end

    for _, item in ipairs(items) do
      hover.add(item)
    end
    return hover
  end

  return tip
end

return tooltip
