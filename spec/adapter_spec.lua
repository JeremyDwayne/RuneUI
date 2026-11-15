_G.log = function() end
_G.var = { VarPlayer = {} }
local adapter = require("src/adapter")

-- The worn inventory as the client returns it: valid reads nil and slots hold ObjType proxies.
local function wearing(...)
  local slots = {}
  for i, name in ipairs({ ... }) do
    slots[i] = { obj = { name = name }, count = 1 }
  end
  slots[#slots + 1] = { obj = { name = "" }, count = 0 }
  _G.Inventory = {
    Find = function()
      return {
        GetSlots = function()
          return slots
        end,
      }
    end,
  }
end

describe("adapter.resourceReads", function()
  it("detects a worn soulbound lantern, augmented or not, rescanning only when worn gear changes", function()
    wearing("Crown of the First Necromancer", "Augmented Soulbound lantern")
    adapter.inventoryChanged({ inv = { id = 94 } })
    assert.is_true(adapter.resourceReads({}).lantern)
    wearing("Crown of the First Necromancer")
    adapter.inventoryChanged({ inv = { id = 93 } })
    assert.is_true(adapter.resourceReads({}).lantern)
    adapter.inventoryChanged({ inv = { id = 94 } })
    assert.is_false(adapter.resourceReads({}).lantern)
  end)
end)

-- Targets NPCTARGET and loads 1490 with the given static components, recording each static ID read.
local function targetPanel(target, statics)
  _G.var = { VarPlayer = { NPCTARGET = { value = target } }, VarClient = {} }
  local reads = {}
  _G.ui = {
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID)
        if interfaceID == 1490 then
          reads[staticID] = true
          return statics[staticID]
        end
      end,
    },
  }
  return reads
end

-- NPCList finding one NPC per uid in npcs, counting lookups.
local function npcList(npcs)
  local list = { lookups = 0 }
  function list.ByUID(uid)
    list.lookups = list.lookups + 1
    return { npcs[uid] }
  end
  _G.NPCList = list
  return list
end

describe("adapter.targetReads", function()
  local INCOMPLETE = { sprites = {}, complete = false }

  it("lists only the debuff slots the panel shows, since expired slots keep their icon while invisible", function()
    npcList({})
    targetPanel(25126, {
      [38] = { spriteID = 30097, visibleGlobal = true },
      [41] = { spriteID = 30212, visibleGlobal = false },
      [44] = { spriteID = 30098, visibleGlobal = true },
      [47] = { spriteID = -1, visibleGlobal = false },
    })
    assert.are.same({ 30097, 30098 }, adapter.targetReads(INCOMPLETE).debuffs)
  end)

  it("takes debuffs from complete target effects without reading the panel's debuff slots", function()
    npcList({})
    local reads = targetPanel(25127, { [38] = { spriteID = 30097, visibleGlobal = true } })
    local effects = { sprites = { 30098, 30100 }, complete = true }
    assert.are.same({ 30098, 30100 }, adapter.targetReads(effects).debuffs)
    for staticID = 38, 71 do
      assert.is_nil(reads[staticID])
    end
  end)

  it("names the target from its entity, looked up once per target", function()
    local list = npcList({ [25128] = { displayName = "Training dummy" } })
    targetPanel(25128, { [21] = { content = "Panel name" } })
    assert.are.equal("Training dummy", adapter.targetReads(INCOMPLETE).name)
    assert.are.equal("Training dummy", adapter.targetReads(INCOMPLETE).name)
    assert.are.equal(1, list.lookups)
  end)

  it("names the target from the panel while no entity is found", function()
    npcList({})
    targetPanel(25129, { [21] = { content = "Panel name" } })
    assert.are.equal("Panel name", adapter.targetReads(INCOMPLETE).name)
  end)
end)

describe("adapter.spriteName", function()
  it("names a sprite by id, and reads nil when the client has no name or raises", function()
    _G.id = {
      Sprite = {
        FromID = function(sprite)
          if sprite == 30212 then
            return "DEBUFF_ICON_NECROMANCY_HAUNTED"
          end
          if sprite == -2 then
            error("bad id")
          end
        end,
      },
    }
    assert.are.equal("DEBUFF_ICON_NECROMANCY_HAUNTED", adapter.spriteName(30212))
    assert.is_nil(adapter.spriteName(30098))
    assert.is_nil(adapter.spriteName(-2))
  end)
end)

