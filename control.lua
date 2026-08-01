local belts = require("scripts.belts")
local gui = require("scripts.gui")
local rates = require("scripts.rates")

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function init_player(index)
  storage.players[index] = storage.players[index] or { lanes = {} }
  storage.players[index].lanes = storage.players[index].lanes or {}
end

local function init_storage()
  storage.players = storage.players or {}
  for index in pairs(game.players) do
    init_player(index)
  end
end

script.on_init(function()
  init_storage()
end)

script.on_configuration_changed(function()
  init_storage()
  belts.invalidate()
  -- Belt list or recipes may have changed under us: close every open window.
  for _, player in pairs(game.players) do
    gui.destroy(player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  init_player(event.player_index)
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.players[event.player_index] = nil
end)

--------------------------------------------------------------------------------
-- Opening / closing
--------------------------------------------------------------------------------

--- The machine the player currently has open, if it is one we support.
---
--- Three sources, in order of intent:
---   1. the entity whose GUI is open,
---   2. the entity we already track (our own window has focus, so player.opened
---      points at our frame rather than the machine),
---   3. whatever is under the cursor.
local function opened_machine(player)
  local opened = player.opened
  -- API objects are userdata, so `type(opened) == "table"` is always false here.
  -- Check object_name instead: player.opened can also be an equipment grid or an
  -- inventory, and reading .type on those would error.
  if opened and opened.object_name == "LuaEntity" then
    if rates.is_supported(opened) then return opened end
  end

  local pdata = storage.players[player.index]
  if pdata and pdata.open_entity and pdata.open_entity.valid then
    if rates.is_supported(pdata.open_entity) then return pdata.open_entity end
  end

  if rates.is_supported(player.selected) then return player.selected end
  return nil
end

script.on_event("bch-toggle-window", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  if gui.is_open(player) then
    gui.destroy(player)
    return
  end

  local entity = opened_machine(player)
  if not entity then
    -- print, not flying text: flying text renders in the world, behind an open
    -- GUI, so the player would get no feedback at all in the common case.
    player.print({ "bch.no-machine" })
    return
  end

  gui.open(player, entity)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "bch-toggle-window" then return end
  local player = game.get_player(event.player_index)
  if not player then return end

  if gui.is_open(player) then
    gui.destroy(player)
    return
  end

  local entity = opened_machine(player)
  if not entity then
    -- print, not flying text: flying text renders in the world, behind an open
    -- GUI, so the player would get no feedback at all in the common case.
    player.print({ "bch.no-machine" })
    return
  end

  gui.open(player, entity)
end)

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not player.mod_settings["bch-auto-open"].value then return end
  if event.gui_type ~= defines.gui_type.entity then return end
  if not rates.is_supported(event.entity) then return end
  gui.open(player, event.entity)
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  -- Our own window closed (Esc / E).
  if event.element and event.element.valid and event.element.name == "bch-root" then
    gui.destroy(player)
    return
  end

  -- The machine window closed: our numbers no longer refer to anything visible.
  if event.gui_type == defines.gui_type.entity then
    local pdata = storage.players[player.index]
    local tracked = pdata and pdata.open_entity
    if tracked and tracked.valid and event.entity and event.entity.valid
        and event.entity.unit_number == tracked.unit_number then
      gui.destroy(player)
    end
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  gui.on_click(player, event.element)
end)

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

--- /bch-debug — report what the API actually returns for the machine you have
--- open or selected. Useful when the window refuses to appear.
commands.add_command("bch-debug", { "bch.debug-help" }, function(command)
  local player = game.get_player(command.player_index)
  if not player then return end

  local function say(msg) player.print(msg) end

  say("--- Belt Capacity Helper ---")

  local opened = player.opened
  -- Factorio API objects are userdata, not tables: read object_name directly.
  say("player.opened      : " .. tostring(opened and opened.object_name or "nil"))
  say("player.opened_gui_type : " .. tostring(player.opened_gui_type))
  say("player.selected    : " ..
    (player.selected and (player.selected.name .. " (" .. player.selected.type .. ")") or "nil"))

  local entity = nil
  if opened and opened.object_name == "LuaEntity" then
    entity = opened
  elseif player.selected then
    entity = player.selected
  end

  if not entity then
    say("No entity found from either source.")
    return
  end

  say("entity             : " .. entity.name .. "  type=" .. entity.type)
  say("supported by mod   : " .. tostring(rates.is_supported(entity)))

  if not rates.is_supported(entity) then
    say("-> this entity type is not in the supported list.")
    return
  end

  local recipe = entity.get_recipe()
  say("get_recipe()       : " .. (recipe and recipe.name or "nil"))
  say("crafting_speed     : " .. tostring(entity.crafting_speed))
  say("productivity_bonus : " .. tostring(entity.productivity_bonus))
  if recipe then
    say("recipe.energy      : " .. tostring(recipe.energy))
    say("ingredients        : " .. #recipe.ingredients)
    say("products           : " .. #recipe.products)
  end

  local data = rates.for_entity(entity)
  say("rates.for_entity   : " .. (data and "ok" or "nil"))

  say("belt_stack_size_bonus : " .. tostring(player.force.belt_stack_size_bonus))

  local all = belts.all()
  say("belts discovered   : " .. #all)
  local unlocked = belts.unlocked_for(player.force)
  say("belts unlocked     : " .. #unlocked)
  for i, b in ipairs(unlocked) do
    if i <= 12 then
      say(string.format("  %s  %.1f items/s per lane", b.name, b.lane))
    end
  end
end)

--------------------------------------------------------------------------------
-- Keep the numbers honest
--------------------------------------------------------------------------------

--- Anything that can change the effective rate of the tracked machine.
local function refresh_if_tracking(player_index, entity)
  local player = game.get_player(player_index)
  if not player or not gui.is_open(player) then return end
  local pdata = storage.players[player.index]
  if not pdata or not pdata.open_entity then return end
  if entity and entity ~= pdata.open_entity then return end
  -- A recipe change alters the columns themselves, so rebuild rather than refresh.
  gui.open(player, pdata.open_entity)
end

script.on_event(defines.events.on_gui_elem_changed, function(event)
  -- Recipe picker inside the machine window.
  refresh_if_tracking(event.player_index, nil)
end)

script.on_event(defines.events.on_player_main_inventory_changed, function() end)

--- Modules inserted / removed: the machine's crafting_speed changed.
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local dest = event.destination
  if not (dest and dest.valid and rates.is_supported(dest)) then return end
  for _, player in pairs(game.players) do
    local pdata = storage.players[player.index]
    local tracked = pdata and pdata.open_entity
    if tracked and tracked.valid and tracked.unit_number == dest.unit_number then
      gui.open(player, dest)
    end
  end
end)

--- Cheap safety net: every second, verify the tracked entity is still valid and
--- its rates still match what we drew. Covers module changes, beacons built or
--- removed nearby, and research finishing.
script.on_nth_tick(60, function()
  for _, player in pairs(game.players) do
    if gui.is_open(player) then
      local pdata = storage.players[player.index]
      local entity = pdata and pdata.open_entity
      if not (entity and entity.valid) then
        gui.destroy(player)
      else
        local data = rates.for_entity(entity)
        if not data then
          gui.destroy(player)
        elseif data.recipe.name ~= pdata.refs.recipe_name then
          gui.open(player, entity)
        else
          gui.refresh_values(player)
        end
      end
    end
  end
end)
