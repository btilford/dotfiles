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
| `tutorial.kbd` | upstream tutorial, kept as reference |
| `Keycode.hs` | kmonad's keycode table, for looking up names |
| `quick-reference.md` | the layer/keycode cheatsheet |

A `.kbd` names its **input device path**, so a config is bound to one machine's
hardware and the files are not interchangeable — pick the one matching the board,
then check its `input (device-file ...)` line.

## `macos-work-2025.kbd` — and why file *names* matter here

That file was previously named after a client. The scrub gate found it only
because `no-local-values.sh` matches against `path:line:text`, i.e. the **filename**
as well as the contents — a plain `grep -ri` over the tree missed it entirely,
since it only ever looks inside files. When scrubbing this repo, check names too.

## Running it

kmonad needs read access to the input device and write access to `uinput`, so it
runs as a system service or via a udev rule granting the user those. Nothing in
this package sets that up — it ships configs only.

## Folding history

One of three packages found **folded** on 2026-08-12 (with `fastfetch` and `gh`).
A folded package links the *directory*, so files under it look like real files,
`diff` shows nothing (they **are** the repo's files), and deleting one deletes it
out of the repo. Repaired; repair is always `stow -R --no-folding -t ~ kmonad`,
never a deletion.
