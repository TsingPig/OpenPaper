#!/usr/bin/env bash
# Install auto-start for OpenPaper backend server.
# - macOS:   registers a launchd user agent (Login Item)
# - Linux:   registers a systemd user service
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

detect_python() {
    # Prefer the project .venv, then uv run, then system python3.
    if command -v uv &>/dev/null && uv run --python python3 -c "" 2>/dev/null; then
        echo "uv run python"
    elif command -v python3 &>/dev/null; then
        echo "python3"
    else
        echo "python3"  # best-effort; will fail at runtime if missing
    fi
}

if [[ "$(uname)" == "Darwin" ]]; then
    PLIST_PATH="$HOME/Library/LaunchAgents/com.openpaper.server.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    PYTHON_CMD="$(detect_python)"

    cat > "$PLIST_PATH" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openpaper.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_CMD</string>
        <string>$PROJECT_DIR/backend/server.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$PROJECT_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$PROJECT_DIR/waatchdog.log</string>
    <key>StandardErrorPath</key>
    <string>$PROJECT_DIR/waatchdog.log</string>
</dict>
</plist>
PLISTEOF

    launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
    echo "launchd plist installed at $PLIST_PATH"
    echo "Service started. Status:"
    launchctl list com.openpaper.server 2>/dev/null || echo "  (check $PROJECT_DIR/waatchdog.log)"

elif pidof systemd &>/dev/null || systemctl --user &>/dev/null 2>&1; then
    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"

    PYTHON_CMD="$(detect_python)"

    cat > "$SERVICE_DIR/openpaper.service" <<SERVICEEOF
[Unit]
Description=OpenPaper paper management server
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_CMD $PROJECT_DIR/backend/server.py
WorkingDirectory=$PROJECT_DIR
Restart=on-failure
RestartSec=5
StandardOutput=append:$PROJECT_DIR/waatchdog.log
StandardError=append:$PROJECT_DIR/waatchdog.log

[Install]
WantedBy=default.target
SERVICEEOF

    systemctl --user daemon-reload
    systemctl --user enable openpaper.service
    systemctl --user restart openpaper.service
    echo "systemd user service installed."
    echo "Status:"
    systemctl --user status openpaper.service --no-pager --lines=0

else
    echo "Unsupported platform: $(uname). Manual setup required." >&2
    exit 1
fi
