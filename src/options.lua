-- The options window and the src/ribbon panel that opens it: a PrettyUI window with a tab per page, the
-- src/appearancepage Appearance and Bars pages, the src/cooldownpage Cooldown manager, the src/buffspage Buffs
-- page, and a footer with Edit mode into src/editmode, Reset positions and Done.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local catalog = require("src/catalog")
local cooldownpage = require("src/cooldownpage")
local draw = require("src/draw")
local editmode = require("src/editmode")
local ribbon = require("src/ribbon")
local style = require("src/style")

local options = {}

local rect = draw.rect
local hitArea = draw.hitArea
local on = draw.on
local COLOURS = draw.WINDOW

local WIDTH = 900
local HEIGHT = 680
-- The window's content sits inside its 8 px border under its 32 px title bar. Page tabs fill it above the
-- footer, and each page sits under the tabs' 42 px strip.
local CONTENT_X = 8
local CONTENT_Y = 32
local CONTENT_W = WIDTH - 2 * CONTENT_X
local CONTENT_H = HEIGHT - CONTENT_Y - CONTENT_X
local FOOTER = 46
local TAB_STRIP = 42
local PAGE_X = CONTENT_X
local PAGE_Y = CONTENT_Y + TAB_STRIP
local PAGE_W = CONTENT_W
local PAGE_H = CONTENT_H - FOOTER - TAB_STRIP
-- Footer buttons from the right, and the gap between them and at the window's edge.
local FOOTER_BUTTONS = { "Done", "Reset positions", "Edit mode" }
local FOOTER_GAP = 12
local BUTTON_H = 27
-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, auraInfo(sprite) naming an aura icon, describe(struct) reading a struct's description,
-- refresh = function redrawing the HUD, configured = function run as the window or edit mode opens or closes }.
-- Returns { placeAll, redrawBuffs, configuring, shutdown }; placeAll places the HUD and edit mode's overlays from
-- the saved positions and anchors, redrawBuffs redraws the Buffs page while it is shown, and configuring says
-- whether the window or edit mode is open. Every plugin on the plugin layer shares its 4096 dynamic ids, so the
-- window builds as it opens, with the Appearance page, each other page builds on the first visit to its tab,
-- and closing destroys them all. A window whose build is refused logs and stays closed.
function options.create(root, deps)
  local saved = deps.saved
  local tracker = deps.tracker
  local elements = deps.elements
  local configured = deps.configured
  -- Redraws the ribbon panel's switches, once the client has built it.
  local showRibbon = function() end

  -- Redraws the HUD and the ribbon's switches after a page saves a change.
  local function refresh()
    deps.refresh()
    showRibbon()
  end

  -- The window, its page tabs, each page's layer by id and the Buffs tooltip while the window is open, and each
  -- page's module once built; nil otherwise.
  local window, pageTabs, pageLayers, buffsTooltip
  local cooldownPage, buffsPage, appearance, bars
  local currentPage = nil
  local windowOpen = false
  local buildPage

  -- Closes the popups of every built page, as a click on a page's background or Esc does.
  local function closePopups()
    if cooldownPage ~= nil then
      cooldownPage.closePopups()
    end
    if buffsPage ~= nil then
      buffsPage.close()
    end
  end

  local function showPage(pageID)
    buildPage(pageID)
    closePopups()
    currentPage = pageID
    if pageID == "buffs" then
      buffsPage.redraw()
    elseif pageID == "appearance" then
      appearance.open()
    elseif pageID == "bars" then
      bars.open()
    end
  end

  -- Edit mode ----------------------------------------------------------------------------------------

  local resetPositions, openWindow
  -- Edit mode while it is open, nil otherwise.
  local editMode = nil

  local function editing()
    return editMode ~= nil and editMode.editing()
  end

  local function openEditMode()
    editMode = editmode.create(root, {
      saved = saved,
      elements = elements,
      view = deps.view,
      label = function(name)
        local group = saved.group(name)
        return group and group.title
      end,
      reset = function()
        resetPositions()
      end,
      done = function()
        openWindow()
      end,
      changed = function()
        if not editing() then
          editMode = nil
        end
        configured()
      end,
    })
    editMode.open()
  end

  -- Places the HUD from the saved positions and anchors, through edit mode while it is open so its overlays
  -- follow.
  local function placeAll()
    if editing() then
      editMode.placeAll()
    else
      deps.view.arrange(elements, saved.positions(), saved.anchors())
    end
  end

  -- The open Reset positions confirm, or nil. It sits over the screen, so edit mode's toolbar can open it too.
  local confirm = nil

  local function closeConfirm()
    if confirm ~= nil then
      confirm:Destroy()
      confirm = nil
    end
  end

  -- Destroys the Buffs tooltip, which sits on root, and forgets the window and its pages.
  local function forgetWindow()
    if buffsTooltip ~= nil then
      buffsTooltip.destroy()
    end
    window, pageTabs, pageLayers, buffsTooltip = nil, nil, nil, nil
    cooldownPage, buffsPage, appearance, bars = nil, nil, nil, nil
  end

  -- Runs as the window closes; PrettyUI then destroys it.
  local function closeWindow()
    closeConfirm()
    if cooldownPage ~= nil then
      cooldownPage.close()
    end
    appearance.cancel()
    if bars ~= nil then
      bars.cancel()
    end
    closePopups()
    forgetWindow()
    windowOpen = false
    configured()
  end

  function resetPositions()
    closePopups()
    closeConfirm()
    confirm = prettyui.Confirm.new(root, {
      title = "Reset positions",
      body = "Every frame, bar, ability group and aura row goes back to its default spot. "
        .. "Your groups and settings stay.",
      cancelLabel = "Cancel",
      confirmLabel = "Reset positions",
      onConfirm = function()
        confirm = nil
        saved.resetPositions()
        placeAll()
      end,
      onCancel = function()
        confirm = nil
      end,
    })
  end

  -- Window --------------------------------------------------------------------------------------------

  local PAGE_LIST = {
    { id = "appearance", label = "Appearance" },
    { id = "cooldowns", label = "Cooldown manager" },
    { id = "buffs", label = "Buffs" },
    { id = "bars", label = "Bars" },
  }

  -- Builds page pageID on its tab's layer unless it is built. The Buffs page's Display tab takes option rows
  -- from the Appearance page, which builds as the window opens.
  function buildPage(pageID)
    local page = pageLayers[pageID]
    local pageDeps = {
      saved = saved,
      view = deps.view,
      tooltip = buffsTooltip,
      auraInfo = deps.auraInfo,
      tracker = tracker,
      refresh = refresh,
    }
    if pageID == "appearance" and appearance == nil then
      appearance = appearancepage.create(page, PAGE_W, PAGE_H, pageDeps)
    elseif pageID == "bars" and bars == nil then
      bars = appearancepage.bars(page, PAGE_W, PAGE_H, pageDeps)
    elseif pageID == "cooldowns" and cooldownPage == nil then
      cooldownPage = cooldownpage.create(page, PAGE_W, PAGE_H, {
        saved = saved,
        tracker = tracker,
        refresh = refresh,
      })
      cooldownPage.open()
    elseif pageID == "buffs" and buffsPage == nil then
      buffsPage = buffspage.create(page, PAGE_W, PAGE_H, {
        saved = saved,
        info = deps.auraInfo,
        catalog = catalog.rows,
        describe = deps.describe,
        tooltip = buffsTooltip,
        toScreen = function(px, py)
          return window.root.x + PAGE_X + px, window.root.y + PAGE_Y + py
        end,
        refresh = refresh,
      })
      local showHide = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
      local display = buffsPage.display
      appearance.choiceRow(display, 24, 18, PAGE_W - 48, "Game buff bars", showHide, "hideBuffBars", 120)
      local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
      appearance.choiceRow(display, 24, 68, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)
      appearance.choiceRow(display, 24, 118, PAGE_W - 48, "Debuff border", style.DEBUFF_EDGES, "debuffEdge", 96)
    end
  end

  -- Builds the window, a layer per page tab, the footer and the Appearance page. PrettyUI builds the window
  -- open, and destroys it once closed.
  local function build()
    window = prettyui.Window.new(root, {
      title = "RuneUI",
      width = WIDTH,
      height = HEIGHT,
      x = -WIDTH // 2,
      y = -HEIGHT // 2,
      xAnchor = 0.5,
      yAnchor = 0.5,
      scrollable = false,
      destroyOnClose = true,
      onClose = function()
        closeWindow()
      end,
    })

    local tabValues = {}
    for i, entry in ipairs(PAGE_LIST) do
      tabValues[i] = { text = entry.label }
    end
    pageTabs = window:AddTabs(tabValues, {
      x = 0,
      y = 0,
      width = CONTENT_W,
      height = CONTENT_H - FOOTER,
      scrollable = false,
      onChange = function(_, index)
        showPage(PAGE_LIST[index].id)
      end,
    })

    -- Each page is a layer on its tab's content, which the page's module draws on.
    pageLayers = {}
    for i, entry in ipairs(PAGE_LIST) do
      local page = draw.new(ui.Layer, pageTabs:GetPage(i).content)
      page:SetSize(PAGE_W, PAGE_H)
      -- A click on the page's background closes its popups.
      if entry.id ~= "appearance" and entry.id ~= "bars" then
        on(hitArea(rect(page, COLOURS.panel, 0, 0, PAGE_W, PAGE_H)), "ONCLICK", function()
          closePopups()
        end)
      end
      pageLayers[entry.id] = page
    end
    buffsTooltip = deps.view.tooltip(root)

    -- Edit mode closes the window, which covers the HUD, and its toolbar's Done returns to the window.
    local footerActions = {
      Done = function()
        window:Close()
      end,
      ["Reset positions"] = resetPositions,
      ["Edit mode"] = function()
        window:Close()
        openEditMode()
      end,
    }
    local footerX = CONTENT_W - FOOTER_GAP
    for _, label in ipairs(FOOTER_BUTTONS) do
      footerX = footerX - prettyui.FancyButton.getSize(label)
      window:AddFancyButton(label, footerActions[label], {
        x = footerX,
        y = CONTENT_H - FOOTER + (FOOTER - BUTTON_H) // 2,
        variant = label == "Done" and "positive" or "neutral",
      })
      footerX = footerX - FOOTER_GAP
    end
    buildPage("appearance")
  end

  function openWindow()
    if window ~= nil then
      window:Show()
    else
      draw.refused()
      local ok, err = pcall(build)
      if not ok or draw.refused() then
        log("cannot open the options window:", ok and "the plugin layer has no ids left" or err)
        if window ~= nil then
          window:Destroy()
        end
        forgetWindow()
        return
      end
    end
    windowOpen = true
    configured()
    if pageTabs:GetActiveIndex() ~= 1 then
      pageTabs:SetActive(1, false)
    end
    showPage("appearance")
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves a drag with the cursor. It runs every frame through Event.Draw so a drag keeps up with the mouse,
  -- and on Event.Logic as well in case Draw does not fire. Each page returns before reading the mouse unless a
  -- press is held, and nothing runs while the window is closed.
  local function followCursor()
    if window == nil then
      return
    end
    appearance.follow()
    if buffsPage ~= nil then
      buffsPage.follow()
    end
    if cooldownPage ~= nil then
      cooldownPage.follow()
    end
    if bars ~= nil then
      bars.follow()
    end
  end
  Event.Draw.Subscribe("runeuiOptions", followCursor)
  Event.Logic.Subscribe("runeuiOptions", followCursor)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE then
      return
    end
    if confirm ~= nil then
      closeConfirm()
    elseif editing() then
      editMode.escape()
    elseif (cooldownPage ~= nil and cooldownPage.popupOpen()) or (buffsPage ~= nil and buffsPage.popupOpen()) then
      closePopups()
    elseif windowOpen then
      window:Close()
    end
  end)

  -- The client builds the ribbon's content layer afresh each time it opens, so the panel is built each time.
  Event.ContentLayerReady.Subscribe("runeuiRibbon", function(e)
    showRibbon = ribbon.create(e.component, {
      saved = saved,
      open = openWindow,
      changed = function()
        deps.refresh()
        if windowOpen then
          showPage(currentPage)
        end
      end,
    })
  end)

  placeAll()

  return {
    placeAll = placeAll,
    redrawBuffs = function()
      if windowOpen and currentPage == "buffs" then
        buffsPage.redraw()
      end
    end,
    configuring = function()
      return windowOpen or editing()
    end,
    shutdown = function()
      closeConfirm()
      if window ~= nil then
        window:Destroy()
        forgetWindow()
      end
      if editMode ~= nil then
        editMode.destroy()
      end
    end,
  }
end

return options
