#!/bin/bash
# Instala o Task Manager como serviço do macOS: sobe no login e reinicia se cair.
# Desinstalar tudo: ../desinstalar.sh
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/media.beza.task-manager.plist"
PY="$(command -v python3)"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>media.beza.task-manager</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$DIR/servidor.py</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/task-manager.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/media.beza.task-manager" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Task Manager rodando em http://localhost:8790"
