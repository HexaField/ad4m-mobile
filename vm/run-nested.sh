#!/bin/bash
# Run Phosh nested in your existing Wayland session (fastest UI iteration)
# Prerequisites: sudo apt install phosh phoc squeekboard
#
# This runs a phone-sized Phosh compositor inside your desktop — no VM needed.
# Native performance, instant startup.

set -euo pipefail

export WLR_BACKENDS=wayland
export GSETTINGS_BACKEND=memory

# Start the compositor
phoc -C /usr/share/phosh/phoc.ini &
PHOC_PID=$!

sleep 1

# Launch Phosh in the nested compositor
WAYLAND_DISPLAY=wayland-1 dbus-run-session /usr/libexec/phosh &
PHOSH_PID=$!

echo "Phosh running nested (compositor PID: $PHOC_PID, shell PID: $PHOSH_PID)"
echo "Press Ctrl+C to stop"

trap "kill $PHOSH_PID $PHOC_PID 2>/dev/null" EXIT
wait $PHOC_PID
