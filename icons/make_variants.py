#!/usr/bin/env python3
"""Derives the Catppuccin Latte icons from the Mocha ones.

The Mocha SVGs in Sources/Pika/Resources/Icons are the sources; edit
those, then run this (no dependencies) and make_icon.sh. Colours map by
name, as the Catppuccin style guide asks (Mocha Pink -> Latte Pink, and
so on), except where a colour plays a role that the name alone would
invert on a light flavour — each exception is listed in ROLE_OVERRIDES.
"""
from __future__ import annotations

import re
from pathlib import Path

ICONS = Path(__file__).resolve().parent.parent / "Sources/Pika/Resources/Icons"

# https://github.com/catppuccin/palette/blob/main/palette.json
MOCHA_TO_LATTE = {
    "#f5e0dc": "#dc8a78",  # rosewater
    "#f2cdcd": "#dd7878",  # flamingo
    "#f5c2e7": "#ea76cb",  # pink
    "#cba6f7": "#8839ef",  # mauve
    "#eba0ac": "#e64553",  # maroon
    "#fab387": "#fe640b",  # peach
    "#f9e2af": "#df8e1d",  # yellow
    "#89b4fa": "#1e66f5",  # blue
    "#b4befe": "#7287fd",  # lavender
    "#cdd6f4": "#4c4f69",  # text
    "#313244": "#ccd0da",  # surface0
    "#1e1e2e": "#eff1f5",  # base
    "#181825": "#e6e9ef",  # mantle
    "#11111b": "#dce0e8",  # crust
}
LATTE_TEXT = "#4c4f69"

# (element id, Mocha colours inside it, Latte replacements, why).
ROLE_OVERRIDES = [
    ("tile", ["#313244", "#1e1e2e", "#181825"], ["#eff1f5", "#e6e9ef", "#dce0e8"],
     "The tile is lit from the top left. Surface0 -> Base -> Mantle runs light to "
     "dark in Mocha but dark -> light -> dark in Latte, so Latte runs Base -> "
     "Mantle -> Crust instead to keep the light where it was."),
    ("fold-shade", ["#1e1e2e"], [LATTE_TEXT],
     "A translucent shadow. Base darkens in Mocha but would lighten in Latte; "
     "Text is Latte's dark ink."),
    ("eye", ["#11111b"], [LATTE_TEXT],
     "The eye is the darkest ink on the pika. Latte's Crust is a pale grey; "
     "Text keeps it dark."),
]


def element_span(svg: str, element_id: str) -> tuple[int, int] | None:
    """The source span of the element with this id, children included."""
    m = re.search(r'<(\w+)\b[^>]*\bid="%s"' % re.escape(element_id), svg)
    if not m:
        return None
    tag = m.group(1)
    open_end = svg.index(">", m.end())
    if svg[open_end - 1] == "/":
        return m.start(), open_end + 1
    close = svg.index("</%s>" % tag, open_end)
    return m.start(), close + len(tag) + 3


def to_latte(svg: str, source_name: str, prose: list[tuple[str, str]]) -> str:
    applied = []
    # Overrides first, written as placeholders so the name map below
    # can't touch them.
    for element_id, mocha, latte, why in ROLE_OVERRIDES:
        span = element_span(svg, element_id)
        if not span:
            continue
        start, end = span
        chunk = svg[start:end]
        for i, (old, new) in enumerate(zip(mocha, latte)):
            chunk = re.sub(re.escape(old), "@@%s:%d@@" % (element_id, i), chunk, flags=re.I)
        svg = svg[:start] + chunk + svg[end:]
        applied.append((element_id, mocha, latte, why))

    unknown = set(re.findall(r"#[0-9a-f]{6}\b", svg, flags=re.I)) - set(MOCHA_TO_LATTE)
    if unknown:
        raise SystemExit("%s: not a mapped Mocha colour: %s" % (source_name, ", ".join(sorted(unknown))))
    svg = re.sub(r"#[0-9a-f]{6}\b", lambda m: MOCHA_TO_LATTE[m.group(0).lower()], svg, flags=re.I)

    for element_id, _, latte, _ in applied:
        for i, new in enumerate(latte):
            svg = svg.replace("@@%s:%d@@" % (element_id, i), new)

    for old, new in prose:
        if old not in svg:
            raise SystemExit("%s: expected to find %r" % (source_name, old))
        svg = svg.replace(old, new)
    svg = svg.replace("Mocha", "Latte")

    notes = "\n".join(
        "       - #%s: %s" % (element_id, why) for element_id, _, _, why in applied
    )
    header = (
        "<!-- Generated from %s by icons/make_variants.py; edit that file\n"
        "     and rerun, not this one. Colours map Mocha -> Latte by name, except:\n%s -->\n"
        % (source_name, notes)
    )
    return re.sub(r"(<svg\b[^>]*>\n)", lambda m: m.group(1) + header, svg, count=1)


def main() -> None:
    jobs = [
        ("pika-origami-mocha.svg", "pika-origami-latte.svg",
         [("across a dark,", "across a light,")]),
        ("pika-glyph-mocha.svg", "pika-glyph-latte.svg",
         [("For dark backgrounds. pika-glyph-latte.svg is generated from\n"
           "    this file by icons/make_variants.py.", "For light backgrounds.")]),
    ]
    for source, target, prose in jobs:
        svg = (ICONS / source).read_text()
        (ICONS / target).write_text(to_latte(svg, source, prose))
        print("wrote", (ICONS / target).relative_to(ICONS.parent.parent.parent.parent))


if __name__ == "__main__":
    main()
