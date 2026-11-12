class_name CombatSim
extends RefCounted
## Motore dello scontro (docs/05): UN SOLO codice per il combattimento reale a tick e per la stima offline.
##   expect = false  ->  RNG vero (flusso "combat"): colpi, critici, schivate estratti a caso.
##   expect = true   ->  "valori attesi": ogni evento casuale pesa per la sua probabilità, nessun RNG.
## La stima offline (CombatSystem.estimate) fa girare questo stesso motore in modalità attesa su uno scontro
## ripetuto: abilità, risorse, ricariche, buff, DoT, evocazioni, meccaniche dei boss e Furia sono quindi
## modellate dalle stesse regole del tick vero e lo scarto tra tick e offline resta piccolo (docs/05 §12).
##
## Il motore NON conosce sistemi né stato globale: CombatSystem gli passa i parametri con configure() e gli
## stati vivi (h = sezione `hero`, a = `activity`) a ogni passo. Nessun numero di bilanciamento qui: costanti da
## data/constants.json (regole), data/abilities.json, data/resources.json, data/boss_mechanics.json.
##
## Stato dell'eroe usato (h.rt, salvato col resto di `hero`):
##   res (risorsa corrente) · cd {abilità: secondi} · buffs {id: {left, mods}} · summons {id: {left, w, el}}
##   shield / shield_s (scudo assorbente) · revived (rinascita già usata in questo scontro)
## Stato del nemico (a.enemy): id, hp, max, t{meccanica: secondi}, shield_s, poison_s, deb{}, dots{}, adds[],
##   slow_s, slow_pct, adds_done, dmg_mult, bounty.

const EPS := 1e-6
const MAX_SWINGS_PER_TICK := 6
const R_NONE := 0
const R_KILL := 1
const R_DIE := 2
const R_STOP := 3
## Tipi di estrazione per la stima stratificata (StratifiedRng.randk): con l'RNG vero non cambiano nulla.
const K_HIT := 0
const K_DMG := 1
const K_CRIT := 2
const K_MHIT := 3
const K_MDMG := 4
const K_MULTI := 5
const K_ADMG := 6
const K_ACRIT := 7
const K_EXTRA := 8          # secondo colpo (multicolpo): K_EXTRA, +1 danno, +2 critico

## --- parametri (CombatSystem.configure)
var expect: bool = false
var rng: Variant = null              # RngStreams (reale) o StratifiedRng (stima Monte Carlo stratificata)
var st: Dictionary = {}                 # statistiche dell'eroe SENZA i buff delle abilità
var tot: Dictionary = {}                # famiglia -> totale add dei modificatori (per i rapporti dei buff)
var elem_add: Dictionary = {}           # elemento -> totale add di element_dmg_pct
var elem_more: Dictionary = {}          # elemento -> moltiplicatore more
var mon: Dictionary = {}
var ms: Dictionary = {}
var rules: Dictionary = {}
var mech: Dictionary = {}               # id meccanica -> definizione (boss_mechanics.json)
var abilities: Array = []               # abilità equipaggiate in ordine di priorità
var res_def: Dictionary = {}
var res_max: float = 100.0
var res_mult: float = 1.0
var mon_avg_ratio: float = 0.7          # colpo medio del mostro / colpo massimo (sim_assumptions)
var crit_cap: float = 0.75
var sink: Callable = Callable()         # registro per la UI (solo modalità reale)
var ammo_cb: Callable = Callable()      # () -> bool: consuma una munizione (solo reale)
var oil_cb: Callable = Callable()       # () -> void: consuma un olio per colpo andato a segno (solo reale)
var potion_cb: Callable = Callable()    # () -> void: una carica della pozione per attacco (solo reale)
var eat_cb: Callable = Callable()       # () -> void: auto-mangiare (reale: CombatSystem; attesa: contatore)
var acc: Dictionary = {}                # contatori della modalità attesa

var _eff: Dictionary = {}
var _eff_ok: bool = false
var _min_ratio_mon: float = 0.4
var _res_on: bool = false
var _res_per_s: float = 0.0
var _res_decay: float = 0.0
var _mon_mech: bool = false             # il mostro ha meccaniche periodiche
var _has_free: bool = false             # almeno un'abilità con condizione (scatta a ogni tick)
var _has_buffs: bool = false            # almeno un potenziamento (buff/debuff/scudo senza condizione): gratuito con l'attacco
var forced_dis: bool = false            # Prova «triangolo sempre sfavorevole»: l'eroe è sempre in svantaggio
var _phased: bool = false               # incursione: stile del boss per fase (cambio al 66% e al 33%)
var _phases: Array = []
var st_alt: Dictionary = {}             # classi ibride negli scontri a fasi: stile -> statistiche di quella postura (COMBAT-3)
var _st_base: Dictionary = {}           # statistiche di partenza (postura iniziale), da ripristinare a ogni nuovo nemico
var _swapped: bool = false              # la postura è cambiata durante lo scontro
var _strat: StratifiedRng = null        # RNG stratificato della stima (null = RNG vero)
var _mon_ls: float = 0.0                # rubavita del mostro (affisso Vampirici), frazione del danno inflitto
## Misura della stima con "pesi di sopravvivenza" (FIX-COMBATTIMENTO, QA4 #1): a ogni colpo del mostro si moltiplica la
## probabilità esatta di sopravvivere a quel colpo (dalla vita attuale e dalla distribuzione del danno) e il percorso
## continua estraendo il colpo condizionato alla sopravvivenza. `surv` = probabilità di essere ancora vivi nello scontro:
## la frazione di scontri persi si stima senza il rumore binario dell'esito (molta meno varianza a parità di cicli).
var surv_mode: bool = false
var surv: float = 1.0


func _init() -> void:
	reset_acc()


static func new_rt() -> Dictionary:
	return {"res": 0.0, "cd": {}, "buffs": {}, "summons": {}, "shield": 0.0, "shield_s": 0.0, "revived": false}


