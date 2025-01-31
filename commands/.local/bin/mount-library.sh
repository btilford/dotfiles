#!/usr/bin/env bash

HOME_NET="$(ip -j a | jq -r '.[].addr_info[].local | select(. | contains("192.0.2."))')"

if [ "${HOME_NET}" == "" ]; then
  echo "Away from home network. Skipping mounts"
else
  # sudo mount -t cifs -o soft,credentials=/root/smb-cred,uid=1000,gid=1000,noauto,x-systemd.automount,x-systemd.idle-timeout=10 //192.0.2.10/library "/home/btilford/nas/library"
  sudo mount -o soft 192.0.2.10:/mnt/shares/user-data "/home/btilford/nas/user-data/"
  sudo mount -o soft 192.0.2.10:/mnt/shares/library "/home/btilford/nas/library/"
  sudo mount -o soft 192.0.2.10:/mnt/shares/images "/home/btilford/nas/images/"
fi
