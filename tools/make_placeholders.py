#!/usr/bin/env python3
"""
Crea immagini SEGNAPOSTO per ogni percorso di immagine citato nei dati, così il gioco è giocabile prima dell'arte.
Uso: python tools/make_placeholders.py [--force] [--out CARTELLA]
- Scrive in game/assets/... (se game/ esiste) altrimenti in build/placeholder_assets/...
- Non sovrascrive file esistenti (le immagini vere hanno la precedenza) a meno di --force.
- Dimensioni native secondo assets_plan/asset_specs.json (stesse della pipeline dell'arte).
Richiede: pip install pillow
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os, sys, zlib
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
SPECS = json.load(open(os.path.join(ROOT, "assets_plan", "asset_specs.json"), encoding="utf-8"))
FORCE = "--force" in sys.argv
OUT_ROOT = os.path.join(ROOT, "game") if os.path.isdir(os.path.join(ROOT, "game")) else os.path.join(ROOT, "build", "placeholder_assets")
if "--out" in sys.argv:
    OUT_ROOT = sys.argv[sys.argv.index("--out") + 1]

CAT_COLORS = {"material": (120, 92, 60), "food": (196, 120, 48), "potion": (120, 60, 160), "ammo": (110, 110, 110),
              "glyph": (40, 120, 140), "equipment": (90, 100, 120), "tool": (100, 84, 64), "key": (200, 170, 60),
              "crate": (150, 110, 50), "skin": (75, 105, 255), "relic": (228, 174, 57), "seed": (80, 140, 60),
              "currency": (210, 190, 80), "consumable": (60, 140, 120), "cosmetic": (140, 140, 180), "openable": (130, 100, 70),
              "quest": (200, 60, 60), "misc": (90, 90, 90)}
RARITY = {"rare": (75, 105, 255), "epic": (136, 71, 255), "legendary": (211, 44, 230), "mythic": (235, 75, 75), "relic": (228, 174, 57)}


def spec_for(path):
    best = None
    for prefix, sp in SPECS["by_path_prefix"].items():
        if path.startswith(prefix) and (best is None or len(prefix) > len(best[0])):
            best = (prefix, sp)
    return best[1] if best else {"w": 32, "h": 32}


def collect():
    refs = {}

    def walk(o, ctx):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, str) and v.startswith("res://assets/"):
                    refs[v] = ctx if ctx else o
                else:
                    walk(v, o if "id" in o else ctx)
        elif isinstance(o, list):
            for v in o:
                walk(v, ctx)
    for dp, _, fs in os.walk(DATA):
        for f in fs:
            if f.endswith(".json"):
                walk(json.load(open(os.path.join(dp, f), encoding="utf-8")), None)
    return refs


def initials(o):
    name = o.get("name", {}).get("en") if isinstance(o.get("name"), dict) else o.get("id", "?")
    words = [w for w in str(name).replace("'", " ").split() if w[:1].isalnum()]
    return ("".join(w[0] for w in words[:2]) or "?").upper()


def manifest_only_refs():
    """Immagini dell'interfaccia (kind=ui) presenti solo nel manifest: servono al tema di Godot."""
    import csv
    path = os.path.join(ROOT, "assets_plan", "asset_manifest.csv")
    out = {}
    if not os.path.exists(path):
        return out
    for r in csv.DictReader(open(path, encoding="utf-8")):
        if r["kind"] == "ui":
            res = "res://" + r["file"][len("game/"):] if r["file"].startswith("game/") else r["file"]
            out[res] = {"name": {"en": r["asset_id"].replace("ui_", "").replace("_", " ")}, "category": "ui",
                        "_w": int(r["w"]), "_h": int(r["h"])}
    return out


def main():
    refs = collect()
    refs.update({k: v for k, v in manifest_only_refs().items() if k not in refs})
    font = ImageFont.load_default()
    made = 0
    for path, o in sorted(refs.items()):
        rel = path.replace("res://", "")
        dst = os.path.join(OUT_ROOT, rel)
        if os.path.exists(dst) and not FORCE:
            continue
        sp = spec_for(path) if "_w" not in o else {"w": o["_w"], "h": o["_h"]}
        w, h = sp["w"], sp["h"]
        cat = o.get("category", "")
        base = RARITY.get(o.get("rarity")) or CAT_COLORS.get(cat) or tuple(40 + zlib.crc32((rel + str(i)).encode()) % 160 for i in range(3))
        if "_locked" in path:
            g = int(sum(base) / 3)
            base = (g, g, g)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle([1, 1, w - 2, h - 2], fill=base + (255,), outline=(20, 20, 20, 255))
        d.rectangle([2, 2, w - 3, h - 3], outline=tuple(min(255, c + 60) for c in base) + (255,))
        txt = initials(o)
        tw = d.textlength(txt, font=font)
        d.text(((w - tw) / 2, h / 2 - 6), txt, fill=(255, 255, 255, 255), font=font)
        t = o.get("tier")
        if isinstance(t, int) and w >= 32:
            d.text((3, h - 12), str(t), fill=(255, 240, 160, 255), font=font)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        img.save(dst)
        made += 1
    print(f"Segnaposto creati: {made} (riferimenti totali {len(refs)}) in {OUT_ROOT}")


if __name__ == "__main__":
    main()
