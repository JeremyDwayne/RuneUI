-- Tracks the debuffs on the player's target from the game's target effect vars, and times the ones whose length
-- is known, for the target frame. It remembers each target's running timers, so swapping away and back keeps
-- them. Pure: main.lua feeds it var changes, server ticks, and the target and debuffs shown.
local targeteffects = {}

-- The target effect bitfields, in the order the game's target panel fills its debuff slots.
targeteffects.VARS = { "COMBATV2_TARGET_EFFECTS" }
for n = 2, 12 do
  targeteffects.VARS[n] = "COMBATV2_TARGET_EFFECTS_" .. n
end

-- Bits whose debuff sprite is known, each { var, mask, sprite }, by var then mask ascending.
targeteffects.BITS = {
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x10000000, sprite = 14391 }, -- Curse
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x20000000, sprite = 14395 }, -- Vulnerability
  { var = "COMBATV2_TARGET_EFFECTS", mask = 0x40000000, sprite = 14371 }, -- Enfeeble
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000, sprite = 26104 }, -- Stun Immune
  { var = "COMBATV2_TARGET_EFFECTS_5", mask = 0x80000000, sprite = 17255 }, -- Corruption Shot
  { var = "COMBATV2_TARGET_EFFECTS_6", mask = 0x80000000, sprite = 26026 }, -- the bit named MAGIC_CURSE
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x40, sprite = 15037 }, -- Chain
  { var = "COMBATV2_TARGET_EFFECTS_8", mask = 0x80, sprite = 14771 }, -- Smoke Cloud
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x20, sprite = 30098 }, -- Bloated
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x40, sprite = 30212 }, -- Haunted
  { var = "COMBATV2_TARGET_EFFECTS_11", mask = 0x80, sprite = 30100 }, -- Death Mark
}

-- A debuff one ability applies for ticks, and whose use again restarts it.
local function one(cause, ticks)
  return { ticks = ticks, causes = { [cause] = ticks } }
end

-- Target debuff lengths in ticks by sprite. ticks is the length when no cause is known. causes gives the length
-- each inflicting ability or spell applies, by name, and a use of one while the debuff is on restarts it, unless
-- keep names it. Debuffs whose length varies with gear, renews on plain hits, has no end, or is unsettled have
-- no entry and show no time.
targeteffects.LENGTHS = {
  [14392] = { -- Bound
    causes = {
      Bind = 20,
      Snare = 30,
      Entangle = 40,
      Backhand = 3,
      Impact = 3,
      ["Binding Shot"] = 16,
      Barge = 11,
      ["Greater Barge"] = 11,
      Flurry = 6,
      ["Greater Flurry"] = 6,
      Asphyxiate = 6,
      ["Rapid Fire"] = 10,
      ["Soul Strike"] = 5,
    },
    keep = { Bind = true, Snare = true, Entangle = true },
  },
  [26103] = { -- Stunned
    causes = {
      Backhand = 3,
      Impact = 3,
      ["Binding Shot"] = 2,
      Flurry = 6,
      ["Greater Flurry"] = 6,
      Asphyxiate = 6,
      ["Soul Strike"] = 5,
    },
  },
  [14389] = { -- Confuse
    causes = { Confuse = 100, ["Smoke Rush"] = 17, ["Smoke Burst"] = 17, ["Smoke Blitz"] = 17, ["Smoke Barrage"] = 17 },
  },
  [14390] = { -- Weaken
    causes = {
      Weaken = 100,
      ["Shadow Rush"] = 17,
      ["Shadow Burst"] = 17,
      ["Shadow Blitz"] = 17,
      ["Shadow Barrage"] = 17,
    },
  },
  [9228] = { causes = { Backstab = 100, Obliterate = 100 } }, -- Base hit chance increased
  [23401] = one("Combust", 30),
  [19226] = one("Corruption Blast", 10),
  [14391] = one("Curse", 100),
  [14371] = one("Enfeeble", 100),
  [15037] = { ticks = 10, causes = { Chain = 10, ["Greater Chain"] = 10 } },
  [14771] = one("Smoke Cloud", 200),
  [14377] = one("Stagger", 100),
  [14395] = one("Vulnerability", 100),
  [14266] = one("Pulverise", 50),
  [30098] = one("Bloat", 33), -- Bloated
  [30100] = one("Invoke Death", 1000), -- Death Mark
  [17255] = one("Corruption Shot", 10),
  [30372] = { ticks = 18 }, -- Soulfire
}

-- Ticks after a debuff shows within which the ability named as just used is the one that applied it. A spell's
-- name arrives a tick after its debuff.
local CAUSE_WINDOW = 2

-- Ticks after a target change within which a debuff the tracker remembers on that target takes its remembered
-- timer when it shows, so a debuff var arriving after the target changes still finds it.
local RECALL_WINDOW = 2

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

