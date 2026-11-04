#!/bin/bash
# Construit Bar27 en Release, arrête l'instance en cours (SIGTERM : tout est rallumé) et installe dans /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=Release scripts/build.sh
pkill -TERM -x Bar27 2>/dev/null && { for _ in $(seq 1 20); do pgrep -x Bar27 >/dev/null || break; sleep 0.25; done; } || true
rm -rf /Applications/Bar27.app
ditto build/Bar27.app /Applications/Bar27.app
codesign --verify --strict /Applications/Bar27.app
spctl --assess --type execute -vv /Applications/Bar27.app 2>&1 | head -2 || true
open /Applications/Bar27.app
echo "Installé : /Applications/Bar27.app"
