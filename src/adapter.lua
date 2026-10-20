-- The only module that reads the RS3 client. Returns plain tables in the shapes src/frames expects.
local adapter = {}

local MAIN_BAR = 1430
local TARGET_PANEL = 1490
-- Target debuff icon sprites sit every 3 static IDs from :38 to :71; -1 marks an empty slot.
local DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP = 38, 71, 3

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

function adapter.targetReads()
  local debuffs = {}
  for staticID = DEBUFF_FIRST, DEBUFF_LAST, DEBUFF_STEP do
    local c = ui.Interfaces:GetComponent(TARGET_PANEL, staticID)
    local sprite = c and read(c, "spriteID")
    if sprite ~= nil and sprite ~= -1 then debuffs[#debuffs + 1] = sprite end
  end
  return {
    target = varValue("VarPlayer", "NPCTARGET"),
    name = labelText(TARGET_PANEL, 21),
    lifepointsLabel = labelText(TARGET_PANEL, 34),
    healthPercent = varValue("VarClient", "COMBATV2_TARGET_SIDE_PANEL_HEALTH"),
    debuffs = debuffs,
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
