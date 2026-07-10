#!/usr/bin/env python3
"""Generate launcher picker data (emoji.json, glyphs.json) from rofimoji's CSVs.

rofimoji ships per-block character data as CSV files:
    <char> <name> [<small>(kw, kw, ...)</small>]
This script converts a curated subset into the minified JSON the quickshell
launcher loads via FileView. Entry shape (matches Launcher.qml):
    { "e": char, "n": name, "k": "kw, kw", "g": group }

Run after a rofimoji update or when changing the curated block list:
    ./gen-glyph-data.py            # writes into ../config/
The picker data dir is discovered per python version, so this keeps working
across rofimoji/python upgrades.
"""

import glob
import json
import re
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "config"

# emoji.json: the rofimoji emoji groups; group label derived from filename.
EMOJI_FILES = [
    "emojis_activities",
    "emojis_animals_nature",
    "emojis_flags",
    "emojis_food_drink",
    "emojis_objects",
    "emojis_people_body",
    "emojis_smileys_emotion",
    "emojis_symbols",
    "emojis_travel_places",
]

# glyphs.json: curated unicode blocks + the full nerd-font PUA set.
# Keep this to a few thousand searchable entries — not all of unicode.
GLYPH_FILES = [
    "math",  # rofimoji's curated math set (operators, letters, symbols)
    "arrows",
    "supplemental_arrows-a",
    "supplemental_arrows-b",
    "miscellaneous_symbols_and_arrows",
    "general_punctuation",
    "supplemental_punctuation",
    "currency_symbols",
    "letterlike_symbols",
    "number_forms",
    "superscripts_and_subscripts",
    "latin-1_supplement",  # degree sign, section, multiplication, ...
    "alphabetic_presentation_forms",  # ligatures (ff, fi, fl, ...)
    "box_drawing",
    "block_elements",
    "geometric_shapes",
    "dingbats",
    "miscellaneous_symbols",
    "miscellaneous_technical",
    "greek_and_coptic",
    "braille_patterns",
    "nerd_font",  # PUA glyphs; name prefix (cod-, dev-, fa-, md-, ...) = icon set
]

LINE_RE = re.compile(r"^(?P<char>\S+) (?P<name>[^<]+?)(?: <small>\((?P<kw>.*)\)</small>)?\s*$")


def data_dir() -> Path:
    hits = sorted(glob.glob("/usr/lib/python3.*/site-packages/picker/data"))
    if not hits:
        sys.exit("rofimoji picker data not found under /usr/lib/python3.*")
    return Path(hits[-1])


def parse(path: Path, group: str) -> list[dict]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = LINE_RE.match(line)
        if not m:
            continue
        out.append({
            "e": m["char"],
            "n": m["name"].strip(),
            "k": m["kw"] or "",
            "g": group,
        })
    return out


def group_label(stem: str) -> str:
    if stem.startswith("emojis_"):
        return stem.removeprefix("emojis_").replace("_", " ")
    return stem.replace("_", " ").replace("-", " ")


def build(files: list[str], base: Path) -> list[dict]:
    entries, seen = [], set()
    for stem in files:
        path = base / f"{stem}.csv"
        if not path.exists():
            print(f"warn: missing {path}", file=sys.stderr)
            continue
        for e in parse(path, group_label(stem)):
            if e["e"] in seen:
                continue
            seen.add(e["e"])
            # nerd-font names are set-prefixed slugs (md-github); make the set
            # searchable as a keyword and group ("nerd md")
            if stem == "nerd_font":
                prefix = e["n"].split("-", 1)[0]
                e["g"] = f"nerd {prefix}"
            entries.append(e)
    return entries


def write(name: str, entries: list[dict]) -> None:
    out = OUT_DIR / name
    out.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{out}: {len(entries)} entries")


def main() -> None:
    base = data_dir()
    write("emoji.json", build(EMOJI_FILES, base))
    write("glyphs.json", build(GLYPH_FILES, base))


if __name__ == "__main__":
    main()
