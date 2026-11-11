#!/usr/bin/env python3
"""Generates MenuMines' Icon Composer documents (AppIcon.icon, AppIcon-Dev.icon).

Usage: scripts/make_app_icon.py [output-directory]   (default: MenuMines/Resources)

Run it after changing the artwork or colours below, then build. Icon Composer can open the
generated documents, and `ictool` (inside Icon Composer.app) renders them for a quick look.

The design follows the original flat icon: a classic grey board of bevelled tiles in a dark
graphite surround, one opened cell with a blue 1 and a red flag on the tile beside it. It's
layered so macOS 26 can render it in Liquid Glass and in the dark, tinted and clear
appearances: a gradient fill, the board plate, the tiles, the 1, and the flag in front. The
Dev variant changes only the colours.
"""

import json
import pathlib
import shutil
import sys

CANVAS = 1024
GRID = 4
PLATE_INSET = 104
PLATE = CANVAS - 2 * PLATE_INSET  # 816
PLATE_RADIUS = 64
PAD = 18
GAP = 10
TILE = (PLATE - 2 * PAD - (GRID - 1) * GAP) // GRID  # 187
ORIGIN = PLATE_INSET + (PLATE - (GRID * TILE + (GRID - 1) * GAP)) // 2
BEVEL = 18
RADIUS = 12

# The opened cell, and the covered cell beside it that holds the flag. The 1 is honest: the
# flagged cell is its only mine.
OPENED = [(1, 1)]
FLAG_CELL = (1, 2)


def cell_origin(row, col):
    return ORIGIN + col * (TILE + GAP), ORIGIN + row * (TILE + GAP)


def svg(body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'
    )


def plate_svg(fill):
    return svg(
        f'<rect x="{PLATE_INSET}" y="{PLATE_INSET}" width="{PLATE}" height="{PLATE}" '
        f'rx="{PLATE_RADIUS}" fill="{fill}"/>'
    )


def raised_tile(x, y, v):
    """A classic Minesweeper tile: light top and left edges, dark bottom and right, flat face."""
    t, b = TILE, BEVEL
    return (
        f'<rect x="{x}" y="{y}" width="{t}" height="{t}" rx="{RADIUS}" fill="{v["shadow"]}"/>'
        f'<path d="M {x + RADIUS} {y} H {x + t - RADIUS} L {x + t - b} {y + b} H {x + b} '
        f'V {y + t - b} L {x} {y + t - RADIUS} V {y + RADIUS} '
        f'Q {x} {y} {x + RADIUS} {y} Z" fill="{v["highlight"]}"/>'
        f'<rect x="{x + b}" y="{y + b}" width="{t - 2 * b}" height="{t - 2 * b}" rx="4" '
        f'fill="{v["face"]}"/>'
    )


def covered_svg(v):
    cells = [(r, c) for r in range(GRID) for c in range(GRID) if (r, c) not in OPENED]
    return svg("".join(raised_tile(*cell_origin(r, c), v) for r, c in cells))


def opened_svg(v):
    rects = "".join(
        f'<rect x="{x}" y="{y}" width="{TILE}" height="{TILE}" rx="{RADIUS}" fill="{v["opened"]}" '
        f'stroke="{v["opened_edge"]}" stroke-width="6"/>'
        for x, y in (cell_origin(r, c) for r, c in OPENED)
    )
    return svg(rects)


def one_path(cx, cy):
    """A bold "1" centred on (cx, cy), drawn as a path so no font is needed."""
    pts = [
        (cx + 16, cy - 66),   # top right of stem
        (cx + 16, cy + 44),   # stem bottom right, above foot
        (cx + 48, cy + 44),
        (cx + 48, cy + 68),   # foot
        (cx - 50, cy + 68),
        (cx - 50, cy + 44),
        (cx - 20, cy + 44),   # stem bottom left
        (cx - 20, cy - 24),   # stem left, under the stroke
        (cx - 46, cy - 12),   # flag stroke
        (cx - 56, cy - 38),
        (cx - 10, cy - 66),   # top left
    ]
    d = "M " + " L ".join(f"{x} {y}" for x, y in pts) + " Z"
    return f'<path d="{d}" stroke-linejoin="round"/>'


