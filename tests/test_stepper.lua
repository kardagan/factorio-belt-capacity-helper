-- Stepper navigation: - and + walk consecutive integer levels, clamped to the
-- range the item allows.
local fails = 0
local function want(l, got, exp)
  if got ~= exp then fails = fails + 1
    print(("FAIL %-46s got %s want %s"):format(l, tostring(got), tostring(exp)))
  else print(("ok   %-46s %s"):format(l, tostring(got))) end
end

-- Mirrors the handler in gui.lua.
local function step(choices, current, delta)
  return math.max(choices[1], math.min(choices[#choices], current + delta))
end

local function range(n)
  local t = {}
  for i = 1, n do t[i] = i end
  return t
end

print("== consecutive levels ==")
local four = range(4)
want("1 +1 -> 2", step(four, 1, 1), 2)
want("2 +1 -> 3", step(four, 2, 1), 3)
want("3 +1 -> 4", step(four, 3, 1), 4)
want("3 -1 -> 2", step(four, 3, -1), 2)

print("\n== clamped at both ends ==")
want("4 +1 stays 4", step(four, 4, 1), 4)
want("1 -1 stays 1", step(four, 1, -1), 1)

print("\n== capped by the item stack size ==")
local ten = range(10)   -- an item whose stack_size is 10
want("9 +1 -> 10", step(ten, 9, 1), 10)
want("10 +1 stays 10", step(ten, 10, 1), 10)

print("\n== current value outside the range ==")
-- Happens right after the padlock closes: the stored level was 16, the list now
-- stops at 4. effective_stack already clamps on read, but the stepper must not
-- run away if it ever sees a stale value.
want("current 16, max 4, +1 -> 4", step(four, 16, 1), 4)
want("current 16, max 4, -1 -> 4", step(four, 16, -1), 4)
want("current 0, min 1, -1 -> 1", step(four, 0, -1), 1)

print("\n== single-level item (stack_size 1) ==")
local one = range(1)
want("no move up", step(one, 1, 1), 1)
want("no move down", step(one, 1, -1), 1)

print()
if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("stepper: all checks passed")
