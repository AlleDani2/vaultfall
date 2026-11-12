#!/usr/bin/env python3
"""
Genera TUTTI i dati di gioco in data/ a partire dalle formule e dal vocabolario in tools/gamedata/.
Uso:  python tools/generate_data.py
Poi:  python tools/validate_data.py  &&  python tools/balance_sim.py
Regola: non modificare a mano i JSON in data/ — modifica i moduli in tools/gamedata/ e rigenera.
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import os, sys, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from gamedata import skills, equipment, combat, crates, economy, estate, quests, meta, modifiers, export, comedy_world, comedy_chat, social, events, coop, run  # noqa: E402
from gamedata import coop_net  # noqa: E402  (COOP-2)
from gamedata.reg import R  # noqa: E402


def main():
    data_dir = os.path.join(ROOT, "data")
    if os.path.isdir(data_dir):
        for sub in ("items", "actions"):
            shutil.rmtree(os.path.join(data_dir, sub), ignore_errors=True)
        for f in os.listdir(data_dir):
            if f.endswith(".json"):
                os.remove(os.path.join(data_dir, f))
    # ordine importante: materiali -> produzione -> equipaggiamento -> combattimento -> casse -> resto
    skills.build_skills()
    skills.build_gathering()
    skills.build_farming()
    skills.build_processing()
    skills.build_thievery()
    skills.build_open_tables()
    skills.build_skill_perks()
    equipment.build_equipment()
    combat.build_world()
    combat.build_classes()
    combat.build_bounties()
    run.build_run()                   # CORSA (resoconto 91): voci e regole della Corsa a scelte
    meta.build_pets()
    meta.build_special_items()
    crates.build_crates()
    economy.build_economy()
    economy.build_currency_shops()
    estate.build_estate()
    social.build_social()
    quests.build_main_story()
    quests.build_side_quests()
    quests.build_class_quests()
    quests.build_skill_paths()
    quests.build_contracts()
    quests.build_guides()
    meta.build_prestige()
    meta.build_achievements()
    meta.build_challenges()
    meta.build_events_and_titles()
    events.build_seasonal()
    coop.build_coop()                 # COOP-1: regole della modalità Amici (dopo i titoli)
    modifiers.build_catalog()
    coop_net.build_coop_net()
    comedy_world.apply_items(R)
    comedy_chat.apply_chat(R)       # G34: battute dei PNG per il menù Città (campo "chat" in npcs.json)
    counts = export.export_all(ROOT)
    print("Dati generati in", data_dir)
    for k, v in counts.items():
        print(f"  {k}: {v}")
    if "--scope" in sys.argv:
        scope = sys.argv[sys.argv.index("--scope") + 1]
        if scope == "slice":
            import subprocess
            r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "scope_filter.py")])
            if r.returncode != 0:
                sys.exit(r.returncode)
            r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "scope_filter.py"), "--verify"])
            sys.exit(r.returncode)
        elif scope != "full":
            print(f"Perimetro sconosciuto: {scope} (valori: full, slice)")
            sys.exit(2)


if __name__ == "__main__":
    main()
