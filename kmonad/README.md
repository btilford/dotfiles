# kmonad — keyboard remapping

Stow package. `stow --no-folding kmonad` from `~/dotfiles`.

Installs `.config/kmonad/*` to `~/.config/kmonad/`.

| File | Board |
|------|-------|
| `us_ansi_100.kbd`, `us_ansi_tkl.kbd`, `us_ansi_60.kbd` | ANSI full / TKL / 60% |
| `iso_100.kbd`, `iso_tkl.kbd`, `iso_60.kbd` | ISO equivalents |
| `apple.kbd`, `macos-macbook-pro-13i-2017.kbd`, `macos-work-2025.kbd` | Apple boards |
| `linux-cachyos2-built-in.kbd`, `linux-cachyos2-laptop.kbd` | this machine's internal keyboards |
| `atreus.kbd`, `freestyle2.kbd`, `thinkpad_T430_iso.kbd`, `thinkpad_x220_iso.kbd` | specific hardware |
| `linux-shared.kbd` | **the live layout** — mirrors `config/base.keymap` in zmk-config; one file for every board, device set per process |
| `tutorial.kbd` | upstream tutorial, kept as reference |
| `Keycode.hs` | kmonad's keycode table — **stale, see below** |
| `quick-reference.md` | the layer/keycode cheatsheet |

Most `.kbd` files name their **input device path**, so they are bound to one
machine's hardware and are not interchangeable — pick the one matching the board,
then check its `input (device-file ...)` line.

`linux-shared.kbd` is the exception and the one now in use. kmonad grabs exactly
one device per process, so instead of a file per board it carries a deliberate
`PLACEHOLDER` path that fails loudly, and the device is supplied per process via
`-i`/`-o`. That is what `kmonad-device@.service` below automates. Its `defsrc` is a
100% layout, so it suits full-size and TKL boards; a 60% or laptop board needs its
own `defsrc`.

Deliberate gaps vs. the keyboard firmware, documented in the file's header: no
F-key layer (a full board has a real F-row), no magic-shift (kmonad has no
adaptive-key), no cross-hand restriction (no equivalent of ZMK's
`hold-trigger-key-positions`), and the mouse/text layers are not ported.

## `Keycode.hs` is stale — do not trust it to reject a keycode

It lists `prnt` for `KeyPrint` and has no `print` alias, yet kmonad 0.4.5 accepts
the `print` that `linux-shared.kbd`'s `defsrc` uses. It is a copy of an upstream
table, not the one the installed binary was built from, so a name missing here is
not evidence the name is invalid.

Parse the config instead — kmonad reads and validates the whole file before it
touches the device, so a bad keycode fails before any grab:

```console
$ kmonad ~/.config/kmonad/linux-shared.kbd
kmonad: /dev/input/by-path/PLACEHOLDER-event-kbd: openFdAt: does not exist
```

Reaching the device error means the parse succeeded.

## `macos-work-2025.kbd` — and why file *names* matter here

That file was previously named after a client. The scrub gate found it only
because `no-local-values.sh` matches against `path:line:text`, i.e. the **filename**
as well as the contents — a plain `grep -ri` over the tree missed it entirely,
since it only ever looks inside files. When scrubbing this repo, check names too.

## Running it

kmonad needs read on the input device (`/dev/input/eventN`, `root:input 0660`) and
read/write on `/dev/uinput` (`0666` here). Add the user to `input` once per machine:

```console
sudo usermod -aG input "$USER"     # then LOG OUT AND BACK IN
```

The re-login is not optional and `newgrp` is not a substitute. The systemd `--user`
manager inherits its groups from the login session that started it, so an
already-running manager keeps failing with `openFdAt: permission denied` until the
next full login however many times you restart the unit.

### `kmonad-device@.service`

A **user** template unit, one instance per keyboard, driving `linux-shared.kbd`
with `-i`/`-o` overrides. It is NOT the distro's `kmonad@.service`
(`/usr/lib/systemd/system/`), which takes one baked-in config per instance and
cannot express the override model; both can be installed at once.

