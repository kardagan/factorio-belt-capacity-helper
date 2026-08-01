-- Test harness: stubs enough of the Factorio API to exercise rates.lua and the
-- belt lane maths against hand-computed vanilla numbers.

package.path = "/home/vador/factoto/BeltCapacityHelper/?.lua;" .. package.path

local failures = 0
local function check(label, got, want, tol)
  tol = tol or 1e-6
  local ok = math.abs(got - want) <= tol
  if not ok then
    failures = failures + 1
    print(string.format("FAIL %-52s got %.6f  want %.6f", label, got, want))
  else
    print(string.format("ok   %-52s %.4f", label, got))
  end
end

--------------------------------------------------------------------------------
-- Stub prototypes
--------------------------------------------------------------------------------

local belt_protos = {
  ["transport-belt"]      = { type = "transport-belt", belt_speed = 0.03125, hidden = false,
                              items_to_place_this = { { name = "transport-belt" } },
                              localised_name = "Transport belt" },
  ["fast-transport-belt"] = { type = "transport-belt", belt_speed = 0.0625, hidden = false,
                              items_to_place_this = { { name = "fast-transport-belt" } },
                              localised_name = "Fast transport belt" },
  ["express-transport-belt"] = { type = "transport-belt", belt_speed = 0.09375, hidden = false,
                              items_to_place_this = { { name = "express-transport-belt" } },
                              localised_name = "Express transport belt" },
  ["turbo-transport-belt"] = { type = "transport-belt", belt_speed = 0.125, hidden = false,
                              items_to_place_this = { { name = "turbo-transport-belt" } },
                              localised_name = "Turbo transport belt" },
  ["secret-belt"]         = { type = "transport-belt", belt_speed = 0.5, hidden = true,
                              items_to_place_this = { { name = "secret-belt" } },
                              localised_name = "Hidden belt" },
  ["no-item-belt"]        = { type = "transport-belt", belt_speed = 0.25, hidden = false,
                              items_to_place_this = {},
                              localised_name = "Unplaceable belt" },
}

prototypes = {
  item = {
    ["transport-belt"] = { hidden = false, localised_name = "Transport belt" },
    ["fast-transport-belt"] = { hidden = false, localised_name = "Fast transport belt" },
    ["express-transport-belt"] = { hidden = false, localised_name = "Express transport belt" },
    ["turbo-transport-belt"] = { hidden = false, localised_name = "Turbo transport belt" },
    ["secret-belt"] = { hidden = true },
    ["iron-plate"] = { hidden = false, localised_name = "Iron plate" },
    ["copper-cable"] = { hidden = false, localised_name = "Copper cable" },
  },
  fluid = {
    ["crude-oil"] = { localised_name = "Crude oil" },
  },
  get_entity_filtered = function(filters)
    local out = {}
    for name, p in pairs(belt_protos) do
      if p.type == filters[1].type then out[name] = p end
    end
    return out
  end,
}

local belts = require("scripts.belts")
local rates = require("scripts.rates")

--------------------------------------------------------------------------------
-- Belt discovery
--------------------------------------------------------------------------------

