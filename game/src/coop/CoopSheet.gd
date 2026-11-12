class_name CoopSheet
extends RefCounted
## «Scheda del Compagno» (COOP-1): copia in SOLA LETTURA dello stato di combattimento di un Eroe.
## Contiene SOLO l'effetto sul combattimento: classe, specializzazione, livello, statistiche derivate (l'equipaggiamento
## c'è già dentro come statistiche), abilità equipaggiate, risorsa; più nome e titolo. NESSUN oggetto, nessun
## identificatore di oggetto, nessun dato personale (l'identificativo `uid` è derivato dalla data di creazione della
## partita, non dall'utente, e serve solo a riconoscere una scheda aggiornata dello stesso amico).
##
## Importazione = validazione robusta: ogni campo ha tipo e intervallo; i numeri sopra il tetto del gioco (stesse
## formule e stessi dati dell'Eroe: vedi limits_for) vengono riportati al tetto, gli id sconosciuti scartati. Una scheda
## manomessa non può quindi dare un vantaggio che il gioco non permetta, e comunque l'effetto in squadra ha il tetto
## dei mercenari (mercenary_rules.raid_roles.ratio_cap).

## Statistiche numeriche portate dalla scheda (le altre di CombatSystem._build_stats non servono al motore).
const NUM_KEYS: PackedStringArray = ["hp", "acc", "eva", "arm", "ward", "max_hit", "min_ratio", "interval", "crit", "critd",
	"regen_pct", "lifesteal", "armor_pen", "dmg_taken_mult", "dot_mult", "summon_mult", "thorns", "multihit",
	"status_resist", "heal_rx", "vs_bounty", "res_mult"]
const SIM_TOTALS: PackedStringArray = ["combat_dmg_pct", "combat_haste_pct", "combat_defense_pct", "combat_eva_pct",
	"combat_dmg_taken_pct", "combat_dot_dmg_pct", "summon_dmg_pct", "combat_crit_chance_pct", "combat_crit_dmg_pct",
	"combat_regen_hps_pct"]
const ELEMENTS: PackedStringArray = ["fire", "frost", "lightning", "poison", "holy", "shadow"]
const STYLES: PackedStringArray = ["melee", "ranged", "arcane"]
## Campi che non devono MAI comparire in una scheda (prova di non-trasferimento: test_coop_codes).
const FORBIDDEN_KEYS: PackedStringArray = ["bank", "items", "inventory", "gear", "equipment", "gold", "currencies", "instances"]

static var _lim_cache: Dictionary = {}


static func rules(data: Object) -> Dictionary:
	return data.rules("coop_rules")


# ====================================================================== esportazione

## Costruisce la scheda dall'Eroe corrente di `combat` (CombatSystem). `uid`/`name` li decide chi chiama.
static func export_from(combat: Object, data: Object, uid: String, nm: String, title_id: String, now_unix: int, rev: int, cozy: bool = false) -> Dictionary:
	var cd: Dictionary = combat.class_def()
	var hybrid := bool(cd.get("hybrid", false))
	var styles: Array = cd.get("styles", []) if hybrid else []
	var st0: Dictionary = CoopCombatAdapter.stats_for(combat, str(styles[0]) if hybrid and not styles.is_empty() else "")
	var sheet := {
		"uid": uid, "name": nm, "title": title_id, "issued": now_unix, "rev": rev,
		"dv": str(data.constants.get("data_version", "")),
		"class": str(combat.state["class"]), "spec": str(combat.state.get("spec", "")), "level": int(combat.hero_level()),
		"era": CoopCombatAdapter.era(combat), "cozy": cozy,
		"st": _stat_block(st0),
	}
	if hybrid:
		var alts := {}
		for sty in styles:
			alts[str(sty)] = _stat_block(CoopCombatAdapter.stats_for(combat, str(sty)))
		sheet["stances"] = alts
	var params: Dictionary = CoopCombatAdapter.sim_params(combat, st0)
	var tot := {}
	for key in SIM_TOTALS:
		tot[key] = float(params.tot.get(key, 0.0))
	sheet["tot"] = tot
	sheet["elem_add"] = _num_map(params.elem_add, ELEMENTS)
	sheet["elem_more"] = _num_map(params.elem_more, ELEMENTS)
	var ab_ids: Array = []
	for ab in combat.build.abilities_equipped():
		ab_ids.append(str(ab.id))
	sheet["abilities"] = ab_ids
	var rd: Dictionary = params.res_def
	sheet["res"] = {"id": str(rd.get("id", "")), "max": float(params.res_max)}
	return sheet


static func _stat_block(st: Dictionary) -> Dictionary:
	var out := {}
	for k in NUM_KEYS:
		out[k] = float(st.get(k, 0.0))
	out["style"] = str(st.get("style", "melee"))
	out["element"] = str(st.get("element", ""))
	out["revive_once"] = bool(st.get("revive_once", false))
	return out