func reset_acc() -> void:
	acc = {"swings": 0.0, "hits": 0.0, "dmg_in": 0.0, "heal": 0.0, "casts": 0.0, "food": 0.0, "time": 0.0}


## `p`: st, tot, elem_add, elem_more, mon, ms, rules, mech, abilities, res_def, res_max, res_mult, rng, expect, ...
func configure(p: Dictionary) -> void:
	for k in p:
		set(k, p[k])
	_min_ratio_mon = 2.0 * mon_avg_ratio - 1.0
	_res_on = not res_def.is_empty()
	if _res_on:
		_res_per_s = float(res_def.get("regen_per_s", 0.0)) * res_mult
		_res_per_s += float(res_def.get("regen_pct_per_s", 0.0)) / 100.0 * res_max * res_mult
		_res_decay = float(res_def.get("decay_out_of_combat_per_s", 0.0))
	_mon_mech = mon.has("mechanics") and not (mon.mechanics as Array).is_empty()
	_phases = mon.get("phases", []) if mon.get("phases") is Array else []
	_phased = _phases.size() > 1
	_mon_ls = float(mon.get("lifesteal_pct", 0.0)) / 100.0
	_strat = rng as StratifiedRng
	_st_base = st
	_swapped = false
	_has_free = false
	_has_buffs = false
	for ab in abilities:
		if (ab.effect as Dictionary).has("trigger"):
			_has_free = true
		elif is_boost(ab):
			_has_buffs = true
	_eff_ok = false


func invalidate() -> void:
	_eff_ok = false


# ====================================================================== statistiche effettive (con i buff)

func _bf(rt: Dictionary) -> Dictionary:
	var out := {}
	for id in rt.buffs:
		for m in rt.buffs[id].get("mods", []):
			out[m.key] = float(out.get(m.key, 0.0)) + float(m.value)
	return out


func _ratio(key: String, v: float) -> float:
	var a := float(tot.get(key, 0.0))
	return (1.0 + (a + v) / 100.0) / maxf(1e-6, 1.0 + a / 100.0)


## Come _ratio ma col tetto della velocità d'attacco (Formulas.effective_haste_pct) applicato alla somma con il buff.
func _haste_ratio(v: float) -> float:
	var a := float(tot.get("combat_haste_pct", 0.0))
	return (1.0 + Formulas.effective_haste_pct(a + v) / 100.0) / maxf(1e-6, 1.0 + Formulas.effective_haste_pct(a) / 100.0)


## Statistiche con i buff correnti. Cache invalidata quando i buff cambiano (invalidate()).
func effective(rt: Dictionary) -> Dictionary:
	if _eff_ok:
		return _eff
	var bf := _bf(rt)
	var e: Dictionary = st.duplicate()
	e["bf"] = bf
	e["max_hit"] = float(st.max_hit) * _ratio("combat_dmg_pct", float(bf.get("combat_dmg_pct", 0.0)))
	e["interval"] = float(st.interval) / _haste_ratio(float(bf.get("combat_haste_pct", 0.0)))
	e["crit"] = minf(crit_cap, float(st.crit) + float(bf.get("combat_crit_chance_pct", 0.0)) / 100.0)
	e["critd"] = float(st.critd) + float(bf.get("combat_crit_dmg_pct", 0.0)) / 100.0
	var dr := _ratio("combat_defense_pct", float(bf.get("combat_defense_pct", 0.0)))
	e["arm"] = float(st.arm) * dr
	e["ward"] = float(st.ward) * dr
	e["eva"] = float(st.eva) * _ratio("combat_eva_pct", float(bf.get("combat_eva_pct", 0.0)))
	e["regen_pct"] = float(st.regen_pct) + float(bf.get("combat_regen_hps_pct", 0.0))
	e["dmg_taken_mult"] = float(st.dmg_taken_mult) * _ratio("combat_dmg_taken_pct", float(bf.get("combat_dmg_taken_pct", 0.0)))
	e["dot_mult"] = float(st.dot_mult) * _ratio("combat_dot_dmg_pct", float(bf.get("combat_dot_dmg_pct", 0.0)))
	e["summon_mult"] = float(st.summon_mult) * _ratio("summon_dmg_pct", float(bf.get("summon_dmg_pct", 0.0)))
	_eff = e
	_eff_ok = true
	return _eff


func _elem_mult_dmg(el: String, bf: Dictionary) -> float:
	if el.is_empty():
		return 1.0
	var a := float(elem_add.get(el, 0.0)) + float(bf.get("element_dmg_pct:" + el, 0.0))
	return (1.0 + a / 100.0) * float(elem_more.get(el, 1.0))


func _weak_mult(el: String) -> float:
	if el.is_empty():
		return 1.0
	if str(mon.get("weakness", "")) == el:
		return float(rules.element_weak_mult)
	if str(mon.get("resistance", "")) == el:
		return float(rules.element_resist_mult)
	return 1.0


func _deb_mult(e: Dictionary) -> float:
	var v := 0.0
	for id in e.deb:
		for m in e.deb[id].get("mods", []):
			if str(m.key) == "target_dmg_taken_pct":
				v += float(m.value)
	return maxf(0.0, 1.0 + v / 100.0)


## Moltiplicatore comune dei danni dell'eroe al bersaglio (difesa, triangolo, elemento, debuff, Barriera, Taglia).
func _common(eff: Dictionary, e: Dictionary, el: String, pen: float) -> float:
	var def_v := float(ms.armor) if str(st.style) != "arcane" else float(ms.ward)
	def_v *= 1.0 - pen
	var m := (1.0 - Formulas.damage_reduction(def_v, float(st.level))) * _tri(str(st.style), mstyle(e), true)
	m *= _weak_mult(el) * _elem_mult_dmg(el, eff.bf) * _deb_mult(e)
	if float(e.shield_s) > 0.0:
		var red := float(_mech_fx("shield_phase").get("dmg_taken_pct", 0.0))
		if _pierce_answered(e):
			red *= float(_mech_ans("shield_phase").get("keep_pct", 100.0)) / 100.0
		m *= 1.0 + red / 100.0
	if bool(e.get("bounty", false)):
		m *= 1.0 + float(st.vs_bounty) / 100.0
	return m


