# brave-linux — Brave browser launch flags (Linux only)

Stow package. `stow --no-folding brave-linux` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/brave-flags.conf` | `~/.config/brave-flags.conf` |

```text
--ozone-platform=wayland
--password-store=kwallet6
```

Native Wayland rather than XWayland — without it Brave renders through Xwayland
and picks up neither fractional scaling nor the Wayland clipboard properly under
Hyprland.

`--password-store=kwallet6` pins the credential backend explicitly. Without the
switch Chromium reaches the Secret Service through libsecret, so the key lands
wherever `org.freedesktop.secrets` points. On a machine with no Secret Service at
all it falls back to `basic`, which stores passwords **unencrypted**.

`kwallet6` names the KWallet D-Bus service (`org.kde.kwalletd6`) directly. It
therefore does not depend on which daemon owns `org.freedesktop.secrets`. That
owner used to be gnome-keyring, by default rather than by choice. The `xdg`
package now pins it to ksecretd, so both routes reach the same wallet — but only
this one says so in the config.

Verify that Chromium-family apps reached the wallet:

```sh
grep -o "Safe Storage" ~/.local/share/kwalletd/kdewallet_attributes.json
```

Claude Desktop needs the same switch and reads no flags file. It gets one from a
desktop-entry override in the `xdg` package.

Linux-only: macOS Brave ignores this file entirely.