static func _num_map(src: Dictionary, keys: PackedStringArray) -> Dictionary:
	var out := {}
	for k in keys:
		out[k] = float(src.get(k, 0.0))
	return out


# ====================================================================== validazione

## Ritorna {"ok", "sheet", "error", "clamped": n campi riportati ai limiti, "dropped": n id scartati}.
## `now_unix` serve solo per rifiutare date impossibili (nel futuro oltre la tolleranza degli orologi).
static func sanitize(raw: Variant, data: Object, now_unix: int) -> Dictionary:
	if not (raw is Dictionary):
		return _bad("shape")
	var r: Dictionary = raw
	for k in FORBIDDEN_KEYS:
		if r.has(k):
			return _bad("forbidden")
	var cr := rules(data)
	var lim: Dictionary = cr.limits
	var clamped := 0
	var dropped := 0
	var uid := _clean_id(r.get("uid"), 16)
	if uid.is_empty():
		return _bad("uid")
	var cls := str(r.get("class", ""))
	var cd: Dictionary = data.get_def("classes", cls)
	if cd.is_empty() or not (bool(cd.get("base", false)) or bool(cd.get("hybrid", false))):
		return _bad("class")
	var spec := str(r.get("spec", ""))
	if not spec.is_empty():
		var sd: Dictionary = data.get_def("classes", spec)
		if sd.is_empty() or str(sd.get("parent", "")) != cls:
			spec = ""
			dropped += 1
	var level_cap := int(data.constants.level_cap)
	var lv_raw := _num(r.get("level"), 1.0)
	var level := clampi(int(lv_raw), 1, level_cap)
	if level != int(lv_raw):
		clamped += 1
	var issued := int(_num(r.get("issued"), 0.0))
	if issued <= 0:
		return _bad("date")
	var slack := int(cr.companions.future_slack_s)
	if now_unix > 0 and issued > now_unix + slack:
		return _bad("future")
	var sheet := {
		"uid": uid, "name": clean_name(str(r.get("name", "")), int(cr.code.name_max)), "title": "",
		"issued": issued, "rev": clampi(int(_num(r.get("rev"), 1.0)), 0, 1000000),
		"dv": str(r.get("dv", "")).substr(0, 24), "class": cls, "spec": spec, "level": level,
		"era": clampi(int(_num(r.get("era"), 1.0)), 1, 1000),
		"cozy": bool(r.get("cozy", false)) if r.get("cozy") is bool else false,
	}
	var tid := str(r.get("title", ""))
	if not tid.is_empty() and not data.get_def("titles", tid).is_empty():
		sheet["title"] = tid
	var ceil_v := limits_for(data, level)
	var st_in: Variant = r.get("st")
	if not (st_in is Dictionary):
		return _bad("stats")
	var sb := _clean_stats(st_in, ceil_v, lim, cls, cd, data, true)
	if sb.is_empty():
		return _bad("stats")
	clamped += int(sb.get("_clamped", 0))
	sb.erase("_clamped")
	sheet["st"] = sb
	if bool(cd.get("hybrid", false)):
		var alts := {}
		var raw_alts: Variant = r.get("stances")
		if raw_alts is Dictionary:
			for sty in cd.get("styles", []):
				if (raw_alts as Dictionary).has(sty) and (raw_alts[sty] is Dictionary):
					var one := _clean_stats(raw_alts[sty], ceil_v, lim, cls, cd, data, false)
					if not one.is_empty():
						clamped += int(one.get("_clamped", 0))
						one.erase("_clamped")
						alts[str(sty)] = one
		if alts.is_empty():
			alts[str(sb.style)] = sb
		sheet["stances"] = alts
	# totali per i buff delle abilità e bonus elementali: intervalli stretti
	var tot := {}
	var tot_in: Variant = r.get("tot")
	for key in SIM_TOTALS:
		var v := _num(tot_in.get(key) if tot_in is Dictionary else 0.0, 0.0)
		var c := clampf(v, -float(lim.tot_abs_max), float(lim.tot_abs_max))
		if c != v:
			clamped += 1
		tot[key] = c
	sheet["tot"] = tot
	var ea := {}
	var em := {}
	for el in ELEMENTS:
		var a_v := _num((r.get("elem_add") as Dictionary).get(el) if r.get("elem_add") is Dictionary else 0.0, 0.0)
		var a_c := clampf(a_v, 0.0, float(lim.tot_abs_max))
		var m_v := _num((r.get("elem_more") as Dictionary).get(el) if r.get("elem_more") is Dictionary else 1.0, 1.0)
		var m_c := clampf(m_v, 1.0, float(lim.elem_more_max))
		if a_c != a_v or m_c != m_v:
			clamped += 1
		ea[el] = a_c
		em[el] = m_c
	sheet["elem_add"] = ea
	sheet["elem_more"] = em
	# abilità: solo id esistenti, della classe o della specializzazione (anche della sua), nel numero degli slot
	var owners: Array = [cls]
	if not spec.is_empty():
		owners.append(spec)
	var slots := int(Formulas.k().combat.rules.ability_slots)
	var ab_ids: Array = []
	if r.get("abilities") is Array:
		for aid in r.abilities:
			var ad: Dictionary = data.get_def("abilities", str(aid))
			if ad.is_empty() or not owners.has(str(ad.get("class", ""))) or int(ad.get("level_req", 1)) > level \
					or ab_ids.has(str(aid)) or ab_ids.size() >= slots:
				dropped += 1
				continue
			ab_ids.append(str(aid))
	sheet["abilities"] = ab_ids
	var res_def: Dictionary = data.get_def("resources", str(cd.get("resource", "")))
	var res_in: Variant = r.get("res")
	var rmax := _num(res_in.get("max") if res_in is Dictionary else 0.0, 0.0)
	var rc := clampf(rmax, 0.0, float(lim.res_max_cap))
	if rc != rmax:
		clamped += 1
	sheet["res"] = {"id": str(res_def.get("id", "")), "max": rc if not res_def.is_empty() else 0.0}
	return {"ok": true, "sheet": sheet, "error": "", "clamped": clamped, "dropped": dropped}


