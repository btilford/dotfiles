# Visual capture harness

Generates a reviewable visual record of the quickshell desktop — stills and short
motion clips of each surface — **without a physical display or a logged-in
graphical session**. Most of the quickshell work happens in the background or
over remote control, where a live preview isn't possible; without this, "done"
is unreviewable for a system whose whole point is how it looks and moves.

## Running it

```sh
mise run screenshots                      # capture every surface -> build/visuals/
mise run screenshots -- --scene drawer    # one surface
mise run screenshots -- --list            # what the scenes are
mise run screenshots -- --no-motion       # stills only, much faster

mise run screenshots:archive -- --ref mr-21 --note 'launcher rows got icons'
mise run screenshots:history              # re-render pages from the ledger only
```

`build/visuals/` is gitignored scratch. The permanent history lives in the notes
vault at `$DOTFILES_SCREENSHOT_ARCHIVE`
(`Projects/hyprland-dotfiles/screenshots/`), never in this repo.

That variable (and `$VOL_SCREENSHOT_ARCHIVE`) is **machine-local and untracked** —
the vault path only exists on hosts that sync it, so hardcoding it in the repo
would be wrong on any other machine. Set it per host in the local override your
shell already sources:

| Shell | File |
|-------|------|
| bash | `~/.bashrc_local` |
| zsh | `~/.zshrc_local` |
| fish | `~/.config/fish/conf.d/local.fish` |

Not `~/.config/nushell/local.nu` — that path is inside the stow package and **is
tracked**, so anything put there gets committed.

`mise run screenshots:archive` refuses to run when the variable is unset, so a
host that has not set it fails loudly rather than writing somewhere unexpected.

## Surfaces

| Scene | What it is | How it is driven |
|-------|-----------|------------------|
| `bar` | top bar | always on screen |
| `drawer` | launcher, drun mode | `qs ipc call launcher show drun` |
| `modal` | session/power overlay | `qs ipc call session show` |
| `popup` | notification popups | `notify-send` on the nested bus |
| `tmux` | terminal surface | private tmux server, `vhs` tape or a real terminal |

`popup` **skips itself with a warning** if nothing owns
`org.freedesktop.Notifications` on the nested bus — a capture of an empty desktop
is worse than no capture. Every other scene works on any branch.

The `popup` scene captures fourteen files, not one, because notification placement is
a choice to be settled from real captures rather than taste — and because the timing
behaviours (countdown, shrink-to-icon) only exist as motion:

| Capture | What it shows |
|---------|---------------|
| `popup` / `popup-motion` | right-center preset: still + arrival |
| `popup-dwell-motion` | timeout: the card flying up into the bar bell |
| `popup-overflow` | more popups than `maxVisible`, with the `+N more` tail |
| `popup-countdown` | a card partway through its dwell, remaining-time bar part-drained |
| `popup-collapse-motion` / `popup-collapsed` | sticky critical folding to a pill and docking in the bar |
| `popup-keyboard-focus` / `popup-keyboard-select` | focus mode: the selected card outlined, key legend under the stack |
| `popup-keyboard-motion` | j/k moving the selection, `d` dismissing, `Esc` releasing |
| `popup-rules` | one Lua rules file deciding three notifications: routed, sticky, silenced |
| `popup-drawer` / `popup-drawer-modal` | history drawer, both shapes, after the popups expired |
| `popup-bottom` / `popup-bottom-motion` | bottom-center preset: still + arrival |

The keyboard scenes press real keys with `wtype`. That only works because the
harness parks a long-sleeping `wtype` on the seat for the whole run: with
`WLR_LIBINPUT_NO_DEVICES=1` the seat has no keyboard, so it never advertises the
keyboard capability, no client binds `wl_keyboard`, and every keystroke is
discarded without a word in any log. Remove that holder and the keyboard captures
silently record a stack that ignores you.

The preset is switched by rewriting a notification config in the nested session's
runtime dir, which the shell hot-reloads. `QS_NOTIFY_CONFIG` points the shell at
that file (the same env-first/fixed-path seam as `HYPR_NOTIFY`), so the user's own
`~/.config/quickshell/notifications.json` is never touched by a capture run.

## 🚨 Isolation — the part you must not break

An agent-launched compositor destroyed the user's live desktop session on this
machine on 2026-07-26 (`Incidents/cachyos-fwd-agent-drm-master-seizure` in the
vault). The rules that came out of that:

- The backend is forced **via environment**, not config: `WLR_BACKENDS=headless`,
  `WLR_LIBINPUT_NO_DEVICES=1` (and `AQ_HEADLESS_ONLY=1` if Hyprland ever becomes
  viable here). A `monitor =` / `output` line in a config file does **not** select
  a backend — the compositor will still take DRM master and kill the session.
- The nested session gets its own short-path `$XDG_RUNTIME_DIR` under `/tmp`, its
  own session bus, and runs with `WAYLAND_DISPLAY`/`DISPLAY` unset.
- The launch lives in `mise-scripts/visual-capture.sh` — a committed, reviewable
  script. Never an ad-hoc shell line.
- **A failed compositor start is never retried in a loop.** One failure: stop and
  report. A retry loop is how the desktop died.

The same reasoning extends to the terminal scene: tmux runs on a private socket
(`-L qs-visuals-$$`) with the working tree's `.tmux.conf`, never the default
socket. The user's live tmux server holds their real work and other agents'
sessions — capturing it would leak that into the vault, and killing sessions in
it would take those agents down.

## Layout the archive produces

```text
$DOTFILES_SCREENSHOT_ARCHIVE/
  SCREENSHOTS.md              index: epic milestones as images, all else a table
  history/log.tsv             append-only ledger — the only source of truth
  history/2026-07.md          month page: every batch, images and clips inline
  history/2026-07/<timestamp>-<surface>-<ref>.png|gif
```

Both `.md` pages are **generated, never hand-edited**. They are a pure function
of `log.tsv`, so a bad edit is recovered by re-running
`mise run screenshots:history`. Filenames sort chronologically, so the directory
listing is itself the timeline.

## Requirements

`sway`, `quickshell`, `grim`, `ffmpeg`, `tmux`, and a terminal (`foot`) are
required and declared in the `metapac` package. `vhs` (scripted terminal GIFs)
and `oxipng` (lossless shrink) are optional — the harness degrades to a real
terminal and to unoptimised PNGs without them.
