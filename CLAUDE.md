# Bar27 (dossier `Bartender/`)

Gestionnaire de barre des menus pour macOS 27 uniquement (Swift 6, SwiftUI/AppKit), GPLv3, hors Mac App Store. Projet XcodeGen (`project.yml`) ; logique dans `Packages/Bar27Core`.

## Doc d'ancrage
- Lire `docs/PLAN.md` (objectif, réalité technique de macOS 27, architecture) et `docs/SPIKES.md` (résultats de phase 0) avant toute tâche non triviale.

## Commandes (vérifiées dans `scripts/`)
- Suite complète : `scripts/test.sh` = `swift test` dans `Packages/Bar27Core` + `scripts/check-localization.py` + `scripts/build.sh` + inventaire `--dump-items` (doit être > 0).
- Build : `scripts/build.sh` (xcodegen + xcodebuild, Debug par défaut, `CONFIG=Release` pour Release) → `build/Bar27.app`, signée Developer ID.
- Installer : `scripts/install.sh [--no-build]` ; notarisation + installation : `scripts/deploy-local.sh`, DMG : `scripts/make-dmg.sh`.
- Vérifications manuelles de la barre (bureau ouvert requis) : `scripts/verify-{native,toggle,hover,conceal,click-bridge}.sh`.

## Pièges
- Le masquage repose sur une API privée (assertion « assessment mode »), honorée seulement pour une app signée Developer ID : un build ad hoc ne masque rien.
- Items lus par Accessibility (permission requise) ; l'ordre des icônes est géré par macOS 27, granularité = une app.
- Le catalogue de localisation est contrôlé par `scripts/check-localization.py` (lancé par `scripts/test.sh`).
- `scripts/notarize.local.env` est ignoré par git (identifiants de notarisation) : ne jamais le committer ni l'afficher.
- Repo public (GPLv3) : aucun secret dans les fichiers versionnés.