static func _clean_stats(raw: Dictionary, ceil_v: Dictionary, lim: Dictionary, _cls: String, cd: Dictionary, _data: Object,
		primary: bool) -> Dictionary:
	var out := {}
	var clamped := 0
	for k in NUM_KEYS:
		var v := _num(raw.get(k), _default_stat(k))
		var hi := _hi(k, ceil_v, lim)
		var lo := _lo(k, ceil_v, lim)
		var c := clampf(v, lo, hi)
		if c != v:
			clamped += 1
		out[k] = c
	if float(out.hp) < 1.0 or float(out.interval) <= 0.0:
		return {}
	var style := str(raw.get("style", ""))
	if bool(cd.get("hybrid", false)):
		if not (cd.get("styles", []) as Array).has(style):
			if not primary:
				return {}
			style = str(cd.styles[0])
	elif not STYLES.has(style):
		style = str(cd.get("style", "melee"))
	out["style"] = style
	var el := str(raw.get("element", ""))
	out["element"] = el if ELEMENTS.has(el) else ""
	out["revive_once"] = bool(raw.get("revive_once", false)) if raw.get("revive_once") is bool else false
	out["_clamped"] = clamped
	return out


static func _default_stat(k: String) -> float:
	match k:
		"dmg_taken_mult", "dot_mult", "summon_mult", "res_mult":
			return 1.0
		"interval":
			return 2.0
	return 0.0


static func _lo(k: String, _c: Dictionary, lim: Dictionary) -> float:
	match k:
		"hp":
			return 1.0
		"dmg_taken_mult":
			return float(lim.dmg_taken_min)
		"dot_mult", "summon_mult", "res_mult":
			return 0.0
		"interval":
			return float(_c.interval_min)
		"min_ratio":
			return 0.0
	return 0.0


## Tetto di una statistica. Quelle grandi (hp, acc, eva, arm, ward, max_hit) dipendono dal livello (limits_for); le altre
## hanno tetti fissi dei dati (coop_rules.limits) o delle regole di combattimento.
static func _hi(k: String, c: Dictionary, lim: Dictionary) -> float:
	var kc: Dictionary = Formulas.k().combat
	match k:
		"hp", "acc", "eva", "arm", "ward", "max_hit":
			return float(c[k])
		"min_ratio":
			return 1.0
		"interval":
			return float(c.interval_max)
		"crit":
			return float(kc.crit_cap)
		"critd":
			return float(c.critd)
		"regen_pct":
			return float(lim.regen_pct_max)
		"lifesteal":
			return float(kc.rules.lifesteal_cap_pct) / 100.0
		"armor_pen":
			return 1.0
		"dmg_taken_mult":
			return float(lim.dmg_taken_max)
		"multihit":
			return float(kc.rules.multihit_cap_pct) / 100.0
		"status_resist", "heal_rx":
			return float(lim.pct_stats_max) / 100.0
		"thorns", "vs_bounty":
			return float(lim.pct_stats_max)
		"dot_mult", "summon_mult", "res_mult":
			return float(lim.elem_more_max) * 2.0
	return 1.0e12


