# Dotfiles

Stow-managed dotfiles for btilford. Each top-level directory is a stow package mirroring `$HOME`.

## Rules

- No absolute paths in configs — use `~`, `$HOME`, or `$XDG_*` vars
- Local machine-specific config lives outside the repo, not in stow packages
- Cross-platform: macOS + Linux. Platform-specific packages are isolated
- Always stow one package at a time with `--no-folding` to prevent directory symlinking and protect local-only files
- `hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` is a committed seed (fresh installs need it to exist), but wallpaper rotation rewrites it through the stow symlink every ~30 min. After cloning, run `git update-index --skip-worktree hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` once per machine so the churn never lands in git. Never commit content updates to it.

## Worktrees, and why config needs a path seam

`~/dotfiles` on `master` is the **single deploy checkout** — every stow symlink
resolves there. Work happens in worktrees (`~/worktrees/<branch>/dotfiles`),
including background agent sessions, so that a half-finished edit is never live
on the running desktop. For a repo that *is* the running system, that insulation
is the point.

The consequence: a worktree edit is invisible to the running system until it is
merged and `~/dotfiles` pulls. Whether that blocks testing depends entirely on
whether the tool accepts a path override.

**Config we own resolves env first, fixed path as fallback.** Anything that can
only be read from a hardcoded `$HOME` path is a testability bug in our config,
not a reason to work in the live checkout — it means the component cannot be
exercised in isolation by a harness, a nested session, or CI.

Tools that already have a seam, and the flag to use:

| Tool | Test a worktree copy with |
|------|---------------------------|
| quickshell | `qs -p <worktree>/quickshell/.config/quickshell/shell.qml` |
| tmux | `tmux -L <private-socket> -f <worktree>/tmux/.tmux.conf` |
| metapac | `metapac --config-dir <worktree>/metapac/.config/metapac` |
| nvim | `nvim -u <worktree>/nvim/.config/nvim/init.lua` |

No seam, so merge first and verify live: shell rc files (sourced from fixed `~`
paths at login) and Hyprland's own config discovery (`-c` applies at launch
only, `hyprctl reload` always re-reads `~/.config/hypr`).

`scripts/visual-capture.sh` is the worked example — it defaults to the working
tree for both the shell entry point and the tmux config, so a capture shows what
is in the branch rather than what happens to be stowed.

## Structure

- **Cross-platform**: `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `zellij`, `wezterm`, `metapac`, `workmux`
- **macOS-only**: `ghostty`, `macos`
- **Linux-only**: `hyprland`, `rofi`, `konsole`, `kmonad`, `terminator`, `yakuake`, `brave-linux`, `xdg`
- **Shared base**: `base`

## Branches

- `master` — main
- `macos` — macOS-specific work

## Hyprland Lua API

- Authoritative API stubs: `/usr/share/hypr/stubs/hl.meta.lua` (installed by `hyprland` package)
- Example config: `/usr/share/hypr/hyprland.lua`
- Consult stubs before guessing `hl.*` signatures or field names

## System packages (metapac)

The `metapac` package declares installed packages across machines. Replaced
`pug`, whose gist-syncing pacman hook had been broken since 2024. Config lives
at `~/.config/metapac/`; group files are the source of truth.

- **One config for every host.** Per-machine divergence lives in the
  `[hostname_enabled_backends]` / `[hostname_groups]` tables in `config.toml`,
  not in separate stow packages.
- **Backends:** `arch`, `brew`, `bun`, `cargo`, `flatpak`, `mise`, `uv`.
  `[arch] package_manager = "paru"` is required so AUR installs stay behind the
  aur-policy gate. `npm` and `pipx` are deliberately disabled.
- **One owner per tool class.** bun owns global JS CLIs, uv owns global Python
  CLIs, mise owns runtimes. Never enable `npm`/`pipx` alongside them — two
  backends claiming the same tool breaks sync/clean semantics.
- **`metapac clean` uninstalls everything not declared.** Always read its
  confirmation list; never script it with `--no-confirm` unless you have just
  read `metapac unmanaged` and the list is what you intend to remove.
- `desktop-arch.toml` was bootstrapped by declaring the full explicit package
  set as-is, so `unmanaged` reports clean. Pruning cruft is deliberate: delete
  the entry, then let `clean` uninstall it.
- Orphaned *dependencies* are invisible to metapac — it only tracks explicitly
  installed packages. Use `pacman -Qdtq` for those.
- **bun quirk:** `bun pm ls -g` colorizes even when piped and ignores
  `NO_COLOR`, so metapac's bun backend captures ANSI escapes into package names
  and then treats every bun package as unmanaged. Each shell defines a `metapac`
  wrapper setting `FORCE_COLOR=0` (see the `bun` drop-ins in `fish`/`bash`/`zsh`
  and `nushell/config.nu`). Drop those and `clean` will offer to remove your bun
  packages.

Not managed by metapac, by design: nvim plugins (lazy.nvim + `lazy-lock.json`)
and Mason's LSP/formatter tools (declared via `mason-tool-installer`).

## Linting & CI

Two surfaces run the same class of checks and must be kept as close as possible:

- **`mise.toml`** — the local toolchain + `mise run lint` tasks (shell, secrets,
  yaml, json, nu, fish) and `mise run fmt` formatters. This is the full suite.
- **`.gitlab-ci.yml`** — the CI gate. A deliberate *subset*: shellcheck +
  gitleaks only, via official tool-bundled images.

**They intentionally diverge** because the self-hosted GitLab runner cannot
reach `api.github.com` (rate-limited) or `sigstore.dev`, so mise's aqua/ubi
installs fail in CI (see the `gitlab-runner-no-github-egress` memory). CI works
around this with prebuilt images; local uses mise directly.

**Sync rule:** whenever you change one of these two files, evaluate the other
and keep the shared gates aligned — same shellcheck flags/excludes/severity,
same gitleaks config, same allowlists. If you add a gate to `mise run lint`,
decide whether CI should carry it too (and whether the runner can, given the
GitHub/sigstore constraint) rather than letting the two drift silently.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)
