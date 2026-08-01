-- Per-item stacking override: the padlock clamp, the item stack_size cap, and
-- how a per-column value interacts with the global one.
local fails = 0
local function want(l, got, exp)
  if got ~= exp then
    fails = fails + 1
    print(("FAIL %-50s got %s  want %s"):format(l, tostring(got), tostring(exp)))
  else print(("ok   %-50s %s"):format(l, tostring(got))) end
end

local ITEMS = { coal={stack_size=50}, engine={stack_size=10}, silo={stack_size=1} }

local function mk(bonus, unlocked, global_override, per_item)
  return { bonus=bonus, unlocked=unlocked, global_override=global_override,
           items=per_item or {} }
end

local function effective_stack(p, item)
  -- Defaults to 1, not to the researched level.
  local level = p.items[item] or 1
  if not p.unlocked then level = math.min(level, 1 + p.bonus) end
  local cap = ITEMS[item] and ITEMS[item].stack_size or 1
  return math.max(1, math.min(level, cap))
end

local function item_choices(p, item)
  local top = p.unlocked and 16 or (1 + p.bonus)
  top = math.min(top, ITEMS[item] and ITEMS[item].stack_size or 1)
  local out = {}
  for n = 1, math.max(1, top) do out[#out+1] = n end
  return out
end

local function join(t)
  local s={} for _,v in ipairs(t) do s[#s+1]=tostring(v) end return table.concat(s,",")
end

print("== locked: per-item override cannot exceed research ==")
local locked = mk(3, false, nil, { coal = 16 })
want("coal overridden to 16 but locked at 4", effective_stack(locked, "coal"), 4)
want("untouched item defaults to 1", effective_stack(locked, "engine"), 1)

print("\n== locked: per-item override BELOW research is honoured ==")
local low = mk(3, false, nil, { coal = 1 })
want("coal forced to 1 while research is 4", effective_stack(low, "coal"), 1)
want("engine still at default 1", effective_stack(low, "engine"), 1)

print("\n== unlocked: per-item override is free ==")
local free = mk(3, true, nil, { coal = 16, engine = 8 })
want("coal at 16 (stack 50)", effective_stack(free, "coal"), 16)
want("engine at 8 capped by stack 10", effective_stack(free, "engine"), 8)
want("silo never stacks", effective_stack(free, "silo"), 1)

print("\n== global override + per-item override ==")
local both = mk(3, true, 8, { coal = 2 })
want("per-item value is used", effective_stack(both, "coal"), 2)
want("no per-item -> default 1", effective_stack(both, "engine"), 1)

print("\n== choices offered per item ==")
want("locked, bonus 3, coal", join(item_choices(mk(3,false), "coal")), "1,2,3,4")
want("unlocked, coal (stack 50)", join(item_choices(mk(3,true), "coal")), "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16")
-- stack_size 10 must stop at 10, and expose it as the top entry.
want("unlocked, engine (stack 10)", join(item_choices(mk(3,true), "engine")), "1,2,3,4,5,6,7,8,9,10")
-- A single choice means no selector at all.
want("silo offers a single level", join(item_choices(mk(3,true), "silo")), "1")

print()
if fails > 0 then print(fails.." FAILED"); os.exit(1) end
print("per-item stacking: all checks passed")
