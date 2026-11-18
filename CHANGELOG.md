# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- "Open Settings" for Full Disk Access now shows a small guide next to the System Settings window, with the Bar27 icon to drag into the list. It follows the window and closes on its own once access is granted.

### Fixed
- Clicking a system icon (battery, Wi‑Fi, sound, Control Center) while Spotlight is hidden no longer makes the whole menu bar slide and come back, and no longer opens the wrong menu when a "Now Playing" item is around. Bar27 now presses the icon through Accessibility without lifting the hiding. The clock still needs a brief lift; its click is replayed once the bar has settled, on the clock itself.

## [0.2.1] - 2026-11-17

### Fixed
- With "Also hide Spotlight" on, clicking Wi‑Fi opened the battery menu and clicking the battery opened Spotlight. Lifting the hiding briefly brings Spotlight back and shifts the system icons; the relayed click is now replayed on the icon you clicked, at its new position.
- System icon positions are refreshed after every hide/reveal, including native hiding, so clicks are no longer relayed (or dropped) based on stale positions.

## [0.2.0] - 2026-11-16

### Added
- English interface: the app now follows the system language (English or French), via a String Catalog (French source language). `scripts/check-localization.py` checks the catalog and runs in `scripts/test.sh`.
- Status menu now reports when "Open at Login" fails or needs approval in System Settings (it used to fail silently).
- English and French screenshots of the arrange window.
- English README, French README (`README.fr.md`), issue forms, PR template, contributing guide.

### Fixed
- Demo mode: the arrange window footer said "none" for hidden apps while some were filed as Hidden.
- The icon count in the footer now reads "1 icon" / "1 icône" instead of "1 icônes".

## [0.1.0] - 2026-11-16

### Added
- Menu bar manager for macOS 27: per-app *Visible*, *Hidden* and *Always hidden* states.
- Click, hover and <kbd>⌃⌥⌘B</kbd> reveal, with adjustable auto re-hide.
- Native per-app hiding when Full Disk Access is granted, assertion fallback otherwise.
- Option to also hide Spotlight and system items not tracked natively.
- App icon, install and notarisation scripts.
