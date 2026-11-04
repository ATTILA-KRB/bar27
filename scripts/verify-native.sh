#!/bin/bash
# Bout en bout, backend natif (exige l'accès complet au disque pour Bar27.app ; lancé par `open`
# pour avoir l'identité TCC de l'app). Usage : scripts/verify-native.sh [bundleID]
set -uo pipefail
cd "$(dirname "$0")/.."
T=${1:-com.openai.codex}
VDIR="${TMPDIR:-/tmp}/bar27-verify"; mkdir -p "$VDIR" build/verify
L="$VDIR/layout-native.json"; E="$VDIR/layout-empty.json"
printf '{"sections":{"%s":"hidden"},"version":1}' "$T" > "$L"; printf '{"sections":{},"version":1}' > "$E"
[ -x build/click-probe ] || swiftc -O -o build/click-probe Spikes/click-probe.swift 2>/dev/null
[ -x build/mba-capture ] || swiftc -O -o build/mba-capture Spikes/mba-capture.swift 2>/dev/null
BIN=build/Bar27.app/Contents/MacOS/Bar27
FAIL=0
check() { if [ "$2" == "$3" ]; then echo "  OK   $1 ($2)"; else echo "  ÉCHEC $1 : obtenu '$2', attendu '$3'"; FAIL=1; fi; }
state() { local o="$VDIR/native-state.txt"; rm -f "$o"; open -n build/Bar27.app --args --native "$o"
          for _ in $(seq 1 40); do [ -s "$o" ] && break; sleep 0.25; done
          awk -v t="$T" '$1==t{print $2} /^ERREUR/{print "ERREUR"}' "$o"; }
running() { pgrep -f "$BIN -LayoutPath" >/dev/null && echo oui || echo non; }
launch() { open -n build/Bar27.app --args -LayoutPath "$1" -HidingBackend native -AutoRehideDelay 0; sleep 3.5; }
hotkey() { osascript -e 'tell application "System Events" to key code 11 using {control down, option down, command down}'; sleep 1.5; }
clockx() { $BIN --dump-items | python3 -c 'import json,sys;i=[i for i in json.load(sys.stdin)["items"] if i["id"].startswith("com.apple.MenuBarAgent")];c=max(i,key=lambda i:int(i["x"]));print(int(c["x"])+int(c["w"])//2)'; }
START=$(date '+%Y-%m-%d %H:%M:%S')

echo "1. État initial"; check "$T autorisé" "$(state)" true
echo "2. Lancement, $T masqué"; launch "$L"
check "$T éteint" "$(state)" false
$BIN --dump-items > "$VDIR/dump.json"
# En natif, MenuBarAgent garde l'élément AX de l'app éteinte (pas de signal de visibilité) :
# le masquage se vérifie sur la capture build/verify/native-masque-0.png.
echo "     item $T encore dans l'AX : $(python3 -c "import json;print(any(i['id'].startswith('$T#') for i in json.load(open('$VDIR/dump.json'))['items']))") (normal en natif)"
echo "     icône Bar27 : $(python3 -c "import json;print([(i['x'],i['w']) for i in json.load(open('$VDIR/dump.json'))['items'] if 'Bar27' in i['id']])")"
build/mba-capture build/verify/native-masque >/dev/null
echo "3. Clics horloge (aucun relais attendu)"
X=$(clockx); OK=0; for i in 1 2 3 4; do R=$(build/click-probe "$X" 12); echo "     $R"; [[ $R == OUVERT* ]] && OK=$((OK+1)); sleep 0.4; done
check "clics système" "$OK/4" "4/4"
echo "4. Raccourci : révéler puis remasquer"
hotkey; check "$T rallumé (révélé)" "$(state)" true
hotkey; check "$T éteint (remasqué)" "$(state)" false
echo "5. SIGTERM : tout rallumer"
pkill -TERM -f "$BIN -LayoutPath"; sleep 1.5
check "processus arrêté" "$(running)" non
check "$T rallumé après SIGTERM" "$(state)" true
echo "6. SIGKILL puis relance : récupération"
launch "$L"; check "$T éteint" "$(state)" false
pkill -KILL -f "$BIN -LayoutPath"; sleep 1
check "$T reste éteint après SIGKILL" "$(state)" false
launch "$E"; check "$T rallumé au lancement suivant" "$(state)" true
pkill -TERM -f "$BIN -LayoutPath"; sleep 1
echo "Journal :"
log show --start "$START" --style compact --info --predicate 'subsystem == "com.attila-krb.Bar27"' 2>/dev/null | rg -o '(Backend : .*|Éteintes.*|Rallumées.*|Clic relayé.*|Natif en échec.*)' | sort | uniq -c | sed 's/^/  /'
[ $FAIL -eq 0 ] && echo "RÉSULTAT : OK" || echo "RÉSULTAT : ÉCHEC"
exit $FAIL
