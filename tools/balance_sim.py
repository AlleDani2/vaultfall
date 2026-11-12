#!/usr/bin/env python3
"""
Simulatore di bilanciamento (legge data/). Produce reports/balance_report.md.
Uso: python tools/balance_sim.py [--quick]
Sezioni: ritmo delle mansioni, artigianato vs raccolta, combattimento per zona/classe/tier, boss, oro/ora,
casse (valore atteso, pity), tenuta (tempo alla prima Rifondazione), ritmo delle Stelle, ritmo delle Ere.
Le formule DEVONO coincidere con docs/19_bilanciamento.md e con il codice GDScript (Formulas.gd).
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os, sys, math, random, statistics
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, os.environ.get("VAULTFALL_DATA", "data"))   # VAULTFALL_DATA=data_slice per la slice (T-P6)
OUT = os.path.join(ROOT, "reports", "balance_report.md" if DATA.endswith("data") else "balance_report_slice.md")
QUICK = "--quick" in sys.argv
SOMMA_MAX = 3.6             # obiettivo docs/19: attivo (<= 1,5) + passivo (Apprendisti + Bottega + Spedizioni) in x gph(tier), senza bonus
THIEVERY_P_REAL = 0.95       # probabilita' di successo del Borseggio a regime (QA3 E5; success.max)


def load(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        return json.load(f)


def load_dir(sub):
    out = {}
    d = os.path.join(DATA, sub)
    for f in os.listdir(d):
        for o in load(f"{sub}/{f}"):
            out[o["id"]] = o
    return out


K = load("constants.json")
ITEMS = load_dir("items")
ACTIONS = load_dir("actions")
MON = {m["id"]: m for m in load("monsters.json")}
ZONES = load("zones.json")
XP_TOT = load("xp_table.json")["total_xp_for_level"]
TL = K["tier_levels"]
lines = []
CHECKS = []      # (sezione, esito, dettaglio) -> riepilogo finale e codice di uscita


def P(s=""):
    lines.append(s)


def check(section, ok, detail):
    CHECKS.append((section, bool(ok), detail))
    P(f"**Controllo automatico ({section}):** {detail} → **{'OK' if ok else 'FUORI LIMITE'}**.")
    P("")


WARNINGS = []    # (sezione, dettaglio): obiettivi di design violati con i profili di bonus (T-P4/D-8). Non fanno fallire il codice di uscita.


def goal(section, ok, detail):
    """Obiettivo di design verificato con i profili di bonus: elencato nel report, ma non blocca (è la lista di cose da ritarare)."""
    if not ok:
        WARNINGS.append((section, detail))
    P(f"**Obiettivo ({section}):** {detail} → **{'OK' if ok else 'VIOLATO'}**.")
    P("")


def xp_to_next(L):
    return math.floor(K["xp"]["base"] * K["xp"]["growth"] ** L)


def tier_of(L):
    t = 1
    for i, l in enumerate(TL):
        if L >= l:
            t = i + 1
    return t


def fmt_h(h):
    if h < 1:
        return f"{h * 60:.0f} min"
    return f"{h:.1f} h"


# --------------------------------------------------------------------------- MANSIONI
def skill_pacing():
    P("## 1. Ritmo delle mansioni di raccolta (azione migliore disponibile)")
    P("")
    P("Profilo **base**: nessun bonus. Profilo **tipico**: attrezzo del tier, maestria media 20 (+10% doppio, -5% tempo), "
      "nessuna stella. Il doppio aumenta la resa, non l'XP.")
    P("")
    P("| Mansione | Lv 10 | Lv 25 | Lv 50 | Lv 75 | Lv 90 | Lv 100 | (tipico) Lv 100 |")
    P("|---|---|---|---|---|---|---|---|")
    for sk in ("woodcutting", "mining", "fishing", "foraging", "trapping", "thievery"):
        acts = [a for a in ACTIONS.values() if a["skill"] == sk]
        res = {}
        for profile in ("base", "typical"):
            t_h = 0.0
            marks = {}
            for L in range(1, 100):
                cands = [a for a in acts if a["level_req"] <= L]
                best = 0
                for a in cands:
                    tm = a["time_s"]
                    if profile == "typical":
                        haste = [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40][a["tier"] - 1] + 5
                        tm = tm / (1 + haste / 100)
                    if sk == "thievery":
                        p = 0.8
                        cyc = tm + (1 - p) * a["stun_s"]
                        rate = a["xp"] * p / cyc * 3600
                    else:
                        rate = a["xp"] / tm * 3600
                    best = max(best, rate)
                t_h += xp_to_next(L) / best
                if L + 1 in (10, 25, 50, 75, 90, 100):
                    marks[L + 1] = t_h
            res[profile] = marks
        b = res["base"]
        P(f"| {sk} | {fmt_h(b[10])} | {fmt_h(b[25])} | {fmt_h(b[50])} | {fmt_h(b[75])} | {fmt_h(b[90])} | {fmt_h(b[100])} | {fmt_h(res['typical'][100])} |")
    P("")
    P("Obiettivo di design: Lv 50 in ~3 h, Lv 100 in ~40-50 h senza bonus (25-35 h con bonus tipici, 18-25 h con il budget completo di docs/14). La seconda metà (50→100) "
      "richiede ~90% del tempo: curva esponenziale come i giochi di riferimento.")
    P("")


def single_craft_check():
    """«Una costruzione per volta» (docs/04 §8.2): le azioni che producono equipaggiamento/attrezzi (uscita non impilabile)
    portano `single_craft` e il gioco le ferma dopo UNA costruzione (online, offline, coda). Qui si controlla la copertura
    e si dichiara come le medie le trattano: l'XP/ora di queste azioni NON entra nei ritmi sostenuti (non si ripetono da sole),
    contano come costruzione singola; i flussi di Mercato (volume elastico) restano quelli del modello, perché dipendono dal
    tempo di costruzione e non dalla ripetizione automatica."""
    P("## 2b. Costruzioni «una per volta» (single_craft)")
    P("")
    single = [a for a in ACTIONS.values() if a.get("single_craft")]
    by = defaultdict(int)
    for a in single:
        by[(a["skill"], a.get("category", ""))] += 1
    P("| Mansione | Categoria | Azioni |")
    P("|---|---|---|")
    for (sk, cat), n in sorted(by.items()):
        P(f"| {sk} | {cat} | {n} |")
    P("")
    miss = [a["id"] for a in ACTIONS.values()
            if any(not ITEMS.get(o["item"], {}).get("stackable", True) for o in a.get("outputs", [])) and not a.get("single_craft")]
    wrong = [a["id"] for a in single
             if not any(not ITEMS.get(o["item"], {}).get("stackable", True) for o in a.get("outputs", []))]
    check("single_craft: copertura", not miss and not wrong,
          f"{len(single)} azioni con uscita non impilabile, tutte marcate; senza flag: {len(miss)}, flag su impilabili: {len(wrong)}")


def artisan_balance():
    P("## 2. Artigianato: consumo di materiali per ora vs produzione della raccolta")
    P("")
    P("Per ogni ricetta 'tipica' del tier: quanti materiali primari consuma in 1 ora di produzione e quante ore di raccolta servono per procurarli.")
    P("")
    P("| Ricetta | Lv | XP/h prod. | Input primario/h | Ore di raccolta per 1 h di produzione |")
    P("|---|---|---|---|---|")
    gather_rate = {}
    for a in ACTIONS.values():
        if a["skill"] in ("woodcutting", "mining", "fishing", "foraging", "trapping"):
            for o in a["outputs"]:
                gather_rate[o["item"]] = 3600 / a["time_s"] * o["qty"]
    picks = ["smelt_iron", "smith_plate_body_iron", "ww_plank_cedar", "ww_shortbow_cedar", "tail_tan_lynx", "cook_lanternfish",
             "alch_fury_2", "rc_rune_t5", "jc_cut_ruby", "key_key_t3", "smith_plate_body_starsteel", "cook_astralpike"]
    for pid in picks:
        a = ACTIONS.get(pid)
        if not a:
            continue
        xph = a["xp"] / a["time_s"] * 3600
        i0 = a["inputs"][0]
        per_h = 3600 / a["time_s"] * i0["qty"]
        # risale alla materia prima di raccolta
        it = i0["item"]
        hrs = None
        if it in gather_rate:
            hrs = per_h / gather_rate[it]
        else:
            prod = [x for x in ACTIONS.values() if any(o["item"] == it for o in x.get("outputs", []))]
            if prod:
                p0 = prod[0]
                raw = p0["inputs"][0]["item"] if p0.get("inputs") else None
                if raw in gather_rate:
                    hrs = per_h * p0["inputs"][0]["qty"] / gather_rate[raw]
        P(f"| {a['name']['it']} | {a['level_req']} | {xph:,.0f} | {per_h:,.0f} × {ITEMS[it]['name']['it']} | {('%.1f' % hrs) if hrs else 'n/d'} |")
    P("")
    P("Lettura: l'artigianato dà XP/ora pari o superiore alla raccolta ma consuma materiali più in fretta di quanto una sola mansione "
      "li produca. È voluto (come nei riferimenti): si alterna raccolta e produzione, oppure si comprano materiali, oppure si usa la Tenuta/gli Apprendisti.")
    P("")


# --------------------------------------------------------------------------- COMBATTIMENTO
CLASS_GEAR = {
    "warrior": {"armor": "plate", "weapon": "sword", "offhand": "shield", "ring": "might", "primary": "str", "style": "melee", "ammo": None},
    "warrior2h": {"armor": "plate", "weapon": "greatsword", "offhand": None, "ring": "might", "primary": "str", "style": "melee", "ammo": None},
    "ranger": {"armor": "leather", "weapon": "shortbow", "offhand": None, "ring": "aim", "primary": "dex", "style": "ranged", "ammo": "arrow"},
    "arcanist": {"armor": "cloth", "weapon": "wand", "offhand": "tome", "ring": "arcana", "primary": "int", "style": "arcane", "ammo": "rune"},
}
METALS = ["copper", "bronze", "iron", "steel", "cobalt", "moonsilver", "orichalcum", "bloodiron", "astralite", "starsteel", "vaultsteel"]
WOODS = ["pine", "birch", "chestnut", "cedar", "ebony", "ironwood", "raventhorn", "silverbark", "vesperwood", "starwood", "vaultroot"]
BEASTS = ["rabbit", "fox", "deer", "lynx", "bear", "basilisk", "gryphon", "wyvern", "panther", "stormdrake", "starbeast"]
FIBERS = ["flax", "hemp", "cotton", "nettle", "silk", "moonthistle", "byssus", "ember", "shadowsilk", "starthread", "vaultthread"]
FISH = ["bleak", "carp", "seabass", "eel", "lanternfish", "frostturbot", "embermoray", "coelacanth", "stormshark", "astralpike", "vaultkoi"]


def gear_set(cls, t):
    g = CLASS_GEAR[cls]
    ids = []
    if g["armor"] == "plate":
        ids += [f"plate_{s}_{METALS[t - 1]}" for s in ("helm", "body", "legs", "gloves", "boots")]
    elif g["armor"] == "leather":
        ids += [f"leather_{s}_{BEASTS[t - 1]}" for s in ("helm", "body", "legs", "gloves", "boots")]
    else:
        ids += [f"cloth_{s}_{FIBERS[t - 1]}" for s in ("helm", "body", "legs", "gloves", "boots")]
    w = g["weapon"]
    ids.append(f"{w}_{METALS[t - 1]}" if w in ("sword", "greatsword") else f"{w}_{WOODS[t - 1]}")
    if g["offhand"] == "shield":
        ids.append(f"shield_{METALS[t - 1]}")
    elif g["offhand"] == "tome":
        ids.append(f"tome_t{t}")
    ids += [f"cape_t{t}", f"ring_{g['ring']}_t{t}", f"ring_{g['ring']}_t{t}", f"amulet_wrath_t{t}"]
    ammo = None
    if g["ammo"] == "arrow":
        ammo = ITEMS[f"arrow_{WOODS[t - 1]}"]["ammo"]["damage"]
    elif g["ammo"] == "rune":
        ammo = ITEMS[f"rune_t{t}"]["ammo"]["damage"]
    return ids, ammo


ERA = load("era_rules.json")[0]
RANK_STATS = set(ERA["item_rank"]["applies_to_stats"])


def hero_stats(cls, L, t, quality_mult=1.0, rank_mult=1.0):
    g = CLASS_GEAR[cls]
    c = K["combat"]["hero"]
    prim_k = g["primary"]
    attrs = {"str": 5.0, "dex": 5.0, "int": 5.0, "vit": 5.0}
    attrs[prim_k] += L * (1.0 + 2)
    attrs["vit"] += L * (0.5 + 1) + (0.5 * L if cls.startswith("warrior") else 0)
    st = defaultdict(float)
    mods = defaultdict(float)
    ids, ammo = gear_set(cls, t)
    weapon = None
    for i in ids:
        eq = ITEMS[i]["equipment"]
        for k, v in eq.get("stats", {}).items():
            rk = rank_mult if k in RANK_STATS else 1.0
            st[k] += v * (quality_mult if isinstance(v, (int, float)) and k not in ("crit_chance",) else 1) * rk
        for m in eq.get("modifiers", []):
            mods[m["key"]] += m["value"]
        if eq["slot"] == "weapon":
            weapon = eq
    for a in ("str", "dex", "int", "vit"):
        attrs[a] += st.get(a, 0)
    prim = attrs[prim_k]
    cf = c["coef"]
    hp = (cf["hp"]["base"] + cf["hp"]["vit"] * attrs["vit"] + cf["hp"]["level"] * L + st["hp"]) * (1 + mods["combat_hp_pct"] / 100)
    ap = cf["ap"]["primary"] * prim + st["ap"]
    acc = cf["acc"]["base"] + cf["acc"]["level"] * L + cf["acc"]["primary"] * prim + st["accuracy"]
    eva = cf["eva"]["base"] + cf["eva"]["level"] * L + cf["eva"]["dex"] * attrs["dex"] + st["evasion"]
    wd = weapon["damage"] * quality_mult * rank_mult + (ammo or 0)
    mh = wd * (1 + ap / 100) * (1 + mods["combat_dmg_pct"] / 100)
    crit = K["combat"]["crit_base"] + weapon["stats"].get("crit_chance", 0) + mods["combat_crit_chance_pct"] / 100
    critd = K["combat"]["crit_dmg_base"] + mods["combat_crit_dmg_pct"] / 100
    return {"hp": hp, "ap": ap, "acc": acc, "eva": eva, "arm": st["armor"] * (1 + mods["combat_defense_pct"] / 100),
            "ward": st["ward"] * (1 + mods["combat_defense_pct"] / 100), "max_hit": mh, "min_ratio": weapon["min_ratio"],
            "interval": weapon["attack_interval_s"], "crit": crit, "critd": critd, "style": g["style"], "level": L}


def hit(acc, eva):
    return max(K["combat"]["hit_min"], min(K["combat"]["hit_max"], K["combat"]["hit_base"] * math.sqrt(acc / max(1e-9, eva))))


def dr(arm, lvl):
    k = K["combat"]["dr_k"]["a"] * K["combat"]["dr_k"]["r"] ** lvl
    return min(K["combat"]["dr_cap"], arm / (arm + k)) if arm > 0 else 0.0


def tri(a, d):
    beats = K["combat"]["triangle"]["beats"]
    if beats.get(a) == d:
        return K["combat"]["triangle"]["advantage"]
    if beats.get(d) == a:
        return K["combat"]["triangle"]["disadvantage"]
    return 1.0


ABILITY_FACTOR = K["combat"]["sim_assumptions"]["ability_dps_factor"]       # da core.SIM_ASSUMPTIONS
MONSTER_AVG_HIT = K["combat"]["sim_assumptions"]["monster_avg_hit_ratio"]


def fight(h, m, era_mult=1.0):
    ms = m["stats"]
    mhp = ms["hp"] * era_mult
    m_def = ms["armor"] if h["style"] != "arcane" else ms["ward"]
    p_hit = hit(h["acc"], ms["evasion"] * era_mult)
    avg = h["max_hit"] * (1 + h["min_ratio"]) / 2
    p_dps = p_hit * avg * (1 + h["crit"] * (h["critd"] - 1)) * (1 - dr(m_def * era_mult, h["level"])) * tri(h["style"], m["style"]) / h["interval"] * ABILITY_FACTOR
    m_hit = hit(ms["accuracy"] * era_mult, h["eva"])
    p_def = h["arm"] if m["damage_type"] == "physical" else h["ward"]
    m_avg = ms["max_hit"] * era_mult * MONSTER_AVG_HIT
    m_dps = m_hit * m_avg * (1 - dr(p_def, m["level"])) * tri(m["style"], h["style"]) / ms["attack_interval_s"]
    ttk = mhp / p_dps
    regen = h["hp"] * K["combat"]["hero"]["regen_base_pct_per_s"] / 100
    return {"ttk": ttk, "p_hit": p_hit, "m_hit": m_hit, "dmg_per_kill": m_dps * ttk, "m_dps": m_dps, "p_dps": p_dps, "regen": regen,
            "net_dps_taken": max(0.0, m_dps - regen), "time_to_die": h["hp"] / max(1e-9, m_dps - regen) if m_dps > regen else float("inf")}


def fight_phased(h, m, era_mult=1.0):
    """Incursione a fasi (monsters.json `phases`): ogni fase pesa per la quota di vita che copre (100→66→33→0) e ha il proprio
    stile (quindi triangolo e tipo di danno). Il TTK è la somma dei tempi per fase; il danno al secondo è la media pesata sul tempo."""
    phases = m.get("phases") or []
    if len(phases) < 2:
        return fight(h, m, era_mult)
    bounds = [p["hp_pct"] for p in phases] + [0]
    ttk = 0.0
    dmg = 0.0
    last = None
    for i, ph in enumerate(phases):
        share = (bounds[i] - bounds[i + 1]) / 100.0
        mm = dict(m)
        mm["style"] = ph["style"]
        mm["damage_type"] = "magic" if ph["style"] == "arcane" else "physical"
        f = fight(h, mm, era_mult)
        ttk += share * f["ttk"]
        dmg += share * f["ttk"] * f["m_dps"]
        last = f
    out = dict(last)
    out["ttk"] = ttk
    out["m_dps"] = dmg / ttk
    out["net_dps_taken"] = max(0.0, out["m_dps"] - out["regen"])
    out["time_to_die"] = h["hp"] / max(1e-9, out["m_dps"] - out["regen"]) if out["m_dps"] > out["regen"] else float("inf")
    out["dmg_per_kill"] = dmg
    return out


def combat_report():
    P("## 3. Combattimento: giocatore al livello della zona con equipaggiamento creato del tier (qualità Normale)")
    P("")
    P("Per ogni zona: media sui 4 mostri normali (livello medio della zona). TTK = tempo per uccidere; Danno/uccisione in % della vita; "
      "Cibo/ora con il cibo del tier; XP/h e Oro/h (solo oro diretto). Abilità stimate +25% DPS.")
    P("")
    P("| Zona | Lv eroe | Classe | Colpisce | Viene colpito | TTK | Danno/uccisione | Cibo/h | XP/h | Oro/h |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    summary = []
    for z in ZONES:
        normals = [MON[mid] for mid in z["monsters"] if MON[mid]["type"] == "normal"]
        L = round(sum(m["level"] for m in normals) / len(normals))
        t = min(11, tier_of(L))
        heal = ITEMS[f"food_{FISH[t - 1]}"]["food"]["heal"]
        for cls in ("warrior", "warrior2h", "ranger", "arcanist"):
            h = hero_stats(cls, L, t)
            rows = [fight(h, m) for m in normals]
            ttk = statistics.mean(r["ttk"] for r in rows)
            dpk = statistics.mean(r["dmg_per_kill"] for r in rows)
            regen = rows[0]["regen"]
            kills_h = 3600 / (ttk + K["combat"]["respawn_s"])
            food_h = max(0.0, (dpk - regen * ttk) * kills_h / heal)
            xp_h = kills_h * statistics.mean(m["xp"] for m in normals)
            gold_h = kills_h * statistics.mean(sum(m["gold"]) / 2 for m in normals)
            P(f"| {z['name']['it']} | {L} | {cls} | {statistics.mean(r['p_hit'] for r in rows):.0%} | {statistics.mean(r['m_hit'] for r in rows):.0%} | "
              f"{ttk:.1f} s | {dpk / h['hp']:.1%} | {food_h:.0f} | {xp_h:,.0f} | {gold_h:,.0f} |")
            summary.append((z["id"], cls, ttk, dpk / h["hp"], food_h))
    P("")
    bad = [s for s in summary if s[2] > 16 or s[2] < 3 or s[3] > 0.35 or s[4] > 450]
    for b in bad:
        P(f"- {b[0]} / {b[1]}: TTK {b[2]:.1f}s, danno/uccisione {b[3]:.0%}, cibo/h {b[4]:.0f}")
    check("combattimento", not bad, f"{len(bad)} combinazioni fuori dai limiti (TTK 3–16 s, danno/uccisione ≤ 35% vita, cibo ≤ 450/h)")
    # differenza tra classi (stessa zona, classi a una mano/due mani a parte)
    spread = []
    for z in ZONES:
        t = [x[2] for x in summary if x[0] == z["id"] and x[1] in ("warrior", "ranger", "arcanist")]
        if t:
            m = statistics.mean(t)
            spread.append((z["id"], max(abs(v - m) / m for v in t)))
    worst = max(spread, key=lambda x: x[1])
    check("classi", worst[1] <= 0.20, f"massima differenza di TTK dalla media tra Guerriero, Ramingo e Arcanista: ±{worst[1]:.0%} ({worst[0]}; obiettivo ≤ ±20%)")
    # cibo/ora: nessuna classe consuma più di 1,6 volte la classe di riferimento (Guerriero a una mano) nella stessa zona
    FOOD_RATIO_MAX = 1.6
    food_ratio = []
    for z in ZONES:
        ref = [x[4] for x in summary if x[0] == z["id"] and x[1] == "warrior"]
        if ref and ref[0] > 0:
            for x in summary:
                if x[0] == z["id"] and x[1] != "warrior":
                    food_ratio.append((x[4] / ref[0], z["id"], x[1]))
    wf = max(food_ratio)
    check("classi: cibo/ora", wf[0] <= FOOD_RATIO_MAX,
          f"cibo/ora massimo rispetto al Guerriero: {wf[0]:.2f}× ({wf[2]} in {wf[1]}; obiettivo ≤ {FOOD_RATIO_MAX:g}×)")
    return summary


def boss_report():
    P("## 4. Boss di zona, boss di dungeon e incursioni (giocatore al livello del boss, tier corrispondente)")
    P("")
    P("Sopravvivenza: secondi prima di morire **senza cibo**; Cibo necessario = danno netto durante il combattimento / cura del cibo del tier.")
    P("")
    P("| Boss | Tipo | Lv | Classe | TTK | Sopravvive senza cibo | Cibo necessario |")
    P("|---|---|---|---|---|---|---|")
    raids = {r["boss"]: r for r in load("raids.json")}
    ttk_by_type = defaultdict(list)
    food_by_type = defaultdict(list)
    boss_spread = []          # (scarto relativo del TTK dalla media delle 3 classi, boss, classe) per boss di zona e di dungeon
    for m in MON.values():
        if m["type"] not in ("boss", "dungeon_boss", "raid_boss"):
            continue
        L = min(100, m["level"])
        t = min(11, tier_of(L))
        heal = ITEMS[f"food_{FISH[t - 1]}"]["food"]["heal"]
        cls_ttk = {}
        for cls in ("warrior", "ranger", "arcanist"):
            h = hero_stats(cls, L, t, quality_mult=1.08)
            f = fight_phased(h, m) if m["type"] == "raid_boss" else fight(h, m)
            ttk = f["ttk"]
            cls_ttk[cls] = ttk
            if m["type"] == "raid_boss":
                # squadra di 3 mercenari al potere richiesto: -30% danni, cura 1,5%/s, +40% danno
                ttk = ttk / 1.40
                f["net_dps_taken"] = max(0.0, f["m_dps"] * 0.70 - f["regen"] - h["hp"] * 0.015)
            food = f["net_dps_taken"] * ttk / heal
            ttk_by_type[m["type"]].append(ttk)
            food_by_type[m["type"]].append(food)
            surv = h["hp"] / f["net_dps_taken"] if f["net_dps_taken"] > 0 else float("inf")
            P(f"| {m['name']['it']} | {m['type']} | {m['level']} | {cls} | {ttk:.0f} s | {('∞' if surv == float('inf') else f'{surv:.0f} s')} | {food:.0f} |")
        if m["type"] in ("dungeon_boss", "raid_boss"):
            mean_t = statistics.mean(cls_ttk.values())
            for cls, v in cls_ttk.items():
                boss_spread.append((abs(v - mean_t) / mean_t, m["id"], cls))
    P("")
    lim = {"boss": (25, 110, 20), "dungeon_boss": (40, 160, 40), "raid_boss": (120, 450, 60)}
    for typ, (lo, hi, fmax) in lim.items():
        tt, ff = ttk_by_type.get(typ, [0]), food_by_type.get(typ, [0])
        if typ in ("dungeon_boss", "raid_boss"):
            sp = max(x for x in boss_spread if x[1] in [k for k, v in MON.items() if v["type"] == typ])
            check(f"boss {typ}: classi", sp[0] <= 0.20, f"massima differenza di TTK dalla media delle 3 classi: ±{sp[0]:.1%} ({sp[1]}, {sp[2]}; obiettivo ≤ ±20%)")
        check(f"boss {typ}", lo <= min(tt) and max(tt) <= hi and max(ff) <= fmax,
              f"TTK {min(tt):.0f}–{max(tt):.0f} s (obiettivo {lo}–{hi} s), cibo massimo {max(ff):.0f} (obiettivo ≤ {fmax})")


def raid_winnable_report():
    """MURI (BOT-02/03): le incursioni devono essere vincibili al livello del capitolo da un Eroe con 0-3 mercenari realistici.
    Il potere di squadra conta anche l'Eroe (mercenary_rules.raid_roles: hero_share, hero_level_cap, hero_role_share). Qui:
    1) raggiungibilita': rapporto potere/richiesto (formule dei dati, nessun Eroe simulato) per l'Eroe al livello dell'incursione
       con 0 mercenari e con una squadra tipica (3 rari di livello 15): deve dare effetti di ruolo reali (f >= soglie);
    2) vincibilita': Eroe al livello dell'incursione (tier corrispondente, qualita' normale), effetti scalati su f, nessuna morte
       media e cibo <= limite, per le 3 classi base."""
    P("## 4d. Incursioni vincibili al livello del capitolo (BOT-02/03)")
    P("")
    rr = load("mercenary_rules.json")[0]["raid_roles"]
    rar = {r["id"]: r for r in load("mercenary_rules.json")[0]["rarities"]}
    tun = K["mercenary_tuning"]
    typ_power = 3 * rar["rare"]["base_power"] * (1 + tun["level_power_step"] * (15 - 1))
    P("Squadra tipica: 3 mercenari rari di livello 15 (potere %.0f). Eroe al livello dell'incursione. "
      "Effetti scalati su f = min(%.1f, potere/richiesto); ruoli scoperti: %.0f%% dell'effetto (l'Eroe li copre da solo)." %
      (typ_power, rr["ratio_cap"], rr["hero_role_share"] * 100))
    P("")
    P("| Incursione | Lv | Richiesto | f solo Eroe | f squadra tipica | Classe | TTK Eroe solo | Sopravvive (solo) | Cibo (solo) | Cibo (tipica) |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    zorder = {z["id"]: z["order"] for z in ZONES}
    worst_f_hero, worst_f_typ, worst_food, dead = 9.0, 9.0, 0.0, []
    for rd in load("raids.json"):
        m = MON[rd["boss"]]
        L = int(rd["level"])
        t = min(11, tier_of(L))
        heal = ITEMS[f"food_{FISH[t - 1]}"]["food"]["heal"]
        req = rr["power_base"] * rr["power_growth"] ** (zorder[rd["zone"]] - 1) * rr["power_party_size"]
        hero_f = min(rr["hero_level_cap"], 1.0) * rr["hero_share"]       # Eroe al livello dell'incursione: rapporto livello = 1
        f_hero = min(rr["ratio_cap"], hero_f)
        f_typ = min(rr["ratio_cap"], hero_f + typ_power / req)
        worst_f_hero, worst_f_typ = min(worst_f_hero, f_hero), min(worst_f_typ, f_typ)
        for cls in ("warrior", "ranger", "arcanist"):
            h = hero_stats(cls, L, t)
            f = fight_phased(h, m)
            rowv = []
            for fcase, role_cov in ((f_hero, rr["hero_role_share"]), (f_typ, 1.0)):
                fe = fcase * role_cov
                ttk = f["ttk"] / (1 + rr["striker"]["dmg_pct"] / 100 * fe)
                net = max(0.0, f["m_dps"] * (1 + rr["defender"]["dmg_taken_pct"] / 100 * fe) - f["regen"] - h["hp"] * rr["healer"]["regen_pct_per_s"] / 100 * fe)
                food = net * ttk / heal
                surv = h["hp"] / net if net > 0 else float("inf")
                rowv.append((ttk, surv, food))
            worst_food = max(worst_food, rowv[0][2], rowv[1][2])
            if rowv[0][1] < rowv[0][0] and rowv[0][2] > 60:
                dead.append(f"{rd['id']}/{cls}")
            sv = "∞" if rowv[0][1] == float("inf") else f"{rowv[0][1]:.0f} s"
            P(f"| {rd['name']['it']} | {L} | {req:.0f} | {f_hero:.2f} | {f_typ:.2f} | {cls} | {rowv[0][0]:.0f} s | {sv} | {rowv[0][2]:.0f} | {rowv[1][2]:.0f} |")
    P("")
    check("incursioni vincibili al livello del capitolo",
          worst_f_hero >= 0.5 and worst_f_typ >= 0.6 and not dead and worst_food <= 60,
          f"f minimo solo Eroe {worst_f_hero:.2f} (obiettivo >= 0.5), con squadra tipica {worst_f_typ:.2f} (>= 0.6); cibo massimo {worst_food:.0f} (<= 60); "
          f"incursioni senza via di scampo: {len(dead)}")


def world_boss_report():
    P("## 4b. Boss mondiali: contributo dell'Eroe e alleati simulati (docs/05 §8)")
    P("")
    P("Eroe al livello del boss (tier corrispondente), 3 classi. Fasce = quota della vita del boss inflitta dall'Eroe (dati: "
      "contribution_tiers); gli alleati simulati tolgono la quota dei dati al minuto. «Quota Eroe» = parte della vita tolta dall'Eroe "
      "quando il boss cade (con gli alleati). FIX-COMBATTIMENTO (QA4 #11): le fasce devono distinguere le build (prima Platino = 10% "
      "e ogni build ne faceva 33-81%).")
    P("")
    P("| Boss | Lv | Classe | TTK da solo | Platino dopo | Boss cade dopo | Quota Eroe | Cibo per il Platino |")
    P("|---|---|---|---|---|---|---|---|")
    wbs = load("world_bosses.json")
    ttk_by_class = defaultdict(dict)
    worst_plat = 0.0
    worst_food = 0.0
    kill_late = []
    shares = defaultdict(list)
    tiers_of = {}
    for wb in wbs:
        m = MON[wb["boss"]]
        L = min(100, m["level"])
        t = min(11, tier_of(L))
        heal = ITEMS[f"food_{FISH[t - 1]}"]["food"]["heal"]
        window = wb["window_min"] * 60
        rate = wb["simulated_allies_dps_pct_of_hp_per_min"] / 100 / 60
        plat = [x for x in wb["contribution_tiers"] if x["id"] == "platinum"][0]["damage_pct"] / 100
        tiers_of[wb["id"]] = {x["id"]: x["damage_pct"] / 100 for x in wb["contribution_tiers"]}
        for cls in ("warrior", "ranger", "arcanist"):
            h = hero_stats(cls, L, t, quality_mult=1.08)
            f = fight(h, m)
            t_plat = plat * f["ttk"]
            t_kill = 1.0 / (1.0 / f["ttk"] + rate)
            share = t_kill / f["ttk"]
            silver = [x for x in wb["contribution_tiers"] if x["id"] == "silver"][0]["damage_pct"] / 100
            food = f["net_dps_taken"] * min(silver * f["ttk"], t_kill, window) / heal
            shares[wb["id"]].append(share)
            ttk_by_class[wb["id"]][cls] = f["ttk"]
            worst_plat = max(worst_plat, t_plat)
            worst_food = max(worst_food, food)
            if t_kill > window:
                kill_late.append((wb["id"], cls, t_kill))
            P(f"| {m['name']['it']} | {m['level']} | {cls} | {fmt_h(f['ttk'] / 3600)} | {t_plat:.0f} s | {t_kill / 60:.1f} min | {share:.0%} | {food:.0f} |")
    P("")
    ok_t = all(min(v) >= tiers_of[b]["bronze"] and max(v) >= tiers_of[b]["silver"] and min(v) < tiers_of[b]["platinum"] for b, v in shares.items())
    check("boss mondiali: fasce", ok_t, "al livello del boss ogni classe arriva almeno al Bronzo, la migliore almeno all'Argento e non tutte "
          "al Platino: " + ", ".join(f"{b} quota {min(v):.0%}-{max(v):.0%}" for b, v in shares.items()))
    # FIX-COMBATTIMENTO: il limite valeva per il vecchio Platino al 10%; l'Argento (35%) costa di piu': il boss mondiale e' una
    # scelta (evento ogni 4 h, facoltativo) e il cibo e' il suo prezzo. Obiettivo: <= 150 porzioni (stima analitica, senza talenti).
    check("boss mondiali: cibo", worst_food <= 150, f"cibo massimo per arrivare all'Argento {worst_food:.0f} porzioni (obiettivo ≤ 150)")
    sp = 0.0
    sp_id = ""
    for bid, d in ttk_by_class.items():
        mean_t = statistics.mean(d.values())
        for cls, v in d.items():
            if abs(v - mean_t) / mean_t > sp:
                sp = abs(v - mean_t) / mean_t
                sp_id = f"{bid}, {cls}"
    check("boss mondiali: classi", sp <= 0.20, f"massima differenza di TTK dalla media delle 3 classi: ±{sp:.1%} ({sp_id}; obiettivo ≤ ±20%)")
    if kill_late:
        P("Boss che gli alleati e l'Eroe NON riescono ad abbattere nei 30 minuti: " + ", ".join(f"{b} ({c}, {t / 60:.0f} min)" for b, c, t in kill_late))
        P("")


def rift_mon_stats(level, mtype):
    c = K["combat"]
    t = c["monster_types"][mtype]
    cv = c["monster_curves"]
    arm = cv["arm"][0] * cv["arm"][1] ** level * t["arm"]
    return {"hp": cv["hp"][0] * cv["hp"][1] ** level * t["hp"], "max_hit": cv["max_hit"][0] * cv["max_hit"][1] ** level * t["dmg"],
            "accuracy": (cv["acc"][0] + cv["acc"][1] * level) * t["acc"], "evasion": (cv["eva"][0] + cv["eva"][1] * level) * t["eva"],
            "armor": arm, "ward": arm, "attack_interval_s": t["interval_s"]}


def rift_report():
    P("## 4c. La Breccia: crescita dei piani (docs/05 §9)")
    P("")
    rd = load("rift.json")[0]
    base = rd["floor_level_base"]
    per = rd["stat_mult_per_floor"]
    per_dmg = rd.get("dmg_mult_per_floor", per)
    P("Eroe di livello 100 con l'equipaggiamento del tier 11 (senza Ranghi, Stelle né Costellazioni: caso peggiore), contro il mostro normale e "
      "il Guardiano di ogni piano. Statistiche = curva del livello (100 + piano) × %s^piano (danno × %s^piano) × affissi cumulativi." % (per, per_dmg))
    P("")
    P("| Piano | Lv | Vita mostro | Classe | TTK mostro | Danno/uccisione | TTK Guardiano (se c'è) |")
    P("|---|---|---|---|---|---|---|")
    ok_first = True
    anomalies = 0
    for fl in (1, 10, 25, 50, 100, 200):
        lvl = base + fl
        mult = per ** fl
        mult_d = per_dmg ** fl
        aff = [a for a in rd["affixes"] if fl >= a["from_floor"]]
        def build(mtype):
            st = rift_mon_stats(lvl, mtype)
            for k in ("hp", "max_hit", "accuracy", "evasion", "armor", "ward"):
                st[k] *= mult if k != "max_hit" else mult_d
            for a in aff:
                e = a["effect"]
                st["hp"] *= 1 + e.get("hp_pct", 0) / 100
                st["max_hit"] *= 1 + e.get("dmg_pct", 0) / 100
                st["evasion"] *= 1 + e.get("evasion_pct", 0) / 100
                d = 1 + e.get("defense_pct", 0) / 100
                st["armor"] *= d
                st["ward"] *= d
            return st
        style = rd["styles_cycle"][(fl - 1) % 3]
        for cls in ("warrior", "ranger", "arcanist"):
            h = hero_stats(cls, 100, 11, quality_mult=1.08)
            mon = {"stats": build(rd["monster_type"]), "style": style, "damage_type": "magic" if style == "arcane" else "physical", "level": lvl}
            f = fight(h, mon)
            g_txt = ""
            if fl % rd["guardian_every"] == 0:
                g = {"stats": build(rd["guardian_type"]), "style": style, "damage_type": mon["damage_type"], "level": lvl}
                g_txt = f"{fight(h, g)['ttk']:.0f} s"
            vals = list(mon["stats"].values())
            if any((not math.isfinite(v)) or v > 2 ** 53 for v in vals if isinstance(v, float)):
                anomalies += 1
            if fl == 1:
                ok_first = ok_first and 3 <= f["ttk"] <= 16
            P(f"| {fl} | {lvl} | {mon['stats']['hp']:,.0f} | {cls} | {f['ttk']:.1f} s | {f['dmg_per_kill'] / h['hp']:.0%} della vita | {g_txt} |")
    P("")
    check("Breccia: piano 1", ok_first, "al piano 1 il TTK del mostro normale è 3–16 s per tutte le classi (come una zona del tier 11)")
    big = 0
    for fl in range(1, 201):
        st = rift_mon_stats(base + fl, rd["guardian_type"])
        if any((not math.isfinite(v * per ** fl * 1.3)) or v * per ** fl * 1.3 > 2 ** 53 for v in st.values()):
            big += 1
    check("Breccia: numeri", anomalies == 0 and big == 0, f"fino al piano 200 (criterio di M10) nessun valore infinito o oltre 2^53 (valori anomali: {anomalies + big})")


def fixcombat_report():
    """FIX-COMBATTIMENTO (resoconto 65): controlli strutturali sui punti del rapporto QA4. I valori misurati col motore vero
    (12 classi, offline contro tick, Custode, Breccia) sono in docs/19 §2b e si rifanno con tools/analysis/q4_*."""
    P("## 4d. Combattimento: controlli del rapporto QA4 (FIX-COMBATTIMENTO)")
    P("")
    # 1) potenziamenti: non sostituiscono l'attacco e restano attivi una parte sensata del tempo
    abil = load("abilities.json")
    boosts = [a for a in abil if a["effect"]["type"] in ("buff", "debuff", "shield") and "trigger" not in a["effect"]]
    low = [(a["id"], a["effect"].get("duration_s", 0) / max(1, a["cooldown_s"])) for a in boosts
           if a["effect"].get("duration_s", 0) / max(1, a["cooldown_s"]) < 0.2]
    check("abilità: potenziamenti", not low and boosts, f"{len(boosts)} potenziamenti, tutti attivi almeno il 20% del tempo "
          f"(durata/ricarica); sotto: {', '.join(f'{i} {u:.0%}' for i, u in low) or 'nessuno'}")
    # 2) ibride: crescita e moltiplicatore non piu penalizzanti (misura col motore: 0,96-0,99x delle classi non ibride)
    cl = {c["id"]: c for c in load("classes.json")}
    bad_h = []
    for c in cl.values():
        if not c.get("hybrid"):
            continue
        base_g = cl["warrior"]["growth_per_level"]["str"]
        r = min(c["growth_per_level"][k] for k in c["primary_attrs"]) / base_g * c["passive"]["stat_mult"]
        if not (1.0 <= r <= 1.25):
            bad_h.append((c["id"], r))
    check("classi: ibride", not bad_h, "crescita degli attributi di stile x moltiplicatore rispetto alle classi base tra 1,00 e 1,25 "
          f"(il triangolo automatico vale il resto); fuori: {bad_h or 'nessuna'}")
    # 3) XP sui mostri molto bassi: a 3 livelli dallo sblocco la zona precedente deve gia rendere meno
    ov = K["combat"]["rules"]["overlevel_xp"]
    zs = sorted(ZONES, key=lambda z: z["order"])
    worst = 1.0
    for i in range(2, len(zs)):
        prev = [MON[m]["level"] for m in zs[i - 1]["monsters"] if MON[m]["type"] == "normal"]
        L = zs[i]["unlock"]["hero_level"] + 3
        mult = statistics.mean(1.0 if lv >= ov["exempt_from_level"] else max(ov["min_pct"] / 100, 1 - max(0, L - lv - ov["grace_levels"]) * ov["pct_per_level"] / 100)
                               for lv in prev)
        worst = max(worst if worst < 1.0 else 0.0, mult)
    check("zone: restare o avanzare", worst <= 0.90, f"a sblocco+3 l'XP della zona precedente e' al massimo il {worst:.0%} (obiettivo <= 90%: "
          "senza la riduzione la zona vecchia rendeva 1,1-1,35x la nuova per ~9 livelli; misura col motore in docs/19 §2b)")
    # 4) Breccia: nessun muro improvviso ai Guardiani (TTK del Guardiano per decina di piani)
    rd = load("rift.json")[0]
    per, per_d = rd["stat_mult_per_floor"], rd.get("dmg_mult_per_floor", rd["stat_mult_per_floor"])
    h = hero_stats("warrior", 100, 11, quality_mult=1.08)
    ttks = []
    for fl in (10, 20, 30, 40, 50):
        st = rift_mon_stats(rd["floor_level_base"] + fl, rd["guardian_type"])
        for k in ("hp", "accuracy", "evasion", "armor", "ward"):
            st[k] *= per ** fl
        st["max_hit"] *= per_d ** fl
        g = {"stats": st, "style": "melee", "damage_type": "physical", "level": rd["floor_level_base"] + fl}
        ttks.append(fight(h, g)["ttk"])
    growth = max(ttks[i + 1] / ttks[i] for i in range(len(ttks) - 1))
    check("Breccia: Guardiani graduali", growth <= 3.0, f"TTK del Guardiano (Guerriero Lv 100, T11) ai piani 10-50: "
          f"{', '.join(f'{t:.0f} s' for t in ttks)}; crescita massima per decina x{growth:.2f} (obiettivo <= x3; prima x5-6)")
    # 5) QA82 Q82-2/3: nessuna munizione gratis, nessun malus di Borseggio azzerabile: i tetti combinati stanno nei dati
    cat = {m["family"]: m for m in load("modifier_catalog.json")}
    rules_c = K["combat"]["rules"]
    arrow_total = min(rules_c["ammo_recovery_max_pct"], rules_c["ammo_arrow_recovery_pct"] + (cat["ammo_save_pct"]["cap"] or 100))
    check("frecce: consumo residuo", arrow_total <= 95 and rules_c["ammo_recovery_max_pct"] < 100,
          f"recupero massimo delle frecce {arrow_total:g}% (base {rules_c['ammo_arrow_recovery_pct']:g}% + tetto di catalogo {cat['ammo_save_pct']['cap']}%, "
          f"tetto combinato {rules_c['ammo_recovery_max_pct']:g}%): consumo residuo almeno {100 - arrow_total:g}% (obiettivo: mai 0, prima 100% = frecce infinite)")
    sc = cat["thievery_stun_reduction_pct"]["cap"]
    check("Borseggio: stordimento", sc is not None and sc < 100, f"riduzione dello stordimento limitata al {sc}% dal catalogo e applicata in SkillSystem (prima senza tetto)")
    P("")


COMBAT_SUMMARY = []     # righe di combat_report (zona, classe, TTK, danno/uccisione, cibo/h): servono alla Corsa


def eff_haste(add):
    """Stessa formula di core.effective_haste_pct / Formulas.effective_haste_pct (tetto della velocità d'attacco)."""
    h = K["combat"]["rules"]["haste_cap"]
    return add if add <= h["soft_pct"] else min(h["hard_pct"], h["soft_pct"] + (add - h["soft_pct"]) * h["soft_slope"])


def corsa_eval(h0, mons, mods):
    """Valori per uccisione con i modificatori della Corsa `mods` (famiglia -> somma) sopra l'Eroe `h0` (statistiche senza
    Corsa). Modello analitico di fight(): danno, velocita' (col tetto), critico, precisione, penetrazione, colpo multiplo,
    difese, vita, rigenerazione, rubavita, spine, danni subiti, cibo; XP/oro/drop dai bonus di Bottino. Le voci di Tecnica
    (risorse, DoT, evocazioni, elementi) dipendono dal kit della classe: qui valgono 0 (stima prudente)."""
    g = lambda k: mods.get(k, 0.0)
    h = dict(h0)
    h["max_hit"] *= 1 + g("combat_dmg_pct") / 100
    h["interval"] /= (1 + eff_haste(g("combat_haste_pct")) / 100)
    h["crit"] = max(0.0, min(K["combat"]["crit_cap"], h["crit"] + g("combat_crit_chance_pct") / 100))
    h["critd"] += g("combat_crit_dmg_pct") / 100
    h["acc"] *= 1 + g("combat_acc_pct") / 100
    h["eva"] *= max(0.05, 1 + g("combat_eva_pct") / 100)
    dm = max(0.05, 1 + g("combat_defense_pct") / 100)
    h["arm"] *= dm
    h["ward"] *= dm
    h["hp"] *= max(0.05, 1 + g("combat_hp_pct") / 100)
    pen = min(0.6, g("combat_armor_pen_pct") / 100)
    multi = min(0.5, g("combat_multihit_pct") / 100)
    taken = max(0.05, 1 + g("combat_dmg_taken_pct") / 100)
    regen_pct = K["combat"]["hero"]["regen_base_pct_per_s"] + g("combat_regen_hps_pct")
    ttk = dpk = 0.0
    for m in mons:
        mm = dict(m)
        st = dict(m["stats"])
        st["armor"] *= 1 - pen
        st["ward"] *= 1 - pen
        mm["stats"] = st
        f = fight(h, mm)
        p_dps = f["p_dps"] * (1 + multi)
        m_dps = f["m_dps"] * taken
        p_dps += m_dps * g("combat_thorns_pct") / 100
        t = m["stats"]["hp"] / max(1e-9, p_dps)
        heal = p_dps * min(25.0, g("combat_lifesteal_pct")) / 100 + h["hp"] * regen_pct / 100
        ttk += t
        dpk += max(0.0, m_dps - heal) * t
    ttk /= len(mons)
    dpk /= len(mons)
    kph = 3600 / (ttk + K["combat"]["respawn_s"])
    food_mult = max(0.05, 1 + g("food_heal_pct") / 100)
    return {"ttk": ttk, "kph": kph, "xp_h": kph * (1 + g("skill_xp_pct:hero") / 100), "gold_h": kph * (1 + g("gold_gain_pct:combat") / 100),
            "drop_h": kph * (1 + g("monster_drop_pct") / 100), "loss_h": dpk * kph / food_mult, "hp": h["hp"],
            "ttd": h["hp"] / max(1e-9, dpk / max(1e-9, ttk)) if dpk > 0 else float("inf")}


def corsa_report():
    """CORSA (resoconto 91, docs/05 §14): ritmo, guadagno medio e picco del ciclo, valore netto di ogni voce, Campione,
    regola 9. Modello analitico (fight); la verifica nel motore vero e' nei test GUT (test_run_system.gd)."""
    P("## 4e. Corsa a scelte (resoconto 91)")
    P("")
    RR = load("run_rules.json")[0]
    PERKS = load("run_perks.json")
    kpc, nmax, stacks, offers = RR["kills_per_choice"], RR["max_choices"], RR["max_stacks"], RR["offers"]
    resp = K["combat"]["respawn_s"]
    fam_order = [f["id"] for f in RR["families"]]

    def mods_of(stack):
        out = defaultdict(float)
        for pid, n in stack.items():
            for m in PBY[pid]["modifiers"]:
                out[m["key"]] += m["value"] * n
        return out
    PBY = {p["id"]: p for p in PERKS}

    # 1) valore netto di ogni voce (una presa) per Guerriero/Ramingo/Arcanista a meta' delle zone 3, 6, 9
    probes = []
    for zi in (2, 5, 8):
        z = sorted(ZONES, key=lambda z_: z_["order"])[zi]
        normals = [MON[mid] for mid in z["monsters"] if MON[mid]["type"] == "normal"]
        L_ = round(sum(m["level"] for m in normals) / len(normals))
        for cls in ("warrior", "ranger", "arcanist"):
            probes.append((z["id"], cls, hero_stats(cls, L_, min(11, tier_of(L_))), normals))
    P("| Voce | Famiglia | XP/h | Oro/h | Drop/h | Danno netto subito | Tempo per cadere |")
    P("|---|---|---|---|---|---|---|")
    bad_val, bad_def = [], []
    for p in PERKS:
        rel = defaultdict(list)
        for _, _, h0, mons in probes:
            b = corsa_eval(h0, mons, {})
            e = corsa_eval(h0, mons, mods_of({p["id"]: 1}))
            for k in ("xp_h", "gold_h", "drop_h"):
                rel[k].append(e[k] / b[k] - 1)
            rel["loss"].append(e["loss_h"] / b["loss_h"] - 1 if b["loss_h"] > 1e-9 else 0.0)
            rel["ttd"].append(e["ttd"] / b["ttd"] - 1 if math.isfinite(b["ttd"]) and math.isfinite(e["ttd"]) else 0.0)
        av = {k: statistics.mean(v) for k, v in rel.items()}
        P(f"| {p['name']['it']} | {p['family']} | {av['xp_h']:+.1%} | {av['gold_h']:+.1%} | {av['drop_h']:+.1%} | {av['loss']:+.1%} | {av['ttd']:+.1%} |")
        main_axis = max(av["xp_h"], av["gold_h"], av["drop_h"])
        if p["family"] in ("offense", "loot") and not (0.01 <= main_axis <= 0.10):
            bad_val.append((p["id"], main_axis))
        if p["family"] == "defense" and (max(-av["loss"], av["ttd"]) < 0.03 or av["xp_h"] < -0.05):
            bad_def.append((p["id"], -av["loss"], av["ttd"], av["xp_h"]))
    P("")
    check("Corsa: valore delle voci", not bad_val and not bad_def,
          f"Offesa/Bottino: ogni voce +1…+10% sul suo asse (XP, oro o drop); Difesa: −3% di danno netto o +3% di tempo per cadere "
          f"con al massimo −5% di XP/h; fuori: {[(i, round(v, 3)) for i, v in bad_val] + [b[0] for b in bad_def] or 'nessuna'}")

    # 2) ciclo con «Scegli per me» (priorita' predefinita) e con priorita' Bottino: guadagno medio, picco, durata, gap
    rng = random.Random(91)
    trials = 40 if QUICK else 160

    def cycle(h0, mons, order):
        stack = defaultdict(int)
        base = corsa_eval(h0, mons, {})
        xp = gold = t = 0.0
        gaps = []
        for k in range(nmax + 1):
            e = corsa_eval(h0, mons, mods_of(stack))
            dt = kpc * (e["ttk"] + resp)
            gaps.append(dt)
            t += dt
            xp += kpc * e["xp_h"] / e["kph"]
            gold += kpc * e["gold_h"] / e["kph"]
            if k == nmax:
                break
            avail = [p for p in PERKS if stack[p["id"]] < stacks]
            offer = rng.sample(avail, min(offers, len(avail)))
            offer.sort(key=lambda p: order.index(p["family"]))
            stack[offer[0]["id"]] += 1
        ch = RR["champion"]
        e = corsa_eval(h0, mons, mods_of(stack))
        t += e["ttk"] * ch["hp_mult"] + resp
        xp += ch["reward_mult"] * e["xp_h"] / e["kph"]
        gold += ch["reward_mult"] * e["gold_h"] / e["kph"]
        bxp = base["xp_h"] / 3600
        bgold = base["gold_h"] / 3600
        return {"avg": xp / t / bxp - 1, "gold": gold / t / bgold - 1, "peak": e["xp_h"] / base["xp_h"] - 1, "dur": t / 60,
                "gap": max(gaps) / 60}

    P("| Zona | Classe | Guadagno medio XP/h | Picco | Oro (priorità Bottino) | Durata del ciclo | Intervallo massimo |")
    P("|---|---|---|---|---|---|---|")
    rows = []
    gold_first = ["loot", "offense", "technique", "defense"]
    for zid, cls, h0, mons in probes:
        rs = [cycle(h0, mons, fam_order) for _ in range(trials)]
        rg = [cycle(h0, mons, gold_first) for _ in range(trials // 2)]
        r = {k: statistics.mean(x[k] for x in rs) for k in ("avg", "peak", "dur", "gap")}
        r["gold"] = statistics.mean(x["gold"] for x in rg)
        rows.append(r)
        P(f"| {zid} | {cls} | {r['avg']:+.1%} | {r['peak']:+.1%} | {r['gold']:+.1%} | {r['dur']:.0f} min | {r['gap']:.1f} min |")
    P("")
    avg_lo, avg_hi = min(r["avg"] for r in rows), max(r["avg"] for r in rows)
    peak = max(r["peak"] for r in rows)
    dur_lo, dur_hi = min(r["dur"] for r in rows), max(r["dur"] for r in rows)
    gold_hi = max(r["gold"] for r in rows)
    check("Corsa: guadagno", 0.05 <= avg_lo and avg_hi <= 0.15 and peak <= 0.40,
          f"guadagno medio di XP/h sul ciclo con «Scegli per me» {avg_lo:+.1%}…{avg_hi:+.1%} (obiettivo +5…+15%, R2), picco a 12 scelte "
          f"{peak:+.1%} (≤ +40%); Tecnica stimata a 0 (dipende dal kit della classe)")
    check("Corsa: oro", gold_hi <= 0.25, f"oro medio sul ciclo con priorità Bottino {gold_hi:+.1%} (≤ +25%: l'oro del combattimento resta sotto le "
          "attività d'oro, §5/§5d; la Corsa vive solo a gioco aperto)")
    # gap: la zona piu' lenta (TTK massimo del report §3) con 30 uccisioni
    worst_ttk = max(s[2] for s in COMBAT_SUMMARY) if COMBAT_SUMMARY else 16.0
    gap_worst = kpc * (worst_ttk + resp) / 60
    check("Corsa: ritmo", gap_worst <= 10.0 and 35 <= dur_lo and dur_hi <= 75,
          f"intervallo tra due scelte nella zona più lenta {gap_worst:.1f} min (≤ 10, R2 §1); durata del ciclo {dur_lo:.0f}–{dur_hi:.0f} min (35–75)")

    # 3) Campione: casse in piu' rispetto al combattimento normale (per ciclo)
    dt = {d["id"]: d for d in load("drop_tables.json")}
    worst_c = 0.0
    for z in ZONES:
        normals = [MON[mid] for mid in z["monsters"] if MON[mid]["type"] == "normal"]
        cc = statistics.mean((dt.get(m.get("drop_table"), {}).get("crate") or {}).get("chance", 0.0) for m in normals)
        per_cycle = cc * (kpc * nmax)
        extra = RR["champion"]["crate_chance"] + RR["champion"]["loot_rolls"] * cc
        worst_c = max(worst_c, extra / max(1e-9, per_cycle))
    check("Corsa: Campione", worst_c <= 0.15 and RR["champion"]["max_attempts"] >= 1,
          f"casse in più dal Campione: +{worst_c:.0%} delle casse del ciclo (≤ +15%); il Campione non uccide e chiude il ciclo")

    # 4) regola 9: niente chiavi di strato, niente «more», bonus temporanei (tetto di scelte finito)
    layer = [m["key"] for p in PERKS for m in p["modifiers"] if m["key"].partition(":")[0] in RR["forbidden_keys"] or m.get("mode") == "more"]
    check("Corsa: prestigio (regola 9)", not layer and nmax < 100 and RR["offline"] == "paused",
          f"nessuna chiave di strato o «more» nelle voci ({layer or 'ok'}); {nmax} scelte poi il Campione azzera la Corsa; offline in pausa")
    # 5) tetto della velocita' d'attacco: anche con 3 Passi di Carica + tutte le fonti note resta sotto il tetto duro
    hc = K["combat"]["rules"]["haste_cap"]
    tal_h = max(sum(t["max_rank"] * m["value"] for t in load("talents.json") if t["class"] == c for m in t["modifiers_per_rank"]
                    if m["key"] == "combat_haste_pct") for c in {t["class"] for t in load("talents.json")})
    run_h = sum(m["value"] * stacks for p in PERKS for m in p["modifiers"] if m["key"] == "combat_haste_pct" and m["value"] > 0)
    tot = tal_h + run_h
    check("velocità d'attacco: tetto", eff_haste(tot) <= hc["hard_pct"] and eff_haste(10 ** 6) == hc["hard_pct"] and eff_haste(30) == 30,
          f"talenti fino a +{tal_h:g}%, Corsa fino a +{run_h:g}%: insieme +{tot:g}% → effettivi +{eff_haste(tot):.0f}%; oltre +{hc['soft_pct']}% vale "
          f"{hc['soft_slope']:g}, mai oltre +{hc['hard_pct']}% (R1 tema 1)")
    P("")


def gold_report():
    P("## 5. Oro/ora per attività (al tier di riferimento, senza bonus)")
    P("")
    P("| Tier | Raccolta (vendita grezzi, -5% tassa) | Borseggio | Combattimento (solo oro) |")
    P("|---|---|---|---|")
    ratios = []
    for t in range(1, 12):
        acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting" and a["tier"] == t]
        g_gather = 0
        if acts:
            a = acts[0]
            g_gather = 3600 / a["time_s"] * ITEMS[a["outputs"][0]["item"]]["value"] * 0.95
        th = [a for a in ACTIONS.values() if a["skill"] == "thievery" and a["tier"] == t]
        g_th = 0
        if th:
            a = th[0]
            p = THIEVERY_P_REAL          # QA3: con livello e maestria il successo reale e' ~0,9-0,95 (success.max 0,95), non 0,8
            g_th = 3600 / (a["time_s"] + (1 - p) * a["stun_s"]) * p * sum(a["gold"]) / 2
        zs = [z for z in ZONES if z["tier"] == t]
        g_c = ""
        if zs:
            normals = [MON[mid] for mid in zs[0]["monsters"] if MON[mid]["type"] == "normal"]
            g_c = f"{3600 / (K['combat']['ttk_target_s'] + K['combat']['respawn_s']) * statistics.mean(sum(m['gold']) / 2 for m in normals):,.0f}"
        P(f"| {t} | {g_gather:,.0f} | {g_th:,.0f} | {g_c} |")
        if g_gather and g_th:
            ratios.append(g_th / g_gather)
    P("")
    check("oro", 0.9 <= min(ratios) and max(ratios) <= 1.6,
          f"Borseggio (p={THIEVERY_P_REAL:g})/raccolta {min(ratios):.2f}–{max(ratios):.2f}× (obiettivo 0,9–1,6×: l'oro e' intero, ai tier bassi l'arrotondamento pesa; "
          f"prima del ritocco QA3 E5 con p=0,8: 1,23–1,46× ma a p reale 1,6–1,9 x gph)")


def gph_tier(tier):
    return K["gph"]["base"] * K["gph"]["growth"] ** (tier - 1)


def gear_purchase_report():
    P("## 5c. Equipaggiamento comprato dai mercanti (E47-8): costo di un set intero in ore di gph(tier)")
    P("")
    mk = load("market_rules.json")[0]
    mult = mk.get("buy_markup_equipment", mk["buy_markup"])
    P(f"Prezzo d'acquisto dai PNG = valore × {mult:g} (equipaggiamento; gli altri oggetti ×{mk['buy_markup']:g}). "
      "Un set intero = armatura (5 pezzi), arma, mano secondaria, mantello, 2 anelli, amuleto. Obiettivo: 1,0–4,0 ore di gph del tier, "
      "così la forgia (materiali ≈ 0,3 × il prezzo) resta la via principale e il set non si ricompra a ogni tier con spiccioli.")
    P("")
    P("| Tier | Guerriero | Ranger | Arcanista | gph(tier) |")
    P("|---|---|---|---|---|")
    lo, hi = 1e9, 0.0
    for t in range(1, 12):
        row = []
        for cls in ("warrior", "ranger", "arcanist"):
            ids, _ = gear_set(cls, t)
            price = sum(ITEMS[i]["value"] for i in ids) * mult
            h = price / gph_tier(t)
            lo, hi = min(lo, h), max(hi, h)
            row.append(f"{h:.2f} h")
        P(f"| {t} | {' | '.join(row)} | {gph_tier(t):,.0f} |")
    P("")
    check("acquisto_set", 1.0 <= lo and hi <= 4.0,
          f"set intero dai mercanti {lo:.2f}–{hi:.2f} ore di gph(tier) (obiettivo 1,0–4,0; prima di E47-8: 0,3–0,9)")


def orders_report():
    """Commesse (R-EC-3): il rendimento orario del giocatore che le evade non supera 1,5 x gph(tier), anche con la Bottega in parallelo."""
    P("## 5b. Commesse: rendimento orario contro 1,5 × gph (R-EC-3)")
    P("")
    OR = load("orders_rules.json")[0]
    MR = load("market_rules.json")[0]
    cats = set(MR["categories"])
    ex = OR.get("item_pool_excluded", {})
    mult_max = OR["reward_mult_range"][1]
    cap = 1.5
    kills_h = 3600 / (K["combat"]["ttk_target_s"] + K["combat"]["respawn_s"])
    dt = {d["id"]: d for d in load("drop_tables.json")}
    drop_rate = defaultdict(float)             # oggetti/ora dai mostri normali (uccisioni al ritmo del TTK di riferimento)
    for m in MON.values():
        d = dt.get(m.get("drop_table")) if m["type"] == "normal" else None
        for e in (d["entries"] if d else []):
            if "item" in e:
                q = e.get("qty", 1)
                q = sum(q) / 2 if isinstance(q, list) else q
                drop_rate[e["item"]] = max(drop_rate[e["item"]], kills_h * e.get("chance", 1) * q)
    INF = 1e18
    T = {i: 1 / r for i, r in drop_rate.items() if r > 0}     # ore per ottenere 1 unità, materiali intermedi compresi
    for a in ACTIONS.values():           # secondari delle azioni di raccolta (piume, gemme grezze, nidi...): ore per unità = tempo / (probabilità × quantità)
        if a.get("time_s", 0) <= 0 or a.get("inputs"):
            continue
        for s_ in a.get("secondary", []):
            q_ = s_.get("chance", 1.0) * (sum(s_.get("qty", 1)) / 2 if isinstance(s_.get("qty", 1), list) else s_.get("qty", 1))
            if "item" in s_ and q_ > 0:
                T[s_["item"]] = min(T.get(s_["item"], INF), a["time_s"] / 3600 / q_)
            elif "pick" in s_ and q_ > 0:
                tw_ = sum(p_["weight"] for p_ in s_["pick"])
                for p_ in s_["pick"]:
                    T[p_["item"]] = min(T.get(p_["item"], INF), a["time_s"] / 3600 / (q_ * p_["weight"] / tw_))
    # audit 84: anche i beni dell'Emporio (fiale, semi: 0 ore) e l'Orto/Frutteto (un raccolto ogni grow_time_min per aiuola
    # di base), così pozioni, raccolti e banchetti entrano nel controllo invece di essere saltati
    for g_ in load("shop.json"):
        if g_.get("section") == "goods" and g_.get("item"):
            T[g_["item"]] = 0.0
    plots_ = {p_["id"]: p_["base_plots"] for p_ in load("farming_plots.json")}
    for _ in range(60):
        changed = False
        for a in ACTIONS.values():
            if not a.get("outputs"):
                continue
            q0 = a["outputs"][0]["qty"]
            q0 = sum(q0) / 2 if isinstance(q0, list) else q0
            if a.get("grow_time_min"):
                if a.get("seed") not in T:
                    continue
                n_ = plots_.get("garden" if a.get("kind") == "crop" else "orchard", 1)
                c = (a["grow_time_min"] / 60 / n_ + a.get("seeds_per_plant", 1) * T[a["seed"]]) / q0
                for o in a["outputs"]:
                    if c < T.get(o["item"], INF) - 1e-12:
                        T[o["item"]] = c
                        changed = True
                continue
            if (a.get("time_s") or 0) <= 0:
                continue
            if any(i["item"] not in T for i in a.get("inputs", [])):
                continue
            c = (a["time_s"] / 3600 + sum(i["qty"] * T[i["item"]] for i in a.get("inputs", []))) / q0
            for o in a["outputs"]:
                if c < T.get(o["item"], INF) - 1e-12:
                    T[o["item"]] = c
                    changed = True
        if not changed:
            break
    rows = []
    direct = []          # vendita diretta al Mercato (valore x 1,0): tutto ciò che è vendibile tranne Finiture e Reliquie (regole proprie)
    n_excl = 0
    for iid, it in ITEMS.items():
        if not it.get("tradeable", True) or it.get("value", 0) <= 0:
            continue
        sub = it.get("subcategory")
        cat = sub if sub in cats else (it["category"] if it["category"] in cats else "")
        if not cat:
            continue
        if it["category"] not in ("skin", "relic") and iid in T:
            direct.append((it["value"] / T[iid] / gph_tier(it["tier"]), iid, cat, it["tier"]))
        if it["category"] in ex.get("categories", []) or cat in ex.get("categories", []) or iid in ex.get("items", []) or (ex.get("unique_items") and it.get("unique")):
            n_excl += 1
            continue
        if iid not in T:
            continue
        rows.append((it["value"] * mult_max / T[iid] / gph_tier(it["tier"]), iid, cat, it["tier"]))
    rows.sort(reverse=True)
    worst = rows[0]
    med = statistics.median(r[0] for r in rows)
    P(f"Ipotesi: la Commessa paga qty × valore × {OR['reward_mult_range'][0]:g}–{mult_max:g}; il giocatore produce tutto da sé (materiali intermedi compresi, tempo reale delle azioni, "
      f"drop dai mostri normali a {kills_h:.0f} uccisioni/h). Rendimento orario = valore × {mult_max:g} / ore per unità, diviso gph del tier dell'oggetto. "
      f"Oggetti esclusi dal pool: {n_excl} (categorie {', '.join(ex.get('categories', []))}, uniche da drop, {len(ex.get('items', []))} oggetti sottovalutati).")
    P("")
    P("| Oggetto | Categoria | Tier | Rendimento / gph |")
    P("|---|---|---|---|")
    for r_, iid, cat, t in rows[:8]:
        P(f"| {iid} | {cat} | {t} | {r_:.2f}× |")
    P("")
    shop_cap = K["estate"]["shop_income_cap_gph"]
    P(f"Mediana {med:.2f}× · massimo {worst[0]:.2f}× ({worst[1]}). La Bottega della Tenuta rende al massimo {shop_cap:g}× gph in parallelo, sul proprio flusso: "
      f"totale teorico {worst[0] + shop_cap:.2f}× gph, due attività distinte ciascuna sotto il proprio tetto.")
    P("")
    bad = [r for r in rows if r[0] > cap * 1.005]       # 0,5% di tolleranza: i valori degli oggetti sono interi
    check("commesse", not bad,
          f"rendimento massimo delle Commesse {worst[0]:.2f}× gph (obiettivo ≤ {cap:g}×), con la Bottega in parallelo al massimo {worst[0] + shop_cap:.2f}×; "
          f"{len(bad)} oggetti oltre il limite" + (": " + ", ".join(f"{r[1]} {r[0]:.1f}×" for r in bad[:5]) if bad else ""))
    # Fattibilità (audit 84, QA3 #9): la Commessa più piccola (volume elastico × qty_range[0], volume come MarketSystem.volume)
    # non deve chiedere più di max_production_hours di produzione propria. Il volume conta solo l'ultima azione, quindi gli
    # oggetti con ingredienti rari (gemme: 1% della Miniera) chiedevano centinaia di ore.
    dem = MR["demand"]
    rate_ = defaultdict(float)
    for a in ACTIONS.values():
        ts_ = a.get("time_s") or 0
        if ts_ > 0:
            for o in a.get("outputs", []):
                q_ = o.get("qty", 1)
                rate_[o["item"]] = max(rate_[o["item"]], (sum(q_) / 2 if isinstance(q_, list) else q_) / ts_ * 3600)

    def vol_(iid):
        if rate_[iid] > 0:
            return max(dem["min_volume"], dem["elasticity_hours_of_production"] * rate_[iid])
        return max(dem["min_volume"], dem["drop_volume_per_tier"] / max(1, ITEMS[iid].get("tier", 1)))
    max_h = OR["max_production_hours"]
    feas = []
    for _r, iid, cat, t in rows:
        qmin = max(1, round(vol_(iid) * OR["qty_range"][0]))
        feas.append((qmin * T[iid], iid, qmin))
    feas.sort(reverse=True)
    n_list = len([i for i in ex.get("items", []) if i in ITEMS])
    P(f"Fattibilità: la Commessa più piccola di ogni oggetto del pool chiede al massimo {feas[0][0]:.1f} h di produzione propria "
      f"({feas[0][1]}, {feas[0][2]} pezzi; tetto {max_h:g} h, vita della Commessa {OR['lifetime_days']:g} giorni). "
      f"Oggetti tolti dal pool per questo motivo o per valore: {n_list} (gemme tagliate, anelli, amuleti, bastoni e bacchette: la gemma grezza esce "
      f"dall'1% delle azioni di Miniera).")
    P("")
    fbad = [f for f in feas if f[0] > max_h]
    check("commesse: fattibilità", not fbad,
          f"Commessa minima ≤ {max_h:g} h di produzione propria per tutti gli oggetti del pool (massimo {feas[0][0]:.1f} h); {len(fbad)} oltre"
          + (": " + ", ".join(f"{f[1]} {f[0]:.0f} h" for f in fbad[:5]) if fbad else "")
          + " (prima dell'audit 84: 128 oggetti oltre, Commessa minima fino a 252 h e massima fino a 757 h)")
    direct.sort(reverse=True)
    dbad = [r for r in direct if r[0] > cap * 1.005]
    P(f"Vendita diretta al Mercato (valore × 1, nessuna Commessa; B42-2): massimo {direct[0][0]:.2f}× ({direct[0][1]}), mediana "
      f"{statistics.median(r[0] for r in direct):.2f}×. Le Rune di tier 1-4 e i Tomi di tier 1-3 non sono vendibili (valore intero minimo 1 per 25 pezzi).")
    P("")
    check("vendita_diretta", not dbad,
          f"rendimento massimo della vendita diretta {direct[0][0]:.2f}× gph (obiettivo ≤ {cap:g}×); {len(dbad)} oggetti oltre il limite"
          + (": " + ", ".join(f"{r[1]} {r[0]:.1f}×" for r in dbad[:5]) if dbad else ""))


def bank_price_fn(formula):
    """Prezzo dell'n-esimo spazio comprato dalla formula dei dati («min(tetto, round(base * crescita^n))»), come MarketSystem."""
    import re
    m = re.search(r"(\d+(?:\.\d+)?)\s*\*\s*(\d+(?:\.\d+)?)\^n", formula)
    cap = re.search(r"min\(\s*(\d+(?:\.\d+)?)", formula)
    base, growth = float(m.group(1)), float(m.group(2))
    top = float(cap.group(1)) if cap else float("inf")
    return lambda n: round(min(top, base * growth ** n))


def bank_capacity_report():
    """5e. Capacità del Deposito (feedback giocatore 23/10/2026, resoconto 114): spazi necessari per fase contro spazi gratuiti e
    costo di quelli da comprare, in confronto all'oro attivo della fase. Il vecchio prezzo (800*1,07^n, base 60) è mostrato per confronto."""
    S = K["bank"]["study"]
    shop = next(e for e in load("shop.json") if e["id"] == "bank_slot")
    price = bank_price_fn(shop["price_formula"])
    old_price = bank_price_fn("min(5000000, round(800 * 1.07^n))")
    base, old_base = int(shop["base_slots"]), 60
    nodes = [n for n in load("constellations.json") if n["modifier_per_level"]["key"] == "bank_slots"]
    vault_per_level = sum(float(n["modifier_per_level"]["value"]) for n in nodes)
    vault_max = sum(float(n["modifier_per_level"]["value"]) * n["max_level"] for n in nodes if n["max_level"])
    quests = [(q["chapter"], int(q["rewards"]["bank_slots"])) for q in load("quests.json") if q.get("rewards", {}).get("bank_slots")]
    q_total = sum(s for _, s in quests)
    tbh = S["tier_by_hour"]

    def tier_h(h):
        t = 1
        for a, b in tbh:
            if h >= a:
                t = b
        return t

    def need(h):
        return (S["need_base"] + S["need_per_tier"] * tier_h(h) + S["need_per_hour"] * h) * (1 + S["headroom_pct"] / 100.0)

    def free_sources(h):
        q = sum(s for ch, s in quests if S["chapter_hours"].get(str(ch), 1e9) <= h)
        lv = 0
        for hh, l in S["vault_levels_by_hour"]:
            if h >= hh:
                lv = l
        return base + q + vault_per_level * lv

    def income(h0, h1):
        s, h = 0.0, h0
        while h < h1:
            s += gph_tier(tier_h(h)) * S["active_gold_mult"] * 0.1
            h += 0.1
        return s

    P("## 5e. Capacità del Deposito: spazi necessari, fonti gratuite e costo di quelli da comprare")
    P("")
    P(f"Base {base} spazi (prima {old_base}); prezzo dell'n-esimo spazio comprato `{shop['price_formula']}` (prima `min(5000000, round(800 * 1.07^n))`), "
      f"massimo {shop['max_purchases']} acquisti. Fonti permanenti gratuite: {len(quests)} missioni principali (+{q_total} in tutto), "
      f"Costellazione «Caveau di Famiglia» (+{vault_per_level:g} per livello, massimo +{vault_max:g}), reliquia Forziere Senza Fondo (+40). "
      f"Spazi necessari = ({S['need_base']} + {S['need_per_tier']} × tier + {S['need_per_hour']} × ore) × {1 + S['headroom_pct'] / 100:g} "
      f"(ipotesi tarata sul bot QA81: 124 posti usati a ~24 h). Oro attivo = {S['active_gold_mult']:g} × gph(tier) per ora (prudente, §5d: 1,09–1,42).")
    P("")
    P("| Ore | Tier | Necessari | Gratuiti | Da comprare (totale) | Costo della fase | Oro attivo della fase | Quota | Prossimo spazio | Costo col vecchio prezzo/base |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    bought = old_bought = 0
    prev = 0.0
    worst = 0.0
    shares = []
    for h in S["checkpoints_h"]:
        nd = need(h)
        want = max(bought, math.ceil(nd - free_sources(h)))
        cost = sum(price(i) for i in range(bought, want))
        old_want = max(old_bought, math.ceil(nd - old_base - 0))
        old_cost = sum(old_price(i) for i in range(old_bought, old_want))
        inc = income(prev, h)
        share = cost / inc if inc else 0.0
        worst = max(worst, share)
        shares.append((h, share))
        P(f"| {h} | {tier_h(h)} | {nd:.0f} | {free_sources(h):.0f} | {want - bought} ({want}) | {cost:,} | {inc:,.0f} | {share:.1%} | {price(want):,} | {old_cost:,} |")
        bought, old_bought, prev = want, old_want, float(h)
    P("")
    top = base + q_total + vault_max + 40 + shop["max_purchases"]
    end_need = need(S["checkpoints_h"][-1])
    check("deposito: costo degli spazi", worst * 100 <= S["max_phase_cost_pct"],
          f"gli spazi da comprare per tenere il passo costano al massimo il {worst:.0%} dell'oro attivo della fase (tetto {S['max_phase_cost_pct']}%); "
          f"col vecchio prezzo e base 60 la stessa tabella supera il 100% già alla prima fase")
    check("deposito: base", base >= need(S["checkpoints_h"][0]) and base > old_base,
          f"la base ({base}) copre i primi {S['checkpoints_h'][0]} h senza comprare nulla (necessari {need(S['checkpoints_h'][0]):.0f})")
    check("deposito: capacità massima", top >= end_need * 2 and price(shop["max_purchases"] - 1) <= 5_000_000,
          f"capacità massima {top:.0f} spazi (base + missioni + Caveau al massimo + reliquia + {shop['max_purchases']} acquisti) contro {end_need:.0f} necessari a "
          f"{S['checkpoints_h'][-1]} h; l'ultimo spazio costa {price(shop['max_purchases'] - 1):,} (tetto 5 M)")
    infinite = [n["id"] for n in nodes if not n["max_level"]]
    check("deposito: prestigio (regola 9)", not infinite and shop.get("max_purchases"),
          f"ogni fonte di spazi è finita: acquisti ≤ {shop['max_purchases']}, missioni +{q_total}, {len(nodes)} nodo di Costellazione con livello massimo "
          f"({'nessuno infinito' if not infinite else 'INFINITI: ' + ', '.join(infinite)}); gli spazi non danno oro né accelerano alcuno strato")
    # F15: Armeria (docs/ui_redesign/02 §4.1, §6). L'equipaggiamento e gli attrezzi non occupano Spazio ma hanno un tetto tecnico.
    SP = K["bank"]["space"]
    G = S["gear_need"]
    gear_need = (G["slots_per_set"] * G["sets_owned"] + G["tool_slots"] * G["tool_stock"]) * (1 + G["stock_pct"] / 100.0)
    check("deposito: Armeria", SP["gear_cap"] >= G["min_cap_factor"] * gear_need,
          f"tetto dell'Armeria {SP['gear_cap']} contro un bisogno a {S['checkpoints_h'][-1]} h di {gear_need:.0f} pezzi "
          f"(= ({G['slots_per_set']} slot × {G['sets_owned']} set + {G['tool_slots']} attrezzi × {G['tool_stock']} scorte) × {1 + G['stock_pct'] / 100:g}); "
          f"richiesto almeno {G['min_cap_factor']}× ({G['min_cap_factor'] * gear_need:.0f}); avviso al {SP['gear_warn_pct']}%")
    cat_stack = {}
    for it in ITEMS.values():
        cat_stack.setdefault(it["category"], set()).add(bool(it.get("stackable", False)))
    bad_cat = [c for c in SP["free_categories"] if c not in cat_stack]
    bad_stack = [c for c in SP["free_categories"] if True in cat_stack.get(c, set())]
    check("deposito: classi dello spazio", not bad_cat and not bad_stack and SP["free_categories"],
          f"categorie libere {SP['free_categories']} tutte esistenti nei dati ({'sì' if not bad_cat else 'MANCANO: ' + ', '.join(bad_cat)}) e mai impilabili "
          f"({'sì' if not bad_stack else 'IMPILABILI: ' + ', '.join(bad_stack)}): ogni pezzo libero è un'istanza, quindi l'Armeria è contabile")
    P("")


def somma_fonti_report():
    """Somma delle fonti d'oro (QA3 §1, R-EC-3): R-EC-3 vale per ogni fonte, ma il giocatore ne cumula una attiva e le passive.
    attivo = la migliore tra Borseggio (p reale), raccolta venduta con 4 flussi alternati, miglior catena artigianale;
    passivo = Apprendisti (5 slot, grezzi venduti) + Bottega (tetto) + Spedizioni (stima MC di QA3). Obiettivo: attivo <= 1,5 e somma <= SOMMA_MAX."""
    P("## 5d. Somma delle fonti d'oro (attiva + passive) in × gph(tier)")
    P("")
    MR = load("market_rules.json")[0]
    ER = load("expedition_rules.json")[0]
    E_h = MR["demand"]["elasticity_hours_of_production"]
    half = MR["demand"]["half_life_h"]
    tax = MR["sell_tax"]
    cats = set(MR["categories"])
    ap = [b for b in load("estate_buildings.json") if b["id"] == "academy"][0]["effect"]
    eff_cap = K["apprentice_tuning"]["eff_cap"]            # stessa fonte di ApprenticeSystem
    slots = int(K["apprentice_tuning"]["max_slots"])
    shop_cap = K["estate"]["shop_income_cap_gph"]
    exped = ER["passive_income_gph_estimate"]

    rate = defaultdict(float)
    for a in ACTIONS.values():
        if a.get("time_s", 0) > 0:
            for o in a.get("outputs", []):
                q = o["qty"]
                q = sum(q) / 2 if isinstance(q, list) else q
                rate[o["item"]] = max(rate[o["item"]], q / a["time_s"] * 3600)

    def vol(iid):
        r = rate.get(iid, 0.0)
        return max(20.0, E_h * r) if r > 0 else max(20.0, 300.0 / max(1, ITEMS[iid].get("tier", 1)))

    def stream(v, V, r, hours=240):
        """Oro/ora a regime vendendo r unita'/ora ogni ora (integrale della curva, emivita del mercato)."""
        decay, x, tot, n = 0.5 ** (1 / half), 0.0, 0.0, 0
        for h in range(hours):
            x *= decay
            rev = v * (1 - tax) * V * math.log((V + x + r) / (V + x))
            x += r
            if h >= hours * 0.6:
                tot += rev
                n += 1
        return tot / n

    kills_h = 3600 / (K["combat"]["ttk_target_s"] + K["combat"]["respawn_s"])
    dt = {d["id"]: d for d in load("drop_tables.json")}
    drop_rate = defaultdict(float)
    for m in MON.values():
        d = dt.get(m.get("drop_table")) if m["type"] == "normal" else None
        for e in (d["entries"] if d else []):
            if "item" in e:
                q = e.get("qty", 1)
                q = sum(q) / 2 if isinstance(q, list) else q
                drop_rate[e["item"]] = max(drop_rate[e["item"]], kills_h * e.get("chance", 1) * q)
    INF = 1e18
    T = {i: 1 / r for i, r in drop_rate.items() if r > 0}
    for a in ACTIONS.values():
        if a.get("time_s", 0) <= 0 or a.get("inputs"):
            continue
        for s_ in a.get("secondary", []):
            q_ = s_.get("chance", 1.0) * (sum(s_.get("qty", 1)) / 2 if isinstance(s_.get("qty", 1), list) else s_.get("qty", 1))
            if "item" in s_ and q_ > 0:
                T[s_["item"]] = min(T.get(s_["item"], INF), a["time_s"] / 3600 / q_)
            elif "pick" in s_ and q_ > 0:
                tw_ = sum(p_["weight"] for p_ in s_["pick"])
                for p_ in s_["pick"]:
                    T[p_["item"]] = min(T.get(p_["item"], INF), a["time_s"] / 3600 / (q_ * p_["weight"] / tw_))
    for _ in range(60):
        ch = False
        for a in ACTIONS.values():
            if a.get("time_s", 0) <= 0 or not a.get("outputs") or any(i["item"] not in T for i in a.get("inputs", [])):
                continue
            q0 = a["outputs"][0]["qty"]
            q0 = sum(q0) / 2 if isinstance(q0, list) else q0
            c = (a["time_s"] / 3600 + sum(i["qty"] * T[i["item"]] for i in a.get("inputs", []))) / q0
            for o in a["outputs"]:
                if c < T.get(o["item"], INF) - 1e-12:
                    T[o["item"]] = c
                    ch = True
        if not ch:
            break

    def tradeable(iid):
        return ITEMS[iid].get("tradeable", True) and ITEMS[iid].get("value", 0) > 0

    P("| Tier | Borseggio | Raccolta 4 flussi | Miglior catena | **Attivo (max)** | Apprendisti | Bottega | Spedizioni | **Passivo** | **Somma** |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    worst_act, worst_sum = 0.0, 0.0
    for t in range(1, 12):
        g = gph_tier(t)
        th = [a for a in ACTIONS.values() if a["skill"] == "thievery" and a["tier"] == t][0]
        pr = THIEVERY_P_REAL
        g_th = 3600 / (th["time_s"] + (1 - pr) * th["stun_s"]) * pr * sum(th["gold"]) / 2 / g
        gat = [a for a in ACTIONS.values() if a["tier"] == t and not a.get("inputs") and a.get("time_s", 0) > 0
               and a["skill"] in ("woodcutting", "mining", "fishing", "foraging", "trapping")]

        def flow(a, share):
            inc = 0.0
            for o in a["outputs"]:
                if tradeable(o["item"]):
                    q = o["qty"]
                    q = sum(q) / 2 if isinstance(q, list) else q
                    inc += stream(ITEMS[o["item"]]["value"], vol(o["item"]), q / a["time_s"] * 3600 * share)
            return inc
        incs = sorted(((flow(a, 1.0), a) for a in gat), key=lambda x: -x[0])
        g_gat4 = sum(flow(a, 0.25) for _, a in incs[:4]) / g
        g_app = sum(flow(a, eff_cap) for _, a in incs[:slots]) / g
        best_c = 0.0
        for iid, it in ITEMS.items():
            if iid in T and tradeable(iid) and it.get("tier", 0) == t and it["category"] not in ("skin", "relic"):
                best_c = max(best_c, stream(it["value"], vol(iid), 1 / T[iid]) / g)
        act = max(g_th, g_gat4, best_c)
        pas = g_app + shop_cap + exped
        worst_act, worst_sum = max(worst_act, act), max(worst_sum, act + pas)
        P(f"| {t} | {g_th:.2f} | {g_gat4:.2f} | {best_c:.2f} | **{act:.2f}** | {g_app:.2f} | {shop_cap:.2f} | {exped:.2f} | **{pas:.2f}** | **{act + pas:.2f}** |")
    P("")
    P(f"Apprendisti: {slots} slot a efficienza {eff_cap:g} (dati `estate_buildings`), grezzi venduti in 5 flussi distinti al Mercato (elasticità {E_h:g} h); "
      f"Spedizioni: {exped:g} × gph (Monte Carlo QA3 §1, tutti i tipi, 4 squadre). Senza bonus: con i bonus di profilo le singole fonti salgono (§9).")
    P("")
    check("somma_fonti", worst_act <= 1.5 * 1.005 and worst_sum <= SOMMA_MAX,
          f"fonte attiva massima {worst_act:.2f}× (≤ 1,5), somma attiva+passive massima {worst_sum:.2f}× gph (obiettivo ≤ {SOMMA_MAX:g}; prima della correzione QA3 ≈ 4,0)")


def crate_report():
    P("## 6. Casse: valore atteso, pity e Schegge")
    P("")
    rules = load("crate_rules.json")[0]
    w = {r["id"]: r["weight_pct"] for r in rules["rarities"]}
    pity = rules["pity"]
    eff = pity["effective_rarity_pct"]            # calcolo esatto (core.relic_pity_stats / effective_rarity_pct)
    # verifica Monte Carlo del calcolo esatto (stessa regola di core.relic_pity_stats)
    rng = random.Random(42)
    N = 200_000 if not QUICK else 40_000
    since, relics = 0, 0
    for _ in range(N):
        p_rel = 1.0 if since + 1 >= pity["hard"] else min(1.0, w["relic"] / 100 + (pity["soft_step"] * (since - pity["soft_start"] + 1) if since >= pity["soft_start"] else 0))
        if rng.random() < p_rel:
            relics += 1
            since = 0
        else:
            since += 1
    mc = relics / N
    P(f"- Probabilità nominale ★: {w['relic']}% (1 su {100 / w['relic']:.0f}). Con la pity (morbida da {pity['soft_start']}, dura a {pity['hard']}): "
      f"**{pity['effective_relic_pct']}%** esatta, 1 su **{pity['mean_openings_per_relic']}** in media (verifica Monte Carlo su {N:,} aperture: {mc:.3%}).")
    P(f"- Probabilità effettive di tutte le rarità (da mostrare accanto alle nominali): " + ", ".join(f"{k} {v}%" for k, v in eff.items()) + ".")
    shards = rules["dismantle_shards"]
    ev_sh = sum(eff[r] / 100 * shards[r] for r in shards)
    P(f"- Schegge attese per apertura fondendo tutto (pity inclusa): {ev_sh:.2f}.")
    P("")
    conds = {c["id"]: c["value_mult"] for c in rules["conditions"]}
    ann = 1 + rules["annalist"]["chance"] * (rules["annalist"]["value_mult"] - 1)

    def item_value(iid):
        it = ITEMS.get(iid)
        if not it:                        # famiglio ★ nel pool: nessun valore in oro
            return 0.0
        sk = it.get("skin") or it.get("relic") or {}
        cm = sum(pct / 100 * conds[c] for c, pct in sk.get("condition_odds", {}).items()) or 1.0
        return it["value"] * cm * ann

    shop = {x["item"]: x["price"] for x in load("shop.json") if x.get("item", "").startswith("key_")}
    P("| Cassa | Chiave | Prezzo chiave all'Emporio | Valore atteso contenuto (oro) | Ritorno vs chiave comprata | Oro/ora di riferimento del tier |")
    P("|---|---|---|---|---|---|")
    rets = []
    crate_info = []
    for it in ITEMS.values():
        if it["category"] != "crate" or it["subcategory"] != "crate":
            continue
        c = it["crate"]
        by_r = defaultdict(list)
        for sid in c["skins"]:
            by_r[ITEMS[sid]["rarity"]].append(item_value(sid))
        by_r["relic"] = [item_value(r) for r in c["relic_pool"]]
        probs = eff if c.get("pity_family") else {k: v for k, v in c["odds"].items()}
        ev = sum(probs[r] / 100 * statistics.mean(vals) for r, vals in by_r.items() if vals)
        kv = shop[c["key"]]
        kt = {1: 1, 2: 3, 3: 5, 4: 7, 5: 9, 6: 11}[ITEMS[c["key"]]["key_tier"]]
        gph = K["gph"]["base"] * K["gph"]["growth"] ** (kt - 1)
        ret = ev / max(1, kv + it["value"])
        rets.append((it["id"], ret))
        crate_info.append((it, c, by_r, probs, kv))
        P(f"| {it['name']['it']} | {ITEMS[c['key']]['name']['it']} | {kv:,} | {ev:,.0f} | {ret:.0%} | {gph:,.0f} |")
    P("")
    P("Il ritorno in oro è volutamente < 100%: le casse sono un **pozzo di oro e materiali**; il valore vero sono i bonus delle "
      "Finiture, le collezioni e le ★. Il calcolo usa le probabilità **effettive** (pity inclusa), le probabilità delle condizioni "
      "di ogni finitura e l'Annalista. Nessuna cassa si compra con denaro reale.")
    P("")
    lo, hi = min(r for _, r in rets), max(r for _, r in rets)
    check("casse: ritorno", 0.55 <= lo and hi <= 0.80, f"ritorno atteso {lo:.0%}–{hi:.0%} del prezzo della chiave comprata (obiettivo 55–80%)")
    mean_open = pity["mean_openings_per_relic"]
    check("casse: pity", 150 <= mean_open <= 220 and abs(mc * 100 - pity["effective_relic_pct"]) < 0.05,
          f"1 ★ ogni {mean_open} aperture (obiettivo 150–220), Monte Carlo coerente col calcolo esatto")
    # Destino Paziente al massimo anticipa la pity morbida: la ★ resta nella forchetta 150-220
    pn = {n["id"]: n for n in load("constellations.json")}["c_so_pity"]
    early = pn["modifier_per_level"]["value"] * pn["max_level"]
    base_p, surv, mean_node = w["relic"] / 100, 1.0, 0.0       # stessa regola esatta di core.relic_pity_stats
    for since_ in range(pity["hard"]):
        p_ = 1.0 if since_ + 1 >= pity["hard"] else min(1.0, base_p + (pity["soft_step"] * (since_ - (pity["soft_start"] - early) + 1) if since_ >= pity["soft_start"] - early else 0.0))
        mean_node += surv
        surv *= 1 - p_
    P(f"- Con «Destino Paziente» al massimo (pity morbida anticipata di {early:g} aperture, da {pity['soft_start'] - early:g}): 1 ★ ogni **{mean_node:.1f}** aperture.")
    P("")
    check("casse: pity (Destino Paziente)", 150 <= mean_node <= 220,
          f"con il nodo al massimo (-{early:g} aperture) 1 ★ ogni {mean_node:.1f} aperture (obiettivo 150–220)")
    challenge_report(rules, eff)
    crate_profiles(crate_info, rules, ITEMS_BY_KEY_ACTION())


def challenge_report(rules, eff):
    """Sfida dei Collezionisti (audit 84, QA3 #12): la ★ non deve decidere la classifica da sola. Peso della ★ nel punteggio
    atteso <= 40% e probabilità di vincere con 35 aperture a settimana (Emporio 5/giorno, tier 3) tra 10% e 35%, crescente
    con le aperture (Monte Carlo con le probabilità effettive, rivali normali con la deviazione dei dati)."""
    ch = rules["collectors_challenge"]
    pts = ch["points"]
    ev_ = sum(pts[r] * eff[r] / 100 for r in pts)
    share = pts["relic"] * eff["relic"] / 100 / ev_
    rar_, w_ = list(eff.keys()), [eff[r] for r in eff]
    rng = random.Random(84)
    tier = 3
    sims = 4000 if QUICK else 20000

    def p_first(n):
        won = 0
        for _ in range(sims):
            s = sum(pts[d] for d in rng.choices(rar_, weights=w_, k=n))
            if all(s >= max(0, round(rng.gauss(r["mean_per_tier"] * tier, r["mean_per_tier"] * tier * r["dev_pct"] / 100))) for r in ch["rivals"]):
                won += 1
        return won / sims
    ps = {n: p_first(n) for n in (10, 35, 75, 150)}
    P(f"- **Sfida dei Collezionisti**: punti {', '.join(f'{k} {v}' for k, v in pts.items())}; punteggio atteso {ev_:.2f} per apertura, "
      f"di cui la ★ {share:.0%}. Probabilità di arrivare primi (tier {tier}): " + " · ".join(f"{n} aperture {p:.0%}" for n, p in ps.items()) + ".")
    P("")
    mono = all(ps[a] <= ps[b] + 0.02 for a, b in [(10, 35), (35, 75), (75, 150)])
    check("casse: Sfida (peso della ★)", share <= 0.40 and 0.10 <= ps[35] <= 0.35 and mono,
          f"la ★ vale il {share:.0%} del punteggio atteso (≤ 40%; con 1000 punti era il 61%); primo posto con 35 aperture/settimana {ps[35]:.0%} "
          f"(10–35%), crescente con le aperture ({ps[10]:.0%} → {ps[150]:.0%})")


def ITEMS_BY_KEY_ACTION():
    """chiave -> costo in oro dei materiali della ricetta di fabbricazione (somma qty × valore degli ingredienti diretti)."""
    out = {}
    for a in ACTIONS.values():
        for o in a.get("outputs", []):
            if o["item"].startswith("key_") and a.get("inputs"):
                out[o["item"]] = sum(i["qty"] * ITEMS[i["item"]]["value"] for i in a["inputs"]) / max(1, o["qty"])
    return out


def crate_profiles(crate_info, rules, craft_cost):
    """T-P4: (a) valore atteso della cassa contro il costo di FABBRICAZIONE della chiave; (b) distribuzione p10/p50/p90 su 100 aperture,
    con tassa di vendita del 10% (che il ritorno 'vs chiave comprata' non conteneva)."""
    P("### Casse: profili di ritorno (T-P4)")
    P("")
    P("Il ritorno 'vs chiave comprata' non dice niente a chi fabbrica le chiavi (il prezzo dell'Emporio è ~2,5× il valore della chiave). "
      "Qui il valore atteso è confrontato col **costo dei materiali della chiave** e la distribuzione è calcolata su 100 aperture "
      "(Monte Carlo, vendita al 90% del valore: tassa 10%).")
    P("")
    P("| Cassa | Costo materiali chiave | Valore atteso | EV / costo di fabbricazione | p10 | p50 | p90 | % in attivo (100 aperture, chiave fabbricata) |")
    P("|---|---|---|---|---|---|---|---|")
    rng = random.Random(7)
    trials = 300 if QUICK else 1500
    tax = 0.9
    bad_craft, bad_loss = [], []
    for it, c, by_r, probs, kv in crate_info:
        rar = [r for r in by_r if by_r[r] and probs.get(r, 0) > 0]
        wts = [probs[r] for r in rar]
        ev = sum(probs[r] / 100 * statistics.mean(by_r[r]) for r in rar) * tax
        cost = craft_cost.get(c["key"], float("nan"))
        ratios = []
        for _ in range(trials):
            tot = 0.0
            for r in rng.choices(rar, wts, k=100):
                tot += rng.choice(by_r[r])
            ratios.append(tot * tax / max(1.0, 100 * (cost + it["value"])))
        ratios.sort()
        p10, p50, p90 = ratios[int(0.1 * trials)], ratios[trials // 2], ratios[int(0.9 * trials)]
        profit = sum(1 for x in ratios if x > 1) / trials
        P(f"| {it['name']['it']} | {cost:,.0f} | {ev:,.0f} | {ev / max(1.0, cost):.1f}× | {p10:.2f} | {p50:.2f} | {p90:.2f} | {profit:.0%} |")
        if ev / max(1.0, cost) > 1.0:
            bad_craft.append((it["id"], ev / max(1.0, cost)))
        if profit > 0.40:
            bad_loss.append((it["id"], profit))
    P("")
    goal("casse: pozzo per chi fabbrica (D-9)", not bad_craft,
         f"{len(bad_craft)} casse hanno EV > costo dei materiali della chiave" + (": " + ", ".join(f"{i} {r:.1f}×" for i, r in bad_craft[:6]) if bad_craft else ""))
    goal("casse: rischio di perdita (100 aperture)", not bad_loss,
         f"{len(bad_loss)} casse sono in attivo nel >40% dei casi dopo 100 aperture" + (": " + ", ".join(f"{i} {p:.0%}" for i, p in bad_loss[:6]) if bad_loss else ""))


STAR_MIN_H = None          # tempo minimo per Stella (star_pacing), letto da time_push_report (UI F13)
STAR_CONST_MIN_H = None    # idem con Polvere e Costellazioni al massimo (prestige_layers)
ERA_WORST_H = None         # ore per Era massime (era_pacing)
ESTATE_FIRST_H = None      # ore di Tenuta alla prima Rifondazione (lo imposta estate_report, lo legge prestige_layers)


def estate_report():
    global ESTATE_FIRST_H
    P("## 7. Tenuta: crescita e prima Rifondazione (simulazione a circuito chiuso)")
    P("")
    P("Ipotesi: tutta la produzione viene venduta dalla Bottega all'80% del valore dei tronchi del tier corrente, fino a un tetto orario di 0,8 × gph(tier) (il resto produce solo Punti Prosperità); il tier del giocatore "
      "sale di 1 ogni 12 ore di Tenuta (max 10); reinvestimento automatico nell'acquisto con miglior rapporto produzione/costo; "
      "ogni livello di edificio richiede 1 colono (Casolare: 5 + 3 per livello).")
    P("")
    eb = {b["id"]: b for b in load("estate_buildings.json")}
    E = K["estate"]
    ms = E["milestones"]
    cap_k = E["shop_income_cap_gph"]          # D-8: tetto orario della Bottega, in multipli di gph(tier)

    def gph_ref(tier):
        return K["gph"]["base"] * K["gph"]["growth"] ** (tier - 1)

    prod_ids = [b for b in eb if eb[b]["type"] == "producer"]
    logs = {a["tier"]: ITEMS[a["outputs"][0]["item"]]["value"] for a in ACTIONS.values() if a["skill"] == "woodcutting"}

    def units(level, soci=0):
        if level <= 0:
            return 0.0
        return E["units_per_level"] * level * 2 ** sum(1 for m in ms if level >= m) * (1 + 0.02 * soci)

    def cost(bid, level):
        band = min(11, 1 + level // 10)
        return eb[bid]["cost"]["gold_base"] * E["cost_growth"] ** level * E["band_cost_growth"] ** (band - 1)

    def run(soci, hours_cap=300):
        levels = {b: 0 for b in prod_ids}
        levels["sawmill"] = 1
        cottage = 1
        gold = 500.0
        pp = 0.0
        t = 0.0
        step = 60.0
        marks = {}
        first = None
        while t < hours_cap * 3600:
            tier = min(10, 1 + int(t / 3600 // 12))
            u = sum(units(l, soci) for l in levels.values()) * step / 3600
            pp += u
            gold += min(u * logs[tier] * 0.8, cap_k * gph_ref(tier) * step / 3600)     # tetto orario della Bottega
            t += step
            bought = True
            while bought:
                bought = False
                used = sum(levels.values())
                if used >= 5 + 3 * cottage:
                    c = eb["cottage"]["cost"]["gold_base"] * E["cost_growth"] ** cottage * E["band_cost_growth"] ** (min(11, 1 + cottage // 10) - 1)
                    if gold >= c:
                        gold -= c
                        cottage += 1
                        bought = True
                    continue
                best = max(prod_ids, key=lambda b: (units(levels[b] + 1) - units(levels[b])) / cost(b, levels[b]))
                c = cost(best, levels[best])
                if gold >= c:
                    gold -= c
                    levels[best] += 1
                    bought = True
            for h in (1, 3, 6, 12, 24, 48, 96, 200):
                if h not in marks and t >= h * 3600:
                    marks[h] = (sum(levels.values()), sum(units(l, soci) for l in levels.values()), pp)
            if first is None and pp >= E["prestige_min_units"]:
                first = t / 3600
        return marks, first
    marks, first = run(0)
    ESTATE_FIRST_H = first
    P("| Ore di Tenuta | Livelli edifici | Unità/ora | Punti Prosperità | Soci ottenibili |")
    P("|---|---|---|---|---|")
    for h, (lv, pr, pp) in marks.items():
        P(f"| {h} | {lv} | {pr:,.0f} | {pp:,.0f} | {math.floor(E['soci_coeff'] * math.sqrt(pp / E['soci_divisor']))} |")
    P("")
    # T-P4: reddito in oro/ora della Tenuta contro l'oro/ora di riferimento del tier (docs/10: la Tenuta deve valere 0,3–0,8 × gph)
    P("Reddito della Tenuta (vendita di tutta la produzione all'80% del valore dei tronchi del tier) contro l'oro/ora di riferimento del tier:")
    P("")
    P("| Ore di Tenuta | Tier | Oro/ora Tenuta | gph di riferimento | Rapporto |")
    P("|---|---|---|---|---|")
    over = []
    for h, (lv, pr, pp) in marks.items():
        tier = min(10, 1 + int(h // 12))
        ref = gph_ref(tier)
        income = min(pr * logs[tier] * 0.8, cap_k * ref)
        P(f"| {h} | {tier} | {income:,.0f} | {ref:,.0f} | {income / ref:.2f}× |")
        if income / ref > 0.8 + 1e-9:
            over.append((h, income / ref))
    P("")
    goal("tenuta: reddito (<= 0,8 × gph)", not over,
         f"{len(over)} punti su {len(marks)} oltre 0,8× gph" + (" (" + ", ".join(f"{h} h: {r:.1f}×" for h, r in over) + ")" if over else ""))
    if first:
        s1 = math.floor(E["soci_coeff"] * math.sqrt(E["prestige_min_units"] / E["soci_divisor"]))
        P(f"Prima Rifondazione possibile dopo **{first:.1f} h** di Tenuta, con almeno {s1} Soci (+{2 * s1}% produzione).")
        P("")
        check("tenuta", 8 <= first <= 15, f"prima Rifondazione dopo {first:.1f} h di Tenuta (obiettivo 8–15 h)")
        marks2, first2 = run(s1)
        P(f"Seconda corsa con {s1} Soci: {E['prestige_min_units']:,.0f} punti raggiunti in {first2:.1f} h (la crescita a vita continua: i Soci si calcolano sul totale a vita).")
    else:
        P("Prima Rifondazione NON raggiunta: ritoccare i parametri.")
        check("tenuta", False, "prima Rifondazione non raggiunta entro 300 h")
    P("")


# --------------------------------------------------------------------------- STELLE
def star_pacing():
    P("## 8. Stelle di Mansione: tempo per stella (controllo anti-fuga)")
    P("")
    S = K["stars"]
    ech = S["echo"]

    def xp_mult(s):
        return 1 + S["xp_cap_pct"] * (1 - S["xp_decay"] ** s) / 100

    def haste(s):
        return S["haste_cap_pct"] * (1 - S["haste_decay"] ** s)

    def echo(L, rec):
        if rec <= L:
            return 1.0
        if L < 0.5 * rec:
            return ech["below_50pct_of_record"]
        if L < 0.9 * rec:
            return ech["below_90pct"]
        return ech["below_record"]

    acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting"]
    best_rate = {}
    for L in range(1, 100):
        best_rate[L] = max(a["xp"] / a["time_s"] * 3600 for a in acts if a["level_req"] <= L)

    def time_to_100(s, legacy=False):
        t = 0.0
        for L in range(1, 100):
            m = (1.1 ** s) if legacy else xp_mult(s)
            rate = best_rate[L] * m * (1 + haste(s) / 100) * (echo(L, 100) if s > 0 else 1.0)
            t += xp_to_next(L) / rate
        return t

    P("Taglialegna, profilo base (nessun altro bonus). Stella *n+1* = risalita 1→100 avendo già *n* stelle (con Eco). "
      f"XP: `{S['xp_cap_pct']} × (1 − {S['xp_decay']}^stelle)` (more) · velocità: `{S['haste_cap_pct']} × (1 − {S['haste_decay']}^stelle)`.")
    P("")
    P("| Stelle possedute | Bonus XP | Velocità | Ore per la stella successiva | Ore cumulative |")
    P("|---|---|---|---|---|")
    cum = 0.0
    times = {}
    for s in range(0, 201):
        times[s] = time_to_100(s)
    for s in range(0, 201):
        cum += times[s]
        if s in (0, 1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200):
            P(f"| {s} | +{(xp_mult(s) - 1) * 100:.0f}% | +{haste(s):.0f}% | {times[s]:.1f} | {cum:,.0f} |")
    P("")
    mn = min(times[s] for s in range(1, 201))
    legacy = {s: time_to_100(s, legacy=True) for s in (25, 50, 75, 100)}
    global STAR_MIN_H
    STAR_MIN_H = mn
    ok = mn >= S["min_hours_target"]
    check("stelle", ok, f"tempo minimo per stella {mn:.1f} h (obiettivo ≥ {S['min_hours_target']} h); la curva converge a un tempo costante, "
          "quindi le stelle crescono in modo lineare nel tempo (nessuna esplosione)")
    P(f"Confronto con una regola ingenua (+10% XP moltiplicativo per stella, senza limite): stella 26ª in {legacy[25]:.1f} h, "
      f"51ª in {legacy[50] * 60:.0f} min, 101ª in {legacy[100] * 3600:.0f} s → fuga verso stelle infinite. Per questo l'XP è asintotica.")
    P("")
    return ok


# --------------------------------------------------------------------------- PROFILI DI BONUS (T-P4)
PROFILES = [
    # nome, haste % (additiva), XP % (more, sull'XP di mansione)
    ("base (nessun bonus)", 0.0, 0.0),
    ("tipico (attrezzo + maestria 20: haste 45%)", 45.0, 0.0),
    ("budget docs/14 (haste 75%, XP +25%)", 75.0, 25.0),
    ("budget + Costellazioni al massimo (XP lv 14 more, Mani Svelte lv 20)", 75.0 + 20.0, ((1.25 * 1.02 ** 14) - 1) * 100),
]


def bonus_profiles():
    P("## 9. Profili di bonus: Livello 100 e tempo per Stella (T-P4, Taglialegna)")
    P("")
    P("Il profilo 'tipico' del §1 ha al massimo il 45% di haste; docs/14 prevede ~75% di haste e ~25% di XP. Qui lo stesso calcolo è ripetuto con "
      "4 profili. I bonus delle Stelle (§8) si sommano a quelli del profilo (haste: somma, XP: prodotto). L'Eco profonda delle Costellazioni "
      "non è modellata (non descritta in modo numerico nei dati).")
    P("")
    S = K["stars"]
    ech = S["echo"]
    acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting"]
    best_rate = {L: max(a["xp"] / a["time_s"] * 3600 for a in acts if a["level_req"] <= L) for L in range(1, 100)}

    def echo(L, rec=100):
        if rec <= L:
            return 1.0
        return ech["below_50pct_of_record"] if L < 0.5 * rec else (ech["below_90pct"] if L < 0.9 * rec else ech["below_record"])

    def t100(haste_pct, xp_pct, stars):
        xm = (1 + xp_pct / 100) * (1 + S["xp_cap_pct"] * (1 - S["xp_decay"] ** stars) / 100)
        hs = haste_pct + S["haste_cap_pct"] * (1 - S["haste_decay"] ** stars)
        return sum(xp_to_next(L) / (best_rate[L] * xm * (1 + hs / 100) * (echo(L) if stars > 0 else 1.0)) for L in range(1, 100))

    P("| Profilo | Lv 100 senza stelle | Stella 1 | Stella 2 | Stella 10 | Minimo (stelle 1–200) |")
    P("|---|---|---|---|---|---|")
    rows = []
    for name, hs, xp in PROFILES:
        t0 = t100(hs, xp, 0)
        ts = {s: t100(hs, xp, s) for s in range(1, 201)}
        mn = min(ts.values())
        rows.append((name, t0, mn))
        P(f"| {name} | {t0:.1f} h | {ts[1]:.1f} h | {ts[2]:.1f} h | {ts[10]:.1f} h | {mn:.1f} h |")
    P("")
    goal("Lv 100 senza bonus (obiettivo 40–50 h)", 40 <= rows[0][1] <= 50, f"profilo base {rows[0][1]:.1f} h")
    goal("Lv 100 con bonus tipici (obiettivo 25–35 h)", 25 <= rows[1][1] <= 35, f"profilo tipico {rows[1][1]:.1f} h")
    # D-8: il profilo «budget» (attrezzo, maestria, talenti, finiture, banchetto) è il giocatore equipaggiato al massimo: 18–25 h
    goal("Lv 100 con il budget di docs/14 (obiettivo 18–25 h)", 18 <= rows[2][1] <= 25, f"profilo budget {rows[2][1]:.1f} h")
    for name, t0, mn in rows:
        # D-8: 6 h per base/tipico/budget; per le Costellazioni al massimo il pavimento anti-fuga è 4 h
        floor_h = 4.0 if "Costellazioni" in name else S["min_hours_target"]
        goal(f"stella minima ≥ {floor_h:g} h, profilo «{name.split(' (')[0]}»", mn >= floor_h, f"minimo {mn:.1f} h")


# --------------------------------------------------------------------------- EVENTI STAGIONALI (T-11.3)
# Totali tipici di fine gioco senza Stelle (docs/14 §5, estremo alto dell'intervallo): l'evento si somma a questi.
DOCS14_TYPICAL = {"skill_xp_pct": 30.0, "skill_double_pct": 80.0, "crate_find_pct": 100.0}


def event_economy():
    """Economia degli eventi stagionali (docs/27 §2, docs/19): valuta/ora, Casse/ora, bonus temporaneo entro il budget di docs/14,
    solo cosmetici, recuperabilità, probabilità mostrate = usate."""
    try:
        evs = load("events.json")
        er = load("event_rules.json")[0]
    except FileNotFoundError:
        return
    ser = er.get("seasonal")
    if not evs or not ser:
        return
    lim = ser["limits"]
    P("## 12. Eventi stagionali (T-11.3): economia, bonus temporaneo, recupero")
    P("")
    P("Valuta evento: 1 ogni %d s di attività (Eco, fuori dalle date: 1 ogni %d s, senza bonus); Cassa evento = %d unità, solo cosmetici. "
      "Tetto dalle cadute: %d unità per edizione (e %d per l'Eco di ciascun evento). Il bonus temporaneo vale solo durante le date." % (
          ser["drop_every_s"], ser["echo_every_s"], ser["crate_cost"], ser["max_drops_per_occurrence"], ser["max_drops_echo"]))
    P("")
    cph = 3600.0 / ser["drop_every_s"] / ser["crate_cost"]
    check("eventi: Casse evento per ora di gioco", cph <= lim["max_crates_per_hour"],
          f"{cph:.2f} Casse/ora dalle sole cadute (limite {lim['max_crates_per_hour']}); Eco {cph * ser['drop_every_s'] / ser['echo_every_s']:.2f}/ora")
    # lv 100 con il budget di docs/14 + bonus XP evento (profilo D-8: haste 75%, XP +25%)
    acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting"]
    best_rate = {L: max(a["xp"] / a["time_s"] * 3600 for a in acts if a["level_req"] <= L) for L in range(1, 100)}

    def lv100_h(haste, xp):
        return sum(xp_to_next(L) / (best_rate[L] * (1 + xp / 100) * (1 + haste / 100)) for L in range(1, 100))

    P("| Evento | Bonus temporaneo | Budget docs/14 | Guadagno relativo | Valuta max (cadute + missioni) | Casse | Negozio completo |")
    P("|---|---|---|---|---|---|---|")
    for ev in evs:
        miss = sum(m["reward"] for m in ev["missions"])
        tot = ser["max_drops_per_occurrence"] + miss
        shop = sum(s["price"] for s in ev["shop"])
        mods = ev["modifiers"]
        desc = []
        worst = 0.0
        single_ok = True
        for m in mods:
            fam, _, scope = m["key"].partition(":")
            typ = DOCS14_TYPICAL.get(fam, 0.0)
            gain = ((1 + (typ + m["value"]) / 100) / (1 + typ / 100) - 1) * 100
            worst = max(worst, gain)
            if scope == "all" and m["value"] > lim["max_single_source_pct_all"]:
                single_ok = False
            desc.append(f"{m['key']} +{m['value']:g}%")
            if fam == "skill_xp_pct":
                h_b, h_e = lv100_h(75.0, 25.0), lv100_h(75.0, 25.0 + m["value"])
                check(f"eventi: {ev['id']} Lv 100 col budget + bonus XP", h_e >= 18.0,
                      f"{h_b:.1f} h → {h_e:.1f} h con l'evento (minimo del budget D-8: 18 h)")
        check(f"eventi: {ev['id']} bonus entro il budget di docs/14", worst <= lim["max_relative_gain_pct"] and single_ok,
              f"{', '.join(desc)}: guadagno relativo sul tipico di fine gioco {worst:.1f}% (limite {lim['max_relative_gain_pct']}%; "
              f"una fonte sola ≤ {lim['max_single_source_pct_all']}% su «all»)")
        check(f"eventi: {ev['id']} Casse per edizione", tot / ser["crate_cost"] <= lim["max_crates_per_occurrence"],
              f"{tot} unità = {tot / ser['crate_cost']:.1f} Casse (limite {lim['max_crates_per_occurrence']})")
        check(f"eventi: {ev['id']} recuperabile", shop <= tot and shop <= ser["max_drops_echo"] + miss,
              f"Negozio completo {shop} unità ≤ {tot} in una edizione e ≤ {ser['max_drops_echo'] + miss} con l'Eco (anche senza fortuna)")
        crate = ITEMS[ev["crate"]]["crate"]
        cos_only = all(ITEMS[s]["category"] == "cosmetic" for s in crate["skins"])
        pets = {p["id"]: p for p in load("pets.json")}
        no_power = all(not pets[p].get("modifiers") for p in crate["relic_pool"])
        check(f"eventi: {ev['id']} Cassa solo cosmetica, nessun potere", cos_only and no_power and crate.get("key") is None,
              f"{len(crate['skins'])} cosmetici + {len(crate['relic_pool'])} famiglio senza bonus; si apre solo con la valuta evento")
        nominal = sum(crate["odds"].values())
        check(f"eventi: {ev['id']} probabilità della Cassa", abs(nominal - 100.0) < 1e-9,
              f"le probabilità mostrate sommano {nominal:g}% (la Cassa evento non ha pity: mostrate = usate)")
        P(f"| {ev['name']['it']} | {', '.join(desc)} | tipico {', '.join(str(int(DOCS14_TYPICAL.get(m['key'].partition(':')[0], 0))) + '%' for m in mods)} | "
          f"+{worst:.1f}% | {tot} | {tot / ser['crate_cost']:.1f} | {shop} |")
    P("")


# --------------------------------------------------------------------------- ERE
def era_pacing():
    P("## 9. Ere del Mondo: ranghi necessari e ore per Era (controllo del ciclo infinito)")
    P("")
    er = load("era_rules.json")[0]
    mult_m = er["monster_stat_mult"]
    rank_m = er["item_rank"]["stat_mult_per_rank"]
    cap_per_era = er["item_rank"]["cap_per_era"]
    zone = ZONES[-1]
    normals = [MON[mid] for mid in zone["monsters"] if MON[mid]["type"] == "normal"]
    elite = [MON[mid] for mid in zone["monsters"] if MON[mid]["type"] == "elite"][0]
    dung = [d for d in load("dungeons.json") if d["zone"] == zone["id"]][0]
    dboss = MON[dung["boss"]]
    classes = ("warrior", "ranger", "arcanist")
    n_items = len(gear_set("warrior", 11)[0])
    resp = K["combat"]["respawn_s"]

    def ok_at(N, r):
        em = mult_m ** (N - 1)
        for cls in classes:
            h = hero_stats(cls, 100, 11, rank_mult=rank_m ** r)
            rows = [fight(h, m, em) for m in normals]
            if statistics.mean(x["ttk"] for x in rows) > 16 or statistics.mean(x["dmg_per_kill"] / h["hp"] for x in rows) > 0.35:
                return False
        return True

    def r_min(N):
        r = 0
        while not ok_at(N, r):
            r += 1
            if r > 4000:
                return None
        return r

    cf = er["item_rank"]["cost_formula"]

    def fx(expr, **v):
        return eval(expr, {"ceil": math.ceil, "floor": math.floor}, v)

    def ess_cost(a, b):
        return n_items * sum(fx(cf["era_essence"], rango=r) for r in range(a + 1, b + 1))

    def gold_cost(a, b):
        return n_items * sum(fx(cf["gold"], tier=11, rango=r) for r in range(a + 1, b + 1))

    def qty(N):
        return fx(er["era_essence"]["qty_formula"], era=N)

    def income(N, r):
        em = mult_m ** (N - 1)
        rew = 1 + er["reward_add_per_era"] * (N - 1)
        h = hero_stats("warrior", 100, 11, rank_mult=rank_m ** r)
        fe = fight(h, elite, em)
        kills_h = 3600 / (fe["ttk"] + resp)
        e_elite = kills_h * er["era_essence"]["drop"]["elite"] * qty(N)
        g_elite = kills_h * sum(elite["gold"]) / 2 * rew
        clear = sum(fight(h, MON[w["monster"]], em)["ttk"] + resp for w in dung["waves"]) + fight(h, dboss, em)["ttk"] + 10
        clears_h = 3600 / clear
        e_d = clears_h * er["era_essence"]["drop"]["dungeon_boss"] * qty(N)
        g_d = clears_h * (dung["completion_reward"]["gold"] + sum(sum(MON[w["monster"]]["gold"]) / 2 for w in dung["waves"])) * rew
        return max(e_elite, e_d), max(g_elite, g_d)

    P(f"Ipotesi: eroe Lv 100, equipaggiamento T11 Normale ({n_items} pezzi) col Rango *r* (×{rank_m}^r su {', '.join(sorted(RANK_STATS))}); "
      "un'Era è \"giocabile\" quando contro i mostri normali dell'ultima zona TTK ≤ 16 s e danno/uccisione ≤ 35% della vita (tutte e 3 le classi). "
      "Entrate: il migliore tra farm dell'élite e dungeon dell'ultima zona (tutta l'Essenza e l'oro vanno nei ranghi). Le incursioni (ogni 4 h) "
      "e le altre fonti (Stelle dell'Eroe, Costellazioni, qualità superiore) sono un margine in più, non conteggiato.")
    P("")
    P("| Era | Rango minimo | Cap rango | Essenza per salire | Oro per salire | Essenza/h | Oro/h | Ore (Essenza) | Ore (oro) | Ore per l'Era successiva |")
    P("|---|---|---|---|---|---|---|---|---|---|")
    prev = r_min(1)
    rows = []
    worst = 0
    for N in range(2, 41):
        r = r_min(N)
        if r is None:
            P(f"| {N} | impossibile | | | | | | | | |")
            break
        e_need, g_need = ess_cost(prev, r), gold_cost(prev, r)
        e_h, g_h = income(N - 1, prev)
        he, hg = (e_need / e_h if e_h > 0 else float("inf")), g_need / g_h
        hrs = max(he if N > 2 else 0, hg)
        rows.append((N, r, hrs, r <= cap_per_era * (N - 1)))
        if N in (2, 3, 4, 5, 6, 8, 10, 15, 20, 25, 30, 40):
            P(f"| {N} | {r} | {cap_per_era * (N - 1)} | {e_need:,.0f} | {g_need:,.0f} | {e_h:,.0f} | {g_h:,.0f} | "
              f"{('—' if N == 2 else f'{he:.1f}')} | {hg:.1f} | **{hrs:.1f}** |")
        worst = max(worst, hrs)
        prev = r
    P("")
    global ERA_WORST_H
    ERA_WORST_H = worst
    over_cap = [x for x in rows if not x[3]]
    late = [x[2] for x in rows if x[0] >= 10]
    ok = not over_cap and worst <= 60 and (max(late) / max(1e-9, min(late)) < 3 if late else True)
    P("Nota: per entrare nell'Era N servono i ranghi indicati, pagati con le risorse raccolte nell'Era N−1 (l'Essenza si accumula già "
      "nell'Era I ma i ranghi si applicano dall'Era II; la scorta iniziale non è conteggiata, quindi le prime Ere sono un po' più rapide del calcolo).")
    P("")
    check("ere", ok, f"rango minimo sempre ≤ cap ({'sì' if not over_cap else 'NO: ' + ', '.join(str(x[0]) for x in over_cap)}); "
          f"ore per Era massime {worst:.1f} (obiettivo ≤ 60 h); dall'Era 10 il tempo per Era resta entro un fattore 3 (ciclo stabile)")
    # --- G03 (GAP-MECCANICHE): il Rango si compra davvero (PrestigeSystem.do_rank_up) con i NUMERI di constants.eras.rank_cost
    # (Formulas.rank_essence_cost / rank_gold_cost). Controlli: numeri = formule testuali, Ranghi solo dall'Era II, e l'anello
    # "più Rango -> uccisioni più rapide -> più Essenza -> più Rango" è chiuso dal tetto 12·N (oltre non si compra nulla):
    # con le entrate al tetto (limite superiore) l'Essenza in più non serve a niente finché non si batte il Custode.
    rc = K["eras"]["rank_cost"]

    def ess_num(r):
        return math.ceil(rc["essence_base"] + rc["essence_per_rank"] * r - 1e-9)

    def gold_num(t, r):
        return round(rc["gold_per_tier"] * t * (1 + r / rc["gold_rank_div"]))
    same = all(ess_num(r) == fx(cf["era_essence"], rango=r) and gold_num(t, r) == round(fx(cf["gold"], tier=t, rango=r))
               for r in range(1, 300) for t in range(1, 12))
    P("**Rango acquistabile (G03).** Costo per salire al rango *r*: Essenza `ceil(%g + %g·r)`, oro `%g·tier·(1 + r/%g)`; dall'Era %d; tetto %d·Era. "
      "Anello Rango → Essenza chiuso dal tetto: ore per arrivare al tetto dell'Era N partendo dal rango minimo, con le entrate che si avrebbero "
      "GIÀ al tetto (limite superiore delle entrate):" % (rc["essence_base"], rc["essence_per_rank"], rc["gold_per_tier"], rc["gold_rank_div"],
                                                          K["eras"]["rank_min_era"], cap_per_era))
    P("")
    P("| Era | Rango minimo | Tetto | Essenza/h al minimo | Essenza/h al tetto | Ore minimo → tetto (Essenza) |")
    P("|---|---|---|---|---|---|")
    loop_ok = True
    for N in (3, 5, 10, 20):
        rmin = r_min(N)
        cap = cap_per_era * N
        if rmin is None or rmin > cap:
            loop_ok = False
            continue
        e_lo, e_hi = income(N, rmin)[0], income(N, cap)[0]
        need = n_items * sum(ess_num(r) for r in range(rmin + 1, cap + 1))
        h_cap = need / e_hi if e_hi > 0 else float("inf")
        P(f"| {N} | {rmin} | {cap} | {e_lo:,.0f} | {e_hi:,.0f} | {h_cap:,.1f} |")
        loop_ok = loop_ok and math.isfinite(h_cap) and h_cap > 0
    P("")
    check("rango (pozzo d'Essenza)", same and K["eras"]["rank_min_era"] >= 2 and loop_ok,
          f"numeri di constants.eras.rank_cost = formule di era_rules ({'sì' if same else 'NO'}); Ranghi dall'Era {K['eras']['rank_min_era']}; "
          "l'anello Rango → Essenza si ferma al tetto 12·N in un tempo finito (oltre il tetto l'Essenza non compra nulla): le Ere oltre "
          "la seconda e la terza sono progredibili (tabella sopra e §9) e nessuno strato accelera sé stesso senza limite")
    return ok and same and loop_ok


# --------------------------------------------------------------------------- STRATI DI PRESTIGIO (agente PRESTIGE)
ACCELERATORS = ("skill_xp_pct", "skill_haste_pct", "skill_double_pct", "echo_mult_pct")   # famiglie che accorciano la risalita a 100
LAYER_CURRENCY = ("stardust_gain_pct", "soci_gain_pct")   # valute degli strati di prestigio: un nodo infinito sarebbe un anello (regola 9)


def prestige_layers():
    """Rito, Polvere, Costellazioni di base e Rifondazione: ogni strato ha un controllo di stabilità (docs/13 §1, regola 9)."""
    nodes = load("constellations.json")
    if not nodes or "prestige" not in K:
        return
    PR = K["prestige"]
    S = K["stars"]
    ech = S["echo"]
    P("## 10. Strati di prestigio: Rito, Polvere, Costellazioni, Rifondazione (controlli di stabilità)")
    P("")
    acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting"]
    best_rate = {L: max(a["xp"] / a["time_s"] * 3600 for a in acts if a["level_req"] <= L) for L in range(1, 100)}

    def echo(L, rec, em=1.0):
        if rec <= L:
            return 1.0
        e = ech["below_50pct_of_record"] if L < 0.5 * rec else (ech["below_90pct"] if L < 0.9 * rec else ech["below_record"])
        return e * em

    def t_to(level, haste_pct, xp_pct):
        return sum(xp_to_next(L) / (best_rate[L] * (1 + xp_pct / 100) * (1 + haste_pct / 100)) for L in range(1, level))

    # --- 10.1 Rito: mini-prestigio precoce (audit 03 #2): ora 5-20, una volta per mansione
    rl = PR["rite_level"]
    P(f"**Rito** (Stella di prova, una volta per mansione, dal livello {rl}): ore di gioco di Taglialegna per arrivarci.")
    P("")
    P("| Profilo | Ore al livello del Rito | Ore al livello 100 |")
    P("|---|---|---|")
    ts = []
    for name, hs, xp in PROFILES[:3]:
        t_r, t_100 = t_to(rl, hs, xp), t_to(100, hs, xp)
        ts.append(t_r)
        P(f"| {name} | {t_r:.1f} h | {t_100:.1f} h |")
    P("")
    # FIX-MEDIO (R4 §1): Rito a livello 50 = primo reset nelle prime ore di una mansione (prima 75, ora 5-20: chi seguiva la
    # storia non lo vedeva mai). Ore di sola mansione (tasso migliore), non ore di partita.
    goal("Rito tra ora 1 e 6 di mansione (R4 §1)", all(1.0 <= t <= 6.0 for t in ts), f"ore al livello {rl}: " + ", ".join(f"{t:.1f}" for t in ts))
    n_skills = len(load("skill_prestige.json"))
    check("rito", True, f"il Rito vale una sola Stella per mansione: al massimo {n_skills} Stelle extra in tutta la partita, nessun anello "
          "(dopo il Rito la risalita 1→100 è quella del §8 con 1 Stella)")

    # --- 10.2 Polvere -> Costellazioni acceleratrici: ciclo chiuso con acquisto goloso (xp, poi velocità)
    nd = {n["id"]: n for n in nodes}
    chain = [nd["c_vi_xp"], nd["c_vi_haste"]]
    cost = lambda n, lv: math.ceil(n["cost_base"] * n["cost_growth"] ** lv - 1e-9)
    total_cost = sum(cost(n, lv) for n in chain for lv in range(n["max_level"]))
    goals_once = sum(g["stardust"] for g in PR["goals"] if g["type"] in ("rites_done", "stars_total", "constellation_levels"))
    base_h, base_xp = 75.0, 25.0      # profilo budget docs/14

    def star_hours(stars, xp_lv, hs_lv):
        xm = (1 + base_xp / 100) * 1.02 ** xp_lv * (1 + S["xp_cap_pct"] * (1 - S["xp_decay"] ** stars) / 100)
        hs = base_h + hs_lv + S["haste_cap_pct"] * (1 - S["haste_decay"] ** stars)
        return sum(xp_to_next(L) / (best_rate[L] * xm * (1 + hs / 100) * echo(L, 100)) for L in range(1, 100))

    dust = float(goals_once)
    lv = {"c_vi_xp": 0, "c_vi_haste": 0}
    rows, mins, cum_h, full_at = [], [], 0.0, None
    for n in range(1, 301):
        dust += 10 + 2 * (n - 1)
        for node in chain:
            while lv[node["id"]] < node["max_level"] and dust >= cost(node, lv[node["id"]]):
                dust -= cost(node, lv[node["id"]])
                lv[node["id"]] += 1
            if lv[node["id"]] < node["max_level"]:
                break
        t = star_hours(n, lv["c_vi_xp"], lv["c_vi_haste"])
        mins.append(t)
        cum_h += t
        if full_at is None and all(lv[x["id"]] >= x["max_level"] for x in chain):
            full_at = n
        if n in (1, 5, 10, 20, 40, 60, 80, 100, 150, 300):
            rows.append((n, lv["c_vi_xp"], lv["c_vi_haste"], t, cum_h))
    P(f"**Polvere e Costellazioni acceleratrici.** Una sola mansione (Taglialegna, profilo budget) è l'unica fonte di Polvere (10 + 2(n−1) per Stella, più {goals_once} "
      f"dei Grandi Obiettivi); si compra a caso goloso Passo Esperto (XP, max 14) poi Mani Svelte (velocità, max 20). Costo per averli al massimo: **{total_cost:,}** Polvere.")
    P("")
    P("| Stelle | Passo Esperto | Mani Svelte | Ore per la Stella successiva | Ore cumulative |")
    P("|---|---|---|---|---|")
    for n, a, b, t, c in rows:
        P(f"| {n} | {a} | {b} | {t:.1f} | {c:,.0f} |")
    P("")
    floor_h = 4.0
    global STAR_CONST_MIN_H
    STAR_CONST_MIN_H = min(mins)
    check("polvere/costellazioni", min(mins) >= floor_h and abs(mins[-1] - mins[-50]) / mins[-1] < 0.01,
          f"con la Polvere reinvestita il tempo minimo per Stella è {min(mins):.1f} h (pavimento {floor_h:g} h); acceleratori al massimo dopo "
          f"{full_at} Stelle; il tempo converge ({mins[-50]:.2f} h alla 251ª, {mins[-1]:.2f} h alla 300ª)")
    # --- 10.2b Imprese del Compendio: pagano Polvere fin dall'inizio (GUILD-2) e anticipano gli acceleratori.
    # Limite superiore: TUTTA la Polvere delle imprese disponibile prima della prima Stella (i doppioni dei famigli ★
    # delle Casse, 8 Polvere ogni ~700 aperture, sono trascurabili). Il ciclo deve restare sopra il pavimento e
    # convergere allo stesso valore di prima.
    ach = load("achievements.json") or []
    ach_dust = sum(int((a.get("reward") or {}).get("stardust", 0)) for a in ach)

    def run_cycle(dust0):
        d, lv2, out = float(dust0), {"c_vi_xp": 0, "c_vi_haste": 0}, []
        for n in range(1, 301):
            d += 10 + 2 * (n - 1)
            for node in chain:
                while lv2[node["id"]] < node["max_level"] and d >= cost(node, lv2[node["id"]]):
                    d -= cost(node, lv2[node["id"]])
                    lv2[node["id"]] += 1
                if lv2[node["id"]] < node["max_level"]:
                    break
            out.append(star_hours(n, lv2["c_vi_xp"], lv2["c_vi_haste"]))
        return out
    with_ach = run_cycle(goals_once + ach_dust)
    first10 = sum(mins[:10])
    first10_a = sum(with_ach[:10])
    P(f"**Imprese del Compendio** ({len(ach)} imprese, {ach_dust} Polvere in tutto, pagate fin dall'inizio): se fossero TUTTE disponibili "
      f"prima della prima Stella, le prime 10 Stelle richiederebbero {first10_a:,.0f} h invece di {first10:,.0f} h "
      f"(−{(1 - first10_a / first10) * 100:.1f}%); minimo per Stella {min(with_ach):.1f} h, a regime {with_ach[-1]:.2f} h.")
    P("")
    check("imprese/polvere iniziale", min(with_ach) >= floor_h and abs(with_ach[-1] - mins[-1]) / mins[-1] < 0.01
          and first10_a >= 0.85 * first10,
          f"Polvere delle imprese ({ach_dust}) tutta in anticipo: minimo {min(with_ach):.1f} h (pavimento {floor_h:g} h), a regime "
          f"{with_ach[-1]:.2f} h come senza imprese ({mins[-1]:.2f} h), prime 10 Stelle −{(1 - first10_a / first10) * 100:.1f}% (≤ 15%): "
          "una spinta una tantum, nessun anello")
    # audit 84 (regola 9): anche la valuta dello strato (Polvere, Soci) non può avere un nodo infinito
    unl = [n["id"] for n in nodes if n["max_level"] is None and n["modifier_per_level"]["key"].split(":")[0] in ACCELERATORS + LAYER_CURRENCY]
    infinite = sorted({n["modifier_per_level"]["key"].split(":")[0] for n in nodes if n["max_level"] is None})
    check("costellazioni (nodi infiniti)", not unl,
          "nessun nodo senza livello massimo accelera le Stelle o moltiplica la valuta dello strato (Polvere, Soci)" + (f" — VIOLATI: {', '.join(unl)}" if unl else
          f" (nodi infiniti rimasti: {', '.join(infinite)}: bonus a costo esponenziale, potere logaritmico)"))
    # Eco profonda: ×(1+10%)^10 sull'Eco manderebbe la Stella sotto il pavimento -> resta dormiente nel codice (PrestigeSystem.DORMANT_FAMILIES)
    ECHO_NOMINAL_LEVELS = 10      # livelli nominali di Eco Profonda (nel gioco max_level 0 = non acquistabile finché il nodo è dormiente)
    em = 1.1 ** ECHO_NOMINAL_LEVELS
    xp_max = ((1 + base_xp / 100) * 1.02 ** 14 - 1) * 100

    def t_echo(stars):
        xm = (1 + xp_max / 100) * (1 + S["xp_cap_pct"] * (1 - S["xp_decay"] ** stars) / 100)
        hs = base_h + 20 + S["haste_cap_pct"] * (1 - S["haste_decay"] ** stars)
        return sum(xp_to_next(L) / (best_rate[L] * xm * (1 + hs / 100) * echo(L, 100, em)) for L in range(1, 100))
    t_e = min(t_echo(s_) for s_ in range(1, 201))
    gd = os.path.join(ROOT, "game", "src", "systems", "PrestigeSystem.gd")
    dormant = False
    if os.path.exists(gd):
        src = open(gd, encoding="utf-8").read()
        dormant = "DORMANT_FAMILIES" in src and '"echo_mult_pct"' in src.split("DORMANT_FAMILIES")[1].split("]")[0]
    echo_off = nd["c_vi_echo"]["max_level"] == 0      # non acquistabile: la Polvere non si spende per nulla
    check("eco profonda", t_e >= floor_h or (dormant and echo_off),
          f"applicata per intero l'Eco profonda porterebbe la Stella a {t_e:.1f} h (pavimento {floor_h:g} h): il nodo resta dormiente in "
          f"PrestigeSystem.DORMANT_FAMILIES ({'sì' if dormant else 'NO'}) e non è acquistabile (max_level 0: {'sì' if echo_off else 'NO'}) finché non viene ritarato")

    # --- 10.3 Rifondazione: crescita dei Soci con la produzione a vita (limite superiore: gli edifici non si azzerano)
    if ESTATE_FIRST_H:
        E = K["estate"]
        r = E["prestige_min_units"] / ESTATE_FIRST_H     # unità/ora medie osservate nella prima corsa
        P(f"**Rifondazione.** Limite superiore della crescita: produzione media della prima corsa ({r:,.0f} unità/h) senza mai perdere gli edifici, "
          f"ogni Socio +{E['socio_bonus_pct']:g}% produzione, Soci = ⌊{E['soci_coeff']:g}·√(punti/{E['soci_divisor']:,.0f})⌋. Ore per raggiungere N Soci totali:")
        P("")
        est = nd["c_me_estate"]
        est_mult = (1 + est["modifier_per_level"]["value"] / 100) ** est["max_level"]      # Imprenditore (more) al massimo
        P("| Soci | senza Rete di Soci | con Rete di Soci al massimo (×2 Soci) | con Imprenditore al massimo (×%.2f produzione) |" % est_mult)
        P("|---|---|---|---|")

        def hours_to(target, gain_mult, prod_mult=1.0):
            u, t, dt = 0.0, 0.0, 0.25
            while t < 100000:
                soci = math.floor(E["soci_coeff"] * math.sqrt(u / E["soci_divisor"])) * gain_mult
                if soci >= target:
                    return t
                u += r * prod_mult * (1 + E["socio_bonus_pct"] / 100 * soci) * dt
                t += dt
            return float("inf")
        res = {n_: (hours_to(n_, 1), hours_to(n_, 2), hours_to(n_, 1, est_mult)) for n_ in (50, 100, 200, 400)}
        for n_, (a, b, c_) in res.items():
            P(f"| {n_} | {a:,.0f} h | {b:,.0f} h | {c_:,.0f} h |")
        P("")
        ratio = res[400][0] / res[200][0]
        check("rifondazione", 1.5 <= ratio <= 3.0 and all(math.isfinite(v) for ab in res.values() for v in ab),
              f"i Soci crescono in modo lineare nel tempo (400 Soci / 200 Soci = ×{ratio:.2f} di ore; un anello darebbe ×1): nessuna fuga né muro")


# --------------------------------------------------------------------------- ERE E PROVE (agente ERE-PROVE, audit 43)
def era_trial_layers():
    """Ere (Polvere del Custode) e Prove del Custode: ogni strato ha un controllo di stabilita' (docs/13 §1, regola 9)."""
    nodes = {n["id"]: n for n in load("constellations.json")}
    trials = load("trials.json")
    if not nodes or not trials or "prestige" not in K:
        return
    er = ERA
    rm = er["item_rank"]["stat_mult_per_rank"]
    mm = er["monster_stat_mult"]
    per_era_dust = lambda n: int(eval(er["stardust_per_warden_kill"], {}, {"era": n}))        # formula dei dati ("5 * era")
    repeat_pct = er.get("stardust_repeat_pct")
    ranks_per_era = math.log(mm) / math.log(rm)

    def ranks_needed(n):
        return 0 if n <= 1 else math.ceil((n - 1) * ranks_per_era - 1e-9)

    P("## 11. Ere (Polvere del Custode) e Prove del Custode: controlli di stabilita'")
    P("")
    # --- 11.1 Ere: la Polvere del Custode non deve fare da anello (piu' danno -> piu' Custodi -> piu' Polvere -> piu' danno)
    P(f"**Ere.** Il Custode paga `{er['stardust_per_warden_kill']}` Polvere SOLO alla prima uccisione di ogni Era (le successive: {repeat_pct}%). "
      "Quindi la Polvere totale dalle Ere dipende dall'Era raggiunta, non dal tempo passato a uccidere il Custode. "
      "Peggior caso per l'accelerazione: tutta questa Polvere comprata nei tre nodi infiniti di combattimento (danno, vita, difesa), "
      f"e il potere ottenuto convertito in Ranghi equivalenti (1 Rango = x{rm} su danno e difese) e confrontato con i Ranghi che l'Era richiede.")
    P("")
    P("| Era raggiunta | Polvere dai Custodi | Livelli (danno/vita/difesa) | Ranghi equivalenti | Ranghi richiesti | Quota |")
    P("|---|---|---|---|---|---|")
    chain = [nodes["c_gu_dmg"], nodes["c_gu_hp"], nodes["c_gu_def"]]

    def buy(dust):
        lv = {n["id"]: 0 for n in chain}

        def cost(n):
            return math.ceil(n["cost_base"] * n["cost_growth"] ** lv[n["id"]] - 1e-9)
        while True:
            n = min(chain, key=cost)
            c = cost(n)
            if c > dust:
                return lv
            dust -= c
            lv[n["id"]] += 1

    def rank_equiv(lv):
        m = 1.0
        for n in chain:
            v = n["modifier_per_level"]["value"]
            m *= (1 + v / 100) ** lv[n["id"]] if n["modifier_per_level"]["mode"] == "more" else (1 + v * lv[n["id"]] / 100)
        return math.log(m) / math.log(rm)

    shares = {}
    for N in (2, 3, 5, 10, 20, 50, 100, 200, 500):
        dust = sum(per_era_dust(e) for e in range(1, N))         # per raggiungere l'Era N: i Custodi delle Ere 1..N-1
        lv = buy(dust)
        re_, rn = rank_equiv(lv), ranks_needed(N)
        shares[N] = re_ / rn
        P(f"| {N} | {dust:,} | {lv['c_gu_dmg']}/{lv['c_gu_hp']}/{lv['c_gu_def']} | {re_:.1f} | {rn} | {re_ / rn:.0%} |")
    P("")
    late = [shares[n] for n in (20, 50, 100, 200, 500)]
    monotone = all(late[i] >= late[i + 1] for i in range(len(late) - 1))
    check("ere: Polvere del Custode", repeat_pct == 0 and max(shares.values()) <= 0.5 and monotone,
          f"ripetere il Custode paga {repeat_pct}% (obiettivo 0: niente anello); la Polvere dei Custodi, spesa tutta in potere, vale al massimo "
          f"{max(shares.values()):.0%} dei Ranghi richiesti (obiettivo ≤ 50%) e dall'Era 20 la quota scende ({late[0]:.0%} → {late[-1]:.1%}): "
          "crescita logaritmica contro Ranghi lineari, il ciclo per Era resta quello del §9")
    # --- 11.2 Ere: costanti coerenti con il design
    check("ere: moltiplicatori", abs(mm - 1.35) < 1e-9 and abs(er["reward_add_per_era"] - 0.3) < 1e-9 and er["infinite"] and er["selectable"],
          f"mostri ×{mm}^(N-1), ricompense ×(1+{er['reward_add_per_era']}(N-1)), infinite e selezionabili; "
          f"Ranghi per Era ≈ {ranks_per_era:.2f} (il giocatore sale di Era a ogni ~25 h, §9)")
    # --- 11.3 Prove: bonus permanenti finiti, Polvere una volta sola, niente di infinito
    keys, dust_tot, n_rewards, nonadd = defaultdict(float), 0, 0, 0
    for t in trials:
        for tier in t["tiers"]:
            dust_tot += tier["reward"]["stardust"]
            for m in tier["reward"]["modifiers"]:
                keys[m["key"].split(":")[0]] += m["value"]
                n_rewards += 1
                nonadd += m["mode"] != "add"
    combat_keys = {"combat_acc_pct", "combat_haste_pct", "combat_dmg_pct", "combat_hp_pct", "combat_defense_pct", "combat_eva_pct"}
    m_all = 1.0
    for k, v in keys.items():
        if k in combat_keys:
            m_all *= 1 + v / 100
    ranks_trials = math.log(m_all) / math.log(rm)
    n_tiers = sum(len(t["tiers"]) for t in trials)
    era_ranks = math.ceil(ranks_per_era)
    P(f"**Prove.** {len(trials)} Prove × 5 gradi = {n_tiers} premi, ciascuno UNA volta (grado superato = premio riscosso): {n_rewards} bonus "
      f"(+{max(keys.values()):g} al massimo per famiglia), {dust_tot} Polvere in tutto. Tutte le famiglie di combattimento al massimo valgono "
      f"×{m_all:.3f} = {ranks_trials:.1f} Ranghi equivalenti, una sola volta e senza dipendere dall'Era (l'Era richiede ≈ {era_ranks} Ranghi OGNI volta).")
    P("")
    check("prove: bonus finiti", nonadd == 0 and n_rewards == n_tiers and max(keys.values()) <= 5 + 1e-9 and ranks_trials <= era_ranks,
          f"ogni grado ha un solo bonus 'add' (+1) e si riscuote una volta: al massimo +{max(keys.values()):g} per famiglia; "
          f"tutte insieme valgono {ranks_trials:.1f} Ranghi, meno di un'Era (≈ {era_ranks}): niente anello, niente muro")
    check("prove: Polvere finita", dust_tot <= 1000 and dust_tot == 45 * len(trials),
          f"{dust_tot} Polvere in tutto, una volta (≈ {dust_tot / 10:.0f} Stelle di Mansione); un grado non si ripete, quindi la Polvere delle Prove non si coltiva")
    # --- 11.4 Prove: ogni grado e' superabile (obiettivo di design, non blocca): hero al livello del boss, equipaggiamento del tier
    P("**Superabilita' dei gradi** (giocatore al livello del boss di zona, equipaggiamento Normale; vale se ce la fanno almeno 2 classi su 3): "
      "guerriero mostrato; TTK in secondi / cibo necessario (cura del cibo del tier). Digiuno: danno netto in % della vita, senza cibo.")
    P("")
    P("| Prova | Grado I | II | III | IV | V |")
    P("|---|---|---|---|---|---|")
    bad = []
    zone_by_order = {z["order"]: z for z in ZONES}
    for t in trials:
        cells = []
        for tier in t["tiers"]:
            z = zone_by_order[tier["zone_index"]]
            rules = dict(t["rules"], **tier.get("rules", {}))
            if rules.get("dungeon"):
                dg = [d for d in load("dungeons.json") if d["zone"] == z["id"]][0]
                boss = dict(MON[dg["boss"]])
                boss["stats"] = dict(boss["stats"], hp=boss["stats"]["hp"] * rules.get("monster_hp_mult", 1.0))
            else:
                boss = [MON[m] for m in z["monsters"] if MON[m]["type"] == "boss"][0]
            L = min(100, boss["level"])
            tt = min(11, tier_of(L))
            gt = max(1, int(eval(rules["max_gear_tier"], {}, {"tier_zona": z["tier"]}))) if "max_gear_tier" in rules else tt
            heal = ITEMS[f"food_{FISH[tt - 1]}"]["food"]["heal"]
            ok_cls, shown = 0, ""
            for cls in ("warrior", "ranger", "arcanist"):
                h = hero_stats(cls, L, gt, quality_mult=1.0)
                if rules.get("no_armor"):
                    h["arm"] = h["ward"] = 0.0
                if "hp_mult" in rules:
                    h["hp"] *= rules["hp_mult"]
                f = fight(h, boss)
                ttk = f["ttk"] * (ABILITY_FACTOR if rules.get("no_abilities") else 1.0)
                net = f["net_dps_taken"]
                if rules.get("forced_disadvantage"):
                    tr_ = K["combat"]["triangle"]
                    ttk = ttk * tri(h["style"], boss["style"]) / tr_["disadvantage"]
                    net = max(0.0, f["m_dps"] * tr_["advantage"] / max(1e-9, tri(boss["style"], h["style"])) - f["regen"])
                dmg = net * ttk
                if rules.get("no_food") or "max_food" in rules:
                    need = max(0.0, dmg - 0.9 * h["hp"]) / heal          # porzioni che servirebbero oltre alla vita (90%)
                    ok = need <= rules.get("max_food", 0) and ttk <= 180
                    cell = f"{dmg / h['hp']:.0%}" + (f" ({need:.0f}/{rules['max_food']})" if "max_food" in rules else "")
                elif "time_limit_s" in rules:
                    ok = ttk <= rules["time_limit_s"] and dmg / heal <= 30
                    cell = f"{ttk:.0f} s"
                else:
                    ok = ttk <= 240 and dmg / heal <= 60
                    cell = f"{ttk:.0f} s / {dmg / heal:.0f}"
                ok_cls += ok
                if cls == "warrior":
                    shown = cell
            good = ok_cls >= 2
            cells.append(shown + ("" if good else " ✗"))
            if not good:
                bad.append(f"{t['id']} grado {tier['tier']}")
        P(f"| {t['name']['it']} | " + " | ".join(cells) + " |")
    P("")
    goal("prove: superabili", not bad, "ogni grado e' superabile da almeno 2 classi su 3 (guerriero mostrato)" + (f" — NON superabili: {', '.join(bad)}" if bad else ""))


# --------------------------------------------------------------------------- MODALITA' DI GIOCO (docs/05 §7, agente MODALITA')
def mode_report():
    """Autarchico ed Estremo: la prima Stella / il Rito / la Rifondazione restano raggiungibili in tempi ragionevoli,
    e la morte Estrema costa tempo, non il gioco (docs/13 §1, regola 9: ogni strato ha un controllo)."""
    MRrows = load("mode_rules.json")
    if not MRrows or "prestige" not in K:
        return
    MR = MRrows[0]["modes"]
    PR = K["prestige"]
    S = K["stars"]
    ech = S["echo"]
    P("## 12. Modalità di gioco: Autarchico ed Estremo (tempi di prestigio e costo della morte)")
    P("")
    acts = [a for a in ACTIONS.values() if a["skill"] == "woodcutting"]
    best_rate = {L: max(a["xp"] / a["time_s"] * 3600 for a in acts if a["level_req"] <= L) for L in range(1, 100)}

    def t_to(level, haste_pct=0.0, xp_pct=0.0):
        return sum(xp_to_next(L) / (best_rate[L] * (1 + xp_pct / 100) * (1 + haste_pct / 100)) for L in range(1, level))

    # --- Autarchico: niente acquisti (attrezzi compresi) e niente Commesse. Gli attrezzi si fabbricano, le Commesse
    # pagano al massimo 1,5 x gph contro 1,0 x della vendita diretta: il guadagno perso e' al massimo 1/3.
    rl = PR["rite_level"]
    OR = load("orders_rules.json")[0]
    mult_max = OR["reward_mult_range"][1]
    lost = 1 - 1.0 / mult_max
    a = MR["autarchic"]
    no_orders = a.get("orders") is False
    no_buy = "market_buy" in a
    P(f"**Autarchico** (acquisti dal Mercato solo per: {', '.join(a['market_buy']['allow_items'])}; Commesse {'disattivate' if no_orders else 'attive'}). "
      f"Le XP delle mansioni non dipendono dal Mercato: l'unico effetto e' l'assenza degli attrezzi comprati (profilo *base*, nessun bonus) e delle Commesse "
      f"(al massimo −{lost * 100:.0f}% di oro rispetto alla sola vendita diretta).")
    P("")
    P("| Profilo | Ore al Rito (Lv %d) | Ore a Lv 100 |" % rl)
    P("|---|---|---|")
    for name, hs, xp in PROFILES[:2]:
        P(f"| {name} | {t_to(rl, hs, xp):.1f} h | {t_to(100, hs, xp):.1f} h |")
    P("")
    t_rite_a = t_to(rl)
    t_100_a = t_to(100)
    t_100_n = t_to(100, PROFILES[1][1], PROFILES[1][2])
    check("modalita autarchico (Rito)", no_orders and no_buy and 2.0 <= t_rite_a <= 25.0,
          f"Rito dopo {t_rite_a:.1f} h senza alcun bonus di attrezzo (obiettivo 2-25 h); Commesse disattivate e acquisti limitati ai materiali di base")
    check("modalita autarchico (Stella)", t_100_a >= S["min_hours_target"] and t_100_a <= 2.0 * t_100_n,
          f"prima Stella (Lv 100) dopo {t_100_a:.1f} h contro {t_100_n:.1f} h del profilo tipico (limite 2×; pavimento {S['min_hours_target']:g} h)")
    if ESTATE_FIRST_H:
        slow = 1.0 / (1.0 - lost)
        t_ref = ESTATE_FIRST_H * slow
        P(f"Rifondazione: {ESTATE_FIRST_H:,.0f} h in Normale, al massimo {t_ref:,.0f} h in Autarchico (oro −{lost * 100:.0f}% nel caso peggiore, ×{slow:.2f}).")
        P("")
        check("modalita autarchico (Rifondazione)", slow <= 2.0 and math.isfinite(t_ref),
              f"prima Rifondazione al peggio {t_ref:,.0f} h contro {ESTATE_FIRST_H:,.0f} h (×{slow:.2f}, limite ×2)")

    # --- Estremo: la morte azzera il livello Eroe ma conserva Stelle e record (Eco): la risalita e' piu' breve della prima corsa.
    e = MR["extreme"]["permadeath"]
    P(f"**Estremo** (alla morte: {', '.join(e['reset_skills'])} torna al livello 1, equipaggiamento indossato perso, Stelle e record conservati). "
      f"Costo di una morte dal livello *L*: risalita con l'Eco (record = *L*) contro la prima salita. Proxy: curva di XP del Taglialegna.")
    P("")
    P("| Livello perso | Prima salita | Risalita con Eco | Costo (frazione) |")
    P("|---|---|---|---|")

    def reclimb(level):
        t = 0.0
        for L in range(1, level):
            em = ech["below_50pct_of_record"] if L < 0.5 * level else (ech["below_90pct"] if L < 0.9 * level else ech["below_record"])
            t += xp_to_next(L) / (best_rate[L] * em)
        return t
    ratios = {}
    for lv in (25, 50, 75, 100):
        t1, t2 = t_to(lv), reclimb(lv)
        ratios[lv] = t2 / t1
        P(f"| {lv} | {t1:.1f} h | {t2:.1f} h | {t2 / t1 * 100:.0f}% |")
    P("")
    check("modalita estremo (morte)", all(0.30 <= r <= 0.70 for r in ratios.values()) and e.get("offline_stops_before_death") is True,
          f"una morte costa il {min(ratios.values()) * 100:.0f}-{max(ratios.values()) * 100:.0f}% della prima salita (obiettivo 30-70%: pesa, non e' un muro) "
          "e offline l'Eroe si ferma prima del rischio senza morire")
    st = (1 + S["xp_cap_pct"] / 100)
    P(f"Prestigio: le Stelle, la Polvere, le Costellazioni e le Ere NON si perdono con la morte (il bonus XP delle Stelle arriva a ×{st:.2f}): "
      "l'Estremo non rompe lo strato e conserva i controlli di §8 e §10 (nessun acceleratore nuovo).")
    P("")



def coop_net_report():
    """COOP-2 (Gilda di amici): bonus di gilda asintotici e con tetto <= +10% per chiave (regola 9), progetti
    completabili anche da un socio solo, Boss della settimana raggiungibile con i tetti per socio, premio per socio
    che NON cresce con il numero di soci (R5 §3)."""
    rows = load("coop_net_rules.json")
    if not rows:
        return
    C = rows[0]
    P("## 13. Gilda di amici (coop): bonus, progetti, Boss della settimana")
    P("")
    cap = C["bonus_cap_pct"]
    per_key = {}
    asym = True
    for p in C["projects"]:
        v = p["value_by_level"]
        inc = [v[i + 1] - v[i] for i in range(len(v) - 1)]
        asym = asym and all(x > 0 for x in inc) and all(inc[i + 1] <= inc[i] + 1e-9 for i in range(len(inc) - 1)) and v[-1] < p["cap_pct"]
        for m in p["mods"]:
            per_key[m["key"]] = per_key.get(m["key"], 0) + v[-1]
        P(f"- {p['id']}: tetto {p['cap_pct']}%, livello max {p['max_level']} = +{v[-1]}%, costo totale (1 socio) {sum(p['cost_by_level']):,} punti")
    worst = max(per_key.values()) if per_key else 0
    check("Coop: bonus di gilda asintotici", asym, "incrementi decrescenti, sotto il tetto del progetto")
    check("Coop: tetto bonus per chiave", worst <= cap, f"massimo {worst:.2f}% (tetto {cap}%)")
    # un socio solo: col tetto giornaliero (2 x costo / n, cassetto 7 gg) ogni livello si finanzia in <= 1 giorno di tetto
    sc = C["member_scale_milli"]
    dep = C["deposit"]
    solo_days = max(cost / (dep["daily_cap_mult_milli"] * cost / 1000 / 1) for p in C["projects"] for cost in p["cost_by_level"][1:])
    check("Coop: progetti completabili da soli", solo_days <= 1.0, f"giorni di tetto per un livello (1 socio) {solo_days:.2f}")
    b = C["boss"]
    ok_boss = True
    det = []
    for n in range(1, C["max_members"] + 1):
        hp = b["hp_points_base"] * sc[n] // 1000
        member_cap = b["member_week_cap_mult_milli"] * hp // 1000 // n
        attempts = b["attempts_per_day"] * 7
        reach = n * min(member_cap, attempts * b["max_points_per_attempt"])
        # raggiungibile con i tetti, e con 2+ soci nessuno lo «porta» da solo
        ok_boss = ok_boss and reach >= hp and (n == 1 or member_cap < hp)
        if n in (1, 2, 4, 8):
            det.append(f"n={n}: vita {hp}, tetto/socio {member_cap}")
    check("Coop: Boss della settimana raggiungibile", ok_boss, "; ".join(det))
    # premio per socio: il premio del boss (punti nel fondo, spendibili solo in progetti uguali per tutti) e i costi dei
    # progetti scalano entrambi con n^0,75 -> il rapporto premio/costo (valore per socio) non dipende da n
    cost1 = C["projects"][0]["cost_by_level"][1]
    ratio = {n: (b["reward_fund_points_base"] * sc[n] // 1000) / (cost1 * sc[n] // 1000) for n in (2, 4)}
    check("Coop: premio per socio indipendente da n", abs(ratio[2] - ratio[4]) / ratio[2] <= 0.10,
          f"premio/costo n=2 {ratio[2]:.3f}, n=4 {ratio[4]:.3f}")
    P("")


# --------------------------------------------------------------------------- SABBIA DEL CUSTODE (UI F13, docs/ui_redesign/03 §7, 06 D24-D26)
# Ipotesi del modello (docs/ui_redesign/03 §7.1): la Sabbia accelera solo mansioni e coda; quota di tempo accelerabile alpha per traguardo.
PUSH_ALPHA = {"cap1": 0.6, "estate": 0.35, "era": 0.35, "star": 1.0}     # Cap. I (parte e' combattimento), Rifondazione (solo oro delle mansioni), Ere (combattimento escluso nella v1)
PUSH_CAP1_MIN_H = 60 / 60.0      # fine Cap. I: 60-90 min (docs/22): si parte dal minimo, la stima piu' severa
PUSH_NIGHT_H = 12                # notte di offline per giorno
PUSH_FLOOR_STAR_H = 6.0          # pavimento delle Stelle a regime (constants.stars.min_hours_target)
PUSH_FLOOR_CONST_H = 4.0         # pavimento con Costellazioni al massimo
PUSH_FIND_ERA_MAX_CHANGE = 0.06  # i tempi per Era non cambiano oltre il 6%


def time_push_report():
    TP = K.get("time_push")
    if not TP:
        return
    P("## 14. Sabbia del Custode: riserva di tempo spendibile a clic (UI F13)")
    P("")
    on, off = TP["regen_online_pct"] / 100.0, TP["regen_offline_pct"] / 100.0
    cap, click = TP["reserve_cap_s"], TP["click_s"]
    gift = TP["unlock_gift_s"] + TP["start_reserve_s"]
    P(f"Parametri (`constants.time_push`): clic = {click:g} s, limite {TP['max_cps']} clic/s (solo CPU), riserva massima {cap} s, ricarica online {TP['regen_online_pct']:g}% "
      f"(solo con un'azione ammessa), offline {TP['regen_offline_pct']:g}%, regalo allo sblocco {TP['unlock_gift_s']} s. La Sabbia NON e' un modificatore: avanza il tempo della sola "
      "azione in corso (mansioni + coda), come la Clessidra; e' un fondo finito, quindi il guadagno massimo dipende solo dalle ore presenti, mai dal numero di clic "
      f"(20 clic/s x {click:g} s sarebbe x{1 + TP['max_cps'] * click:g} senza fondo: la riserva lo impedisce).")
    P("")

    def regen_day(p_h):
        return p_h * 3600 * on + PUSH_NIGHT_H * 3600 * off

    # simulazione a passi di 1 minuto: la Sabbia viene spesa non appena c'e' (politica «sempre»); il guadagno non puo' superare la ricarica
    def sim_days(p_h, days=30):
        res, gain_tot = 0.0, 0.0
        per_day = []
        for d in range(days):
            g_d = 0.0
            if d == 0:
                res += gift
            for _ in range(int(p_h * 60)):
                res = min(cap, res + 60 * on)
                spend = min(res, 60.0)                      # il giocatore spende tutto quello che puo' ogni minuto
                res -= spend
                g_d += spend
            res = min(cap, res + PUSH_NIGHT_H * 3600 * off)
            spend = res
            res = 0.0
            g_d += spend
            per_day.append(g_d)
        return per_day

    P("| Presenza al giorno | Ricarica online | Ricarica offline (notte 12 h) | Guadagno massimo al giorno | % delle ore presenti | Clessidre (3600 s) | Giorno 1 (con regalo) | Massimo simulato (30 giorni) |")
    P("|---|---|---|---|---|---|---|---|")
    rows = {}
    for p_h in (1, 4, 8, 16):
        r_on, r_off = p_h * 3600 * on, PUSH_NIGHT_H * 3600 * off
        tot = r_on + r_off
        sd = sim_days(p_h)
        rows[p_h] = (tot, tot / (p_h * 3600), tot / 3600, (tot + gift) / (p_h * 3600), max(sd))
        P(f"| {p_h} h | {r_on:,.0f} s | {r_off:,.0f} s | {tot:,.0f} s | {tot / (p_h * 3600) * 100:.1f}% | {tot / 3600:.2f} | {tot + gift:,.0f} s | {max(sd):,.0f} s |")
    P("")
    g4, g16 = rows[4][1], rows[16][1]
    g_max = max(g4, g16)
    day1 = max(rows[4][3], rows[16][3])
    sim_ok = all(rows[p][4] <= rows[p][0] + gift + 1e-6 for p in rows)
    check("sabbia: guadagno giornaliero (1)", max(g_max, day1) <= 0.08 and sim_ok,
          f"guadagno massimo {g4 * 100:.1f}% delle ore presenti con 4 h e {g16 * 100:.1f}% con 16 h (notte di 12 h offline; giorno 1 con il regalo: {day1 * 100:.1f}%; limite 8%); "
          f"la simulazione minuto per minuto a 30 giorni non supera la ricarica ({'sì' if sim_ok else 'NO'})")
    check("sabbia: meno di una Clessidra al giorno (2)", rows[16][0] + gift <= 3600,
          f"anche con 16 h di presenza il guadagno e' {rows[16][0] + gift:,.0f} s (<= 3600 s = 1 Clessidra, 150 Schegge): la Sabbia non svaluta la Clessidra")
    # (3) pavimenti delle Stelle con la Sabbia al massimo (alpha = 1: le Stelle sono tutte mansioni)
    if STAR_MIN_H is not None and STAR_CONST_MIN_H is not None:
        f_star = 1 + PUSH_ALPHA["star"] * g_max
        t_star, t_const = STAR_MIN_H / f_star, STAR_CONST_MIN_H / f_star
        P(f"Stelle: tempo minimo {STAR_MIN_H:.2f} h -> {t_star:.2f} h con la Sabbia (pavimento {PUSH_FLOOR_STAR_H:g} h); con Polvere e Costellazioni al massimo "
          f"{STAR_CONST_MIN_H:.3f} h -> {t_const:.3f} h (pavimento {PUSH_FLOOR_CONST_H:g} h).")
        P("")
        check("sabbia: pavimenti delle Stelle (3)", t_star >= PUSH_FLOOR_STAR_H and t_const >= PUSH_FLOOR_CONST_H,
              f"con la Sabbia sempre spesa (+{g_max * 100:.1f}% sulle ore presenti) la Stella a regime resta a {t_star:.2f} h (>= {PUSH_FLOOR_STAR_H:g} h) e con le Costellazioni al massimo a "
              f"{t_const:.3f} h (>= {PUSH_FLOOR_CONST_H:g} h)")
    # (4) fine Cap. I
    f_c1 = 1 + PUSH_ALPHA["cap1"] * g_max
    t_c1 = PUSH_CAP1_MIN_H / f_c1 * 60
    check("sabbia: fine Cap. I (4)", t_c1 >= 55,
          f"fine Cap. I: {PUSH_CAP1_MIN_H * 60:.0f} min -> {t_c1:.1f} min con la Sabbia sempre spesa (alpha = {PUSH_ALPHA['cap1']:g}; obiettivo >= 55 min)")
    # (5) prima Rifondazione
    if ESTATE_FIRST_H:
        f_e = 1 + PUSH_ALPHA["estate"] * g_max
        t_e = ESTATE_FIRST_H / f_e
        check("sabbia: prima Rifondazione (5)", 8 <= t_e <= 15,
              f"prima Rifondazione {ESTATE_FIRST_H:.2f} h -> {t_e:.2f} h con la Sabbia (alpha = {PUSH_ALPHA['estate']:g}; fascia 8-15 h)")
    # (6) tempi per Era
    if ERA_WORST_H is not None:
        f_era = 1 + PUSH_ALPHA["era"] * g_max
        change = 1 - 1 / f_era
        check("sabbia: tempi per Era (6)", change <= PUSH_FIND_ERA_MAX_CHANGE,
              f"tempo massimo per Era {ERA_WORST_H:.1f} h -> {ERA_WORST_H / f_era:.1f} h (-{change * 100:.1f}%, alpha = {PUSH_ALPHA['era']:g}: il combattimento e' escluso nella v1; limite {PUSH_FIND_ERA_MAX_CHANGE * 100:g}%)")
    # (7) nessun nodo/modificatore che potenzia la Sabbia senza livello massimo
    keys = set()
    for n in load("constellations.json"):
        keys.add((n["id"], n["modifier_per_level"]["key"].split(":")[0], n["max_level"]))
    bad = sorted(i for i, fam, mx in keys if ("push" in fam or "sand" in fam or "time_push" in fam) and mx is None)
    fams = [m["family"] for m in load("modifier_catalog.json") if "push" in m["family"] or "sand" in m["family"]]
    check("sabbia: nessun potenziamento infinito (7)", not bad and not fams,
          "nessuna famiglia di modificatori ne' nodo di Costellazione potenzia la Sabbia (v1: la Sabbia non e' un modificatore, regole 4 e 9)" if not bad and not fams
          else f"VIOLATI: nodi {bad}, famiglie {fams}")
    P("Etica (docs/24): la Sabbia non tocca Casse, estrazioni, seme, coop, Prove, dungeon, incursioni, Breccia, boss mondiali ne' modalita' Estremo; nessun acquisto, regalo ricorrente o serie.")
    P("")


def main():
    P("# Report di bilanciamento — VAULTFALL")
    P("")
    P("Generato da `tools/balance_sim.py` sui dati in `data/`. Rigenerarlo dopo ogni modifica alle formule.")
    P("")
    skill_pacing()
    artisan_balance()
    single_craft_check()
    COMBAT_SUMMARY.extend(combat_report())
    boss_report()
    raid_winnable_report()
    world_boss_report()
    rift_report()
    fixcombat_report()
    corsa_report()
    gold_report()
    gear_purchase_report()
    orders_report()
    somma_fonti_report()
    bank_capacity_report()
    crate_report()
    estate_report()
    star_pacing()
    era_pacing()
    bonus_profiles()
    prestige_layers()
    era_trial_layers()
    mode_report()
    coop_net_report()
    event_economy()
    time_push_report()
    P("## Riepilogo dei controlli automatici")
    P("")
    P("| Sezione | Esito | Dettaglio |")
    P("|---|---|---|")
    for sec, ok, det in CHECKS:
        P(f"| {sec} | {'OK' if ok else '**FUORI LIMITE**'} | {det} |")
    P("")
    P("## Obiettivi violati con i profili di bonus (da ritarare, D-8/D-9)")
    P("")
    if WARNINGS:
        for sec, det in WARNINGS:
            P(f"- **{sec}:** {det}")
    else:
        P("Nessuno.")
    P("")
    failed = [c for c in CHECKS if not c[1]]
    if QUICK:
        print("(--quick: report NON scritto, campioni ridotti)")
    else:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"Controlli: {len(CHECKS) - len(failed)}/{len(CHECKS)} OK" + (" — FUORI LIMITE: " + ", ".join(c[0] for c in failed) if failed else ""))
    print(f"Obiettivi violati con i profili di bonus (non bloccanti): {len(WARNINGS)}" + (" — " + "; ".join(w[0] for w in WARNINGS) if WARNINGS else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
