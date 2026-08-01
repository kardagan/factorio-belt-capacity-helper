--- Discovery of belt tiers from the runtime prototype table.
--- Nothing here is hardcoded: every mod that declares a transport-belt shows up.

local belts = {}

--- Items per tile on a belt lane. This is a hard game constant (4 items per
--- tile per lane for normal-sized items), not a prototype value.
local ITEMS_PER_TILE_PER_LANE = 4

--- How many items ride in a single belt slot for `item_name`.
---
--- `force.belt_stack_size_bonus` is the researched bonus (0 with no stacking
--- tech, 1 after the first level, and so on), so a slot holds 1 + bonus. An item
--- can never stack past its own stack size: with stack_size 1 it stays flat on
--- the belt no matter how much stacking has been researched.
function belts.stack_height(force, item_name)
  local bonus = force and force.belt_stack_size_bonus or 0
  local proto = prototypes.item[item_name]
  local cap = proto and proto.stack_size or 1
  return math.max(1, math.min(1 + bonus, cap))
end

--- Cached list, rebuilt on load / on configuration changed.
local cache = nil

--- Throughput of one lane of a belt, in items per second.
--- `belt_speed` is in tiles per tick for the whole belt, so a lane carries
--- belt_speed * 60 ticks * 4 items/tile.
local function lane_throughput(proto)
  return proto.belt_speed * 60 * ITEMS_PER_TILE_PER_LANE
end

--- Is this belt something the player would actually recognise and build?
--- Filters out hidden/technical belts some overhaul mods declare.
local function is_visible(proto)
  if proto.hidden then return false end
  -- A belt the player can build always has a matching item that places it.
  local items = proto.items_to_place_this
  if not items or #items == 0 then return false end
  local item_proto = prototypes.item[items[1].name]
  if not item_proto or item_proto.hidden then return false end
  return true
end

--- Build the sorted belt list. Called lazily, cached until config changes.
local function build()
  local list = {}
  for name, proto in pairs(prototypes.get_entity_filtered({
    { filter = "type", type = "transport-belt" },
  })) do
    if is_visible(proto) then
      local item = proto.items_to_place_this[1].name
      list[#list + 1] = {
        name = name,
        item = item,
        localised_name = proto.localised_name,
        lane = lane_throughput(proto),
      }
    end
  end

  -- Slowest first: the table reads bottom-up as you tech up.
  table.sort(list, function(a, b)
    if a.lane ~= b.lane then return a.lane < b.lane end
    return a.name < b.name
  end)

  return list
end

--- All visible belt tiers, slowest first.
function belts.all()
  if not cache then cache = build() end
  return cache
end

--- Belt tiers this force has actually unlocked, slowest first.
--- Falls back to everything if nothing is unlocked yet (very early game).
---
--- Walks the force's recipes ONCE and collects every item they produce, instead
--- of scanning all recipes per belt. With overhaul mods that is thousands of
--- recipes, and this runs on every window open.
function belts.unlocked_for(force)
  local all = belts.all()

  local wanted = {}
  for _, belt in ipairs(all) do
    wanted[belt.item] = false
  end

  for _, recipe in pairs(force.recipes) do
    if recipe.enabled and not recipe.hidden then
      for _, product in ipairs(recipe.products) do
        if product.type == "item" and wanted[product.name] == false then
          wanted[product.name] = true
        end
      end
    end
  end

  local out = {}
  for _, belt in ipairs(all) do
    if wanted[belt.item] then out[#out + 1] = belt end
  end

  if #out == 0 then return all end
  return out
end

function belts.invalidate()
  cache = nil
end

return belts
