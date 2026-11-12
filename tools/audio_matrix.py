#!/usr/bin/env python3
"""Matrice evento di gioco -> suono (docs/21, AUDIO-3). Legge AudioManager.gd, controlla che ogni evento importante abbia
un suono agganciato e che il file esista, e stampa (Markdown) volume, moderazione e loudness effettiva stimata.

Uso: python tools/audio_matrix.py [--misura]    (--misura decodifica gli OGG per la loudness: ~1,5 min)
Esce con 1 se un evento della lista EXPECTED non ha suono o il file manca.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_audio as ma  # noqa: E402

GD = open(os.path.join(ROOT, "game", "src", "autoload", "AudioManager.gd"), encoding="utf-8").read()

# (descrizione, segnale, argomento) -> il suono si ricava da EVENT_MAP / COMBAT_HIT_MAP / IMPORTANT_MAP / NOTICE_MAP
EXPECTED = [
    ("Colpo dell'eroe", "combat_hit", "hit"), ("Colpo critico", "combat_hit", "crit"),
    ("Schivata", "combat_hit", "dodge"), ("Colpo subito", "combat_hit", "hurt"),
    ("Mostro sconfitto", "monster_killed", ""), ("Oggetto raro caduto", "rare_drop", ""),
    ("Morte dell'eroe", "player_died", ""), ("Cassa trovata", "crate_found", ""),
    ("Apertura Cassa (scatto)", "crate_opened", ""), ("Tick del rullo", "reel", "reel_tick"),
    ("Rivelazione Rara", "reel", "reveal_rare"), ("Rivelazione Epica", "reel", "reveal_epic"),
    ("Rivelazione Leggendaria", "reel", "reveal_legendary"), ("Rivelazione Mitica", "reel", "reveal_mythic"),
    ("Rivelazione Reliquia", "reel", "reveal_relic"),
    ("Level up", "level_up", ""), ("Missione completata", "quest_completed", ""),
    ("Impresa sbloccata", "achievement_unlocked", ""), ("Stella", "star_gained", ""), ("Famiglio", "pet_found", ""),
    ("Funzione sbloccata", "unlocked", ""), ("Bentornato (offline)", "offline_progress", ""),
    ("Vendita", "item_sold", ""), ("Acquisto", "item_bought", ""), ("Commessa", "order_completed", ""),
    ("Spedizione finita", "expedition_finished", ""), ("Grado di fazione", "faction_rank_up", ""),
    ("Rito di prestigio", "important_event", "rite"), ("Rifondazione", "important_event", "refounding"),
    ("Nuova Era", "important_event", "era"), ("Custode", "important_event", "warden"),
    ("Incursione vinta", "important_event", "raid"), ("Boss mondiale", "important_event", "world_boss"),
    ("Prova superata", "important_event", "trial"), ("Prova fallita", "important_event", "trial_fail"),
    ("Co-op: amico collegato", "important_event", "coop"),
    ("Clic UI", "ui", "ui_click"), ("Errore (notifica)", "notice", "error"), ("Successo (notifica)", "notice", "success"),
    ("Avviso (notifica)", "notice", "warning"),
]
SKILLS = re.findall(r'"(\w+)"', re.search(r"const SKILL_IDS[^=]*=\s*\[(.*?)\]", GD, re.S).group(1))


def const_dict(name):
    m = re.search(r"const %s\s*(?::[^=]*)?:?=\s*\{(.*?)\n\}" % name, GD, re.S)
    one = re.search(r"const %s\s*(?::[^=]*)?:?=\s*\{([^\n]*)\}" % name, GD)
    if one and (not m or len(one.group(1)) < len(m.group(1))):
        return one.group(1)
    return m.group(1) if m else ""


def event_map():
    out = {}
    for m in re.finditer(r'"(\w+)": \{"sfx": "(\w+)", "bus": "(\w+)", "db": (-?[\d.]+), "gap_ms": (\d+)(, "calm": true)?', const_dict("EVENT_MAP")):
        out[m.group(1)] = dict(sfx=m.group(2), bus=m.group(3), db=float(m.group(4)), gap=int(m.group(5)), calm=bool(m.group(6)))
    return out


def simple_map(name):
    return dict(re.findall(r'"(\w+)": "(\w*)"', const_dict(name)))


def combat_map():
    m = re.search(r"const COMBAT_HIT_MAP[^=]*=\s*\{(.*?)\}\n", GD, re.S)
    return {k: (s, float(d)) for k, s, d in re.findall(r'"(\w+)": \["(\w+)", (-?[\d.]+)\]', m.group(1))}


def sfx_exists(i):
    return any(os.path.exists(os.path.join(ROOT, "game", "assets", "audio", "sfx", i + e)) for e in (".ogg", ".wav"))


def main():
    measure = "--misura" in sys.argv
    lufs = {}
    if measure:
        for a in ma.measure_all(os.path.join(ROOT, "game", "assets", "audio")):
            if a["kind"] == "sfx":
                lufs[a["file"].rsplit(".", 1)[0]] = a["lufs"]
    ev, imp, notice, comb = event_map(), simple_map("IMPORTANT_MAP"), simple_map("NOTICE_MAP"), combat_map()
    bad = 0
    print("| Evento | Segnale | Suono | Bus | dB | Intervallo min. | LUFS~ file | LUFS~ effettiva |")
    print("|---|---|---|---|---|---|---|---|")
    for desc, sig, arg in EXPECTED:
        bus, db, gap, snd = "SFX", 0.0, 0, ""
        if sig == "combat_hit" and sig in ev and arg in comb:
            snd, db = comb[arg][0], ev[sig]["db"] + comb[arg][1]
            bus, gap = ev[sig]["bus"], ev[sig]["gap"]
        elif sig == "important_event":
            snd = imp.get(arg, ev[sig]["sfx"])
            db = 0.0 if snd in ("prestige", "era", "victory", "defeat") else -3.0
            bus, gap = ev[sig]["bus"], ev[sig]["gap"]
        elif sig == "notice":
            snd, bus, gap = notice.get(arg, ""), "UI", 300
        elif sig == "reel":
            snd, bus = arg, "Reel"
            db = -6.0 if arg == "reel_tick" else 0.0
        elif sig == "ui":
            snd, bus, db = arg, "UI", -6.0
        elif sig in ev:
            snd, bus, db, gap = ev[sig]["sfx"], ev[sig]["bus"], ev[sig]["db"], ev[sig]["gap"]
        ok = bool(snd) and sfx_exists(snd)
        bad += 0 if ok else 1
        base = lufs.get(snd)
        print("| %s | `%s%s` | %s | %s | %+.0f | %s | %s | %s |" % (
            desc, sig, (":" + arg) if arg and sig not in ("reel", "ui") else "", ("`%s`" % snd) if ok else "**MANCA**", bus, db,
            ("%d ms" % gap) if gap else "-", ("%.1f" % base) if base is not None else "-",
            ("%.1f" % (base + db)) if base is not None else "-"))
    for sk in SKILLS:
        ok = all(sfx_exists("sk_%s_%d" % (sk, v)) for v in (1, 2, 3))
        bad += 0 if ok else 1
        if not ok:
            print("| Mansione %s | action_completed | **MANCA** | | | | | |" % sk)
    print("\nMansioni coperte: %d/%d (3 varianti ciascuna)" % (len(SKILLS) - sum(
        0 if all(sfx_exists("sk_%s_%d" % (s, v)) for v in (1, 2, 3)) else 1 for s in SKILLS), len(SKILLS)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
