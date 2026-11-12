#!/usr/bin/env python3
"""
Controllo unico del progetto: lancia in sequenza validatore, simulatore, sync, valori di riferimento e (se c'è game/) i test GUT.
Uso: python tools/check_all.py [--senza-gut] [--veloce]
  --veloce: i test GUT girano con "run_tests.py --fast" (senza i playthrough lunghi del bot) per il lavoro quotidiano;
            prima di chiudere un compito/milestone lanciare il controllo completo (senza --veloce).
Esce con 0 e scrive "TUTTO OK" solo se ogni passo riesce.
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PASSI = [
    ("validatore dati", ["validate_data.py"]),
    ("simulatore di bilanciamento", ["balance_sim.py"]),
    ("copia dati nel progetto Godot", ["sync_data.py"]),
    ("valori di riferimento", ["export_reference_values.py"]),
    ("perimetro slice (filtro)", ["scope_filter.py"]),
    ("perimetro slice (verifica)", ["scope_filter.py", "--verify"]),
    ("qualità dell'inglese (tests/test_en_quality.py)", ["../tests/test_en_quality.py"]),
    ("chiavi di interfaccia (tests/test_ui_keys.py: nessuna chiave nuda a schermo)", ["../tests/test_ui_keys.py"]),
    ("coerenza globale (tests/test_coherence.py, controlli QA5)", ["../tests/test_coherence.py"]),
    ("wiki (rigenerazione + test)", ["../tests/test_wiki.py"]),
    ("testi pubblici (tests/test_testi_pubblici.py: Casse, Esc, Impostazioni, terminologia, wiki, store)", ["../tests/test_testi_pubblici.py"]),
    ("rilascio: contatti vuoti = errore con --pubblico (tests/test_release_config.py)", ["../tests/test_release_config.py"]),
    ("audio: livelli, loop e manifest (tests/test_audio_levels.py)", ["../tests/test_audio_levels.py"]),
    ("telai UI (file = generatore, pixel esatti)", ["make_ui_frames.py", "--check"]),
    ("marchio (file = generatore, misure, palette, monocromo, icona)", ["../tests/test_logo.py"]),
]


def lancia(nome, argv):
    print(f"\n=== {nome} ===", flush=True)
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, argv[0]), *argv[1:]], cwd=ROOT)
    return r.returncode == 0


def main():
    falliti = [n for n, a in PASSI if not lancia(n, a)]
    if os.path.isdir(os.path.join(ROOT, "game")) and "--senza-gut" not in sys.argv:
        veloce = "--veloce" in sys.argv
        if not lancia("test GUT" + (" (veloce: senza playthrough lunghi)" if veloce else ""),
                      ["run_tests.py"] + (["--fast"] if veloce else [])):
            falliti.append("test GUT")
    print()
    if "--veloce" in sys.argv:
        print("NB: modalità veloce, i playthrough lunghi del bot NON sono stati eseguiti.")
    if falliti:
        print("FALLITI: " + ", ".join(falliti))
        return 1
    print("TUTTO OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
