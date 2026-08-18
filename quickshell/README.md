# quickshell — the desktop shell

Stow package. `stow --no-folding quickshell` from `~/dotfiles`.

A DIY [quickshell](https://quickshell.org/) desktop, built incrementally to
replace the waybar/rofi/swaync stack. One persistent `qs` process hosts every
surface. Targets **stable quickshell 0.3.0** (Arch repo), *not* `quickshell-git`.

Installs to `~/.config/quickshell/` — the default config path, so bare `qs` and
`qs ipc` target it with no `-c` flag.

> Deep design notes, IPC contracts and the per-component rules live in
> [`CLAUDE.md`](CLAUDE.md). This file is the tour.

## Bar

Always on screen. Power and workspace glyphs at the left, status at the right.

![quickshell bar](../docs/images/quickshell-bar.png)

## Launcher

Replaces rofi. Modes: **combi** (default — apps plus a `run:` fallback), **drun**,
**run** (`$PATH` autocomplete via `compgen -c`), **files**, **emoji**, **glyphs**,
**icons**, **wallpaper**. `Tab` cycles; prefixes jump straight to one (`>` run,
`/` or `~` files, `:` emoji, `;` glyphs, `#` icons, `!` wallpaper).

![quickshell launcher in drun mode](../docs/images/quickshell-launcher.png)

```sh
qs ipc call launcher toggle [mode]
```

Placed on `Hyprland.focusedMonitor`.

## Session overlay

Lock / logout / suspend / hibernate / reboot / shutdown, each with a single-key
accelerator.

![quickshell session overlay](../docs/images/quickshell-session.png)

```sh
qs ipc call session show
```

## Notifications

A full `org.freedesktop.Notifications` server — popups with actions and a
remaining-time bar, plus a searchable history drawer.

| Popup | History drawer |
|-------|----------------|
| ![notification popup](../docs/images/quickshell-popup.png) | ![notification drawer](../docs/images/quickshell-notifications.png) |

The drawer groups by app, supports `/` search and `j`/`k` navigation, and the
popup stack has its own keyboard-focus mode. Placement is a preset
(right-center / bottom-center), and routing/sticky/silence decisions come from a
Lua rules file. Per-machine config is `~/.config/quickshell/notifications.json` —
**untracked**; provision from `notifications.example.json`.

⚠️ **The `actions` capability is not optional.** A notification server that does
not advertise it loses every Chromium client silently — no error, no retry. They
fall back to internal notification windows, which Hyprland then tiles fullscreen.

## Submap hints

An on-screen legend for the active Hyprland submap (resize, and its nested
groups), driven from the compositor's submap state.

## Screenshots

Every image above came from the headless harness — no physical display, no
logged-in graphical session:

```sh
mise run screenshots -- --no-motion          # stills, every surface
mise run screenshots -- --list               # what the scenes are
mise run screenshots -- --scene drawer       # one surface
```

`build/visuals/` is gitignored scratch; the long-term history lives in the notes
vault. `docs/images/` holds only the handful of stills this README embeds. See
[`mise-scripts/visuals/README.md`](../mise-scripts/visuals/README.md) — **including
its isolation section**: an agent-launched compositor destroyed the live desktop
session on this machine once, and the rules that came out of that are not
negotiable.

## Working on it

**quickshell does not hot-reload through stow.** `qs` keeps running the QML it
already parsed, so a repo edit changes nothing until the daemon restarts. Test a
branch without touching the live shell:

```sh
qs -p ~/dotfiles/quickshell/.config/quickshell/shell.qml
```

Two more traps worth knowing before debugging QML here:

- **`DesktopEntries` scans lazily.** Nothing is populated until something *binds*
  to `.applications`; an imperative `heuristicLookup()` at startup returns null
  forever. Resolve icons from the entry's `Icon=`, not from `app_id`.
- **A `property data` on an `Item` shadows `Item.data`,** so the layer surface
  never keyboard-activates — mouse works, keyboard is dead, and nothing logs.

`wallust/colors.json` is written on every wallpaper switch and is excluded in both
`.stow-local-ignore` and `.gitignore`.
