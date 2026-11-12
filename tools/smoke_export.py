#!/usr/bin/env python3
"""Prova di fumo dell'export Linux: scompatta lo zip (o usa una cartella) e fa due prove con una cartella utente isolata:
  1. AVVIO VERO (se c'e' xvfb-run): `Vaultfall.x86_64` per 300 fotogrammi con schermo virtuale, rendering OpenGL (Compatibility);
     il log non deve avere ERROR / Parse Error / Failed to load (gli avvisi ALSA/V-Sync dell'ambiente senza scheda audio si ignorano).
  2. GIOCO DAL PACCHETTO: `GODOT_BIN --headless --main-pack Vaultfall.x86_64 --script tools/smoke_export.gd` (le build di rilascio
     ignorano --script, quindi si usa il binario normale di Godot sullo stesso pacchetto): dati, IT/EN, risorse, nuova partita,
     10 minuti simulati, salvataggio e ricaricamento in user://. Controlla anche che accanto all'eseguibile non nasca nulla.
Uso: GODOT_BIN=... python tools/smoke_export.py <VAULTFALL_x_linux.zip | cartella con Vaultfall.x86_64>
Verifica: righe 'SMOKE FAIL', 'ERROR', 'Parse Error', 'Failed to load' nel log; nessun file nuovo accanto all'eseguibile;
i salvataggi finiscono in <XDG_DATA_HOME>/VAULTFALL/saves."""
import os, shutil, subprocess, sys, tempfile, zipfile, re

# rumore dell'ambiente di prova (nessuna scheda audio) e perdite innocue alla chiusura del motore
IGNORA = re.compile(r"ALSA|status < 0|audio_driver|resources still in use at exit")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    work = tempfile.mkdtemp(prefix="vf_smoke_")
    if src.endswith(".zip"):
        with zipfile.ZipFile(src) as z:
            z.extractall(work)
        folder = os.path.join(work, os.listdir(work)[0])
    else:
        folder = src
    exe = os.path.join(folder, "Vaultfall.x86_64")
    os.chmod(exe, 0o755)
    before = sorted(os.listdir(folder))
    home = os.path.join(work, "home")
    env = dict(os.environ, XDG_DATA_HOME=os.path.join(home, "data"), XDG_CONFIG_HOME=os.path.join(home, "config"))
    problems = []
    log = ""
    godot = os.environ.get("GODOT_BIN", "").strip()
    if shutil.which("xvfb-run"):
        env1 = dict(env, XDG_DATA_HOME=os.path.join(home, "start", "data"))
        try:
            r1 = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1600x900x24", "timeout", "60", exe, "--rendering-driver", "opengl3", "--quit-after", "300"],
                                env=env1, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", timeout=180)
        except subprocess.TimeoutExpired:
            r1 = None
        out1 = r1.stdout if r1 else ""
        bad1 = [l for l in out1.splitlines() if re.search(r"\bERROR\b|SCRIPT ERROR|Parse Error|Failed to load", l) and not IGNORA.search(l)]
        print("Avvio vero sotto xvfb:", "ERRORI" if bad1 else "pulito (uscita %s)" % (r1.returncode if r1 else "?"))
        problems += ["avvio vero: " + l for l in bad1[:10]]
    else:
        print("xvfb-run non trovato: salto l'avvio vero")
    if not godot or not os.path.exists(godot):
        sys.exit("Imposta GODOT_BIN (Godot 4.7.2) per la prova dal pacchetto.")
    r = subprocess.run([godot, "--headless", "--main-pack", exe, "--script", os.path.join(ROOT, "tools", "smoke_export.gd")], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", timeout=600)
    log = r.stdout
    smoke = [l for l in log.splitlines() if l.startswith("SMOKE")]
    print("\n".join(smoke))
    bad = [l for l in log.splitlines() if re.search(r"\bERROR\b|SCRIPT ERROR|Parse Error|Failed to load|FAIL", l) and not IGNORA.search(l)]
    after = sorted(os.listdir(folder))
    if r.returncode != 0:
        problems.append("codice di uscita %d" % r.returncode)
    if bad:
        problems.append("righe di errore nel log:\n    " + "\n    ".join(bad[:15]))
    if after != before:
        problems.append("file nuovi accanto all'eseguibile: %s" % sorted(set(after) - set(before)))
    udir = os.path.join(home, "data", "VAULTFALL")
    if not os.path.isdir(udir):
        problems.append("cartella utente %s non creata" % udir)
    print("Cartella utente:", udir, sorted(os.listdir(udir)) if os.path.isdir(udir) else "-")
    print("PROVA DI FUMO " + ("OK" if not problems else "FALLITA\n  - " + "\n  - ".join(problems)))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