-- Returns a tracker. onVar takes every var change, seed takes a function returning a var's value at load, and
-- debuffs() returns { sprites, complete }: the sprites of the known set bits in target panel order and whether
-- every set bit is known, the same table until a target effect var changes. Each server tick, onTick(nameOf)
-- runs first, with nameOf(struct) returning { name } for the struct of a just-used ability, read once per use,
-- then observe(target, sprites) takes the NPCTARGET read that tick and the debuffs the target frame shows.
-- timers() returns { [sprite] = { left, full } } in ticks for each timed debuff shown since it was applied, the
-- same table until a tick passes with one running or the shown debuffs change. A debuff shown at load or when
-- the target changes may have been on already, so it shows no time unless the ability just used applies it or
-- the tracker remembers its timer on that target. A remembered timer counts on while the target is not shown,
-- and only debuffs seen on the target are known: one applied or renewed by anyone while the player looks at
-- another target keeps the old timer.
function targeteffects.tracker()
  local values = {}
  local result = nil
  local tick = 0
  -- Shown debuffs by sprite as { start, ticks }: the tick each showed and its length, nil while untimed.
  local shown = {}
  local count = 0
  -- Whether the next observe sees newly applied debuffs, rather than ones already on.
  local primed = false
  -- The struct of a just-used ability not yet named, and the last name read with its tick.
  local pending = nil
  local lastName, lastTick = nil, nil
  local timers = nil
  local running = false
  -- The target the shown debuffs are on, the running timers of the targets left by target as { [sprite] = entry },
  -- and the timers remembered on the current target with the tick it was taken.
  local target = nil
  local remembered = {}
  local recalled = nil
  local recalledAt = 0

  local tracker = {}

  function tracker.onVar(name, _, new)
    if name == "COMBATV2_JUST_USED_ABILITY" then
      pending = new
    elseif bitsOf[name] ~= nil then
      local value = unsigned(new)
      if values[name] ~= value then
        values[name] = value
        result = nil
      end
    end
  end

  function tracker.seed(read)
    for _, name in ipairs(targeteffects.VARS) do
      values[name] = unsigned(read(name))
    end
    result = nil
  end

  -- Applies a use of the ability called name to the debuffs shown: it sets the length of one it just applied,
  -- and restarts one already on, unless it keeps it.
  local function used(name)
    for sprite, entry in pairs(shown) do
      local def = targeteffects.LENGTHS[sprite]
      local ticks = def and def.causes and def.causes[name]
      if ticks ~= nil then
        if tick - entry.start <= CAUSE_WINDOW then
          entry.ticks = ticks
        elseif not (def.keep and def.keep[name]) then
          entry.start = tick
          entry.ticks = ticks
        end
        timers = nil
      end
    end
  end

  function tracker.onTick(nameOf)
    tick = tick + 1
    if running then
      timers = nil
    end
    if pending ~= nil then
      local found = nameOf(pending)
      pending = nil
      if found ~= nil and found.name ~= nil then
        lastName, lastTick = found.name, tick
        used(found.name)
      end
    end
  end

  -- Whether entry's timer has time left.
  local function hasTime(entry)
    return entry.ticks ~= nil and entry.ticks - (tick - entry.start) > 0
  end

  -- Remembers the shown debuffs' running timers on the target being left, and forgets each target whose timers
  -- have all run out.
  local function leave()
    for uid, entries in pairs(remembered) do
      for sprite, entry in pairs(entries) do
        if not hasTime(entry) then
          entries[sprite] = nil
        end
      end
      if next(entries) == nil then
        remembered[uid] = nil
      end
    end
    local entries = nil
    for sprite, entry in pairs(shown) do
      if hasTime(entry) then
        entries = entries or {}
        entries[sprite] = entry
      end
    end
    -- A remembered timer whose debuff has not shown yet since the target came back stays remembered.
    for sprite, entry in pairs(recalled or {}) do
      if hasTime(entry) then
        entries = entries or {}
        entries[sprite] = entries[sprite] or entry
      end
    end
    if target ~= nil and entries ~= nil then
      remembered[target] = entries
    end
  end

  -- A newly shown debuff's entry. Its length comes from the ability just used when that applies it, or else its
  -- remembered timer on this target, or else its own, except right after load or a target change, when it may
  -- have been on already.
  local function applied(sprite)
    local def = targeteffects.LENGTHS[sprite]
    local ticks = nil
    if def ~= nil and lastName ~= nil and tick - lastTick <= CAUSE_WINDOW and def.causes then
      ticks = def.causes[lastName]
    end
    if ticks == nil and recalled ~= nil and recalled[sprite] ~= nil then
      local entry = recalled[sprite]
      recalled[sprite] = nil
      if hasTime(entry) then
        return entry
      end
    end
    if ticks == nil and def ~= nil and primed then
      ticks = def.ticks
    end
    return { start = tick, ticks = ticks }
  end

  function tracker.observe(uid, sprites)
    if uid ~= target then
      leave()
      target = uid
      recalled = remembered[uid]
      remembered[uid] = nil
      recalledAt = tick
      shown = {}
      count = 0
      primed = false
      timers = nil
    elseif recalled ~= nil and tick - recalledAt > RECALL_WINDOW then
      recalled = nil
    end
    local same = #sprites == count
    for _, sprite in ipairs(sprites) do
      if shown[sprite] == nil then
        same = false
      end
    end
    if not same then
      local now = {}
      for _, sprite in ipairs(sprites) do
        if shown[sprite] == nil then
          now[sprite] = applied(sprite)
        else
          now[sprite] = shown[sprite]
        end
      end
      shown = now
      count = #sprites
      timers = nil
    end
    primed = true
  end

  function tracker.timers()
    if timers == nil then
      timers = {}
      running = false
      for sprite, entry in pairs(shown) do
        if entry.ticks ~= nil then
          local left = entry.ticks - (tick - entry.start)
          if left > 0 then
            timers[sprite] = { left = left, full = entry.ticks }
            running = true
          else
            entry.ticks = nil
          end
        end
      end
    end
    return timers
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
