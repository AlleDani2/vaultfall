#!/usr/bin/env python3
"""
Estrae TUTTI i testi {it,en} dei dati in un CSV per traduttori (una riga per testo, con percorso di origine).
Uso: python tools/export_strings.py [--lang de]   -> build/strings_for_translation.csv
Per aggiungere una lingua: tradurre la colonna vuota e reimportarla nel generatore (aggiungere la chiave lingua ai dizionari L()).
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import csv, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
lang = sys.argv[sys.argv.index("--lang") + 1] if "--lang" in sys.argv else "new"
rows = []


def walk(o, path):
    if isinstance(o, dict):
        if set(o.keys()) >= {"it", "en"} and all(isinstance(o[k], str) for k in ("it", "en")):
            rows.append([path, o["en"], o["it"], o.get(lang, "")])
            return
        for k, v in o.items():
            walk(v, f"{path}.{k}" if path else k)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            key = v.get("id", i) if isinstance(v, dict) else i
            walk(v, f"{path}[{key}]")


for dp, _, fs in os.walk(DATA):
    for f in sorted(fs):
        if f.endswith(".json"):
            rel = os.path.relpath(os.path.join(dp, f), DATA).replace("\\", "/")
            walk(json.load(open(os.path.join(dp, f), encoding="utf-8")), rel)
os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
out = os.path.join(ROOT, "build", "strings_for_translation.csv")
with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["path", "en", "it", lang])
    w.writerows(rows)
print(f"{len(rows)} testi esportati in {out}")
