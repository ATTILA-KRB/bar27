#!/bin/bash
# Raccourci ⌃⌥⌘B → révélation, puis re-masquage automatique (3 s), lus dans le journal.
set -uo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:-com.openai.codex}
# Layout hors de ~/Documents : sinon Bar27 lancé seul reste bloqué sur l'invite TCC « Documents ».
mkdir -p build/verify; VDIR="${TMPDIR:-/tmp}/bar27-verify"; mkdir -p "$VDIR"; LAYOUT="$VDIR/layout.json"
printf '{"sections":{"%s":"hidden"},"version":1}' "$TARGET" > "$LAYOUT"
[ -x build/warp ] || { printf 'import CoreGraphics\nCGWarpMouseCursorPosition(CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!))\n' > build/verify/warp.swift; swiftc -O -o build/warp build/verify/warp.swift 2>/dev/null; }
# Pointeur hors de la barre : sinon le re-masquage est (à raison) différé.
build/warp 700 500
START=$(date '+%Y-%m-%d %H:%M:%S')
build/Bar27.app/Contents/MacOS/Bar27 -LayoutPath "$LAYOUT" -HidingBackend assessment -AutoRehideDelay 3 &
APP=$!
sleep 3
build/Bar27.app/Contents/MacOS/Bar27 --dump-items | python3 -c 'import json,sys;[print("  icône Bar27 :", i["x"], i["w"]) for i in json.load(sys.stdin)["items"] if "Bar27" in i["id"]]'
# Un CGEvent clavier synthétique n'atteint pas les raccourcis Carbon ; System Events oui.
osascript -e 'tell application "System Events" to key code 11 using {control down, option down, command down}'; sleep 1.5
build/mba-capture build/verify/toggle-revele >/dev/null
sleep 6
build/mba-capture build/verify/toggle-remasque >/dev/null
kill $APP; wait $APP 2>/dev/null
log show --start "$START" --style compact --info --predicate 'subsystem == "com.attila-krb.Bar27" AND (category == "ConcealmentController" OR category == "HotKey")' 2>/dev/null | rg -o '(Plan appliqué.*|Backend.*)' | sed 's/^/  /'
