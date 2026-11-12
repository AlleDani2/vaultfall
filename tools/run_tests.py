#!/usr/bin/env python3
"""
Esegue i test GUT del progetto Godot (cartella game/) in modalità headless, IN PARALLELO. Funziona su Windows, Linux e
macOS e da Claude Code (Git Bash o PowerShell) senza problemi di ExecutionPolicy.

Eseguibile di Godot: variabile d'ambiente GODOT_BIN. Su Windows usare la versione *console*, per esempio:
    setx GODOT_BIN "C:\\Godot\\Godot_v4.7.2-stable_win64_console.exe"      (poi riaprire il terminale)
In mancanza di GODOT_BIN si cerca "godot" (o "godot4") nel PATH.

Passi: 1) importazione delle risorse (--import, una sola volta, condivisa da tutti i processi);
       2) GUT sui file di test (game/tests, sottocartelle incluse), divisi in N processi Godot (N = min(4, CPU),
          ripartizione per pesi in tools/test_weights.json), ognuno con la PROPRIA cartella dati utente (user://) in una
          directory temporanea, quindi nessuna collisione sui salvataggi (SaveService.save_dir) né sulle impostazioni;
       3) gruppo "perf": le funzioni `test_perf_*` (solo misure di tempo) non girano nei processi paralleli
          (VAULTFALL_PERF=off) ma in un ultimo processo SOLO, a macchina meno carica (vedi game/tests/helpers/perf_gate.gd).
Gruppi: "lento" = playthrough lunghi del bot (SLOW_FILES), "veloce" = tutto il resto.
Uso:
    python tools/run_tests.py                       # tutti i test, in parallelo
    python tools/run_tests.py --fast                # senza il gruppo lento (playthrough lunghi): per il lavoro quotidiano
    python tools/run_tests.py --slow-only           # solo i playthrough lunghi
    python tools/run_tests.py --perf-only           # solo i test_perf_* (in serie)
    python tools/run_tests.py --jobs 2              # numero di processi (default min(4, CPU); 1 = seriale)
    python tools/run_tests.py --select test_formulas.gd   # solo i file il cui nome contiene la stringa
    python tools/run_tests.py --no-import           # salta l'importazione (più veloce se già fatta)
    python tools/run_tests.py --no-perf             # salta la fase seriale dei test_perf_*
    python tools/run_tests.py --verbose             # stampa l'output completo anche dei processi verdi
    python tools/run_tests.py --update-weights      # riscrive tools/test_weights.json con i tempi misurati
Codice di uscita: 0 = tutti verdi · 1 = test falliti · 2 = Godot, progetto o GUT non trovati.
Verde SOLO se OGNI processo: codice di uscita di Godot 0, nell'output c'è "All tests passed", il riepilogo riporta
almeno un test eseguito, nessun test non passato e nessun "SCRIPT ERROR" / "Parse Error" (protezione dal falso verde con
interruzione del debugger, docs/audit_2026-10-22/14_RESOCONTO_SPIKE_S2.md); e in totale almeno un test.
Report JUnit unito in game/test_results.xml (un <testsuite> per file, con il tempo).
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, time
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
TESTS = os.path.join(GAME, "tests")
WEIGHTS_FILE = os.path.join(ROOT, "tools", "test_weights.json")

# Gruppo LENTO: partite intere del bot (BotPlayer) che durano minuti. Restano nella suite completa, ma --fast le salta.
SLOW_FILES = {
    "test_playthrough_long.gd",
    "test_playthrough.gd",
}
DEFAULT_WEIGHT = 5.0      # secondi stimati per un file senza peso noto


def godot_bin():
    b = os.environ.get("GODOT_BIN", "").strip().strip('"')
    if b and os.path.exists(b):
        return b
    for name in ("godot", "godot4", "Godot"):
        p = shutil.which(name)
        if p:
            return p
    # ripiego: Godot installato nel progetto (cartella _strumenti/, fuori da git) - spike S1
    local = os.path.join(ROOT, "_strumenti", "godot-4.7.2", "Godot_v4.7.2-stable_win64_console.exe")
    return local if os.path.exists(local) else None


def discover():
    """Tutti i file test_*.gd sotto game/tests, come percorsi relativi a game/tests con '/' (es. 'test_ui.gd')."""
    out = []
    for p in glob.glob(os.path.join(TESTS, "**", "test_*.gd"), recursive=True):
        out.append(os.path.relpath(p, TESTS).replace(os.sep, "/"))
    return sorted(out)


def load_weights():
    try:
        with open(WEIGHTS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def partition(files, n, weights):
    """Ripartizione LPT (il più pesante nel contenitore meno carico). Restituisce lista di liste non vuote."""
    bins = [[0.0, []] for _ in range(n)]
    for f in sorted(files, key=lambda x: -float(weights.get(x, DEFAULT_WEIGHT))):
        b = min(bins, key=lambda x: x[0])
        b[0] += float(weights.get(f, DEFAULT_WEIGHT))
        b[1].append(f)
    return [b[1] for b in bins if b[1]]


def has_perf(rel):
    try:
        with open(os.path.join(TESTS, rel), encoding="utf-8") as f:
            return "func test_perf_" in f.read()
    except OSError:
        return False


def worker_env(tag):
    """Ambiente con cartella dati utente propria (user://), così i processi paralleli non si pestano i piedi."""
    base = tempfile.mkdtemp(prefix="vaultfall_test_%s_" % tag)
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = os.path.join(base, "data")
    env["XDG_CONFIG_HOME"] = os.path.join(base, "config")
    env["XDG_CACHE_HOME"] = os.path.join(base, "cache")
    env["APPDATA"] = os.path.join(base, "appdata")            # Windows: %APPDATA%\VAULTFALL
    env["LOCALAPPDATA"] = os.path.join(base, "localappdata")
    env["VAULTFALL_NO_PLATFORM"] = "1"                        # i test non devono mai parlare con un Steam vero (imprese, Cloud)
    if sys.platform == "darwin":
        env["HOME"] = base                                    # macOS: ~/Library/Application Support/VAULTFALL
    for k in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        os.makedirs(env[k], exist_ok=True)
    return base, env


def plain_text(out):
    return re.sub(r"\x1b\[[0-9;]*m", "", out)


def judge(plain, code):
    """Applica i criteri di 'verde' a UN processo. Restituisce (n_test, n_pass, n_asserts, problemi)."""
    m_tests = re.search(r"^Tests\s+(\d+)", plain, re.M)
    m_pass = re.search(r"^Passing Tests\s+(\d+)", plain, re.M)
    m_asserts = re.search(r"^Asserts\s+(\d+)", plain, re.M)
    n_tests = int(m_tests.group(1)) if m_tests else 0
    n_pass = int(m_pass.group(1)) if m_pass else 0
    problems = []
    if code != 0:
        problems.append(f"codice di uscita di Godot {code}")
    if "All tests passed" not in plain:
        problems.append('manca "All tests passed" nell\'output')
    if n_tests == 0:
        problems.append("0 test eseguiti")
    elif n_pass != n_tests:
        problems.append(f"{n_tests - n_pass} test non passati")
    for marker in ("SCRIPT ERROR", "Parse Error", "Debugger Break"):
        if marker in plain:
            problems.append(f'trovato "{marker}" nell\'output')
    return n_tests, n_pass, int(m_asserts.group(1)) if m_asserts else 0, problems


class Job:
    def __init__(self, name, files, extra_args=None, env_extra=None):
        self.name = name
        self.files = files
        self.extra = extra_args or []
        self.env_extra = env_extra or {}
        self.xml = "test_results_%s.xml" % name
        self.t0 = 0.0
        self.t1 = 0.0
        self.code = None
        self.out = ""
        self.proc = None
        self.log = None
        self.base = None


def start(exe, job):
    job.base, env = worker_env(job.name)
    env.update(job.env_extra)
    cmd = [exe, "--headless", "-d", "-s", "--path", GAME, "addons/gut/gut_cmdln.gd",
           "-gtest=" + ",".join("res://tests/" + f for f in job.files),
           "-gexit", "-gjunit_xml_file=res://" + job.xml] + job.extra
    job.log = tempfile.TemporaryFile()
    job.t0 = time.time()
    # stdin chiuso: un'eventuale interruzione del debugger (-d) non resta in attesa di comandi
    job.proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=job.log, stderr=subprocess.STDOUT, env=env)


