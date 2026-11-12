#!/usr/bin/env python3
"""
Genera docs/18_schemi_dati.md deducendo i campi di ogni file JSON in data/ (tipi, presenza, esempi).
Uso: python tools/make_schema_doc.py
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os
from collections import OrderedDict, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "docs", "18_schemi_dati.md")


def tname(v):
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, int):
        return "int"
    if isinstance(v, float):
        return "float"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    if isinstance(v, dict):
        if set(v.keys()) == {"it", "en"}:
            return "loc{it,en}"
        return "object"
    if v is None:
        return "null"
    return type(v).__name__


def short(v):
    s = json.dumps(v, ensure_ascii=False)
    return s if len(s) <= 70 else s[:67] + "…"


def describe(objs):
    fields = OrderedDict()
    for o in objs:
        for k, v in o.items():
            f = fields.setdefault(k, {"types": set(), "count": 0, "example": None})
            f["types"].add(tname(v))
            f["count"] += 1
            if f["example"] is None and v not in (None, [], {}):
                f["example"] = v
    return fields


def main():
    files = []
    for dp, _, fs in os.walk(DATA):
        for f in fs:
            if f.endswith(".json"):
                files.append(os.path.relpath(os.path.join(dp, f), DATA).replace("\\", "/"))
    files.sort()
    L = ["# 18 — Schemi dei dati (generato da `tools/make_schema_doc.py`)", "",
         "Ogni file in `data/` è JSON UTF-8. Quasi tutti sono **array di oggetti con `id` univoco**. "
         "I testi visibili sono sempre oggetti `{\"it\": ..., \"en\": ...}` (tipo `loc{it,en}`). "
         "I percorsi delle immagini (`icon`, `portrait`, `banner`) sono già in formato `res://` del progetto Godot.", "",
         "Colonna *Presenza*: in quanti oggetti del file compare il campo (campi opzionali < 100%).", "",
         "Regole generali:", "",
         "- **id**: `snake_case` ASCII, univoco nel proprio file; gli oggetti hanno id univoci in tutto `items/`.",
         "- **Riferimenti**: per id (mai per indice). Il validatore `tools/validate_data.py` controlla tutti i riferimenti.",
         "- **Modificatori**: `{\"key\": \"famiglia[:ambito]\", \"value\": numero, \"mode\": \"add\"|\"more\"}` (docs/14).",
         "- **Quantità**: intero oppure `[min, max]` (estrazione uniforme inclusiva).",
         "- **Probabilità**: `chance` in [0,1] (frazione), `weight` relativo, `*_pct` in percentuale.", ""]
    for rel in files:
        if rel == "manifest.json":
            continue
        with open(os.path.join(DATA, rel), encoding="utf-8") as f:
            d = json.load(f)
        L.append(f"## `{rel}`")
        L.append("")
        if isinstance(d, list) and d and isinstance(d[0], dict):
            L.append(f"Array di **{len(d)}** oggetti.")
            L.append("")
            L.append("| Campo | Tipo | Presenza | Esempio |")
            L.append("|---|---|---|---|")
            for k, f in describe(d).items():
                L.append(f"| `{k}` | {', '.join(sorted(f['types']))} | {f['count'] * 100 // len(d)}% | `{short(f['example'])}` |".replace("|`", "| `"))
            # sotto-oggetti significativi
            subs = defaultdict(list)
            for o in d:
                for k, v in o.items():
                    if isinstance(v, dict) and set(v.keys()) != {"it", "en"} and k not in ("rewards",):
                        subs[k].append(v)
            for k, lst in subs.items():
                if len(lst) < 1:
                    continue
                L.append("")
                L.append(f"Sotto-oggetto `{k}`:")
                L.append("")
                L.append("| Campo | Tipo | Presenza | Esempio |")
                L.append("|---|---|---|---|")
                for kk, f in describe(lst).items():
                    L.append(f"| `{k}.{kk}` | {', '.join(sorted(f['types']))} | {f['count'] * 100 // len(lst)}% | `{short(f['example'])}` |")
        elif isinstance(d, dict):
            L.append("Oggetto con chiavi: " + ", ".join(f"`{k}`" for k in d.keys()))
        L.append("")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("Scritto", OUT, len(L), "righe")


if __name__ == "__main__":
    main()