func _mech_fx(id: String) -> Dictionary:
	return mech.get(id, {}).get("effect", {})


## Risposta alla meccanica (boss_mechanics.json `answer`, Preparazione dei boss, resoconto 91).
func _mech_ans(id: String) -> Dictionary:
	return mech.get(id, {}).get("answer", {})


## Colpo Devastante: risposto se c'è uno scudo assorbente o un potenziamento difensivo attivo in quel momento.
func _guard_answered(rt: Dictionary) -> bool:
	if float(rt.get("shield", 0.0)) > 0.0:
		return true
	var keys: Array = _mech_ans("heavy_blow").get("buff_keys", [])
	for bid in rt.buffs:
		for m in rt.buffs[bid].get("mods", []):
			var k := str(m.key)
			if keys.has(k) and ((k == "combat_dmg_taken_pct" and float(m.value) < 0.0) or (k != "combat_dmg_taken_pct" and float(m.value) > 0.0)):
				return true
	return false


## Barriera: risposta se la penetrazione arriva alla soglia o se c'è un danno nel tempo sul boss.
func _pierce_answered(e: Dictionary) -> bool:
	var an := _mech_ans("shield_phase")
	if an.is_empty():
		return false
	if float(st.armor_pen) * 100.0 >= float(an.get("min_armor_pen_pct", 1e9)) - EPS:
		return true
	return bool(an.get("or_dot", false)) and e.get("dots") is Dictionary and not (e.dots as Dictionary).is_empty()


func _mech_tr(id: String) -> Dictionary:
	return mech.get(id, {}).get("trigger", {})


func _has_mech(id: String) -> bool:
	return (mon.get("mechanics", []) as Array).has(id)


func _emit(entry: Dictionary) -> void:
	if not expect and sink.is_valid():
		sink.call(entry)


# ====================================================================== tempi dell'eroe (sempre, anche fuori dagli scontri)

## Ricariche, durata dei buff, evocazioni, scudo e risorsa. `fighting` = c'è un nemico in campo.
func tick_timers(h: Dictionary, dt: float, fighting: bool) -> void:
	var rt: Dictionary = h.rt
	if not rt.cd.is_empty():
		for id in rt.cd.keys():
			var v := float(rt.cd[id]) - dt
			if v <= EPS:
				rt.cd.erase(id)
			else:
				rt.cd[id] = v
	if not rt.buffs.is_empty():
		var changed := false
		for id in rt.buffs.keys():
			rt.buffs[id]["left"] = float(rt.buffs[id].left) - dt
			if float(rt.buffs[id].left) <= EPS:
				rt.buffs.erase(id)
				changed = true
		if changed:
			_eff_ok = false
	if not rt.summons.is_empty():
		for id in rt.summons.keys():
			rt.summons[id]["left"] = float(rt.summons[id].left) - dt
			if float(rt.summons[id].left) <= EPS:
				rt.summons.erase(id)
	if float(rt.shield_s) > 0.0:
		rt.shield_s = float(rt.shield_s) - dt
		if float(rt.shield_s) <= EPS:
			rt.shield = 0.0
			rt.shield_s = 0.0
	_regen_resource(rt, dt, fighting)


func _regen_resource(rt: Dictionary, dt: float, fighting: bool) -> void:
	if not _res_on:
		return
	var r := float(rt.res) + _res_per_s * dt
	if not fighting:
		r -= _res_decay * dt
	rt.res = clampf(r, 0.0, res_max)


func _gain(rt: Dictionary, amount: float) -> void:
	if res_def.is_empty() or amount <= 0.0:
		return
	rt.res = minf(res_max, float(rt.res) + amount * res_mult)


# ====================================================================== nuovo nemico

func new_enemy(hp_mult: float = 1.0, dmg_mult: float = 1.0, bounty: bool = false, hp_shift: float = 0.0) -> Dictionary:
	var hp := maxf(float(ms.hp) * hp_mult * float(rules.enemy_hp_floor_pct) / 100.0, float(ms.hp) * hp_mult + hp_shift)
	return {"id": str(mon.id), "hp": hp, "max": float(ms.hp) * hp_mult, "t": {}, "shield_s": 0.0, "poison_s": 0.0,
		"deb": {}, "dots": {}, "adds": [], "slow_s": 0.0, "slow_pct": 0.0, "adds_done": false,
		"dmg_mult": dmg_mult, "bounty": bounty, "phase": 0}


## Modalità attesa: deviazione standard del danno totale accumulato prima di uccidere un nemico con `hp` punti vita
## (somma di N attacchi con N ≈ hp/μ: σ = cv·√(hp·μ)). Serve alla stima per "sfumare" il bersaglio con i quantili
## del danno (la media di un tempo di uccisione a scalini non è lo scalino della media).
func hp_sigma(hp: float) -> float:
	var rmin := float(st.min_ratio)
	var crit := float(st.crit)
	var critd := float(st.critd)
	var p := Formulas.hit_chance(float(st.acc), float(ms.evasion))
	var mean_raw := float(st.max_hit) * (1.0 + rmin) / 2.0 * (1.0 + crit * (critd - 1.0))
	var d2 := 4.0 * (1.0 + rmin + rmin * rmin) / (3.0 * (1.0 + rmin) * (1.0 + rmin))
	var c2 := ((1.0 - crit) + crit * critd * critd) / pow(1.0 + crit * (critd - 1.0), 2.0)
	var common := (1.0 - Formulas.damage_reduction(float(ms.armor if str(st.style) != "arcane" else ms.ward) * (1.0 - float(st.armor_pen)),
		float(st.level))) * Formulas.triangle_mult(str(st.style), str(mon.style)) * _weak_mult(str(st.element))
	var mu := p * mean_raw * common
	var cv2 := maxf(0.0, d2 * c2 / maxf(1e-9, p) - 1.0)
	return sqrt(cv2) * sqrt(maxf(0.0, hp * mu))


