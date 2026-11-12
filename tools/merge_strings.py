#!/usr/bin/env python3
"""
Unisce i file di stringhe per area (localization/parts/*.csv, colonne keys,en,it) in localization/ui_strings.csv
e copia il risultato in game/localization/. Idempotente: le righe delle parti sostituiscono quelle con la stessa chiave.
Ogni agente scrive SOLO il proprio file parts/<area>.csv (chiavi con prefisso UI_<AREA>_) per non confliggere.
Uso: python tools/merge_strings.py
"""
import csv, glob, os, shutil, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "localization", "ui_strings.csv")


def read(p):
    with open(p, encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def main():
    rows = read(BASE)
    head, body = rows[0], rows[1:]
    index = {r[0]: i for i, r in enumerate(body) if r}
    for part in sorted(glob.glob(os.path.join(ROOT, "localization", "parts", "*.csv"))):
        for r in read(part)[1:]:
            if not r or not r[0].strip():
                continue
            r = (r + ["", ""])[:3]
            if r[0] in index:
                body[index[r[0]]] = r
            else:
                index[r[0]] = len(body)
                body.append(r)
    with open(BASE, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(head)
        w.writerows(body)
    dst = os.path.join(ROOT, "game", "localization", "ui_strings.csv")
    shutil.copyfile(BASE, dst)
    print(f"{len(body)} stringhe in {dst}")


if __name__ == "__main__":
    sys.exit(main())
