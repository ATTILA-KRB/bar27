#!/bin/bash
# Bout en bout : Bar27 masque une app (assertion) et les clics sur l'horloge ouvrent quand même
# le Centre de notifications. Usage : scripts/verify-click-bridge.sh [bundleID] [essais]
set -uo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:-com.openai.codex}; N=${2:-8}
# Layout hors de ~/Documents : sinon Bar27 lancé seul reste bloqué sur l'invite TCC « Documents ».
mkdir -p build/verify; VDIR="${TMPDIR:-/tmp}/bar27-verify"; mkdir -p "$VDIR"; LAYOUT="$VDIR/layout.json"
printf '{"sections":{"%s":"hidden"},"version":1}' "$TARGET" > "$LAYOUT"
[ -x build/click-probe ] || swiftc -O -o build/click-probe Spikes/click-probe.swift 2>/dev/null
[ -x build/mba-capture ] || swiftc -O -o build/mba-capture Spikes/mba-capture.swift 2>/dev/null
clock() { build/Bar27.app/Contents/MacOS/Bar27 --dump-items | python3 -c 'import json,sys;i=[i for i in json.load(sys.stdin)["items"] if i["id"].startswith("com.apple.MenuBarAgent")];c=max(i,key=lambda i:int(i["x"]));print(int(c["x"])+int(c["w"])//2)'; }

echo "--- sans Bar27"
X=$(clock); build/click-probe "$X" 12
build/Bar27.app/Contents/MacOS/Bar27 -LayoutPath "$LAYOUT" -HidingBackend assessment -AutoRehideDelay 0 ${EXTRA_ARGS:-} &
APP=$!
sleep 3
build/mba-capture build/verify/bridge-masque >/dev/null
X=$(clock); echo "--- Bar27 actif ($TARGET masqué), horloge x=$X"
OK=0
for i in $(seq 1 "$N"); do R=$(build/click-probe "$X" 12); echo "  essai $i : $R"; [[ $R == OUVERT* ]] && OK=$((OK+1)); sleep 0.5; done
kill $APP; wait $APP 2>/dev/null
sleep 1; build/mba-capture build/verify/bridge-apres >/dev/null
echo "RÉSULTAT : $OK/$N clics relayés"
log show --last 2m --style compact --info --predicate 'subsystem == "com.attila-krb.Bar27"' 2>/dev/null | rg -o 'Backend.*|Plan appliqué.*|Clic relayé.*|Tap.*' | sort | uniq -c | head
[ "$OK" -eq "$N" ]