func spawn(h: Dictionary, a: Dictionary, hp_mult: float = 1.0, dmg_mult: float = 1.0, bounty: bool = false,
		hp_shift: float = 0.0) -> void:
	var rt: Dictionary = h.rt
	rt["revived"] = false
	if _swapped:
		st = _st_base
		_swapped = false
		_eff_ok = false
	var eff := effective(rt)
	a["enemy"] = new_enemy(hp_mult, dmg_mult, bounty, hp_shift)
	a["hero_cd"] = float(eff.interval)
	a["mon_cd"] = float(ms.attack_interval_s)


# ====================================================================== un passo di scontro

## Un passo (dt) di scontro con il nemico a.enemy vivo. Ritorna R_NONE / R_KILL / R_DIE / R_STOP.
func step(h: Dictionary, a: Dictionary, dt: float) -> int:
	var rt: Dictionary = h.rt
	var e: Dictionary = a.enemy
	var eff := effective(rt)
	a["hero_cd"] = float(a.hero_cd) - dt
	a["mon_cd"] = float(a.mon_cd) - dt
	if _phased:
		_check_phase(e)
		eff = effective(rt)
	if _mon_mech or float(e.slow_s) > 0.0 or not e.deb.is_empty() or not e.dots.is_empty() or not rt.summons.is_empty():
		_tick_enemy(h, a, e, eff, dt)
	if float(h.hp) <= 0.0 and not _revive_if_possible(h):
		return R_DIE
	if float(e.hp) <= 0.0:
		return R_KILL
	if _has_free and _try_cast(h, a, e, true):
		eff = effective(rt)
	var n := 0
	while float(a.hero_cd) <= EPS and float(e.hp) > 0.0 and n < MAX_SWINGS_PER_TICK:
		n += 1
		var acted := false
		if _has_buffs and _try_cast_boost(h, a, e):
			eff = effective(rt)          # il potenziamento accompagna l'attacco (gratuito), non lo sostituisce
		if not abilities.is_empty():
			acted = _try_cast(h, a, e, false)
			if acted:
				eff = effective(rt)
				# la tecnica usa l'attacco: costa come un attacco in munizioni e cariche di pozione
				if bool(st.needs_ammo):
					acc["swings"] = float(acc.swings) + 1.0
					if not expect and ammo_cb.is_valid() and not ammo_cb.call():
						return R_STOP
				if not expect and potion_cb.is_valid():
					potion_cb.call()
		if not acted and not _hero_swing(h, a, e, eff):
			return R_STOP
		a["hero_cd"] = float(a.hero_cd) + float(eff.interval)
	if float(e.hp) <= 0.0:
		return R_KILL
	n = 0
	while float(a.mon_cd) <= EPS and n < MAX_SWINGS_PER_TICK:
		n += 1
		_mon_swing(h, e, eff, float(e.dmg_mult), mon)
		for ad in e.adds:
			if float(ad.hp) > 0.0:
				_mon_swing(h, e, eff, float(ad.mult), mon)
		a["mon_cd"] = float(a.mon_cd) + _mon_interval(e)
		if float(h.hp) <= 0.0 and not _revive_if_possible(h):
			return R_DIE
	if float(e.hp) <= 0.0:
		return R_KILL
	if eat_cb.is_valid():
		eat_cb.call()
	return R_NONE


## Stima Monte Carlo: quanti passi interi (di `dt`) si possono fondere in uno solo perché in mezzo non accade nulla.
## Un evento è un colpo dell'eroe o del mostro oppure una meccanica periodica del boss; i tempi (ricariche, durata dei
## potenziamenti, danni nel tempo) si aggiornano comunque della somma dei passi, quindi il risultato è identico a quello
## passo per passo. Con effetti continui in corso (evocazioni, danni nel tempo, nube tossica) o tecniche a condizione
## (controllate a ogni passo) non si fonde nulla.
func ticks_until_event(h: Dictionary, a: Dictionary, dt: float) -> int:
	if not (h.rt.summons as Dictionary).is_empty():
		return 1
	if _has_free:
		# FIX-COMBATTIMENTO: una difesa d'emergenza può scattare solo se la sua condizione è già vera (la vita cambia
		# solo con i colpi, che sono eventi; la rigenerazione la fa solo salire)
		for ab in abilities:
			var fx: Dictionary = ab.effect
			if fx.has("trigger") and _trigger_ok(h, str(fx.trigger)):
				return 1
	var e: Dictionary = a.enemy
	if float(e.poison_s) > 0.0:
		return 1
	var r := minf(float(a.hero_cd), float(a.mon_cd))
	for d in (e.dots as Dictionary).values():          # i danni nel tempo scattano a scadenze note: sono eventi
		r = minf(r, float(d.t))
	if _mon_mech:
		for mid in ["heavy_blow", "poison_cloud", "shield_phase", "stun"]:
			if (mon.mechanics as Array).has(mid):
				r = minf(r, float(_mech_tr(mid).get("every_s", 1e9)) - float((e.t as Dictionary).get(mid, 0.0)))
	return maxi(1, int(ceil((r - EPS) / dt - 1e-9)))


## Fasi dell'incursione: sotto le soglie di vita (data/monsters.json, `phases`) il boss cambia stile e quindi
## difesa bersagliata, tipo di danno e vantaggio del triangolo. La fase non torna indietro.
func _check_phase(e: Dictionary) -> void:
	var idx := int(e.get("phase", 0))
	if idx >= _phases.size() - 1:
		return
	var pct := float(e.hp) / maxf(1.0, float(e.max)) * 100.0
	while idx < _phases.size() - 1 and pct <= float(_phases[idx + 1].hp_pct):
		idx += 1
	if idx != int(e.get("phase", 0)):
		e["phase"] = idx
		_emit({"k": "phase", "i": idx, "style": str(_phases[idx].style)})
		if not st_alt.is_empty():
			_set_stance(CombatSim.pick_stance(st_alt.keys(), str(_phases[idx].style)))


