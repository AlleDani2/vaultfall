class_name Formulas
extends RefCounted
## Formule di gioco portate 1:1 da tools/gamedata/core.py e tools/balance_sim.py (docs/17 §7).
## Verificate da tests/test_formulas.gd su TUTTI i casi di tests/reference_values.json.
##
## Nessun numero di bilanciamento qui: le costanti arrivano da data/constants.json tramite
## Formulas.configure(), chiamata da DataRegistry all'avvio (e dai test).
## Anche i coefficienti che prima erano un blocco PENDING_CONSTANTS (stelle, Tenuta, derivazione dei mostri, qualità, valori
## delle Casse) ora arrivano da constants.json (generato da tools/gamedata/core.py::constants): nessun numero qui.

static var _k: Dictionary = {}


## Imposta le costanti (constants.json) + eventuali extra ricavati da altri file di dati.
## Le chiavi di constants.json hanno la precedenza su quelle di extras.
static func configure(constants: Dictionary, extras: Dictionary = {}) -> void:
	var merged: Dictionary = {}
	_deep_merge(merged, extras)
	_deep_merge(merged, constants)
	_k = merged


static func is_configured() -> bool:
	return not _k.is_empty()


## Accesso in sola lettura alle costanti unite (per i sistemi che vogliono leggere un parametro).
static func k() -> Dictionary:
	return _k


static func _deep_merge(dst: Dictionary, src: Dictionary) -> void:
	for key in src:
		if dst.has(key) and dst[key] is Dictionary and src[key] is Dictionary:
			_deep_merge(dst[key], src[key])
		else:
			dst[key] = src[key] if not (src[key] is Dictionary or src[key] is Array) else src[key].duplicate(true)


# ------------------------------------------------------------------ arrotondamenti (core.rhalf / rdec)

## Interi "sicuri" (QA4 #12, come core.INT_LIMIT): ogni intero derivato da un float satura a +-2^62, NaN -> 0
## (niente conversioni silenziose a -9.223.372.036.854.775.808 oltre 2^63).
const INT_LIMIT := 4611686018427387904


static func _sat(v: float) -> int:
	if is_nan(v):
		return 0
	if v >= float(INT_LIMIT):
		return INT_LIMIT
	if v <= -float(INT_LIMIT):
		return -INT_LIMIT
	return int(v)


## floor() intero saturato (core.ifloor).
static func ifloor(x: float) -> int:
	if is_nan(x):
		return 0
	if absf(x) >= float(INT_LIMIT):
		return _sat(x)
	return int(floor(x))


## Intero con le metà per eccesso (lontano da zero per i negativi), come core.rhalf (saturato a +-2^62, NaN -> 0).
static func rhalf(x: float) -> int:
	if is_nan(x):
		return 0
	if absf(x) >= float(INT_LIMIT):
		return _sat(x)
	if x >= 0.0:
		return int(floor(x + 0.5))
	return -int(floor(-x + 0.5))


static func rdec(x: float, nd: int) -> float:
	var f := pow(10.0, nd)
	return rhalf(x * f) / f


## Valori "puliti" (2-3 cifre significative) per prezzi e costi.
static func round_nice(x: float) -> int:
	if not x >= 100.0:                # anche NaN
		return maxi(1, rhalf(x))
	if x >= float(INT_LIMIT):
		return INT_LIMIT
	var digits := str(int(x)).length()
	var mag := int(pow(10.0, digits - 2))
	return rhalf(x / mag) * mag


# ------------------------------------------------------------------ livelli e XP

static func xp_to_next(level: int) -> int:
	return ifloor(float(_k.xp.base) * pow(float(_k.xp.growth), level))


## XP totali per ESSERE al livello L (L=1 -> 0).
static func xp_total_for_level(level: int) -> int:
	var tot := 0
	for l in range(1, level):
		tot += xp_to_next(l)
	return tot


static func tier_of_level(level: int) -> int:
	var t := 1
	var levels: Array = _k.tier_levels
	for i in levels.size():
		if level >= int(levels[i]):
			t = i + 1
	return t


