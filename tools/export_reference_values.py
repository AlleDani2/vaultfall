#!/usr/bin/env python3
"""
Esporta valori di riferimento calcolati in Python per i test GUT delle formule GDScript.
Uso: python tools/export_reference_values.py  -> game/tests/reference_values.json (o tests/reference_values.json se game/ non esiste)
Ogni voce: {"fn": nome_funzione, "args": [...], "expected": valore, "tol": tolleranza}
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from gamedata import core  # noqa: E402


def main():
    cases = []

    def add(fn, args, expected, tol=1e-6):
        cases.append({"fn": fn, "args": args, "expected": expected, "tol": tol})

    for L in (1, 2, 10, 25, 50, 75, 99):
        add("xp_to_next", [L], core.xp_to_next(L), 0)
    tbl = core.xp_table()
    for L in (2, 10, 50, 100):
        add("xp_total_for_level", [L], tbl[L], 0)
    for L in (1, 9, 10, 19, 20, 94, 95, 100):
        add("tier_of_level", [L], core.tier_of_level(L), 0)
    for t in range(1, 12):
        add("xph", [t], core.xph(t), 1e-6)
        add("gph", [t], core.gph(t), 1e-6)
        add("food_heal", [t], core.food_heal(t), 0)
        add("weapon_damage", [t, 1.0], core.weapon_damage(t, 1.0), 0)
    for m in (1, 10, 25, 49):
        add("mastery_to_next", [m], core.mastery_to_next(m), 0)
    for acc, eva in ((100, 100), (200, 100), (50, 100), (10, 1000), (1000, 10), (775, 681)):
        add("hit_chance", [acc, eva], core.hit_chance(acc, eva), 1e-9)
    for arm, lvl in ((0, 10), (40, 1), (500, 50), (1157, 100), (100000, 1)):
        add("damage_reduction", [arm, lvl], core.damage_reduction(arm, lvl), 1e-9)
    for a, d in (("melee", "ranged"), ("ranged", "melee"), ("arcane", "arcane"), ("arcane", "melee"), ("ranged", "arcane")):
        add("triangle_mult", [a, d], core.triangle_mult(a, d), 1e-9)
    for lvl in (1, 50, 100):
        for mt in ("normal", "elite", "boss", "dungeon_boss", "raid_boss"):
            add("monster_stats", [lvl, mt], core.monster_stats(lvl, mt), 0)
    for lvl, rec in ((10, 100), (49, 100), (50, 100), (89, 100), (90, 100), (99, 100), (100, 100), (5, 0)):
        add("echo_multiplier", [lvl, rec], core.echo_multiplier(lvl, rec), 1e-9)
    for s in (0, 1, 5, 10, 50):
        add("star_haste_pct", [s], core.star_haste_pct(s), 1e-9)
        add("star_xp_pct", [s], core.star_xp_pct(s), 1e-9)
        add("star_curve", [40, 0.95, s], core.star_curve(40, 0.95, s), 1e-9)
    for n in (1, 2, 10):
        add("stardust_for_star", [n], core.stardust_for_star(n), 0)
    for pp in (0, 10000, 50000, 1_000_000):
        add("soci_total", [pp], core.soci_total(pp), 0)
    for L in (0, 1, 9, 10, 25, 100):
        add("estate_units_per_hour", [L], core.estate_units_per_hour(L), 1e-9)
    for L, b in ((0, 1), (10, 2), (55, 6)):
        add("estate_cost_gold", [L, b], core.estate_cost_gold(L, b), 0)
    for d, m in ((0, 0), (10, 20), (60, 50)):
        add("quality_chances", [d, m], core.quality_chances(d, m), 1e-9)
    for k in range(1, 7):
        add("key_shop_price", [k], core.key_shop_price(k), 0)
        for r in ("rare", "epic", "legendary", "mythic", "relic"):
            add("skin_value", [k, r], core.skin_value(k, r), 0)
    for e in (1, 2, 5, 10):
        add("era_monster_mult", [e], core.era_monster_mult(e), 1e-9)
        add("era_reward_mult", [e], core.era_reward_mult(e), 1e-9)
    for r in (1, 2, 3, 8, 12, 24, 100):        # G03: costo del Rango degli oggetti
        add("rank_essence_cost", [r], core.rank_essence_cost(r), 0)
        for t in (1, 6, 11):
            add("rank_gold_cost", [t, r], core.rank_gold_cost(t, r), 0)
    for dt, pct in ((0.1, 5.0), (3600.0, 5.0), (43200.0, 0.3), (86400.0, 0.3), (0.0, 5.0), (10.0, 0.0)):   # F13: Sabbia del Custode
        add("push_regen", [dt, pct], core.push_regen(dt, pct), 1e-9)
    for r, c in ((600.0, 0.3), (0.2, 0.3), (0.0, 0.3), (0.3, 0.3), (12.5, 0.3)):
        add("push_spend", [r, c], core.push_spend(r, c), 1e-9)
    for x in (1, 99, 100, 125, 135, 1234, 1250, 56789, 123456):
        add("round_nice", [x], core.round_nice(x), 0)
    for x in (0.5, 1.5, 2.5, 3.49, 12.5):
        add("rhalf", [x], core.rhalf(x), 0)
    for fr in ((0.0, 1.0), (0.10, 0.90), (0.06, 0.80), (0.0, 0.70), (0.0, 0.08), (0.02, 1.0), (0.0, 0.5)):
        add("condition_odds", list(fr), core.condition_odds(*fr), 0.005)
    mean, eff = core.relic_pity_stats()
    add("relic_pity_mean_openings", [], mean, 1e-6)
    add("relic_pity_effective_rate", [], eff, 1e-9)
    add("effective_rarity_pct", [], core.effective_rarity_pct(), 0.0005)
    # --- T-P2: copertura oltre core.py ------------------------------------------------------------
    for t in range(1, 12):
        for sec in (1.0, 3.0, 4.5, 12.0):
            add("raw_value", [t, sec], core.raw_value(t, sec), 0)
    for b in (1.0, 12.5, 100.0, 1234.5):
        for t in (1, 5, 11):
            add("set_value", [b, t], core.set_value(b, t), 1e-6)
    for lv in (0, 1, 9, 10, 24, 25, 49, 50, 99, 100, 200):
        add("estate_milestone_mult", [lv], core.estate_milestone_mult(lv), 0)
    for ml in (1, 10, 50, 100, 150, 500):
        add("dr_k", [ml], core.dr_k(ml), 1e-6)
    for vit, lv, gh, pct in ((5, 1, 0, 0), (100, 50, 300, 10), (1000, 100, 5000, 25), (50000, 150, 1e6, 0)):
        add("hero_hp", [vit, lv, gh, pct], core.hero_hp(vit, lv, gh, pct), 1e-6)
    for pr, ga in ((5, 0), (300, 40), (4000, 900)):
        add("hero_ap", [pr, ga], core.hero_ap(pr, ga), 1e-6)
    for lv, pr, ga in ((1, 5, 0), (50, 200, 120), (100, 4000, 3000)):
        add("hero_acc", [lv, pr, ga], core.hero_acc(lv, pr, ga), 1e-6)
    for lv, de, ge in ((1, 5, 0), (50, 200, 120), (100, 4000, 3000)):
        add("hero_eva", [lv, de, ge], core.hero_eva(lv, de, ge), 1e-6)
    for wd, ap, pct in ((5, 0, 0), (40, 300, 0), (250, 4000, 35), (1e4, 1e5, 100)):
        add("max_hit", [wd, ap, pct], core.max_hit(wd, ap, pct), 1e-6)
    # bordi: livelli alti, Ere molto alte (il double basta fino a ~Era 2.000: vedi report 07)
    for lv in (100, 101, 120, 150):
        add("xp_to_next", [lv], core.xp_to_next(lv), 0)
        add("tier_of_level", [lv], core.tier_of_level(lv), 0)
    for e in (100, 500, 1000, 2000):
        add("era_monster_mult", [e], core.era_monster_mult(e), 1e-9 * 1.0)
        add("era_reward_mult", [e], core.era_reward_mult(e), 1e-9 * 1.0)
    for lv in (100, 200, 300):
        add("estate_cost_gold", [lv, 11], core.estate_cost_gold(lv, 11), 0)
    # fixture di eroe e combattimento (balance_sim.py); i valori infiniti sono scritti come stringa "inf"
    sys.path.insert(0, HERE)
    import balance_sim as bs  # noqa: E402

    def jclean(o):
        if isinstance(o, float) and (o != o or o in (float("inf"), float("-inf"))):
            return "inf" if o > 0 else "-inf"
        if isinstance(o, dict):
            return {k: jclean(v) for k, v in o.items()}
        return o

    # casi limite (FIX-COMBATTIMENTO, QA4 #12): saturazione a +-2^62, potenze che traboccano (inf), guardie su stile vuoto
    # e precisione <= 0. Valori calcolati da core.py come tutti gli altri (NaN resta nei test GUT: il JSON non lo porta).
    for lv in (1000, 9000):
        add("xp_to_next", [lv], core.xp_to_next(lv), 0)
    add("mastery_to_next", [500], core.mastery_to_next(500), 0)
    for lv, mt in ((680, "normal"), (5000, "normal"), (1500, "world_boss"), (100000, "normal")):
        add("monster_stats", [lv, mt], core.monster_stats(lv, mt), 0)
    add("food_heal", [1000], core.food_heal(1000), 0)
    add("raw_value", [200, 3600.0], core.raw_value(200, 3600.0), 0)
    add("soci_total", [1e300], core.soci_total(1e300), 0)
    add("estate_cost_gold", [2000, 1], core.estate_cost_gold(2000, 1), 0)
    for x in (9.3e18, 1e19, 1e30, -1e30, 9007199254740993.0):
        add("rhalf", [x], core.rhalf(x), 0)
    for x in (1e17, 1e19, 1e25, -5.0):
        add("round_nice", [x], core.round_nice(x), 0)
    add("triangle_mult", ["", ""], core.triangle_mult("", ""), 1e-9)
    add("triangle_mult", ["melee", ""], core.triangle_mult("melee", ""), 1e-9)
    for acc, eva in ((0, 10), (-10, 10), (100, 0), (1e300, 1e-300)):
        add("hit_chance", [acc, eva], core.hit_chance(acc, eva), 1e-9)
    for arm, lvl in ((100, 1e6), (-5, 50), (1e9, 100)):
        add("damage_reduction", [arm, lvl], core.damage_reduction(arm, lvl), 1e-9)
    add("dr_k", [1e6], jclean(core.dr_k(1e6)), 0)
    for hl, ml in ((10, 10), (13, 10), (14, 10), (20, 10), (40, 25), (99, 5), (100, 91), (100, 95), (1, 50)):
        add("overlevel_xp_mult", [hl, ml], core.overlevel_xp_mult(hl, ml), 1e-12)
    add("era_monster_mult", [2400], jclean(core.era_monster_mult(2400)), 0)
    for hp_ in (-20.0, 0.0, 35.0, 60.0, 61.0, 100.0, 140.0, 500.0):
        add("effective_haste_pct", [hp_], core.effective_haste_pct(hp_), 1e-12)

    for cls in ("warrior", "warrior2h", "ranger", "arcanist"):
        for lv, t in ((1, 1), (30, 4), (60, 7), (100, 11)):
            h = bs.hero_stats(cls, lv, t)
            add("hero_stats", [cls, lv, t], jclean(h), 1e-6)
    for cls, lv, t, zone_i in (("warrior", 10, 2, 0), ("ranger", 40, 5, 2), ("arcanist", 80, 9, 4), ("warrior2h", 100, 11, -1)):
        z = bs.ZONES[zone_i]
        mon = [bs.MON[mid] for mid in z["monsters"]][0]
        for era in (1.0, 5.0):
            add("fight", [cls, lv, t, mon["id"], era], jclean(bs.fight(bs.hero_stats(cls, lv, t), mon, era)), 1e-6)
    # valori enormi: il JSON li legge come float in Godot (perdita sopra 2^53), quindi si confronta in modo relativo
    for cs in cases:
        e = cs["expected"]
        if isinstance(e, (int, float)) and abs(e) > 1e6:
            cs["tol_rel"] = 1e-9
            if abs(e) > 2 ** 53:
                cs["oltre_2_alla_53"] = True
    # sempre in tests/ (pacchetto) e, se il progetto Godot esiste, anche in game/tests/ (letto dai test GUT)
    dirs = [os.path.join(ROOT, "tests")] + ([os.path.join(ROOT, "game", "tests")] if os.path.isdir(os.path.join(ROOT, "game")) else [])
    for out_dir in dirs:
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "reference_values.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"generated_from": "tools/gamedata/core.py", "cases": cases}, f, indent=1)
        print(f"{len(cases)} casi scritti in {path}")


if __name__ == "__main__":
    main()