describe("adapter.auraReads", function()
  it("reads shown icons with their labels, skipping item icons, hidden slots and slots past an empty run", function()
    -- { sprite, label, label visibleGlobal } per 284 slot from :19. Visibility comes from the label, since
    -- RuneUI hides the icons themselves.
    local slots = {
      [19] = { 30093, "6m", true },
      [20] = { -1, "5m", true },
      [21] = { 18857, "", false },
      [22] = { 14766, "20<br>(5)", true },
      [27] = { 27432, "9", true },
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          local slot = interfaceID == 284 and slots[staticID]
          if not slot then
            return nil
          end
          if dynamicID == 0 then
            return { spriteID = slot[1], visibleGlobal = false }
          end
          return { content = slot[2], visibleGlobal = slot[3] }
        end,
      },
    }
    assert.are.same({
      buffs = { { sprite = 30093, label = "6m" }, { sprite = 14766, label = "20<br>(5)" } },
      debuffs = {},
    }, adapter.auraReads())
  end)
end)

-- Action bars as the client builds them: { [interfaceID] = { [staticID] = component } }, counting label reads.
local function loadBars(bars)
  local stub = { labelReads = 0 }
  _G.ui = {
    Interfaces = {
      GetComponent = function(_, interfaceID, staticID)
        local c = bars[interfaceID] and bars[interfaceID][staticID]
        if c ~= nil and c.content ~= nil then
          stub.labelReads = stub.labelReads + 1
        end
        return c
      end,
    },
  }
  return stub
end

describe("adapter.barSlots", function()
  it("reads each slot's keybind, and that its ability can't be cast while the client dims its icon", function()
    -- Main bar 1430: slot 0 Concentrated Blast on Q, slot 1 Wild Magic dimmed with no keybind.
    loadBars({
      [1430] = {
        [66] = { spriteID = 13309, rgb = 0xffffff },
        [73] = { content = "Q" },
        [79] = { spriteID = 14385, rgb = 0x333333 },
        [86] = { content = "" },
      },
    })
    assert.are.same({ [13309] = { keybind = "Q", usable = true }, [14385] = { usable = false } }, adapter.barSlots())
  end)

  it("keeps the keybind of an ability on two bars from the bar that has one", function()
    -- Concentrated Blast on the main bar's slot 0 with Q, and on action bar 5's slot 0 with no keybind.
    loadBars({
      [1430] = { [66] = { spriteID = 13309, rgb = 0xffffff }, [73] = { content = "Q" } },
      [1673] = { [16] = { spriteID = 13309, rgb = 0xffffff }, [23] = { content = "" } },
    })
    assert.are.equal("Q", adapter.barSlots()[13309].keybind)
  end)

  it("reads a slot's keybind label again only when its icon changes, or every 8 ticks", function()
    local bars = { [1430] = { [66] = { spriteID = 13309, rgb = 0xffffff }, [73] = { content = "Q" } } }
    local stub = loadBars(bars)
    adapter.barSlots()
    stub.labelReads = 0
    bars[1430][73].content = "W"
    assert.are.equal("Q", adapter.barSlots()[13309].keybind)
    assert.are.equal(0, stub.labelReads)
    bars[1430][66].spriteID = 14236
    assert.are.equal("W", adapter.barSlots()[14236].keybind)
    bars[1430][73].content = "E"
    for _ = 1, 8 do
      adapter.barSlots()
    end
    assert.are.equal("E", adapter.barSlots()[14236].keybind)
    assert.are.equal(2, stub.labelReads)
  end)

  it("names the icon in the queued bar and slot from the last read, without reading the client", function()
    -- Main bar 1430: slot 0 Concentrated Blast, slot 1 Wild Magic.
    loadBars({
      [1430] = { [66] = { spriteID = 13309, rgb = 0xffffff }, [79] = { spriteID = 14385, rgb = 0xffffff } },
    })
    adapter.barSlots()
    _G.ui = nil
    assert.are.same({ 13309, 14385 }, { adapter.slotSprite(1003, 1), adapter.slotSprite(1003, 2) })
    assert.is_nil(adapter.slotSprite(1003, 3))
    assert.is_nil(adapter.slotSprite(nil, nil))
    assert.is_nil(adapter.slotSprite(1, 1))
  end)
end)

