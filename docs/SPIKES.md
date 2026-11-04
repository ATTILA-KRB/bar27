# Phase 0 — sondes (macOS 27.0.1, build 26A434, MacBook Pro Mac17,7 à encoche, 1512 pt de large)

## A. Inventaire AX — `swift Spikes/ax-dump.swift` ✅

- Chaque process expose ses items sous l'attribut `AXExtrasMenuBar` ; les items système (horloge, batterie, Wi‑Fi, Control Center, bouton de débordement) appartiennent à `com.apple.MenuBarAgent` (pid unique).
- Relevé : 20 items, 13 apps propriétaires. `AXIdentifier` vide pour tous ; titres souvent vides → identité = bundleID + rang, pas le titre.
- macOS 27 a son **propre débordement** à l'encoche : item MenuBarAgent « Afficher les éléments masqués de la barre des menus » ; les items repliés derrière lui rapportent tous x ≈ 856–868 (cadres empilés) → ne pas déduire la visibilité du cadre.
- **Coût : 1,9 s** en balayant séquentiellement les 129 apps (timeout AX 250 ms). À faire en phase 1 : ne balayer que les apps connues pour avoir des items + balayage parallèle + cache court (Ice : 120 ms).

## B. Assertion assessment mode — `Spikes/assertion/run.sh` ✅

- `MenuBarClientCore` se charge, les classes `MBAssessmentModeConfiguration` / `MBAssessmentModeAssertion` répondent aux 3 sélecteurs.
- App `.app` signée Developer ID (équipe 5FMH389VS7) : activation **acceptée sans erreur en 71 ms**, `invalidate` OK, process terminé proprement.
- **Effet visuel vérifié** : pendant l'assertion, seuls Claude (allowlisté) et les items système restent ; tout réapparaît après `invalidate`.
- Capture : `screencapture` rend du noir quand une app est en plein écran (barre cachée). En revanche, ScreenCaptureKit capture les fenêtres de MenuBarAgent (couche 24, 1512×33, `onScreen=false`) même en plein écran → `Spikes/mba-capture.swift`. Initialiser `NSApplication.shared` avant, sinon `CGS_REQUIRE_INIT` fait avorter le binaire.

## C. Spacer — non lancé

Repli seulement. Ice 2 le plafonne à ½ écran sur macOS 27 et le réserve aux configurations à encoche. À sonder seulement si B échoue.

## D. Clic système pendant une assertion — repris des mesures d'Ice (PR #995), à revérifier en phase 2

Les clics sur l'horloge, la batterie ou le Wi‑Fi sont ignorés tant que l'assertion est active. Il faut retenir le clic, lever l'assertion, puis le rejouer. Une levée de 80 ms ou plus fait passer 16 clics sur 16 ; à 60 ms, 1 sur 16 est perdu. Control Center s'ouvre par `AXPress` sans levée. Appliquer une assertion bloque MenuBarAgent 100 à 150 ms.

## Verdict : GO (04/11/2026)

## Phase 1 — socle ✅

- `swift test` : 7 tests du planificateur et du stockage (Bar27Core).
- `scripts/build.sh` : app signée Developer ID (Debug comprise : `ENABLE_DEBUG_DYLIB=NO`).
- Lecture AX parallèle : **588 ms** contre 1,9 s en séquentiel.
- `scripts/verify-conceal.sh com.openai.codex` : seule Codex disparaît (les icônes repliées à l'encoche reprennent sa place), puis tout revient.
- Lancée, l'app publie son icône (`com.attila-krb.Bar27`)… **repliée derrière le débordement de l'encoche** (x = 869), comme toute nouvelle icône. À traiter en phase 2 : l'icône Bar27 doit rester accessible.
