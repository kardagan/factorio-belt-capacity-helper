#!/usr/bin/env python3
"""Generate the shortcut icons: a stylised belt with flow chevrons.

Factorio shortcut icons are white-on-transparent; the game tints them for the
enabled / disabled / hovered states. Sizes x56 and x24 mirror the vanilla set.
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "graphics")
os.makedirs(OUT, exist_ok=True)

W = (255, 255, 255, 255)
DIM = (255, 255, 255, 110)


def draw(size, chevrons=True):
    """Belt seen from above, split into two lanes.

    `chevrons` is dropped at 24px: the flow arrows turn into mush at that size,
    so the small icon keeps only the silhouette and the lane split.
    """
    # Supersample 8x, then downscale: gives clean antialiased edges.
    s = size * 8
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    u = s / 56.0          # design on a 56px grid
    lw = max(1, int((3.5 if chevrons else 4.5) * u))

    # Belt body: a horizontal band with rounded ends.
    top, bot = 14 * u, 42 * u
    left, right = 5 * u, 51 * u
    d.rounded_rectangle([left, top, right, bot], radius=4 * u, outline=W, width=lw)

    mid = (top + bot) / 2

    if chevrons:
        d.line([left + 4 * u, mid, right - 4 * u, mid], fill=DIM,
               width=max(1, int(2 * u)))
        # One pair of chevrons per lane, pointing right.
        for cy in (top + 7 * u, bot - 7 * u):
            for cx in (22 * u, 36 * u):
                d.line([cx - 4 * u, cy - 4.5 * u, cx + 3 * u, cy], fill=W, width=lw)
                d.line([cx + 3 * u, cy, cx - 4 * u, cy + 4.5 * u], fill=W, width=lw)
    else:
        # Full-strength separator: at 24px it is the only thing that still reads,
        # and it is what distinguishes a belt from a plain rectangle.
        d.line([left, mid, right, mid], fill=W, width=lw)
        # A single arrowhead keeps a sense of direction without clutter.
        cx, cy = 38 * u, mid
        head = 7 * u
        d.line([cx - head, cy - head, cx, cy], fill=W, width=lw)
        d.line([cx, cy, cx - head, cy + head], fill=W, width=lw)

    return img.resize((size, size), Image.LANCZOS)


BELT_BODY = (78, 74, 70, 255)
BELT_EDGE = (150, 146, 140, 255)
CHEVRON = (240, 184, 32, 255)
RAIL_ON = (245, 245, 245, 255)
RAIL_OFF = (245, 245, 245, 60)


def draw_lanes(size, lanes):
    """Belt seen from above, running vertically, in the in-game colours.

    A white rail beside a lane means that lane feeds the machine. With `lanes`
    set to 1 only the right rail lights up; with 2 both do. Modelled on the
    reference image rather than the earlier abstract outline, so the button reads
    as a belt at a glance.
    """
    s = size * 8
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    u = s / 32.0

    # Belt body, centred, with room for a rail on each side.
    bx0, bx1 = 9 * u, 23 * u
    by0, by1 = 2 * u, 30 * u
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=1.5 * u,
                        fill=BELT_BODY, outline=BELT_EDGE, width=max(1, int(1.2 * u)))

    # Chevrons pointing up, the way items travel.
    cw = max(1, int(2.2 * u))
    cx = (bx0 + bx1) / 2
    half = 4.2 * u
    y = by0 + 5 * u
    while y < by1 - 2 * u:
        d.line([cx - half, y, cx, y - 3 * u], fill=CHEVRON, width=cw)
        d.line([cx, y - 3 * u, cx + half, y], fill=CHEVRON, width=cw)
        y += 6.5 * u

    # Side rails: lit when that lane is in use.
    rw = 2.4 * u
    for x0, lit in ((3.2 * u, lanes == 2), (26.4 * u, True)):
        d.rounded_rectangle([x0, by0, x0 + rw, by1], radius=0.8 * u,
                            fill=RAIL_ON if lit else RAIL_OFF)

    return img.resize((size, size), Image.LANCZOS)


def draw_lock(size, closed):
    """Padlock for the titlebar: closed = numbers follow your research,
    open = planning mode, showing levels you have not researched yet."""
    s = size * 8
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    u = s / 32.0
    lw = max(1, int(2.5 * u))

    # Body.
    bx0, bx1 = 8 * u, 24 * u
    by0, by1 = 15 * u, 27 * u
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=2 * u, outline=W, width=lw)
    # Keyhole.
    cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
    d.ellipse([cx - 2 * u, cy - 2.5 * u, cx + 2 * u, cy + 1.5 * u], outline=W, width=lw)

    # Shackle: centred when closed, hinged to the left and open otherwise.
    if closed:
        d.arc([11 * u, 6 * u, 21 * u, 19 * u], start=180, end=360, fill=W, width=lw)
        d.line([11 * u, 12.5 * u, 11 * u, by0], fill=W, width=lw)
        d.line([21 * u, 12.5 * u, 21 * u, by0], fill=W, width=lw)
    else:
        d.arc([4 * u, 5 * u, 14 * u, 18 * u], start=180, end=360, fill=W, width=lw)
        d.line([4 * u, 11.5 * u, 4 * u, 15 * u], fill=W, width=lw)
        d.line([14 * u, 11.5 * u, 14 * u, by0], fill=W, width=lw)

    return img.resize((size, size), Image.LANCZOS)


for size, chevrons in ((56, True), (24, False)):
    path = os.path.join(OUT, f"belt-capacity-x{size}.png")
    draw(size, chevrons).save(path)
    print("wrote", os.path.normpath(path))

for lanes in (1, 2):
    path = os.path.join(OUT, f"lanes-{lanes}.png")
    draw_lanes(32, lanes).save(path)
    print("wrote", os.path.normpath(path))

for closed, name in ((True, "lock-closed"), (False, "lock-open")):
    path = os.path.join(OUT, f"{name}.png")
    draw_lock(32, closed).save(path)
    print("wrote", os.path.normpath(path))

# Mod portal thumbnail: 144x144, derived from the full-resolution artwork kept
# in assets/ so the published image can be regenerated rather than hand-resized.
ROOT = os.path.dirname(OUT)
source = os.path.join(ROOT, "assets", "thumbnail-source.png")
if os.path.exists(source):
    out = os.path.join(ROOT, "thumbnail.png")
    Image.open(source).convert("RGBA").resize((144, 144), Image.LANCZOS).save(out)
    print("wrote", os.path.normpath(out))
