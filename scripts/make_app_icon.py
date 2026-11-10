#!/usr/bin/env python3
"""Generates MenuMines' Icon Composer documents (AppIcon.icon, AppIcon-Dev.icon).

Usage: scripts/make_app_icon.py [output-directory]   (default: MenuMines/Resources)

Run it after changing the artwork or colours below, then build. Icon Composer can open the
generated documents, and `ictool` (inside Icon Composer.app) renders them for a quick look.

Each document is layered so macOS 26 can render it in Liquid Glass and in the dark, tinted
and clear appearances: a gradient fill, a 3x3 block of tiles, two opened tiles showing "1",
and a red flag in front. The Dev variant changes only the colours.
"""

import json
import pathlib
import shutil
import sys

CANVAS = 1024
TILE = 214
GAP = 26
ORIGIN = (CANVAS - (3 * TILE + 2 * GAP)) // 2  # 166
RADIUS = 44

# Opened cells; every other cell is covered. The flag sits in the middle, so the opened
# cells either side of it honestly read 1.
OPENED = [(1, 0), (1, 2)]
FLAG_CELL = (1, 1)


def cell_origin(row, col):
    return ORIGIN + col * (TILE + GAP), ORIGIN + row * (TILE + GAP)


def svg(body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'
    )


def tiles_svg(cells, fill):
    rects = "".join(
        f'<rect x="{x}" y="{y}" width="{TILE}" height="{TILE}" rx="{RADIUS}" fill="{fill}"/>'
        for x, y in (cell_origin(r, c) for r, c in cells)
    )
    return svg(rects)


def one_path(cx, cy):
    """A bold "1" centred on (cx, cy), drawn as a path so no font is needed."""
    # Stem 52 wide, 150 tall, with a flag stroke to the upper left and a foot bar.
    pts = [
        (cx + 18, cy - 82),   # top right of stem
        (cx + 18, cy + 56),   # stem bottom right, above foot
        (cx + 58, cy + 56),
        (cx + 58, cy + 86),   # foot
        (cx - 62, cy + 86),
        (cx - 62, cy + 56),
        (cx - 26, cy + 56),   # stem bottom left
        (cx - 26, cy - 30),   # stem left, under the stroke
        (cx - 58, cy - 14),   # flag stroke
        (cx - 70, cy - 46),
        (cx - 14, cy - 82),   # top left
    ]
    d = "M " + " L ".join(f"{x} {y}" for x, y in pts) + " Z"
    return f'<path d="{d}" stroke-linejoin="round"/>'


def ones_svg(fill):
    paths = "".join(
        one_path(x + TILE // 2, y + TILE // 2) for x, y in (cell_origin(r, c) for r, c in OPENED)
    )
    return svg(f'<g fill="{fill}" stroke="{fill}" stroke-width="10">{paths}</g>')


def flag_svg(cloth, pole):
    x, y = cell_origin(*FLAG_CELL)
    # The flag is the thing the icon is about and has to read at 16pt, so it's a little
    # bigger than its tile and stands up out of it.
    pole_x = x + 76
    top = y - 30
    bottom = y + TILE - 30
    cloth_path = (
        f"M {pole_x + 12} {top + 8} "
        f"L {x + TILE + 6} {top + 82} "
        f"L {pole_x + 12} {top + 156} Z"
    )
    return svg(
        f'<rect x="{pole_x - 16}" y="{top}" width="32" height="{bottom - top}" rx="16" fill="{pole}"/>'
        f'<rect x="{pole_x - 58}" y="{bottom - 30}" width="150" height="46" rx="23" fill="{pole}"/>'
        f'<path d="{cloth_path}" fill="{cloth}" stroke="{cloth}" stroke-width="16" stroke-linejoin="round"/>'
    )


def color(r, g, b, a=1.0):
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


VARIANTS = {
    "AppIcon": {
        "fill": color(0.13, 0.42, 0.98),
        "fill_dark": color(0.05, 0.16, 0.45),
        "covered": "#F4F6FA",
        "opened": "#C7D3EA",
        "one": "#1D4ED8",
        "cloth": "#F23B30",
        "pole": "#2B2F38",
    },
    # Debug builds use a different icon so they can't be mistaken for a real install.
    "AppIcon-Dev": {
        "fill": color(0.98, 0.58, 0.12),
        "fill_dark": color(0.50, 0.24, 0.03),
        "covered": "#FBF6EF",
        "opened": "#EFD9BC",
        "one": "#B45309",
        "cloth": "#16A34A",
        "pole": "#2B2F38",
    },
}


# The tinted appearances colour by brightness, so the dark flag and numbers would sink into
# the tiles. There they're drawn white, which the tint then colours.
TINTED_WHITE = [
    {"appearance": "tinted", "value": {"solid": "extended-gray:1.00000,1.00000"}},
]


# ...and the tiles behind them fade, so there's still something for the white to stand out from.
TINTED_FADE = [{"appearance": "tinted", "value": 0.3}]


def write_document(out_dir, name, v):
    doc = out_dir / f"{name}.icon"
    # Start clean, so a layer removed here doesn't linger in the document.
    if doc.exists():
        shutil.rmtree(doc)
    assets = doc / "Assets"
    assets.mkdir(parents=True, exist_ok=True)

    covered = [(r, c) for r in range(3) for c in range(3) if (r, c) not in OPENED]
    (assets / "covered.svg").write_text(tiles_svg(covered, v["covered"]))
    (assets / "opened.svg").write_text(tiles_svg(OPENED, v["opened"]))
    (assets / "ones.svg").write_text(ones_svg(v["one"]))
    (assets / "flag.svg").write_text(flag_svg(v["cloth"], v["pole"]))

    icon = {
        "fill-specializations": [
            {"value": {"automatic-gradient": v["fill"]}},
            {"appearance": "dark", "value": {"automatic-gradient": v["fill_dark"]}},
        ],
        # Front to back.
        "groups": [
            {
                "name": "Flag",
                "layers": [{"name": "Flag", "image-name": "flag.svg", "glass": True,
                            "fill-specializations": TINTED_WHITE}],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.5},
                "specular": True,
            },
            {
                "name": "Board",
                "layers": [
                    {"name": "Ones", "image-name": "ones.svg", "glass": False,
                     "fill-specializations": TINTED_WHITE},
                    {"name": "Opened", "image-name": "opened.svg", "glass": True,
                     "opacity-specializations": TINTED_FADE},
                    {"name": "Covered", "image-name": "covered.svg", "glass": True,
                     "opacity-specializations": TINTED_FADE},
                ],
                "shadow": {"kind": "neutral", "opacity": 0.4},
                "translucency": {"enabled": True, "value": 0.3},
                "specular": True,
            },
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (doc / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
    return doc


def main():
    default = pathlib.Path(__file__).resolve().parent.parent / "MenuMines" / "Resources"
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else default
    for name, v in VARIANTS.items():
        print(write_document(out_dir, name, v))


if __name__ == "__main__":
    main()
