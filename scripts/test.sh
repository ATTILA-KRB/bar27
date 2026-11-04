#!/bin/bash
# Tests du cœur (sans barre des menus) + build signé + inventaire AX.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
(cd Packages/Bar27Core && swift test 2>&1 | tail -1)
scripts/build.sh
build/Bar27.app/Contents/MacOS/Bar27 --dump-items | python3 -c 'import json,sys;d=json.load(sys.stdin);print("inventaire :", d["count"], "items en", d["durationMs"], "ms");assert d["count"]>0'
