#!/usr/bin/env bash

# Pixel 8 Pro Dimensions
WLR_RENDERER=headless krfb-virtualmonitor \
    wayland \
    --resolution 1344x2992 \
    --name pixel-8-pro \
    --password abc \
    --port 5900 &

# Samsung Tablet Dimensions
WLR_RENDERER=headless krfb-virtualmonitor \
    wayland \
    --resolution 2304x1440 \
    --name galaxy-tab-s9-fe \
    --password abc \
    --port 5901 &
