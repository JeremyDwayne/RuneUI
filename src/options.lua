-- The options window and its ribbon button: a PrettyUI window with a tab per page, the src/appearancepage
-- Appearance and Bars pages, the src/cooldownpage Cooldown manager, the src/buffspage Buffs page, and a footer
-- with Edit mode into src/editmode, Reset positions and Done.
local appearancepage = require("src/appearancepage")
local buffspage = require("src/buffspage")
local catalog = require("src/catalog")
local cooldownpage = require("src/cooldownpage")
local draw = require("src/draw")
local editmode = require("src/editmode")
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
-- refresh = function redrawing the HUD }. Returns
-- { placeAll, redrawBuffs, shutdown }; placeAll places the HUD and edit mode's overlays from the saved
-- positions and anchors, and redrawBuffs redraws the Buffs page while it is shown. The window and its pages
-- are built on the first press of Options, since they are a third of the plugin's components and a load
-- that builds them freezes the game for seconds.
function options.create(root, deps)
  local saved = deps.saved
  local tracker = deps.tracker
  local elements = deps.elements

  -- The window and its pages, nil until the first open.
  local window, pageTabs, cooldownPage, buffsPage, appearance, bars
  local currentPage = nil
  local windowOpen = false

  -- Closes the popups of every page, as a click on a page's background or Esc does.
  local function closePopups()
    if window ~= nil then
      cooldownPage.closePopups()
      buffsPage.close()
    end
  end

  local function showPage(pageID)
    closePopups()
    currentPage = pageID
    if pageID == "buffs" then
      buffsPage.redraw()
    end
    if pageID == "appearance" then
      appearance.open()
    elseif pageID == "bars" then
      bars.open()
    end
  end

  -- Edit mode ----------------------------------------------------------------------------------------

  local resetPositions, openWindow
  local editMode = editmode.create(root, {
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
  })

  -- The open Reset positions confirm, or nil. It sits over the screen, so edit mode's toolbar can open it too.
  local confirm = nil

  local function closeConfirm()
    if confirm ~= nil then
      confirm:Destroy()
      confirm = nil
    end
  end

  local function closeWindow()
    closeConfirm()
    cooldownPage.close()
    appearance.cancel()
    bars.cancel()
    closePopups()
    windowOpen = false
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
        editMode.placeAll()
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

  -- Builds the window, a page per tab and the footer. PrettyUI builds the window open.
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
    local pages = {}
    for i, entry in ipairs(PAGE_LIST) do
      local page = ui.Layer.new(pageTabs:GetPage(i).content)
      page:SetSize(PAGE_W, PAGE_H)
      -- A click on the page's background closes its popups.
      if entry.id ~= "appearance" and entry.id ~= "bars" then
        on(hitArea(rect(page, COLOURS.panel, 0, 0, PAGE_W, PAGE_H)), "ONCLICK", function()
          closePopups()
        end)
      end
      pages[entry.id] = page
    end

    cooldownPage = cooldownpage.create(pages.cooldowns, PAGE_W, PAGE_H, {
      saved = saved,
      tracker = tracker,
      refresh = deps.refresh,
    })

    local buffsTooltip = deps.view.tooltip(root)
    buffsPage = buffspage.create(pages.buffs, PAGE_W, PAGE_H, {
      saved = saved,
      info = deps.auraInfo,
      catalog = catalog.rows,
      describe = deps.describe,
      tooltip = buffsTooltip,
      toScreen = function(px, py)
        return window.root.x + PAGE_X + px, window.root.y + PAGE_Y + py
      end,
      refresh = deps.refresh,
    })

    local pageDeps = {
      saved = saved,
      view = deps.view,
      tooltip = buffsTooltip,
      auraInfo = deps.auraInfo,
      tracker = tracker,
      refresh = deps.refresh,
    }
    appearance = appearancepage.create(pages.appearance, PAGE_W, PAGE_H, pageDeps)
    bars = appearancepage.bars(pages.bars, PAGE_W, PAGE_H, pageDeps)
    local showHide = { { id = false, label = "Show" }, { id = true, label = "Hide" } }
    appearance.choiceRow(buffsPage.display, 24, 18, PAGE_W - 48, "Game buff bars", showHide, "hideBuffBars", 120)
    local auraIcons = { { id = false, label = "Plain" }, { id = true, label = "With bars" } }
    appearance.choiceRow(buffsPage.display, 24, 68, PAGE_W - 48, "Aura icons", auraIcons, "auraBars", 120)
    appearance.choiceRow(buffsPage.display, 24, 118, PAGE_W - 48, "Debuff border", style.DEBUFF_EDGES, "debuffEdge", 96)

    -- Edit mode closes the window, which covers the HUD, and its toolbar's Done returns to the window.
    local footerActions = {
      Done = function()
        window:Close()
      end,
      ["Reset positions"] = resetPositions,
      ["Edit mode"] = function()
        window:Close()
        editMode.open()
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
  end

  function openWindow()
    if window == nil then
      build()
    else
      window:Show()
    end
    windowOpen = true
    cooldownPage.open()
    if pageTabs:GetActiveIndex() ~= 1 then
      pageTabs:SetActive(1, false)
    end
    showPage("appearance")
  end

  -- Ticks ---------------------------------------------------------------------------------------------

  -- Moves a drag with the cursor. It runs every frame through Event.Draw so a drag keeps up with the mouse,
  -- and on Event.Logic as well in case Draw does not fire. Each returns before reading the mouse unless a
  -- press is held, and nothing runs until the window is built.
  local function followCursor()
    if window == nil then
      return
    end
    buffsPage.follow()
    cooldownPage.follow()
    appearance.follow()
    bars.follow()
  end
  Event.Draw.Subscribe("runeuiOptions", followCursor)
  Event.Logic.Subscribe("runeuiOptions", followCursor)

  Event.KeyDown.Subscribe("runeuiOptions", function(e)
    if e.gameKey ~= GameKey.ESCAPE then
      return
    end
    if confirm ~= nil then
      closeConfirm()
    elseif editMode.editing() then
      editMode.escape()
    elseif window ~= nil and (cooldownPage.popupOpen() or buffsPage.popupOpen()) then
      closePopups()
    elseif windowOpen then
      window:Close()
    end
  end)

  Event.ContentLayerReady.Subscribe("runeuiRibbon", function(e)
    prettyui.FancyButton.new(e.component, "Options", openWindow, { x = 10, y = 10 })
  end)

  editMode.placeAll()

  return {
    placeAll = editMode.placeAll,
    redrawBuffs = function()
      if windowOpen and currentPage == "buffs" then
        buffsPage.redraw()
      end
    end,
    shutdown = function()
      closeConfirm()
      if window ~= nil then
        buffsPage.destroy()
        window:Destroy()
      end
      editMode.shutdown()
    end,
  }
end

return options
