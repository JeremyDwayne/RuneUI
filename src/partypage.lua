-- The options window's Party page: the role presets down the left, the group's members with a Base tank
-- button and a tag box each, and along the bottom each tier's cell size, columns and Show my frame, with the
-- sidebar's switch.
local controls = require("src/controls")
local draw = require("src/draw")
local party = require("src/party")
local savedparty = require("src/savedparty")
local style = require("src/style")

local partypage = {}

local set = draw.set
local rect = draw.rect
local text = draw.windowText
local hideAll = draw.hideAll
local hitArea = draw.hitArea
local on = draw.on
local FONTS = draw.FONTS
local COLOURS = draw.WINDOW

local MARGIN = 16
-- The preset list on the left: Defaults, then a row per preset.
local LIST_W = 200
local LIST_Y = 40
local LIST_ROW = 30
-- Member rows, this many to a page of the list.
local ROWS = 10
local ROW_H = 32
local FIELD_W = 58
local BASE_TANK_W = 96
-- The frame sizes along the bottom: a block per tier of three stepper rows and a check box.
local BAND_H = 176
local STEP_ROW = 32
local TIER_FIELDS = { { "w", "Width" }, { "h", "Height" }, { "columns", "Columns" } }
local GOLD = draw.COLOURS.adrenaline
local NO_MEMBERS = {}

