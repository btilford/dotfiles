#!/usr/bin/env bash
#
# Mount the NAS shares, but only when on the home network.
#
# Host and subnets are machine-local — they identify private infrastructure, so
# they are not committed. They live in ~/.config/dotfiles/local.env, which is
# untracked and read by every shell plus the systemd user session.
#
# Plain KEY=VALUE, no quotes and no expansion — systemd's environment.d reads
# this same file verbatim and supports neither. That is also why an optional
# variable is COMMENTED OUT rather than left empty: systemd rejects a bare `VAR=`.
#
#   NAS_HOST=nas.example.lan
#   NAS_SHARE_ROOT=/mnt/pool0             # path exported by the NAS
#   #NAS_MOUNT_ROOT=                      # optional, defaults to ~/nas
#   #NAS_SHARES=                          # optional, space separated
#   #HOME_NET_PREFIXES=                   # optional, ERE alternation e.g. 192\.168\.(1|2)
#
# `dotfiles-local-env --check` reports which of these are set, against the
# manifest in commands/.local/share/dotfiles/required-env.
#
# Each share in NAS_SHARES is mounted from NAS_SHARE_ROOT/<name> to
# NAS_MOUNT_ROOT/<name>.

set -uo pipefail

: "${NAS_HOST:?set NAS_HOST — see the comment at the top of this script}"
: "${NAS_SHARE_ROOT:?set NAS_SHARE_ROOT — see the comment at the top of this script}"

NAS_MOUNT_ROOT="${NAS_MOUNT_ROOT:-${HOME}/nas}"
NAS_SHARES="${NAS_SHARES:-user-data library images}"
HOME_NET_PREFIXES="${HOME_NET_PREFIXES:-10\\.(0|1)}"

HOME_NET="$(ip -j a | jq -r --arg re "^${HOME_NET_PREFIXES}\\.[0-9]{1,3}\\.[0-9]{1,3}\$" \
  '.[].addr_info[].local | select(. | test($re))')"

if [ "${HOME_NET}" == "" ]; then
  echo "Away from home network. Skipping mounts"
else
  for share in ${NAS_SHARES}; do
    sudo mount -o soft \
      "${NAS_HOST}:${NAS_SHARE_ROOT}/${share}" \
      "${NAS_MOUNT_ROOT}/${share}/"
  done
fi
