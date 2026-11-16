# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