-- page: the options window's page layer, width by height. deps: { saved = src/settings, members = function
-- returning the group's members as src/party's tracker lists them, refresh() redrawing the HUD }. Returns
-- { open, follow }: open redraws the whole page from settings, and follow redraws the member rows, each
-- server tick while the page shows, writing nothing while the group is unchanged.
function partypage.create(page, width, height, deps)
  local saved = deps.saved
  local members = deps.members or function()
    return NO_MEMBERS
  end
  local p = {}
  local top = height - BAND_H
  local detailX = LIST_W + MARGIN
  local detailW = width - detailX - MARGIN
  -- The page of member rows shown, whether Remove has been clicked once, and the name typed for a new preset.
  local pageIndex = 1
  local confirmRemove = false
  local typedName = ""

  local function changed()
    p.open()
    deps.refresh()
  end

  local function label(content, x, y, w, h, font, rgb)
    local t = text(page, font or FONTS.body, ui.AlignMode.TOPLEFT, x, y, w, h)
    set(t, "content", content)
    if rgb ~= nil then
      set(t, "rgb", rgb)
    end
    return t
  end

  -- Presets ------------------------------------------------------------------------------------------

  label("Role presets", MARGIN, 8, LIST_W - MARGIN, 24, nil, COLOURS.accent)
  rect(page, COLOURS.line, LIST_W, 0, 1, top)
  -- Row 1 is Defaults, no preset active, and each row after it one preset: lit with an accent bar when active.
  local listRows = {}
  for i = 1, savedparty.MAX_ROLE_PRESETS + 1 do
    local y = LIST_Y + (i - 1) * LIST_ROW
    local r = {
      hit = hitArea(rect(page, COLOURS.panel, 0, y, LIST_W, LIST_ROW)),
      bar = rect(page, COLOURS.accent, 0, y, 3, LIST_ROW),
      title = text(page, FONTS.body, ui.AlignMode.TOPLEFT, MARGIN, y, LIST_W - 2 * MARGIN, LIST_ROW),
    }
    on(r.hit, "ONCLICK", function()
      if r.shown then
        confirmRemove = false
        saved.setActiveRolePreset(r.slot)
        changed()
      end
    end)
    listRows[i] = r
  end
  local nameField = controls.inputField(page, MARGIN, 0, LIST_W - 2 * MARGIN - 52, 24, savedparty.MAX_PRESET_NAME)
  on(nameField, "ONCONTENTCHANGED", function(_, _, contents)
    typedName = contents or ""
  end)
  local addButton = controls.button(page, "Add", LIST_W - MARGIN - 48, 0, 48, 24, "dark", function()
    local slot = saved.addRolePreset(typedName)
    if slot ~= nil then
      saved.setActiveRolePreset(slot)
      typedName = ""
      nameField.content = ""
      changed()
    end
  end)
  -- Removing takes a second click, since a hook cannot tell a right click from a left.
  local removeButton
  removeButton = controls.button(page, "Remove", MARGIN, 0, LIST_W - 2 * MARGIN, 26, "dark", function()
    if not confirmRemove then
      confirmRemove = true
      set(removeButton.label, "content", "Click to remove")
      return
    end
    confirmRemove = false
    saved.removeRolePreset(saved.activeRolePreset())
    changed()
  end)

  local function showPresets()
    local presets = saved.rolePresets()
    local active = saved.activeRolePreset()
    for i, r in ipairs(listRows) do
      local preset = presets[i - 1]
      r.shown = i == 1 or preset ~= nil
      r.slot = preset and preset.slot
      local chosen = r.shown and r.slot == active
      hideAll({ r.hit, r.title }, not r.shown)
      set(r.bar, "hidden", not chosen)
      if r.shown then
        set(r.hit, "rgb", chosen and COLOURS.line or COLOURS.panel)
        set(r.title, "content", preset and preset.name or "Defaults")
        set(r.title, "rgb", chosen and COLOURS.text or COLOURS.mutedText)
      end
    end
    local y = LIST_Y + (#presets + 1) * LIST_ROW + 8
    local full = #presets >= savedparty.MAX_ROLE_PRESETS
    set(nameField, "hidden", full)
    draw.pos(nameField, MARGIN, y)
    addButton.group.set("hidden", full)
    addButton.group.place(LIST_W - MARGIN - 48, y)
    removeButton.group.set("hidden", active == nil)
    removeButton.group.place(MARGIN, full and y or y + 32)
    set(removeButton.label, "content", confirmRemove and "Click to remove" or "Remove")
  end

  -- Members ------------------------------------------------------------------------------------------

  local heading = label("", detailX, 8, 200, 24, nil, COLOURS.accent)
  local hint = label("", detailX + 208, 8, detailW - 208 - 190, 24, FONTS.small, COLOURS.mutedText)
  local range = text(page, FONTS.small, ui.AlignMode.BOTTOMRIGHT, width - MARGIN - 170, 8, 104, 24)
  local function turn(by)
    return function()
      pageIndex = pageIndex + by
      p.follow()
    end
  end
  local pager = {
    range,
    controls.gameButton(page, "<", width - MARGIN - 60, 6, 28, 28, turn(-1)),
    controls.gameButton(page, ">", width - MARGIN - 28, 6, 28, 28, turn(1)),
  }

  -- The tags of the names shown: the active preset's, or the defaults.
  local function setRole(name, tag)
    saved.setRole(name, tag)
    confirmRemove = false
    changed()
  end

  local rows = {}
  for i = 1, ROWS do
    local y = LIST_Y + (i - 1) * ROW_H
    local right = detailX + detailW - 8
    local r = {
      bg = rect(page, i % 2 == 1 and COLOURS.row or COLOURS.rowAlt, detailX, y, detailW, ROW_H),
      name = text(page, FONTS.body, ui.AlignMode.TOPLEFT, detailX + 8, y, 200, ROW_H),
      leader = draw.new(ui.Sprite, page),
      tagEdge = rect(page, COLOURS.highlight, detailX + 240, y + 9, 20, 13),
      tagFace = rect(page, COLOURS.border, detailX + 241, y + 10, 18, 11),
      tagText = text(page, FONTS.small, ui.AlignMode.CENTRE, detailX + 240, y + 9, 20, 13),
      field = controls.inputField(page, right - FIELD_W, y + 4, FIELD_W, 24, savedparty.MAX_TAG),
    }
    draw.pos(r.leader, detailX + 216, y + 10)
    draw.size(r.leader, 12, 12)
    set(r.tagText, "isShadowed", false)
    r.baseTank = controls.option(
      page,
      "Base tank",
      right - FIELD_W - 8 - BASE_TANK_W,
      y + 4,
      BASE_TANK_W,
      24,
      function()
        if r.member ~= nil then
          setRole(r.member, r.tag ~= party.BASE_TANK and party.BASE_TANK or nil)
        end
      end
    )
    on(r.field, "ONCONTENTCHANGED", function(_, _, contents)
      -- A change arriving after the row took another member is ignored.
      if r.member ~= nil and r.fieldFor == r.member then
        local roles = saved.roles()
        saved.setRole(r.member, contents)
        -- The field keeps what was typed, so the next redraw leaves it alone.
        r.fieldTag = party.tag(roles, r.member)
        changed()
      end
    end)
    r.tagParts = { r.tagEdge, r.tagFace, r.tagText }
    r.all = { r.bg, r.name, r.field, r.baseTank.canvas, r.baseTank.bg, r.baseTank.label }
    rows[i] = r
  end

  function p.follow()
    local list = members()
    local active = saved.activeRolePreset()
    local roles = saved.roles()
    local pages = math.max(1, (#list + ROWS - 1) // ROWS)
    pageIndex = math.max(1, math.min(pageIndex, pages))
    hideAll(pager, pages == 1)
    local first = (pageIndex - 1) * ROWS
    set(range, "content", (first + 1) .. " to " .. math.min(first + ROWS, #list) .. " of " .. #list)
    for i, r in ipairs(rows) do
      local m = list[first + i]
      hideAll(r.all, m == nil)
      r.member = m and m.name
      local tag = m and party.tag(roles, m.name)
      r.tag = tag
      set(r.leader, "hidden", m == nil or m.leader == nil)
      hideAll(r.tagParts, tag == nil)
      if m ~= nil then
        set(r.name, "content", m.name)
        if m.leader ~= nil then
          draw.icon(r.leader, m.leader)
        end
        controls.showOption(r.baseTank, tag == party.BASE_TANK)
        if tag ~= nil then
          local gold = tag == party.BASE_TANK
          local w = math.max(20, 7 * #tag + 6)
          draw.width(r.tagEdge, w)
          draw.width(r.tagFace, w - 2)
          draw.width(r.tagText, w)
          set(r.tagEdge, "rgb", gold and GOLD or COLOURS.highlight)
          set(r.tagFace, "rgb", gold and GOLD or COLOURS.border)
          set(r.tagText, "rgb", gold and style.DARK_TEXT or COLOURS.highlight)
          set(r.tagText, "content", tag)
        end
        -- The field takes the tag when its row shows another member or preset, or the tag changed elsewhere.
        if r.fieldFor ~= m.name or r.fieldPreset ~= active or r.fieldTag ~= tag then
          r.fieldFor, r.fieldPreset, r.fieldTag = m.name, active, tag
          r.field.content = tag ~= nil and tag ~= party.BASE_TANK and tag or ""
        end
      else
        r.fieldFor = nil
      end
    end
    local presetName = nil
    for _, preset in ipairs(active and saved.rolePresets() or NO_MEMBERS) do
      if preset.slot == active then
        presetName = preset.name
      end
    end
    set(heading, "content", presetName or "Defaults")
    local none = #list == 0 and "Join a group to tag its members."
    set(hint, "content", none or presetName and "Other names keep their default tag." or "")
  end

  -- Frame sizes --------------------------------------------------------------------------------------

  rect(page, COLOURS.line, 0, top, width, 1)
  label("Frame sizes", MARGIN, top + 8, 200, 24, nil, COLOURS.accent)
  local sidebarCheck = controls.check(page, width - MARGIN - 250, top + 12, 16, function(ticked)
    saved.setSidebar("on", ticked)
    changed()
  end)
  label("Draw the group window as a sidebar", width - MARGIN - 226, top + 8, 226, 24)

  local blockW = (width - 2 * MARGIN - (#party.TIERS - 1) * MARGIN) // #party.TIERS
  local tierParts = {}
  for i, tier in ipairs(party.TIERS) do
    local x = MARGIN + (i - 1) * (blockW + MARGIN)
    label(tier.label, x, top + 34, blockW, 20)
    local parts = { steppers = {} }
    for row, field in ipairs(TIER_FIELDS) do
      local y = top + 56 + (row - 1) * STEP_ROW
      label(field[2], x, y, 70, 28, FONTS.small, COLOURS.mutedText)
      local limits = savedparty.TIER_RANGES[field[1]]
      parts.steppers[field[1]] = controls.stepper(page, x + 70, y, limits[1], limits[2], 1, function(n)
        saved.setPartyTier(tier.id, field[1], n)
        changed()
      end)
    end
    local checkY = top + 56 + #TIER_FIELDS * STEP_ROW + 2
    parts.showSelf = controls.check(page, x, checkY, 16, function(ticked)
      saved.setPartyTier(tier.id, "showSelf", ticked)
      changed()
    end)
    label("Show my frame", x + 24, checkY - 4, blockW - 24, 24, FONTS.small, COLOURS.mutedText)
    tierParts[tier.id] = parts
  end

  function p.open()
    showPresets()
    p.follow()
    sidebarCheck.show(saved.sidebar().on)
    for id, tier in pairs(saved.partyTiers()) do
      for field, stepper in pairs(tierParts[id].steppers) do
        stepper.show(tier[field])
      end
      tierParts[id].showSelf.show(tier.showSelf)
    end
  end

  p.open()
  return p
end

return partypage
