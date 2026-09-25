#!/bin/bash
# Compila o app e instala em ~/Applications/Tarefas.app. Na primeira vez ele mesmo se registra pra abrir no login
# (dá pra desligar nos ajustes, na engrenagem do painel).
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Tarefas.app"
pkill -x Tarefas 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp AppIcon.icns "$APP/Contents/Resources/"
swiftc -O main.swift -o "$APP/Contents/MacOS/Tarefas" -framework Cocoa -framework WebKit
codesign -s - --force "$APP" >/dev/null 2>&1
open "$APP"
echo "Tarefas instalado em $APP"
