# fastfetch — system info banner

Stow package. `stow --no-folding fastfetch` from `~/dotfiles`.

| Path | Installs to |
|------|-------------|
| `.config/fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` |

JSONC with a `$schema` line, so an editor with schema support completes and
validates module names.

Module order: title, os, host, kernel, bios, bootmgr, shell, display, de, lm, wm,
wmtheme, … Several modules are commented out rather than deleted (`uptime`,
`packages`, `theme`, `icons`) — commented-out entries are the record of what was
tried and rejected; keep that style rather than removing them.

Run from the shell drop-ins at startup (`30-autostart` in the bash/zsh packages).

## Folding history

This package was one of three found **folded** on 2026-08-12 (with `kmonad` and
`gh`): because it has a single subdirectory, an early stow run without
`--no-folding` linked `~/.config/fastfetch` itself rather than the file inside it.
A folded file is dangerous — the file at that path is *not* a symlink, its parent
is, so `diff` shows no difference (it **is** the repo's file) and deleting it
deletes it out of the repo. Repaired since; `~/.config/fastfetch` is a real
directory again.

Repair is always `stow -R --no-folding -t ~ fastfetch`, never a deletion.
`mise run status` classifies this as **FOLDED**.
