#!/usr/bin/env bash
# Remove auto-start registration for OpenPaper backend server.
set -euo pipefail

if [[ "$(uname)" == "Darwin" ]]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/com.openpaper.server.plist"
    if [[ -f "$PLIST_PATH" ]]; then
        launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
        rm -f "$PLIST_PATH"
        echo "Removed launchd plist: $PLIST_PATH"
    else
        echo "No launchd plist found at $PLIST_PATH"
    fi

elif pidof systemd &>/dev/null || systemctl --user &>/dev/null 2>&1; then
    SERVICE_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SERVICE_DIR/openpaper.service"
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl --user stop openpaper.service 2>/dev/null || true
        systemctl --user disable openpaper.service 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl --user daemon-reload
        echo "Removed systemd user service: openpaper.service"
    else
        echo "No systemd service file found at $SERVICE_FILE"
    fi

else
    echo "Unsupported platform: $(uname)." >&2
    exit 1
fi