def finish(job, timed_out=False):
    job.t1 = time.time()
    if timed_out:
        job.proc.kill()
        job.proc.wait()
        job.code = 124
    else:
        job.code = job.proc.returncode
    job.log.seek(0)
    job.out = job.log.read().decode("utf-8", errors="replace")
    job.log.close()
    if timed_out:
        job.out += "\n[run_tests] TIMEOUT"
    shutil.rmtree(job.base, ignore_errors=True)


def run_jobs(exe, jobs, timeout):
    """Lancia tutti i job insieme e li aspetta (ognuno con il proprio timeout)."""
    for j in jobs:
        start(exe, j)
    pending = list(jobs)
    while pending:
        for j in list(pending):
            if j.proc.poll() is not None:
                if j.proc.returncode is not None and j.proc.returncode < 0 and not getattr(j, "retried", False):
                    # Processo ucciso da un segnale esterno (es. `pkill godot` di un altro agente/utente sulla stessa
                    # macchina): non è un esito del test. Si riparte UNA volta da capo.
                    print(f"[run_tests] {j.name}: ucciso dal segnale {-j.proc.returncode} dall'esterno, rilancio una volta", flush=True)
                    j.log.close()
                    shutil.rmtree(j.base, ignore_errors=True)
                    j.retried = True
                    start(exe, j)
                    continue
                finish(j)
                pending.remove(j)
            elif time.time() - j.t0 > timeout:
                finish(j, timed_out=True)
                pending.remove(j)
        if pending:
            time.sleep(0.5)


