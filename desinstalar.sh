#!/bin/bash
# Remove servidor, app de barra de menu e widget. As tarefas (dados/tarefas.json) ficam.
launchctl bootout "gui/$(id -u)/media.beza.task-manager" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/media.beza.task-manager.plist"
pkill -x Tarefas 2>/dev/null
osascript -e 'tell application "System Events" to if (exists login item "Tarefas") then delete login item "Tarefas"' >/dev/null 2>&1
rm -rf "$HOME/Applications/Tarefas.app"
rm -f "$HOME/Library/Application Support/Übersicht/widgets/task-manager.jsx"
"$(cd "$(dirname "$0")" && pwd)/scripts/conectar-ia.sh" --remover
echo "Removido. Suas tarefas continuam em dados/tarefas.json."