def ones_svg(fill):
    paths = "".join(
        one_path(x + TILE // 2, y + TILE // 2) for x, y in (cell_origin(r, c) for r, c in OPENED)
    )
    return svg(f'<g fill="{fill}" stroke="{fill}" stroke-width="8">{paths}</g>')


def flag_svg(cloth, pole):
    x, y = cell_origin(*FLAG_CELL)
    # Stands on its tile's face, as on the board: a pole, a stepped base and a pennant.
    pole_x = x + 66
    top = y + 26
    base_y = y + TILE - 40
    cloth_path = (
        f"M {pole_x + 6} {top + 2} "
        f"L {x + TILE - 22} {top + 50} "
        f"L {pole_x + 6} {top + 98} Z"
    )
    return svg(
        f'<rect x="{pole_x - 8}" y="{top}" width="18" height="{base_y - top}" rx="9" fill="{pole}"/>'
        f'<rect x="{pole_x - 32}" y="{base_y - 16}" width="64" height="18" rx="6" fill="{pole}"/>'
        f'<rect x="{pole_x - 52}" y="{base_y}" width="104" height="22" rx="8" fill="{pole}"/>'
        f'<path d="{cloth_path}" fill="{cloth}" stroke="{cloth}" stroke-width="8" stroke-linejoin="round"/>'
    )


def color(r, g, b, a=1.0):
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


BOARD = {
    "plate": "#9AA0A9",
    "highlight": "#FFFFFF",
    "face": "#DCDFE4",
    "shadow": "#8C939D",
    "opened": "#C9CDD3",
    "opened_edge": "#AEB4BC",
}

VARIANTS = {
    # The graphite surround is the original icon's bezel.
    "AppIcon": {
        **BOARD,
        "fill": color(0.25, 0.27, 0.31),
        "fill_dark": color(0.13, 0.14, 0.16),
        "one": "#1D4ED8",
        "cloth": "#E5322B",
        "pole": "#2B2F38",
    },
    # Debug builds use a different icon so they can't be mistaken for a real install.
    "AppIcon-Dev": {
        **BOARD,
        "fill": color(0.92, 0.50, 0.10),
        "fill_dark": color(0.50, 0.24, 0.03),
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

    (assets / "plate.svg").write_text(plate_svg(v["plate"]))
    (assets / "covered.svg").write_text(covered_svg(v))
    (assets / "opened.svg").write_text(opened_svg(v))
    (assets / "ones.svg").write_text(ones_svg(v["one"]))
    (assets / "flag.svg").write_text(flag_svg(v["cloth"], v["pole"]))

    icon = {
        "fill-specializations": [
            {"value": {"automatic-gradient": v["fill"]}},
            {"appearance": "dark", "value": {"automatic-gradient": v["fill_dark"]}},
        ],
        # Front to back. The tiles keep their drawn bevels rather than turning to glass, so
        # the board still reads as Minesweeper; the system adds its light on top.
        "groups": [
            {
                "name": "Flag",
                "layers": [
                    {"name": "Flag", "image-name": "flag.svg", "glass": False,
                     "fill-specializations": TINTED_WHITE},
                    {"name": "Ones", "image-name": "ones.svg", "glass": False,
                     "fill-specializations": TINTED_WHITE},
                ],
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": False, "value": 0.5},
                "specular": False,
            },
            {
                "name": "Board",
                "layers": [
                    {"name": "Opened", "image-name": "opened.svg", "glass": False,
                     "opacity-specializations": TINTED_FADE},
                    {"name": "Covered", "image-name": "covered.svg", "glass": False,
                     "opacity-specializations": TINTED_FADE},
                    {"name": "Plate", "image-name": "plate.svg", "glass": False,
                     "opacity-specializations": TINTED_FADE},
                ],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": False, "value": 0.3},
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
