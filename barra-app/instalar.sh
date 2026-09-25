#!/bin/bash
# Compila o app de barra de menu e instala em ~/Applications/Tarefas.app, abrindo no login.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Tarefas.app"
pkill -x Tarefas 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
swiftc -O main.swift -o "$APP/Contents/MacOS/Tarefas" -framework Cocoa -framework WebKit
codesign -s - --force "$APP" >/dev/null 2>&1
osascript -e 'tell application "System Events" to if not (exists login item "Tarefas") then make login item at end with properties {path:"'"$APP"'", hidden:true}' >/dev/null
open "$APP"
echo "Tarefas instalado em $APP"
