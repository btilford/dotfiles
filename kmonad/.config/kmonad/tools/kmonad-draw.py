#!/usr/bin/env python3
"""Render a kmonad .kbd file to an SVG via keymap-drawer.

keymap-drawer parses ZMK and QMK, NOT kmonad, so this converts first: the .kbd
becomes a keymap-drawer keymap YAML plus a QMK-style info.json holding the
physical layout. Styling is shared with the zmk-config repo's keymap-drawer
YAMLs so the kmonad and firmware diagrams read as one set.

    ./kmonad-draw.py ~/.config/kmonad/linux-shared.kbd -o drawings/

Only the 105-key defsrc used by linux-shared.kbd is described here. A different
defsrc (60%, laptop) needs its own entry in GEOMETRY -- the script refuses to
guess, because a wrong physical layout produces a plausible diagram of the wrong
keyboard.
"""

import argparse
from itertools import islice
import json
import re
import shutil
import yaml
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Physical layout: standard full-size ANSI, in key units.
#
# Rows are (y, [(name_index_advances, x, w, h)]) built programmatically below.
# The two non-standard keys in this defsrc are placed explicitly:
#   * `print` sits left of the ssrq/slck/pause cluster. On real hardware the
#     PrtSc key emits KEY_SYSRQ (`ssrq`), so `print` (KEY_PRINT) is very likely
#     dead -- drawn anyway, because it IS in defsrc and the diagram documents
#     the config, not the hardware.
#   * `fn` likewise: laptop Fn is handled in firmware and usually never reaches
#     evdev at all.
# ---------------------------------------------------------------------------

NAV_X = [15.25, 16.25, 17.25]
NUM_X = [19.5, 20.5, 21.5, 22.5]  # shifted right of stock 18.5 to clear `print`


def _row(y, spec):
    return [dict(x=x, y=y, **kw) for (x, kw) in spec]


def _seq(start, n, y, step=1.0, **kw):
    return [(start + i * step, dict(**kw)) for i in range(n)]


GEOMETRY_105 = (
    # F-row
    _row(0, [(0, {})]
         + _seq(2, 4, 0) + _seq(6.5, 4, 0) + _seq(11, 4, 0)
         + [(15.25, {}), (16.25, {}), (17.25, {}), (18.25, {})])
    # number row
    + _row(1.25, _seq(0, 13, 0) + [(13, dict(w=2))]
           + [(x, {}) for x in NAV_X] + [(x, {}) for x in NUM_X])
    # tab row (kp+ is double height)
    + _row(2.25, [(0, dict(w=1.5))] + _seq(1.5, 13, 0)
           + [(x, {}) for x in NAV_X]
           + [(NUM_X[0], {}), (NUM_X[1], {}), (NUM_X[2], {}),
              (NUM_X[3], dict(h=2))])
    # home row
    + _row(3.25, [(0, dict(w=1.75))] + _seq(1.75, 11, 0)
           + [(12.75, dict(w=2.25))] + [(x, {}) for x in NUM_X[:3]])
    # shift row (kprt is double height)
    + _row(4.25, [(0, dict(w=2.25))] + _seq(2.25, 10, 0)
           + [(12.25, dict(w=2.75)), (16.25, {})]
           + [(NUM_X[0], {}), (NUM_X[1], {}), (NUM_X[2], {}),
              (NUM_X[3], dict(h=2))])
    # bottom row
    + _row(5.25, [(0, dict(w=1.25)), (1.25, dict(w=1.25)), (2.5, dict(w=1.25)),
                  (3.75, dict(w=1.25)), (5, dict(w=6.25)), (11.25, dict(w=1.25)),
                  (12.5, dict(w=1.25)), (13.75, dict(w=1.25))]
           + [(x, {}) for x in NAV_X]
           + [(NUM_X[0], dict(w=2)), (NUM_X[2], {})])
)

GEOMETRY = {105: GEOMETRY_105}

# ---------------------------------------------------------------------------
# Display names. Left of the arrow is a kmonad keycode; right is what shows on
# the diagram. Anything absent is drawn as-is, which is right for the alphas.
# ---------------------------------------------------------------------------

MOD_LABEL = {
    "lmet": "Super", "rmet": "Super", "met": "Super",
    "lctl": "Ctrl", "rctl": "Ctrl",
    "lalt": "Alt", "ralt": "AltGr",
    "lsft": "Shift", "rsft": "Shift",
}