def collect_xml(jobs):
    """Unisce i report JUnit dei job in game/test_results.xml; restituisce {file: secondi} e cancella i parziali."""
    root = ET.Element("testsuites")
    times = {}
    for j in jobs:
        p = os.path.join(GAME, j.xml)
        if not os.path.exists(p):
            continue
        try:
            tree = ET.parse(p)
        except ET.ParseError:
            continue
        for ts in tree.getroot().iter("testsuite"):
            root.append(ts)
            name = ts.get("name", "")
            m = re.search(r"([^/\\]+\.gd)$", name)
            key = m.group(1) if m else name
            try:
                times[key] = times.get(key, 0.0) + float(ts.get("time", "0"))
            except ValueError:
                pass
        os.remove(p)
    try:
        ET.ElementTree(root).write(os.path.join(GAME, "test_results.xml"), encoding="utf-8", xml_declaration=True)
    except OSError:
        pass
    return times


def cpu_info():
    """Tempo CPU dei processi figli (Unix): indica il costo reale anche quando la macchina è occupata da altri."""
    try:
        import resource
        r = resource.getrusage(resource.RUSAGE_CHILDREN)
        return f", CPU {r.ru_utime + r.ru_stime:.0f} s"
    except Exception:
        return ""


def main():
    ap = argparse.ArgumentParser(description="Test GUT headless del progetto Godot (in parallelo)")
    ap.add_argument("--select", help="solo i file di test il cui nome contiene questa stringa")
    ap.add_argument("--no-import", action="store_true", help="salta il passo di importazione")
    ap.add_argument("--timeout", type=int, default=1200, help="secondi massimi per ogni processo di test (default 1200)")
    ap.add_argument("--fast", action="store_true", help="esclude il gruppo lento (playthrough lunghi del bot)")
    ap.add_argument("--slow-only", action="store_true", help="solo il gruppo lento")
    ap.add_argument("--perf-only", action="store_true", help="solo i test_perf_*, in serie")
    ap.add_argument("--no-perf", action="store_true", help="salta la fase seriale dei test_perf_*")
    ap.add_argument("--jobs", type=int, default=0, help="processi Godot in parallelo (default min(4, CPU))")
    ap.add_argument("--verbose", action="store_true", help="output completo anche dei processi verdi")
    ap.add_argument("--update-weights", action="store_true", help="riscrive tools/test_weights.json con i tempi misurati")
    a = ap.parse_args()
    exe = godot_bin()
    if not exe:
        print("Godot non trovato: imposta GODOT_BIN (vedi l'intestazione di questo file).")
        return 2
    if not os.path.exists(os.path.join(GAME, "project.godot")):
        print("Progetto Godot non trovato in game/ (si crea nel compito T-0.1).")
        return 2
    if not os.path.exists(os.path.join(GAME, "addons", "gut", "gut_cmdln.gd")):
        print("GUT non trovato in game/addons/gut/ (si installa nel compito T-0.2: GUT 9.7.0, o 9.7.1 se confermata).")
        return 2
    if a.fast and a.slow_only:
        print("--fast e --slow-only si escludono a vicenda.")
        return 2
    # game/data è generata (ignorata da git): in un clone o worktree pulito manca e i test mostrerebbero decine di falsi
    # "SCRIPT ERROR" (cartella dati mancante). Revisione 1.0, docs/review_1_0/02 punto 20: la si copia da soli.
    if not os.path.exists(os.path.join(GAME, "data", "constants.json")):
        print("0/3 game/data mancante: eseguo tools/sync_data.py...", flush=True)
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sync_data.py")], check=False)
    if not a.no_import:
        print("1/3 Importazione delle risorse...", flush=True)
        # due giri: il primo su una cartella senza .godot stampa errori innocui (font, tema, ctex mancanti); il secondo è pulito
        for _giro in range(2):
            subprocess.run([exe, "--headless", "--path", GAME, "--import"], check=False, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    files = discover()
    if a.select:
        files = [f for f in files if a.select in f]
    if a.fast:
        files = [f for f in files if os.path.basename(f) not in SLOW_FILES]
    if a.slow_only:
        files = [f for f in files if os.path.basename(f) in SLOW_FILES]
    if not files:
        print("Nessun file di test selezionato.")
        return 1
    n_jobs = a.jobs if a.jobs > 0 else min(4, os.cpu_count() or 1)
    t_start = time.time()
    all_jobs = []
    results = []          # (job, n_tests, n_pass, n_asserts, problems)

    def report(job):
        n, p, asr, problems = judge(plain_text(job.out), job.code)
        results.append((job, n, p, asr, problems))
        if problems or a.verbose:
            print(job.out)
        else:
            tail = [l for l in plain_text(job.out).splitlines() if l.strip()][-14:]
            print("\n".join(tail))
        print(f"[{job.name}] {len(job.files)} file, {n} test, {job.t1 - job.t0:.0f} s -> "
              + ("ERRORE: " + "; ".join(problems) if problems else "verde"), flush=True)

    if not a.perf_only:
        groups = partition(files, min(n_jobs, len(files)), load_weights())
        jobs = [Job("w%d" % i, g, env_extra={"VAULTFALL_PERF": "off"}) for i, g in enumerate(groups)]
        print("2/3 Test GUT: %d file in %d processi paralleli%s..." % (len(files), len(jobs),
              " (gruppo veloce)" if a.fast else " (solo gruppo lento)" if a.slow_only else ""), flush=True)
        run_jobs(exe, jobs, a.timeout)
        for j in jobs:
            report(j)
        all_jobs += jobs
    if not a.no_perf:
        pf = [f for f in files if has_perf(f)]
        if pf:
            print("3/3 Test di prestazione (test_perf_*) in serie, da soli...", flush=True)
            pj = Job("perf", pf, extra_args=["-gunit_test_name=test_perf_"])
            run_jobs(exe, [pj], a.timeout)
            report(pj)
            all_jobs.append(pj)
    times = collect_xml(all_jobs)
    if times:
        top = sorted(times.items(), key=lambda kv: -kv[1])[:10]
        print("\nFile più lenti: " + ", ".join("%s %.0f s" % kv for kv in top))
        if a.update_weights and not a.select and not a.fast and not a.slow_only and not a.perf_only:
            merged = {k: round(v, 1) for k, v in sorted(times.items())}
            with open(WEIGHTS_FILE, "w", encoding="utf-8") as f:
                json.dump(merged, f, indent=1, sort_keys=True)
                f.write("\n")
            print("Pesi riscritti in tools/test_weights.json")
    total = sum(r[1] for r in results)
    asserts = sum(r[3] for r in results)
    bad = [r for r in results if r[4]]
    wall = time.time() - t_start
    if total == 0:
        bad = bad or [(None, 0, 0, 0, ["0 test eseguiti in totale"])]
    if bad:
        names = ", ".join("%s (%s)" % (r[0].name if r[0] else "-", "; ".join(r[4])) for r in bad)
        print(f"RISULTATO: test FALLITI in {len(bad)} processo/i: {names}; dettagli in game/test_results.xml ({wall:.0f} s{cpu_info()})")
        return 1
    print(f"RISULTATO: tutti i test verdi ({total} test, {asserts} verifiche, {wall:.0f} s{cpu_info()}, {len(all_jobs)} processi)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