static func xph(tier: int) -> float:
	return float(_k.xph.base) * pow(float(_k.xph.growth), tier - 1)


static func gph(tier: int) -> float:
	return float(_k.gph.base) * pow(float(_k.gph.growth), tier - 1)


static func raw_value(tier: int, action_time_s: float) -> int:
	return maxi(1, rhalf(gph(tier) * action_time_s / 3600.0))


static func mastery_to_next(m: int) -> int:
	return ifloor(float(_k.mastery.base) * pow(float(_k.mastery.growth), m))


# ------------------------------------------------------------------ Stelle, Eco, Ere

static func star_curve(cap: float, decay: float, stars: int) -> float:
	return cap * (1.0 - pow(decay, stars))


static func star_xp_pct(stars: int) -> float:
	return star_curve(float(_k.stars.xp_cap_pct), float(_k.stars.xp_decay), stars)


static func star_haste_pct(stars: int) -> float:
	return star_curve(float(_k.stars.haste_cap_pct), float(_k.stars.haste_decay), stars)


static func stardust_for_star(star_index: int) -> int:
	return int(_k.stars.stardust_base) + int(_k.stars.stardust_step) * (star_index - 1)


static func echo_multiplier(level: int, record: int) -> float:
	if record <= level:
		return 1.0
	var ratio := float(level) / float(record)
	var e: Dictionary = _k.stars.echo
	var th: Dictionary = _k.stars.echo_ratio
	if ratio < float(th.below_50pct_of_record):
		return float(e.below_50pct_of_record)
	if ratio < float(th.below_90pct):
		return float(e.below_90pct)
	return float(e.below_record)


static func era_monster_mult(era: int) -> float:
	return pow(float(_k.eras.monster_mult), era - 1)


static func era_reward_mult(era: int) -> float:
	return 1.0 + float(_k.eras.reward_add) * (era - 1)


## Essenza d'Era per salire AL rango r (core.rank_essence_cost, G03): ceil(base + per_rank·r).
static func rank_essence_cost(r: int) -> int:
	var c: Dictionary = _k.eras.rank_cost
	return int(ceil(float(c.essence_base) + float(c.essence_per_rank) * r - 1e-9))


## Oro per salire AL rango r un oggetto di tier `tier` (core.rank_gold_cost): per_tier·tier·(1 + r/rank_div).
static func rank_gold_cost(tier: int, r: int) -> int:
	var c: Dictionary = _k.eras.rank_cost
	return roundi(float(c.gold_per_tier) * tier * (1.0 + float(r) / float(c.gold_rank_div)))


# ------------------------------------------------------------------ Tenuta

static func soci_total(lifetime_units: float) -> int:
	return ifloor(float(_k.estate.soci_coeff) * sqrt(maxf(0.0, lifetime_units) / float(_k.estate.soci_divisor)))


static func estate_milestone_mult(level: int) -> int:
	var n := 0
	for m in _k.estate.milestones:
		if level >= int(m):
			n += 1
	return int(pow(float(_k.estate.milestone_mult), n))


static func estate_units_per_hour(level: int) -> float:
	if level <= 0:
		return 0.0
	return float(_k.estate.units_per_level) * level * estate_milestone_mult(level)


static func estate_cost_gold(level: int, band_tier: int) -> int:
	return round_nice(float(_k.estate.cost_base) * pow(float(_k.estate.cost_growth), level)
		* pow(float(_k.estate.band_cost_growth), band_tier - 1))


# ------------------------------------------------------------------ combattimento (core.py)

static func hit_chance(acc: float, eva: float) -> float:
	var c: Dictionary = _k.combat
	# guardie (QA4 #12, come core.hit_chance): NaN o precisione <= 0 -> minimo; evasione <= 0 -> massimo; inf/inf -> minimo
	if is_nan(acc) or is_nan(eva):
		return float(c.hit_min)
	if eva <= 0.0:
		return float(c.hit_max)
	if acc <= 0.0:
		return float(c.hit_min)
	var r := acc / eva
	if is_nan(r):
		return float(c.hit_min)
	return maxf(float(c.hit_min), minf(float(c.hit_max), float(c.hit_base) * sqrt(r)))


