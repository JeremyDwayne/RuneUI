-- Tracks the debuffs on the player's target from the game's target effect vars, for the target frame.
-- Pure: main.lua feeds it var changes.
local targeteffects = {}

-- The target effect bitfields, in the order the game's target panel fills its debuff slots.
targeteffects.VARS = { "COMBATV2_TARGET_EFFECTS" }
for n = 2, 12 do
  targeteffects.VARS[n] = "COMBATV2_TARGET_EFFECTS_" .. n
end

-- Bits whose debuff sprite is known, each { var, mask, sprite, ticks, struct }, by var then mask ascending.
-- ticks is how long the debuff lasts from the tick its bit sets, for the debuffs the player applies and times.
-- struct is the spell whose cast restarts that time while the debuff is on.
targeteffects.BITS = {
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x10000000, sprite = 14391, ticks = 106 }, -- Curse
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x20000000, sprite = 14395, ticks = 102, struct = 14784 }, -- Vulnerability
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x40000000, sprite = 14371, ticks = 102, struct = 14787 }, -- Enfeeble
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000, sprite = 26104 }, -- Stun Immune
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000000, sprite = 17255 }, -- Corruption Shot
  { var = "COMBATV2_TARGET_EFFECTS_6", mask = 0x80000000, sprite = 26026 }, -- the bit named MAGIC_CURSE
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x40, sprite = 15037, ticks = 12 }, -- Chain
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x80, sprite = 14771, ticks = 201, struct = 44912 }, -- Smoke Cloud
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x20, sprite = 30098, ticks = 33 }, -- Bloated
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x40, sprite = 30212, ticks = 50 }, -- Haunted
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x80, sprite = 30100 }, -- Death Mark
}

-- Known bits of each var, keyed by var name, and the bit each spell struct restarts.
local bitsOf = {}
local bitOfStruct = {}
for _, name in ipairs(targeteffects.VARS) do
  bitsOf[name] = {}
end
for _, bit in ipairs(targeteffects.BITS) do
  local list = bitsOf[bit.var]
  list[#list + 1] = bit
  if bit.struct ~= nil then
    bitOfStruct[bit.struct] = bit
  end
end

-- A var value as an unsigned 32-bit integer; the game sends the top bit as a negative number.
local function unsigned(value)
  return (math.type(value) == "integer" and value or 0) & 0xFFFFFFFF
end

-- Returns a tracker. onVar takes every var change, onTick runs once per server tick, and seed takes a function
-- returning a var's value at load. A cast of a bit's struct while the bit is set restarts its time. debuffs()
-- returns { sprites, complete, timers }: the sprites of the known set bits in target panel order, whether every
-- set bit is known, and { [sprite] = { left, full } } in ticks for each timed bit seen setting on the current
-- target whose time has not run out. It returns the same table until a target effect var changes or, while a
-- timer runs, a tick passes.
function targeteffects.tracker()
  local values = {}
  local result = nil
  local tick = 0
  -- The tick each timed bit set, keyed by its BITS entry.
  local setAt = {}

  local tracker = {}

  local function record(name, value)
    if values[name] == value then
      return
    end
    local old = values[name] or 0
    for _, bit in ipairs(bitsOf[name]) do
      if bit.ticks ~= nil and old & bit.mask == 0 and value & bit.mask ~= 0 then
        setAt[bit] = tick
      elseif value & bit.mask == 0 then
        setAt[bit] = nil
      end
    end
    values[name] = value
    result = nil
  end

  function tracker.onVar(name, old, new)
    if name == "COMBATV2_JUST_USED_ABILITY" then
      local bit = bitOfStruct[new]
      if bit ~= nil and (values[bit.var] or 0) & bit.mask ~= 0 then
        setAt[bit] = tick
        result = nil
      end
    elseif name == "NPCTARGET" then
      if old ~= new and next(setAt) ~= nil then
        setAt = {}
        result = nil
      end
    elseif bitsOf[name] ~= nil then
      record(name, unsigned(new))
    end
  end

  -- A bit already set at load has no known start, so seeding records no timers.
  function tracker.seed(read)
    for _, name in ipairs(targeteffects.VARS) do
      values[name] = unsigned(read(name))
    end
    result = nil
  end

  function tracker.onTick()
    tick = tick + 1
    if next(setAt) ~= nil then
      result = nil
    end
  end

  function tracker.debuffs()
    if result == nil then
      result = { sprites = {}, complete = true, timers = {} }
      for _, name in ipairs(targeteffects.VARS) do
        local rest = values[name] or 0
        for _, bit in ipairs(bitsOf[name]) do
          if rest & bit.mask ~= 0 then
            result.sprites[#result.sprites + 1] = bit.sprite
            rest = rest & ~bit.mask
            local start = setAt[bit]
            if start ~= nil and bit.ticks - (tick - start) > 0 then
              result.timers[bit.sprite] = { left = bit.ticks - (tick - start), full = bit.ticks }
            elseif start ~= nil then
              setAt[bit] = nil
            end
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
