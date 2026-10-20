-- Builds display models for the player frame, target frame and resource bar from plain reads.
-- Pure: no client calls, so specs drive it with fake reads from src/adapter's shape.
local frames = {}

-- Spender resources shown as blocks above the resource bar, keyed by their VarPlayer name.
-- Both maxes are unconfirmed in the client.
frames.SPENDERS = {
  { var = "COMBATV2_BUFF_NECROMANCY_RESIDUAL_SOUL_STACKS", label = "Souls", max = 5 },
  { var = "COMBATV2_BUFF_NECROMANCY_NECROSIS_STACKS", label = "Necrosis", max = 12 },
}

local function clamp01(x)
  return math.max(0, math.min(1, x))
end

local function oneDecimal(x)
  if x == math.floor(x) then return tostring(math.floor(x)) end
  return string.format("%.1f", x)
end

local function withCommas(n)
  local reversed = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,")
  return (reversed:reverse():gsub("^,", ""))
end

-- Multiplies before dividing so 290 of 1000 reads 29%, not the 28% that 0.29 * 100 floors to.
local function percentText(part, whole)
  return math.floor(math.max(0, math.min(part, whole)) * 100 / whole) .. "%"
end

-- The max from a native "current/max" label such as "13,362/16,845", or nil.
local function labelMax(label)
  local max = label and label:match("/%s*([%d,]+)")
  return max and tonumber((max:gsub(",", "")))
end

-- 6,800 below ten thousand, 13.1K and 1.2M above, rounded down so it never overstates.
function frames.formatAmount(n)
  if n >= 1000000 then return oneDecimal(math.floor(n / 100000) / 10) .. "M" end
  if n >= 10000 then return oneDecimal(math.floor(n / 100) / 10) .. "K" end
  return withCommas(n)
end

-- reads: { available, name, lifepoints, lifepointsLabel, prayerValue, prayerLabel }
function frames.player(reads)
  if not reads.available or reads.lifepoints == nil then return { hidden = true } end
  local model = { hidden = false, name = reads.name or "" }
  local amount = frames.formatAmount(reads.lifepoints)
  local max = labelMax(reads.lifepointsLabel)
  if max ~= nil and max > 0 then
    model.fill = clamp01(reads.lifepoints / max)
    model.valueText = amount .. " | " .. percentText(reads.lifepoints, max)
  else
    model.valueText = amount
  end
  if reads.prayerValue ~= nil then
    -- The low 14 bits hold prayer in tenths of a point.
    local points = math.floor((reads.prayerValue % 16384) / 10)
    local prayerMax = labelMax(reads.prayerLabel)
    model.prayerText = tostring(points)
    if prayerMax ~= nil and prayerMax > 0 then model.prayerFill = clamp01(points / prayerMax) end
  end
  return model
end

-- reads: { target = NPCTARGET, name, lifepointsLabel = "6,800", healthPercent = 0..100, debuffs = { spriteID } }
-- The name and lifepoints come from the native target panel, which can be unloaded while a target is set.
function frames.target(reads)
  if reads.target == nil or reads.target == -1 or reads.lifepointsLabel == "N/A" then return { hidden = true } end
  local model = { hidden = false, name = reads.name or "", debuffs = reads.debuffs }
  local parts = {}
  local lifepoints = reads.lifepointsLabel and tonumber((reads.lifepointsLabel:gsub(",", "")))
  if lifepoints ~= nil then parts[#parts + 1] = frames.formatAmount(lifepoints) end
  if reads.healthPercent ~= nil then
    model.fill = clamp01(reads.healthPercent / 100)
    parts[#parts + 1] = percentText(reads.healthPercent, 100)
  end
  model.valueText = table.concat(parts, " | ")
  return model
end

-- reads: { adrenaline = SA_ENERGY in tenths of a percent, spenders = { [varName] = count } }
-- markers: { threshold = percent, ultimate = percent }
function frames.resource(reads, markers)
  if reads.adrenaline == nil then return { hidden = true } end
  local fill = clamp01(reads.adrenaline / 1000)
  local model = {
    hidden = false,
    fill = fill,
    text = percentText(reads.adrenaline, 1000),
    markers = {
      { at = clamp01(markers.threshold / 100), label = "Threshold" },
      { at = clamp01(markers.ultimate / 100), label = "Ultimate" },
    },
  }
  for _, spender in ipairs(frames.SPENDERS) do
    local count = reads.spenders[spender.var]
    if count ~= nil and count > 0 then
      model.spender = { label = spender.label, count = math.min(count, spender.max), max = spender.max }
      break
    end
  end
  return model
end

return frames
