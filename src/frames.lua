-- Builds display models for the player frame, target frame and resource bar from plain reads.
-- Pure: no client calls, so specs drive it with fake reads from src/adapter's shape.
local frames = {}

-- Unit frame lifepoints texts, with a sample of each.
frames.LIFEPOINTS = {
  { id = "short", label = "12.2K | 78%" }, { id = "full", label = "12,242 / 15,695" },
  { id = "amount", label = "12.2K" }, { id = "percent", label = "78%" },
}

-- Spender resources shown as rows of blocks above the resource bar, read by their VarPlayer name.
-- Residual souls cap at 3, or 5 with a Soulbound lantern equipped.
frames.SPENDERS = {
  { key = "souls", var = "COMBATV2_BUFF_NECROMANCY_RESIDUAL_SOUL_STACKS", max = 3, lanternMax = 5 },
  { key = "necrosis", var = "COMBATV2_BUFF_NECROMANCY_NECROSIS_STACKS", max = 12 },
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

-- A unit frame's value text in a frames.LIFEPOINTS format from its lifepoints, percent text and max, any of
-- which may be nil, formatting only what the format shows. The full format joins lifepoints and max with a
-- slash, or with a bar to the percent when the max is unknown. A format whose part is missing falls back to the
-- parts there are.
local function valueText(format, lifepoints, percent, max)
  if format == "full" and lifepoints ~= nil then
    if max ~= nil then return withCommas(lifepoints) .. " / " .. withCommas(max) end
    if percent == nil then return withCommas(lifepoints) end
    return withCommas(lifepoints) .. " | " .. percent
  elseif format == "amount" and lifepoints ~= nil then
    return frames.formatAmount(lifepoints)
  elseif format == "percent" and percent ~= nil then
    return percent
  end
  local amount = lifepoints and frames.formatAmount(lifepoints)
  if amount ~= nil and percent ~= nil then return amount .. " | " .. percent end
  return amount or percent or ""
end

-- reads: { available, name, lifepoints, lifepointsLabel, prayerValue, prayerLabel }. format is one of
-- frames.LIFEPOINTS, short when nil.
function frames.player(reads, format)
  if not reads.available or reads.lifepoints == nil then return { hidden = true } end
  local model = { hidden = false, name = reads.name or "" }
  local max = labelMax(reads.lifepointsLabel)
  local percent
  if max ~= nil and max > 0 then
    model.fill = clamp01(reads.lifepoints / max)
    percent = percentText(reads.lifepoints, max)
  else
    max = nil
  end
  model.valueText = valueText(format, reads.lifepoints, percent, max)
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
-- format is one of frames.LIFEPOINTS, short when nil.
function frames.target(reads, format)
  if reads.target == nil or reads.target == -1 or reads.lifepointsLabel == "N/A" then return { hidden = true } end
  local model = { hidden = false, name = reads.name or "", debuffs = reads.debuffs }
  local lifepoints = reads.lifepointsLabel and tonumber((reads.lifepointsLabel:gsub(",", "")))
  local percent
  if reads.healthPercent ~= nil then
    model.fill = clamp01(reads.healthPercent / 100)
    percent = percentText(reads.healthPercent, 100)
  end
  model.valueText = valueText(format, lifepoints, percent, nil)
  return model
end

-- reads: { adrenaline = SA_ENERGY in tenths of a percent, spenders = { [varName] = count },
--         lantern = whether a Soulbound lantern is equipped, necromancy = whether a Necromancy weapon is worn }
-- Each spender with stacks gets a row, and every one does while a Necromancy weapon is worn, so the rows and the
-- elements they push stay put between casts.
-- markers: { threshold = percent, ultimate = percent }
function frames.resource(reads, markers)
  if reads.adrenaline == nil then return { hidden = true } end
  local fill = clamp01(reads.adrenaline / 1000)
  local model = {
    hidden = false,
    fill = fill,
    text = percentText(reads.adrenaline, 1000),
    markers = { { at = clamp01(markers.threshold / 100) }, { at = clamp01(markers.ultimate / 100) } },
    spenders = {},
  }
  for _, spender in ipairs(frames.SPENDERS) do
    local count = reads.spenders[spender.var] or 0
    if count > 0 or reads.necromancy then
      local max = reads.lantern and spender.lanternMax or spender.max
      model.spenders[#model.spenders + 1] = { key = spender.key, count = math.min(count, max), max = max }
    end
  end
  return model
end

return frames
