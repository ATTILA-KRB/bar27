#!/bin/bash
# Build Release, notarisation Apple (clé API App Store Connect), agrafage, puis contrôle Gatekeeper.
# Variables : ASC_KEY_PATH (.p8), ASC_KEY_ID, ASC_ISSUER_ID. Sortie : build/Bar27.app agrafée + build/Bar27-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
# Valeurs locales hors dépôt : scripts/notarize.local.env (ignoré par git).
[ -f scripts/notarize.local.env ] && source scripts/notarize.local.env
: "${ASC_KEY_PATH:?ASC_KEY_PATH manquant}" "${ASC_KEY_ID:?ASC_KEY_ID manquant}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID manquant}"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
CONFIG=Release scripts/build.sh
APP=build/Bar27.app
if codesign -d --entitlements - "$APP" 2>/dev/null | rg -q get-task-allow; then echo "ERREUR : get-task-allow présent"; exit 1; fi
codesign -dvv "$APP" 2>&1 | rg -q '^Timestamp=' || { echo "ERREUR : signature sans horodatage sécurisé"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ZIP=build/Bar27-$VERSION.zip
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --timeout 30m | tee build/notary.log
ID=$(awk '/^  id:/{print $2; exit}' build/notary.log)
if ! rg -q 'status: Accepted' build/notary.log; then
    xcrun notarytool log "$ID" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
    exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"   # zip de distribution, app agrafée
spctl --assess --type execute -vv "$APP"
echo "Notarisée : $APP ($ZIP)"
