#!/usr/bin/env python3
"""Validate a built mod zip against what the Factorio mod portal expects.

The portal rejects an upload outright on any of these, with an error message
that rarely says which one:
  - more than one top-level directory, or a name that is not `<name>_<version>`
  - a missing or malformed info.json (version must be X.Y.Z)
  - a thumbnail that is not 144x144

Everything else is reported as a warning: shipping dev files bloats the download
without breaking anything.
"""
import io
import json
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image

REQUIRED_FIELDS = ("name", "version", "title", "author", "factorio_version")
THUMB_SIZE = (144, 144)

path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
if not path or not path.exists():
    print(f"FAIL  no such zip: {path}")
    sys.exit(1)

errors: list[str] = []
warnings: list[str] = []

zf = zipfile.ZipFile(path)
names = zf.namelist()

roots = {n.split("/")[0] for n in names}
if len(roots) != 1:
    print(f"FAIL  the zip must hold exactly one top-level directory, found: {sorted(roots)}")
    sys.exit(1)
root = next(iter(roots))

info_path = f"{root}/info.json"
if info_path not in names:
    errors.append(f"info.json missing at {info_path}")
else:
    try:
        info = json.loads(zf.read(info_path))
    except json.JSONDecodeError as exc:
        errors.append(f"info.json is not valid JSON: {exc}")
        info = {}

    for field in REQUIRED_FIELDS:
        if not info.get(field):
            errors.append(f"info.json: required field missing -> {field}")

    if info.get("name") and info.get("version"):
        expected = f"{info['name']}_{info['version']}"
        if root != expected:
            errors.append(f"directory is {root!r}, the portal requires {expected!r}")

    version = info.get("version", "")
    if version and not re.fullmatch(r"\d+\.\d+\.\d+", version):
        errors.append(f"version must be X.Y.Z, got {version!r}")

for required in ("control.lua", "data.lua"):
    if f"{root}/{required}" not in names:
        errors.append(f"{required} missing")

thumb = f"{root}/thumbnail.png"
if thumb not in names:
    warnings.append("no thumbnail.png: the portal will show a placeholder")
else:
    size = Image.open(io.BytesIO(zf.read(thumb))).size
    if size != THUMB_SIZE:
        errors.append(f"thumbnail.png is {size[0]}x{size[1]}, the portal requires 144x144")

for name in names:
    if "/tests/" in name or name.endswith((".py", "Makefile", ".gitignore")):
        warnings.append(f"development file shipped: {name}")

total = sum(zf.getinfo(n).file_size for n in names)
print(f"      {path.name}: {len(names)} entries, {total // 1024} KiB uncompressed")

for w in warnings:
    print(f"warn  {w}")
for e in errors:
    print(f"FAIL  {e}")

if errors:
    sys.exit(1)
print(f"ok    package: {root} is portal-ready")
