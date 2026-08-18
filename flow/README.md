# flow — the flow-control editor

Stow package. `stow --no-folding flow` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/flow/config` | `~/.config/flow/config` |

[flow](https://github.com/neurocyte/flow) is a Zig terminal editor. The file is
**entirely commented out** — it is a checked-in copy of the default config kept as
a reference for what is tunable (frame rate, theme, input mode, gutter, animation
lag, LSP timeout, bar contents), not as active configuration.

Editing it means uncommenting a line; there is nothing to un-break if the package
is unstowed.
