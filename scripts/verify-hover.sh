#!/bin/bash
# Usage : [HOVER=NO] [HOVER_X=x|clock] [EXPECT=none] scripts/verify-hover.sh
# Méthode de secours : survol d'une zone vide de la barre → révélation, puis re-masquage (3 s) une fois sorti.
set -uo pipefail
cd "$(dirname "$0")/.."
T=${1:-com.openai.codex}
VDIR="${TMPDIR:-/tmp}/bar27-verify"; mkdir -p "$VDIR"; L="$VDIR/layout-hover.json"
printf '{"sections":{"%s":"hidden"},"version":1}' "$T" > "$L"
[ -x build/warp ] || { printf 'import CoreGraphics\nCGWarpMouseCursorPosition(CGPoint(x: Double(CommandLine.arguments[1])!, y: Double(CommandLine.arguments[2])!))\n' > "$VDIR/warp.swift"; swiftc -O -o build/warp "$VDIR/warp.swift" 2>/dev/null; }
build/warp 700 500
START=$(date '+%Y-%m-%d %H:%M:%S')
build/Bar27.app/Contents/MacOS/Bar27 -LayoutPath "$L" -HidingBackend assessment -AutoRehideDelay 3 -RevealOnHover ${HOVER:-YES} -Onboarded YES &
APP=$!
sleep 3
# Zone vide cherchée à chaque fois : elle dépend des menus de l'app au premier plan.
[ -x build/empty-x ] || swiftc -O -o build/empty-x Spikes/empty-x.swift 2>/dev/null
# HOVER_X=clock : centre de l'horloge mesuré masquage actif (les icônes se décalent sous assertion).
if [ "${HOVER_X:-}" == clock ]; then
    X=$(build/Bar27.app/Contents/MacOS/Bar27 --dump-items | python3 -c 'import json,sys;i=[i for i in json.load(sys.stdin)["items"] if i["id"].startswith("com.apple.MenuBarAgent")];c=max(i,key=lambda i:int(i["x"]));print(int(c["x"])+int(c["w"])//2)')
else
    X=${HOVER_X:-$(build/empty-x)}
fi
echo "Survol x=$X"
build/warp "$X" 10; sleep 1.5
build/warp 700 500; sleep 5
kill $APP; wait $APP 2>/dev/null
P=$(log show --start "$START" --style compact --info --predicate 'subsystem == "com.attila-krb.Bar27" AND category == "ConcealmentController"' 2>/dev/null | rg -o 'Plan appliqué :.*' | sed 's/Plan appliqué : *//; s/^$/(rien)/' | paste -sd '>' -)
echo "Séquence : $P"
# EXPECT=none : contrôle négatif (option coupée, ou HOVER_X sur une icône) → jamais révélé.
WANT="$T>(rien)>$T"; [ "${EXPECT:-reveal}" == none ] && WANT="$T"
[ "$P" == "$WANT" ] && echo "RÉSULTAT : OK" || { echo "RÉSULTAT : ÉCHEC (attendu $WANT)"; exit 1; }
