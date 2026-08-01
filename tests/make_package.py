#!/usr/bin/env python3
"""Package the mod for Factorio 2.0 and 2.1 from a single source tree.

The Lua, graphics and locale files are identical for both game branches; only
info.json differs (factorio_version and the base dependency floor). So both zips
are derived from the same content, with info.json rewritten per target.

Version convention — the MINOR encodes the game branch:

    info.json carries the canonical semver, which is the Factorio 2.0 release.
    The 2.1 release is the same code with MINOR + 1.
    => even minor (0, 2, 4, …) = Factorio 2.0 channel
       odd  minor (1, 3, 5, …) = Factorio 2.1 channel

    A fix bumps PATCH on both channels: 1.0.0 -> 1.0.1 and 1.1.0 -> 1.1.1, so
    PATCH stays free for fixes on either side.

    COLLISION WARNING: for a feature release, advance the canonical MINOR by at
    least 2 (1.0.x -> 1.2.x), so the derived 2.1 version (1.3.x) never reuses an
    odd minor that already shipped (1.1.x).

    When 2.0 support is dropped, remove that target and the mod goes back to
    plain continuous versioning.

This mirrors the scheme used by smart-train-combinator.
"""
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_NAME = "BeltCapacityHelper"
DIST = ROOT / "build"

# Allowlist: dev files (tests/, assets/, Makefile, .git) are never shipped.
CONTENTS = [
    "info.json",
    "control.lua",
    "data.lua",
    "settings.lua",
    "scripts",
    "prototypes",
    "locale",
    "graphics",
    "thumbnail.png",
    "LICENSE",
    "README.md",
]

# (game version, base dependency floor, minor offset)
TARGETS = [
    ("2.0", "2.0.0", 0),
    ("2.1", "2.1.0", 1),
]


def canonical_version() -> str:
    """The semver in info.json, which is the Factorio 2.0 release.

    Refuses an odd minor: the whole scheme rests on the canonical version being
    the even-minor channel, so an odd one would silently publish a 2.0 zip under
    a number that reads as 2.1 — and would collide with a real 2.1 release.
    """
    version = json.loads((ROOT / "info.json").read_text())["version"]
    minor = int(version.split(".")[1])
    if minor % 2 != 0:
        raise SystemExit(
            f"FAIL  info.json version {version} has an odd minor.\n"
            f"      The canonical version is the Factorio 2.0 channel and must\n"
            f"      use an even minor; the 2.1 release is derived as minor + 1.\n"
            f"      Use {version.split('.')[0]}.{minor + 1}.0 or "
            f"{version.split('.')[0]}.{minor - 1}.0 instead."
        )
    return version


def bump_minor(version: str, offset: int) -> str:
    major, minor, patch = version.split(".")
    return f"{major}.{int(minor) + offset}.{patch}"


def rewrite_info(path: Path, mod_version: str, game_version: str, base_min: str) -> None:
    """Retarget a staged info.json. Optional dependencies are left untouched."""
    data = json.loads(path.read_text())
    data["version"] = mod_version
    data["factorio_version"] = game_version
    data["dependencies"] = [
        f"base >= {base_min}" if d.strip().startswith("base") else d
        for d in data.get("dependencies", [])
    ]
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def build() -> int:
    base_version = canonical_version()
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir(parents=True)

    failed = False
    for game_version, base_min, offset in TARGETS:
        mod_version = bump_minor(base_version, offset)
        stage = DIST / f"{MOD_NAME}_{mod_version}"
        stage.mkdir()

        for item in CONTENTS:
            src = ROOT / item
            if not src.exists():
                print(f"warn  missing from the source tree, skipped: {item}")
                continue
            if src.is_dir():
                shutil.copytree(src, stage / item)
            else:
                shutil.copy2(src, stage / item)

        rewrite_info(stage / "info.json", mod_version, game_version, base_min)

        archive = DIST / f"{MOD_NAME}_{mod_version}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for file in sorted(stage.rglob("*")):
                if file.is_file():
                    zf.write(file, file.relative_to(DIST))
        shutil.rmtree(stage)

        check = subprocess.run(
            [sys.executable, str(ROOT / "tests" / "check_package.py"), str(archive)]
        )
        if check.returncode != 0:
            failed = True

        print(f"  -> build/{archive.name}   (Factorio {game_version})")

    if failed:
        print("\nFAIL  at least one archive is not portal-ready")
        return 1

    print(f"\nok    packaged both channels from canonical version {base_version}")
    return 0


if __name__ == "__main__":
    sys.exit(build())
