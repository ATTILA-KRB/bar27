#!/bin/bash
# Vérifie de bout en bout que Bar27 masque puis réaffiche une app (captures de MenuBarAgent).
# Usage : scripts/verify-conceal.sh <bundleID> ; puis inspecter build/verify/{avant,pendant,apres}-0.png
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:-com.openai.codex}
CAP=build/mba-capture; [ -x "$CAP" ] || swiftc -O -o "$CAP" Spikes/mba-capture.swift 2>/dev/null
rm -rf build/verify; mkdir -p build/verify
"$CAP" build/verify/avant >/dev/null
build/Bar27.app/Contents/MacOS/Bar27 --conceal "$TARGET" 3 > build/verify/out.txt 2>&1 &
PID=$!
for i in $(seq 1 30); do rg -q 'CONCEALED|ERREUR|RIEN' build/verify/out.txt && break; sleep 0.1; done
sleep 0.5; "$CAP" build/verify/pendant >/dev/null
wait $PID; sleep 0.5; "$CAP" build/verify/apres >/dev/null
cat build/verify/out.txt