## Postura di un'ibrida contro un nemico di stile `enemy_style`: tra i suoi stili quello in vantaggio di triangolo, altrimenti
## quello senza svantaggio, altrimenti il primo (docs/06 R-CL-3).
static func pick_stance(styles: Array, enemy_style: String) -> String:
	for s in styles:
		if Formulas.triangle_mult(str(s), enemy_style) > 1.0:
			return str(s)
	for s in styles:
		if Formulas.triangle_mult(str(s), enemy_style) >= 1.0:
			return str(s)
	return str(styles[0])


## Cambio di postura a metà scontro (classi ibride, fasi del boss): nuove statistiche, stesso eroe.
func _set_stance(style: String) -> void:
	if not st_alt.has(style) or str(st.style) == style:
		return
	st = st_alt[style]
	_swapped = true
	_eff_ok = false
	_emit({"k": "stance", "style": style})


## Moltiplicatore del triangolo; con la regola di Prova l'eroe subisce sempre lo svantaggio e il mostro ha sempre il vantaggio.
func _tri(att: String, def: String, hero_attacks: bool) -> float:
	if forced_dis:
		var t: Dictionary = Formulas.k().combat.triangle
		return float(t.disadvantage) if hero_attacks else float(t.advantage)
	return Formulas.triangle_mult(att, def)


## Stile del mostro ora (con le fasi: quello della fase corrente).
func mstyle(e: Dictionary) -> String:
	if _phased:
		return str(_phases[clampi(int(e.get("phase", 0)), 0, _phases.size() - 1)].style)
	return str(mon.style)


func _revive_if_possible(h: Dictionary) -> bool:
	if expect:
		return false
	var rt: Dictionary = h.rt
	if bool(st.get("revive_once", false)) and not bool(rt.revived):
		rt["revived"] = true
		h["hp"] = float(st.hp) * float(rules.revive_once_hp_pct) / 100.0
		_emit({"k": "revive_once"})
		return true
	return false


func _mon_interval(e: Dictionary) -> float:
	var iv := float(ms.attack_interval_s)
	if _has_mech("enrage") and _enraged(e):
		iv /= 1.0 + float(_mech_fx("enrage").get("haste_pct", 0.0)) / 100.0
	if float(e.slow_s) > 0.0:
		iv /= maxf(0.05, 1.0 - float(e.slow_pct) / 100.0)
	return iv


func _enraged(e: Dictionary) -> bool:
	return float(e.hp) < float(e.max) * float(_mech_tr("enrage").get("hp_below_pct", 0.0)) / 100.0


# ---------------------------------------------------------------------- nemico: stati, meccaniche, DoT, evocazioni

func _tick_enemy(h: Dictionary, a: Dictionary, e: Dictionary, eff: Dictionary, dt: float) -> void:
	var rt: Dictionary = h.rt
	if float(e.slow_s) > 0.0:
		e["slow_s"] = float(e.slow_s) - dt
		if float(e.slow_s) <= EPS:             # niente residui da virgola mobile: la durata è quella dei dati
			e["slow_s"] = 0.0
	if not e.deb.is_empty():
		for id in e.deb.keys():
			e.deb[id]["left"] = float(e.deb[id].left) - dt
			if float(e.deb[id].left) <= EPS:
				e.deb.erase(id)
	# meccaniche periodiche dei boss
	if mon.has("mechanics"):
		var mechs: Array = mon.mechanics
		if not mechs.is_empty():
			_tick_mechanics(h, a, e, eff, dt, mechs)
	# DoT dell'eroe
	if not e.dots.is_empty():
		var tick_s := float(rules.dot_tick_s)
		for id in e.dots.keys():
			var d: Dictionary = e.dots[id]
			d["t"] = float(d.t) - dt
			while float(d.t) <= EPS and int(d.n) > 0:
				d["t"] = float(d.t) + tick_s
				d["n"] = int(d.n) - 1
				var dmg := float(d.raw) * _common(eff, e, str(d.el), float(st.armor_pen))
				_hit_enemy(e, dmg, true)
				_emit({"k": "dot", "v": dmg})
			if int(d.n) <= 0:
				e.dots.erase(id)
	# evocazioni (compagni / servitori)
	if not rt.summons.is_empty():
		var avg_raw := float(eff.max_hit) * (1.0 + float(st.min_ratio)) / 2.0 / maxf(0.05, float(eff.interval))
		for id in rt.summons:
			var s: Dictionary = rt.summons[id]
			var dmg := float(s.w) * avg_raw * float(eff.summon_mult) * _common(eff, e, str(s.el), float(st.armor_pen)) * dt
			_hit_enemy(e, dmg, false)