describe("adapter.iconStruct", function()
  it("reads combat and spell structs with an icon and a name, and skips other structs", function()
    local params = {
      COMBATV2_ABILITY_ICON = { id = 1 },
      COMBATV2_ABILITY_NAME = { id = 2 },
      COMBATV2_ABILITY_INFO = { id = 3 },
    }
    local function struct(configName, values)
      return {
        configName = configName,
        HasParam = function(_, p)
          return values[p.id] ~= nil
        end,
        GetParamValue = function(_, p)
          return values[p.id]
        end,
      }
    end
    local structs = {
      [1] = struct("MAGIC_VULNERABILITY", { 14395, "Vulnerability" }),
      [2] = struct("COMBATV2_STUNNED_DUMMY_ABILITY", { 26103, "Stunned" }),
      [3] = struct("QUEST_REWARD", { 99, "Lamp" }),
    }
    _G.config = {
      Param = params,
      Struct = {
        FromID = function(structID)
          return structs[structID]
        end,
      },
    }
    assert.are.same({ configName = "MAGIC_VULNERABILITY", icon = 14395, name = "Vulnerability" }, adapter.iconStruct(1))
    assert.are.equal("Stunned", adapter.iconStruct(2).name)
    assert.is_nil(adapter.iconStruct(3))
  end)
end)

describe("adapter.auraReads", function()
  it("reads a buff slot that shows an item, such as an overload, as minus the item id", function()
    local slots = {
      [19] = { icon = { spriteID = 30099 }, label = { content = "" } },
      [20] = { icon = { spriteID = -1, associatedObjectID = 49039 }, label = { content = "5m" } },
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          local slot = interfaceID == 284 and slots[staticID]
          if slot then
            return dynamicID == 0 and slot.icon or slot.label
          end
        end,
      },
    }
    assert.are.same({ { sprite = 30099 }, { sprite = -49039, label = "5m" } }, adapter.auraReads().buffs)
  end)
end)

describe("adapter.structInfo", function()
  it("reads a struct's description, or nil when it has none", function()
    local info = { id = 3 }
    local function struct(text)
      return {
        HasParam = function(_, p)
          return p == info and text ~= nil
        end,
        GetParamValue = function()
          return text
        end,
      }
    end
    local structs = { [1] = struct("Swollen."), [2] = struct(nil) }
    local function fromID(structID)
      return structs[structID]
    end
    _G.config = { Param = { COMBATV2_ABILITY_INFO = info }, Struct = { FromID = fromID } }
    assert.are.same({ "Swollen.", nil, nil }, { adapter.structInfo(1), adapter.structInfo(2), adapter.structInfo(9) })
  end)

  it("falls back to the text after the dash in a struct's name when it has no description", function()
    local info = { id = 3 }
    local name = { id = 4 }
    local params = { [name] = "Drenched - Each stack slows you." }
    local struct = {
      HasParam = function(_, p)
        return params[p] ~= nil
      end,
      GetParamValue = function(_, p)
        return params[p]
      end,
    }
    _G.config = {
      Param = { COMBATV2_ABILITY_INFO = info, COMBATV2_ABILITY_NAME = name },
      Struct = {
        FromID = function()
          return struct
        end,
      },
    }
    assert.are.equal("Each stack slows you.", adapter.structInfo(1))
    params[name] = "Stunned"
    assert.is_nil(adapter.structInfo(1))
  end)
end)

describe("adapter.abilityInfo", function()
  it("reads an ability's description by its key, or nil when its struct is missing", function()
    local info = { id = 3 }
    local struct = {
      HasParam = function(_, p)
        return p == info
      end,
      GetParamValue = function()
        return "Inflict searing pain on the target."
      end,
    }
    _G.config = {
      Param = { COMBATV2_ABILITY_INFO = info },
      Struct = setmetatable({ COMBATV2_ABILITY_MAGIC_FINGER_OF_DEATH = struct }, {
        __index = function(_, structName)
          error("no struct " .. structName)
        end,
      }),
    }
    assert.are.equal("Inflict searing pain on the target.", adapter.abilityInfo("MAGIC_FINGER_OF_DEATH"))
    assert.is_nil(adapter.abilityInfo("MAGIC_DRAGON_BREATH"))
  end)
end)

describe("adapter.itemName", function()
  it("names an item by id", function()
    local salve = { name = "Elder overload salve (6)" }
    _G.config =
      { Obj = {
        FromID = function(objID)
          return objID == 49039 and salve or nil
        end,
      } }
    assert.are.same({ "Elder overload salve (6)", nil }, { adapter.itemName(49039), adapter.itemName(1) })
  end)
end)