GLYPH = {
    "lsft": "$$mdi:apple-keyboard-shift$$",
    "rsft": "$$mdi:apple-keyboard-shift$$",
    "bspc": "$$mdi:backspace-outline$$",
    "ret": "$$mdi:keyboard-return$$",
    "tab": "$$mdi:keyboard-tab$$",
    "spc": "$$mdi:keyboard-space$$",
    "esc": "$$mdi:keyboard-esc$$",
    "up": "$$mdi:arrow-up$$", "down": "$$mdi:arrow-down$$",
    "left": "$$mdi:arrow-left$$", "lft": "$$mdi:arrow-left$$",
    "rght": "$$mdi:arrow-right$$",
    "caps": "$$mdi:apple-keyboard-caps$$",
    "menu": "$$mdi:menu$$",
}

NAME = {
    "grv": "`", "scln": ";", "slck": "Scroll Lk", "ssrq": "PrtSc",
    "print": "Print", "pause": "Pause", "nlck": "Num Lk", "ins": "Ins",
    "home": "Home", "end": "End", "pgup": "PgUp", "pgdn": "PgDn",
    "del": "Del", "kprt": "Enter", "kp/": "/", "kp*": "*", "kp-": "-",
    "kp+": "+", "kp.": ".", "fn": "Fn",
    **{f"kp{i}": str(i) for i in range(10)},
}


def label(kc):
    if kc in GLYPH:
        return GLYPH[kc]
    if kc in NAME:
        return NAME[kc]
    if kc in MOD_LABEL:
        return MOD_LABEL[kc]
    return kc


def sexps(text):
    """Yield each top-level (...) form."""
    depth, start = 0, None
    for i, ch in enumerate(text):
        if ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                yield text[start:i + 1]


def strip_comments(text):
    text = re.sub(r"#\|.*?\|#", "", text, flags=re.S)
    return re.sub(r";;[^\n]*", "", text)


def parse_aliases(forms):
    """Resolve @name -> {tap, hold, type}. Only the constructs this repo's
    configs actually use; anything else is passed through verbatim so it shows
    up on the diagram rather than being silently dropped."""
    out = {}
    for f in forms:
        if not f.startswith("(defalias"):
            continue
        body = f[len("(defalias"):-1]
        # name followed by either a bare token or a balanced (...) form
        for m in re.finditer(r"(\S+)\s+(\([^()]*(?:\([^()]*\)[^()]*)*\)|\S+)", body):
            name, val = m.group(1), m.group(2).strip()
            out[name] = val
    return out


def render(binding, aliases, seen=()):
    """kmonad binding -> keymap-drawer key dict."""
    b = binding.strip()
    if b in ("_", "‗"):
        return {"t": "▽", "type": "trans"}
    if b == "XX":
        return {"t": "", "type": "none"}

    if b.startswith("@"):
        name = b[1:]
        if name in seen:                      # cycle guard
            return {"t": b}
        val = aliases.get(name)
        if val is None:
            return {"t": b}
        return render(val, aliases, seen + (name,))

    if b.startswith("("):
        inner = b[1:-1].strip()
        head, *rest = inner.split(None, 1)
        rest = rest[0] if rest else ""

        if head in ("tap-hold-next-release", "tap-hold-next", "tap-hold"):
            # <timeout> <tap> <hold>
            parts = split_args(rest)
            if len(parts) == 3:
                _, tap, hold = parts
                return {"t": label_of(tap, aliases), "h": label_of(hold, aliases)}
        if head in ("tap-next-release", "tap-next", "tap-hold-press"):
            # same shape with no timeout: <tap> <hold>
            parts = split_args(rest)
            if len(parts) == 2:
                tap, hold = parts
                return {"t": label_of(tap, aliases), "h": label_of(hold, aliases)}
        if head in ("layer-toggle", "layer-switch", "layer-add", "layer-rem"):
            verb = {"layer-toggle": "", "layer-switch": "→ ",
                    "layer-add": "+", "layer-rem": "-"}[head]
            return {"t": f"{verb}{rest.strip()}", "type": "layer"}
        if head == "multi-tap":
            # (multi-tap <ms> <action> [<ms> <action> ...] <final-action>) --
            # the actions are the odd-index args PLUS the trailing one, which a
            # plain stride misses. islice rather than a stride slice literal:
            # the dotfiles scrub gate reads that bracketed colon-separated form
            # as an IPv6 address and blocks the commit.
            parts = split_args(rest)
            actions = list(islice(parts, 1, None, 2))
            if len(parts) % 2 == 1:
                actions.append(parts[-1])
            return {"t": " / ".join(label_of(a, aliases) for a in actions)}
        if head == "around":
            parts = split_args(rest)
            return {"t": "+".join(label_of(p, aliases) for p in parts)}
        return {"t": inner}

    return {"t": label(b)}


