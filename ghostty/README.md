# ghostty — the session terminal

Stow package. `stow --no-folding ghostty` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/ghostty/config` | `~/.config/ghostty/config` |
| `.config/ghostty/theme.conf` | `~/.config/ghostty/theme.conf` |

JetBrains Mono 20, 0.8 background opacity over `#1a0808`, block cursor with
click-to-move, amber selection, and a `cursor_warp.glsl` custom shader.

Listed as macOS-only in older docs; it is now the terminal on **both** platforms —
[`xdg/`](../xdg) exists partly to make it the `inode/directory` handler on Linux so
`xdg-open` on a folder stops opening kitty.

## `wallust.conf` is excluded, and the reason is a live hazard

[`wallust`](../wallust) writes `~/.config/ghostty/wallust.conf` on every wallpaper
switch. The repo used to track it as an **empty 0-byte file** — so re-stowing this
package would have replaced a real palette with nothing and blanked the terminal
colours. It is now in the package `.stow-local-ignore`:

```text
CLAUDE\.md
wallust\.conf
```

Note that a package-local `.stow-local-ignore` **replaces** stow's built-in ignore
list rather than adding to it, which is why `CLAUDE.md` has to be named
explicitly here. `README.*` is covered by the same rule — if you add a file to
this list, check that repo-meta files are still excluded.

## The shader

`custom-shader = shaders/cursor_warp.glsl` is a **relative** path, resolved
against the config dir. The shader file itself is not tracked here, so on a fresh
machine ghostty logs a missing-shader warning and runs without it — harmless, but
that is the reason if the cursor trail is absent.