The instance name is a **systemd-escaped absolute device path**, so generate it —
never type it by hand:

```console
ls /dev/input/by-id/ | grep -i kbd          # USB boards
ls /dev/input/by-path/ | grep -i kbd        # laptop built-in (i8042: NO by-id link)

INST=$(systemd-escape --path /dev/input/by-id/usb-<vendor>_<model>-event-kbd)
systemctl --user enable --now "kmonad-device@${INST}.service"
systemctl --user status "kmonad-device@${INST}.service"
```

`by-id`/`by-path`, never `eventN` — the event number follows probe order and moves
across reboots and replugs, so a unit pinned to `event16` eventually grabs some
other device.

Enabled instances are per-machine state and are NOT tracked here; only the template
is. Each new machine runs its own `enable`.

### Verified instances

| Machine | Board | Device path |
|---|---|---|
| cachyos-fwd | Das Keyboard 5Q (`DK5QS`, full-size ANSI) | `/dev/input/by-id/usb-Metadot_-_Das_Keyboard_DK5QS-event-kbd` |

### Escape hatch

`linux-shared.kbd` maps **Scroll Lock** to a `passthru` layer — a stock keyboard
with kmonad still running. It exists because you cannot toggle kmonad back on once
it has exited. Laptop boards have no `slck` and need their own choice.

`systemctl --user stop` is the other way out, but needs a working keyboard to type.

## Layout diagrams

`drawings/linux-shared.svg` is the rendered layout, one panel per layer, styled to
match the zmk-config diagrams so the kmonad and firmware sets read as one.

Regenerate after any edit to a `.kbd`:

```console
$ ~/.config/kmonad/tools/kmonad-draw.py ~/.config/kmonad/linux-shared.kbd \
    -o ~/.config/kmonad/drawings/
drawings/linux-shared.svg  (3 layers, 105 keys)
```

keymap-drawer parses ZMK and QMK but **not** kmonad, so `tools/kmonad-draw.py`
does the parsing itself: it reads `defsrc`, `deflayer` and `defalias`, resolves
`tap-hold-next-release` into tap/hold label pairs and `layer-toggle`/`layer-switch`
into layer references, then emits a keymap-drawer YAML plus a QMK-style
`info.json` for the physical layout.

`tools/draw-config.yaml` is a verbatim copy of the `draw_config` half of
`keymap-drawer/corne-42.yaml` in zmk-config. Re-copy it when the ZMK styling
changes; do not hand-edit, or the two sets drift.

### Adding a board

The script carries geometry for the 105-key `defsrc` only, and **refuses** an
unknown key count rather than guessing — a wrong physical layout yields a
convincing diagram of the wrong keyboard. A 60% or laptop `defsrc` needs its own
entry in `GEOMETRY`.

### Two traps, both of which fail silently

* **No bare `<` in `draw-config.yaml`.** keymap-drawer emits `svg_extra_style`
  straight into a `<style>` element with no CDATA wrapper, so one `<` in a CSS
  *comment* makes the whole SVG invalid XML. The copied comment originally read
  `an external <image href> ...`; that single character is why all five committed
  SVGs in zmk-config fail to parse today.
* **Glyph `<use>` refs need the hyphen ids.** keymap-drawer gives every embedded
  glyph both `id="mdi:arrow-up"` and `id="mdi-arrow-up"` but points each `<use>`
  at the colon form. librsvg does not resolve a colon in a URL fragment, so every
  glyph key renders blank — in thumbnailers, ImageMagick, GTK previews, pandoc —
  while the command reports success. Browsers *do* resolve it, so a spot check in
  a browser will not catch this. The script rewrites the refs after drawing.

## Folding history

One of three packages found **folded** on 2026-08-12 (with `fastfetch` and `gh`).
A folded package links the *directory*, so files under it look like real files,
`diff` shows nothing (they **are** the repo's files), and deleting one deletes it
out of the repo. Repaired; repair is always `stow -R --no-folding -t ~ kmonad`,
never a deletion.
