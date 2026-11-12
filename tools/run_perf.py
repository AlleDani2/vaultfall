#!/usr/bin/env python3
"""Profilo delle prestazioni (resoconto docs/audit_2026-10-22/100_RESOCONTO_PRESTAZIONI.md).

Uso:  python tools/run_perf.py fixture [ore]      costruisce il salvataggio di prova (bot + ore "via" + Deposito pieno)
      python tools/run_perf.py startup|screens|leak|save|idle [etichetta]
                                                  esegue il modo sotto Xvfb con rendering software (OpenGL/Mesa)
      python tools/run_perf.py all [etichetta]    tutti i modi, uno dopo l'altro (serie: niente misure in parallelo)

Variabile GODOT_BIN = eseguibile di Godot 4.7.2. Il salvataggio di prova sta in user://perf_fixture/ (cartella del
profilo utente di Godot, mai nei salvataggi veri). I risultati (JSON) vengono copiati in reports/perf/<etichetta>/.
I tempi sono di CPU del thread principale (PerfGate.clock_usec): non dipendono dal carico della macchina.
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get("PERF_GAME") or os.path.join(ROOT, "game")
MODES = ["startup", "screens", "leak", "save", "idle"]


def godot():
    exe = os.environ.get("GODOT_BIN")
    if not exe or not os.path.exists(exe):
        sys.exit("Imposta GODOT_BIN con il percorso di Godot 4.7.2")
    return exe


def user_dir():
    # use_custom_user_dir=true, nome VAULTFALL: ~/.local/share/VAULTFALL (Linux)
    return os.path.join(os.path.expanduser("~/.local/share"), "VAULTFALL")


def run_fixture(hours):
    cmd = [godot(), "--headless", "--path", GAME, "-s", "res://scripts/perf_fixture.gd", "--", str(hours)]
    print(" ".join(cmd))
    return subprocess.call(cmd)


def run_mode(mode, label, extra=()):
    extra = list(extra) + os.environ.get("PERF_ARGS", "").split()
    cmd = ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24", godot(), "--path", GAME, "--rendering-driver", "opengl3",
           "--resolution", "1280x720", *(["--fixed-fps", "60"] if mode in ("screens", "leak", "who") else []), "-s", "res://scripts/perf_profile.gd", "--", mode, *extra]
    print(" ".join(cmd))
    code = subprocess.call(cmd)
    src = os.path.join(user_dir(), "perf_out", mode + ".json")
    if os.path.exists(src):
        out = os.path.join(ROOT, "reports", "perf", label)
        os.makedirs(out, exist_ok=True)
        shutil.copy(src, os.path.join(out, mode + ".json"))
    return code


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    mode = sys.argv[1]
    if mode == "fixture":
        sys.exit(run_fixture(sys.argv[2] if len(sys.argv) > 2 else "50"))
    label = sys.argv[2] if len(sys.argv) > 2 else "corrente"
    for m in (MODES if mode == "all" else [mode]):
        run_mode(m, label)


if __name__ == "__main__":
    main()
