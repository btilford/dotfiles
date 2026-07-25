# Dotfiles

Stow-managed dotfiles for btilford. Each top-level directory is a stow package mirroring `$HOME`.

## Rules

- No absolute paths in configs — use `~`, `$HOME`, or `$XDG_*` vars
- Local machine-specific config lives outside the repo, not in stow packages
- Cross-platform: macOS + Linux. Platform-specific packages are isolated
- Always stow one package at a time with `--no-folding` to prevent directory symlinking and protect local-only files
- `hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` is a committed seed (fresh installs need it to exist), but wallpaper rotation rewrites it through the stow symlink every ~30 min. After cloning, run `git update-index --skip-worktree hyprland/.config/hypr/wallpaper_effects/.wallpaper_current` once per machine so the churn never lands in git. Never commit content updates to it.

## Structure

- **Cross-platform**: `bash`, `fish`, `zsh`, `nvim`, `tmux`, `git`, `starship`, `yazi`, `lazygit`, `helix`, `zellij`, `wezterm`
- **macOS-only**: `ghostty`, `macos`
- **Linux-only**: `hyprland`, `rofi`, `konsole`, `konsole`, `kmonad`, `terminator`, `yakuake`, `brave-linux`, `xdg`
- **Shared base**: `base`

## Branches

- `master` — main
- `macos` — macOS-specific work

## Hyprland Lua API

- Authoritative API stubs: `/usr/share/hypr/stubs/hl.meta.lua` (installed by `hyprland` package)
- Example config: `/usr/share/hypr/hyprland.lua`
- Consult stubs before guessing `hl.*` signatures or field names

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