## Tetti plausibili al livello `level`: l'Eroe con attributi e equipaggiamento migliori del gioco, per `headroom`.
## Stesse formule (Formulas.hero_stats) e stessi dati (data/items, data/classes) dell'Eroe vero.
static func limits_for(data: Object, level: int) -> Dictionary:
	var key := "%d|%s" % [level, str(data.constants.get("data_version", ""))]
	if _lim_cache.has(key):
		return _lim_cache[key]
	var kc: Dictionary = Formulas.k().combat
	var hero: Dictionary = kc.hero
	var lim: Dictionary = rules(data).limits
	var growth := {"str": 0.0, "dex": 0.0, "int": 0.0, "vit": 0.0}
	for c in data.table("classes"):
		if not (bool(c.get("base", false)) or bool(c.get("hybrid", false))):
			continue
		for a in growth:
			growth[a] = maxf(float(growth[a]), float(c.get("growth_per_level", {}).get(a, 0.0)) + float(c.get("auto_alloc", {}).get(a, 0.0)))
	var attrs := {}
	for a in growth:
		attrs[a] = float(hero.attr_base) + float(growth[a]) * level + float(hero.attr_points_per_level) * level
	# equipaggiamento: per ogni slot il massimo di ogni statistica (anelli due volte)
	var best: Dictionary = {}                  # slot -> {chiave: max}
	var w_dmg := 0.0
	var w_int := 99.0
	var crit_w := 0.0
	var req_ok := func(e: Dictionary) -> bool: return int(e.get("level_req", 1)) <= level
	for it in data.items_by_category("equipment"):
		var e: Dictionary = it.get("equipment", {})
		if e.is_empty() or not bool(req_ok.call(e)):
			continue
		var slot := str(e.get("slot", ""))
		if slot == "weapon":
			w_dmg = maxf(w_dmg, float(e.get("damage", 0.0)))
			w_int = minf(w_int, float(e.get("attack_interval_s", 2.0)))
			crit_w = maxf(crit_w, float(e.get("stats", {}).get("crit_chance", 0.0)))
		var b: Dictionary = best.get(slot, {})
		for sk in e.get("stats", {}):
			b[sk] = maxf(float(b.get(sk, 0.0)), float(e.stats[sk]))
		best[slot] = b
	var sum := {}
	for slot in best:
		var mult := 2.0 if slot == "ring" else 1.0
		for sk in best[slot]:
			sum[sk] = float(sum.get(sk, 0.0)) + float(best[slot][sk]) * mult
	sum["crit_chance"] = crit_w
	var ammo_dmg := 0.0
	for am in data.items_by_category("ammo"):
		ammo_dmg = maxf(ammo_dmg, float(am.get("ammo", {}).get("damage", 0.0)))
	var qmax := 1.0
	for q in data.constants.get("quality", []):
		qmax = maxf(qmax, float(q.mult))
	var gear := [{"slot": "weapon", "damage": maxf(w_dmg, 1.0), "min_ratio": 1.0, "attack_interval_s": maxf(w_int, 0.1),
		"stats": sum}]
	var out := {"hp": 0.0, "acc": 0.0, "eva": 0.0, "arm": 0.0, "ward": 0.0, "max_hit": 0.0, "critd": float(kc.crit_dmg_base),
		"interval_min": maxf(w_int, 0.1) * float(lim.min_interval_ratio), "interval_max": 20.0}
	for prim in ["str", "dex", "int"]:
		var s: Dictionary = Formulas.hero_stats(level, attrs, prim, "melee", gear, ammo_dmg, qmax, 1.0, [])
		for k in ["hp", "acc", "eva", "arm", "ward", "max_hit"]:
			out[k] = maxf(float(out[k]), float(s[k]))
	var hr := float(lim.headroom)
	for k in ["hp", "acc", "eva", "arm", "ward", "max_hit"]:
		out[k] = float(out[k]) * hr
	out["critd"] = float(kc.crit_dmg_base) + hr * 2.0
	_lim_cache[key] = out
	return out


# ====================================================================== utilità

static func signature(sheet: Dictionary) -> String:
	return CoopCodec.checksum(CoopCodec.canonical(sheet))


## Nome visibile: solo lettere, cifre, spazi e pochi segni; lunghezza massima; mai vuoto.
static func clean_name(raw: String, max_len: int) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 32 or c == 45 or c == 95 \
			or c == 39 or c == 46 or (c >= 0xC0 and c <= 0x24F and c != 0xD7 and c != 0xF7)
		if ok:
			out += String.chr(c)
	out = out.strip_edges()
	while out.contains("  "):
		out = out.replace("  ", " ")
	if out.length() > max_len:
		out = out.substr(0, max_len).strip_edges()
	return out if not out.is_empty() else "?"


static func _clean_id(v: Variant, max_len: int) -> String:
	var s := str(v) if v is String else ""
	if s.is_empty() or s.length() > max_len:
		return ""
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return ""
	return s


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
	return fallback


static func _bad(code: String) -> Dictionary:
	return {"ok": false, "sheet": {}, "error": code, "clamped": 0, "dropped": 0}
