#!/bin/bash
# Construit un .app minimal signé Developer ID, l'exécute et capture la barre avant/pendant/après.
set -euo pipefail
cd "$(dirname "$0")"; OUT=build/Bar27Spike.app; rm -rf build; mkdir -p "$OUT/Contents/MacOS" shots
swiftc -O -o "$OUT/Contents/MacOS/Bar27Spike" main.swift
cat > "$OUT/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>fr.attila-krb.bar27.spike</string>
<key>CFBundleExecutable</key><string>Bar27Spike</string><key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>27.0</string></dict></plist>
PL
ID=$(security find-identity -v -p codesigning | awk '/Developer ID Application/{print $2; exit}')
codesign --force --options runtime --timestamp=none -s "$ID" "$OUT" && codesign -dv "$OUT" 2>&1 | rg 'Authority=Developer|TeamIdentifier'
LOG=$PWD/shots/log.txt; rm -f "$LOG"
screencapture -x -R 800,0,712,32 shots/0-avant.png
open -n "$OUT" --args "$LOG"
for i in $(seq 1 40); do rg -q ACTIVE "$LOG" 2>/dev/null && break; sleep 0.1; done
sleep 0.6; screencapture -x -R 800,0,712,32 shots/1-pendant.png
for i in $(seq 1 80); do rg -q RELEASED "$LOG" 2>/dev/null && break; sleep 0.1; done
sleep 0.6; screencapture -x -R 800,0,712,32 shots/2-apres.png
cat "$LOG"