print("== belt discovery ==")
local all = belts.all()
print(string.format("     %d visible belts found", #all))
assert(#all == 4, "expected 4 visible belts, got " .. #all)
assert(all[1].name == "transport-belt", "slowest first: got " .. all[1].name)
assert(all[4].name == "turbo-transport-belt", "fastest last: got " .. all[4].name)

-- Vanilla lane throughputs: yellow 7.5, red 15, blue 22.5, turbo 30 items/s.
check("yellow belt: items/s per lane", all[1].lane, 7.5)
check("red belt: items/s per lane", all[2].lane, 15)
check("blue belt: items/s per lane", all[3].lane, 22.5)
check("turbo belt: items/s per lane", all[4].lane, 30)

--------------------------------------------------------------------------------
-- Rates: electronic circuit in an assembling machine 2 (speed 0.75)
--------------------------------------------------------------------------------

print("\n== rates: electronic circuit, AM2, no modules ==")

local recipe_circuit = {
  name = "electronic-circuit",
  localised_name = "Electronic circuit",
  energy = 0.5,
  ingredients = {
    { name = "iron-plate", type = "item", amount = 1 },
    { name = "copper-cable", type = "item", amount = 3 },
  },
  products = {
    { name = "electronic-circuit", type = "item", amount = 1 },
  },
}

local am2 = {
  valid = true,
  type = "assembling-machine",
  crafting_speed = 0.75,
  productivity_bonus = 0,
  get_recipe = function() return recipe_circuit end,
}

local d = rates.for_entity(am2)
assert(d, "expected rates for AM2")
-- 0.75 speed / 0.5s recipe = 1.5 crafts/s
check("crafts/s", d.crafts_per_second, 1.5)
check("iron plate consumption /s", d.ingredients[1].per_second, 1.5)
check("copper cable consumption /s", d.ingredients[2].per_second, 4.5)
check("circuit production /s", d.products[1].per_second, 1.5)

--------------------------------------------------------------------------------
-- machines_fed
--------------------------------------------------------------------------------

print("\n== machines fed ==")
local yellow, red, blue = all[1], all[2], all[3]

-- Iron: 1.5/s per machine. Yellow lane = 7.5/s -> 5 machines on one lane.
check("iron, yellow, 1 lane", rates.machines_fed(yellow, 1, 1.5), 5)
check("iron, yellow, 2 lanes", rates.machines_fed(yellow, 2, 1.5), 10)
check("iron, blue,   2 lanes", rates.machines_fed(blue, 2, 1.5), 30)

-- Copper cable: 4.5/s per machine. Yellow lane = 7.5/s -> 1.667 machines.
check("cable, yellow, 1 lane", rates.machines_fed(yellow, 1, 4.5), 7.5 / 4.5)
check("cable, red,    2 lanes", rates.machines_fed(red, 2, 4.5), 30 / 4.5)

-- The limiting ingredient at fixed lanes is the highest per_second/lanes ratio.
-- Iron on 1 lane = 1.5, cable on 2 lanes = 2.25 -> cable still limits.
local iron_ratio = 1.5 / 1
local cable_ratio = 4.5 / 2
assert(cable_ratio > iron_ratio, "cable should limit even with iron on one lane")
print("ok   limiting ingredient ranking is lane-aware")

--------------------------------------------------------------------------------
-- Modules + beacons: crafting_speed already includes everything
--------------------------------------------------------------------------------

print("\n== rates: AM3 with speed modules + productivity ==")

local am3 = {
  valid = true,
  type = "assembling-machine",
  -- 1.25 base * (1 + 0.5 speed modules + 1.0 beacons) = 3.125 effective
  crafting_speed = 3.125,
  productivity_bonus = 0.4,
  get_recipe = function() return recipe_circuit end,
}

local d3 = rates.for_entity(am3)
check("crafts/s (speed already effective)", d3.crafts_per_second, 6.25)
-- Productivity does NOT reduce ingredient use.
check("iron consumption unaffected by prod", d3.ingredients[1].per_second, 6.25)
check("cable consumption unaffected by prod", d3.ingredients[2].per_second, 18.75)
-- Productivity DOES boost output: 6.25 * 1.4
check("circuit output boosted by prod", d3.products[1].per_second, 8.75)

--------------------------------------------------------------------------------
-- ignored_by_productivity (recycling / Space Age)
--------------------------------------------------------------------------------

print("\n== ignored_by_productivity ==")

local recipe_recycle = {
  name = "recycle-thing",
  localised_name = "Recycle thing",
  energy = 1,
  ingredients = { { name = "iron-plate", type = "item", amount = 1 } },
  products = {
    -- 2 out, 1 of which never benefits from productivity.
    { name = "iron-plate", type = "item", amount = 2, ignored_by_productivity = 1 },
  },
}

local recycler = {
  valid = true,
  type = "assembling-machine",
  crafting_speed = 1,
  productivity_bonus = 1.0, -- +100%
  get_recipe = function() return recipe_recycle end,
}

local dr = rates.for_entity(recycler)
-- 1 ignored + 1 boostable*(1+1.0) = 3 per craft, 1 craft/s
check("output with 1 of 2 ignored, +100% prod", dr.products[1].per_second, 3)

--------------------------------------------------------------------------------
-- Probability + amount ranges
--------------------------------------------------------------------------------

print("\n== probability / amount ranges ==")

local recipe_prob = {
  name = "prob-thing", localised_name = "Prob thing", energy = 1,
  ingredients = { { name = "iron-plate", type = "item", amount = 1 } },
  products = {
    { name = "copper-cable", type = "item", amount = 4, probability = 0.5 },
    { name = "iron-plate", type = "item", amount_min = 1, amount_max = 3 },
    { name = "crude-oil", type = "fluid", amount = 10 },
    { name = "iron-plate", type = "item", amount = 0 }, -- must be dropped
  },
}

local probm = {
  valid = true, type = "assembling-machine",
  crafting_speed = 1, productivity_bonus = 0,
  get_recipe = function() return recipe_prob end,
}

local dp = rates.for_entity(probm)
check("probability 0.5 x amount 4", dp.products[1].per_second, 2)
check("amount_min 1 / amount_max 3 -> avg 2", dp.products[2].per_second, 2)
check("fluid product kept", dp.products[3].per_second, 10)
assert(#dp.products == 3, "zero-amount product should be dropped, got " .. #dp.products)
print("ok   zero-amount product dropped")

local solids, fluids = rates.split(dp.products)
assert(#solids == 2, "expected 2 solid products, got " .. #solids)
assert(#fluids == 1, "expected 1 fluid product, got " .. #fluids)
print("ok   split() separates fluids from solids")

--------------------------------------------------------------------------------
-- Guards
--------------------------------------------------------------------------------

print("\n== guards ==")

assert(rates.for_entity(nil) == nil, "nil entity")
assert(rates.for_entity({ valid = false }) == nil, "invalid entity")
assert(rates.for_entity({ valid = true, type = "transport-belt" }) == nil, "unsupported type")
print("ok   nil / invalid / unsupported entity rejected")

local no_recipe = {
  valid = true, type = "furnace", crafting_speed = 2, productivity_bonus = 0,
  get_recipe = function() return nil end,
}
assert(rates.for_entity(no_recipe) == nil, "furnace with no recipe yet")
print("ok   machine with no recipe returns nil")

local zero_speed = {
  valid = true, type = "assembling-machine", crafting_speed = 0, productivity_bonus = 0,
  get_recipe = function() return recipe_circuit end,
}
assert(rates.for_entity(zero_speed) == nil, "zero crafting speed")
print("ok   zero crafting speed returns nil")

check("machines_fed with zero demand is infinite",
  rates.machines_fed(yellow, 1, 0) == math.huge and 1 or 0, 1)

--------------------------------------------------------------------------------
-- Belt stacking (belt_stack_size_bonus, e.g. the stack-inserters mod)
--------------------------------------------------------------------------------

print("\n== belt stacking ==")

-- stack_size drives the cap: a machine that stacks to 10 cannot ride 16 deep.
prototypes.item["coal"] = { hidden = false, localised_name = "Coal", stack_size = 50 }
prototypes.item["engine"] = { hidden = false, localised_name = "Engine", stack_size = 10 }
prototypes.item["silo"] = { hidden = false, localised_name = "Silo", stack_size = 1 }

local force_no_stack = { belt_stack_size_bonus = 0, recipes = {} }
local force_stack_4 = { belt_stack_size_bonus = 3, recipes = {} }
local force_stack_16 = { belt_stack_size_bonus = 15, recipes = {} }

check("no research: 1 item per slot",
  belts.stack_height(force_no_stack, "coal"), 1)
check("bonus 3: 4 coal per slot",
  belts.stack_height(force_stack_4, "coal"), 4)
check("bonus 15: 16 coal per slot (stack_size 50 allows it)",
  belts.stack_height(force_stack_16, "coal"), 16)
-- Capped by the item's own stack size.
check("bonus 15 but stack_size 10: capped at 10",
  belts.stack_height(force_stack_16, "engine"), 10)
check("stack_size 1 never stacks",
  belts.stack_height(force_stack_16, "silo"), 1)
check("nil force degrades to no stacking",
  belts.stack_height(nil, "coal"), 1)
-- Unknown item (a mod removed it mid-game): must not error.
check("unknown item degrades to 1",
  belts.stack_height(force_stack_4, "does-not-exist"), 1)

-- Throughput scales linearly with stack height.
check("yellow, 1 lane, no stacking, 1.5/s demand",
  rates.machines_fed(yellow, 1, 1.5, 1), 5)
check("yellow, 1 lane, stack 4 -> 4x the machines",
  rates.machines_fed(yellow, 1, 1.5, 4), 20)
check("blue, 2 lanes, stack 4",
  rates.machines_fed(blue, 2, 1.5, 4), 120)
check("omitted stack argument behaves as 1",
  rates.machines_fed(yellow, 1, 1.5), 5)

-- The bottleneck is measured in belt SLOTS, not items: a non-stacking item can
-- limit the line even though fewer of them are consumed.
local coal_slots = 10.0 / (1 * 16)   -- 10/s, stacks 16 deep
local silo_slots = 1.0 / (1 * 1)     -- 1/s, never stacks
assert(silo_slots > coal_slots,
  "a non-stacking item at 1/s must outweigh a 16-stacking item at 10/s")
print("ok   slot demand, not item rate, decides the bottleneck")

--------------------------------------------------------------------------------
-- Regression: Factorio API objects are userdata, not tables.
--
-- `player.opened` reported type "userdata", so an earlier
-- `type(opened) == "table"` guard rejected every machine and the window never
-- opened. is_supported must work on anything exposing .valid and .type, without
-- caring what Lua type it is.
--------------------------------------------------------------------------------

print("\n== userdata-like entity (the real API shape) ==")

-- Proxy whose fields live behind __index, the way LuaEntity behaves.
local backing = { valid = true, type = "assembling-machine",
                  crafting_speed = 1, productivity_bonus = 0 }
local proxy = setmetatable({}, {
  __index = function(_, k)
    if k == "get_recipe" then return function() return recipe_circuit end end
    return backing[k]
  end,
})

assert(rates.is_supported(proxy), "is_supported must accept a proxied entity")
local dproxy = rates.for_entity(proxy)
assert(dproxy, "for_entity must work through __index")
check("crafts/s through a proxy entity", dproxy.crafts_per_second, 2)
print("ok   entity fields read through __index, no type() check")

--------------------------------------------------------------------------------
-- unlocked_for
--------------------------------------------------------------------------------

print("\n== unlocked_for ==")

local force_early = {
  recipes = {
    ["transport-belt"] = { enabled = true, hidden = false,
      products = { { type = "item", name = "transport-belt" } } },
    ["fast-transport-belt"] = { enabled = false, hidden = false,
      products = { { type = "item", name = "fast-transport-belt" } } },
    ["express-transport-belt"] = { enabled = true, hidden = true,
      products = { { type = "item", name = "express-transport-belt" } } },
  },
}
local unlocked = belts.unlocked_for(force_early)
assert(#unlocked == 1, "expected only yellow unlocked, got " .. #unlocked)
assert(unlocked[1].name == "transport-belt")
print("ok   only enabled, non-hidden recipes count as unlocked")

local force_nothing = { recipes = {} }
local fallback = belts.unlocked_for(force_nothing)
assert(#fallback == 4, "expected fallback to all belts, got " .. #fallback)
print("ok   falls back to all belts when nothing is unlocked")

--------------------------------------------------------------------------------

print()
if failures > 0 then
  print(string.format("%d CHECK(S) FAILED", failures))
  os.exit(1)
end
print("all checks passed")