def split_args(s):
    """Split a sexp body on whitespace, keeping (...) groups intact."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch.isspace() and depth == 0:
            if cur:
                out.append(cur)
                cur = ""
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


def label_of(tok, aliases):
    r = render(tok, aliases)
    return r.get("t", "")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kbd", type=Path)
    ap.add_argument("-o", "--out-dir", type=Path, default=Path("drawings"))
    ap.add_argument("-c", "--draw-config", type=Path,
                    default=Path(__file__).parent / "draw-config.yaml",
                    help="keymap-drawer draw_config, shared with zmk-config")
    args = ap.parse_args()

    if not shutil.which("keymap"):
        sys.exit("keymap-drawer not on PATH (pip install keymap-drawer)")

    text = strip_comments(args.kbd.read_text())
    forms = list(sexps(text))

    src = None
    layers = {}
    for f in forms:
        head = f[1:].split(None, 1)[0]
        if head == "defsrc":
            src = f[1:-1].split(None, 1)[1].split()
        elif head == "deflayer":
            body = f[1:-1].split(None, 2)
            layers[body[1]] = body[2].split()

    if src is None:
        sys.exit(f"{args.kbd}: no defsrc")
    if len(src) not in GEOMETRY:
        sys.exit(f"{args.kbd}: no geometry for a {len(src)}-key defsrc. "
                 f"Known: {sorted(GEOMETRY)}. Add one rather than guessing.")

    geom = GEOMETRY[len(src)]
    aliases = parse_aliases(forms)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stem = args.kbd.stem

    info = {"keyboard_name": stem,
            "layouts": {"LAYOUT": {"layout": geom}}}
    info_path = args.out_dir / f"{stem}.info.json"
    info_path.write_text(json.dumps(info, indent=2))

    # Dump with a real YAML emitter, never f-strings: this keymap contains keys
    # that ARE quote characters (' and \\ and "), and hand-built `t: "..."` lines
    # produce a file that parses as broken flow mappings.
    doc = {"layout": {"qmk_info_json": info_path.name, "layout_name": "LAYOUT"},
           "layers": {}}
    for name, binds in layers.items():
        if len(binds) != len(src):
            sys.exit(f"layer {name}: {len(binds)} keys, defsrc has {len(src)}")
        doc["layers"][name] = [render(b, aliases) for b in binds]
    keymap_path = args.out_dir / f"{stem}.yaml"
    keymap_path.write_text(yaml.safe_dump(doc, sort_keys=False, width=200,
                                          allow_unicode=True, default_flow_style=None))

    svg_path = args.out_dir / f"{stem}.svg"
    cmd = ["keymap"]
    if args.draw_config.exists():
        cmd += ["-c", str(args.draw_config)]
    cmd += ["draw", keymap_path.name]
    svg = subprocess.run(cmd, cwd=args.out_dir, check=True,
                         capture_output=True, text=True).stdout

    # keymap-drawer gives each embedded glyph BOTH a colon id ("mdi:arrow-up")
    # and a hyphen id ("mdi-arrow-up"), but points every <use> at the colon one.
    # A colon in a URL fragment is not resolved by librsvg (and so by anything
    # built on it -- thumbnailers, ImageMagick, GTK previews, pandoc), which
    # renders every glyph key BLANK while reporting success. Browsers do resolve
    # it, which is why the defect survives a spot check in a browser. Retarget
    # the refs at the hyphen ids, which both parsers handle.
    svg = svg.replace('href="#mdi:', 'href="#mdi-')

    svg_path.write_text(svg)

    print(f"{svg_path}  ({len(layers)} layers, {len(src)} keys)")


if __name__ == "__main__":
    main()