static func dr_k(monster_level: float) -> float:
	return float(_k.combat.dr_k.a) * pow(float(_k.combat.dr_k.r), monster_level)


static func damage_reduction(armor: float, attacker_level: float) -> float:
	if is_nan(armor) or armor <= 0.0:
		return 0.0
	if is_inf(armor):
		return float(_k.combat.dr_cap)
	return minf(float(_k.combat.dr_cap), armor / (armor + dr_k(attacker_level)))


static func triangle_mult(att_style: String, def_style: String) -> float:
	var t: Dictionary = _k.combat.triangle
	var beats: Dictionary = t.beats
	if att_style.is_empty() or def_style.is_empty():     # stile mancante: nessun vantaggio (QA4 #12)
		return 1.0
	if beats.get(att_style, "") == def_style:
		return float(t.advantage)
	if beats.get(def_style, "") == att_style:
		return float(t.disadvantage)
	return 1.0


static func hero_hp(vit: float, level: int, gear_hp: float, hp_pct: float = 0.0) -> float:
	var c: Dictionary = _k.combat.hero.coef.hp
	return (float(c.base) + float(c.vit) * vit + float(c.level) * level + gear_hp) * (1.0 + hp_pct / 100.0)


static func hero_ap(primary: float, gear_ap: float) -> float:
	return float(_k.combat.hero.coef.ap.primary) * primary + gear_ap


static func hero_acc(level: int, primary: float, gear_acc: float) -> float:
	var c: Dictionary = _k.combat.hero.coef.acc
	return float(c.base) + float(c.level) * level + float(c.primary) * primary + gear_acc


static func hero_eva(level: int, des: float, gear_eva: float) -> float:
	var c: Dictionary = _k.combat.hero.coef.eva
	return float(c.base) + float(c.level) * level + float(c.dex) * des + gear_eva


static func max_hit(weapon_dmg: float, ap: float, dmg_pct: float = 0.0) -> float:
	return weapon_dmg * (1.0 + ap / 100.0) * (1.0 + dmg_pct / 100.0)


static func monster_stats(level: int, mtype: String = "normal") -> Dictionary:
	var c: Dictionary = _k.combat
	var t: Dictionary = c.monster_types[mtype]
	var cv: Dictionary = c.monster_curves
	var d: Dictionary = c.monster_derivation
	var hp := float(cv.hp[0]) * pow(float(cv.hp[1]), level) * float(t.hp)
	var mh := float(cv.max_hit[0]) * pow(float(cv.max_hit[1]), level) * float(t.dmg)
	var acc := (float(cv.acc[0]) + float(cv.acc[1]) * level) * float(t.acc)
	var eva := (float(cv.eva[0]) + float(cv.eva[1]) * level) * float(t.eva)
	var arm := float(cv.arm[0]) * pow(float(cv.arm[1]), level) * float(t.arm)
	var lv_t := 1.0 + (maxi(1, level) - 1) / float(d.levels_per_tier)
	var cycle := (float(c.ttk_target_s) + float(c.respawn_s)) / 3600.0
	var xp := float(_k.xph.base) * pow(float(_k.xph.growth), lv_t - 1.0) * cycle * float(t.xp)
	var gold := float(_k.gph.base) * pow(float(_k.gph.growth), lv_t - 1.0) * cycle * float(d.gold_share) * float(t.gold)
	return {
		"hp": rhalf(hp), "max_hit": rhalf(mh), "accuracy": rhalf(acc), "evasion": rhalf(eva),
		"armor": rhalf(arm), "ward": rhalf(arm), "attack_interval_s": float(t.interval_s),
		"xp": maxi(int(d.xp_floor), rhalf(xp)),
		"gold_min": maxi(int(d.gold_min_floor), rhalf(gold * float(d.gold_min_mult))),
		"gold_max": maxi(int(d.gold_max_floor), rhalf(gold * float(d.gold_max_mult))),
	}


