-- PrettyUI stand-in for specs that drive src/options and its pages, built on spec/support/fake_ui. require()
-- sets the prettyui global and returns the fake: calls counts setter calls a spec makes, such as SetActive,
-- Show and Close; find(kind, match) returns the first live component of that kind whose root is shown and that
-- match(c) accepts; fire(c, value) acts as the player would, choosing a tab by index or label, pressing a
-- button, clicking a CheckboxButton's choice of that value (default its first), or answering a Confirm with
-- "confirm" or "cancel"; button(text) presses the shown FancyButton or game button reading text; reset() forgets every
-- component and resets fake_ui as well. Each component keeps its options and a fake_ui root, and hosts keep a
-- content layer for raw components.
local fake = require("spec/support/fake_ui")

local pretty = { calls = 0, made = {} }

local function make(kind, parent, options)
  local c = { kind = kind, options = options or {}, root = ui.Layer.new(parent) }
  pretty.made[#pretty.made + 1] = c
  return c
end

-- Host methods: each Add helper builds its component on the host's content layer.
local function host(c)
  c.content = ui.Layer.new(c.root)
  function c.AddTabs(self, values, options)
    return pretty.Tabs.new(self.content, values, options)
  end
  function c.AddFancyButton(self, text, action, options)
    return pretty.FancyButton.new(self.content, text, action, options)
  end
  return c
end

pretty.Window = {}

function pretty.Window.new(parent, options)
  local w = host(make("Window", parent, options))
  w.root:MoveToFront()
  function w.Show(self)
    pretty.calls = pretty.calls + 1
    self.root.hidden = false
    self.root:MoveToFront()
  end
  function w.Close(self)
    pretty.calls = pretty.calls + 1
    if self.options.onClose then
      self.options.onClose(self)
    end
    if self.options.destroyOnClose then
      self:Destroy()
    else
      self.root.hidden = true
    end
  end
  function w.Destroy(self)
    self.destroyed = true
    self.root:Destroy()
  end
  return w
end

pretty.Tabs = {}

-- Shows page index and hides the rest, running onChange on a change unless notify is false.
local function activate(tabs, index, notify)
  local previous = tabs.active
  tabs.active = index
  for i, page in ipairs(tabs.pages) do
    page.root.hidden = i ~= index
  end
  if notify ~= false and previous ~= index and tabs.options.onChange then
    tabs.options.onChange(tabs, index, tabs.values[index].text, tabs.pages[index])
  end
end

function pretty.Tabs.new(parent, values, options)
  local tabs = make("Tabs", parent, options)
  tabs.values = values
  tabs.content = ui.Layer.new(tabs.root)
  tabs.pages = {}
  for i = 1, #values do
    local page = { root = ui.Layer.new(tabs.content) }
    tabs.pages[i] = host(page)
  end
  function tabs.SetActive(self, index, notify)
    pretty.calls = pretty.calls + 1
    activate(self, index, notify)
  end
  function tabs.GetActiveIndex(self)
    return self.active
  end
  function tabs.GetPage(self, index)
    return self.pages[index]
  end
  activate(tabs, tabs.options.activeIndex or 1, false)
  return tabs
end

pretty.FancyButton = {}

-- A button's width and height for text, as PrettyUI measures it.
function pretty.FancyButton.getSize(text)
  return math.max(100, #text * 9 + 40), 27
end

function pretty.FancyButton.new(parent, text, action, options)
  local b = make("FancyButton", parent, options)
  b.text = text
  b.action = action
  function b.SetText(self, t)
    pretty.calls = pretty.calls + 1
    self.text = t
  end
  return b
end

pretty.CheckboxButton = {}

-- Ticks each choice in options.selectedValues or marked selected. SetSelected runs onChange on a change unless
-- notify is false, as PrettyUI's does.
function pretty.CheckboxButton.new(parent, choices, options)
  local box = make("CheckboxButton", parent, options)
  box.choices = choices
  box.ticked = {}
  for _, choice in ipairs(choices) do
    for _, value in ipairs(box.options.selectedValues or {}) do
      box.ticked[choice.value] = box.ticked[choice.value] or value == choice.value
    end
    box.ticked[choice.value] = box.ticked[choice.value] or choice.selected == true
  end
  function box.SetSelected(self, value, selected, notify)
    pretty.calls = pretty.calls + 1
    if self.ticked[value] == selected then
      return true
    end
    self.ticked[value] = selected
    if notify ~= false and self.options.onChange then
      local values = {}
      for _, choice in ipairs(self.choices) do
        if self.ticked[choice.value] then
          values[#values + 1] = choice.value
        end
      end
      self.options.onChange(self, values, value, selected)
    end
    return true
  end
  function box.IsSelected(self, value)
    return self.ticked[value] == true
  end
  return box
end

pretty.Confirm = {}

function pretty.Confirm.new(parent, options)
  local dialog = make("Confirm", parent, options)
  function dialog.Destroy(self)
    self.destroyed = true
    self.root:Destroy()
  end
  return dialog
end

function pretty.find(kind, match)
  for _, c in ipairs(pretty.made) do
    if c.kind == kind and not c.destroyed and fake.shown(c.root) and (match == nil or match(c)) then
      return c
    end
  end
end

function pretty.fire(c, value)
  if c.kind == "Tabs" then
    local index = value
    for i, v in ipairs(c.values) do
      if v.text == value then
        index = i
      end
    end
    activate(c, index)
  elseif c.kind == "FancyButton" then
    c.action(c)
  elseif c.kind == "CheckboxButton" then
    local choice = value or c.choices[1].value
    c:SetSelected(choice, not c:IsSelected(choice))
  elseif c.kind == "Confirm" then
    local answer = value == "confirm" and c.options.onConfirm or c.options.onCancel
    if answer == nil or answer() ~= false then
      c:Destroy()
    end
  end
end

function pretty.button(text)
  local b = pretty.find("FancyButton", function(c)
    return c.text == text
  end)
  if b == nil then
    return fake.press(text)
  end
  pretty.fire(b)
end

function pretty.reset()
  fake.reset()
  pretty.calls = 0
  pretty.made = {}
end

_G.prettyui = pretty

return pretty
