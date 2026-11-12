#!/usr/bin/env python3
"""
Lancia il bot NOVIZIO (game/scripts/bot_novizio.gd, QA 95) in più configurazioni (lingua x risoluzione) e ne riassume i
difetti. Il bot gioca solo con clic e tasti veri sulla UI; serve un display (xvfb-run) e il rendering OpenGL (llvmpipe va bene).

Uso:
    GODOT_BIN=/percorso/godot python tools/run_bot_novizio.py --out /tmp/novizio            # IT+EN x 720p+1080p, 3 h + 10 h
    python tools/run_bot_novizio.py --lang en --res 1280x720 --hours-a 0.5 --hours-b 0.2    # prova veloce
Opzioni: --jobs N (processi in parallelo, default 2) · --fast-until main_c0_q3 (porta la partita a una missione con il bot
diretto: solo per provare stati avanzati) · --only timing,tab,leaks,shortcuts,save (controlli della fase C; vuoto = tutti).
Ogni configurazione scrive <out>/<lingua>_<risoluzione>/{log.txt,findings.json,trace.txt}; alla fine <out>/riepilogo.json.
HOME viene reindirizzata per ogni processo: i salvataggi e le impostazioni dell'utente non si toccano.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_one(godot, out, lang, res, a, b, seed, fast, only):
    name = "%s_%s" % (lang, res)
    d = os.path.join(out, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    home = tempfile.mkdtemp(prefix="novizio_home_")
    env = dict(os.environ, HOME=home, NV_C=only)
    cmd = ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24", godot, "--path", os.path.join(ROOT, "game"),
           "--rendering-driver", "opengl3", "--resolution", res, "-s", "res://scripts/bot_novizio.gd", "--",
           d, lang, str(a), str(b), str(seed)] + ([fast] if fast else [])
    t0 = time.time()
    with open(os.path.join(d, "log.txt"), "w") as log:
        code = subprocess.call(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, cwd=ROOT)
    shutil.rmtree(home, ignore_errors=True)
    return name, code, time.time() - t0


def script_errors(log_path):
    """Errori di Godot (SCRIPT ERROR / ERROR / WARNING) con l'ultima azione del bot prima dell'errore, raggruppati."""
    skip = re.compile(r"ALSA|audio|V-Sync|leaked|still in use|never freed|ObjectDB|cleanup|Utilities|RID allocations|CanvasShader")
    groups, last_act = {}, ""
    lines = open(log_path, errors="replace").read().splitlines()
    for i, line in enumerate(lines):
        if line.startswith("ACT "):
            last_act = line
        elif line.startswith(("SCRIPT ERROR", "ERROR:", "WARNING:")) and not skip.search(line):
            where = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].lstrip().startswith("at:") else ""
            key = line + " | " + where
            g = groups.setdefault(key, {"errore": line, "dove": where, "dopo": last_act, "conteggio": 0})
            g["conteggio"] += 1
    return list(groups.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--lang", default="it,en")
    ap.add_argument("--res", default="1280x720,1920x1080")
    ap.add_argument("--hours-a", type=float, default=3.0)
    ap.add_argument("--hours-b", type=float, default=10.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--fast-until", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot")
    if not godot:
        print("Imposta GODOT_BIN"); return 2
    os.makedirs(a.out, exist_ok=True)
    jobs = [(l, r) for l in a.lang.split(",") for r in a.res.split(",")]
    summary = {}
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(run_one, godot, a.out, l, r, a.hours_a, a.hours_b, a.seed, a.fast_until, a.only) for l, r in jobs]
        for f in futs:
            name, code, secs = f.result()
            d = os.path.join(a.out, name)
            fj = os.path.join(d, "findings.json")
            res = {"exit": code, "wall_s": round(secs)}
            if os.path.exists(fj):
                data = json.load(open(fj))
                kinds = {}
                for x in data["findings"]:
                    kinds[x["kind"]] = kinds.get(x["kind"], 0) + 1
                res.update({"findings": len(data["findings"]), "per_tipo": kinds, "clic": data["stats"].get("clicks"),
                            "play_s": data["stats"].get("play_s")})
            res["errori_godot"] = script_errors(os.path.join(d, "log.txt"))
            summary[name] = res
            print(name, json.dumps({k: v for k, v in res.items() if k != "errori_godot"}), "errori Godot:", len(res["errori_godot"]))
    json.dump(summary, open(os.path.join(a.out, "riepilogo.json"), "w"), indent=2, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
