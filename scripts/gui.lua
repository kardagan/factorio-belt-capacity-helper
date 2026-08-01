--- The Belt Capacity Helper window.
---
--- Layout: one column per solid ingredient, one row per belt tier.
--- Each ingredient column has a 1/2 lane toggle; the rightmost column of each
--- row is the minimum across ingredients — what your actual setup supports.

local belts_mod = require("scripts.belts")
local rates_mod = require("scripts.rates")

local gui = {}

local ROOT = "bch-root"

--- Format a machine count. Shows the exact value plus the whole-machine floor
--- when they differ, because "12.5 machines" means 12 saturated + one starved.
local function fmt_machines(n)
  if n == math.huge then return "∞" end
  local rounded = math.floor(n * 10 + 0.5) / 10
  if rounded == math.floor(rounded) then
    return string.format("%d", rounded)
  end
  return string.format("%.1f", rounded)
end

local function fmt_rate(n)
  if n >= 100 then return string.format("%.0f", n) end
  if n >= 10 then return string.format("%.1f", n) end
  return string.format("%.2f", n)
end

--- Per-player, per-recipe lane configuration. Defaults to 2 lanes.
---
--- Keys are namespaced by side ("in"/"out") because an item can be both an
--- ingredient and a product (recycling, and plenty of Nullius recipes), and the
--- two toggles must stay independent.
local function lane_key(side, item_name)
  return side .. ":" .. item_name
end

local function lane_count(player, recipe_name, side, item_name)
  local pdata = storage.players[player.index]
  local cfg = pdata.lanes[recipe_name]
  if not cfg then return 2 end
  return cfg[lane_key(side, item_name)] or 2
end

local function set_lane_count(player, recipe_name, side, item_name, lanes)
  local pdata = storage.players[player.index]
  pdata.lanes[recipe_name] = pdata.lanes[recipe_name] or {}
  pdata.lanes[recipe_name][lane_key(side, item_name)] = lanes
end

local function reset_lanes(player, recipe_name)
  storage.players[player.index].lanes[recipe_name] = nil
end

local function refs_machine_name(entity)
  return entity.prototype.localised_name
end

