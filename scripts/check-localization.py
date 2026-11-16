#!/usr/bin/env python3
"""Verifie le catalogue Bar27/Resources/Localizable.xcstrings.

- chaque entree a une traduction fr et en non vide (ou des variations de pluriel) ;
- les specificateurs de format (%@, %lld...) sont identiques entre la cle et chaque traduction ;
- chaque chaine litterale localisable du code (String(localized:), Text, Button, Toggle,
  Picker, TableColumn, Label, LabeledContent, confirmationDialog) a une entree.
"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((root / "Bar27/Resources/Localizable.xcstrings").read_text())
strings = catalog["strings"]
errors = []
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f)")


def specs(text):
    return sorted(re.sub(r"\d+\$", "", s) for s in SPEC.findall(text))


def leaf_values(entry):
    """Valeurs (par langue) d'une entree, pluriels inclus."""
    out = {}
    for lang, loc in entry.get("localizations", {}).items():
        if "stringUnit" in loc:
            out[lang] = [loc["stringUnit"].get("value", "")]
        elif "variations" in loc:
            vals = []
            for kind in loc["variations"].values():
                vals += [v["stringUnit"].get("value", "") for v in kind.values()]
            out[lang] = vals
    return out


for key, entry in strings.items():
    values = leaf_values(entry)
    for lang in ("fr", "en"):
        if not values.get(lang) or not all(v.strip() for v in values[lang]):
            errors.append(f"{key!r}: traduction {lang} manquante")
            continue
        for v in values[lang]:
            if specs(v) != specs(key):
                errors.append(f"{key!r}: formats differents en {lang} ({v!r})")

# --- Chaines litterales du code -------------------------------------------------------
CALL = re.compile(r'(?:String\(localized:|\b(?:Text|Toggle|Button|Picker|TableColumn|Label|LabeledContent|confirmationDialog)\()\s*"')


def read_literal(src, i):
    """Lit un litteral a partir de l'apres-guillemet ouvrant ; rend (cle normalisee, fin)."""
    out, depth = [], 0
    while i < len(src):
        c = src[i]
        if c == "\\" and src[i + 1] == "(":
            out.append("%")
            i += 2
            depth = 1
            while depth:  # interpolation, avec chaines imbriquees
                c = src[i]
                if c == '"':
                    _, i = read_literal(src, i + 1)
                    continue
                depth += (c == "(") - (c == ")")
                i += 1
            continue
        if c == "\\":
            out.append(src[i:i + 2].encode().decode("unicode_escape") if src[i + 1] in '"\\' else src[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    return "".join(out), i


normalized = {SPEC.sub("%", k): k for k in strings}
for path in sorted((root / "Bar27").rglob("*.swift")):
    src = path.read_text()
    for m in CALL.finditer(src):
        key, _ = read_literal(src, m.end())
        if not re.search(r"[A-Za-zÀ-ÿ]", key.replace("%", "")):
            continue  # vide, symbole ou simple interpolation
        if key not in normalized:
            line = src.count("\n", 0, m.start()) + 1
            errors.append(f"{path.relative_to(root)}:{line}: {key!r} absent du catalogue")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"localisation : {len(strings)} entrees fr/en completes")
