# Bar27 — gestionnaire de barre des menus pour macOS 27

> Nom : **Bar27**. Licence : **GPLv3, open source**. Cible : **macOS 27 uniquement**.
> Swift 6 + SwiftUI/AppKit, distribution Developer ID (équipe 5FMH389VS7) + Sparkle, hors Mac App Store.
> Décisions du 04/11/2026. Résultats de la phase 0 : `docs/SPIKES.md`.

## 1. Objectif

Ranger les icônes de la barre des menus (status items tiers + extras système) :
masquer, révéler à la demande, organiser par sections, afficher les éléments cachés
dans une barre secondaire, le tout sans dégrader l'usage des icônes système.

## 2. Réalité technique (constatée, nov. 2026)

| Fait | Source / preuve |
|---|---|
| macOS 27 dessine **tous** les items dans un seul process `MenuBarAgent` ; plus de fenêtre par item, `CGWindowList` ne les décrit plus. | `pgrep` local : `/System/Library/CoreServices/MenuBarAgent.app` actif ; Ice PR #995 |
| Items, cadres et propriétaires se lisent par **Accessibility** sur `MenuBarAgent`. | Ice PR #995 (`MenuBarItemProvider27`) |
| Masquage fiable = assertion privée **assessment mode** (`MenuBarClientCore` : `MBAssessmentModeConfiguration` / `MBAssessmentModeAssertion`), allowlist par app, honorée seulement pour une app **signée Developer ID**. | Framework présent : `/System/Library/PrivateFrameworks/MenuBarClientCore.framework` ; PR #995 |
| Pendant une assertion, `MenuBarAgent` **ignore les clics** sur horloge/batterie/Wi‑Fi (et Globe+N) → il faut intercepter le clic, lever ~80–120 ms, rejouer. Control Center s'ouvre par `AXPress` sans levée. | Mesures PR #995 |
| macOS 27 **réordonne lui-même** les items : plus de réorganisation fine ; granularité = **une app** (toutes ses icônes ensemble). | PR #995, notes Ice 2 |
| Méthode publique alternative : **spacer** (`NSStatusItem` à longueur énorme qui pousse les items hors écran), plafonnée à ~½ largeur d'écran sur 27, utile surtout sur écran à encoche. | Ice 2 (`MacOS27HidingMode spacer\|assessment`) |
| Captures d'items : plus de capture par fenêtre ; on découpe une capture ScreenCaptureKit de la barre (260–290 ms). `CGWindowListCreateImage` indisponible dans le SDK 26+. | PR #995 ; skill macos-swiftui |
| Bartender 7 fonctionne **sans Screen Recording** (icônes d'app à la place des glyphes). | macbartender.com, Lounge blog |

Conséquences produit :
- **Pas de Mac App Store** (API privée + contrôle AX d'autres apps, incompatible sandbox) → Developer ID + notarisation + Sparkle.
- Ice / Thaw / Barometer sont **GPLv3**, comme Bar27 : on **réutilise et adapte** leurs briques éprouvées (assertion, lecture AX, ClickBroker) en gardant l'attribution en tête de fichier. Bar27 reste un code neuf limité à macOS 27 ; on ne forke pas Ice, qui traîne l'héritage de macOS 13 à 26.
- Code fragile par nature : chaque bêta macOS peut casser → architecture à backends interchangeables + sondes de diagnostic.

## 3. Architecture

```
App (SwiftUI + AppKit, LSUIElement)
├─ Core (package SwiftPM pur, testable sans barre)
│   ├─ Model        : MenuBarItem(id app+titre, pid, bundleID, frame), Section(visible|hidden|alwaysHidden), Layout
│   ├─ Planner      : layout → plan de masquage (allowlists), règles de révélation, détection overflow/encoche
│   └─ Persistence  : layout par bundleID (JSON, Application Support), profils
├─ Platform (adaptateurs, derrière protocoles)
│   ├─ ItemProvider     : AX `AXExtrasMenuBar` de chaque process (balayage parallèle + cache)
│   ├─ HidingBackend    : AssessmentBackend (privé, dlopen + garde-fous) | SpacerBackend (public)
│   ├─ ClickBroker      : CGEventTap → hold/lift/replay pour les items système
│   ├─ ImageProvider    : ScreenCaptureKit (optionnel) | NSRunningApplication.icon (fallback)
│   └─ Permissions      : AXIsProcessTrusted, CGPreflightScreenCaptureAccess, onboarding
├─ Features
│   ├─ Reveal       : clic sur l'icône, raccourci global, survol bord, scroll
│   ├─ AutoRehide   : délai, menu encore ouvert ? (détection fenêtre de menu)
│   ├─ SecondaryBar : panneau NSPanel sous la barre listant les items cachés (clic → AXPress)
│   ├─ Search       : palette ⌘⇧Espace sur les items (nom, app)
│   └─ Triggers (v2): batterie, Wi‑Fi, app au premier plan, horaire → révéler une app
└─ UI : popover d'état, Réglages (Général, Sections drag-and-drop, Raccourcis, Apparence, Diagnostic)
```

Principes : `@MainActor` pour l'UI, captures/AX sur files dédiées (une capture bloquée ne doit pas geler le pool Swift — piège mesuré par Ice) ; journal `os.Logger` + écran **Diagnostic** (process répondants, assertion active, latence) pour trier les régressions de bêta.

## 4. Périmètre par version

**MVP (v0.1)** — utile au quotidien
1. Onboarding permissions (Accessibility obligatoire, Screen Recording facultatif).
2. Inventaire des items via AX, groupés par app.
3. Deux sections : visible / caché ; affectation par drag-and-drop dans les Réglages.
4. Masquage/révélation (backend assessment ; spacer en repli), raccourci global, auto‑remasquage.
5. ClickBroker pour horloge, batterie, Wi‑Fi, Notification Center.
6. Lancement à l'ouverture de session (`SMAppService`), persistance du layout.

**v0.2** — confort
- Barre secondaire (icônes d'app ; glyphes réels si Screen Recording accordé).
- Section « toujours caché », révélation au survol/scroll, recherche d'items.
- Multi‑écrans (section appliquée à tous les écrans sur 27, contrainte système).

**v1.0** — version publique
- Apparence (teinte, bordure, coins de la barre) si encore faisable sur 27.
- Triggers, profils (par écran / par lieu), import de layout.
- Notarisation, Sparkle, page GitHub + site, localisation FR/EN (`.xcstrings`).

Hors périmètre : macOS ≤ 26, réordonnancement fin des icônes (macOS 27 l’interdit), version App Store, vente.

## 5. Phases et critères d'acceptation

| Phase | Contenu | Sortie vérifiable |
|---|---|---|
| **0. Spikes (2–3 j)** | Sondes CLI Swift : (a) dump AX de `MenuBarAgent` (titre, pid, frame) ; (b) prise/relâche d'une assertion assessment sur app signée Developer ID ; (c) spacer : largeur max effective sur cet écran ; (d) hold/replay d'un clic horloge. | Rapport `docs/SPIKES.md` avec mesures ; choix du backend par défaut. **Go/no‑go** du projet ici. |
| **1. Socle (3–4 j)** | Projet XcodeGen, package Core + tests, LSUIElement, permissions, logger, signature Developer ID locale. | `xcodebuild test` vert ; app signée qui démarre et liste les items. |
| **2. MVP (1–2 sem.)** | Points 1–6 du MVP. | Script de vérif : cacher/révéler 10×, sans icône fantôme ; clic horloge fonctionne en < 250 ms ; layout survit à un redémarrage. |
| **3. v0.2 (1–2 sem.)** | Barre secondaire, recherche, multi‑écrans, captures SCK. | Vérif sur 2 écrans ; aucun gel si SCK refusé ou bloqué. |
| **4. Release (1 sem.)** | Notarisation, Sparkle, GitHub Releases, FR/EN. | DMG notarisé installé sur un Mac propre ; mise à jour Sparkle testée. |

Vérification continue : tests unitaires du Planner (sans barre) + scripts d'intégration qui pilotent la vraie barre et assertent via AX / `screencapture -R`.

## 6. Risques

| Risque | Mitigation |
|---|---|
| Apple modifie `MenuBarClientCore` / ferme l'assertion | Backend spacer public en repli ; résolution des symboles par `dlsym` avec dégradation propre ; test sur chaque bêta. |
| Clics système perdus pendant le masquage | ClickBroker mesuré (fenêtre de levée ≥ 80 ms), tests répétés 16/16. |
| Gel dû aux captures | Files dédiées, timeouts, Screen Recording optionnel. |
| Concurrence open source (Ice 2, Thaw) | Créneau : app légère dédiée à 27, sans code hérité, UX soignée. |
| Licence GPL | Bar27 en GPLv3 ; attribution d'origine conservée dans chaque fichier adapté. |

## 7. Décisions

- 04/11/2026 : open source GPLv3 ; macOS 27 uniquement ; nom Bar27 ; réutilisation des briques GPL d'Ice (PR #995), Barometer et Thaw.
- Pas de vente : la phase 4 se limite à notarisation, Sparkle, page GitHub/site et FR/EN.

## État phase 2 (2026-11-04)
- Fait : deux backends (natif prioritaire, assertion en repli), relais de clics système, raccourci ⌃⌥⌘B, re-masquage auto, ouverture à la connexion, réglages dans « Organiser la barre ».
- À valider : backend natif avec l'accès complet au disque accordé ; présence de l'icône Bar27 en natif ; moyen de révélation sans raccourci sous assertion (survol ou clic sur la barre vide).
