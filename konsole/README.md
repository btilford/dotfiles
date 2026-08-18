# konsole — KDE terminal, application settings (Linux)

Stow package. `stow --no-folding konsole` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/konsolerc` | `~/.config/konsolerc` |

The whole file is three keys: `DefaultProfile=Default.profile`, a config version,
and an empty `[UiSettings] ColorScheme=`.

**Everything that makes konsole look like anything is elsewhere.** `konsolerc`
names a profile; the profile itself — font, colour scheme, scrollback, cursor —
lives in `~/.local/share/konsole/Default.profile`, which this package does not
track. Stowing this package on a fresh machine therefore gets you konsole's
built-in defaults under a profile name that may not exist.

The empty `ColorScheme=` is deliberate: it lets the profile's scheme apply rather
than pinning one at the application level.

konsole is not the session terminal (ghostty is). This exists mainly for
[`yakuake`](../yakuake), which embeds konsole's terminal part and reads the same
profile.

konsole rewrites this file itself when settings change in the GUI — i.e. through
the stow symlink and into the repo. Read the diff before committing.
