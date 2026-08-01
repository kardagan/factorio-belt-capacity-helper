#!/usr/bin/env python3
"""Validate the locale files and cross-check them against the Lua sources.

Catches, in order of how badly they break the game:
  1. a line that is neither a section, a comment, a blank, nor `key=value`
     (Factorio refuses to load the mod: "Missing value at ...")
  2. a real newline inside a value, which is what produces case 1 — locale files
     want the two characters \\n, never an actual line break
  3. a key used from Lua but absent from a locale file (renders as the raw key)
  4. a key defined but never used (dead weight)
  5. keys present in one language but not the other
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = sorted((ROOT / "locale").glob("*/strings.cfg"))
LUA = [ROOT / "control.lua"] + sorted((ROOT / "scripts").glob("*.lua"))

KEY_RE = re.compile(r"^([A-Za-z0-9_.-]+)=(.*)$")
SECTION_RE = re.compile(r"^\[([^\]]+)\]$")

errors: list[str] = []
warnings: list[str] = []
per_file_keys: dict[Path, set[str]] = {}


def parse(path: Path) -> set[str]:
    keys: set[str] = set()
    section = None
    for lineno, raw in enumerate(path.read_text(encoding="utf8").splitlines(), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith(";"):
            continue
        if SECTION_RE.match(line.strip()):
            section = SECTION_RE.match(line.strip()).group(1)
            continue
        m = KEY_RE.match(line)
        if not m:
            errors.append(
                f"{path.relative_to(ROOT)}:{lineno}: not a key=value line -> {line!r}\n"
                f"    Factorio will refuse to load the mod. A value must never contain a\n"
                f"    real line break: write the two characters \\n instead."
            )
            continue
        key, value = m.group(1), m.group(2)
        if section == "bch":
            keys.add(key)
        # A trailing backslash means the value was cut across lines.
        if value.endswith("\\"):
            errors.append(
                f"{path.relative_to(ROOT)}:{lineno}: value ends with a bare backslash"
            )
    return keys


for path in LOCALES:
    per_file_keys[path] = parse(path)

# Keys referenced from Lua as {"bch.<key>"}.
used: set[str] = set()
for lua in LUA:
    used |= set(re.findall(r'"bch\.([A-Za-z0-9_-]+)"', lua.read_text(encoding="utf8")))

for path, keys in per_file_keys.items():
    rel = path.relative_to(ROOT)
    for missing in sorted(used - keys):
        errors.append(f"{rel}: missing key used from Lua -> bch.{missing}")
    for dead in sorted(keys - used):
        warnings.append(f"{rel}: key defined but never used -> bch.{dead}")

# Every language must define the same set.
if len(per_file_keys) > 1:
    reference = max(per_file_keys.values(), key=len)
    for path, keys in per_file_keys.items():
        for missing in sorted(reference - keys):
            errors.append(
                f"{path.relative_to(ROOT)}: key present in another language but missing here"
                f" -> bch.{missing}"
            )

for w in warnings:
    print(f"warn  {w}")
for e in errors:
    print(f"FAIL  {e}")

if errors:
    sys.exit(1)

total = len(next(iter(per_file_keys.values()))) if per_file_keys else 0
print(f"ok    locale: {len(LOCALES)} file(s), {total} keys, all used and consistent")
