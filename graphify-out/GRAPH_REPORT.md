# Graph Report - .  (2026-04-29)

## Corpus Check
- Corpus is ~2,805 words - fits in a single context window. You may not need a graph.

## Summary
- 71 nodes · 72 edges · 11 communities detected
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Cross-Platform Shell & Editor Tools|Cross-Platform Shell & Editor Tools]]
- [[_COMMUNITY_Linux-Only Desktop Environment|Linux-Only Desktop Environment]]
- [[_COMMUNITY_Hyprland Desktop Configuration|Hyprland Desktop Configuration]]
- [[_COMMUNITY_Git Identity Profiles|Git Identity Profiles]]
- [[_COMMUNITY_Dotfiles Management System|Dotfiles Management System]]
- [[_COMMUNITY_Git Authentication & Paths|Git Authentication & Paths]]
- [[_COMMUNITY_Git Config Fragments|Git Config Fragments]]
- [[_COMMUNITY_Local Config Protection|Local Config Protection]]
- [[_COMMUNITY_Pyprland Plugins|Pyprland Plugins]]
- [[_COMMUNITY_NetworkManager dmenu|NetworkManager dmenu]]
- [[_COMMUNITY_Delta Pager|Delta Pager]]

## God Nodes (most connected - your core abstractions)

## Surprising Connections (you probably didn't know these)
- `Dotfiles Repository` --supports--> `Cross-Platform Config`  [EXTRACTED]
   →   _Bridges community 4 → community 0_
- `Cross-Platform Config` --includes--> `Linux`  [EXTRACTED]
   →   _Bridges community 0 → community 1_
- `Git` --part_of--> `Cross-Platform Config`  [EXTRACTED]
   →   _Bridges community 0 → community 5_
- `Rofi Launcher` --exclusive_to--> `Linux`  [EXTRACTED]
   →   _Bridges community 1 → community 2_
- `Wallust Color Pipeline` --colors--> `Ghostty Terminal`  [EXTRACTED]
   →   _Bridges community 0 → community 2_

## Hyperedges (group relationships)
- **** — git_vcs, gitconfig, git_config_fragments, git_profiles, credential_helpers [INFERRED]
- **** — hyprland_wm, waybar_status_bar, wallust_color_pipeline, awww_wallpaper, rofi_launcher [INFERRED]
- **** — cross_platform, macos, linux, bash_shell, fish_shell, zsh_shell, nvim_editor, tmux_multiplexer [INFERRED]
- **** — dotfiles_repo, gnu_stow, stow_package, stow_no_folding, home_directory [EXTRACTED]

## Communities

### Community 0 - "Cross-Platform Shell & Editor Tools"
Cohesion: 0.15
Nodes (14): Bash Shell, Cross-Platform Config, Fish Shell, Ghostty Terminal, Helix Editor, Lazygit, macOS, Neovim (+6 more)

### Community 1 - "Linux-Only Desktop Environment"
Cohesion: 0.18
Nodes (11): AMD Graphics, Brave Browser, Hyprland Window Manager, Intel Graphics, KMonad Keyboard, Konsole, Linux, Nvidia Graphics (+3 more)

### Community 2 - "Hyprland Desktop Configuration"
Cohesion: 0.22
Nodes (11): awww Wallpaper Daemon, Hyprland Configuration, Key Bindings, Multi-Monitor Setup, Rofi Launcher, GLSL Shaders, SwayNC Notifications, Wallust Color Pipeline (+3 more)

### Community 3 - "Git Identity Profiles"
Cohesion: 0.29
Nodes (8): Anonymous Git Profile, Default Git Profile, Git Dirs Config, Git Identity Profiles, GPG Signing, includeIf Directive, Profile Routing by Directory, REDACTED Work Profile

### Community 4 - "Dotfiles Management System"
Cohesion: 0.29
Nodes (7): Base Config, Dotfiles Repository, GNU Stow, Graphify Knowledge Graph, $HOME Directory, Stow Package, Symlink

### Community 5 - "Git Authentication & Paths"
Cohesion: 0.29
Nodes (7): Credential Helpers, GitHub CLI, Git, ~/.gitconfig, GLab CLI, No Absolute Paths Rule, XDG Environment Variables

### Community 6 - "Git Config Fragments"
Cohesion: 0.33
Nodes (6): Git Aliases, Git Commands Config, Git Config Fragments, Git Flow Config, Git Shell Config, Git Web Config

### Community 7 - "Local Config Protection"
Cohesion: 0.5
Nodes (4): Git Credential Manager, Local Machine Config, .stow-local-ignore, Stow --no-folding

### Community 8 - "Pyprland Plugins"
Cohesion: 1.0
Nodes (1): Pyprland Plugins

### Community 9 - "NetworkManager dmenu"
Cohesion: 1.0
Nodes (1): NetworkManager dmenu

### Community 10 - "Delta Pager"
Cohesion: 1.0
Nodes (1): Delta Pager

## Knowledge Gaps
- **Thin community `Pyprland Plugins`** (1 nodes): `Pyprland Plugins`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `NetworkManager dmenu`** (1 nodes): `NetworkManager dmenu`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Delta Pager`** (1 nodes): `Delta Pager`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Not enough signal to generate questions. This usually means the corpus has no AMBIGUOUS edges, no bridge nodes, no INFERRED relationships, and all communities are tightly cohesive. Add more files or run with --mode deep to extract richer edges._