#!/usr/bin/env python3
"""
Validatore di integrità dei dati di gioco (legge SOLO data/).
Uso:  python tools/validate_data.py            -> esce con codice 1 se ci sono ERRORI
      python tools/validate_data.py --strict   -> anche gli AVVISI fanno fallire
Controlla: riferimenti incrociati, nomi IT/EN, chiavi di modificatore, fonti/usi degli oggetti, sanità numerica.
"""
import sys as _sys
for _s in (_sys.stdout, _sys.stderr):      # testo UTF-8 anche quando l'output è reindirizzato (Windows, Claude Code)
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8", errors="replace")
import json, os, sys, re
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
errors, warnings = [], []


def E(msg):
    errors.append(msg)


def W(msg):
    warnings.append(msg)


def load(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        return json.load(f)


def load_dir(sub):
    out = []
    d = os.path.join(DATA, sub)
    for f in sorted(os.listdir(d)):
        if f.endswith(".json"):
            out.extend(load(f"{sub}/{f}"))
    return out


def index(lst, what):
    idx = {}
    for o in lst:
        if o["id"] in idx:
            E(f"{what}: id duplicato '{o['id']}'")
        idx[o["id"]] = o
    return idx


def check_name(o, what, field="name"):
    n = o.get(field)
    if not isinstance(n, dict) or not n.get("it") or not n.get("en"):
        E(f"{what} '{o.get('id')}': campo '{field}' senza testo IT/EN")


def main():
    strict = "--strict" in sys.argv
    items = index(load_dir("items"), "oggetto")
    actions = index(load_dir("actions"), "azione")
    T = {f[:-5]: load(f) for f in os.listdir(DATA) if f.endswith(".json") and f not in ("manifest.json", "constants.json", "xp_table.json")}
    skills = index(T["skills"], "mansione")
    monsters = index(T["monsters"], "mostro")
    drops = index(T["drop_tables"], "tabella drop")
    loots = index(T["loot_tables"], "tabella apribile")
    zones = index(T["zones"], "zona")
    dungeons = index(T["dungeons"], "dungeon")
    raids = index(T["raids"], "incursione")
    wbosses = index(T["world_bosses"], "boss mondiale")
    quests = index(T["quests"], "missione")
    pets = index(T["pets"], "famiglio")
    titles = index(T["titles"], "titolo")
    buildings = index(T["estate_buildings"], "edificio")
    npcs = index(T["npcs"], "png")
    classes = index(T["classes"], "classe")
    factions = index(T["factions"], "fazione")
    catalog = {c["family"]: c for c in T["modifier_catalog"]}
    collections = index(T["collections"], "collezione")

    def item_or_pet(i):
        return i in items or i in pets

    # ---------------- modificatori
    def check_mod(m, where):
        k = m.get("key")
        fam, _, scope = k.partition(":")
        if fam not in catalog:
            E(f"{where}: chiave modificatore sconosciuta '{k}'")
            return
        sc = catalog[fam]["scopes"]
        if scope:
            if fam in ("dungeon_loot_pct", "dungeon_speed_pct"):
                if scope != "all" and scope not in dungeons:
                    E(f"{where}: ambito dungeon sconosciuto '{k}'")
            elif sc is None or scope not in sc:
                E(f"{where}: ambito non ammesso '{k}'")
        if m.get("mode", "add") not in ("add", "more"):
            E(f"{where}: mode non valido in '{k}'")
        val = m.get("value", m.get("cap"))   # le curve delle Stelle hanno "cap" + "decay" invece di "value"
        if not isinstance(val, (int, float)):
            E(f"{where}: valore non numerico in '{k}'")
        if "decay" in m and not (0 < m["decay"] < 1):
            E(f"{where}: decay fuori da (0,1) in '{k}'")

    def walk_mods(o, where):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("modifiers", "modifiers_per_rank", "per_star_linear", "curves") and isinstance(v, list):
                    for m in v:
                        check_mod(m, where)
                elif k in ("modifier", "modifier_per_level") and isinstance(v, dict) and "key" in v:
                    check_mod(v, where)
                else:
                    walk_mods(v, where)
        elif isinstance(o, list):
            for v in o:
                walk_mods(v, where)

    for name, tbl in T.items():
        if name == "modifier_catalog":
            continue
        walk_mods(tbl, f"tabella {name}")
    for it in items.values():
        walk_mods(it, f"oggetto {it['id']}")

    # ---------------- oggetti
    valid_cats = {"material", "seed", "openable", "misc", "food", "potion", "ammo", "glyph", "equipment", "tool", "key", "currency",
                  "consumable", "quest", "skin", "relic", "crate", "cosmetic"}
    for it in items.values():
        check_name(it, "oggetto")
        if it["category"] not in valid_cats:
            E(f"oggetto {it['id']}: categoria '{it['category']}' non valida")
        if not isinstance(it.get("value"), int) or it["value"] < 0:
            E(f"oggetto {it['id']}: valore non valido {it.get('value')}")
        if not 1 <= it.get("tier", 1) <= 11:
            E(f"oggetto {it['id']}: tier fuori intervallo")
        eq = it.get("equipment")
        if it["category"] == "equipment":
            if not eq or eq.get("slot") not in ("weapon", "offhand", "helm", "body", "legs", "gloves", "boots", "cape", "amulet", "ring", "relic", "insignia"):
                E(f"oggetto {it['id']}: slot equipaggiamento non valido")
            elif not 1 <= eq.get("level_req", 1) <= 100:
                E(f"oggetto {it['id']}: level_req non valido")
            if eq and eq.get("slot") == "weapon" and (eq.get("damage", 0) <= 0 or eq.get("attack_interval_s", 0) <= 0):
                E(f"oggetto {it['id']}: arma senza danno o velocità")
        if it["category"] == "skin":
            s = it["skin"]
            if not 0 <= s["float_min"] < s["float_max"] <= 1:
                E(f"finitura {it['id']}: intervallo float non valido")
        if it["category"] == "crate":
            c = it["crate"]
            if c["key"] and c["key"] not in items:
                E(f"cassa {it['id']}: chiave inesistente {c['key']}")
            for s in c["skins"]:
                if s not in items:
                    E(f"cassa {it['id']}: contenuto inesistente {s}")
            for r in c["relic_pool"]:
                if not item_or_pet(r):
                    E(f"cassa {it['id']}: ★ inesistente {r}")
            if c.get("collection") and c["collection"] not in collections:
                E(f"cassa {it['id']}: collezione inesistente")
            if abs(sum(c["odds"].values()) - 100) > 0.01:
                E(f"cassa {it['id']}: le probabilità non sommano a 100")
            if "pity_family" not in c:
                E(f"cassa {it['id']}: manca pity_family (null se la cassa non ha pity)")
            elif c["pity_family"] is None and c["odds"].get("relic", 0) > 0 and c.get("kind") not in ("event",):
                W(f"cassa {it['id']}: ha ★ ma nessuna pity")
        sk = it.get("skin") or it.get("relic")
        if sk is not None and it.get("category") in ("skin", "relic"):
            co = sk.get("condition_odds")
            valid_c = {"pristine", "polished", "marked", "worn", "scarred"}
            if not co:
                E(f"finitura {it['id']}: mancano le probabilità delle condizioni (condition_odds)")
            else:
                if abs(sum(co.values()) - 100) > 0.05:
                    E(f"finitura {it['id']}: condition_odds somma {sum(co.values()):.2f} invece di 100")
                if set(co) - valid_c:
                    E(f"finitura {it['id']}: condizioni sconosciute {set(co) - valid_c}")
        if it.get("open_table") and it["open_table"] not in loots:
            E(f"oggetto {it['id']}: tabella apribile inesistente")

    # ---------------- azioni
    for a in actions.values():
        check_name(a, "azione")
        if a["skill"] not in skills:
            E(f"azione {a['id']}: mansione sconosciuta")
        if not 1 <= a["level_req"] <= 100:
            E(f"azione {a['id']}: level_req {a['level_req']} fuori intervallo")
        if a["skill"] != "farming":
            if a.get("time_s", 0) <= 0 or a.get("xp", 0) <= 0:
                E(f"azione {a['id']}: tempo o XP non validi")
        for io in ("inputs", "outputs"):
            for e in a.get(io, []):
                if e["item"] not in items:
                    E(f"azione {a['id']}: {io} inesistente {e['item']}")
        for s in a.get("secondary", []):
            if "item" in s and s["item"] not in items:
                E(f"azione {a['id']}: secondario inesistente {s['item']}")
            for p in s.get("pick", []):
                if p["item"] not in items:
                    E(f"azione {a['id']}: secondario inesistente {p['item']}")
        for d in a.get("drops", []):
            if d["item"] not in items:
                E(f"azione {a['id']}: drop inesistente {d['item']}")
        if a.get("seed") and a["seed"] not in items:
            E(f"azione {a['id']}: seme inesistente")
        c = a.get("crate")
        if c and f"{c['id']}" not in items:
            E(f"azione {a['id']}: cassa inesistente {c['id']}")
    for s in skills.values():
        if s["id"] in ("hero", "bounty"):
            continue
        lv = [a["level_req"] for a in actions.values() if a["skill"] == s["id"]]
        if not lv:
            E(f"mansione {s['id']}: nessuna azione")
        elif min(lv) > 1 and s["id"] not in ():
            E(f"mansione {s['id']}: nessuna azione al livello 1 (minimo {min(lv)})")

    # ---------------- combattimento
    mechanics = index(T["boss_mechanics"], "meccanica dei boss")
    for mc in mechanics.values():
        check_name(mc, "meccanica dei boss")
        check_name(mc, "meccanica dei boss", "desc")
        if not isinstance(mc.get("trigger"), dict) or not isinstance(mc.get("effect"), dict):
            E(f"meccanica {mc['id']}: servono 'trigger' e 'effect'")
        if "every_s" in mc.get("trigger", {}) and not mc["trigger"]["every_s"] > 0:
            E(f"meccanica {mc['id']}: every_s deve essere positivo")
    for m in monsters.values():
        for mech_id in m.get("mechanics", []):
            if mech_id not in mechanics:
                E(f"mostro {m['id']}: meccanica inesistente {mech_id}")
    for a in T["abilities"]:
        if not a["cooldown_s"] > 0 or a["cost"] < 0:
            E(f"abilità {a['id']}: ricarica o costo non validi")
        if a["class"] not in classes:
            E(f"abilità {a['id']}: classe inesistente {a['class']}")
    for t in T["talents"]:
        if t["class"] not in classes:
            E(f"talento {t['id']}: classe inesistente {t['class']}")
        for mod in t["modifiers_per_rank"]:
            check_mod(mod, f"talento {t['id']}")
    for m in monsters.values():
        check_name(m, "mostro")
        if m["drop_table"] not in drops:
            E(f"mostro {m['id']}: tabella drop inesistente")
        if m["zone"] and m["zone"] not in zones:
            E(f"mostro {m['id']}: zona inesistente")
        for u in m.get("unique_drops", []):
            if u not in items:
                E(f"mostro {m['id']}: unico inesistente {u}")
        if m.get("pet") and m["pet"] not in pets:
            E(f"mostro {m['id']}: famiglio inesistente {m['pet']}")
    for d in drops.values():
        for e in d["entries"]:
            if "item" in e and not item_or_pet(e["item"]):
                E(f"tabella {d['id']}: oggetto inesistente {e['item']}")
        if d.get("crate") and d["crate"]["id"] not in items:
            E(f"tabella {d['id']}: cassa inesistente {d['crate']['id']}")
    for lt in loots.values():
        for e in lt["entries"]:
            if e["item"] not in items:
                E(f"tabella apribile {lt['id']}: oggetto inesistente {e['item']}")
    for z in zones.values():
        for m in z["monsters"]:
            if m not in monsters:
                E(f"zona {z['id']}: mostro inesistente {m}")
        for k in ("crate", "common_material", "rare_material"):
            if z[k] not in items:
                E(f"zona {z['id']}: {k} inesistente")
    for d in dungeons.values():
        for w in d["waves"]:
            if w["monster"] not in monsters:
                E(f"dungeon {d['id']}: mostro inesistente {w['monster']}")
        if d["unlock"]["quest"] not in quests:
            E(f"dungeon {d['id']}: missione di sblocco inesistente")
    for r in raids.values():
        if r["boss"] not in monsters or r["unlock"]["quest"] not in quests:
            E(f"incursione {r['id']}: boss o missione inesistente")

    # ---------------- missioni
    token_re = re.compile(r"^(skill|feature|zone|dungeon|raid|building|chapter|class|era):[a-z0-9_]+$")
    for q in quests.values():
        check_name(q, "missione", "title")
        for r in q["requires"]:
            if r not in quests and not token_re.match(r):
                E(f"missione {q['id']}: requisito non valido '{r}'")
        for u in q["unlocks"]:
            if not token_re.match(u):
                E(f"missione {q['id']}: sblocco non valido '{u}'")
            kind, _, val = u.partition(":")
            ref = {"skill": skills, "zone": zones, "dungeon": dungeons, "raid": raids, "building": buildings, "class": classes}.get(kind)
            if ref is not None and val not in ref:
                E(f"missione {q['id']}: sblocco a riferimento inesistente '{u}'")
        if q.get("giver") and q["giver"] not in npcs:
            E(f"missione {q['id']}: PNG inesistente {q['giver']}")
        for o in q["objectives"]:
            for k, ref in (("item", items), ("monster", monsters), ("dungeon", dungeons), ("building", buildings), ("npc", npcs)):
                if k in o and o[k] not in ref:
                    E(f"missione {q['id']}: {k} inesistente '{o[k]}'")
            if "raid" in o and o["raid"] != "any" and o["raid"] not in raids:
                E(f"missione {q['id']}: incursione inesistente")
            if "skill" in o and o["skill"] not in skills and o["skill"] != "any":
                E(f"missione {q['id']}: mansione inesistente {o['skill']}")
            if "target" in o and o["target"] not in actions:
                E(f"missione {q['id']}: bersaglio di borseggio inesistente")
            if "crop" in o and o["crop"] not in items:
                E(f"missione {q['id']}: raccolto inesistente")
        rw = q["rewards"]
        for e in rw.get("items", []):
            if e["item"] not in items:
                E(f"missione {q['id']}: ricompensa inesistente {e['item']}")
        if rw.get("title") and rw["title"] not in titles:
            E(f"missione {q['id']}: titolo inesistente {rw['title']}")
        if rw.get("reputation") and rw["reputation"]["faction"] not in factions:
            E(f"missione {q['id']}: fazione inesistente")
    # catena principale: ogni capitolo raggiungibile
    main = [q for q in quests.values() if q["kind"] == "main"]
    reach = set()
    changed = True
    while changed:
        changed = False
        for q in main:
            if q["id"] in reach:
                continue
            if all((r in reach) or (r not in quests) for r in q["requires"]):
                reach.add(q["id"])
                changed = True
    for q in main:
        if q["id"] not in reach:
            E(f"missione principale irraggiungibile: {q['id']}")
    # i numeri scritti nella descrizione seguono gli obiettivi (ritaratura del ritmo: resoconto 29)
    for q in main:
        nums = {str(o[k]) for o in q["objectives"] for k in ("qty", "level", "gold", "floor")
                if isinstance(o.get(k), int) and o[k] > 1}
        for lang in ("it", "en"):
            found = set(re.findall(r"\d+", q["desc"].get(lang, "").replace(".", "")))
            for n in sorted(nums - found):
                E(f"missione {q['id']}: la descrizione ({lang}) non riporta il numero {n} dell'obiettivo")

    # ---------------- negozio, banco, gettoni, famigli, imprese
    for s in T["shop"]:
        if s.get("item") and s["item"] not in items:
            E(f"negozio {s['id']}: oggetto inesistente")
    # invariante di non-arbitraggio (QA3 E1, ricerca R3 P3.1): un oggetto comprabile all'Emporio e rivendibile non deve dare utile
    # nemmeno con i bonus massimi: valore x (1 - tassa minima) x (1 + msp max 50%) x (1 + gold_gain 40%) <= prezzo
    tax_min = T["market_rules"][0]["sell_tax"] * 0.2     # riduzione massima delle tasse: 80%
    arb = (1 - tax_min) * 1.50 * 1.40
    for s in T["shop"]:
        it = items.get(s.get("item", ""))
        if it and it.get("tradeable", True) and s.get("price") and it.get("value", 0) * arb > s["price"]:
            E(f"negozio {s['id']}: arbitraggio, rivendendo {s['item']} (valore {it['value']}) con i bonus massimi si guadagna (prezzo {s['price']})")
    cr = T["crate_rules"][0]
    for v in cr["vault_bank"]:
        if v["item"] not in items:
            E(f"Banco dei Caveau: oggetto inesistente {v['item']}")
    for v in T["contract_rules"][0]["token_shop"]:
        if v["item"] not in items:
            E(f"negozio gettoni: oggetto inesistente {v['item']}")
    for p in pets.values():
        check_name(p, "famiglio")
        src = p["source"]
        if src.get("monster") and src["monster"] not in monsters:
            E(f"famiglio {p['id']}: mostro inesistente")
        if src.get("raid") and src["raid"] not in raids:
            E(f"famiglio {p['id']}: incursione inesistente")
        if src.get("crate") and src["crate"] not in items:
            E(f"famiglio {p['id']}: cassa inesistente")
    for a in T["achievements"]:
        check_name(a, "impresa")
        c = a["condition"]
        if c.get("monster") and c["monster"] not in monsters:
            E(f"impresa {a['id']}: mostro inesistente")
        if c.get("skill") and c["skill"] not in skills:
            E(f"impresa {a['id']}: mansione inesistente")
        if c.get("raid") and c["raid"] not in raids:
            E(f"impresa {a['id']}: incursione inesistente")
        if a["reward"].get("title") and a["reward"]["title"] not in titles:
            E(f"impresa {a['id']}: titolo inesistente")
        if not re.match(r"^[A-Z0-9_]+$", a["steam_api_name"]):
            E(f"impresa {a['id']}: steam_api_name non valido")
    n_ach = len(T["achievements"])
    n_phase1 = sum(1 for a in T["achievements"] if a.get("steam_phase", 1) == 1)
    if n_phase1 > 100:
        E(f"imprese di fase 1 (Steam al lancio): {n_phase1} > 100, il limite di Steam prima delle Profile Features")

    # mappa delle imprese su Steam: 1:1 con le imprese del gioco, ID stabili e unici, limiti di lunghezza di Steamworks
    steam = T.get("steam_achievements", [])
    if steam:
        by_id = {a["id"]: a for a in T["achievements"]}
        seen_api = set()
        if {s["id"] for s in steam} != set(by_id) or len(steam) != len(by_id):
            E("steam_achievements: non corrisponde 1:1 alle imprese del gioco")
        for s_ in steam:
            a = by_id.get(s_["id"])
            if a is None:
                continue
            if s_["steam_api_name"] != a["steam_api_name"] or s_["phase"] != a.get("steam_phase"):
                E(f"steam_achievements {s_['id']}: ID o fase diversi dall'impresa")
            if s_["steam_api_name"] in seen_api:
                E(f"steam_achievements: ID Steam duplicato {s_['steam_api_name']}")
            seen_api.add(s_["steam_api_name"])
            for lang in ("it", "en"):
                if not s_["name"].get(lang) or not s_["desc"].get(lang):
                    E(f"steam_achievements {s_['id']}: testo {lang} mancante")
                elif len(s_["name"][lang]) > 100 or len(s_["desc"][lang]) > 250:
                    E(f"steam_achievements {s_['id']}: testo {lang} oltre i limiti di Steamworks (nome 100, descrizione 250)")
            if a["hidden"] and not s_["hidden"]:
                E(f"steam_achievements {s_['id']}: nascosta nel gioco ma non su Steam")
        if sum(1 for s_ in steam if s_["phase"] == 1) > 100:
            E("steam_achievements: piu' di 100 imprese di fase 1")

    frames = {f["id"] for f in T["frames"]}
    for q in quests.values():
        c = q["rewards"].get("cosmetic")
        if c and c not in frames and c not in items:
            E(f"missione {q['id']}: cosmetico inesistente {c}")
    for st in T["skill_prestige"]:
        for m in st["milestones"]:
            if m.get("cosmetic") and m["cosmetic"] not in frames:
                E(f"stelle {st['skill']}: cornice inesistente {m['cosmetic']}")
            if m.get("title") and m["title"] not in titles:
                E(f"stelle {st['skill']}: titolo inesistente {m['title']}")
    for ev in T["events"]:
        for r in ev["rewards"]:
            if r not in items and r not in pets and r not in titles:
                E(f"evento {ev['id']}: ricompensa inesistente {r}")
        if ev["crate"] not in items or ev["currency"] not in items:
            E(f"evento {ev['id']}: cassa o valuta inesistente")
    # eventi stagionali (T-11.3): date, missioni, negozio, famiglio senza potere, anti-FOMO
    ser = T["event_rules"][0].get("seasonal", {})
    if not ser:
        E("event_rules: manca la sezione 'seasonal'")
    npc_ids = set(npcs)
    for n in T["npcs"]:      # G34: battute del menù Città (campo facoltativo "chat": 3-5 righe bilingui)
        ch = n.get("chat")
        if ch is not None and not (3 <= len(ch) <= 5 and all(c.get("it") and c.get("en") for c in ch)):
            E(f"png {n['id']}: 'chat' deve avere 3-5 battute con testo it/en")
    for ev in T["events"]:
        eid = ev["id"]
        for k in ("start", "end"):
            md = ev["dates"][k]
            if not (len(md) == 5 and md[2] == "-" and 1 <= int(md[:2]) <= 12 and 1 <= int(md[3:]) <= 31):
                E(f"evento {eid}: data '{md}' non valida (MM-GG)")
        if len(ev.get("missions", [])) != ev.get("quests"):
            E(f"evento {eid}: 'quests' non coincide con le missioni")
        for m in ev.get("missions", []):
            if m["kind"] not in ("actions", "kills", "crates", "currency") or m["qty"] <= 0 or m["reward"] <= 0:
                E(f"evento {eid}: missione {m['id']} non valida")
            if m["skill"] and m["skill"] not in skills:
                E(f"evento {eid}: missione {m['id']}: mansione inesistente {m['skill']}")
            check_name(m, "missione evento")
            check_name(m, "missione evento", "desc")
            if str(m["qty"]) not in m["desc"]["it"] or str(m["qty"]) not in m["desc"]["en"]:
                E(f"evento {eid}: missione {m['id']}: la descrizione non dice la quantità ({m['qty']})")
        if ev.get("host") not in npc_ids:
            E(f"evento {eid}: presentatore inesistente {ev.get('host')}")
        check_name(ev, "evento", "intro")
        # recuperabile: ogni ricompensa non-titolo è acquistabile a prezzo fisso nel Negozio dell'evento
        shop = {s["id"]: s for s in ev.get("shop", [])}
        for r in ev["rewards"]:
            if r.startswith("title_"):
                if ev.get("title_from") != "missions":
                    E(f"evento {eid}: titolo {r} senza via di recupero")
            elif r not in shop:
                E(f"evento {eid}: ricompensa {r} non recuperabile (manca nel Negozio)")
        ecr = items[ev["crate"]]["crate"]
        for s in ev.get("shop", []):
            if s["price"] <= 0 or (s["kind"] == "item" and s["id"] not in items) or (s["kind"] == "pet" and s["id"] not in pets):
                E(f"evento {eid}: voce di negozio non valida {s}")
            if s["kind"] == "item":
                it = items[s["id"]]
                if it.get("category") != "cosmetic" or it.get("tradeable"):
                    E(f"evento {eid}: {s['id']} deve essere un cosmetico non scambiabile")
        for sid in ecr.get("skins", []):
            if items[sid].get("category") != "cosmetic":
                E(f"evento {eid}: la Cassa contiene '{sid}' che non è un cosmetico (solo cosmetici)")
        for pid in ecr.get("relic_pool", []):
            if pets[pid].get("modifiers"):
                E(f"evento {eid}: il famiglio {pid} ha poteri (la Cassa evento è solo cosmetica)")
        if ecr.get("key") is not None or "open_cost" not in ecr or ecr["open_cost"]["item"] != ev["currency"]:
            E(f"evento {eid}: la Cassa si apre solo con la valuta dell'evento (niente chiavi)")
        if not (ser.get("max_drops_per_occurrence", 0) > 0 and ser.get("echo_every_s", 0) >= ev["currency_drop_every_s"]):
            E(f"evento {eid}: l'Eco non può essere più veloce dell'evento")
        for m in ev["modifiers"]:
            check_mod(m, f"evento {eid}")
    for t in titles.values():
        check_name(t, "titolo")

    # ---------------- modalità di gioco (docs/05 §7): mode_rules.json
    mr_rows = T.get("mode_rules", [])
    if mr_rows:
        mr = mr_rows[0]
        modes = mr.get("modes", {})
        if sorted(modes.keys()) != ["autarchic", "extreme", "normal"]:
            E(f"mode_rules: modalità attese normal/autarchic/extreme, trovate {sorted(modes.keys())}")
        if mr.get("default") != "normal":
            E("mode_rules: la modalità predefinita deve essere 'normal'")
        for mid, m in modes.items():
            for fld, pool in (("title", titles), ("star_title", titles), ("frame", frames)):
                v = m.get(fld)
                if v is not None and v not in pool:
                    E(f"mode_rules {mid}: {fld} inesistente '{v}'")
            if mid != "normal" and not (m.get("title") and m.get("frame")):
                E(f"mode_rules {mid}: titolo e cornice dedicati obbligatori (docs/05 §7)")
            for iid in m.get("market_buy", {}).get("allow_items", []):
                if iid not in items:
                    E(f"mode_rules {mid}: oggetto consentito inesistente '{iid}'")
            pd = m.get("permadeath")
            if pd:
                for sid in pd.get("reset_skills", []):
                    if sid not in skills:
                        E(f"mode_rules {mid}: mansione inesistente '{sid}'")

    # ---------------- fonti e usi degli oggetti
    sources = defaultdict(list)
    uses = defaultdict(list)
    for a in actions.values():
        for e in a.get("outputs", []):
            sources[e["item"]].append(a["id"])
        for e in a.get("inputs", []):
            uses[e["item"]].append(a["id"])
        for s in a.get("secondary", []):
            if "item" in s:
                sources[s["item"]].append(a["id"])
            for p in s.get("pick", []):
                sources[p["item"]].append(a["id"])
        for d in a.get("drops", []):
            sources[d["item"]].append(a["id"])
        if a.get("seed"):
            uses[a["seed"]].append(a["id"])
        if a.get("crate"):
            sources[a["crate"]["id"]].append(a["id"])
    for d in drops.values():
        for e in d["entries"]:
            if "item" in e:
                sources[e["item"]].append(d["id"])
        if d.get("crate"):
            sources[d["crate"]["id"]].append(d["id"])
    for lt in loots.values():
        for e in lt["entries"]:
            sources[e["item"]].append(lt["id"])
    for it in items.values():
        if it["category"] == "crate":
            for s in it["crate"]["skins"] + it["crate"]["relic_pool"]:
                sources[s].append(it["id"])
    for s in T["shop"]:
        if s.get("item"):
            sources[s["item"]].append("shop")
    for v in cr["vault_bank"] + T["contract_rules"][0]["token_shop"]:
        sources[v["item"]].append("token_shop")
    for shop_ in T["currency_shops"]:
        for v in shop_["items"]:
            if v["item"] not in items:
                E(f"negozio {shop_['id']}: oggetto inesistente {v['item']}")
            sources[v["item"]].append(shop_["id"])
    for q in quests.values():
        for e in q["rewards"].get("items", []):
            sources[e["item"]].append(q["id"])
        if q["rewards"].get("xp_tome"):
            sources[f"tome_xp_{q['rewards']['xp_tome']['size']}"].append(q["id"])
        for o in q["objectives"]:
            if o["type"] == "deliver":
                uses[o["item"]].append(q["id"])
    for z in zones.values():
        sources[z["crate"]].append(z["id"])
    for d in dungeons.values():
        for c in d["completion_reward"]["crates"]:
            sources[c["id"]].append(d["id"])
        for e in d["completion_reward"]["items"]:
            sources[e["item"]].append(d["id"])
    for r in raids.values():
        for e in r["completion_reward"]["items"]:
            sources[e["item"]].append(r["id"])
    for wb in wbosses.values():
        for tier, lst in wb["rewards"].items():
            for e in lst:
                sources[e["item"]].append(wb["id"])
    rift = T["rift"][0]
    sources[rift["crate"]].append("rift")
    for e in rift["guardian_rewards"]:
        sources[e["item"]].append("rift")
    bb = T["bounty_board"][0]
    sources[bb["completion_bonus"]["crate"]].append("bounty_board")
    for e in bb["wanted_variant"]["drops"]:
        sources[e["item"]].append("bounty_board")
    for it_id in ("granite",) + tuple(i for i in items if i.startswith("padlock_") or i.startswith("plank_") or i.startswith("bar_")):
        uses[it_id].append("costi edifici Tenuta")
    for ev in T["events"]:
        sources[ev["crate"]].append(ev["id"])
        sources[ev["currency"]].append(ev["id"])
    implicit = {"vault_shard": "fusione oggetti da cassa", "bounty_mark": "taglie", "commission_token": "commesse",
                "raid_seal": "incursioni", "rift_shard": "Breccia", "stardust": "stelle/imprese", "era_essence": "ere",
                "map_fragment": "spedizioni", "burnt_food": "cucina (bruciatura)", "celestial_key": "missione"}
    for k in implicit:
        sources[k].append(implicit[k])
    tpl = cr.get("era_crate_template", {})
    for n in range(int(tpl.get("min_era", 2)), int(tpl.get("max_era", 1)) + 1):
        sources[tpl["id_pattern"].replace("{n}", str(n))].append("Custode del Caveau (Era)")
    estate_subcats = {"log", "ore", "fish_raw", "fiber", "crop", "hide", "meat_raw", "feather"}
    for it in items.values():
        if it["category"] in ("cosmetic",):
            sources[it["id"]].append("capsula")
        if it.get("subcategory") in estate_subcats:
            sources[it["id"]].append("tenuta")
        if it["category"] == "equipment" and it["equipment"]["slot"] == "insignia":
            sources[it["id"]].append("percorso di mansione")
    for it in items.values():
        if not sources.get(it["id"]):
            E(f"oggetto senza fonte: {it['id']}")
    for it in items.values():
        if it["category"] == "material" and not uses.get(it["id"]) and it["subcategory"] not in ("monster_mat_rare", "era", "map", "padlock", "gem_raw"):
            W(f"materiale senza utilizzo diretto: {it['id']} ({it['subcategory']})")

    # ---------------- COOP-1: coop_rules.json (modalità Amici, nessuna rete)
    cr_rows = T.get("coop_rules", [])
    if cr_rows:
        cr = cr_rows[0]
        for cid, role in cr["roles"].items():
            if cid not in classes:
                E(f"coop_rules: classe inesistente '{cid}'")
            if role not in ("defender", "healer", "striker"):
                E(f"coop_rules: ruolo sconosciuto '{role}' per {cid}")
        for cid, c in classes.items():
            if (c.get("base") or c.get("hybrid")) and cid not in cr["roles"]:
                E(f"coop_rules: la classe {cid} non ha un ruolo di squadra")
        for mid in cr["weekly"]["guardian_pool"]:
            if mid not in mechanics:
                E(f"coop_rules: meccanica del Guardiano inesistente '{mid}'")
        if cr["title"] not in titles:
            E(f"coop_rules: titolo inesistente '{cr['title']}'")
        lo, hi = cr["weekly"]["affix_count"]
        if not (1 <= lo <= hi):
            E("coop_rules: affix_count non valido")
        if cr["companions"]["max"] < 1 or cr["code"]["max_chars"] < 100:
            E("coop_rules: limiti dei codici non validi")
        for nm in cr["weekly"]["name_pool"]:
            if not nm.get("it") or not nm.get("en"):
                E("coop_rules: nome della settimana senza testo IT/EN")

    # ---------------- CORSA (resoconto 91): run_perks.json + run_rules.json
    rr_rows = T.get("run_rules", [])
    rp_rows = T.get("run_perks", [])
    if rr_rows:
        rr = rr_rows[0]
        fams = {f["id"] for f in rr["families"]}
        for f in rr["families"]:
            if not f["name"].get("it") or not f["name"].get("en"):
                E(f"run_rules: famiglia {f['id']} senza nome IT/EN")
        seen = set()
        for p in rp_rows:
            check_name(p, "voce della Corsa")
            if p["id"] in seen:
                E(f"run_perks: voce duplicata {p['id']}")
            seen.add(p["id"])
            if p["family"] not in fams:
                E(f"run_perks {p['id']}: famiglia sconosciuta '{p['family']}'")
            if not p.get("desc", {}).get("it") or not p.get("desc", {}).get("en"):
                E(f"run_perks {p['id']}: frase senza testo IT/EN")
            worse = set(rr["worse_if_higher"])
            gains = [(m["value"] > 0) != (m["key"].partition(":")[0] in worse) for m in p["modifiers"]]
            if not any(gains) or all(gains):
                E(f"run_perks {p['id']}: ogni voce deve avere un vantaggio e un compromesso (91 §3.3)")
            for m in p["modifiers"]:
                if m["key"].partition(":")[0] in rr["forbidden_keys"]:
                    E(f"run_perks {p['id']}: chiave vietata '{m['key']}' (regola 9: niente bonus di strato)")
                if m.get("mode", "add") != "add":
                    E(f"run_perks {p['id']}: solo modificatori add (i «more» sono dei prestigi, docs/14)")
        for fid in fams:
            n = sum(1 for p in rp_rows if p["family"] == fid)
            if n < rr["offers"]:
                E(f"run_rules: la famiglia {fid} ha {n} voci (servono almeno {rr['offers']})")
        if rr["default_mode"] not in rr["modes"] or rr["kills_per_choice"] < 1 or rr["max_choices"] < 1:
            E("run_rules: modalità o contatori non validi")
        if len(rp_rows) * rr["max_stacks"] < rr["max_choices"] + rr["offers"]:
            E("run_rules: troppo poche voci per riempire una Corsa")
        ch = rr["champion"]
        if not (0 <= ch["crate_chance"] <= 1) or ch["max_attempts"] < 1 or ch["hp_mult"] <= 0:
            E("run_rules: Campione con parametri non validi")
    elif rp_rows:
        E("run_perks senza run_rules")

    # ---------------- passi di scoperta (guides): testi bilingui e bersaglio «Vai» presente
    gseen = set()
    for g in T.get("guides", []):
        gid = g.get("id", "?")
        if gid in gseen:
            E(f"guida duplicata: {gid}")
        gseen.add(gid)
        for fld in ("title", "text", "why"):
            v = g.get(fld) or {}
            if not (str(v.get("it", "")).strip() and str(v.get("en", "")).strip()):
                E(f"guida {gid}: campo '{fld}' senza testo IT/EN")
        if not g.get("screen") or not (g.get("goto") or {}).get("screen"):
            E(f"guida {gid}: schermata o bersaglio 'goto' mancante")

    # ---------------- sanità numerica: XP/ora crescente per tier nelle raccolte
    for sk in ("woodcutting", "mining", "fishing", "foraging", "trapping"):
        acts = sorted([a for a in actions.values() if a["skill"] == sk], key=lambda a: a["level_req"])
        prev = 0
        for a in acts:
            rate = a["xp"] / a["time_s"] * 3600
            if rate + 1e-9 < prev * 0.98 and "herb" not in a["id"] and "fiber" not in a["id"]:
                W(f"{a['id']}: XP/ora {rate:.0f} inferiore all'azione precedente ({prev:.0f})")
            prev = max(prev, rate)

    print(f"Oggetti {len(items)} · Azioni {len(actions)} · Mostri {len(monsters)} · Missioni {len(quests)} · Imprese {n_ach}")
    for w in warnings[:200]:
        print("AVVISO:", w)
    if len(warnings) > 200:
        print(f"... altri {len(warnings) - 200} avvisi")
    for e in errors[:300]:
        print("ERRORE:", e)
    print(f"\nRisultato: {len(errors)} errori, {len(warnings)} avvisi")
    sys.exit(1 if errors or (strict and warnings) else 0)


if __name__ == "__main__":
    main()
