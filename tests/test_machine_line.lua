-- Exercise the machine_line builder in isolation: it must produce a valid
-- localised-string table and stay under the 20-parameter API limit.
local function fmt_rate(n)
  if n >= 100 then return string.format("%.0f", n) end
  if n >= 10 then return string.format("%.1f", n) end
  return string.format("%.2f", n)
end

local function machine_line(machine_name, data)
  local parts = { "" }
  local function add(s) parts[#parts + 1] = s end
  add(machine_name); add(" — "); add(fmt_rate(data.crafts_per_second)); add(" crafts/s")
  local bonuses = {}
  if (data.speed_bonus or 0) ~= 0 then
    bonuses[#bonuses+1] = string.format("%+.0f%% ", data.speed_bonus*100)
    bonuses[#bonuses+1] = { "bch.bonus-speed" }
  end
  if (data.productivity or 0) ~= 0 then
    if #bonuses > 0 then bonuses[#bonuses+1] = ", " end
    bonuses[#bonuses+1] = string.format("%+.0f%% ", data.productivity*100)
    bonuses[#bonuses+1] = { "bch.bonus-productivity" }
  end
  if data.quality and data.quality ~= "normal" then
    if #bonuses > 0 then bonuses[#bonuses+1] = ", " end
    bonuses[#bonuses+1] = { "bch.bonus-quality" }
    bonuses[#bonuses+1] = " " .. data.quality
  end
  if #bonuses > 0 then
    add("  (")
    for _, b in ipairs(bonuses) do add(b) end
    add(")")
  end
  return parts
end

local function render(t)
  -- Flatten the way Factorio would, for assertion purposes.
  local out = {}
  for i = 2, #t do
    local v = t[i]
    out[#out+1] = type(v) == "table" and ("<"..v[1]..">") or tostring(v)
  end
  return table.concat(out)
end

local fails = 0
local function want(label, got, expect)
  if got ~= expect then
    fails = fails + 1
    print(("FAIL %s\n  got    %s\n  expect %s"):format(label, got, expect))
  else
    print("ok   " .. label .. "  ->  " .. got)
  end
end

local function nparams(t) return #t - 1 end

-- No bonuses at all.
local a = machine_line("Assembler 1", { crafts_per_second = 0.5 })
want("no bonus", render(a), "Assembler 1 — 0.50 crafts/s")

-- Speed only (the case Geoffrey hit: speed applied but never shown).
local b = machine_line("Medium assembler 2",
  { crafts_per_second = 0.12, speed_bonus = 0.5 })
want("speed only", render(b),
  "Medium assembler 2 — 0.12 crafts/s  (+50% <bch.bonus-speed>)")

-- Speed + productivity.
local c = machine_line("AM3",
  { crafts_per_second = 6.25, speed_bonus = 1.5, productivity = 0.4 })
want("speed + prod", render(c),
  "AM3 — 6.25 crafts/s  (+150% <bch.bonus-speed>, +40% <bch.bonus-productivity>)")

-- All three, including quality.
local d = machine_line("AM3",
  { crafts_per_second = 10, speed_bonus = 2, productivity = 0.5, quality = "legendary" })
want("speed + prod + quality", render(d),
  "AM3 — 10.0 crafts/s  (+200% <bch.bonus-speed>, +50% <bch.bonus-productivity>, <bch.bonus-quality> legendary)")
assert(nparams(d) <= 20, "must stay within the 20-parameter localised-string limit, got " .. nparams(d))
print("ok   parameter count within limit: " .. nparams(d) .. "/20")

-- normal quality must not be shown: it is the default, not a bonus.
local e = machine_line("AM2", { crafts_per_second = 1, quality = "normal" })
want("normal quality hidden", render(e), "AM2 — 1.00 crafts/s")

-- Negative speed bonus (Nullius and overhaul mods do apply penalties).
local f = machine_line("Slowed", { crafts_per_second = 0.25, speed_bonus = -0.3 })
want("negative speed bonus", render(f), "Slowed — 0.25 crafts/s  (-30% <bch.bonus-speed>)")

print()
if fails > 0 then print(fails .. " FAILED"); os.exit(1) end
print("machine_line: all checks passed")
