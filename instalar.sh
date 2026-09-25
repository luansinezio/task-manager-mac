#!/bin/bash
# Instala tudo: servidor local, app de barra de menu e (se tiver Übersicht) o widget da mesa.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

command -v python3 >/dev/null || { echo "Falta o python3. Rode: xcode-select --install"; exit 1; }
command -v swiftc  >/dev/null || { echo "Falta o swiftc. Rode: xcode-select --install"; exit 1; }

echo "1/3  Servidor local (http://localhost:8790)"
"$DIR/scripts/instalar.sh"

echo "2/3  App Tarefas na barra de menu"
"$DIR/barra-app/instalar.sh"
# O canto superior direito passa a abrir a lista; desliga o Canto Ativo do macOS nesse canto pra não abrir os dois.
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-tr-modifier -int 0
killall Dock

echo "3/3  Widget da mesa"
if [ -d "/Applications/Übersicht.app" ]; then
  W="$HOME/Library/Application Support/Übersicht/widgets"
  mkdir -p "$W"
  ln -sfn "$DIR/widget/task-manager.jsx" "$W/task-manager.jsx"
  osascript -e 'tell application "System Events" to if not (exists login item "Übersicht") then make login item at end with properties {path:"/Applications/Übersicht.app", hidden:true}' >/dev/null
  open -a "Übersicht"
  echo "     Widget instalado."
else
  echo "     Übersicht não encontrado, widget pulado. Pra ter: brew install --cask ubersicht && ./instalar.sh"
fi

echo
echo "Pronto. Abra http://localhost:8790 ou encoste o mouse no canto superior direito da tela."