func _tick_mechanics(h: Dictionary, a: Dictionary, e: Dictionary, eff: Dictionary, dt: float, mechs: Array) -> void:
	var t: Dictionary = e.t
	if float(e.shield_s) > 0.0:
		e["shield_s"] = float(e.shield_s) - dt
		if float(e.shield_s) <= EPS:
			e["shield_s"] = 0.0
	if float(e.poison_s) > 0.0:
		e["poison_s"] = float(e.poison_s) - dt
		if float(e.poison_s) <= EPS:
			e["poison_s"] = 0.0
		var fx := _mech_fx("poison_cloud")
		var resist := float(st.status_resist)
		var dot := float(st.hp) * float(fx.get("dot_pct_max_hp", 0.0)) / 100.0 * dt * (1.0 - resist)
		h["hp"] = float(h.hp) - dot
		acc["dmg_in"] = float(acc.dmg_in) + dot
	for mid in ["heavy_blow", "poison_cloud", "shield_phase", "stun"]:
		if not mechs.has(mid):
			continue
		t[mid] = float(t.get(mid, 0.0)) + dt
		var every := float(_mech_tr(mid).get("every_s", 1e9))
		if float(t[mid]) < every - EPS:
			continue
		t[mid] = float(t[mid]) - every
		var fx := _mech_fx(mid)
		match mid:
			"heavy_blow":
				var hm := float(fx.get("hit_mult", 1.0))
				var guarded := _guard_answered(h.rt)
				if guarded:
					hm *= float(_mech_ans("heavy_blow").get("hit_mult", 1.0))
				_mon_swing(h, e, eff, hm * float(e.dmg_mult), mon)
				_emit({"k": "heavy", "id_m": str(mon.id), "guard": guarded})
			"poison_cloud":
				e["poison_s"] = float(fx.get("duration_s", 0.0))
				_emit({"k": "mech", "m": mid})
			"shield_phase":
				e["shield_s"] = float(fx.get("duration_s", 0.0))
				_emit({"k": "mech", "m": mid})
			"stun":
				a["hero_cd"] = float(a.hero_cd) + float(fx.get("stun_s", 0.0)) * (1.0 - float(st.status_resist))
				_emit({"k": "mech", "m": mid})
	if mechs.has("summon_adds") and not bool(e.adds_done):
		var fx2 := _mech_fx("summon_adds")
		if float(e.hp) < float(e.max) * float(_mech_tr("summon_adds").get("hp_below_pct", 0.0)) / 100.0:
			e["adds_done"] = true
			for i in int(fx2.get("summon", 0)):
				e.adds.append({"hp": float(e.max) * float(fx2.get("hp_pct_of_boss", 0.0)) / 100.0,
					"mult": float(fx2.get("dmg_pct_of_boss", 0.0)) / 100.0 * float(e.dmg_mult)})
			_emit({"k": "mech", "m": "summon_adds"})


## Danno all'avversario: prima ai servitori evocati (se vivi), poi al boss. Ritorna il danno applicato.
func _hit_enemy(e: Dictionary, dmg: float, _dot: bool) -> float:
	var left := dmg
	for ad in e.adds:
		if left <= 0.0:
			break
		if float(ad.hp) > 0.0:
			var take := minf(left, float(ad.hp)) if not expect else left
			ad["hp"] = float(ad.hp) - take
			left -= take
			if expect:
				left = 0.0
	if left > 0.0:
		var take2 := minf(left, float(e.hp)) if not expect else left
		e["hp"] = float(e.hp) - take2
		return take2
	return dmg - left


# ---------------------------------------------------------------------- colpi dell'eroe

## Un attacco base (più l'eventuale secondo colpo). false = combattimento fermato (munizioni finite).
func _hero_swing(h: Dictionary, _a: Dictionary, e: Dictionary, eff: Dictionary) -> bool:
	if expect:
		acc["swings"] = float(acc.swings) + 1.0
		_swing_roll(h, e, eff, 1.0)
		var mhe := float(st.multihit)
		if mhe > 0.0:
			_swing_roll(h, e, eff, mhe)
		return true
	acc["swings"] = float(acc.swings) + 1.0
	if bool(st.needs_ammo) and ammo_cb.is_valid() and not ammo_cb.call():
		return false
	if potion_cb.is_valid():
		potion_cb.call()
	_swing_roll(h, e, eff)
	var mh := float(st.multihit)
	if mh > 0.0:
		if (_strat.randk(K_MULTI) < mh) if _strat != null else rng.chance("combat", mh):
			_swing_roll(h, e, eff, 1.0, K_EXTRA)
	return true


func _swing_roll(h: Dictionary, e: Dictionary, eff: Dictionary, weight: float = 1.0, k0: int = K_HIT) -> void:
	var rt: Dictionary = h.rt
	var p := Formulas.hit_chance(float(st.acc), float(ms.evasion))
	var common := _common(eff, e, str(st.element), float(st.armor_pen))
	if expect:
		var mean_raw := float(eff.max_hit) * (1.0 + float(st.min_ratio)) / 2.0 * (1.0 + float(eff.crit) * (float(eff.critd) - 1.0))
		var dmg := mean_raw * common
		acc["hits"] = float(acc.hits) + p * weight
		_hit_enemy(e, p * dmg * weight, false)
		_gain(rt, p * weight * float(res_def.get("on_hit_dealt", 0.0)))
		_gain(rt, p * weight * float(eff.crit) * float(res_def.get("on_crit", 0.0)))
		if float(st.lifesteal) > 0.0:
			_heal(h, p * dmg * weight * float(st.lifesteal))
		return
	var kd := K_DMG if k0 == K_HIT else k0 + 1
	var kc := K_CRIT if k0 == K_HIT else k0 + 2
	if (_strat.randk(k0) if _strat != null else rng.randf("combat")) >= p:
		if _strat != null:                 # il danno e il critico di questo colpo non servono: i contatori avanzano lo stesso
			_strat.skip(kd)
			_strat.skip(kc)
		_emit({"k": "miss"})
		return
	acc["hits"] = float(acc.hits) + 1.0
	var raw := float(eff.max_hit) * lerpf(float(st.min_ratio), 1.0, _strat.randk(kd) if _strat != null else rng.randf("combat"))
	var crit: bool = (_strat.randk(kc) if _strat != null else rng.randf("combat")) < float(eff.crit)
	if crit:
		raw *= float(eff.critd)
	var dmg2 := raw * common
	var dealt := _hit_enemy(e, dmg2, false)
	if oil_cb.is_valid():
		oil_cb.call()
	_gain(rt, float(res_def.get("on_hit_dealt", 0.0)))
	if crit:
		_gain(rt, float(res_def.get("on_crit", 0.0)))
	if float(st.lifesteal) > 0.0:
		_heal(h, dealt * float(st.lifesteal))
	_emit({"k": "hit", "v": dealt, "crit": crit})


