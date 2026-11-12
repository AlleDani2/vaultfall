#!/usr/bin/env python3
"""
Genera le appendici consultabili (docs/appendici/*.md) a partire da data/.
Uso: python tools/make_appendices.py   (rilanciare dopo ogni generate_data.py)
Le appendici sono SOLO per lettura umana: la fonte di verità resta data/.
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "docs", "appendici")


def load(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        return json.load(f)


def load_dir(sub):
    out = []
    for f in sorted(os.listdir(os.path.join(DATA, sub))):
        out += load(f"{sub}/{f}")
    return out


ITEMS = {i["id"]: i for i in load_dir("items")}
ACTIONS = load_dir("actions")
SK = {s["id"]: s for s in load("skills.json")}


def n(o, f="name"):
    return f"{o[f]['it']} / {o[f]['en']}"


def iname(i):
    return ITEMS[i]["name"]["it"] if i in ITEMS else i


def write(name, lines):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def a1():
    L = ["# A1 — Mansioni e azioni (generato da data/)", "",
         "Per ogni mansione: tutte le azioni con livello richiesto, durata, XP, ingredienti e prodotti.", ""]
    by = defaultdict(list)
    for a in ACTIONS:
        by[a["skill"]].append(a)
    for sid, s in SK.items():
        L += [f"## {n(s)}", "", s["desc"]["it"], ""]
        acts = sorted(by.get(sid, []), key=lambda a: (a["level_req"], a["id"]))
        if not acts:
            L += ["(nessuna azione: XP dal combattimento/taglie)", ""]
            continue
        if sid == "farming":
            L += ["| Coltura | Lv | Crescita | XP semina | XP raccolto | Resa |", "|---|---|---|---|---|---|"]
            for a in acts:
                L.append(f"| {a['name']['it']} | {a['level_req']} | {a['grow_time_min']} min | {a['xp_plant']} | {a['xp_harvest']} | {a['outputs'][0]['qty']} |")
        elif sid == "thievery":
            L += ["| Bersaglio | Lv | s | XP | Oro | Drop speciali |", "|---|---|---|---|---|---|"]
            for a in acts:
                L.append(f"| {a['name']['it']} | {a['level_req']} | {a['time_s']} | {a['xp']} | {a['gold'][0]}–{a['gold'][1]} | "
                         + ", ".join(f"{iname(d['item'])} {d['chance']:.1%}" for d in a["drops"]) + " |")
        else:
            L += ["| Azione | Lv | s | XP | XP/h | Ingredienti | Prodotto |", "|---|---|---|---|---|---|---|"]
            for a in acts:
                ins = ", ".join(f"{e['qty']}× {iname(e['item'])}" for e in a.get("inputs", [])) or "—"
                outs = ", ".join(f"{e['qty']}× {iname(e['item'])}" for e in a.get("outputs", []))
                L.append(f"| {a['name']['it']} | {a['level_req']} | {a['time_s']} | {a['xp']} | {a['xp'] / a['time_s'] * 3600:,.0f} | {ins} | {outs} |")
        L.append("")
    write("A1_mansioni_e_azioni.md", L)


def a2():
    L = ["# A2 — Equipaggiamento creato e unici (generato)", "",
         "Statistiche base (qualità Normale). Qualità Fine ×1,08 · Eccellente ×1,16 · Capolavoro ×1,28. Rango +4% per livello.", ""]
    eq = [i for i in ITEMS.values() if i["category"] == "equipment"]
    groups = defaultdict(list)
    for i in eq:
        e = i["equipment"]
        key = e["slot"] if e["slot"] not in ("helm", "body", "legs", "gloves", "boots") else f"armor_{e.get('armor_type')}"
        if i.get("unique"):
            key = "unique"
        groups[key].append(i)
    order = ["weapon", "offhand", "armor_plate", "armor_leather", "armor_cloth", "cape", "ring", "amulet", "insignia", "unique"]
    titles = {"weapon": "Armi", "offhand": "Mano secondaria", "armor_plate": "Armature a piastre (Mischia)", "armor_leather": "Armature di cuoio (Distanza)",
              "armor_cloth": "Armature di stoffa (Arcano)", "cape": "Mantelli", "ring": "Anelli", "amulet": "Amuleti", "insignia": "Insegne", "unique": "Oggetti unici (boss, dungeon, incursioni)"}
    for g in order:
        lst = sorted(groups.get(g, []), key=lambda i: (i["equipment"].get("level_req", 0), i["id"]))
        if not lst:
            continue
        L += [f"## {titles[g]}", "", "| Oggetto | Lv | Danno/vel. | Statistiche | Modificatori |", "|---|---|---|---|---|"]
        for i in lst:
            e = i["equipment"]
            dv = f"{e['damage']} / {e['attack_interval_s']}s" if e.get("damage") else ""
            st = ", ".join(f"{k} {v}" for k, v in e.get("stats", {}).items())
            md = ", ".join(f"{m['key']} {m['value']}" for m in e.get("modifiers", []))
            if e.get("element"):
                md += f" · elemento {e['element']}"
            L.append(f"| {i['name']['it']} | {e.get('level_req', '')} | {dv} | {st} | {md} |")
        L.append("")
    tools = sorted([i for i in ITEMS.values() if i["category"] == "tool"], key=lambda i: (i["tool"]["skill"], i["tier"]))
    L += ["## Attrezzi", "", "| Attrezzo | Mansione | Lv | Velocità | Doppio/Successo |", "|---|---|---|---|---|"]
    for i in tools:
        t = i["tool"]
        L.append(f"| {i['name']['it']} | {t['skill']} | {t['level_req']} | +{t['haste_pct']}% | {t.get('double_pct', t.get('success_pct'))} |")
    write("A2_equipaggiamento.md", L)


def a3():
    L = ["# A3 — Zone, mostri, dungeon, incursioni (generato)", ""]
    mons = {m["id"]: m for m in load("monsters.json")}
    drops = {d["id"]: d for d in load("drop_tables.json")}
    for z in load("zones.json"):
        L += [f"## {n(z)} — Lv {z['level_min']}-{z['level_max']}", "", z["desc"]["it"], "",
              "| Mostro | Tipo | Lv | Stile | Debole a | Resiste a | HP | Colpo max | Prec. | Evas. | XP | Oro |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for mid in z["monsters"]:
            m = mons[mid]
            s = m["stats"]
            L.append(f"| {m['name']['it']} | {m['type']} | {m['level']} | {m['style']} | {m['weakness'] or '—'} | {m['resistance'] or '—'} | "
                     f"{s['hp']:,} | {s['max_hit']} | {s['accuracy']} | {s['evasion']} | {m['xp']} | {m['gold'][0]}–{m['gold'][1]} |")
        L.append("")
        L.append(f"Cassa di zona: **{iname(z['crate'])}** · Materiali: {iname(z['common_material'])}, {iname(z['rare_material'])}")
        L.append("")
    L += ["## Dungeon", "", "| Dungeon | Zona | Ondate | Boss | Lv boss | HP boss |", "|---|---|---|---|---|---|"]
    for d in load("dungeons.json"):
        b = mons[d["boss"]]
        L.append(f"| {n(d)} | {d['zone']} | {len(d['waves'])} | {b['name']['it']} | {b['level']} | {b['stats']['hp']:,} |")
    L += ["", "## Incursioni (con squadra di 3 mercenari)", "", "| Incursione | Lv | Boss | HP | Meccaniche |", "|---|---|---|---|---|"]
    for r in load("raids.json"):
        b = mons[r["boss"]]
        L.append(f"| {n(r)} | {r['level']} | {b['name']['it']} | {b['stats']['hp']:,} | {', '.join(b.get('mechanics', []))} |")
    L += ["", "## Boss mondiali", "", "| Boss | Lv | Ogni | Finestra |", "|---|---|---|---|"]
    for w in load("world_bosses.json"):
        L.append(f"| {n(w)} | {w['level']} | {w['spawn_every_h']} h | {w['window_min']} min |")
    write("A3_zone_mostri.md", L)


def a4():
    L = ["# A4 — Casse, finiture e reliquie ★ (generato)", "",
         "Probabilità: Rara 79,20% · Epica 15,80% · Leggendaria 3,80% · Mitica 0,90% · Reliquia ★ 0,30% (+ pity). Annalista 10%.", ""]
    for c in [i for i in ITEMS.values() if i["category"] == "crate"]:
        cr = c["crate"]
        L += [f"## {n(c)}", "", f"Chiave: **{iname(cr['key']) if cr['key'] else 'nessuna (capsula)'}** · valore cassa {c['value']} oro", "",
              "| # | Finitura | Rarità | Slot | Float | Bonus | Valore |", "|---|---|---|---|---|---|---|"]
        for k, sid in enumerate(cr["skins"], start=1):
            s = ITEMS[sid]
            if s["category"] == "skin":
                sk = s["skin"]
                L.append(f"| {k} | {s['name']['it']} / {s['name']['en']} | {s['rarity']} | {sk['slot']} | {sk['float_min']:.2f}–{sk['float_max']:.2f} | "
                         f"{sk['modifier']['key']} +{sk['modifier']['value']} | {s['value']:,} |")
            else:
                L.append(f"| {k} | {s['name']['it']} | {s['rarity']} | cosmetico | — | — | {s['value']:,} |")
        if cr["relic_pool"]:
            L += ["", "**Pool ★:**", ""]
            for r in cr["relic_pool"]:
                if r in ITEMS:
                    rr = ITEMS[r]
                    L.append(f"- {rr['name']['it']} / {rr['name']['en']}: " + ", ".join(f"{m['key']} +{m['value']}" for m in rr["relic"]["modifiers"]) + f" · valore {rr['value']:,}")
                else:
                    L.append(f"- Famiglio ★ `{r}`")
        L.append("")
    write("A4_casse_finiture.md", L)


def a5():
    L = ["# A5 — Missioni (generato)", ""]
    qs = load("quests.json")
    chapters = {c["id"]: c for c in load("chapters.json")}
    L += ["## Storia principale — Cronache del Caveau", ""]
    cur = None
    for q in [q for q in qs if q["kind"] == "main"]:
        if q["chapter"] != cur:
            cur = q["chapter"]
            L += ["", f"### {chapters[cur]['name']['it']}", "", "| ID | Titolo | Obiettivi | Ricompense | Sblocca |", "|---|---|---|---|---|"]
        obj = "; ".join(f"{o['type']} " + " ".join(f"{k}={v}" for k, v in o.items() if k != "type") for o in q["objectives"])
        rw = q["rewards"]
        rws = ", ".join([f"{rw.get('gold', 0):,} oro"] + [f"{e['qty']}× {iname(e['item'])}" for e in rw.get("items", [])] +
                        ([f"Tomo XP ({rw['xp_tome']['size']})"] if rw.get("xp_tome") else []) + ([f"titolo {rw['title']}"] if rw.get("title") else []))
        L.append(f"| {q['id']} | {q['title']['it']} | {obj} | {rws} | {', '.join(q['unlocks'])} |")
    for kind, title in (("side", "Incarichi di fazione"), ("class", "Missioni di classe"), ("skill_path", "Percorsi di mansione (estratto)")):
        L += ["", f"## {title}", "", "| ID | Titolo | Obiettivi |", "|---|---|---|"]
        lst = [q for q in qs if q["kind"] == kind]
        if kind == "skill_path":
            lst = [q for q in lst if q["id"].endswith(("_1", "_5", "_10"))]
        for q in lst:
            obj = "; ".join(f"{o['type']} " + " ".join(f"{k}={v}" for k, v in o.items() if k != "type") for o in q["objectives"])
            L.append(f"| {q['id']} | {q['title']['it']} | {obj} |")
    write("A5_missioni.md", L)


def a6():
    L = ["# A6 — Imprese (achievement Steam), famigli, costellazioni, titoli (generato)", "",
         "## Imprese", "", "| API Steam | Nome IT | Nome EN | Condizione | Polvere Stellare |", "|---|---|---|---|---|"]
    for a in load("achievements.json"):
        c = ", ".join(f"{k}={v}" for k, v in a["condition"].items())
        L.append(f"| `{a['steam_api_name']}` | {a['name']['it']} | {a['name']['en']} | {c} | {a['reward']['stardust']} |")
    L += ["", "## Famigli", "", "| ID | Nome | Fonte | Bonus |", "|---|---|---|---|"]
    for p in load("pets.json"):
        src = ", ".join(f"{k}={v}" for k, v in p["source"].items())
        L.append(f"| {p['id']} | {n(p)} | {src} | " + ", ".join(f"{m['key']} +{m['value']}" for m in p["modifiers"]) + " |")
    L += ["", "## Costellazioni (Polvere Stellare)", "", "| Nodo | Costellazione | Effetto/livello | Max | Costo |", "|---|---|---|---|---|"]
    for c in load("constellations.json"):
        m = c["modifier_per_level"]
        L.append(f"| {c['name']['it']} | {c['constellation_name']['it']} | {m['key']} +{m['value']} ({m['mode']}) | {'∞' if c['max_level'] is None else c['max_level']} | {c['cost_formula']} |")
    L += ["", "## Modificatori (catalogo)", "", "| Famiglia | Unità | Ambiti | Cap | Descrizione |", "|---|---|---|---|---|"]
    for c in load("modifier_catalog.json"):
        L.append(f"| `{c['family']}` | {c['unit']} | {', '.join(c['scopes']) if c['scopes'] else '—'} | {c['cap'] if c['cap'] is not None else '—'} | {c['desc']['it']} |")
    write("A6_imprese_famigli_costellazioni.md", L)


if __name__ == "__main__":
    a1(); a2(); a3(); a4(); a5(); a6()
    print("Appendici scritte in", OUT)
