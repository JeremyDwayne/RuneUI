-- Names over players' heads: one label per player in view, moved on each rendered frame to the point over that
-- player's head. A name is coloured when the game's own lists show the player as a friend, in the player's
-- clan chat, in their friends chat or a guest in their clan chat, in the colour the player gave that chat in
-- the game's settings when it reads. Labels take no clicks.
local nameplates = {}

local draw = require("src/draw")
local party = require("src/party")

local set = draw.set

-- The relations a name can show, first match first, and each one's colour when the game's own does not read.
nameplates.KINDS = { "friend", "clan", "friendsChat", "guest" }
nameplates.COLOURS = { friend = 0xffe14d, clan = 0xff8a1f, friendsChat = 0x5cc8ff, guest = 0xff9ec7 }
-- The most players named at once, so a crowd cannot fill the component ids every plugin on the layer shares.
nameplates.MAX = 500
local W = 160
local H = 14

-- The names on root, hidden until setShown(true). deps: { position = src/adapter's headPosition, valid =
-- src/adapter's entityValid }. Returns { add(player), remove(uid), prune(), setRelations(names, colours),
-- setSelf(name), setShown(on), frame(), destroy() }: add takes src/adapter's { entity, name, uid } as a player
-- enters view, and remove drops the player with that uid as they leave, returning their name, or nil when it
-- holds none. prune drops every player whose entity has gone and returns their names, for a leaving player whose
-- uid did not read. setRelations takes src/adapter's relationNames and chatColours, setSelf the player's own
-- name, which gets no label, and frame runs on every rendered frame, reading nothing while hidden. A label is
-- built the first time its player is on screen and reused once they leave.
function nameplates.create(root, deps)
  local layer = draw.new(ui.Layer, root)
  local width, height = tonumber(root.width) or 4096, tonumber(root.height) or 4096
  draw.size(layer, width, height)
  set(layer, "hidden", true)

  local n = {}
  local plates = {}
  local byUID = {}
  local spare = {}
  -- The relation of each listed name, by party.key.
  local kinds = {}
  local colours = nameplates.COLOURS
  local selfKey = nil
  local shown = false

  function n.add(player)
    if player.name == nil or player.uid == nil then
      return
    end
    local plate = byUID[player.uid]
    if plate == nil then
      if #plates >= nameplates.MAX then
        return
      end
      plate = { uid = player.uid, index = #plates + 1 }
      plates[plate.index] = plate
      byUID[player.uid] = plate
    end
    -- A player the client adds again comes as a new entity.
    plate.entity, plate.name, plate.key, plate.styled = player.entity, player.name, party.key(player.name), false
  end

  function n.remove(uid)
    local plate = uid ~= nil and byUID[uid]
    if not plate then
      return nil
    end
    byUID[uid] = nil
    local last = table.remove(plates)
    if last ~= plate then
      plates[plate.index] = last
      last.index = plate.index
    end
    if plate.label ~= nil then
      set(plate.label, "hidden", true)
      spare[#spare + 1] = plate.label
    end
    return plate.name
  end

  function n.prune()
    local gone = {}
    for i = #plates, 1, -1 do
      local plate = plates[i]
      if not deps.valid(plate.entity) then
        gone[#gone + 1] = n.remove(plate.uid)
      end
    end
    return gone
  end

  function n.setRelations(names, chatColours)
    colours = chatColours or nameplates.COLOURS
    kinds = {}
    for i = #nameplates.KINDS, 1, -1 do
      local kind = nameplates.KINDS[i]
      for _, name in ipairs(names[kind] or {}) do
        kinds[party.key(name)] = kind
      end
    end
    for _, plate in ipairs(plates) do
      plate.styled = false
    end
  end

  function n.setSelf(name)
    selfKey = name and party.key(name)
  end

  function n.setShown(on)
    shown = on
    set(layer, "hidden", not on)
  end

  function n.frame()
    if not shown then
      return
    end
    for _, plate in ipairs(plates) do
      local x, y
      if plate.key ~= selfKey then
        x, y = deps.position(plate.entity)
      end
      if x ~= nil then
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
      end
      local visible = x ~= nil and x >= 0 and x <= width and y >= 0 and y <= height
      local label = plate.label
      if visible and label == nil then
        label = table.remove(spare)
          or draw.text(layer, id.Font.NOTO_SANS_11PT_BOLD_OUTLINE, ui.AlignMode.CENTRE, 0, 0, W, H)
        set(label, "isShadowed", false)
        plate.label = label
        plate.styled = false
      end
      if label ~= nil then
        set(label, "hidden", not visible)
        if visible then
          if not plate.styled then
            plate.styled = true
            set(label, "content", plate.name)
            local kind = kinds[plate.key]
            set(label, "rgb", kind and (colours[kind] or nameplates.COLOURS[kind]) or draw.COLOURS.text)
          end
          draw.pos(label, x - W // 2, y - H)
        end
      end
    end
  end

  function n.destroy()
    layer:Destroy()
  end

  return n
end

return nameplates
