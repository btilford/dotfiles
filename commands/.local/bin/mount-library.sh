#!/usr/bin/env bash
#
# Mount the NAS shares, but only when on the home network.
#
# Host and subnets are machine-local — they identify private infrastructure, so
# they are not committed. Set them in ~/.config/fish/conf.d/local.fish (or the
# shell equivalent), which is untracked:
#
#   set -gx NAS_HOST        10.0.0.1
#   set -gx NAS_SHARE_ROOT  /mnt/shares          # path exported by the NAS
#   set -gx NAS_MOUNT_ROOT  ~/nas              # optional, defaults to ~/nas
#   set -gx NAS_SHARES      'user-data library images'   # optional
#   set -gx HOME_NET_PREFIXES '10\.(33|101)'   # optional, ERE alternation
#
# Each share in NAS_SHARES is mounted from NAS_SHARE_ROOT/<name> to
# NAS_MOUNT_ROOT/<name>.

set -uo pipefail

: "${NAS_HOST:?set NAS_HOST — see the comment at the top of this script}"
: "${NAS_SHARE_ROOT:?set NAS_SHARE_ROOT — see the comment at the top of this script}"

NAS_MOUNT_ROOT="${NAS_MOUNT_ROOT:-${HOME}/nas}"
NAS_SHARES="${NAS_SHARES:-user-data library images}"
HOME_NET_PREFIXES="${HOME_NET_PREFIXES:-10\\.(0|1|2|3)}"

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
