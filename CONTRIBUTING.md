# Contributing to Bar27

Thanks for helping! Bar27 is GPLv3; contributions are accepted under the same license.

## Setup

```sh
brew install xcodegen
xcodegen            # generates Bar27.xcodeproj from project.yml
scripts/test.sh     # core tests + signed build + accessibility inventory
```

You need macOS 27, Xcode with the macOS 27 SDK and a Developer ID certificate
(the hiding assertion is only honoured for Developer ID–signed apps).

## Workflow

1. Open an issue or a Discussion for anything non-trivial.
2. Branch from `main`, one topic per pull request.
3. Run `scripts/test.sh` before pushing.
4. Commit subjects: short, imperative, English (e.g. `Fix hover reveal on external displays`).
5. Open the PR using the template. PRs are merged with a merge commit, so keep your commits meaningful.

## Rules of thumb

- Never commit secrets. Notarisation keys live in `scripts/notarize.local.env`, which is git-ignored.
- Code adapted from other projects must be GPLv3-compatible and credited in the README.
- Behaviour changes need a note in `CHANGELOG.md` under *Unreleased*.
- Manual checks live in `scripts/verify-*.sh`; see `docs/SPIKES.md` for how the system behaviour was measured.

## Localisation

The interface follows the system language (French and English). Strings live in `Bar27/Resources/Localizable.xcstrings`; the **source language is French**, so the French text is the key. SwiftUI literals (`Text("…")`) are localised automatically; elsewhere use `String(localized: "…")`. Add the English translation to the catalog for every new string. `scripts/check-localization.py` (run by `scripts/test.sh`) fails on a missing fr/en translation, a mismatched format specifier, or a literal string in the code that is not in the catalog.
