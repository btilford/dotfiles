# bazecor — Dygma Raise 2 configurator

**This package installs nothing.** `stow bazecor` is deliberately a no-op; the files
here are reference material. See below for why, and for the one-line install.

## Why nothing is stowed

`~/.config/Bazecor` is an **Electron application profile**, not a config directory.
Of ~3 MB across 40-odd files, exactly one is settings:

| Path | What it is |
|---|---|
| `config.json` | the only real settings file |
| `Cookies`, `Trust Tokens`, `TransportSecurity`, `Network Persistent State` | Chromium browser state |
| `Crashpad/client_id` | a per-install identifier |
| `GPUCache/`, `DawnWebGPUCache/`, `DawnGraphiteCache/`, `Shared Dictionary/` | caches, rewritten constantly |
| `Local Storage/`, `Session Storage/` | leveldb app state |
| `window-state.json` | window geometry, tied to this machine's displays |

Stowing the directory would put browser cookies, a machine identifier and megabytes
of churning cache into a public repo. Stowing `config.json` alone is also wrong: the
app rewrites it on exit, and its `neurons` array **fills with paired-device
identifiers** the moment a keyboard is registered — so a live symlink quietly commits
hardware ids on the next sync.

Hence `config.example.json`, following the same pattern as
`git/.config/git/profiles/default.example.gitconfig`: the shape is tracked, the live
file is not.

## Install

```console
mkdir -p ~/.config/Bazecor
cp ~/dotfiles/bazecor/config.example.json ~/.config/Bazecor/config.json
sed -i "s|REPLACE_ME|$HOME|" ~/.config/Bazecor/config.json
```

Only do this on a machine with no Bazecor profile yet — it overwrites settings and
would drop any paired neurons. Bazecor rewrites the file on exit, so treat the copy
as a seed, not a link.

Two fields are deliberately altered from the captured original:

- `settings.backupFolder` — a literal `/home/<user>/...` path is machine-local and the
  scrub gate rejects it, so it ships as `REPLACE_ME` for the `sed` above.
- `neurons` — emptied. Never commit a populated one.

## How Bazecor is installed here

An **AppImage**, not a package — `~/Applications/Bazecor-1.10.0-x64_<hash>.AppImage`,
registered by appimagelauncher (which writes
`~/.local/share/applications/appimagekit_<hash>-Bazecor.desktop`). So `which bazecor`
finds nothing and `pacman -Q bazecor` fails; neither means it is absent. Check
`~/Applications/` and `~/.config/Bazecor/logs/main.log` instead.

Upstream ships .deb/.rpm/AppImage only; there is no official Arch package.

## It needs polkit, and this host had no polkit agent

Bazecor calls `pkexec` to install its udev rule for the keyboard's serial device. If no
polkit **authentication agent** is running it reports polkit as missing — even though
`polkitd` is fine, because the agent is the piece that draws the prompt.

That was broken on this host until 2026-09-01: `hyprland`'s `autostart.lua` pointed at a
path Arch does not use, so no agent had ever started and every privileged prompt failed
silently. Fixed in the hyprland package. If Bazecor reports polkit missing again, check
`pgrep -af polkit-.*authentication-agent` before suspecting Bazecor.

Note the device is `root:uucp 660`, so a user in `uucp` can already reach
`/dev/ttyACM0` without any udev rule.

## Settings that matter

- `backupFolder` — where layout backups are exported. **Take a backup before touching
  a layout**: the live config is in the keyboard's EEPROM, and restore replays Focus
  commands verbatim with *no validation of any kind*, so a bad value lands in EEPROM.
- `backupFrequency: 0` — automatic backups off. Worth raising once a layout exists.
- `allowBeta: true` — opts into beta firmware.
- `verbose: false` — turn on when debugging device detection; it logs every serial port
  probe to `logs/main.log`.

## Layout sync

The Raise 2 layout is generated from the ZMK keymap, not hand-maintained here — ZMK is
the source of truth, the same way `qmk-config` and this repo's `kmonad` package are.
The 42-key core comes from ZMK; the extra keys a 68-key board has and a split 42 does
not (number row, outer columns, extra thumbs) follow the `kmonad` package's
`linux-shared.kbd`, which already answers that question for a full-size board.

The plan, the Focus API notes and the ZMK→Dygma parity table live in the vault:
`Projects/Keyboards/sync-raise2-layout-with-zmk.md` and
`Projects/Keyboards/Dygma Raise 2 Config Format.md`.
