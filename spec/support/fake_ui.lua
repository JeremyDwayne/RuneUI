-- Client stand-ins for specs that drive src/view, src/options and src/editmode. require() sets the ui, Event,
-- Mouse, GameKey, id and log globals and returns the fake: writes counts property writes and Set, Add, Clear
-- and MoveToFront calls, and each component's clears counts its Clear calls; component() builds a root;
-- fire(name, payload) runs Event handlers, and Event.<name>.Unsubscribe(ref) drops one; hook(c, name) runs a
-- component's hook; find(predicate) returns the first created component that is shown and matches;
-- press(label) clicks the hit area under a shown label, presses a game Button or ticks a game Check reading
-- label, picks a game RadioGroup's entry reading it, or ticks the Check on a label's row; pressText(text) clicks
-- the hit area under a canvas's text, which textHit(text) returns;
-- reset() forgets every component and handler, for a before_each. MoveToFront marks a shown component fronted
-- and a hidden one undrawn, along with each hidden direct child, as the client stops drawing those for good.
-- Destroy marks a component destroyed, and with it everything under it; live(root) counts the components under
-- root not destroyed. Setting limit makes a create raise, as the client's does, once that many live components
-- sit under the create's top root.
local fake = { writes = 0, mouse = { x = 0, y = 0 }, created = {}, handlers = {}, limit = nil }

local dataOf = setmetatable({}, { __mode = "k" })

