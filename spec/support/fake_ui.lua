-- Client stand-ins for specs that drive src/view, src/options and src/editmode. require() sets the ui, Event,
-- Mouse, GameKey, id and log globals and returns the fake: writes counts property writes and Set, Add, Clear
-- and MoveToFront calls; component() builds a root; fire(name, payload) runs Event handlers, and
-- Event.<name>.Unsubscribe(ref) drops one; hook(c, name) runs a component's hook; find(predicate) returns the
-- first created component that is shown and matches; press(label) clicks the hit area under a shown label;
-- reset() forgets every component and handler, for a before_each. MoveToFront marks a shown component fronted
-- and a hidden one undrawn, along with each hidden direct child, as the client stops drawing those for good.
-- Destroy marks a component destroyed, and with it everything under it; live(root) counts the components under
-- root not destroyed. Setting limit makes a create raise, as the client's does, once that many live components
-- sit under the create's top root.
local fake = { writes = 0, mouse = { x = 0, y = 0 }, created = {}, handlers = {}, limit = nil }

local dataOf = setmetatable({}, { __mode = "k" })

local function call(method)
  return function(c, a, b)
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
    if method == "Destroy" then
      data.destroyed = true
    end
    if method == "SetAssociatedObject" then
      data.object = a
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

-- Clicks the last shown ONCLICK component under the nth shown text reading label, default the first, as the
-- client passes a click through the label to the hit area below it.
function fake.press(label, nth)
  local seen = 0
  local text = fake.find(function(_, d)
    if d.content == label then
      seen = seen + 1
    end
    return d.content == label and seen == (nth or 1)
  end)
  assert(text, "no shown label " .. label)
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
  assert(hit, "nothing to click under " .. label)
  fake.hook(hit, "ONCLICK")
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
_G.ui = {
  Layer = constructor,
  Rectangle = constructor,
  Text = constructor,
  Sprite = constructor,
  Canvas = constructor,
  InputField = constructor,
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
