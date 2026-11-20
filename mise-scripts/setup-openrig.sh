#!/usr/bin/env bash
# Install and configure OpenRig (`rig`) without `rig setup`. Idempotent.
#
#   mise run setup:openrig                         # install + config
#   mise run setup:openrig -- --pi-seat <session>  # also write that pi seat's models.json
#
# Why not `rig setup`: its only effects worth having are two config keys. Its
# side effects are not:
#   - it appends a managed block to ~/.tmux.conf with plain writeFileSync, which
#     follows the stow symlink into tmux/.tmux.conf in this PUBLIC repo, and has
#     no flag to skip it. The block sets `mouse on` (already set) and
#     `history-limit 10000`, which lands AFTER our 50000 and lowers scrollback.
#   - it curl|sh-installs herdr unless --no-herdr.
#
# Config applied BEFORE the first daemon start (the daemon reads it at start):
#   daemon.host 127.0.0.1    the default also binds the first CGNAT-range
#                            address (netbird's wt0 here) and exempts that range
#                            from the bearer token: unauthenticated on the mesh.
#   terminal.tmux_server isolated
#                            seats get their own socket (openrig-<hash>) instead
#                            of the personal tmux server, and the daemon's
#                            server-wide set-clipboard/copy-command stay off ours.
#   provider.selected claude what `rig setup --providers claude` would record.
#
# What the daemon still writes outside ~/.openrig (none of it tracked here):
# ~/.claude/skills/{openrig-skills,refocusing,rigs} and the same under
# ~/.agents/skills; ~/.claude.json trust flags per seat cwd; and in each seat
# cwd: .claude/settings.local.json, .mcp.json, .openrig/, a managed CLAUDE.md
# block. NEVER give a seat cwd inside ~/dotfiles or ~/private-dotfiles.

set -euo pipefail

OPENRIG_VERSION=${OPENRIG_VERSION:-0.7.14}
NODE_VER=${OPENRIG_NODE:-24}

die() {
  echo "setup:openrig: $*" >&2
  exit 1
}

pi_seat=
while [ $# -gt 0 ]; do
  case "$1" in
    --pi-seat)
      pi_seat=${2:?--pi-seat needs a session name, e.g. dev-builder@myrig}
      shift 2
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v mise > /dev/null || die "mise not found"
mise install -q "node@$NODE_VER" > /dev/null
node_dir=$(mise where "node@$NODE_VER")
rig_bin=$node_dir/bin/rig

installed=
[ -x "$rig_bin" ] && installed=$(PATH="$node_dir/bin:$PATH" "$rig_bin" --version 2> /dev/null | cut -d' ' -f1)
if [ "$installed" != "$OPENRIG_VERSION" ]; then
  echo "installing @openrig/cli@$OPENRIG_VERSION under node@$NODE_VER (was: ${installed:-none})"
  mise exec "node@$NODE_VER" -- npm install -g --no-fund --no-audit "@openrig/cli@$OPENRIG_VERSION"
fi

# The wrapper in commands/.local/bin is what puts node@$NODE_VER first on PATH.
rig() { PATH="$node_dir/bin:$PATH" "$rig_bin" "$@"; }

changed=
set_key() {
  if [ "$(rig config get "$1" 2> /dev/null)" != "$2" ]; then
    rig config set "$1" "$2" > /dev/null
    echo "set $1 = $2"
    changed=1
  fi
}
set_key daemon.host 127.0.0.1
set_key terminal.tmux_server isolated
set_key provider.selected claude

if [ -n "$changed" ] && rig daemon status > /dev/null 2>&1; then
  echo "note: daemon already running; daemon.* and terminal.* apply at the next 'rig daemon stop && rig daemon start --no-kernel'"
fi

if [ -n "$pi_seat" ]; then
  : "${LITELLM_GATEWAY:?LITELLM_GATEWAY unset — set it in ~/.config/dotfiles/local.env}"
  home=${OPENRIG_HOME:-$HOME/.openrig}
  dir=$home/state/pi/$pi_seat/agent
  out=$dir/models.json
  if [ -e "$out" ]; then
    echo "exists, left alone: $out"
  else
    mkdir -p "$dir"
    # Pi passes no custom provider key into a seat's environment, so the key is
    # resolved by command at request time. dotfiles-secrets reads the session
    # cache (no network) and works without XDG_RUNTIME_DIR in the env.
    umask 077
    cat > "$out" << EOF
{
  "providers": {
    "litellm": {
      "name": "LiteLLM",
      "baseUrl": "${LITELLM_GATEWAY%/}/v1",
      "api": "openai-completions",
      "apiKey": "!dotfiles-secrets --get PI_API_KEY",
      "models": [
        { "id": "role/agent", "name": "role/agent" },
        { "id": "role/reasoning", "name": "role/reasoning" },
        { "id": "role/completion", "name": "role/completion" }
      ]
    }
  }
}
EOF
    echo "wrote $out (seat model: litellm/role/agent)"
  fi
fi
