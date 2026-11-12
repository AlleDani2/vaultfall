#!/usr/bin/env python3
"""
Bot CAOTICO (QA 83): lancia game/scripts/chaos_bot.gd su più semi in parallelo, ognuno con la propria cartella dati utente
(XDG_DATA_HOME), un tetto di tempo reale per seme e il riconoscimento dei blocchi (un metodo che non torna mai = hang).
Un blocco viene annotato e il seme rilanciato SENZA quel metodo (--skip), fino a MAX_RESTARTS volte.

Uso:
    python tools/chaos_run.py --seeds 1-50 --hours 20 --jobs 4 --out reports/chaos
    python tools/chaos_run.py --seeds 3 --hours 2 --mode normal
Variabile d'ambiente: GODOT_BIN. Scrive <out>/seed<N>.json (uno per seme) e <out>/riepilogo.json (findings aggregati).
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
MAX_RESTARTS = 4


def parse_seeds(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def run_seed(seed, hours, out_dir, timeout, mode, bot_share, godot, game, ui=False):
    skip = []
    hangs = []
    log_all = []
    for attempt in range(MAX_RESTARTS + 1):
        data_home = tempfile.mkdtemp(prefix="vf_chaos_")
        out = os.path.join(out_dir, "seed%d.json" % seed)
        if os.path.exists(out):
            os.remove(out)
        cmd = [godot, "--headless", "--path", game, "scripts/chaos_bot.tscn", "--", "--seed=%d" % seed,
               "--hours=%s" % hours, "--out=" + out, "--bot=%s" % bot_share]
        if mode:
            cmd.append("--mode=" + mode)
        if ui:
            cmd.append("--ui")
        if skip:
            cmd.append("--skip=" + ",".join(skip))
        env = dict(os.environ, XDG_DATA_HOME=data_home, XDG_CONFIG_HOME=data_home, HOME=data_home)
        t0 = time.time()
        timed_out = False
        logf = os.path.join(out_dir, "seed%d.log" % seed)
        hb = out + ".hb"
        with open(logf, "w") as lf:
            proc = subprocess.Popen(cmd, env=env, stdout=lf, stderr=subprocess.STDOUT)
            while True:
                try:
                    proc.wait(timeout=10)
                    break
                except subprocess.TimeoutExpired:
                    pass
                now = time.time()
                if now - t0 > timeout:
                    timed_out = True
                elif os.path.exists(hb):
                    # battito fermo: un metodo che non torna (ciclo infinito). I tratti lunghi legittimi (bot, tick, offline)
                    # hanno una soglia più larga.
                    try:
                        stale = now - os.path.getmtime(hb)
                        last_call = open(hb, errors="replace").read(60)
                    except OSError:
                        continue
                    longop = last_call.startswith(("bot_player", "ticks(", "offline(", "fork_check", "roundtrip", "section ", "base_game"))
                    if stale > (1500 if longop else 300):
                        timed_out = True
                if timed_out:
                    proc.kill()
                    proc.wait()
                    break
        code = proc.returncode if not timed_out else -9
        try:
            with open(logf, "rb") as lf:
                lf.seek(0, 2)
                lf.seek(max(0, lf.tell() - 3000))
                output = lf.read().decode("utf-8", "replace")
        except OSError:
            output = ""
        shutil.rmtree(data_home, ignore_errors=True)
        hb = out + ".hb"
        last = open(hb, errors="replace").read() if os.path.exists(hb) else ""
        log_all.append(output[-3000:])
        if os.path.exists(out) and not timed_out:
            res = json.load(open(out))
            res["hangs"] = hangs
            res["exit_code"] = code
            res["wall_s"] = round(time.time() - t0, 1)
            res["crashed"] = code not in (0,)
            json.dump(res, open(out, "w"), indent=1)
            if os.path.exists(hb):
                os.remove(hb)
            return res
        # nessun risultato: blocco o crash
        name = last.split("(")[0].strip() if last else ""
        hangs.append({"attempt": attempt, "timed_out": timed_out, "exit": code, "last_call": last[:300]})
        if timed_out and name and "." in name and name not in skip and not name.startswith(("ticks", "offline", "roundtrip", "fork")):
            skip.append(name)
        elif not timed_out:
            if name and "." in name and name not in skip:
                skip.append(name)
            else:
                break
        else:
            break
    res = {"seed": seed, "findings": [{"kind": "hang_or_crash", "sig": "hang_or_crash|seed%d" % seed, "msg": json.dumps(hangs)[:1500],
                                       "ctx": {"seed": seed}, "hostile": True, "count": 1}], "stats": {}, "hangs": hangs}
    res["log_tail"] = log_all[-1][-1500:] if log_all else ""
    json.dump(res, open(os.path.join(out_dir, "seed%d.json" % seed), "w"), indent=1)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="1-4")
    ap.add_argument("--hours", default="20")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--out", default=os.path.join(ROOT, "reports", "chaos"))
    ap.add_argument("--timeout", type=int, default=3300)
    ap.add_argument("--mode", default="")
    ap.add_argument("--bot", default="0.5")
    ap.add_argument("--ui", action="store_true", help="istanzia anche la schermata principale vera (risoluzioni, lingua, schermate)")
    ap.add_argument("--game", default=GAME, help="cartella del progetto Godot (una copia congelata per non cambiare codice a metà lotto)")
    a = ap.parse_args()
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot")
    if not godot:
        print("GODOT_BIN mancante")
        return 2
    os.makedirs(a.out, exist_ok=True)
    seeds = parse_seeds(a.seeds)
    results = []
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(run_seed, s, a.hours, a.out, a.timeout, a.mode, a.bot, godot, a.game, a.ui): s for s in seeds}
        for f, s in futs.items():
            r = f.result()
            results.append(r)
            n = len(r.get("findings", []))
            print("seme %3d: %3d findings, %.0f s reali, %.1f h simulate" % (s, n, r.get("stats", {}).get("wall_s", 0), r.get("stats", {}).get("sim_h", 0)), flush=True)
    agg = {}
    for r in results:
        for f in r.get("findings", []):
            k = f["sig"]
            e = agg.setdefault(k, {"sig": k, "kind": f["kind"], "msg": f["msg"], "seeds": [], "count": 0, "hostile_only": True, "example": f.get("ctx")})
            e["seeds"].append(r["seed"])
            e["count"] += f.get("count", 1)
            if not f.get("hostile"):
                e["hostile_only"] = False
    json.dump(sorted(agg.values(), key=lambda e: (e["kind"], e["sig"])), open(os.path.join(a.out, "riepilogo.json"), "w"), indent=1, ensure_ascii=False)
    print("findings distinti:", len(agg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
