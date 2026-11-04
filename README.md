# Bar27

Gestionnaire de barre des menus pour **macOS 27**, open source (GPLv3) : il masque les icônes
dont vous n'avez pas besoin et les réaffiche d'un clic.

- Clic sur l'icône Bar27 : masquer / afficher les apps rangées dans « Masqué ».
- Clic droit : menu (Tout afficher, Organiser la barre…, Quitter).
- « Organiser la barre » : choisir pour chaque app Visible, Masqué ou Toujours masqué.

macOS 27 masque **par application** et range lui-même les icônes ; Bar27 ne réordonne pas.

## Développement

```sh
scripts/test.sh                 # tests du cœur + build signé + inventaire AX
scripts/build.sh                # build/Bar27.app (Debug, signée Developer ID)
scripts/verify-conceal.sh <id>  # masque une app 3 s, captures dans build/verify/
```

Prérequis : Xcode (SDK macOS 27), XcodeGen, certificat Developer ID (l'assertion de
MenuBarAgent n'est honorée que pour une app signée Developer ID).

Plan : `docs/PLAN.md` · Mesures : `docs/SPIKES.md`.

## Crédits

Le masquage par assertion « assessment mode » est adapté d'[Ice](https://github.com/jordanbaird/Ice)
(PR #995), de [Barometer](https://github.com/mackid1993/Barometer) et de
[Thaw](https://github.com/thaw-app/Thaw), tous sous GPLv3.

## Installation locale

`scripts/install.sh` : build Release signé Developer ID, arrêt propre de l'instance en cours, copie dans `/Applications`, lancement. Accorder ensuite l'accès complet au disque à `/Applications/Bar27.app` (sinon repli sur l'assertion).
