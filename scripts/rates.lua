--- Per-machine consumption / production rates for the machine the player has open.
---
--- Everything comes from the live entity: `crafting_speed` already includes
--- modules, beacons, quality and the machine tier, and `productivity_bonus`
--- already includes module + research productivity. We never recompute any of it.

local rates = {}

--- Crafting machines we can read a recipe from.
local SUPPORTED_TYPES = {
  ["assembling-machine"] = true,
  ["furnace"] = true,
  ["rocket-silo"] = true,
}

function rates.is_supported(entity)
  return entity and entity.valid and SUPPORTED_TYPES[entity.type] or false
end

--- Read the recipe currently set on the entity.
--- Furnaces have no player-set recipe: they report whatever they last smelted,
--- and nil until they have smelted anything at all.
--- In 2.0 this also returns the recipe quality as a second value, which we
--- deliberately ignore — ingredient amounts do not vary with product quality.
local function current_recipe(entity)
  return entity.get_recipe()
end

--- Rates for one machine, in units per second.
--- Returns nil when the machine has no recipe set yet.
---
--- Result shape:
---   {
---     recipe = LuaRecipe,
---     crafts_per_second = number,
---     productivity = number,          -- 0.4 means +40%
---     ingredients = { { name, type, amount, per_second, localised_name }, ... },
---     products    = { { name, type, amount, per_second, localised_name }, ... },
---   }
function rates.for_entity(entity)
  if not rates.is_supported(entity) then return nil end

  local recipe = current_recipe(entity)
  if not recipe then return nil end

  -- crafting_speed is the final effective speed of THIS entity.
  local speed = entity.crafting_speed
  local energy = recipe.energy -- seconds per craft at speed 1
  if not energy or energy <= 0 or not speed or speed <= 0 then return nil end

  local crafts_per_second = speed / energy
  local productivity = entity.productivity_bonus or 0

  local result = {
    recipe = recipe,
    crafts_per_second = crafts_per_second,
    speed = speed,
    -- Both bonuses come straight from the entity and already include force
    -- research, beacons and modules (per the API docs), so they are display-only
    -- here: `crafting_speed` above has the speed bonus baked in already.
    speed_bonus = entity.speed_bonus or 0,
    quality = entity.quality and entity.quality.name or nil,
    productivity = productivity,
    ingredients = {},
    products = {},
  }

  for _, ing in ipairs(recipe.ingredients) do
    -- Productivity does NOT reduce ingredient consumption; it adds free output.
    result.ingredients[#result.ingredients + 1] = {
      name = ing.name,
      type = ing.type,
      amount = ing.amount,
      per_second = ing.amount * crafts_per_second,
    }
  end

  for _, prod in ipairs(recipe.products) do
    -- Expected yield per craft, honouring probability and amount ranges.
    local amount = prod.amount
    if not amount then
      -- amount_min / amount_max range: the expected value is the average.
      amount = ((prod.amount_min or 0) + (prod.amount_max or 0)) / 2
    end
    amount = amount * (prod.probability or 1)

    -- Some products are excluded from the productivity bonus (recycling gives
    -- back what you put in, so productivity must not mint free items there).
    -- `ignored_by_productivity` is the amount per craft that gets no bonus.
    local ignored = math.min(prod.ignored_by_productivity or 0, amount)
    local boostable = amount - ignored
    local per_second = (ignored + boostable * (1 + productivity)) * crafts_per_second

    if per_second > 0 then
      result.products[#result.products + 1] = {
        name = prod.name,
        type = prod.type,
        amount = amount,
        per_second = per_second,
      }
    end
  end

  return result
end

--- Split a rate list into solids (belt-able) and fluids.
function rates.split(list)
  local solids, fluids = {}, {}
  for _, entry in ipairs(list) do
    if entry.type == "fluid" then
      fluids[#fluids + 1] = entry
    else
      solids[#solids + 1] = entry
    end
  end
  return solids, fluids
end

--- How many machines `lanes` lanes of `belt` can feed, given per-machine demand.
---
--- `stack` is how many items ride in one belt slot (1 without belt stacking
--- research). It multiplies throughput directly: a belt moving the same number
--- of slots per second carries `stack` times as many items.
function rates.machines_fed(belt, lanes, per_second, stack)
  if per_second <= 0 then return math.huge end
  return (belt.lane * lanes * (stack or 1)) / per_second
end

return rates
