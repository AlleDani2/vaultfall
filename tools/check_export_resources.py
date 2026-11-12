#!/usr/bin/env python3
"""Controllo risorse dell'export: ogni percorso res:// citato nel codice (.gd), nelle scene/risorse (.tscn/.tres),
in project.godot, nel preset di export e nei dati JSON deve esistere in game/ e NON essere escluso dall'export
(exclude_filter di game/export_presets.cfg). Controlla anche le icone dei dati (IconLib: assets/icons/<categoria>/<id>.png).
Uso: python tools/check_export_resources.py   -> esce con 1 se manca qualcosa."""
import fnmatch, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
SKIP_DIRS = {".godot", "addons", "tests", "scripts", "store", "export"}     # non finiscono nel gioco
REF = re.compile(r'res://[A-Za-z0-9_./\-]+')


def excludes():
    text = open(os.path.join(GAME, "export_presets.cfg"), encoding="utf-8").read()
    m = re.search(r'^exclude_filter="([^"]*)"', text, re.M)
    return [p.strip() for p in m.group(1).split(",") if p.strip()] if m else []


def is_excluded(rel, pats):
    return any(fnmatch.fnmatch(rel, p) for p in pats)


def sources():
    for base, dirs, files in os.walk(GAME):
        rel_dir = os.path.relpath(base, GAME)
        if rel_dir == ".":
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f.endswith((".gd", ".tscn", ".tres", ".godot", ".cfg", ".json", ".csv")) and not f.endswith("reference_values.json"):
                yield os.path.join(base, f)


def main():
    pats = excludes()
    missing, excluded, n = [], [], 0
    for path in sources():
        rel_src = os.path.relpath(path, GAME)
        try:
            text = open(path, encoding="utf-8").read()
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("#") or line.lstrip().startswith("##"):
                continue
            for m in REF.finditer(line):
                ref = m.group(0).rstrip(".")
                rel = ref[len("res://"):]
                if not rel or rel.endswith("/") or "*" in rel:
                    continue
                n += 1
                full = os.path.join(GAME, rel)
                if os.path.isdir(full):
                    continue
                if not os.path.exists(full):
                    # risorse importate: l'originale deve esistere; .translation sono create dall'import
                    if rel.endswith(".translation") or rel.startswith(".godot/"):
                        continue
                    missing.append((rel_src, lineno, ref))
                elif is_excluded(rel, pats) and not rel_src.startswith(("tests", "scripts")):
                    excluded.append((rel_src, lineno, ref))
    # icone dei dati: stesse regole di IconLib
    icon_missing = icons_from_data()
    print("Riferimenti res:// controllati: %d" % n)
    for t, items in (("MANCANTI", missing), ("ESCLUSI DALL'EXPORT", excluded)):
        print("%s: %d" % (t, len(items)))
        for s, l, r in items[:40]:
            print("   %s:%d  %s" % (s, l, r))
    print("Icone dei dati senza file: %d" % len(icon_missing))
    for r in icon_missing[:40]:
        print("   ", r)
    bad = len(missing) + len(excluded)
    print("RISORSE OK" if bad == 0 else "RISORSE: %d problemi" % bad)
    return 1 if bad else 0


def icons_from_data():
    """Informativo: per ogni tabella con icone dedicate controlla assets/icons/<cat>/<id>.png (se la cartella esiste)."""
    out = []
    icons = os.path.join(GAME, "assets", "icons")
    if not os.path.isdir(icons):
        return out
    cats = {d: set(f[:-4] for f in os.listdir(os.path.join(icons, d)) if f.endswith(".png")) for d in os.listdir(icons)
            if os.path.isdir(os.path.join(icons, d))}
    data = os.path.join(GAME, "data")
    for name, cat in (("crates.json", "crates"), ("abilities.json", "abilities"), ("achievements.json", "achievements")):
        p = os.path.join(data, name)
        if not (os.path.exists(p) and cat in cats):
            continue
        try:
            v = json.load(open(p, encoding="utf-8"))
        except ValueError:
            continue
        rows = v if isinstance(v, list) else next((x for x in v.values() if isinstance(x, list)), [])
        for r in rows:
            if isinstance(r, dict) and r.get("id") and r["id"] not in cats[cat]:
                out.append("%s: %s" % (cat, r["id"]))
    return out


if __name__ == "__main__":
    sys.exit(main())
