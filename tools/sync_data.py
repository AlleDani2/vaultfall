#!/usr/bin/env python3
"""
Copia data/ dentro il progetto Godot (game/data/), tests/reference_values.json in game/tests/ e
localization/ui_strings.csv in game/localization/.
Uso: python tools/sync_data.py   (funziona su Windows, Linux e macOS)
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import os, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data")
DST = os.path.join(ROOT, "game", "data")


def main():
    if not os.path.isdir(os.path.join(ROOT, "game")):
        print("Cartella game/ non trovata: crea prima il progetto Godot (milestone M0).")
        return
    if os.path.isdir(DST):
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST)
    n = sum(len(fs) for _, _, fs in os.walk(DST))
    print(f"Copiati {n} file in {DST}")
    ref = os.path.join(ROOT, "tests", "reference_values.json")
    if os.path.exists(ref):
        os.makedirs(os.path.join(ROOT, "game", "tests"), exist_ok=True)
        shutil.copyfile(ref, os.path.join(ROOT, "game", "tests", "reference_values.json"))
        print("Copiato tests/reference_values.json in game/tests/")
    loc = os.path.join(ROOT, "localization", "ui_strings.csv")
    if os.path.exists(loc):
        os.makedirs(os.path.join(ROOT, "game", "localization"), exist_ok=True)
        shutil.copyfile(loc, os.path.join(ROOT, "game", "localization", "ui_strings.csv"))
        print("Copiato localization/ui_strings.csv in game/localization/")


if __name__ == "__main__":
    main()
