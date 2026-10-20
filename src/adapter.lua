-- The only module that reads the RS3 client. Returns plain tables in the shapes src/frames expects.
local adapter = {}

local MAIN_BAR = 1430

-- Reads a field from a game proxy, returning nil when the proxy does not expose it.
local function read(obj, field)
  local ok, value = pcall(function() return obj[field] end)
  if ok then return value end
end

local function varValue(domain, name)
  local v = read(var[domain], name)
  if v ~= nil then return read(v, "value") end
end

-- Text of a label component, or nil when it is missing or empty.
local function labelText(interfaceID, staticID, categoryID, dynamicID)
  local c
  if categoryID ~= nil then
    c = ui.Interfaces:GetComponent(interfaceID, staticID, categoryID, dynamicID)
  else
    c = ui.Interfaces:GetComponent(interfaceID, staticID)
  end
  local text = c and read(c, "content")
  if type(text) == "string" and text ~= "" then return text end
end

function adapter.playerReads()
  local available = Player.IsAvailable()
  local entity = available and Player.GetEntity() or nil
  return {
    available = available,
    name = entity and read(entity, "displayName"),
    lifepoints = varValue("VarPlayer", "LIFEPOINTS"),
    lifepointsLabel = labelText(MAIN_BAR, 9, 0, 8),
    prayerValue = varValue("VarPlayer", "PRAYER_POINTS_VAR"),
    prayerLabel = labelText(MAIN_BAR, 16, 0, 8),
  }
end

-- spenders: the frames.SPENDERS list; each is read by its var name.
function adapter.resourceReads(spenders)
  local counts = {}
  for _, spender in ipairs(spenders) do
    counts[spender.var] = varValue("VarPlayer", spender.var)
  end
  return { adrenaline = varValue("VarPlayer", "SA_ENERGY"), spenders = counts }
end

return adapter