## Velocità d'attacco effettiva (core.effective_haste_pct, resoconto 91): lineare fino al tetto morbido, poi metà, tetto duro.
static func effective_haste_pct(add_pct: float) -> float:
	if is_nan(add_pct):
		return 0.0
	var h: Dictionary = (_k.combat.rules as Dictionary).get("haste_cap", {})
	if h.is_empty() or add_pct <= float(h.soft_pct):
		return add_pct
	return minf(float(h.hard_pct), float(h.soft_pct) + (add_pct - float(h.soft_pct)) * float(h.soft_slope))


## XP ridotta sui mostri molto sotto il livello dell'Eroe (core.overlevel_xp_mult, QA4 #5).
static func overlevel_xp_mult(hero_level: int, monster_level: int) -> float:
	var o: Dictionary = (_k.combat.rules as Dictionary).get("overlevel_xp", {})
	if o.is_empty() or monster_level >= int(o.exempt_from_level):
		return 1.0
	var gap := hero_level - monster_level - int(o.grace_levels)
	if gap <= 0:
		return 1.0
	return maxf(float(o.min_pct) / 100.0, 1.0 - gap * float(o.pct_per_level) / 100.0)


static func food_heal(tier: int) -> int:
	var f: Array = _k.combat.food_heal
	return rhalf(float(f[0]) * pow(float(f[1]), tier - 1))


static func weapon_damage(tier: int, mult: float) -> int:
	return rhalf(float(_k.combat.weapon_damage_base) * pow(float(_k.combat.gear_growth), tier - 1) * mult)


## Sabbia del Custode (core.push_regen): riserva ricaricata in `dt` secondi contati a `pct` % (online/offline dai dati).
static func push_regen(dt: float, pct: float) -> float:
	if not (dt > 0.0) or not (pct > 0.0):
		return 0.0
	return dt * pct / 100.0


## Sabbia del Custode (core.push_spend): tempo speso da un clic = min(riserva, secondi per clic), mai negativo.
static func push_spend(reserve_s: float, click_s: float) -> float:
	if not (reserve_s > 0.0) or not (click_s > 0.0):
		return 0.0
	return minf(reserve_s, click_s)


static func set_value(base: float, tier: int) -> float:
	return base * pow(float(_k.combat.gear_growth), tier - 1)


