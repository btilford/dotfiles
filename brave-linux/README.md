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

`--password-store=kwallet6` pins the credential backend explicitly. Chromium's
auto-detection keys off the desktop-environment variables, and under Hyprland
(neither GNOME nor a full Plasma session) it guesses `basic`, which stores
passwords **unencrypted**. This machine runs `ksecretd`/kwallet6, which is the
same wallet `dotfiles-secrets` depends on.

Linux-only: macOS Brave ignores this file entirely.
