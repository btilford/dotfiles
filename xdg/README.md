# xdg — freedesktop defaults (Linux)

Stow package. `stow --no-folding xdg` from `~/dotfiles`.

| Path | Purpose |
|------|---------|
| `.config/mimeapps.list` | default handlers — browser/scheme handlers plus `inode/directory` |
| `.config/xdg-terminals.list` | preferred emulators for `Terminal=true` desktop entries; ghostty first |
| `.local/share/applications/ghostty-yazi.desktop` | directory handler: `ghostty -e yazi %f` |
| `.local/share/applications/com.anthropic.Claude.desktop` | Claude Desktop override: adds `--password-store=kwallet6` |
| `.local/share/dbus-1/services/org.freedesktop.secrets.service` | routes the Secret Service to ksecretd (kwallet), not gnome-keyring |

> Agent-facing notes: [`CLAUDE.md`](CLAUDE.md).

## Why the directory handler exists

kitty ships `kitty-open.desktop` (`kitty +open`) and it wins `inode/directory` by
default. Anything that calls `xdg-open` on a path then spawns **kitty**, not the
session's terminal — which is how clipborg's `open`-mode actions ended up in kitty
while its `terminal`-mode actions correctly used ghostty. Two different code
paths, and no `$TERMINAL` setting fixes the xdg-open one.

`ghostty-yazi.desktop` is `Terminal=false` **on purpose**: it launches the emulator
itself. A `Terminal=true` entry (like the stock `yazi.desktop`) hands the choice of
emulator back to xdg-open/gio — which is what put us in kitty to begin with.

## Two knobs, kept in sync

| Knob | Governs |
|------|---------|
| `$TERMINAL` (set in the `hyprland` package's `environments.lua`) | programs that spawn a terminal themselves |
| this package | `xdg-open` |

Neither affects the other.

## Editing

Changing `inode/directory` changes the **file manager for the whole session** —
browsers, chat apps, `xdg-open .`, everything.

After editing `.local/share/applications/`:

```sh
update-desktop-database ~/.local/share/applications
xdg-mime query default inode/directory
xdg-open ~/some-dir            # actually try it
```

The query can be right while the entry fails `TryExec`, so run the last line too.

## The Claude Desktop override

`com.anthropic.Claude.desktop` is a copy of the packaged entry
(`/usr/share/applications/com.anthropic.Claude.desktop`). It changes one thing:
`--password-store=kwallet6` on all three `Exec` lines.

Claude Desktop is Electron, so Chromium chooses the backend. Without the switch it
uses the Secret Service, which means whichever daemon owns
`org.freedesktop.secrets`. On this machine that is gnome-keyring, and the key
landed there on first run:

```text
label:      Claude Safe Storage
application Claude
xdg:schema  chrome_libsecret_os_crypt_password_v2
```

That is real encryption, but it is the wrong store. `plasma-kwallet-pam.service`
unlocks kwallet, not gnome-keyring's login keyring. The switch moves the key to
`org.kde.kwalletd6`, where Brave and Chrome already keep theirs.

The app can select kwallet by itself, but only on KDE, and this session reports
`Hyprland`. Chromium's portal-based provider also failed here, which
`~/.config/Claude/Local State` records:

```json
"os_crypt":{"portal":{"prev_desktop":"Hyprland","prev_init_success":false}}
```

The libsecret provider succeeded after it, which is why a key exists at all.

The desktop entry is the only seam. The app reads no flags file, and no
environment variable controls this. `CLAUDE_PASSWORD_STORE` appears in neither
the binary nor `resources/app.asar` — the `CLAUDE_*` variables it does read are
`CLAUDE_ENABLE_LOGGING`, `CLAUDE_USER_DATA_DIR` and `CLAUDE_AI_URL`.

The switch changes the encryption key, so values written under `basic` become
unreadable. Expect one re-login after the first launch with the override.

A full copy can drift from the packaged entry. Check after a package upgrade:

```sh
diff <(grep -v "^#" ~/.local/share/applications/com.anthropic.Claude.desktop \
        | sed "s/ --password-store=kwallet6//") \
     <(grep -v "^#" /usr/share/applications/com.anthropic.Claude.desktop)
```

Empty output means the override carries every key the package ships.

## The Secret Service points at kwallet

`org.freedesktop.secrets` is the D-Bus name every libsecret client uses — `gh`,
JetBrains Toolbox, Element, nm-applet, Chromium without a `--password-store`
switch. Two packages provide it, and only one ships an activation file:

| Package | Ships an activation file for the name |
|---------|----------------------------------------|
| gnome-keyring | yes, `/usr/share/dbus-1/services/org.freedesktop.secrets.service` |
| kwallet | no — only `org.kde.kwalletd6` and `org.kde.secretservicecompat` |

So gnome-keyring won the name by default, and secrets went to a keyring that
`plasma-kwallet-pam.service` never unlocks. The file in this package names
`ksecretd` for the same D-Bus name. `XDG_DATA_HOME` precedes `XDG_DATA_DIRS`, so
it wins while gnome-keyring is installed, and it is the only activation path once
gnome-keyring is gone.

ksecretd needs no autostart entry. D-Bus starts it on the first request and it
claims both `org.freedesktop.secrets` and `org.kde.secretservicecompat`.

Two per-machine steps go with the file, because neither is committable:

```sh
systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service
systemctl --user stop gnome-keyring-daemon.socket gnome-keyring-daemon.service
```

Verify:

```sh
busctl --user list | grep org.freedesktop.secrets     # must name ksecretd
printf x | secret-tool store --label=t probe yes      # then check the wallet:
grep -c t ~/.local/share/kwalletd/kdewallet_attributes.json
secret-tool clear probe yes
```

The Secret Service must report exactly one collection, `kdewallet`.