## Statistiche dell'eroe a partire dagli attributi (già allocati) e dall'equipaggiamento indossato.
## gear: Array dei blocchi "equipment" degli oggetti (items/*.json). Porta 1:1 di balance_sim.hero_stats
## (la scelta dell'equipaggiamento "standard" del simulatore resta nel test, non è una regola di gioco).
static func hero_stats(level: int, attrs_in: Dictionary, primary: String, style: String, gear: Array,
		ammo_damage: float = 0.0, quality_mult: float = 1.0, rank_mult: float = 1.0,
		rank_stats: Array = []) -> Dictionary:
	var c: Dictionary = _k.combat
	var attrs: Dictionary = attrs_in.duplicate()
	var st := {}
	var mods := {}
	var weapon: Dictionary = {}
	for eq in gear:
		var stats: Dictionary = eq.get("stats", {})
		for key in stats:
			var v: float = float(stats[key])
			var rk := rank_mult if rank_stats.has(key) else 1.0
			var qm := quality_mult if key != "crit_chance" else 1.0
			st[key] = float(st.get(key, 0.0)) + v * qm * rk
		for m in eq.get("modifiers", []):
			mods[m.key] = float(mods.get(m.key, 0.0)) + float(m.value)
		if eq.get("slot", "") == "weapon":
			weapon = eq
	for a in ["str", "dex", "int", "vit"]:
		attrs[a] = float(attrs.get(a, 0.0)) + float(st.get(a, 0.0))
	var prim: float = attrs[primary]
	var cf: Dictionary = c.hero.coef
	var hp := (float(cf.hp.base) + float(cf.hp.vit) * float(attrs.vit) + float(cf.hp.level) * level + float(st.get("hp", 0.0))) \
		* (1.0 + float(mods.get("combat_hp_pct", 0.0)) / 100.0)
	var ap := float(cf.ap.primary) * prim + float(st.get("ap", 0.0))
	var acc := float(cf.acc.base) + float(cf.acc.level) * level + float(cf.acc.primary) * prim + float(st.get("accuracy", 0.0))
	var eva := float(cf.eva.base) + float(cf.eva.level) * level + float(cf.eva.dex) * float(attrs.dex) + float(st.get("evasion", 0.0))
	var wd := float(weapon.damage) * quality_mult * rank_mult + ammo_damage
	var mh := wd * (1.0 + ap / 100.0) * (1.0 + float(mods.get("combat_dmg_pct", 0.0)) / 100.0)
	var wstats: Dictionary = weapon.get("stats", {})
	var crit := float(c.crit_base) + float(wstats.get("crit_chance", 0.0)) + float(mods.get("combat_crit_chance_pct", 0.0)) / 100.0
	var critd := float(c.crit_dmg_base) + float(mods.get("combat_crit_dmg_pct", 0.0)) / 100.0
	var def_mult := 1.0 + float(mods.get("combat_defense_pct", 0.0)) / 100.0
	return {"hp": hp, "ap": ap, "acc": acc, "eva": eva, "arm": float(st.get("armor", 0.0)) * def_mult,
		"ward": float(st.get("ward", 0.0)) * def_mult, "max_hit": mh, "min_ratio": float(weapon.min_ratio),
		"interval": float(weapon.attack_interval_s), "crit": crit, "critd": critd, "style": style, "level": level}


## Stima analitica di uno scontro (balance_sim.fight): DPS, TTK, tempo alla morte (INF se non si muore).
static func fight_estimate(h: Dictionary, m: Dictionary, era_mult: float = 1.0) -> Dictionary:
	var c: Dictionary = _k.combat
	var ms: Dictionary = m.stats
	var mhp := float(ms.hp) * era_mult
	var m_def := float(ms.armor) if h["style"] != "arcane" else float(ms.ward)
	var p_hit := _sim_hit(float(h.acc), float(ms.evasion) * era_mult)
	var avg := float(h.max_hit) * (1.0 + float(h.min_ratio)) / 2.0
	var p_dps := p_hit * avg * (1.0 + float(h.crit) * (float(h.critd) - 1.0)) \
		* (1.0 - damage_reduction(m_def * era_mult, float(h.level))) * triangle_mult(h["style"], m["style"]) \
		/ float(h.interval) * float(c.sim_assumptions.ability_dps_factor)
	var m_hit := _sim_hit(float(ms.accuracy) * era_mult, float(h.eva))
	var p_def := float(h.arm) if m.damage_type == "physical" else float(h.ward)
	var m_avg := float(ms.max_hit) * era_mult * float(c.sim_assumptions.monster_avg_hit_ratio)
	var m_dps := m_hit * m_avg * (1.0 - damage_reduction(p_def, float(m.level))) * triangle_mult(m["style"], h["style"]) \
		/ float(ms.attack_interval_s)
	var ttk := mhp / p_dps
	var regen := float(h.hp) * float(c.hero.regen_base_pct_per_s) / 100.0
	var ttd := INF
	if m_dps > regen:
		ttd = float(h.hp) / maxf(1e-9, m_dps - regen)
	return {"ttk": ttk, "p_hit": p_hit, "m_hit": m_hit, "dmg_per_kill": m_dps * ttk, "m_dps": m_dps, "p_dps": p_dps,
		"regen": regen, "net_dps_taken": maxf(0.0, m_dps - regen), "time_to_die": ttd}


static func _sim_hit(acc: float, eva: float) -> float:
	var c: Dictionary = _k.combat
	return maxf(float(c.hit_min), minf(float(c.hit_max), float(c.hit_base) * sqrt(acc / maxf(1e-9, eva))))


