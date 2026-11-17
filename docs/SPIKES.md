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

## Phase 2 — constats (2026-11-04)

- **Relais de clics (assertion)** : `scripts/verify-click-bridge.sh` donne 6/6 et 8/8 clics sur l'horloge qui ouvrent le Centre de notifications, en 190–245 ms contre 150 ms sans Bar27. Le contrôle négatif (`EXTRA_ARGS="-DisableClickBridge YES"`) donne 0/4 : le relais est bien nécessaire et efficace.
- **Raccourci ⌃⌥⌘B (Carbon)** : il fonctionne. Un `CGEvent` clavier synthétique ne l'atteint pas, alors qu'un `osascript`/System Events l'atteint. C'est donc une limite de l'injecteur de test, pas de l'app.
- **Re-masquage auto** : il est différé si un menu est ouvert ou si le pointeur est dans la barre. Le cycle masqué → révélé → remasqué en 3 s est validé (`scripts/verify-toggle.sh`). Piège : `-Clé 3` passé en argument arrive comme une chaîne, il faut donc lire avec `double(forKey:)`.
- **Icône de Bar27 sous assertion** : MenuBarAgent la retire aussi (dans l'AX, x = 7 ; à l'écran, elle n'est pas dessinée), même quand elle est dans l'allowlist. Ice fait le même constat (`Concealer27.swift`). Il ne reste donc que le raccourci pour révéler. Une fois révélée sans section « toujours masquée », l'assertion est levée et l'icône revient.
- **Interrupteur natif** (`trackedApplications`, `group.com.apple.controlcenter`) : sans accès complet au disque, sandboxd refuse `kTCCServiceSystemPolicyAppDataDetailed`, avec « user interaction not allowed » et sans invite. Une fois l'accès accordé à Bar27.app (lancée par `open`), `scripts/verify-native.sh` passe entièrement :
  - masquage effectif, confirmé par capture ;
  - l'icône de Bar27 reste visible ;
  - 4/4 clics système sans relais ;
  - le raccourci rallume puis éteint ;
  - après un SIGTERM, tout est rallumé ;
  - après un SIGKILL, l'app reste éteinte puis se rallume au lancement suivant.

  L'élément AX de l'app éteinte reste présent : sa présence ne prouve pas qu'elle est visible.
- **Piège de test** : Bar27 lancé seul et qui lit un fichier dans `~/Documents` reste bloqué sur l'invite TCC « Documents ». Les layouts de test sont donc placés dans `$TMPDIR/bar27-verify`.

## Phase 3 — usage réel (2026-11-04)

- Révélation au survol d'une zone vide (secours : seul accès sans l'icône, retirée sous assertion). Zone vide = `AXUIElementCopyElementAtPosition` rend `AXMenuBar` (et non `AXMenuBarItem`) ; test hors fil principal, seulement pointeur dans la barre, 0,35 s d'arrêt, une fois par survol. `scripts/verify-hover.sh` + négatifs (`HOVER=NO`, `HOVER_X=clock`).
- Piège de test : la zone vide dépend des menus de l'app au premier plan (Dia jusqu'à x = 620) et les icônes se décalent sous assertion → x mesurés à chaque passage (`Spikes/empty-x.swift`, `--dump-items`), jamais codés en dur.
- Fenêtre « Organiser » : liste les apps rangées même absentes de la barre (non lancées, ou masquées donc invisibles à l'AX), suivi des autorisations toutes les 2 s, bascule de méthode sans relance (contrôle toutes les 5 s, sauf échec d'écriture native), réglages, remise à zéro. Ouverte au premier lancement et sur double-clic Finder (`applicationShouldHandleReopen`).

## Apps non masquées en natif (2026-11-15)

