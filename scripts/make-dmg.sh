#!/bin/bash
# DMG de distribution : build/Bar27.app (deja notarisee et agrafee) + lien Applications,
# signe Developer ID, notarise, agrafe, puis controle Gatekeeper. Sortie : build/Bar27-<version>.dmg
# Appele par scripts/notarize.sh ; utilisable seul apres une notarisation de l'app.
# Variables : ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (scripts/notarize.local.env), BAR27_SIGN_IDENTITY (optionnel).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f scripts/notarize.local.env ] && source scripts/notarize.local.env
: "${ASC_KEY_PATH:?ASC_KEY_PATH manquant}" "${ASC_KEY_ID:?ASC_KEY_ID manquant}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID manquant}"
export PATH="/opt/homebrew/bin:$PATH"
command -v create-dmg >/dev/null || { echo "ERREUR : create-dmg absent (brew install create-dmg)"; exit 1; }

APP=build/Bar27.app
xcrun stapler validate "$APP" >/dev/null || { echo "ERREUR : $APP n'est pas agrafee, lancer scripts/notarize.sh"; exit 1; }
# Hash du certificat : deux certificats « Developer ID Application » de meme nom coexistent dans le trousseau.
IDENTITY="${BAR27_SIGN_IDENTITY:-D0F93EE12C167056F3206C7CB7D208C0952E9728}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="build/Bar27-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Bar27.app"
rm -f "$DMG"
create-dmg --volname "Bar27" --window-pos 200 120 --window-size 600 360 --icon-size 112 \
  --icon "Bar27.app" 160 170 --hide-extension "Bar27.app" --app-drop-link 440 170 \
  --no-internet-enable --skip-jenkins "$DMG" "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait --timeout 30m | tee build/notary-dmg.log
rg -q 'status: Accepted' build/notary-dmg.log || { echo "ERREUR : notarisation du DMG refusee"; exit 1; }
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "DMG notarise : $DMG"