func _heal(h: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var mx := float(st.hp)
	var before := float(h.hp)
	h["hp"] = minf(mx, before + amount)
	acc["heal"] = float(acc.heal) + (float(h.hp) - before)


# ---------------------------------------------------------------------- colpi del mostro

func _mon_swing(h: Dictionary, e: Dictionary, eff: Dictionary, mult: float, m: Dictionary, w: float = 1.0) -> void:
	var rt: Dictionary = h.rt
	var p := Formulas.hit_chance(float(ms.accuracy), float(eff.eva))
	var mst := mstyle(e)
	var dtype := str(m.damage_type)
	if _phased:
		dtype = "magic" if mst == "arcane" else "physical"
	var def_v := float(eff.arm) if dtype == "physical" else float(eff.ward)
	var enr := 1.0
	if _has_mech("enrage") and _enraged(e):
		enr = 1.0 + float(_mech_fx("enrage").get("dmg_pct", 0.0)) / 100.0
	var base_mult := (1.0 - Formulas.damage_reduction(def_v, float(m.level))) \
		* _tri(mst, str(st.style), false) * float(eff.dmg_taken_mult) * enr * mult
	if expect:
		var dmg := float(ms.max_hit) * mon_avg_ratio * base_mult
		var taken := _absorb(rt, p * dmg * w)
		h["hp"] = float(h.hp) - taken
		acc["dmg_in"] = float(acc.dmg_in) + taken
		_gain(rt, p * w * float(res_def.get("on_hit_taken", 0.0)))
		_post_mon_hit(e, p * dmg * w, true)
		return
	var p_eff := p
	var u_top := 1.0
	if surv_mode and not (bool(st.get("revive_once", false)) and not bool(rt.revived)):
		# (con la rinascita ancora disponibile il colpo letale non uccide: si estrae normalmente)
		# colpo letale se danno >= vita + scudo: u* sulla scala lineare del danno [min_ratio, 1]
		var full := float(ms.max_hit) * base_mult
		var need := float(h.hp) + float(rt.shield)
		var u_star := 1.0 if full <= 0.0 else ((need / full) - _min_ratio_mon) / maxf(1e-9, 1.0 - _min_ratio_mon)
		u_star = clampf(u_star, 0.0, 1.0)
		var q := p * (1.0 - u_star)
		if q >= 1.0 - 1e-9:
			surv = 0.0            # morte certa: il percorso muore davvero (sotto)
		elif q > 0.0:
			surv *= 1.0 - q
			p_eff = p * u_star / (1.0 - q)        # colpo a segno sapendo di sopravvivere
			u_top = u_star * (1.0 - 1e-6)
	if (_strat.randk(K_MHIT) if _strat != null else rng.randf("combat")) >= p_eff:
		if _strat != null:
			_strat.skip(K_MDMG)
		_emit({"k": "mmiss"})
		return
	var raw := float(ms.max_hit) * lerpf(_min_ratio_mon, 1.0, u_top * (_strat.randk(K_MDMG) if _strat != null else rng.randf("combat")))
	var dmg2 := raw * base_mult
	var taken2 := _absorb(rt, dmg2)
	acc["dmg_in"] = float(acc.dmg_in) + taken2
	h["hp"] = float(h.hp) - taken2
	_gain(rt, float(res_def.get("on_hit_taken", 0.0)))
	_post_mon_hit(e, dmg2, false)
	_emit({"k": "mhit", "v": taken2})


func _absorb(rt: Dictionary, dmg: float) -> float:
	var sh := float(rt.shield)
	if sh <= 0.0:
		return dmg
	var soak := minf(sh, dmg)
	rt.shield = sh - soak
	return dmg - soak


## Prosciugamento del boss e spine dell'eroe sul danno appena inflitto.
func _post_mon_hit(e: Dictionary, dmg: float, _exp: bool) -> void:
	if _has_mech("lifedrain"):
		e["hp"] = minf(float(e.max), float(e.hp) + dmg * float(_mech_fx("lifedrain").get("lifesteal_pct", 0.0)) / 100.0)
	if _mon_ls > 0.0:
		e["hp"] = minf(float(e.max), float(e.hp) + dmg * _mon_ls)
	var th := float(st.thorns)
	if th > 0.0:
		_hit_enemy(e, dmg * th, false)


# ====================================================================== abilità

func _trigger_ok(h: Dictionary, trig: String) -> bool:
	if trig.is_empty():
		return true
	var parts := trig.split(":")
	if parts[0] == "hp_below_pct" and parts.size() > 1:
		return float(h.hp) < float(st.hp) * float(parts[1]) / 100.0
	return false


## Lancia al massimo UNA abilità: la prima pronta della lista di priorità. `free` = le abilità con condizione (difese
## d'emergenza) scattano a ogni tick senza costare l'attacco; le tecniche offensive si lanciano al posto dell'attacco
## base, quando questo è dovuto (docs/05 §5, lista di priorità); i potenziamenti accompagnano l'attacco (_try_cast_boost).
## Ritorna true se ha lanciato.
func _try_cast(h: Dictionary, a: Dictionary, e: Dictionary, free: bool) -> bool:
	var rt: Dictionary = h.rt
	for ab in abilities:
		var id := str(ab.id)
		var fx: Dictionary = ab.effect
		if fx.has("trigger") != free:
			continue
		if not free and is_boost(ab):
			continue
		if rt.cd.has(id):
			continue
		if float(rt.res) < float(ab.cost) - EPS:
			continue
		if not _trigger_ok(h, str(fx.get("trigger", ""))):
			continue
		if not _useful(h, e, ab):
			continue
		_cast(h, a, e, ab)
		return true
	return false


## Potenziamento (FIX-COMBATTIMENTO, QA4 #7): buff, debuff o scudo senza condizione. Non prende il posto dell'attacco:
## si lancia insieme all'attacco base (costa solo la risorsa), così non è mai una scelta in perdita.
static func is_boost(ab: Dictionary) -> bool:
	var fx: Dictionary = ab.effect
	return not fx.has("trigger") and ["buff", "debuff", "shield"].has(str(fx.type))


## Lancia il primo potenziamento pronto della lista (al massimo uno per attacco). Ritorna true se ha lanciato.
func _try_cast_boost(h: Dictionary, a: Dictionary, e: Dictionary) -> bool:
	var rt: Dictionary = h.rt
	for ab in abilities:
		if not is_boost(ab):
			continue
		if rt.cd.has(str(ab.id)) or float(rt.res) < float(ab.cost) - EPS:
			continue
		if not _useful(h, e, ab):
			continue
		_cast(h, a, e, ab)
		return true
	return false


func _useful(h: Dictionary, e: Dictionary, ab: Dictionary) -> bool:
	var rt: Dictionary = h.rt
	var fx: Dictionary = ab.effect
	var id := str(ab.id)
	match str(fx.type):
		"buff":
			return not rt.buffs.has(id)
		"debuff":
			return not e.deb.has(id)
		"dot":
			return not e.dots.has(id)
		"summon":
			return not rt.summons.has(id)
		"shield":
			return float(rt.shield_s) <= 0.0
		"heal":
			return float(h.hp) < float(st.hp) - EPS
	return true


func _cast(h: Dictionary, a: Dictionary, e: Dictionary, ab: Dictionary) -> void:
	var rt: Dictionary = h.rt
	var fx: Dictionary = ab.effect
	var id := str(ab.id)
	rt.cd[id] = float(ab.cooldown_s)
	rt.res = maxf(0.0, float(rt.res) - float(ab.cost))
	acc["casts"] = float(acc.casts) + 1.0
	var eff := effective(rt)
	match str(fx.type):
		"damage":
			_cast_damage(h, a, e, eff, fx, id)
		"dot":
			e.dots[id] = _make_dot(eff, float(fx.weapon_mult_per_tick), int(fx.ticks), str(fx.get("element", "") if fx.get("element") != null else ""))
		"buff":
			rt.buffs[id] = {"left": float(fx.duration_s), "mods": (fx.modifiers as Array).duplicate(true)}
			_eff_ok = false
		"debuff":
			e.deb[id] = {"left": float(fx.duration_s), "mods": (fx.modifiers as Array).duplicate(true)}
		"heal":
			_heal(h, float(st.hp) * float(fx.pct_max_hp) / 100.0 * (1.0 + float(st.heal_rx)))
		"shield":
			rt.shield = float(st.hp) * float(fx.pct_max_hp) / 100.0
			rt.shield_s = float(fx.duration_s)
		"summon":
			rt.summons[id] = {"left": float(fx.duration_s), "w": float(fx.dps_weapon_mult),
				"el": str(fx.get("element", "") if fx.get("element") != null else "")}
	_emit({"k": "cast", "ab": id})


func _make_dot(eff: Dictionary, w: float, ticks: int, el: String) -> Dictionary:
	var avg_raw := float(eff.max_hit) * (1.0 + float(st.min_ratio)) / 2.0
	return {"raw": avg_raw * w * float(eff.dot_mult), "n": ticks, "t": float(rules.dot_tick_s), "el": el}


func _cast_damage(h: Dictionary, _a: Dictionary, e: Dictionary, eff: Dictionary, fx: Dictionary, _id: String) -> void:
	var rt: Dictionary = h.rt
	var el := str(fx.get("element", "") if fx.get("element") != null else "")
	var pen := 1.0 - (1.0 - float(st.armor_pen)) * (1.0 - float(fx.get("armor_pen_pct", 0.0)) / 100.0)
	var hits := int(fx.get("hits", 1))
	var w := float(fx.weapon_mult)
	var crit_p := minf(crit_cap, float(eff.crit) + float(fx.get("crit_bonus", 0.0)))
	var common := _common(eff, e, el, pen)
	var exec_mult := 1.0
	var thr := float(fx.get("execute_below_pct", 0.0))
	if thr > 0.0 and float(e.hp) < float(e.max) * thr / 100.0:
		exec_mult = float(fx.get("execute_mult", 1.0))
	var total := 0.0
	for i in hits:
		var crit := false
		var raw: float
		if expect:
			raw = float(eff.max_hit) * (1.0 + float(st.min_ratio)) / 2.0 * (1.0 + crit_p * (float(eff.critd) - 1.0))
			_gain(rt, crit_p * float(res_def.get("on_crit", 0.0)))
		else:
			raw = float(eff.max_hit) * lerpf(float(st.min_ratio), 1.0, _strat.randk(K_ADMG) if _strat != null else rng.randf("combat"))
			crit = (_strat.randk(K_ACRIT) if _strat != null else rng.randf("combat")) < crit_p
			if crit:
				raw *= float(eff.critd)
				_gain(rt, float(res_def.get("on_crit", 0.0)))
		var dmg := raw * w * common * exec_mult
		total += _hit_enemy(e, dmg, false)
		_emit({"k": "ahit", "v": dmg, "crit": crit})
	var hp_frac := float(fx.get("heal_pct_of_damage", 0.0)) / 100.0
	if hp_frac > 0.0:
		_heal(h, total * hp_frac * (1.0 + float(st.heal_rx)))
	if fx.has("stun_s"):
		_a["mon_cd"] = float(_a.mon_cd) + float(fx.stun_s)
	if fx.has("slow_pct"):
		e["slow_s"] = float(fx.slow_s)
		e["slow_pct"] = float(fx.slow_pct)
	if fx.has("dot_weapon_mult_per_tick"):
		e.dots[_id + ":dot"] = _make_dot(eff, float(fx.dot_weapon_mult_per_tick), int(fx.dot_ticks), el)