- **Assistant porteur de l'icône** : l'icône de Gemini appartient à `com.google.GeminiMacOS.launcher` (`Gemini.app/Contents/Helpers/GeminiAppLauncher.app`), mais `trackedApplications` la range sous `com.google.GeminiMacOS`. Invariant : le layout garde le bundleID du propriétaire AX ; l'interrupteur natif résout la clé suivie en remontant les `.app` englobantes (`TrackedApplications.trackedKey`, `NativeAllowListBackend.containingBundleIDs`).
- **Éléments système hors interrupteur** : Spotlight (`com.apple.campo`, « Siri AI.app ») n'est pas dans `trackedApplications` ; sa préférence `NSStatusItem VisibleCC Item-0` (domaine `com.apple.campo`) n'est pas relue à chaud (vérifié : écrite à false, l'item reste). En natif il reste donc visible ; Bar27 le signale (`unconcealable`, fenêtre Organiser) au lieu de l'ignorer en silence. Seule l'assertion le masque : option « Masquer aussi Spotlight et les éléments système » (`ConcealSystemItems`), assertion limitée au résidu non suivi, interrupteur natif pour le reste. Vérifié par capture : Spotlight masqué, icône Bar27 **toujours visible** (contrairement à l'assertion seule de la phase 2), journal `VisibilityRestrictionAssertion session activated`.

## Relais de clic : AXPress d'abord, levée seulement pour l'horloge (2026-11-17)

- **Symptôme** : avec « Masquer aussi Spotlight » (assertion résiduelle), un clic sur la batterie fait glisser toute la barre puis la ramène, et ouvre parfois le mauvais panneau (Wi‑Fi → batterie, batterie → Spotlight, horloge → Control Center). C'est intermittent.
- **Cause** : sous assertion, MenuBarAgent ignore les clics souris. L'ancien relais levait donc l'assertion et rejouait le clic. Mais la levée réaffiche ce que l'assertion masque : Spotlight, et « **À l'écoute** » si un média a joué récemment (d'où l'intermittence). La barre glisse (−32 pt) **et les items changent de rang** : « À l'écoute » s'insère avant le Wi‑Fi. Rejouer aux coordonnées d'origine, comme en 0.2.0, ou au rang d'origine, comme en 0.2.1, visait le voisin. La recomposition arrive 90 à 340 ms après la levée ; un clic rejoué avant est souvent perdu.
- **Faits mesurés** (macOS 27.0.1) :
  - Chaque item système est un `AXHostingView` ; son enfant `AXMenuBarItem` porte `AXIdentifier` (`com.apple.menuextra.{sound,now-playing,wifi,battery,controlcenter,clock}`) et l'action `AXPress`.
  - **`AXPress` est honoré sous assertion** pour le son, le Wi‑Fi, la batterie et Control Center (16/16), en environ 25 ms et sans rien lever.
  - L'horloge renvoie un succès à `AXPress` sans rien ouvrir. `postToPid` et `cgSessionEventTap` restent ignorés eux aussi.
- **Invariants** (`ClickBridgeRule`) :
  1. Un item s'identifie par `AXIdentifier`, jamais par rang ni par coordonnées.
  2. On essaie `AXPress` d'abord, sans levée (`canPress`). Seule l'horloge (`pressIgnored`) ou un `AXPress` refusé passe par la levée.
  3. Après une levée, on attend que la barre soit stable (deux lectures identiques après un changement, plafond de 450 ms), puis on rejoue dans le nouveau cadre de l'item retrouvé par identifiant.
  4. Les items système sont relus après **chaque** application, y compris en natif.
- **Vérifié** sur le binaire installé :
  - AXPress : 16/16 (son, Wi‑Fi, batterie, Control Center), et la barre reste immobile pendant le clic sur la batterie.
  - Horloge : 12/12. La sonde `nctrace` suit le Centre de notifications ; `which` se trompe quand un panneau reste ouvert d'un essai à l'autre.
- **Les assertions ne se cumulent pas** : la dernière posée l'emporte. Un `--conceal` lancé pendant que Bar27 tourne réaffiche Spotlight.
