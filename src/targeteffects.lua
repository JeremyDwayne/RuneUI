-- Tracks the debuffs on the player's target from the game's target effect vars, for the target frame.
-- Pure: main.lua feeds it var changes.
local targeteffects = {}

-- The target effect bitfields, in the order the game's target panel fills its debuff slots.
targeteffects.VARS = { "COMBATV2_TARGET_EFFECTS" }
for n = 2, 12 do
  targeteffects.VARS[n] = "COMBATV2_TARGET_EFFECTS_" .. n
end

-- Bits whose debuff sprite is known, each { var, mask, sprite }, by var then mask ascending.
targeteffects.BITS = {
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x20000000, sprite = 14395 }, -- Vulnerability
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x40000000, sprite = 14371 }, -- Enfeeble
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000, sprite = 26104 }, -- Stun Immune
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000000, sprite = 17255 }, -- Corruption Shot
  { var = "COMBATV2_TARGET_EFFECTS_6", mask = 0x80000000, sprite = 26026 }, -- Curse
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x40, sprite = 15037 }, -- Chain
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x80, sprite = 14771 }, -- Smoke Cloud
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x20, sprite = 30098 }, -- Bloated
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x40, sprite = 30212 }, -- Haunted
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x80, sprite = 30100 }, -- Death Mark
}

-- Known bits of each var, keyed by var name.
local bitsOf = {}
for _, name in ipairs(targeteffects.VARS) do
  bitsOf[name] = {}
end
for _, bit in ipairs(targeteffects.BITS) do
  local list = bitsOf[bit.var]
  list[#list + 1] = bit
end

-- A var value as an unsigned 32-bit integer; the game sends the top bit as a negative number.
local function unsigned(value)
  return (math.type(value) == "integer" and value or 0) & 0xFFFFFFFF
end

-- Returns a tracker. onVar takes every var change and seed a function returning a var's value at load.
-- debuffs() returns { sprites, complete }: the sprites of the known set bits in target panel order, and whether
-- every set bit is known. It returns the same table until a target effect var changes.
function targeteffects.tracker()
  local values = {}
  local result = nil

  local tracker = {}

  function tracker.onVar(name, _, new)
    if bitsOf[name] == nil then
      return
    end
    local value = unsigned(new)
    if values[name] ~= value then
      values[name] = value
      result = nil
    end
  end

  function tracker.seed(read)
    for _, name in ipairs(targeteffects.VARS) do
      tracker.onVar(name, nil, read(name))
    end
  end

  function tracker.debuffs()
    if result == nil then
      result = { sprites = {}, complete = true }
      for _, name in ipairs(targeteffects.VARS) do
        local rest = values[name] or 0
        for _, bit in ipairs(bitsOf[name]) do
          if rest & bit.mask ~= 0 then
            result.sprites[#result.sprites + 1] = bit.sprite
            rest = rest & ~bit.mask
          end
        end
        if rest ~= 0 then
          result.complete = false
        end
      end
    end
    return result
  end

  return tracker
end

return targeteffects