describe("adapter.groupReads", function()
  -- Interface 1519 with its member list :3 holding the title :0 and each member's row of 23 dynamic children.
  local function groupWindow(shown, title, members)
    local children = { [0] = { content = title } }
    for i, member in ipairs(members) do
      local first = (i - 1) * 23
      children[first + 1] = { content = member.name }
      children[first + 15] = { spriteID = member.rank }
      children[first + 23] = { content = member.lifepoints }
    end
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          if interfaceID ~= 1519 or staticID ~= 3 then
            return nil
          end
          if dynamicID == nil then
            return { visibleGlobal = shown }
          end
          return children[dynamicID]
        end,
      },
    }
  end

  it("reads the title and each member's row in order, stopping at the first row with no name", function()
    groupWindow(true, "Oakhelm's group", {
      { name = "Oakhelm", rank = 25847, lifepoints = "9400/15695" },
      { name = "Mirelle", rank = -1, lifepoints = "0/12000" },
    })
    assert.are.same({
      open = true,
      title = "Oakhelm's group",
      rows = {
        { name = "Oakhelm", rank = 25847, lifepoints = "9400/15695" },
        { name = "Mirelle", lifepoints = "0/12000" },
      },
    }, adapter.groupReads())
  end)

  it("reads an open window with no members as an empty list", function()
    groupWindow(true, nil, {})
    assert.are.same({ open = true, rows = {} }, adapter.groupReads())
  end)

  it("reads a closed or unloaded window as not open, leaving its stale rows unread", function()
    groupWindow(false, "Oakhelm's group", { { name = "Oakhelm", rank = 25847, lifepoints = "9400/15695" } })
    assert.are.same({ open = false }, adapter.groupReads())
    _G.ui = {
      Interfaces = {
        GetComponent = function() end,
      },
    }
    assert.are.same({ open = false }, adapter.groupReads())
  end)
end)

describe("adapter.groupLayout", function()
  -- A shown component at screen x, y sized w by h, with other fields.
  local function at(x, y, w, h, fields)
    local c = { visibleGlobal = true, xyGlobal = { x = x, y = y }, width = w, height = h }
    for k, v in pairs(fields or {}) do
      c[k] = v
    end
    return c
  end

  -- The group window at 100, 200 in the window frame whose content static is content: its base, list area,
  -- set status and hidden invite buttons, selected group tab, size label, Ready button and members' name labels.
  local function groupWindow(content, shown, names)
    local frame = { interfaceID = 1477, staticID = content }
    local statics = {
      [11] = at(104, 220, 257, 231, { parentStatic = { interfaceID = 1519, staticID = 9, parentStatic = frame } }),
      [3] = { visibleGlobal = shown },
      [5] = at(104, 250, 257, 168),
      [20] = at(107, 223, 24, 24),
      [57] = { spriteID = 25853 },
      [19] = { visibleGlobal = false, xyGlobal = { x = 134, y = 223 }, width = 24, height = 24 },
      [51] = { spriteID = 25851 },
      [31] = at(322, 227, 17, 17, { spriteID = 6028 }),
      [29] = at(295, 223, 26, 24, { content = "2/50" }),
      [6] = at(114, 453, 237, 27),
      [44] = { content = "Ready" },
    }
    if not shown then
      for _, c in pairs(statics) do
        c.visibleGlobal = false
      end
    end
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID, _, dynamicID)
          if interfaceID == 1477 then
            local frames = { [523] = at(100, 200, 265, 290), [529] = at(340, 204, 16, 16, { spriteID = 21004 }) }
            return shown and frames[staticID] or nil
          end
          if dynamicID ~= nil then
            return staticID == 3 and names[dynamicID] or nil
          end
          return statics[staticID]
        end,
      },
    }
  end

  it("gives the window's box, a tile per shown button, tab and label, and each row's place", function()
    groupWindow(525, true, { [1] = at(183, 269, 178, 13), [24] = at(183, 307, 178, 13) })
    local layout = adapter.groupLayout(2)
    assert.are.same({ 100, 200, 265, 290, 220 }, { layout.x, layout.y, layout.w, layout.h, layout.top })
    assert.are.same({ 250, 168 }, { layout.listY, layout.listH })
    assert.are.same({
      { x = 107, y = 223, w = 24, h = 24, sprite = 25853 },
      { x = 322, y = 227, w = 17, h = 17, sprite = 6028 },
      { x = 295, y = 223, w = 26, h = 24, text = "2/50", plain = true },
      { x = 114, y = 453, w = 237, h = 27, text = "Ready" },
      { x = 340, y = 204, w = 16, h = 16, sprite = 21004, plain = true },
    }, layout.tiles)
    assert.are.same({ { x = 109, y = 267, w = 247, h = 38 }, { x = 109, y = 305, w = 247, h = 38 } }, layout.rows)
  end)

  it("says whether the window's frame has left a layout's box", function()
    groupWindow(525, true, {})
    local layout = adapter.groupLayout(0)
    assert.is_false(adapter.groupMoved(layout))
    layout.w = 300
    assert.is_true(adapter.groupMoved(layout))
    groupWindow(525, false, {})
    assert.is_false(adapter.groupMoved(layout))
  end)

  it("gives no row places once a row reaches outside the list area", function()
    groupWindow(525, true, { [1] = at(183, 269, 178, 13), [24] = at(183, 400, 178, 13) })
    assert.is_nil(adapter.groupLayout(2).rows)
  end)

  it("reads a closed window as not open, and one docked into another window or unloaded as nil", function()
    groupWindow(525, false, {})
    assert.are.same({ open = false }, adapter.groupLayout(0))
    groupWindow(493, true, {})
    assert.is_nil(adapter.groupLayout(0))
    _G.ui = {
      Interfaces = {
        GetComponent = function() end,
      },
    }
    assert.is_nil(adapter.groupLayout(0))
  end)
