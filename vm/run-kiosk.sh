#!/bin/bash
# Run WE in a phone-sized kiosk window (no phone shell, just WE)
# Prerequisites: sudo apt install cage chromium-browser
#
# Point WE_URL at a running WE dev server or built dist.

set -euo pipefail

WE_URL="${WE_URL:-http://localhost:5173}"
WIDTH="${WIDTH:-390}"
HEIGHT="${HEIGHT:-844}"

cage -- chromium-browser \
    --kiosk \
    --app="$WE_URL" \
    --window-size="${WIDTH},${HEIGHT}" \
    --disable-gpu-compositing \
    --enable-features=UseOzonePlatform \
    --ozone-platform=wayland