local function call(method)
  return function(c, a, b, ...)
    if method:match("^Set") or method:match("^Add") or method == "Clear" or method == "MoveToFront" then
      fake.writes = fake.writes + 1
    end
    local data = dataOf[c]
    if method == "SetPos" then
      data.x = a
      data.y = b
    end
    if method == "SetSize" then
      data.width = a
      data.height = b
    end
    if method == "SetWidth" then
      data.width = a
    end
    if method == "SetHeight" then
      data.height = a
    end
    if method == "Clear" then
      data.clears = (data.clears or 0) + 1
      data.texts = nil
    end
    if method == "AddText" then
      data.texts = data.texts or {}
      data.texts[#data.texts + 1] = { x = a, y = b, text = select(3, ...) }
    end
    if method == "Destroy" then
      data.destroyed = true
    end
    if method == "SetAssociatedObject" then
      data.object = a
    end
    if method == "Add" and type(b) == "string" then
      data.entries = data.entries or {}
      data.entries[#data.entries + 1] = { id = a, label = b }
    end
    if method == "SetSelectionLimits" then
      data.limits = { a, b }
    end
    if method == "SetOptionSelected" then
      data.selected = data.selected or {}
      local count = 0
      for _, on in pairs(data.selected) do
        count = count + (on and 1 or 0)
      end
      -- The client refuses a change that leaves the selection outside its limits.
      local after = count + (b and not data.selected[a] and 1 or 0) - (not b and data.selected[a] and 1 or 0)
      if data.limits == nil or (after >= data.limits[1] and after <= data.limits[2]) then
        data.selected[a] = b or nil
      end
    end
    if method == "MoveToFront" then
      if fake.shown(c) then
        data.fronted = true
        for _, other in ipairs(fake.created) do
          if dataOf[other].parent == c and dataOf[other].hidden then
            dataOf[other].undrawn = true
          end
        end
      else
        data.undrawn = true
      end
    end
  end
end

local function subscribe(c, hook, fn)
  dataOf[c].hooks[hook] = fn
end

-- Whether c or any parent it has is destroyed.
local function destroyed(c)
  while c ~= nil do
    if dataOf[c].destroyed then
      return true
    end
    c = dataOf[c].parent
  end
  return false
end

-- Whether root is c or a parent of c.
local function under(c, root)
  while c ~= nil do
    if c == root then
      return true
    end
    c = dataOf[c].parent
  end
  return false
end

function fake.live(root)
  local n = 0
  for _, c in ipairs(fake.created) do
    if c ~= root and under(c, root) and not destroyed(c) then
      n = n + 1
    end
  end
  return n
end

function fake.component(parent)
  if parent ~= nil and fake.limit ~= nil then
    local top = parent
    while dataOf[top].parent ~= nil do
      top = dataOf[top].parent
    end
    if fake.live(top) >= fake.limit then
      error("Failed to create component (category=0 ID=4096) - invalid dynamic ID")
    end
  end
  local data = { hooks = {}, parent = parent, x = 0, y = 0 }
  local c = setmetatable({}, {
    __index = function(_, key)
      if key == "Subscribe" then
        return subscribe
      end
      if data[key] ~= nil then
        return data[key]
      end
      if type(key) == "string" and key:match("^%u") then
        return call(key)
      end
      return nil
    end,
    __newindex = function(_, key, value)
      fake.writes = fake.writes + 1
      data[key] = value
    end,
  })
  dataOf[c] = data
  fake.created[#fake.created + 1] = c
  return c
end

function fake.reset()
  fake.writes = 0
  fake.created = {}
  fake.handlers = {}
  fake.limit = nil
  fake.mouse.x = 0
  fake.mouse.y = 0
end

-- Whether c and every parent it has are shown and not destroyed.
function fake.shown(c)
  while c ~= nil do
    if dataOf[c].hidden or dataOf[c].destroyed then
      return false
    end
    c = dataOf[c].parent
  end
  return true
end

function fake.find(predicate)
  for _, c in ipairs(fake.created) do
    if fake.shown(c) and predicate(c, dataOf[c]) then
      return c
    end
  end
end

function fake.hook(c, name, x, y)
  dataOf[c].hooks[name](c, x or 0, y or 0)
end

-- The last shown ONCLICK component under shown text t, as the client passes a click through a label to the hit
-- area below it, or failing that the shown Check on t's row.
local function under_(text)
  local t = dataOf[text]
  local hit = nil
  for _, c in ipairs(fake.created) do
    local d = dataOf[c]
    if
      c ~= text
      and d.parent == t.parent
      and d.hooks.ONCLICK
      and fake.shown(c)
      and d.width
      and t.x >= d.x
      and t.x < d.x + d.width
      and t.y >= d.y
      and t.y < d.y + d.height
    then
      hit = c
    end
  end
  if hit ~= nil then
    return function()
      fake.hook(hit, "ONCLICK")
    end
  end
  for _, c in ipairs(fake.created) do
    local d = dataOf[c]
    if d.parent == t.parent and d.check and fake.shown(c) and t.y + (t.height or 0) > d.y and t.y < d.y + d.height then
      return function()
        fake.tick(c)
      end
    end
  end
end

-- Ticks or unticks a game Check, as a click on it does.
function fake.tick(c)
  local d = dataOf[c]
  d.value = not d.value
  d.hooks.ONBUTTONPRESSED(c, d.value and 1 or 0, d.value and 0 or 1)
end

-- Picks a game RadioGroup's entry id, as a click on it does: the old entry reports (id, 0), then the new
-- (id, 1), each once the selection has moved. A click on the chosen entry reports nothing.
local function pick(c, entryID)
  local d = dataOf[c]
  d.selected = d.selected or {}
  if d.selected[entryID] then
    return
  end
  local old = next(d.selected)
  d.selected = { [entryID] = true }
  if old ~= nil then
    d.hooks.ONSELECTIONCHANGED(c, old, 0)
  end
  d.hooks.ONSELECTIONCHANGED(c, entryID, 1)
end

-- Presses the nth shown control reading label, default the first, counting in the order each was made: a label
-- over a hit area or on a Check's row, a game Button or Check, or a game RadioGroup entry.
function fake.press(label, nth)
  local seen = 0
  for _, c in ipairs(fake.created) do
    local d = dataOf[c]
    if fake.shown(c) then
      local found, action = false, nil
      if d.content == label then
        found, action = true, under_(c)
      elseif d.label == label and d.hooks.ONBUTTONPRESSED then
        found = true
        action = function()
          if d.check then
            fake.tick(c)
          else
            d.hooks.ONBUTTONPRESSED(c, 0, 1)
          end
        end
      else
        for _, entry in ipairs(d.entries or {}) do
          if entry.label == label and d.hooks.ONSELECTIONCHANGED then
            found = true
            action = function()
              pick(c, entry.id)
            end
          end
        end
      end
      if found then
        seen = seen + 1
        if seen == (nth or 1) then
          assert(action, "nothing to press under " .. label)
          return action()
        end
      end
    end
  end
  error("no shown control reading " .. label)
end

-- The label of the entry chosen on game RadioGroup c, or nil when none is.
function fake.chosen(c)
  local d = dataOf[c]
  for _, entry in ipairs(d.entries or {}) do
    if (d.selected or {})[entry.id] then
      return entry.label
    end
  end
end

-- The shown hit area at the spot of the shown canvas text reading text.
function fake.textHit(text)
  for _, c in ipairs(fake.created) do
    local d = dataOf[c]
    for _, t in ipairs(d.texts or {}) do
      if t.text == text and fake.shown(c) then
        for _, hit in ipairs(fake.created) do
          local h = dataOf[hit]
          if h.parent == d.parent and h.hooks.ONCLICK and h.x == d.x + t.x and h.y == d.y + t.y and fake.shown(hit) then
            return hit
          end
        end
      end
    end
  end
  error("no canvas text " .. text)
end

-- Clicks the hit area textHit finds, as press does for a label.
function fake.pressText(text)
  fake.hook(fake.textHit(text), "ONCLICK")
end

function fake.hasHook(c, name)
  return dataOf[c].hooks[name] ~= nil
end

function fake.fire(name, payload)
  for _, fn in pairs(fake.handlers[name] or {}) do
    fn(payload)
  end
end

local constructor = { new = fake.component }
-- A game Check, which press and tick tell apart from a Button by this mark.
local check = {
  new = function(parent)
    local c = fake.component(parent)
    dataOf[c].check = true
    return c
  end,
}
_G.ui = {
  Layer = constructor,
  Rectangle = constructor,
  Text = constructor,
  Sprite = constructor,
  Canvas = constructor,
  InputField = constructor,
  Button = constructor,
  Check = check,
  RadioGroup = constructor,
  TextDataConfig = {
    new = function()
      return {}
    end,
  },
  TextContentVisibilityMode = { VISIBLE = 0 },
  InputFieldFilterMode = { NONE = 0 },
  InputFieldActionResult = { NONE = 0, CONTENT_CHANGE = 2, SUBMIT = 3, SUBMIT_ON_FOCUS_LOSS = 5 },
  Hook = setmetatable({}, {
    __index = function(_, name)
      return name
    end,
  }),
  AlignMode = { TOPLEFT = 0, CENTRE = 1, BOTTOMRIGHT = 2 },
}
_G.Event = setmetatable({}, {
  __index = function(_, name)
    return {
      Subscribe = function(ref, fn)
        fake.handlers[name] = fake.handlers[name] or {}
        fake.handlers[name][ref] = fn
      end,
      Unsubscribe = function(ref)
        if fake.handlers[name] ~= nil then
          fake.handlers[name][ref] = nil
        end
      end,
    }
  end,
})
_G.Mouse = {
  GetX = function()
    return fake.mouse.x
  end,
  GetY = function()
    return fake.mouse.y
  end,
}
_G.GameKey = { ESCAPE = 13, SHIFT = 81 }
-- Each font and sprite id is its name, so specs can read which font a label holds or which sprite shows.
local byName = {
  __index = function(_, name)
    return name
  end,
}
_G.id = { Font = setmetatable({}, byName), Sprite = setmetatable({}, byName), StyleSheet = {} }
_G.log = function() end

return fake