end)

describe("adapter.nearbyPlayers", function()
  it("lists every player in view with its name and uid, and gives a player entity event's player", function()
    local oakhelm, unnamed = { displayName = "Oakhelm", uid = 7 }, { uid = 8 }
    _G.PlayerList = {
      All = function()
        return { oakhelm, unnamed }
      end,
    }
    assert.are.same(
      { { entity = oakhelm, name = "Oakhelm", uid = 7 }, { entity = unnamed, uid = 8 } },
      adapter.nearbyPlayers()
    )
    local brunt = { displayName = "Brunt", uid = 9 }
    assert.are.same({ entity = brunt, name = "Brunt", uid = 9 }, adapter.entityPlayer({ playerEntity = brunt }))
    _G.PlayerList = nil
    assert.are.same({}, adapter.nearbyPlayers())
  end)
end)

describe("adapter.headPosition", function()
  it("gives the screen point 1024 units over a player, and nil for one that cannot be placed", function()
    _G.Vector3 = {
      new = function(x, y, z)
        return { x = x, y = y, z = z }
      end,
    }
    _G.ScreenConvert = {
      Vector3ToScreen = function(at)
        return at.onScreen and { x = at.x, y = at.y } or nil
      end,
    }
    -- A position whose sum with the lift is the point given to the client.
    local function standing(x, y, onScreen)
      return setmetatable({}, {
        __add = function(_, lift)
          return { x = x, y = y + lift.y, onScreen = onScreen }
        end,
      })
    end
    assert.are.same({ 640, 1324 }, { adapter.headPosition({ position = standing(640, 300, true) }) })
    assert.is_nil(adapter.headPosition({ position = standing(640, 300, false) }))
    assert.is_nil(adapter.headPosition({}))
  end)
end)

describe("adapter.relationNames", function()
  it("reads each game list's names without their tags, and an unloaded list as empty", function()
    local function list(...)
      local children = {}
      for i, content in ipairs({ ... }) do
        children[i] = { content = content }
      end
      return {
        IterateDynamicComponents = function(_, fn)
          for _, child in ipairs(children) do
            fn(child)
          end
        end,
      }
    end
    local lists = {
      ["550:7"] = list("Oakhelm", "<img=3><col=ffffff>Iron Oak", ""),
      ["1110:83"] = list("Brunt"),
      ["1110:38"] = list("Ysolde"),
    }
    _G.ui = {
      Interfaces = {
        GetComponent = function(_, interfaceID, staticID)
          return lists[interfaceID .. ":" .. staticID]
        end,
      },
    }
    assert.are.same({
      friend = { "Oakhelm", "Iron Oak" },
      friendsChat = {},
      clan = { "Brunt" },
      guest = { "Ysolde" },
    }, adapter.relationNames())
  end)
end)