# ------------------------------------------------------------------ qualità di creazione

## Probabilità [normale, fine, eccellente, capolavoro].
static func quality_chances(levels_above_req: int, mastery: int) -> Array:
	var q: Dictionary = _k.quality_chances
	var d := float(maxi(0, levels_above_req))
	var m := float(maxi(0, mastery))
	var master := _q_part(q.masterwork, d, m)
	var exc := _q_part(q.excellent, d, m)
	var fine := _q_part(q.fine, d, m)
	var normal := maxf(0.0, 1.0 - master - exc - fine)
	var nd := int(q.decimals)
	return [rdec(normal, nd), rdec(fine, nd), rdec(exc, nd), rdec(master, nd)]


static func _q_part(p: Dictionary, d: float, m: float) -> float:
	return minf(float(p.cap), float(p.base) + float(p.per_level) * d + float(p.per_mastery) * m)


# ------------------------------------------------------------------ casse (docs/09)

static func key_econ_tier(key_tier: int) -> int:
	return int(_k.crates.key_econ_tier[str(key_tier)])


static func skin_value(key_tier: int, rarity: String) -> int:
	var cr: Dictionary = _k.crates
	return round_nice(gph(key_econ_tier(key_tier)) * float(cr.skin_value_fraction_of_gph) * float(cr.rarity_value_mult[rarity]))


static func key_shop_price(key_tier: int) -> int:
	return round_nice(gph(key_econ_tier(key_tier)) * float(_k.crates.key_shop_fraction_of_gph))


## Probabilità nominale (%) di una rarità da constants.crates.rarities ([id, peso%, colore, simbolo, bonus]).
static func rarity_weight_pct(rarity: String) -> float:
	for r in _k.crates.rarities:
		if r[0] == rarity:
			return float(r[1])
	return 0.0


## Calcolo esatto della pity: [aperture medie tra due ★, probabilità effettiva della ★].
static func relic_pity_stats(base_pct: float = -1.0) -> Array:
	var p_cfg: Dictionary = _k.crates.pity
	var soft_start := int(p_cfg.soft_start)
	var soft_step := float(p_cfg.soft_step)
	var hard := int(p_cfg.hard)
	var base := (base_pct if base_pct >= 0.0 else rarity_weight_pct("relic")) / 100.0
	var surv := 1.0
	var mean := 0.0
	for since in hard:
		var p: float
		if since + 1 >= hard:
			p = 1.0
		else:
			p = minf(1.0, base + (soft_step * (since - soft_start + 1) if since >= soft_start else 0.0))
		mean += surv
		surv *= (1.0 - p)
	return [mean, 1.0 / mean]


static func relic_pity_mean_openings() -> float:
	return relic_pity_stats()[0]


static func relic_pity_effective_rate() -> float:
	return relic_pity_stats()[1]


## Probabilità effettive delle rarità sul lungo periodo, pity inclusa (docs/09 §4).
static func effective_rarity_pct() -> Dictionary:
	var eff_relic: float = relic_pity_stats()[1]
	var nominal_relic := rarity_weight_pct("relic") / 100.0
	var kk := (1.0 - eff_relic) / (1.0 - nominal_relic)
	var out := {}
	for r in _k.crates.rarities:
		var w := float(r[1]) / 100.0
		out[r[0]] = rdec(100.0 * (eff_relic if r[0] == "relic" else w * kk), 3)
	return out


## Probabilità (%) di ogni condizione per una finitura con intervallo [float_min, float_max] (docs/09 §5).
static func condition_odds(float_min: float, float_max: float) -> Dictionary:
	var reach: Array = []
	var tot := 0.0
	for c in _k.crates.conditions:
		if minf(float(c[2]), float_max) - maxf(float(c[1]), float_min) > 1e-9:
			reach.append(c)
			tot += float(c[3])
	var out := {}
	for c in reach:
		out[c[0]] = rdec(100.0 * float(c[3]) / tot, 2)
	return out
