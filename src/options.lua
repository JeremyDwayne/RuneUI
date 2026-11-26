-- The options window and the src/ribbon panel that opens it: a PrettyUI window with a src/pagenav list of pages
-- down its left side, the src/appearancepage Style and Bars pages, the src/cooldownpage Cooldown manager, the
-- src/buffspage Buffs page, the src/partypage Party page, and a footer with Edit mode into src/editmode, Reset
-- positions and Done.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local catalog = require("src/catalog")
local controls = require("src/controls")
local cooldownpage = require("src/cooldownpage")
local draw = require("src/draw")
local editmode = require("src/editmode")
local pagenav = require("src/pagenav")
local partypage = require("src/partypage")
local ribbon = require("src/ribbon")
local style = require("src/style")

local options = {}

local rect = draw.rect
local hitArea = draw.hitArea
local on = draw.on
local COLOURS = draw.WINDOW

-- The list of pages' width.
local NAV_W = 184
local WIDTH = 900 + NAV_W
local HEIGHT = 680
-- The window's content sits inside its 8 px border under its 32 px title bar. The list of pages runs down its
-- left above the footer, and each page fills the rest.
local CONTENT_X = 8
local CONTENT_Y = 32
local CONTENT_W = WIDTH - 2 * CONTENT_X
local CONTENT_H = HEIGHT - CONTENT_Y - CONTENT_X
local FOOTER = 46
local PAGE_X = CONTENT_X + NAV_W
local PAGE_Y = CONTENT_Y
local PAGE_W = CONTENT_W - NAV_W
local PAGE_H = CONTENT_H - FOOTER
-- Footer game buttons from the right with their widths, and the gap between them and at the window's edge.
local FOOTER_BUTTONS = { { "Done", 90 }, { "Reset positions", 150 }, { "Edit mode", 110 } }
local FOOTER_GAP = 12
local BUTTON_H = 28
-- deps: { saved = src/settings, tracker = src/cooldowns tracker, elements = src/view elements by name,
-- view = src/view, auraInfo(sprite) naming an aura icon, describe(struct) reading a struct's description,
-- members = function returning the group's members as src/party's tracker lists them, windows = function
-- returning the game windows the Windows page lists, each { name, label }, refresh = function
-- redrawing the HUD, configured = function run as the window or edit mode opens or closes, escape = optional
-- function run first on Esc, returning true when a popup above the window took the key }.
-- Returns { placeAll, open, redrawPage, configuring, shutdown }; placeAll places the HUD and edit mode's overlays
-- from the saved positions and anchors, open(pageID) opens the window on that page, redrawPage redraws the Buffs
-- or Party page while it is shown, each server tick, and configuring says whether the window or edit mode is
-- open. Every plugin on the plugin layer shares its 4096 dynamic ids, so the window builds as it opens, with the
-- Style page, each other page builds on the first visit to it, and closing destroys them all. A window
-- whose build is refused logs and stays closed.
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

  -- The window, its list's show(id), each page's layer by id and the Buffs tooltip while the window is open, nil
  -- otherwise, and each page's module by id once built in the window's life.
  local window, showNav, pageLayers, buffsTooltip
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

  -- The pages. build(layer) builds one on its layer, once per window, and show(page), when given, redraws it as
  -- it is chosen. A settings page is a src/appearancepage page, whose scrollbar drag cancel ends. The Buffs
  -- page's Display tab takes rows from the Style page, which builds as the window opens.
  local PAGE_LIST = {
    {
      id = "appearance",
      label = "Style",
      settings = true,
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
        local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
        appearance.choiceRow(display, 24, 18, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)
        appearance.choiceRow(display, 24, 68, PAGE_W - 48, "Debuff border", style.DEBUFF_EDGES, "debuffEdge", 96)
        -- The Style page redrew its rows as the window opened, before these were built.
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
      settings = true,
      build = function(layer)
        return appearancepage.bars(layer, PAGE_W, PAGE_H, settingsDeps())
      end,
      show = open,
    },
    {
      id = "party",
      label = "Party",
      build = function(layer)
        return partypage.create(layer, PAGE_W, PAGE_H, { saved = saved, members = deps.members, refresh = refresh })
      end,
      show = open,
    },
    {
      id = "windows",
      label = "Windows",
      settings = true,
      build = function(layer)
        local pageDeps = settingsDeps()
        pageDeps.windows = deps.windows
        return appearancepage.windows(layer, PAGE_W, PAGE_H, pageDeps)
      end,
      show = open,
    },
    {
      id = "actionbars",
      label = "Action bars",
      settings = true,
      build = function(layer)
        return appearancepage.actionBars(layer, PAGE_W, PAGE_H, settingsDeps())
      end,
      show = open,
    },
    {
      id = "hidden",
      label = "Hidden interfaces",
      settings = true,
      build = function(layer)
        return appearancepage.hidden(layer, PAGE_W, PAGE_H, settingsDeps())
      end,
      show = open,
    },
  }
  local PAGES = {}
  for _, entry in ipairs(PAGE_LIST) do
    PAGES[entry.id] = entry
  end
  -- The list of pages' groups, each { label, pages = { { id, label } } } in list order.
  local NAV_GROUPS = {}
  for i, group in ipairs({
    { label = "RuneUI HUD", pages = { "appearance", "bars", "cooldowns", "buffs", "party" } },
    { label = "Game interfaces", pages = { "windows", "actionbars", "hidden" } },
  }) do
    NAV_GROUPS[i] = { label = group.label, pages = {} }
    for j, pageID in ipairs(group.pages) do
      NAV_GROUPS[i].pages[j] = { id = pageID, label = PAGES[pageID].label }
    end
  end

  -- Builds page pageID on its layer unless it is built.
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
    if pages.windows ~= nil then
      pages.windows.closePopup()
    end
  end

  -- Shows page pageID, building it on its first visit, and hides the rest.
  local function showPage(pageID)
    buildPage(pageID)
    closePopups()
    currentPage = pageID
    for id, layer in pairs(pageLayers) do
      draw.set(layer, "hidden", id ~= pageID)
    end
    showNav(pageID)
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
    window, showNav, pageLayers, buffsTooltip = nil, nil, nil, nil
    pages = {}
  end

  -- Runs as the window closes; PrettyUI then destroys it.
  local function closeWindow()
    closeConfirm()
    if pages.cooldowns ~= nil then
      pages.cooldowns.close()
    end
    for id, page in pairs(pages) do
      if PAGES[id].settings then
        page.cancel()
      end
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

  -- Builds the window, its list of pages, a layer per page, the footer and the Style page. PrettyUI builds the window
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

    local nav = draw.new(ui.Layer, window.content)
    draw.size(nav, NAV_W, PAGE_H)
    showNav = pagenav.create(nav, NAV_W, PAGE_H, NAV_GROUPS, showPage)

    -- Each page is a layer beside the list, which the page's module draws on.
    pageLayers = {}
    for _, entry in ipairs(PAGE_LIST) do
      local page = draw.new(ui.Layer, window.content)
      draw.pos(page, NAV_W, 0)
      draw.size(page, PAGE_W, PAGE_H)
      -- A click on the page's background closes its popups. A settings page's backdrop takes the wheel instead.
      if not entry.settings then
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

  -- Opens the window on the page whose id is pageID, or on Style.
  function openWindow(pageID)
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
    showPage(PAGES[pageID] and pageID or "appearance")
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves a drag with the cursor on every rendered frame. Each page returns before reading the mouse unless a
  -- press is held, and no page is built while the window is closed.
  Event.Draw.Subscribe("runeuiOptions", function()
    for _, page in pairs(pages) do
      page.follow()
    end
  end)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE or (deps.escape ~= nil and deps.escape()) then
      return
    end
    if confirm ~= nil then
      closeConfirm()
    elseif editing() then
      editMode.escape()
    elseif
      (pages.cooldowns ~= nil and pages.cooldowns.popupOpen())
      or (pages.buffs ~= nil and pages.buffs.popupOpen())
      or (pages.windows ~= nil and pages.windows.popupOpen())
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
    open = openWindow,
    redrawPage = function()
      if windowOpen and currentPage == "buffs" then
        pages.buffs.redraw()
      elseif windowOpen and currentPage == "party" then
        pages.party.follow()
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