--- Subtitle under the recipe name: machine, effective crafts/s, and every bonus
--- that is already baked into that figure. Showing them makes it obvious that
--- modules and beacons are accounted for rather than ignored.
local function machine_line(machine_name, data)
  local parts = { "" }
  local function add(s) parts[#parts + 1] = s end

  add(machine_name)
  add(" — ")
  add(fmt_rate(data.crafts_per_second))
  add(" crafts/s")

  local bonuses = {}
  if (data.speed_bonus or 0) ~= 0 then
    bonuses[#bonuses + 1] = string.format("%+.0f%% ", data.speed_bonus * 100)
    bonuses[#bonuses + 1] = { "bch.bonus-speed" }
  end
  if (data.productivity or 0) ~= 0 then
    if #bonuses > 0 then bonuses[#bonuses + 1] = ", " end
    bonuses[#bonuses + 1] = string.format("%+.0f%% ", data.productivity * 100)
    bonuses[#bonuses + 1] = { "bch.bonus-productivity" }
  end
  if data.quality and data.quality ~= "normal" then
    if #bonuses > 0 then bonuses[#bonuses + 1] = ", " end
    bonuses[#bonuses + 1] = { "bch.bonus-quality" }
    bonuses[#bonuses + 1] = " " .. data.quality
  end

  if #bonuses > 0 then
    add("  (")
    -- Localised strings cap at 20 parameters; each bonus costs two slots, and
    -- there are at most three bonuses, so this stays well inside the limit.
    for _, b in ipairs(bonuses) do add(b) end
    add(")")
  end

  return parts
end

--- Stacking footnote for an item tooltip.
---
--- Says how deep the item rides when it stacks, and calls out the case that is
--- easy to miss: stacking is researched, but THIS item is capped at 1 by its own
--- stack size, so its column is far lower than its neighbours for no visible
--- reason.
local function stack_note(force, stack)
  local researched = (force and force.belt_stack_size_bonus or 0) > 0
  if stack > 1 then return { "bch.stacked-note", stack } end
  if researched then return { "bch.no-stack-note" } end
  return ""
end

local function sprite_for(entry)
  if entry.type == "fluid" then return "fluid/" .. entry.name end
  return "item/" .. entry.name
end

local function localised_name_for(entry)
  if entry.type == "fluid" then
    local p = prototypes.fluid[entry.name]
    return p and p.localised_name or entry.name
  end
  local p = prototypes.item[entry.name]
  return p and p.localised_name or entry.name
end

--- Per-item stacking override, stored next to the lane config so both are reset
--- together and both survive reopening the same recipe.
local function stack_key(side, item_name)
  return "stack:" .. side .. ":" .. item_name
end

local function item_stack_override(player, recipe_name, side, item_name)
  local cfg = storage.players[player.index].lanes[recipe_name]
  return cfg and cfg[stack_key(side, item_name)] or nil
end

local function set_item_stack(player, recipe_name, side, item_name, stack)
  local pdata = storage.players[player.index]
  pdata.lanes[recipe_name] = pdata.lanes[recipe_name] or {}
  pdata.lanes[recipe_name][stack_key(side, item_name)] = stack
end

--- Stacking depth used for one column.
---
--- Two clamps always apply on top of the stored value: the item's own stack
--- size, and — while the padlock is closed — what the force has researched.
local function effective_stack(player, item_name, recipe_name, side)
  -- Defaults to 1: the window opens showing plain, unstacked belts, and the
  -- player raises each column to match how that lane is actually fed.
  local level = 1
  if recipe_name and side then
    level = item_stack_override(player, recipe_name, side, item_name) or 1
  end

  local pdata = storage.players[player.index]
  if not pdata.stack_unlocked then
    level = math.min(level, 1 + (player.force.belt_stack_size_bonus or 0))
  end

  local proto = prototypes.item[item_name]
  local cap = proto and proto.stack_size or 1
  return math.max(1, math.min(level, cap))
end

--- Stacking levels this item's stepper may reach.
--- Bounded by the padlock (research while closed, up to 16 while open) and by
--- the item's own stack size, so a stack_size 1 item gets no stepper at all.
local function item_stack_choices(player, item_name)
  local pdata = storage.players[player.index]
  local researched = 1 + (player.force.belt_stack_size_bonus or 0)
  local top = pdata.stack_unlocked and 16 or researched

  local proto = prototypes.item[item_name]
  top = math.min(top, proto and proto.stack_size or 1)

  -- Every integer, not the 1/2/4/8/16 research progression: with a -/+ stepper
  -- there is no reason to skip 3, and a mixed belt can carry any depth.
  local out = {}
  for n = 1, math.max(1, top) do out[#out + 1] = n end
  return out, researched
end

--- One column's controls on a single row: a lane button whose icon flips
--- between one and two lanes, followed by a - / + stepper for belt stacking.
local function lane_selector(parent, player, recipe_name, side, item_name)
  local lanes = lane_count(player, recipe_name, side, item_name)
  local choices = item_stack_choices(player, item_name)
  local stack = effective_stack(player, item_name, recipe_name, side)

  local flow = parent.add({ type = "flow", direction = "horizontal" })
  flow.style.horizontal_align = "center"
  flow.style.horizontally_stretchable = true
  flow.style.vertical_align = "center"
  flow.style.horizontal_spacing = 3

  local refs = {}

  refs.lane = flow.add({
    type = "sprite-button",
    sprite = "bch-lanes-" .. lanes,
    style = "bch_lane_button",
    tags = { bch_action = "toggle-lane", item = item_name, side = side },
    tooltip = { lanes == 1 and "bch.lane-1-tooltip" or "bch.lane-2-tooltip" },
  })

  -- Stacking stepper, on the same row. Skipped entirely when the item admits a
  -- single level (stack_size 1, or no stacking researched): a stepper that can
  -- never move would just be noise.
  if #choices > 1 then
    refs.minus = flow.add({
      type = "button",
      caption = "−",
      style = "bch_step_button",
      tags = { bch_action = "step-stack", item = item_name, side = side, delta = -1 },
      tooltip = { "bch.stack-down-tooltip" },
    })
    refs.value = flow.add({
      type = "label",
      caption = "×" .. stack,
      style = "bold_label",
    })
    refs.value.style.minimal_width = 26
    refs.value.style.horizontal_align = "center"
    refs.plus = flow.add({
      type = "button",
      caption = "+",
      style = "bch_step_button",
      tags = { bch_action = "step-stack", item = item_name, side = side, delta = 1 },
      tooltip = { "bch.stack-up-tooltip",
        tostring(1 + (player.force.belt_stack_size_bonus or 0)) },
    })
  end

  return refs
end

--- Repaint one column's lane button and stacking stepper.
--- `choices` is the list of levels the item allows, used to grey out the ends.
local function refresh_lane_selector(refs, lanes, stack, choices)
  if not refs then return end

  if refs.lane and refs.lane.valid then
    refs.lane.sprite = "bch-lanes-" .. lanes
    refs.lane.tooltip = { lanes == 1 and "bch.lane-1-tooltip" or "bch.lane-2-tooltip" }
  end

  if refs.value and refs.value.valid then
    refs.value.caption = "×" .. stack
  end

  -- Disable the ends rather than letting a click do nothing silently.
  if refs.minus and refs.minus.valid then
    refs.minus.enabled = stack > choices[1]
  end
  if refs.plus and refs.plus.valid then
    refs.plus.enabled = stack < choices[#choices]
  end
end

--------------------------------------------------------------------------------
-- Teardown
--------------------------------------------------------------------------------

function gui.destroy(player)
  local root = player.gui.screen[ROOT]
  if root and root.valid then root.destroy() end
  local pdata = storage.players[player.index]
  if pdata then
    pdata.open_entity = nil
    pdata.refs = nil
  end
  player.set_shortcut_toggled("bch-toggle-window", false)
end

function gui.is_open(player)
  local root = player.gui.screen[ROOT]
  return root ~= nil and root.valid
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Build the ingredient table for the currently tracked entity.
local function build_table(parent, player, data, belt_list)
  local solids, fluids = rates_mod.split(data.ingredients)
  local recipe_name = data.recipe.name

  local refs = { cells = {}, toggles = {}, totals = {}, rate_labels = {} }

  if #solids == 0 then
    parent.add({
      type = "label",
      caption = { "bch.no-solid-ingredients" },
      style = "bold_label",
    })
  else
    -- Columns: belt label + one per ingredient + the "supported" total.
    local tbl = parent.add({
      type = "table",
      name = "bch-ingredients",
      column_count = #solids + 2,
      style = "bordered_table",
    })
    tbl.style.horizontally_stretchable = true

    -- Header row: icons.
    tbl.add({ type = "label", caption = "" })
    for _, ing in ipairs(solids) do
      local flow = tbl.add({ type = "flow", direction = "horizontal" })
      flow.style.horizontal_align = "center"
      flow.style.horizontally_stretchable = true
      local stack = effective_stack(player, ing.name, recipe_name, "in")
      local sprite = flow.add({
        type = "sprite-button",
        sprite = sprite_for(ing),
        style = "transparent_slot",
        tooltip = {
          "",
          {
            "bch.ingredient-tooltip",
            localised_name_for(ing),
            fmt_rate(ing.per_second),
            fmt_rate(ing.amount),
          },
          stack_note(player.force, stack),
        },
      })
      sprite.style.size = 32
    end
    tbl.add({
      type = "label",
      caption = { "bch.header-supported" },
      style = "bold_label",
      tooltip = { "bch.header-supported-tooltip" },
    })

    -- Lane row: two icon buttons, the active one pressed in. Clicking the choice
    -- directly beats a toggle, where the other state is invisible until clicked.
    tbl.add({ type = "label", caption = { "bch.row-lanes" }, style = "caption_label" })
    for _, ing in ipairs(solids) do
      refs.toggles[ing.name] = lane_selector(tbl, player, recipe_name, "in", ing.name)
    end
    tbl.add({ type = "label", caption = "" })

    -- Consumption row.
    tbl.add({ type = "label", caption = { "bch.row-consumption" }, style = "caption_label" })
    for _, ing in ipairs(solids) do
      local lbl = tbl.add({
        type = "label",
        caption = fmt_rate(ing.per_second) .. "/s",
      })
      lbl.style.horizontal_align = "center"
      lbl.style.horizontally_stretchable = true
      refs.rate_labels[ing.name] = lbl
    end
    tbl.add({ type = "label", caption = "" })

    -- One row per belt tier.
    for _, belt in ipairs(belt_list) do
      local head = tbl.add({ type = "flow", direction = "horizontal" })
      head.style.vertical_align = "center"
      local icon = head.add({
        type = "sprite-button",
        sprite = "item/" .. belt.item,
        style = "transparent_slot",
        tooltip = { "bch.belt-tooltip", belt.localised_name, fmt_rate(belt.lane) },
      })
      icon.style.size = 24
      head.add({ type = "label", caption = belt.localised_name })

      refs.cells[belt.name] = {}
      for _, ing in ipairs(solids) do
        local lanes = lane_count(player, recipe_name, "in", ing.name)
        local stack = effective_stack(player, ing.name, recipe_name, "in")
        local n = rates_mod.machines_fed(belt, lanes, ing.per_second, stack)
        local lbl = tbl.add({ type = "label", caption = fmt_machines(n) })
        lbl.style.horizontal_align = "center"
        lbl.style.horizontally_stretchable = true
        refs.cells[belt.name][ing.name] = lbl
      end

      local total = tbl.add({ type = "label", caption = "", style = "bold_label" })
      total.style.horizontal_align = "center"
      refs.totals[belt.name] = total
    end

    -- The limiting-ingredient warning belongs right under the table it comments
    -- on, not further down past the fluid block.
    local limiting = parent.add({
      type = "label",
      caption = "",
      style = "bold_label",
      visible = false,
    })
    limiting.style.top_margin = 4
    limiting.style.font_color = { r = 1, g = 0.75, b = 0.25 }
    refs.limiting_label = limiting
  end

  -- Fluids: rates only, no belt translation.
  if #fluids > 0 and player.mod_settings["bch-show-fluids"].value then
    local fl = parent.add({ type = "flow", direction = "vertical" })
    fl.style.top_margin = 8
    fl.add({ type = "label", caption = { "bch.fluids-header" }, style = "caption_label" })
    for _, fluid in ipairs(fluids) do
      local row = fl.add({ type = "flow", direction = "horizontal" })
      row.style.vertical_align = "center"
      local icon = row.add({
        type = "sprite-button",
        sprite = sprite_for(fluid),
        style = "transparent_slot",
      })
      icon.style.size = 24
      row.add({ type = "label", caption = localised_name_for(fluid) })
      local rate = row.add({ type = "label", caption = fmt_rate(fluid.per_second) .. "/s" })
      rate.style.left_margin = 8
      rate.style.font = "default-semibold"
    end
  end

  return refs, solids
end

--- Output block: how many machines it takes to saturate a belt.
local function build_output(parent, player, data, belt_list)
  local solids, fluids = rates_mod.split(data.products)
  if #solids == 0 and #fluids == 0 then return nil end

  -- `direction` matters: inside a vertical flow a line with no direction is laid
  -- out vertically and renders as a stray coloured block.
  parent.add({ type = "line", direction = "horizontal" }).style.top_margin = 6
  parent.add({ type = "label", caption = { "bch.outputs-header" }, style = "caption_label" })

  local refs = { cells = {}, toggles = {}, rate_labels = {} }
  local recipe_name = data.recipe.name

  if #solids > 0 then
    local tbl = parent.add({
      type = "table",
      column_count = #solids + 1,
      style = "bordered_table",
    })
    tbl.style.horizontally_stretchable = true

    -- Header icons.
    tbl.add({ type = "label", caption = "" })
    for _, prod in ipairs(solids) do
      local flow = tbl.add({ type = "flow", direction = "horizontal" })
      flow.style.horizontal_align = "center"
      flow.style.horizontally_stretchable = true
      local stack = effective_stack(player, prod.name, recipe_name, "out")
      local sprite = flow.add({
        type = "sprite-button",
        sprite = sprite_for(prod),
        style = "transparent_slot",
        tooltip = {
          "",
          {
            "bch.product-tooltip",
            localised_name_for(prod),
            fmt_rate(prod.per_second),
          },
          stack_note(player.force, stack),
        },
      })
      sprite.style.size = 32
    end

    -- Lane toggles for outputs too: a full belt out vs one lane out.
    tbl.add({ type = "label", caption = { "bch.row-lanes" }, style = "caption_label" })
    for _, prod in ipairs(solids) do
      refs.toggles[prod.name] = lane_selector(tbl, player, recipe_name, "out", prod.name)
    end

    -- Production row.
    tbl.add({ type = "label", caption = { "bch.row-production" }, style = "caption_label" })
    for _, prod in ipairs(solids) do
      local lbl = tbl.add({ type = "label", caption = fmt_rate(prod.per_second) .. "/s" })
      lbl.style.horizontal_align = "center"
      lbl.style.horizontally_stretchable = true
      refs.rate_labels[prod.name] = lbl
    end

    for _, belt in ipairs(belt_list) do
      local head = tbl.add({ type = "flow", direction = "horizontal" })
      head.style.vertical_align = "center"
      local icon = head.add({
        type = "sprite-button",
        sprite = "item/" .. belt.item,
        style = "transparent_slot",
        tooltip = { "bch.belt-tooltip", belt.localised_name, fmt_rate(belt.lane) },
      })
      icon.style.size = 24
      head.add({ type = "label", caption = belt.localised_name })

      refs.cells[belt.name] = {}
      for _, prod in ipairs(solids) do
        local lanes = lane_count(player, recipe_name, "out", prod.name)
        local stack = effective_stack(player, prod.name, recipe_name, "out")
        local n = rates_mod.machines_fed(belt, lanes, prod.per_second, stack)
        local lbl = tbl.add({ type = "label", caption = fmt_machines(n) })
        lbl.style.horizontal_align = "center"
        lbl.style.horizontally_stretchable = true
        refs.cells[belt.name][prod.name] = lbl
      end
    end
  end

  if #fluids > 0 and player.mod_settings["bch-show-fluids"].value then
    for _, fluid in ipairs(fluids) do
      local row = parent.add({ type = "flow", direction = "horizontal" })
      row.style.vertical_align = "center"
      local icon = row.add({
        type = "sprite-button",
        sprite = sprite_for(fluid),
        style = "transparent_slot",
      })
      icon.style.size = 24
      row.add({ type = "label", caption = localised_name_for(fluid) })
      local rate = row.add({ type = "label", caption = fmt_rate(fluid.per_second) .. "/s" })
      rate.style.left_margin = 8
      rate.style.font = "default-semibold"
    end
  end

  return refs, solids
end

--- Refresh the numbers in place, without rebuilding the frame.
function gui.refresh_values(player)
  local pdata = storage.players[player.index]
  local refs = pdata.refs
  if not refs then return end

  local entity = pdata.open_entity
  if not (entity and entity.valid) then
    gui.destroy(player)
    return
  end

  local data = rates_mod.for_entity(entity)
  if not data then
    gui.destroy(player)
    return
  end

  local recipe_name = data.recipe.name
  local belt_list = refs.belt_list

  -- Researched belt stacking, force-wide. Shown in the subtitle; the per-item
  -- height is capped by each item's own stack size and computed per column.
  data.belt_stack = 1 + (player.force.belt_stack_size_bonus or 0)

  -- Re-read the rates from the freshly computed data rather than trusting the
  -- values captured at build time: a module swap or a finished research changes
  -- crafting_speed, and the cached per_second would be stale.
  local fresh_in, fresh_out = {}, {}
  for _, ing in ipairs(data.ingredients) do
    if ing.type ~= "fluid" then fresh_in[ing.name] = ing.per_second end
  end
  for _, prod in ipairs(data.products) do
    if prod.type ~= "fluid" then fresh_out[prod.name] = prod.per_second end
  end
  for _, ing in ipairs(refs.solid_inputs) do
    ing.per_second = fresh_in[ing.name] or ing.per_second
    local lbl = refs.inputs.rate_labels[ing.name]
    if lbl and lbl.valid then lbl.caption = fmt_rate(ing.per_second) .. "/s" end
  end
  for _, prod in ipairs(refs.solid_outputs) do
    prod.per_second = fresh_out[prod.name] or prod.per_second
    local lbl = refs.outputs and refs.outputs.rate_labels[prod.name]
    if lbl and lbl.valid then lbl.caption = fmt_rate(prod.per_second) .. "/s" end
  end

  -- The header carries the effective crafts/s and productivity, both of which
  -- move when modules or research change.
  if refs.subtitle and refs.subtitle.valid then
    refs.subtitle.caption = machine_line(refs.machine_name, data)
  end

  -- Standing warning while the table shows a level the factory cannot reach.
  -- Without it, planning numbers are indistinguishable from real ones.
  if refs.planning_label and refs.planning_label.valid then
    local researched = 1 + (player.force.belt_stack_size_bonus or 0)
    -- Any single column above the researched depth makes the whole table
    -- hypothetical, so warn on the highest one.
    local highest = 0
    for _, ing in ipairs(refs.solid_inputs) do
      highest = math.max(highest, effective_stack(player, ing.name, recipe_name, "in"))
    end
    for _, prod in ipairs(refs.solid_outputs) do
      highest = math.max(highest, effective_stack(player, prod.name, recipe_name, "out"))
    end

    if highest > researched then
      refs.planning_label.caption = { "bch.planning-warning", tostring(highest) }
      refs.planning_label.visible = true
    else
      refs.planning_label.visible = false
    end
  end

  -- The limiting ingredient does not depend on the belt tier: every column in a
  -- row scales by the same belt speed, so the ranking is fixed once lanes are
  -- chosen. Compute it once, on demand per lane, as items/s per lane consumed.
  -- Belt slots consumed per second, the quantity that actually competes for belt
  -- room. Stacking matters here: an item that cannot stack (stack_size 1) eats a
  -- whole slot each, so it can be the bottleneck even at a low item rate.
  local function slot_demand(ing)
    local lanes = lane_count(player, recipe_name, "in", ing.name)
    local stack = effective_stack(player, ing.name, recipe_name, "in")
    return ing.per_second / (lanes * stack)
  end

  local worst_ratio = -1
  for _, ing in ipairs(refs.solid_inputs) do
    local ratio = slot_demand(ing)
    if ratio > worst_ratio then worst_ratio = ratio end
  end

  -- Several ingredients can tie for worst (very common: same amount, same lane
  -- count). Naming only one of them would read as "the other is fine", so list
  -- every ingredient at the limit.
  local worst_names = {}
  for _, ing in ipairs(refs.solid_inputs) do
    local ratio = slot_demand(ing)
    -- Relative tolerance: these are floats derived from crafting_speed.
    if worst_ratio > 0 and math.abs(ratio - worst_ratio) <= worst_ratio * 1e-9 then
      worst_names[#worst_names + 1] = localised_name_for(ing)
    end
  end

  -- Inputs: recompute each cell, then the row minimum.
  for _, belt in ipairs(belt_list) do
    local min_n = math.huge
    for _, ing in ipairs(refs.solid_inputs) do
      local lanes = lane_count(player, recipe_name, "in", ing.name)
      local stack = effective_stack(player, ing.name, recipe_name, "in")
      local n = rates_mod.machines_fed(belt, lanes, ing.per_second, stack)
      local cell = refs.inputs.cells[belt.name] and refs.inputs.cells[belt.name][ing.name]
      if cell and cell.valid then cell.caption = fmt_machines(n) end
      if n < min_n then min_n = n end
    end
    local total = refs.inputs.totals[belt.name]
    if total and total.valid then
      total.caption = fmt_machines(min_n)
    end
  end

  -- Repaint the column selectors: lane and stacking both change on click,
  -- on reset, and when the padlock moves.
  for name, col in pairs(refs.inputs.toggles) do
    refresh_lane_selector(col,
      lane_count(player, recipe_name, "in", name),
      effective_stack(player, name, recipe_name, "in"),
      item_stack_choices(player, name))
  end

  if refs.limiting_label and refs.limiting_label.valid then
    -- Only meaningful with something to compare against, and only if the
    -- limiting item actually consumes anything.
    if #worst_names > 0 and #refs.solid_inputs > 1 then
      -- Localised strings cannot be concatenated with "..", so build a nested
      -- {"", a, ", ", b, ...} chain, which Factorio renders as one line.
      -- A localised string takes at most 20 parameters, and each name costs two
      -- slots (separator + name), so cap the list well below that.
      local MAX = 6
      local joined = { "" }
      for i, name in ipairs(worst_names) do
        if i > MAX then
          joined[#joined + 1] = ", …"
          break
        end
        if i > 1 then joined[#joined + 1] = ", " end
        joined[#joined + 1] = name
      end
      refs.limiting_label.caption = {
        #worst_names > 1 and "bch.limiting-plural" or "bch.limiting",
        joined,
      }
      refs.limiting_label.visible = true
    else
      refs.limiting_label.visible = false
    end
  end

  -- Outputs.
  if refs.outputs then
    for _, prod in ipairs(refs.solid_outputs) do
      local lanes = lane_count(player, recipe_name, "out", prod.name)
      local stack = effective_stack(player, prod.name, recipe_name, "out")
      refresh_lane_selector(refs.outputs.toggles[prod.name], lanes, stack,
        item_stack_choices(player, prod.name))
      for _, belt in ipairs(belt_list) do
        local n = rates_mod.machines_fed(belt, lanes, prod.per_second, stack)
        local cell = refs.outputs.cells[belt.name] and refs.outputs.cells[belt.name][prod.name]
        if cell and cell.valid then cell.caption = fmt_machines(n) end
      end
    end
  end
end

--- Build the whole window for `entity`.
function gui.open(player, entity)
  gui.destroy(player)

  local data = rates_mod.for_entity(entity)
  if not data then
    player.print({ "bch.no-recipe" })
    return
  end

  data.belt_stack = 1 + (player.force.belt_stack_size_bonus or 0)

  local belt_list
  if player.mod_settings["bch-only-unlocked-belts"].value then
    belt_list = belts_mod.unlocked_for(player.force)
  else
    belt_list = belts_mod.all()
  end

  if #belt_list == 0 then
    player.print({ "bch.no-belts" })
    return
  end

  local root = player.gui.screen.add({
    type = "frame",
    name = ROOT,
    direction = "vertical",
  })
  root.style.minimal_width = 340

  -- Titlebar.
  local titlebar = root.add({ type = "flow", name = "titlebar", direction = "horizontal" })
  titlebar.drag_target = root
  titlebar.add({
    type = "label",
    caption = { "bch.window-title" },
    style = "frame_title",
    ignored_by_interaction = true,
  })
  local filler = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true,
  })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true
  local pdata_now = storage.players[player.index]
  titlebar.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = pdata_now.stack_unlocked and "bch-lock-open" or "bch-lock-closed",
    hovered_sprite = pdata_now.stack_unlocked and "bch-lock-open" or "bch-lock-closed",
    tooltip = { pdata_now.stack_unlocked and "bch.stack-unlocked-tooltip"
      or "bch.stack-locked-tooltip" },
    tags = { bch_action = "toggle-stack-lock" },
  })
  titlebar.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = "utility/reset",
    hovered_sprite = "utility/reset",
    tooltip = { "bch.reset-tooltip" },
    tags = { bch_action = "reset" },
  })
  titlebar.add({
    type = "sprite-button",
    style = "frame_action_button",
    sprite = "utility/close",
    hovered_sprite = "utility/close",
    tags = { bch_action = "close" },
  })

  local content = root.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical",
  })

  -- Header: recipe, machine, effective speed.
  local header = content.add({ type = "flow", direction = "horizontal" })
  header.style.vertical_align = "center"
  header.style.bottom_margin = 6
  local ricon = header.add({
    type = "sprite-button",
    sprite = "recipe/" .. data.recipe.name,
    style = "transparent_slot",
    tooltip = data.recipe.localised_name,
  })
  ricon.style.size = 40
  local hinfo = header.add({ type = "flow", direction = "vertical" })
  hinfo.add({
    type = "label",
    caption = data.recipe.localised_name,
    style = "heading_2_label",
  })
  local subtitle = hinfo.add({
    type = "label",
    caption = machine_line(refs_machine_name(entity), data),
    style = "subheader_label",
  })

  -- Scroll pane so a 10-tier belt list still fits on screen.
  -- Scroll only kicks in when the belt list is long (overhaul mods with 8+ tiers).
  -- Capped against the player's own resolution so the window never runs off the
  -- bottom of the screen.
  local res = player.display_resolution
  local scale = player.display_scale
  -- Sits above the table: a warning below it would be read after the numbers.
  local planning = content.add({
    type = "label",
    caption = "",
    style = "bold_label",
    visible = false,
  })
  planning.style.bottom_margin = 4
  planning.style.font_color = { r = 1, g = 0.75, b = 0.25 }

  -- Vertical scrolling only: the belt list can be long with overhaul mods, but
  -- the table must always be readable across its full width. Constraining the
  -- width instead produced a horizontal bar that hid the leftmost column.
  local scroll = content.add({ type = "scroll-pane", direction = "vertical" })
  scroll.style.maximal_height = math.max(300, (res.height / scale) - 260)
  scroll.style.horizontally_stretchable = true
  scroll.vertical_scroll_policy = "auto"
  scroll.horizontal_scroll_policy = "never"

  local input_refs, solid_inputs = build_table(scroll, player, data, belt_list)
  local output_refs, solid_outputs = build_output(scroll, player, data, belt_list)

  storage.players[player.index].open_entity = entity
  storage.players[player.index].refs = {
    root = root,
    belt_list = belt_list,
    inputs = input_refs,
    outputs = output_refs,
    solid_inputs = solid_inputs or {},
    solid_outputs = solid_outputs or {},
    limiting_label = input_refs.limiting_label,
    subtitle = subtitle,
    planning_label = planning,
    machine_name = entity.prototype.localised_name,
    recipe_name = data.recipe.name,
  }

  gui.refresh_values(player)

  -- Deliberately NOT setting player.opened: that would close the machine window,
  -- and the whole point is to read both side by side.
  --
  -- Anchor to the left edge. The frame's real width is only known after a render
  -- pass, so any right-anchored placement has to guess it — and a guess that is
  -- too small pushes the window off screen. x = 0 always fits.
  root.location = { x = 0, y = math.floor(80 * scale) }
  player.set_shortcut_toggled("bch-toggle-window", true)
end

--------------------------------------------------------------------------------
-- Events routed from control.lua
--------------------------------------------------------------------------------

function gui.on_click(player, element)
  local action = element.tags and element.tags.bch_action
  if not action then return false end

  if action == "close" then
    gui.destroy(player)
    return true
  end

  if action == "reset" then
    local pdata = storage.players[player.index]
    if pdata.refs then
      reset_lanes(player, pdata.refs.recipe_name)
      gui.refresh_values(player)
    end
    return true
  end

  if action == "toggle-lane" then
    local pdata = storage.players[player.index]
    if not pdata.refs then return true end
    local side, item = element.tags.side, element.tags.item
    local current = lane_count(player, pdata.refs.recipe_name, side, item)
    set_lane_count(player, pdata.refs.recipe_name, side, item, current == 1 and 2 or 1)
    gui.refresh_values(player)
    return true
  end

  if action == "step-stack" then
    local pdata = storage.players[player.index]
    if not pdata.refs then return true end
    local side, item = element.tags.side, element.tags.item
    local choices = item_stack_choices(player, item)
    local current = effective_stack(player, item, pdata.refs.recipe_name, side)

    -- Levels are consecutive integers, so stepping is plain arithmetic, clamped
    -- to the range this item allows.
    local wanted = math.max(choices[1], math.min(choices[#choices],
      current + element.tags.delta))

    set_item_stack(player, pdata.refs.recipe_name, side, item, wanted)
    gui.refresh_values(player)
    return true
  end

  if action == "toggle-stack-lock" then
    local pdata = storage.players[player.index]
    pdata.stack_unlocked = not pdata.stack_unlocked
    -- Closing the padlock must pull every column back under what is researched,
    -- otherwise the table keeps showing numbers the factory cannot reach.
    -- `effective_stack` clamps on read, so the stored values can stay as they
    -- are and come back if the padlock opens again.
    if pdata.open_entity and pdata.open_entity.valid then
      gui.open(player, pdata.open_entity)
    end
    return true
  end

  return false
end

return gui
