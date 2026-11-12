#!/usr/bin/env python3
"""Nessuna chiave nuda a schermo (revisione testi, docs/audit_2026-10-22/86_REVISIONE_TESTI.md).

Controlla che ogni chiave di interfaccia UI_XXX usata nel codice GDScript (game/src, game/scripts) esista in
localization/ui_strings.csv (che nasce dall'unione di localization/parts/*.csv con tools/merge_strings.py) e che sia
tradotta in tutte e due le lingue. Le chiavi costruite a runtime ("UI_FOO_" + id) sono verificate in due modi:
  - il prefisso deve avere almeno una chiave nel CSV;
  - per i suffissi che vengono dai dati (tipi di obiettivo, funzioni sbloccate, rarità, modalità, categorie di Mercato)
    deve esistere la chiave per ogni valore presente nei dati.
Uso: python tests/test_ui_keys.py   (esce con 0 se tutto va bene; collegato a tools/check_all.py)
"""
import csv
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LITERAL = re.compile(r'"(UI_[A-Z0-9_]+)"')


def load_keys():
    keys = {}
    with open(os.path.join(ROOT, "localization", "ui_strings.csv"), encoding="utf-8", newline="") as fh:
        for r in csv.DictReader(fh):
            keys[r["keys"]] = (r.get("it", ""), r.get("en", ""))
    return keys


def code_files():
    out = []
    for sub in ("src", "scripts"):
        out += glob.glob(os.path.join(ROOT, "game", sub, "**", "*.gd"), recursive=True)
    return sorted(out)


def jload(name):
    with open(os.path.join(ROOT, "data", name), encoding="utf-8") as fh:
        return json.load(fh)


def main():
    keys = load_keys()
    errors = []
    used_full, used_prefix = {}, {}
    for f in code_files():
        rel = os.path.relpath(f, ROOT).replace("\\", "/")
        with open(f, encoding="utf-8", errors="ignore") as fh:
            for n, line in enumerate(fh, 1):
                if line.lstrip().startswith("#"):
                    continue
                for m in LITERAL.finditer(line):
                    k = m.group(1)
                    (used_prefix if k.endswith("_") else used_full).setdefault(k, f"{rel}:{n}")
    for k, where in sorted(used_full.items()):
        if k not in keys:
            errors.append(f"{where}: chiave {k} usata nel codice ma assente da ui_strings.csv")
    for k, where in sorted(used_prefix.items()):
        if not any(x.startswith(k) for x in keys):
            errors.append(f"{where}: nessuna chiave con il prefisso {k} in ui_strings.csv")
    for k, (it, en) in sorted(keys.items()):
        if not it.strip() or not en.strip():
            errors.append(f"{k}: testo vuoto in una delle due lingue")

    def need(prefix, values, where):
        for v in values:
            k = prefix + str(v).upper()
            if k not in keys:
                errors.append(f"{k}: manca (valore «{v}» presente in {where})")

    types, feats = set(), set()
    for q in jload("quests.json"):
        for o in q.get("objectives") or []:
            types.add(o["type"])
        for u in q.get("unlocks") or []:
            if u.startswith("feature:"):
                feats.add(u.split(":", 1)[1])
    need("UI_QUESTS_OBJ_", sorted(types), "data/quests.json (obiettivi)")
    need("UI_QUESTS_FEATURE_", sorted(feats), "data/quests.json (sblocchi)")
    need("UI_RARITY_", [r["id"] for r in jload("crate_rules.json")[0]["rarities"]], "data/crate_rules.json")
    modes = list(jload("mode_rules.json")[0]["modes"])
    for p in ("UI_MODES_DESC_", "UI_MODE_"):
        need(p, modes, "data/mode_rules.json")
    need("UI_MARKET_CAT_", jload("market_rules.json")[0]["categories"], "data/market_rules.json")

    for e in errors:
        print("ERRORE:", e)
    print(f"test_ui_keys: {'OK' if not errors else str(len(errors)) + ' problemi'} "
          f"({len(used_full)} chiavi letterali, {len(used_prefix)} prefissi, {len(keys)} chiavi nel CSV)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
