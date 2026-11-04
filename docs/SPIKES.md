# Phase 0 — sondes (macOS 27.0.1, build 26A434, MacBook Pro Mac17,7 à encoche, 1512 pt de large)

## A. Inventaire AX — `swift Spikes/ax-dump.swift` ✅

- Chaque process expose ses items sous l'attribut `AXExtrasMenuBar` ; les items système (horloge, batterie, Wi‑Fi, Control Center, bouton de débordement) appartiennent à `com.apple.MenuBarAgent` (pid unique).
- Relevé : 20 items, 13 apps propriétaires. `AXIdentifier` vide pour tous ; titres souvent vides → identité = bundleID + rang, pas le titre.
- macOS 27 a son **propre débordement** à l'encoche : item MenuBarAgent « Afficher les éléments masqués de la barre des menus » ; les items repliés derrière lui rapportent tous x ≈ 856–868 (cadres empilés) → ne pas déduire la visibilité du cadre.
- **Coût : 1,9 s** en balayant séquentiellement les 129 apps (timeout AX 250 ms). À faire en phase 1 : ne balayer que les apps connues pour avoir des items + balayage parallèle + cache court (Ice : 120 ms).

## B. Assertion assessment mode — `Spikes/assertion/run.sh` ⚠️ partiel

- `MenuBarClientCore` se charge, les classes `MBAssessmentModeConfiguration` / `MBAssessmentModeAssertion` répondent aux 3 sélecteurs.
- App `.app` signée Developer ID (équipe 5FMH389VS7) : activation **acceptée sans erreur en 71 ms**, `invalidate` OK, process terminé proprement.
- **Effet visuel non vérifié** : Dia était en plein écran, la barre des menus était masquée et les captures sont noires. À relancer hors plein écran : `Spikes/assertion/run.sh` puis comparer `shots/0-avant.png`, `1-pendant.png`, `2-apres.png` (attendu pendant : seuls Claude + items système visibles).

## C. Spacer — non lancé

Repli seulement. Ice 2 le plafonne à ½ écran sur macOS 27 et le réserve aux configurations à encoche. À sonder seulement si B échoue.

## D. Clic système pendant une assertion — repris des mesures d'Ice (PR #995), à revérifier en phase 2

Les clics sur l'horloge, la batterie ou le Wi‑Fi sont ignorés tant que l'assertion est active. Il faut retenir le clic, lever l'assertion, puis le rejouer. Une levée de 80 ms ou plus fait passer 16 clics sur 16 ; à 60 ms, 1 sur 16 est perdu. Control Center s'ouvre par `AXPress` sans levée. Appliquer une assertion bloque MenuBarAgent 100 à 150 ms.

## Verdict provisoire

Go probable : API présente, acceptée pour une app signée, latence faible. Le go définitif dépend de la vérification visuelle de B.
