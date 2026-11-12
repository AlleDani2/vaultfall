class_name CoopSim
extends RefCounted
## Potere REALE di un compagno (COOP-1): la sua Scheda gira nello stesso CombatSim dell'Eroe, in modalità «valori attesi»
## (nessun RNG), contro lo stesso nemico dell'incontro. Stesso motore del tick e dell'offline: abilità, risorse, buff,
## meccaniche del boss e Furia sono quelle vere. Il passaggio è lo stesso (passo `dt`) di EndgameCombat.boss_pass, quindi
## incursioni, boss mondiali e Breccia danno lo stesso potere in tempo reale e offline.
##
## Punteggio = frazione di vita del nemico tolta nella finestra `window_s`: chi lo batte conta 1/tempo, chi cade o non
## ce la fa conta quanto ha tolto diviso l'intera finestra. «Qualità» di un compagno = suo punteggio / punteggio del tuo
## Eroe (la stessa Scheda esportata dal tuo Eroe, stessa simulazione), con il tetto dei mercenari.

var _sim: CombatSim = CombatSim.new()
var _cache: Dictionary = {}


func clear_cache() -> void:
	_cache.clear()


func cache_size() -> int:
	return _cache.size()


## Statistiche per il motore a partire dal blocco della Scheda.
static func sim_stats(sheet: Dictionary, block: Dictionary) -> Dictionary:
	var st: Dictionary = block.duplicate(true)
	st["level"] = int(sheet.level)
	st["ap"] = 0.0
	st["needs_ammo"] = false
	st["has_ammo"] = true
	st["armed"] = true
	st["class"] = str(sheet["class"])
	st["spec"] = str(sheet.spec)
	st["attrs"] = {}
	return st


## Blocco di statistiche di partenza per un nemico (le ibride scelgono la postura come l'Eroe vero).
static func base_block(sheet: Dictionary, data: Object, mon: Dictionary) -> Dictionary:
	var alts: Variant = sheet.get("stances")
	if alts is Dictionary and not (alts as Dictionary).is_empty():
		var cd: Dictionary = data.get_def("classes", str(sheet["class"]))
		var ph: Variant = mon.get("phases")
		var mstyle := str(mon.get("style", ""))
		if ph is Array and (ph as Array).size() > 1:
			mstyle = str((ph as Array)[0].style)
		var pick := CombatSim.pick_stance(cd.get("styles", (alts as Dictionary).keys()), mstyle)
		if (alts as Dictionary).has(pick):
			return (alts as Dictionary)[pick]
	return sheet.st


## Un solo scontro della Scheda contro `mon`/`ms`. Ritorna {"score", "won", "died", "t", "dealt_frac", "hp_end"}.
## `cache_key` ("" = nessuna cache) evita di rifare la stessa simulazione.
func run(sheet: Dictionary, combat: Object, mon: Dictionary, ms: Dictionary, window_s: float, dt: float, min_score: float,
		cache_key: String = "") -> Dictionary:
	if cache_key != "" and _cache.has(cache_key):
		return _cache[cache_key]
	var data: Object = combat.ctx.data
	var k: Dictionary = Formulas.k().combat
	var block := base_block(sheet, data, mon)
	var st := sim_stats(sheet, block)
	var abil: Array = []
	for aid in sheet.abilities:
		var ad: Dictionary = data.get_def("abilities", str(aid))
		if not ad.is_empty():
			abil.append(ad)
	var rd: Dictionary = data.get_def("resources", str(sheet.res.id))
	var st_alt := {}
	var ph: Variant = mon.get("phases")
	if sheet.get("stances") is Dictionary and ph is Array and (ph as Array).size() > 1:
		for sty in sheet.stances:
			st_alt[str(sty)] = sim_stats(sheet, sheet.stances[sty])
	_sim.configure({"expect": true, "rng": null, "st": st, "tot": sheet.tot, "elem_add": sheet.elem_add, "elem_more": sheet.elem_more,
		"mon": mon, "ms": ms, "rules": k.rules, "mech": combat.mechanics(), "abilities": abil, "forced_dis": false,
		"st_alt": st_alt, "res_def": rd, "res_max": float(sheet.res.max), "res_mult": float(st.res_mult),
		"mon_avg_ratio": float(k.sim_assumptions.monster_avg_hit_ratio), "crit_cap": float(k.crit_cap)})
	_sim.rng = null
	_sim.reset_acc()
	var mx := float(st.hp)
	var h := {"hp": mx, "rt": CombatSim.new_rt()}
	var a := {"enemy": {}, "hero_cd": 0.0, "mon_cd": 0.0}
	_sim.spawn(h, a, 1.0, 1.0)
	var e: Dictionary = a.enemy
	if CoopCombatAdapter.sim_phased(_sim):
		CoopCombatAdapter.sim_check_phase(_sim, e)
	var t := 0.0
	var dealt := 0.0
	var r := CombatSim.R_NONE
	var cap_t := maxf(window_s, dt)
	while t < cap_t:
		_sim.tick_timers(h, dt, true)
		if float(h.hp) < mx:
			CoopCombatAdapter.est_regen(combat, h, _sim, st, dt)
		var before := maxf(float(e.hp), 0.0)
		r = _sim.step(h, a, dt)
		t += dt
		dealt += maxf(0.0, before - maxf(float(e.hp), 0.0))
		if r != CombatSim.R_NONE:
			break
	var frac := clampf(dealt / maxf(float(e.max), 1.0), 0.0, 1.0)
	var won := r == CombatSim.R_KILL
	var score := frac / maxf(t, dt) if won else frac / cap_t
	var out := {"score": maxf(score, 0.0) if score > min_score else 0.0, "won": won, "died": r == CombatSim.R_DIE, "t": t,
		"dealt_frac": frac, "hp_end": maxf(float(h.hp), 0.0)}
	if cache_key != "":
		_cache[cache_key] = out
	return out
