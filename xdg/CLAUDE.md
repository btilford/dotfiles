# xdg package

Context for AI agents working on this stow package. Not stowed (excluded by `.stow-local-ignore`).

## What this package manages

Freedesktop defaults — which app handles which mime type, and which terminal
emulator gets used when something has to spawn one.

| Path | Purpose |
|------|---------|
| `.config/mimeapps.list` | Default handlers. Browser/scheme handlers plus `inode/directory`. |
| `.config/xdg-terminals.list` | Preferred emulators for `Terminal=true` desktop entries (xdg-terminal-exec spec). ghostty first. |
| `.local/share/applications/ghostty-yazi.desktop` | Directory handler: `ghostty -e yazi %f`. |
| `.local/share/applications/com.anthropic.Claude.desktop` | Claude Desktop override. Adds `--password-store=kwallet6`. |
| `.local/share/dbus-1/services/org.freedesktop.secrets.service` | Routes `org.freedesktop.secrets` to ksecretd, not gnome-keyring. |

## Why the directory handler exists

kitty ships `kitty-open.desktop` (`kitty +open`) and it wins `inode/directory` by
default. Anything that calls `xdg-open` on a path then spawns **kitty**, not the
session's terminal — this is what made clipborg's `open`-mode actions appear in
kitty while its `terminal`-mode actions correctly used ghostty. The two are
different code paths and no `$TERMINAL` setting fixes the xdg-open one.

`ghostty-yazi.desktop` is `Terminal=false` on purpose: it launches the emulator
itself. A `Terminal=true` entry (like the stock `yazi.desktop`) hands the choice
of emulator back to xdg-open/gio, which is how we ended up in kitty in the first
place.

## Rules

- **Changing `inode/directory` changes the file manager for the whole session**, not
  just clipborg. Anything that opens a folder (browsers, chat apps, `xdg-open .`)
  goes through it.
- After editing `.local/share/applications/`, run
  `update-desktop-database ~/.local/share/applications` or the entry won't resolve.
- Verify with `xdg-mime query default inode/directory`, then actually
  `xdg-open ~/some-dir` — the query can be right while the entry fails `TryExec`.
- `$TERMINAL` (set in the `hyprland` package's `environments.lua`) governs programs
  that spawn a terminal themselves. It does **not** affect xdg-open. Keep both in sync.

## Why Claude Desktop needs a desktop-entry override

The packaged entry is `/usr/share/applications/com.anthropic.Claude.desktop`.
Ours has the same basename in `~/.local/share/applications`, so it shadows the
package copy — `XDG_DATA_HOME` always precedes `XDG_DATA_DIRS`, and the first
entry that claims a desktop ID wins.

**Do not add `CLAUDE_PASSWORD_STORE` to any file. It does not exist.** The string
appears in neither `/usr/lib/claude-desktop/claude-desktop` nor
`resources/app.asar` (verified on 1.30096.1-1). The app reads `CLAUDE_ENABLE_LOGGING`,
`CLAUDE_USER_DATA_DIR` and `CLAUDE_AI_URL`, and nothing else in that namespace.
It also reads no `*-flags.conf`, unlike Brave. The command line is the only seam.

The app handles the password store itself, but only on KDE. Its detection is:

```js
(XDG_CURRENT_DESKTOP ?? "").toUpperCase().split(":").includes("KDE")
```

`XDG_CURRENT_DESKTOP` is `Hyprland` here, so that branch never runs.

**Do not describe the unswitched state as `basic`.** Current Chromium reaches the
Secret Service through libsecret whatever the desktop environment reports, so
without the switch the key goes to the owner of `org.freedesktop.secrets`. Here
that is gnome-keyring, and the item is real: `Claude Safe Storage`, schema
`chrome_libsecret_os_crypt_password_v2`. `Local State` shows only the *portal*
provider failing (`"os_crypt":{"portal":{"prev_init_success":false}}`), and the
libsecret provider then succeeding. The switch changes which store holds the key,
not whether one exists.

**Use `kwallet6`, not `gnome-libsecret`.** `kwallet6` calls `org.kde.kwalletd6`
over D-Bus by name, so it cannot be redirected by whatever owns
`org.freedesktop.secrets`. Both now reach the same wallet — see the Secret Service
section below — but only one of them says so in the config. The `brave-linux`
package pins the same value for the same reason.

One upstream behaviour to keep in mind: on a KDE session with **no** wallet file,
the app forces `--password-store=basic` for that launch, so Chromium cannot wedge
behind the wallet-creation dialog. That guard reads
`$XDG_DATA_HOME/kwalletd/*.kwl` and then asks kwalletd for its wallet list. It
never fires here, because the session is not KDE and `kdewallet.kwl` exists.

### Rules for the override

- The override is a **full copy**. Re-check it after every `claude-desktop`
  package upgrade:

  ```sh
  diff <(grep -v "^#" ~/.local/share/applications/com.anthropic.Claude.desktop \
          | sed "s/ --password-store=kwallet6//") \
       <(grep -v "^#" /usr/share/applications/com.anthropic.Claude.desktop)
  ```

- Keep the switch on **all three** `Exec` lines. The two `Desktop Action` entries
  launch the same binary, and a launch without the switch writes values the
  wallet-backed key cannot read.
- Adding a file here needs `stow -R --no-folding -t ~ xdg` and then
  `update-desktop-database ~/.local/share/applications`.
- Verify the wallet actually received a key after a relaunch:

  ```sh
  grep -o "Claude[a-zA-Z ]*" ~/.local/share/kwalletd/kdewallet_attributes.json
  ```

  Brave, Chrome and Chromium already appear in that file, which is the evidence
  that the switch works on this machine.

## Why this package owns the Secret Service activation file

`org.freedesktop.secrets` had no deliberate owner. gnome-keyring ships the only
activation file for it in `/usr/share`, so it won the name by default, and
`autostart.lua` had a comment predicting exactly that race. kwallet ships no file
for the name at all — only `org.kde.kwalletd6` and `org.kde.secretservicecompat`.

`.local/share/dbus-1/services/org.freedesktop.secrets.service` names `ksecretd`
for it. `XDG_DATA_HOME` precedes `XDG_DATA_DIRS`, so this file wins while
gnome-keyring is installed, and it becomes the only activation path once
gnome-keyring is removed.

Facts worth keeping:

- **The Exec path must be absolute.** D-Bus activation does no `PATH` lookup. This
  is the one place in the repo where an absolute system path is correct.
- **The session bus caches service files at startup.** A new file is not seen
  until `busctl --user call org.freedesktop.DBus /org/freedesktop/DBus
  org.freedesktop.DBus ReloadConfig`, or the next login. Skipping the reload
  activated gnome-keyring again and looked like the file had no effect.
- **A running ksecretd does not retroactively claim the name.** It decides at its
  own startup. After freeing the name, the existing instance must be restarted, or
  the request times out while the process sits there owning only
  `org.kde.secretservicecompat`.
- **Do not add an autostart entry for ksecretd.** Activation covers it, and a
  second start path is what created the original race.
- Masking `gnome-keyring-daemon.socket` and `.service` is **per machine**, not
  committable. Keep the masks even after removing the package — they are what stops
  the race returning if something pulls gnome-keyring back in as a dependency.

Switching the owner orphans everything already stored in the other keyring. `gh`
is the loud one: it reports `The token in keyring is invalid` and every GitHub
push through `gh-git-credential` fails until `gh auth login` runs again.
