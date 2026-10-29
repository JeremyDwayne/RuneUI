-- The options window and the src/ribbon panel that opens it: a PrettyUI window with a tab per page, the
-- src/appearancepage Appearance and Bars pages, the src/cooldownpage Cooldown manager, the src/buffspage Buffs
-- page, and a footer with Edit mode into src/editmode, Reset positions and Done.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local catalog = require("src/catalog")
local controls = require("src/controls")
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
-- Footer game buttons from the right with their widths, and the gap between them and at the window's edge.
local FOOTER_BUTTONS = { { "Done", 90 }, { "Reset positions", 150 }, { "Edit mode", 110 } }
local FOOTER_GAP = 12
local BUTTON_H = 28
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

  -- The window, its page tabs, each page's layer by id and the Buffs tooltip while the window is open, nil
  -- otherwise, and each page's module by id once built in the window's life.
  local window, pageTabs, pageLayers, buffsTooltip
  local pages = {}
  local currentPage = nil
  local windowOpen = false

  -- What the Appearance and Bars pages take.
  local function settingsDeps()
    return {
      saved = saved,
      view = deps.view,
      tooltip = buffsTooltip,
      auraInfo = deps.auraInfo,
      tracker = tracker,
      refresh = refresh,
    }
  end

  local function open(page)
    page.open()
  end

  -- The pages in tab order. build(layer) builds one on its tab's layer, once per window, and show(page), when
  -- given, redraws it as its tab is chosen. The Buffs page's Display tab takes rows from the Appearance page,
  -- which builds as the window opens.
  local PAGE_LIST = {
    {
      id = "appearance",
      label = "Appearance",
      build = function(layer)
        return appearancepage.create(layer, PAGE_W, PAGE_H, settingsDeps())
      end,
      show = open,
    },
    {
      id = "cooldowns",
      label = "Cooldown manager",
      build = function(layer)
        local page = cooldownpage.create(layer, PAGE_W, PAGE_H, { saved = saved, tracker = tracker, refresh = refresh })
        page.open()
        return page
      end,
    },
    {
      id = "buffs",
      label = "Buffs",
      build = function(layer)
        local page = buffspage.create(layer, PAGE_W, PAGE_H, {
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
        local appearance = pages.appearance
        local display = page.display
        appearance.checkRow(display, 24, 18, PAGE_W - 48, "Hide game buff bars", "hideBuffBars")
        local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
        appearance.choiceRow(display, 24, 68, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)
        appearance.choiceRow(display, 24, 118, PAGE_W - 48, "Debuff border", style.DEBUFF_EDGES, "debuffEdge", 96)
        -- The Appearance page redrew its rows as the window opened, before these were built.
        appearance.open()
        return page
      end,
      show = function(page)
        page.redraw()
      end,
    },
    {
      id = "bars",
      label = "Bars",
      build = function(layer)
        return appearancepage.bars(layer, PAGE_W, PAGE_H, settingsDeps())
      end,
      show = open,
    },
  }
  local PAGES = {}
  for _, entry in ipairs(PAGE_LIST) do
    PAGES[entry.id] = entry
  end

  -- Builds page pageID on its tab's layer unless it is built.
  local function buildPage(pageID)
    if pages[pageID] == nil then
      pages[pageID] = PAGES[pageID].build(pageLayers[pageID])
    end
  end

  -- Closes the popups of every built page, as a click on a page's background or Esc does.
  local function closePopups()
    if pages.cooldowns ~= nil then
      pages.cooldowns.closePopups()
    end
    if pages.buffs ~= nil then
      pages.buffs.close()
    end
  end

  local function showPage(pageID)
    buildPage(pageID)
    closePopups()
    currentPage = pageID
    local show = PAGES[pageID].show
    if show ~= nil then
      show(pages[pageID])
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
    pages = {}
  end

  -- Runs as the window closes; PrettyUI then destroys it.
  local function closeWindow()
    closeConfirm()
    if pages.cooldowns ~= nil then
      pages.cooldowns.close()
    end
    pages.appearance.cancel()
    if pages.bars ~= nil then
      pages.bars.cancel()
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
    for _, button in ipairs(FOOTER_BUTTONS) do
      local label, w = button[1], button[2]
      footerX = footerX - w
      controls.gameButton(
        window.content,
        label,
        footerX,
        CONTENT_H - FOOTER + (FOOTER - BUTTON_H) // 2,
        w,
        BUTTON_H,
        footerActions[label]
      )
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
  -- press is held, and no page is built while the window is closed.
  local function followCursor()
    for _, page in pairs(pages) do
      page.follow()
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
    elseif
      (pages.cooldowns ~= nil and pages.cooldowns.popupOpen()) or (pages.buffs ~= nil and pages.buffs.popupOpen())
    then
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
        pages.buffs.redraw()
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
