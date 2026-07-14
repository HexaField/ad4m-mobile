#!/bin/sh
# WE kiosk session — started by display manager as a wayland session
# AD4M executor must be running (systemd service)

squeekboard &
exec cage -- chromium --kiosk --app=http://localhost:12000/we --enable-features=UseOzonePlatform --ozone-platform=wayland
