#!/usr/bin/env python3
"""Controlli sull'AUDIO generato (docs/21): non si può ascoltare, quindi si misura il segnale.

- manifest (assets_plan/audio_manifest.csv) coerente con i contesti di AudioManager.gd e con i file in game/assets/audio;
- limiti di tools/make_audio.py (LIMITS): picco <= -1 dBFS, nessun clipping, tracce livellate entro 3 dB di loudness
  stimata, durata 24-48 s, spettro non stridulo, nessun click al punto di loop, nessun silenzio, peso totale <= 12 MB;
- determinismo: lo stesso nome produce gli stessi byte (un effetto e una traccia).

Uso: python tests/test_audio_levels.py   (esce con 0 se tutto va bene; collegato a tools/check_all.py)
Se non c'è ffmpeg gli OGG non si possono decodificare: i controlli sul segnale sono saltati (restano quelli sui file).
"""
import csv
import hashlib
import os
import re
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_audio as ma  # noqa: E402

errors = []


def check(cond, msg):
    if not cond:
        errors.append(msg)


def manifest_vs_code():
    gd = open(os.path.join(ROOT, "game", "src", "autoload", "AudioManager.gd"), encoding="utf-8").read()
    block = gd[gd.index("const CONTEXT_TRACKS"):]
    block = block[:block.index("\n}\n")]
    in_code = {}
    for m in re.finditer(r'"(\w+)": \[([^\]]*)\]', block):
        in_code[m.group(1)] = re.findall(r'"(mus_\w+)"', m.group(2))
    rows = list(csv.DictReader(open(os.path.join(ROOT, "assets_plan", "audio_manifest.csv"), encoding="utf-8")))
    in_manifest = {}
    for r in rows:
        if r["categoria"] == "music":
            in_manifest.setdefault(r["contesto"], []).append(r["id"])
    check(in_code == in_manifest, "contesti di AudioManager.gd e manifest non coincidono")
    in_specs = {}
    for sp in ma.MUSIC_SPECS:
        in_specs.setdefault(sp["ctx"], []).append(sp["name"])
    check(in_code == in_specs, "contesti di AudioManager.gd e MUSIC_SPECS non coincidono")
    for ctx, tracks in in_code.items():
        check(len(tracks) >= 2, "contesto %s con una sola variante" % ctx)
    base_ids = re.findall(r'"(\w+)"', re.search(r"const BASE_SFX_IDS[^=]*=\s*\[(.*?)\]", gd, re.S).group(1))
    gen_ids = sorted(k for k in ma.SFX if not k.startswith("sk_"))
    check(sorted(base_ids) == gen_ids, "BASE_SFX_IDS di AudioManager.gd e SFX di make_audio.py non coincidono: %s" % (
        sorted(set(base_ids) ^ set(gen_ids)),))
    for k in ma.SFX:
        check(ma.sfx_category(k) in ("skill", "ui", "combat", "stinger"), "categoria sconosciuta per " + k)
    sk = [r["id"] for r in rows if r["categoria"] == "sfx_skill"]
    check(len(sk) == 51, "attese 51 varianti di mansione, trovate %d" % len(sk))
    base = os.path.join(ROOT, "game", "assets", "audio")
    for r in rows:
        sub = "music" if r["categoria"] == "music" else "sfx"
        ok = any(os.path.exists(os.path.join(base, sub, r["id"] + e)) for e in (".ogg", ".wav"))
        check(ok, "file mancante per %s" % r["id"])


def levels():
    if not ma.have_ogg() and not any(f.endswith(".wav") for _, f, _ in ma.audio_files(os.path.join(ROOT, "game", "assets", "audio"))):
        print("ffmpeg assente e nessun WAV: controlli sul segnale saltati")
        return
    rows = ma.measure_all(os.path.join(ROOT, "game", "assets", "audio"))
    check(len(rows) >= 100, "troppo pochi file audio (%d)" % len(rows))
    for b in ma.check_rows(rows):
        errors.append(b)
    mus = [r for r in rows if r["kind"] == "music"]
    check(len(mus) == len(ma.MUSIC_SPECS), "tracce musicali: %d invece di %d" % (len(mus), len(ma.MUSIC_SPECS)))
    sk = [r["lufs"] for r in rows if r["file"].startswith("sk_")]
    check(sk and max(sk) - min(sk) <= 4.0, "effetti delle mansioni non livellati (scarto > 4 dB)")


def determinism():
    if not ma.have_ogg():
        return
    with tempfile.TemporaryDirectory() as td:
        hashes = []
        for _ in range(2):
            out = []
            for name in ("sk_smithing_2", "ui_achievement"):
                x = ma.limit_peak(ma.SFX[name](ma.rng_for(name)))
                p = os.path.join(td, name + ".ogg")
                ma.write_ogg(p, x, 3)
                out.append(hashlib.sha1(open(p, "rb").read()).hexdigest())
            x = ma.MUSIC["mus_prestige_2"]()
            p = os.path.join(td, "m.ogg")
            ma.write_ogg(p, x, 3)
            out.append(hashlib.sha1(open(p, "rb").read()).hexdigest())
            hashes.append(out)
        check(hashes[0] == hashes[1], "la generazione non è deterministica")


def main():
    manifest_vs_code()
    levels()
    determinism()
    if errors:
        print("AUDIO: %d problemi" % len(errors))
        for e in errors:
            print(" -", e)
        return 1
    print("AUDIO OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
