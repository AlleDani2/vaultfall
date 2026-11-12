class_name EndgameCombat
extends RefCounted
## Combattimento di fine gioco (docs/05 §8-9, docs/11 §8): Incursioni con la squadra di mercenari, Boss mondiali,
## La Breccia. Aiutante di CombatSystem (stesso schema di HeroBuild): legge e scrive la sezione `hero` e l'attività
## `combat` con i modi "raid", "wboss", "rift". Stesso motore dello scontro (CombatSim), nessun numero di
## bilanciamento qui: tutto da data/raids.json, world_bosses.json, rift.json, mercenary_rules.json, era_rules.json.
##
## Stato in `hero` (CombatSystem):
##   raid_cd {raid: secondi}  raid_clears {raid: n}  raid_best_s {raid: secondi}
##   wb   {t: orologio "a gioco aperto", done_slot: finestra già usata, horn: {boss, left_s}, kills, best}
##   rift {best: piano massimo raggiunto, guardian: ultimo Guardiano battuto, runs, deaths, shards}
## Attività (modi):
##   raid   {raid, party[uid], fx{...}, t}
##   wboss  {wb, source, slot, left_s, dealt, ally, t}
##   rift   {floor, idx, start_floor}
##
## Offline: passaggio rapido in "valori attesi" (boss_pass) con lo stesso CombatSim del tick; vedi docs/05 §12.

const R_TIMEOUT := 9
const MODES: PackedStringArray = ["raid", "wboss", "rift"]
const WARDEN_BOSS := "vault_warden"
const EPS := 1e-6
## Passo dei passaggi analitici (campionamento, non una regola di gioco): come il tick (0,1 s) per incursioni e boss mondiali,
## più largo (le ricariche delle abilità arrivano in ritardo di ~dt/2: +2% di durata a 0,25 s) per i molti scontri della Breccia.
const PASS_DT := 0.1
const RIFT_PASS_DT := 0.25
const PASS_MAX_S := 7200.0
const BUSY_PREFIX := "raid:"
const TIER_IDS: PackedStringArray = ["bronze", "silver", "gold", "platinum"]
## Soglie dell'indicatore di rischio (solo presentazione): vittoria stimata sotto RISK_RED = rosso, sotto RISK_YELLOW = giallo.
const RISK_RED := 0.5
const RISK_YELLOW := 0.9
## Tetto di piani valutati in una sola chiamata offline della Breccia (protezione dai tempi).
const RIFT_FLOORS_CAP := 400

var _ref: WeakRef
var sys: CombatSystem:
	get:
		return _ref.get_ref() as CombatSystem
var _fx_key: String = ""
var _fx_st: Dictionary = {}
var _rift_cache: Dictionary = {}
var _prev_cache: Dictionary = {}
var _prev_gen: int = -1
## COOP-1: Breccia alternativa (Prova della settimana) per la sola simulazione di CoopSystem; {} = la Breccia dei dati.
var rift_override: Dictionary = {}


func _init(p_sys: CombatSystem) -> void:
	_ref = weakref(p_sys)


# ====================================================================== stato

static func default_wb() -> Dictionary:
	return {"t": 0.0, "done_slot": 0, "horn": {}, "kills": {}, "best": {}}


static func default_rift() -> Dictionary:
	return {"best": 0, "guardian": 0, "runs": 0, "deaths": 0, "shards": 0}


## Riempie le chiavi mancanti (salvataggi precedenti) e porta i numeri al tipo giusto.
func normalize() -> void:
	var s: Dictionary = sys.state
	var wb: Dictionary = s.wb
	var dw := default_wb()
	for k in dw:
		var cur: Variant = wb.get(k)
		if cur is float or cur is int:
			if typeof(dw[k]) == TYPE_FLOAT or typeof(dw[k]) == TYPE_INT:
				if typeof(dw[k]) == TYPE_FLOAT:       # JSON restituisce i numeri come float
					wb[k] = float(cur)
				else:
					wb[k] = int(cur)
				continue
		if not wb.has(k) or typeof(wb[k]) != typeof(dw[k]):
			wb[k] = dw[k]
	wb["done_slot"] = int(wb.done_slot)
	var horn: Dictionary = wb.horn
	if not horn.is_empty():
		horn["left_s"] = float(horn.get("left_s", 0.0))
		if ctx_data().get_def("world_bosses", str(horn.get("boss", ""))).is_empty():
			wb["horn"] = {}
	var rf: Dictionary = s.rift
	var dr := default_rift()
	for k in dr:
		if not rf.has(k):
			rf[k] = dr[k]
		rf[k] = int(rf[k])
	for k in (s.raid_cd as Dictionary).keys():
		s.raid_cd[k] = float(s.raid_cd[k])
	_rift_cache.clear()
	_prev_cache.clear()
	_fx_key = ""


func ctx_data() -> Object:
	return sys.ctx.data


func _mercs() -> Variant:
	return sys.ctx.get_system("mercenaries")


func _bank() -> Variant:
	return sys.ctx.get_system("bank")


## COOP-1: sistema dei compagni d'armi (null se la modalità Amici non è registrata, per esempio nei test dei sistemi).
func _coop() -> Variant:
	return sys.ctx.get_system("coop")


func _unlock_has(token: String) -> bool:
	return (sys.ctx.state.get("unlocks", []) as Array).has(token)


func _quest_done(qid: String) -> bool:
	var q: Variant = sys.ctx.get_system("quests")
	return q != null and q.has_method("is_done") and bool(q.is_done(qid))


func _quest_active(qid: String) -> bool:
	var q: Variant = sys.ctx.get_system("quests")
	return q != null and q.has_method("is_active") and bool(q.is_active(qid))


## Orologi che girano con la partita aperta: ricariche delle incursioni, finestre dei boss mondiali.
func tick(dt: float) -> void:
	var s: Dictionary = sys.state
	var wb: Dictionary = s.wb
	wb["t"] = float(wb.t) + dt
	var horn: Dictionary = wb.horn
	if not horn.is_empty():
		horn["left_s"] = float(horn.left_s) - dt
		if float(horn.left_s) <= EPS:
			wb["horn"] = {}
	var cds: Dictionary = s.raid_cd
	if not cds.is_empty():
		for k in cds.keys():
			var v := float(cds[k]) - dt
			if v <= EPS:
				cds.erase(k)
			else:
				cds[k] = v


## Offline: le ricariche scorrono, le finestre dei boss mondiali no (compaiono "a gioco aperto", docs/05 §8).
func advance_offline_clocks(seconds: float) -> void:
	var cds: Dictionary = sys.state.raid_cd
	for k in cds.keys():
		var v := float(cds[k]) - seconds
		if v <= EPS:
			cds.erase(k)
		else:
			cds[k] = v


## Ogni secondo di gioco: libera i mercenari «in incursione» se l'attività non è più quell'incursione
## (per esempio il giocatore è passato a una mansione).
func housekeeping() -> void:
	var m: Variant = _mercs()
	if m == null:
		return
	var a := sys._act()
	var party: Array = []
	if str(a.get("type", "")) == "combat" and str(a.get("mode", "")) == "raid":
		party = a.get("party", [])
	for mm in m.roster():
		var b := str(mm.get("busy", ""))
		if b.begins_with(BUSY_PREFIX) and not party.has(str(mm.uid)):
			mm["busy"] = ""


func is_endgame_mode(mode: String) -> bool:
	return MODES.has(mode)


# ====================================================================== INCURSIONI

func raid_def(raid_id: String) -> Dictionary:
	return ctx_data().get_def("raids", raid_id)


func raid_unlocked(raid_id: String) -> bool:
	var d := raid_def(raid_id)
	if d.is_empty():
		return false
	return _unlock_has("raid:" + raid_id) and sys.hero_unlock_level() >= int(d.get("unlock", {}).get("hero_level", 1))


func raid_cd(raid_id: String) -> float:
	return float(sys.state.raid_cd.get(raid_id, 0.0))


func raid_clears(raid_id: String) -> int:
	return int(sys.state.raid_clears.get(raid_id, 0))


## Incursioni dei dati in ordine: id, def, unlocked, cd_s (ricarica residua), clears, best_s.
func raids() -> Array:
	var out: Array = []
	for r in ctx_data().table("raids"):
		var rid := str(r.id)
		out.append({"id": rid, "def": r, "unlocked": raid_unlocked(rid), "cd_s": raid_cd(rid), "clears": raid_clears(rid),
			"best_s": float(sys.state.raid_best_s.get(rid, 0.0))})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.def.order) < int(y.def.order))
	return out


func _raid_roles() -> Dictionary:
	return ctx_data().rules("mercenary_rules")["raid_roles"]


## Potere richiesto: base × crescita^(ordine zona − 1) × dimensione di riferimento (mercenary_rules.raid_roles).
func raid_required_power(raid_id: String) -> float:
	var rr := _raid_roles()
	var z := sys.zone_def(str(raid_def(raid_id).get("zone", "")))
	var order := int(z.get("order", 1))
	return float(rr["power_base"]) * pow(float(rr["power_growth"]), order - 1) * float(rr["power_party_size"])


## Potere dell'Eroe nella squadra d'incursione (BOT-02/03): quota `hero_share` del potere richiesto quando l'Eroe è al livello
## dell'incursione, proporzionale a livello Eroe / livello incursione fino a `hero_level_cap` (mercenary_rules.raid_roles).
## I mercenari sommano il resto: l'incursione si vince con l'Eroe del proprio livello, i mercenari la rendono più sicura.
func raid_hero_power(raid_id: String) -> float:
	var rr := _raid_roles()
	var lv := float(raid_def(raid_id).get("level", 1.0))
	var rel := minf(float(sys.hero_level()) / maxf(lv, 1.0), float(rr["hero_level_cap"]))
	return raid_required_power(raid_id) * float(rr["hero_share"]) * rel


## Mercenari che possono partire (liberi e non feriti), con il loro potere.
func party_candidates() -> Array:
	var m: Variant = _mercs()
	var out: Array = []
	if m == null:
		return out
	for mm in m.roster():
		if m.is_available(str(mm.uid)):
			out.append(mm)
	return out


## Effetti di ruolo di una squadra: {"required","power","ratio","f","defender","healer","striker"}. Ogni ruolo presente
## vale f = min(tetto, potere/potere_richiesto) (+ tratto Predone dei mercenari di quel ruolo). Squadra incompleta: i
## ruoli assenti non danno nulla (consentito, l'incursione è molto più dura).
func raid_fx(raid_id: String, party: Array) -> Dictionary:
	var rr := _raid_roles()
	var req := raid_required_power(raid_id)
	var m: Variant = _mercs()
	var power := 0.0
	var present: Dictionary = {}
	if m != null:
		var real: Array = party.filter(func(u: Variant) -> bool: return not str(u).begins_with("c:"))   # i compagni (COOP-1) non sono mercenari
		power = float(m.team_power(real))
		for u in real:
			var mm: Dictionary = m.get_merc(str(u))
			if mm.is_empty():
				continue
			var role := str(mm.role)
			present[role] = float(present.get(role, 0.0)) + float(m.trait_sum(mm, "raid_role_pct"))
	var co: Variant = _coop()
	if co != null and party.size() > 0:
		var ex: Dictionary = co.raid_contrib(raid_id, party)
		power += float(ex.power)
		for role2 in ex.roles:
			present[role2] = float(present.get(role2, 0.0)) + float(ex.roles[role2])
	var hero_p := raid_hero_power(raid_id)
	power += hero_p
	var ratio := power / maxf(req, 1e-9)
	var f := minf(ratio, float(rr["ratio_cap"]))
	var out := {"required": req, "power": power, "ratio": ratio, "f": f, "hero_power": hero_p, "defender": 0.0, "healer": 0.0, "striker": 0.0}
	# I ruoli di squadra scoperti (nessun mercenario di quel ruolo) valgono comunque la quota dell'Eroe: lui li copre da solo.
	for role in ["defender", "healer", "striker"]:
		if present.has(role):
			out[role] = f * (1.0 + float(present[role]) / 100.0)
		else:
			out[role] = f * float(rr["hero_role_share"])
	return out


## Statistiche dell'eroe con gli effetti di ruolo: meno danni subiti, cura al secondo, più danno.
func apply_fx(st: Dictionary, fx: Dictionary) -> Dictionary:
	var rr := _raid_roles()
	var s := st.duplicate()
	s["dmg_taken_mult"] = float(st.dmg_taken_mult) * maxf(0.0, 1.0 + float(rr.defender.dmg_taken_pct) / 100.0 * float(fx.defender))
	s["regen_pct"] = float(st.regen_pct) + float(rr.healer.regen_pct_per_s) * float(fx.healer)
	s["max_hit"] = float(st.max_hit) * (1.0 + float(rr.striker.dmg_pct) / 100.0 * float(fx.striker))
	s["min_hit"] = float(s.max_hit) * float(st.min_ratio)
	return s


## Effetti di squadra dell'incursione in corso ({} fuori dalle incursioni): servono alle posture delle ibride (COMBAT-3).
func active_fx() -> Dictionary:
	var a := sys._act()
	if str(a.get("type", "")) != "combat":
		return {}
	if str(a.get("mode", "")) == "rift":
		return _rift_fx(int(a.get("floor", 1)))
	if str(a.get("mode", "")) != "raid":
		return {}
	return a.get("fx", {})


## Statistiche per CombatSim: nelle incursioni quelle con gli effetti della squadra (in cache), altrimenti invariate.
func run_stats(st: Dictionary) -> Dictionary:
	var a := sys._act()
	if str(a.get("type", "")) != "combat" or not (str(a.get("mode", "")) == "raid" or str(a.get("mode", "")) == "rift"):
		return st
	var fx: Dictionary = a.get("fx", {}) if str(a.get("mode", "")) == "raid" else _rift_fx(int(a.get("floor", 1)))
	if fx.is_empty():
		return st
	var key := "%d|%s|%.4f|%.4f|%.4f" % [sys._gen, sys._stance, float(fx.defender), float(fx.healer), float(fx.striker)]
	if key != _fx_key:
		_fx_key = key
		_fx_st = apply_fx(st, fx)
	return _fx_st


## COOP-1: i compagni d'armi in squadra occupano i posti liberi (o quello del mercenario più debole).
func _with_companions(raid_id: String, party: Array) -> Array:
	var co: Variant = _coop()
	return party if co == null else co.party_with_companions(raid_id, party)


## COOP-1: effetti dei compagni d'armi alla Breccia, piano `fl` ({} senza compagni). Stessa funzione per tick e offline.
func _rift_fx(fl: int) -> Dictionary:
	var co: Variant = _coop()
	return {} if co == null else co.rift_fx(fl)


func _release_party(a: Dictionary) -> void:
	var m: Variant = _mercs()
	if m == null:
		return
	for u in a.get("party", []):
		var mm: Dictionary = m.get_merc(str(u))
		if not mm.is_empty() and str(mm.get("busy", "")).begins_with(BUSY_PREFIX):
			mm["busy"] = ""


func _party_ok(party: Array, size: int) -> bool:
	if party.size() > size:
		return false
	var m: Variant = _mercs()
	var seen: Dictionary = {}
	var co: Variant = _coop()
	for u in party:
		if seen.has(str(u)):
			return false
		seen[str(u)] = true
		if str(u).begins_with("c:"):               # compagno d'armi (COOP-1)
			if co == null or not co.party_member_ok(str(u)):
				return false
			continue
		if m == null or not m.is_available(str(u)):
			return false
	return true


## Sceglie la squadra automaticamente: per ogni ruolo dell'incursione il mercenario libero più forte.
func suggest_party(raid_id: String) -> Array:
	var m: Variant = _mercs()
	var out: Array = []
	if m == null:
		return out
	var cands := party_candidates()
	for role in raid_def(raid_id).get("party", {}).get("roles", []):
		var best := ""
		var bp := -1.0
		for mm in cands:
			if str(mm.role) != str(role) or out.has(str(mm.uid)):
				continue
			var p := float(m.power_of(mm))
			if p > bp:
				bp = p
				best = str(mm.uid)
		if not best.is_empty():
			out.append(best)
	return out


## Anteprima: effetti di ruolo, esito atteso (passaggio rapido a vita piena) e indicatore di rischio.
## {"fx","level": green|yellow|red,"win","time_s","food","food_have","hp_min_pct","worst_hit","size"}
func raid_preview(raid_id: String, party: Array) -> Dictionary:
	var rd := raid_def(raid_id)
	if rd.is_empty():
		return {}
	party = _with_companions(raid_id, party)
	if sys._gen != _prev_gen:
		_prev_cache.clear()
		_prev_gen = sys._gen
	var key := "%s|%s|%s|%d|%d|%s" % [raid_id, ",".join(PackedStringArray(party)), sys._est_food_sig(), sys._abil_ver, sys._era(), str(sys.food_available())]
	if _prev_cache.has(key):
		return _prev_cache[key]
	var fx := raid_fx(raid_id, party)
	var mon: Dictionary = ctx_data().get_def("monsters", str(rd.boss))
	var ms := sys._scaled(mon, sys._era())
	var st := apply_fx(sys._stats_for(sys.stance_for(mon)), fx)
	var res := boss_pass(mon, ms, st, {"hp0": float(st.hp), "food": sys.food_available(), "fx": fx})
	var out := _risk_from_pass(res, mon, ms, st)
	out["fx"] = fx
	out["size"] = int(rd.party.size)
	_prev_cache[key] = out
	return out


func _risk_from_pass(res: Dictionary, mon: Dictionary, ms: Dictionary, st: Dictionary) -> Dictionary:
	var worst := _worst_hit(mon, ms, st)
	var mx := float(st.hp)
	var p_die := death_prob(res, mon, ms, st)
	var level := "green"
	var need := int(ceil(float(res.food)))
	var have := sys.food_available()
	if not bool(res.won) or 1.0 - p_die < RISK_RED:
		level = "red"
	elif need > have or 1.0 - p_die < RISK_YELLOW:
		level = "yellow"
	return {"level": level, "win": bool(res.won), "p_win": 1.0 - p_die, "time_s": float(res.t), "food": need, "food_have": have,
		"hp_min_pct": float(res.hp_min) / maxf(mx, 1.0) * 100.0, "worst_hit": worst}


## Probabilità di morire nello scontro: 1 se il passaggio medio perde; altrimenti il rischio di un colpo fortunato
## (o della combo del boss) sopra la vita che l'eroe ha prima del colpo, stesso modello della stima offline (docs/05 §12).
func death_prob(res: Dictionary, mon: Dictionary, ms: Dictionary, st: Dictionary) -> float:
	if bool(res.died) or not (bool(res.won) or bool(res.timeout) or bool(res.stopped)):
		return 1.0
	return sys._death_prob_per_kill([_est_of(res, mon, ms, st)], st, false)


func _est_of(res: Dictionary, mon: Dictionary, ms: Dictionary, st: Dictionary) -> Dictionary:
	var losing := float(res.food) > 0.0 or float(res.hp_end) < float(res.hp0) - 1.0
	var mechs: Array = mon.get("mechanics", [])
	var mech: Dictionary = sys.mechanics()
	return {"loss_per_kill": 1.0 if losing else 0.0, "worst_hit": _worst_hit(mon, ms, st),
		"m_hit": Formulas.hit_chance(float(ms.accuracy), float(st.eva)), "ttk": maxf(float(res.t), 1e-6),
		"mon_interval": float(ms.attack_interval_s),
		# colpo normale e moltiplicatori delle meccaniche (sys._death_prob_per_kill li conta per tipo di colpo)
		"hit_base": _worst_hit(mon, ms, st, false),
		"heavy_mult": float(mech.get("heavy_blow", {}).get("effect", {}).get("hit_mult", 1.0)) if mechs.has("heavy_blow") else 1.0,
		"heavy_every": float(mech.get("heavy_blow", {}).get("trigger", {}).get("every_s", 1e9)),
		"enrage_mult": 1.0 + float(mech.get("enrage", {}).get("effect", {}).get("dmg_pct", 0.0)) / 100.0 if mechs.has("enrage") else 1.0}


## Colpo massimo possibile del mostro sull'eroe (con Colpo Devastante e Furia, nella fase più sfavorevole).
func _worst_hit(mon: Dictionary, ms: Dictionary, st: Dictionary, with_mech: bool = true) -> float:
	var w := float(ms.max_hit)
	var styles: Array = [str(mon.style)]
	if mon.get("phases") is Array:
		styles = []
		for ph in mon.phases:
			styles.append(str(ph.style))
	var worst := 0.0
	for sty in styles:
		var dtype := str(mon.damage_type)
		if mon.get("phases") is Array:
			dtype = "magic" if sty == "arcane" else "physical"
		var def_v := float(st.arm) if dtype == "physical" else float(st.ward)
		var hero_style := str(st.style)
		var cd := sys.class_def()
		if bool(cd.get("hybrid", false)):          # le ibride cambiano postura a ogni fase: il caso peggiore è la loro scelta
			hero_style = CombatSim.pick_stance(cd.styles, sty)
		var v := w * (1.0 - Formulas.damage_reduction(def_v, float(mon.level))) * Formulas.triangle_mult(sty, hero_style) \
			* float(st.dmg_taken_mult)
		worst = maxf(worst, v)
	if not with_mech:
		return worst
	var mechs: Array = mon.get("mechanics", [])
	if mechs.has("heavy_blow"):
		worst *= float(sys.mechanics().get("heavy_blow", {}).get("effect", {}).get("hit_mult", 1.0))
	if mechs.has("enrage"):
		worst *= 1.0 + float(sys.mechanics().get("enrage", {}).get("effect", {}).get("dmg_pct", 0.0)) / 100.0
	return worst


## Avvia l'incursione con la squadra indicata (uid dei mercenari, anche meno di quanti previsti). false se non si può.
func start_raid(raid_id: String, party: Array) -> bool:
	var rd := raid_def(raid_id)
	if rd.is_empty() or not raid_unlocked(raid_id) or raid_cd(raid_id) > 0.0:
		return false
	party = _with_companions(raid_id, party)
	if not _party_ok(party, int(rd.party.size)):
		return false
	var fx := raid_fx(raid_id, party)
	var uids: Array = []
	for u in party:
		uids.append(str(u))
	var ok := sys._begin({"zone": str(rd.zone), "monster": str(rd.boss), "mode": "raid", "raid": raid_id, "party": uids,
		"fx": fx, "t": 0.0})
	if ok:
		var m: Variant = _mercs()
		if m != null:
			for u in uids:
				m.set_busy(u, BUSY_PREFIX + raid_id)
		_fx_key = ""
		sys._st_dirty = true
		sys._push({"k": "raid_start", "raid": raid_id})
	return ok


func _raid_win(a: Dictionary) -> Dictionary:
	var c := sys
	var rid := str(a.raid)
	var rd := raid_def(rid)
	var reward: Dictionary = rd.completion_reward
	var bank: Variant = _bank()
	var gold := int(round(c.ctx.modifiers.apply(float(reward.get("gold", 0)), "gold_gain_pct", ["combat", "all"])))
	var items: Array = []
	var crates: Array = []
	for it in reward.get("items", []):
		var q := c._qty(it.get("qty", 1))
		if q > 0:
			items.append({"id": str(it.item), "qty": q})
	for cr in reward.get("crates", []):
		for i in int(cr.get("qty", 1)):
			crates.append(str(cr.id))
	var essence := _essence_qty("raid_boss")
	if essence > 0:
		items.append({"id": "era_essence", "qty": essence})
	if bank != null:
		if gold > 0:
			bank.add_gold(gold)
		for it2 in items:
			bank.add(str(it2.id), int(it2.qty), "raid")
	for cid in crates:
		c.ctx.events.crate_found.emit(str(cid), "raid:" + rid)
	var stats: Variant = c.ctx.state.get("stats")
	if stats is Dictionary:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + gold
	c.state.raid_clears[rid] = raid_clears(rid) + 1
	c.state.raid_cd[rid] = float(rd.cooldown_h) * 3600.0
	var secs := float(a.get("t", 0.0))
	var best := float(c.state.raid_best_s.get(rid, 0.0))
	if secs > 0.0 and (best <= 0.0 or secs < best):
		c.state.raid_best_s[rid] = secs
	var m: Variant = _mercs()
	var xps: Dictionary = {}
	if m != null:
		for u in a.get("party", []):
			var mm: Dictionary = m.get_merc(str(u))
			if mm.is_empty():
				continue
			var xp := float(rd.get("merc_xp", 0)) * (1.0 + float(m.trait_sum(mm, "merc_xp_pct")) / 100.0)
			m.grant_xp(str(u), xp)
			xps[str(u)] = xp
	var co: Variant = _coop()
	if co != null:
		co.on_raid_win(a)             # COOP-1: sblocca «Amici» e premia con il titolo chi ha vinto con un compagno (nessuna ricompensa extra)
	_release_party(a)
	c._push({"k": "raid_done", "raid": rid, "gold": gold, "items": items, "crates": crates, "t": secs, "merc_xp": xps})
	c.ctx.events.objective_event.emit("complete_raid", {"raid": rid, "qty": 1, "era": c._era()})
	if str(rd.boss) == WARDEN_BOSS:
		var pr: Variant = c.ctx.get_system("prestige")
		if pr != null and pr.has_method("on_warden_defeated"):
			pr.on_warden_defeated(c._era())
	c.ctx.events.important_event.emit("raid")
	return {"gold": gold, "items": items, "crates": crates.size()}


## Essenza d'Era per un tipo di mostro (era_rules.era_essence): `drop` = numero di porzioni garantite (parte frazionaria
## = probabilità), quantità per porzione = Era (qty_formula "era").
func _essence_qty(mtype: String) -> int:
	var e: Dictionary = sys.ctx.data.rules("era_rules").get("era_essence", {})
	var drops := float(e.get("drop", {}).get(mtype, 0.0))
	var n := int(floor(drops))
	var frac := drops - float(n)
	if frac > 1e-9 and sys.ctx.rng.chance("loot", frac):
		n += 1
	return n * sys._era()


func _raid_fail(a: Dictionary) -> void:
	var c := sys
	var rid := str(a.raid)
	var m: Variant = _mercs()
	var hurt: Array = []
	if m != null:
		var rules: Dictionary = c.ctx.data.rules("mercenary_rules")
		var inj: Dictionary = rules.get("injury", {})
		for u in a.get("party", []):
			var mm: Dictionary = m.get_merc(str(u))
			if mm.is_empty():
				continue
			var p := float(inj.get("chance_on_fail", 0.0)) * maxf(0.0, 1.0 + float(m.trait_sum(mm, "injury_chance_pct")) / 100.0)
			if c.ctx.rng.chance("world", p):
				m.injure(str(u), float(inj.get("duration_h", 0.0)) * 3600.0)
				hurt.append(str(u))
	_release_party(a)
	c._push({"k": "raid_failed", "raid": rid, "injured": hurt})


# ====================================================================== passaggio rapido (valori attesi)

## Un solo scontro contro `mon` col motore in modalità attesa (CombatSim.expect), passo PASS_DT. Opzioni:
##   hp_frac boss 0..1 (1 = vita piena) · hp0 vita dell'eroe · food porzioni disponibili (-1 = infinite) ·
##   ally_per_s frazione di vita del boss tolta al secondo dagli alleati simulati · limit_s tempo massimo (0 = nessuno).
## Ritorna: won, died, stopped, timeout, t, dealt (danno dell'eroe), ally, hp_min, hp_end, e_hp, e_max, phase, food,
## swings, hits, dmg_in.
func boss_pass(mon: Dictionary, ms: Dictionary, st: Dictionary, opts: Dictionary) -> Dictionary:
	var c := sys
	var sim: CombatSim = c._est_sim
	sim.configure(c._sim_params(st, mon, ms, true, opts.get("fx", {})))
	sim.rng = null
	sim.reset_acc()
	var mx := float(st.hp)
	var h := {"hp": float(opts.get("hp0", mx)), "rt": CombatSim.new_rt()}
	var a := {"enemy": {}, "hero_cd": 0.0, "mon_cd": 0.0}
	var food_box := {"n": int(opts.get("food", -1))}
	var cfg := c.auto_eat_cfg()
	var fid := c._first_food_or_slot()
	var heal_each := c._food_heal_value(fid, float(cfg.efficiency)) if not fid.is_empty() else 0.0
	var thr := mx * float(cfg.threshold_pct) / 100.0
	var target := mx * float(cfg.target_pct) / 100.0
	if heal_each > 0.0:
		sim.eat_cb = func() -> void:
			if float(h.hp) >= thr:
				return
			var guard := 0
			while float(h.hp) < target and guard < 64 and int(food_box.n) != 0:
				guard += 1
				h["hp"] = minf(mx, float(h.hp) + heal_each)
				sim.acc["food"] = float(sim.acc.food) + 1.0
				if int(food_box.n) > 0:
					food_box["n"] = int(food_box.n) - 1
	else:
		sim.eat_cb = Callable()
	sim.spawn(h, a, 1.0, float(opts.get("dmg_mult", 1.0)))
	var e: Dictionary = a.enemy
	var frac := clampf(float(opts.get("hp_frac", 1.0)), 0.0, 1.0)
	e["hp"] = float(e.max) * frac
	if sim._phased:
		sim._check_phase(e)
	var ally := float(opts.get("ally_per_s", 0.0))
	var limit := float(opts.get("limit_s", 0.0))
	var dt := float(opts.get("dt", PASS_DT))
	var t := 0.0
	var dealt := 0.0
	var ally_total := 0.0
	var hp_min := float(h.hp)
	var r := CombatSim.R_NONE
	var timeout := false
	while t < PASS_MAX_S:
		sim.tick_timers(h, dt, true)
		if float(h.hp) < mx:
			c._est_regen(h, sim, st, dt)
		if ally > 0.0:
			var take := minf(maxf(float(e.hp), 0.0), ally * float(e.max) * dt)
			e["hp"] = float(e.hp) - take
			ally_total += take
		var before := maxf(float(e.hp), 0.0)
		if float(e.hp) <= 0.0:
			r = CombatSim.R_KILL
		else:
			r = sim.step(h, a, dt)
		t += dt
		dealt += maxf(0.0, before - maxf(float(e.hp), 0.0))
		hp_min = minf(hp_min, float(h.hp))
		if r != CombatSim.R_NONE:
			break
		if limit > 0.0 and t >= limit - EPS:
			timeout = true
			break
	sim.eat_cb = Callable()
	return {"won": r == CombatSim.R_KILL, "died": r == CombatSim.R_DIE, "stopped": r == CombatSim.R_STOP, "timeout": timeout,
		"hp0": float(opts.get("hp0", mx)), "t": t, "dealt": dealt, "ally": ally_total, "hp_min": hp_min, "hp_end": maxf(float(h.hp), 0.0),
		"e_hp": maxf(float(e.hp), 0.0), "e_max": float(e.max), "phase": int(e.get("phase", 0)),
		"food": float(sim.acc.food), "swings": float(sim.acc.swings), "hits": float(sim.acc.hits), "dmg_in": float(sim.acc.dmg_in)}


# ====================================================================== BOSS MONDIALI

func wb_def(boss_id: String) -> Dictionary:
	return ctx_data().get_def("world_bosses", boss_id)


func _wb_list() -> Array:
	var out: Array = ctx_data().table("world_bosses").duplicate()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.order) < int(y.order))
	return out


func wb_unlocked() -> bool:
	return _unlock_has("feature:world_bosses") or _quest_active("main_c9_q2") or _quest_done("main_c9_q2")


func _wb_spawn_s() -> float:
	var l := _wb_list()
	return float(l[0].spawn_every_h) * 3600.0 if not l.is_empty() else 14400.0


func _wb_window_s(boss_id: String = "") -> float:
	var d: Dictionary = wb_def(boss_id) if not boss_id.is_empty() else (_wb_list()[0] if not _wb_list().is_empty() else {})
	return float(d["window_min"]) * 60.0


## Boss mondiali dei dati con il miglior livello di contributo raggiunto e il numero di sconfitte.
func world_bosses() -> Array:
	var out: Array = []
	for d in _wb_list():
		out.append({"id": str(d.id), "def": d, "best": str(sys.state.wb.best.get(str(d.id), "")),
			"kills": int(sys.state.wb.kills.get(str(d.id), 0))})
	return out


## Finestra a rotazione aperta ora ("compare ogni 4 ore e resta 30 minuti"): {"boss","left_s","slot","source"} o {}.
func wb_window() -> Dictionary:
	var l := _wb_list()
	if l.is_empty():
		return {}
	var wb: Dictionary = sys.state.wb
	var spawn := _wb_spawn_s()
	var k := int(floor(float(wb.t) / spawn))
	if k < 1:
		return {}
	var off := float(wb.t) - float(k) * spawn
	var win := _wb_window_s()
	if off >= win or int(wb.done_slot) == k:
		return {}
	return {"boss": str(l[(k - 1) % l.size()].id), "left_s": win - off, "slot": k, "source": "rotation"}


## Secondi alla prossima finestra a rotazione e quale boss arriva (se ora non ce n'è una disponibile).
func wb_next() -> Dictionary:
	var l := _wb_list()
	if l.is_empty():
		return {}
	var wb: Dictionary = sys.state.wb
	var spawn := _wb_spawn_s()
	var k := int(floor(float(wb.t) / spawn)) + 1
	return {"boss": str(l[(k - 1) % l.size()].id), "in_s": float(k) * spawn - float(wb.t), "slot": k}


func wb_horn() -> Dictionary:
	return sys.state.wb.horn


## Corno dell'Adunata: evoca subito un boss mondiale a scelta (consuma un corno, la finestra dura come le altre).
func summon_world_boss(boss_id: String) -> bool:
	var d := wb_def(boss_id)
	var bank: Variant = _bank()
	if d.is_empty() or bank == null or not wb_horn().is_empty():
		return false
	var item := str(d.get("summon_item", "rally_horn"))
	if not bank.has(item, 1) or not bank.remove(item, 1):
		return false
	sys.state.wb["horn"] = {"boss": boss_id, "left_s": _wb_window_s(boss_id)}
	sys._push({"k": "wb_horn", "boss": boss_id})
	return true


## Entra nell'incontro: "rotation" (finestra a tempo) o "horn" (evocazione col Corno).
func start_world_boss(source: String) -> bool:
	if not wb_unlocked():
		return false
	var w: Dictionary = {}
	if source == "rotation":
		w = wb_window()
	elif source == "horn" and not wb_horn().is_empty():
		w = {"boss": str(wb_horn().boss), "left_s": float(wb_horn().left_s), "slot": 0, "source": "horn"}
	if w.is_empty():
		return false
	var d := wb_def(str(w.boss))
	return sys._begin({"zone": "", "monster": str(d.boss), "mode": "wboss", "wb": str(d.id), "source": source, "slot": int(w.slot),
		"left_s": float(w.left_s), "dealt": 0.0, "ally": 0.0, "t": 0.0})


func _ally_per_s(d: Dictionary) -> float:
	var base := float(d.get("simulated_allies_dps_pct_of_hp_per_min", 0.0)) / 100.0 / 60.0
	var co: Variant = _coop()
	return base if co == null else base + float(co.wb_ally_bonus(d, base))        # COOP-1: amici simulati in più


func wb_tier_for(d: Dictionary, pct: float) -> String:
	var best := ""
	for t in d.contribution_tiers:
		if pct + 1e-9 >= float(t.damage_pct):
			best = str(t.id)
	return best


## Stato dell'incontro in corso per la UI: boss, danno, % della vita, livello raggiunto e prossimo, tempo residuo.
func wb_progress() -> Dictionary:
	var a := sys._act()
	if str(a.get("mode", "")) != "wboss" or not sys.in_combat():
		return {}
	var d := wb_def(str(a.wb))
	var e: Dictionary = a.get("enemy", {})
	var mx := float(e.get("max", 0.0))
	if mx <= 0.0:
		var mon: Dictionary = ctx_data().get_def("monsters", str(d.boss))
		mx = float(sys._scaled(mon, sys._era()).hp)
	var pct := float(a.dealt) / maxf(mx, 1.0) * 100.0
	var cur := wb_tier_for(d, pct)
	var nxt: Dictionary = {}
	for t in d.contribution_tiers:
		if pct + 1e-9 < float(t.damage_pct):
			nxt = t
			break
	var hp_pct := 100.0
	if not e.is_empty():
		hp_pct = maxf(0.0, float(e.hp)) / maxf(mx, 1.0) * 100.0
	return {"boss": str(d.id), "dealt": float(a.dealt), "max": mx, "pct": pct, "tier": cur, "next": nxt, "left_s": float(a.left_s),
		"hp_pct": hp_pct, "ally_pct": float(a.ally) / maxf(mx, 1.0) * 100.0}


## Fine dell'incontro: premio del livello di contributo raggiunto (anche se l'eroe cade o si ritira), contatori ed eventi.
func _wb_finish(a: Dictionary, killed: bool) -> Dictionary:
	var c := sys
	var d := wb_def(str(a.wb))
	var mon: Dictionary = ctx_data().get_def("monsters", str(d.boss))
	var mx := float(c._scaled(mon, c._era()).hp)
	var pct := float(a.dealt) / maxf(mx, 1.0) * 100.0
	var tier := wb_tier_for(d, pct)
	var items: Array = []
	var crates: Array = []
	var bank: Variant = _bank()
	if not tier.is_empty():
		for r in d.rewards.get(tier, []):
			if r.has("chance"):
				if not c.ctx.rng.chance("loot", float(r.chance)):
					continue
				items.append({"id": str(r.item), "qty": 1})
			else:
				var q := int(r.get("qty", 1))
				if str(c.ctx.data.item(str(r.item)).get("category", "")) == "crate":
					for i in q:
						crates.append(str(r.item))
				else:
					items.append({"id": str(r.item), "qty": q})
		if bank != null:
			for it in items:
				bank.add(str(it.id), int(it.qty), "world_boss")
		for cid in crates:
			c.ctx.events.crate_found.emit(str(cid), "world_boss:" + str(d.id))
		var idx := TIER_IDS.find(tier)
		for i in idx + 1:
			c.ctx.events.objective_event.emit("world_boss", {"tier": TIER_IDS[i], "boss": str(d.id), "qty": 1})
		var wb: Dictionary = c.state.wb
		var prev := TIER_IDS.find(str(wb.best.get(str(d.id), "")))
		if idx > prev:
			wb.best[str(d.id)] = tier
	if killed:
		c.state.wb.kills[str(d.id)] = int(c.state.wb.kills.get(str(d.id), 0)) + 1
	if str(a.get("source", "")) == "rotation":
		c.state.wb["done_slot"] = int(a.get("slot", 0))
	elif str(a.get("source", "")) == "horn":
		c.state.wb["horn"] = {}
	c._push({"k": "wb_done", "boss": str(d.id), "tier": tier, "pct": pct, "killed": killed, "items": items, "crates": crates,
		"dealt": float(a.dealt)})
	c.ctx.events.important_event.emit("world_boss")
	return {"tier": tier, "items": items, "crates": crates.size(), "pct": pct}


# ====================================================================== LA BRECCIA

func rift_def() -> Dictionary:
	if not rift_override.is_empty():
		return rift_override
	var t: Array = ctx_data().table("rift")
	return t[0] if not t.is_empty() else {}


## COOP-1: svuota le cache dei mostri/stime della Breccia (cambio di Breccia della settimana).
func clear_rift_caches() -> void:
	_rift_cache.clear()
	_prev_cache.clear()
	_fx_key = ""


func rift_unlocked() -> bool:
	return _unlock_has("feature:rift") or _quest_done(str(rift_def().get("unlock", {}).get("quest", "")))


func rift_best() -> int:
	return int(sys.state.rift.best)


func rift_guardian_cleared() -> int:
	return int(sys.state.rift.guardian)


## Piani da cui si può partire: 1 e, dopo ogni Guardiano battuto, il piano successivo (punti di ripartenza).
func rift_start_options() -> Array:
	var every := int(rift_def()["guardian_every"])
	var out: Array = [1]
	var g := rift_guardian_cleared()
	var f := every
	while f <= g:
		out.append(f + 1)
		f += every
	return out


func rift_monsters_on(fl: int) -> int:
	var rd := rift_def()
	var n := int(rd.monsters_per_floor)
	return n + (1 if fl % int(rd.guardian_every) == 0 else 0)


## Affissi attivi al piano (cumulativi dal piano indicato dai dati).
func rift_affixes(fl: int) -> Array:
	var out: Array = []
	for af in rift_def().get("affixes", []):
		if fl >= int(af.from_floor):
			out.append(af)
	return out


## Mostro generato del piano: statistiche del livello (100 + piano) × stat_mult_per_floor^piano (danno × dmg_mult_per_floor^piano), affissi, stile a rotazione.
@warning_ignore("integer_division")
func rift_mon(fl: int, idx: int) -> Dictionary:
	var key := "%d:%d" % [fl, idx]
	if _rift_cache.has(key):
		return _rift_cache[key]
	var rd := rift_def()
	var guardian := idx >= int(rd.monsters_per_floor)
	var mtype := str(rd.guardian_type if guardian else rd.monster_type)
	var lvl := int(rd.floor_level_base) + fl
	var s := Formulas.monster_stats(lvl, mtype)
	var fm := pow(float(rd.stat_mult_per_floor), fl)
	# danno più piatto della vita (FIX-COMBATTIMENTO, QA4 #11): senza il campo, come prima (stesso moltiplicatore)
	var dm_f := pow(float(rd.get("dmg_mult_per_floor", rd.stat_mult_per_floor)), fl)
	var stats := {"hp": float(s.hp) * fm, "max_hit": float(s.max_hit) * dm_f, "accuracy": float(s.accuracy) * fm,
		"evasion": float(s.evasion) * fm, "armor": float(s.armor) * fm, "ward": float(s.ward) * fm,
		"attack_interval_s": float(s.attack_interval_s)}
	var ls := 0.0
	for af in rift_affixes(fl):
		var fx: Dictionary = af.effect
		stats.hp = float(stats.hp) * (1.0 + float(fx.get("hp_pct", 0.0)) / 100.0)
		stats.max_hit = float(stats.max_hit) * (1.0 + float(fx.get("dmg_pct", 0.0)) / 100.0)
		stats.evasion = float(stats.evasion) * (1.0 + float(fx.get("evasion_pct", 0.0)) / 100.0)
		var dm := 1.0 + float(fx.get("defense_pct", 0.0)) / 100.0
		stats.armor = float(stats.armor) * dm
		stats.ward = float(stats.ward) * dm
		ls += float(fx.get("lifesteal_pct", 0.0))
	var cyc: Array = rd.styles_cycle
	var style := str(cyc[(fl - 1) % cyc.size()])
	var names: Array = rd.guardian_names if guardian else rd.monster_names
	@warning_ignore("integer_division")
	var nm: Dictionary = names[((fl / int(rd.guardian_every)) - 1 if guardian else (fl + idx)) % names.size()]
	var mon := {"id": "rift_guardian" if guardian else "rift_shade", "ckey": "rift:" + key, "name": nm, "level": lvl,
		"type": mtype, "style": style, "damage_type": "magic" if style == "arcane" else "physical",
		"weakness": "", "resistance": "", "stats": stats, "xp": s.xp, "gold": [s.gold_min, s.gold_max],
		"drop_table": "", "mechanics": (rd.guardian_mechanics as Array).duplicate() if guardian else [], "lifesteal_pct": ls,
		"rift": true, "floor": fl}
	_rift_cache[key] = mon
	return mon


func start_rift(fl: int) -> bool:
	if not rift_unlocked() or not rift_start_options().has(fl):
		return false
	var ok := sys._begin({"zone": "", "monster": "", "mode": "rift", "floor": fl, "idx": 0, "start_floor": fl})
	if ok:
		sys.state.rift["runs"] = int(sys.state.rift.runs) + 1
		_reach_floor(fl)
	return ok


func _reach_floor(fl: int) -> void:
	var rf: Dictionary = sys.state.rift
	if fl > int(rf.best):
		rf["best"] = fl
	sys.ctx.events.objective_event.emit("rift_floor", {"floor": fl})


## Fine di un piano: Frammenti (con rift_shard_pct), Cassa della Breccia a probabilità crescente, premi del Guardiano.
@warning_ignore("integer_division")
func _rift_floor_done(_a: Dictionary, fl: int) -> void:
	var c := sys
	var rd := rift_def()
	var sh: Dictionary = rd.shards
	@warning_ignore("integer_division")
	var shards := int(sh.base) + fl / int(sh.per_floors)
	shards = int(round(c.ctx.modifiers.apply(float(shards), "rift_shard_pct")))
	var cc: Dictionary = rd.crate_chance
	var p := minf(float(cc.max), float(cc.base) + float(cc.per_floor) * fl)
	p *= 1.0 + c.ctx.modifiers.total_add_capped("crate_find_pct", ["combat", "all"]) / 100.0
	var crates: Array = []
	var items: Array = [{"id": "rift_shard", "qty": shards}]
	if c.ctx.rng.chance("loot", minf(1.0, p)):
		crates.append(str(rd.crate))
	var guardian := fl % int(rd.guardian_every) == 0
	if guardian:
		for r in rd.guardian_rewards:
			if str(c.ctx.data.item(str(r.item)).get("category", "")) == "crate":
				for i in int(r.qty):
					crates.append(str(r.item))
			else:
				var q := int(r.qty) * (c._era() if str(r.item) == "era_essence" else 1)
				items.append({"id": str(r.item), "qty": q})
		c.state.rift["guardian"] = maxi(int(c.state.rift.guardian), fl)
	var bank: Variant = _bank()
	if bank != null:
		for it in items:
			bank.add(str(it.id), int(it.qty), "rift")
	for cid in crates:
		c.ctx.events.crate_found.emit(str(cid), "rift:" + str(fl))
	c.state.rift["shards"] = int(c.state.rift.shards) + shards
	c._push({"k": "rift_floor", "floor": fl, "items": items, "crates": crates, "guardian": guardian})
	_reach_floor(fl + 1)


func _rift_end(a: Dictionary, died: bool) -> void:
	var c := sys
	if died:
		c.state.rift["deaths"] = int(c.state.rift.deaths) + 1
	c._push({"k": "rift_end", "floor": int(a.get("floor", 1)), "start": int(a.get("start_floor", 1)), "died": died})


# ====================================================================== negozi a valuta (Sala dei Trofei, Bazar della Breccia)

func shop_def(shop_id: String) -> Dictionary:
	return ctx_data().get_def("currency_shops", shop_id)


## Voci del negozio con costo e quantità posseduta della valuta: [{item, cost, note, can_buy}].
func shop_items(shop_id: String) -> Array:
	var d := shop_def(shop_id)
	var out: Array = []
	var bank: Variant = _bank()
	var have: int = int(bank.count(str(d.get("currency", "")))) if bank != null and not d.is_empty() else 0
	for it in d.get("items", []):
		out.append({"item": str(it.item), "cost": int(it.cost), "note": str(it.get("note", "")), "can_buy": have >= int(it.cost)})
	return out


## Compra `qty` pezzi pagando nella valuta del negozio (Sigilli d'Incursione, Frammenti di Breccia…).
func shop_buy(shop_id: String, item_id: String, qty: int = 1) -> bool:
	var d := shop_def(shop_id)
	var bank: Variant = _bank()
	if d.is_empty() or bank == null or qty <= 0:
		return false
	for it in d.items:
		if str(it.item) != item_id:
			continue
		var total := int(it.cost) * qty
		if not bank.has(str(d.currency), total) or not bank.remove(str(d.currency), total):
			return false
		bank.add(item_id, qty, "currency_shop")
		sys._push({"k": "shop_buy", "shop": shop_id, "item": item_id, "qty": qty})
		return true
	return false


# ====================================================================== ganci di CombatSystem

## Un passo dell'incontro: stesso motore, più (boss mondiali) gli alleati simulati, il danno dell'eroe e la finestra.
func step(a: Dictionary, dt: float) -> int:
	a["t"] = float(a.get("t", 0.0)) + dt
	if str(a.get("mode", "")) != "wboss":
		return sys._sim.step(sys.state, a, dt)
	var e: Dictionary = a.enemy
	var d := wb_def(str(a.wb))
	var take := minf(maxf(float(e.hp), 0.0), _ally_per_s(d) * float(e.max) * dt)
	e["hp"] = float(e.hp) - take
	a["ally"] = float(a.ally) + take
	a["left_s"] = float(a.left_s) - dt
	var before := maxf(float(e.hp), 0.0)
	var r := CombatSim.R_KILL if float(e.hp) <= 0.0 else sys._sim.step(sys.state, a, dt)
	a["dealt"] = float(a.dealt) + maxf(0.0, before - maxf(float(e.hp), 0.0))
	if r == CombatSim.R_NONE and float(a.left_s) <= 0.0:
		return R_TIMEOUT
	return r


## Mostro del modo corrente (per _spawn / _enemy_mon).
func mon_for(a: Dictionary) -> Dictionary:
	match str(a.get("mode", "")):
		"raid", "wboss":
			return ctx_data().get_def("monsters", str(a.monster))
		"rift":
			return rift_mon(int(a.floor), int(a.idx))
	return {}


## Dopo l'uccisione generica (XP, oro, drop già consegnati da CombatSystem._kill).
func after_kill(a: Dictionary, _mon: Dictionary) -> void:
	match str(a.get("mode", "")):
		"raid":
			_raid_win(a)
			sys._end_endgame()
			sys._st_dirty = true
		"wboss":
			_wb_finish(a, true)
			sys._end_endgame()
			sys._st_dirty = true
		"rift":
			a["idx"] = int(a.idx) + 1
			if int(a.idx) >= rift_monsters_on(int(a.floor)):
				_rift_floor_done(a, int(a.floor))
				a["floor"] = int(a.floor) + 1
				a["idx"] = 0


## L'eroe è caduto (dopo l'attesa): fine dell'incontro. Il chiamante svuota l'attività.
func on_fail(a: Dictionary) -> void:
	match str(a.get("mode", "")):
		"raid":
			_raid_fail(a)
		"wboss":
			_wb_finish(a, false)
		"rift":
			_rift_end(a, true)


## Ritirata voluta: i mercenari tornano liberi, il boss mondiale paga per il contributo, la Breccia registra la fine.
func on_stop(a: Dictionary) -> void:
	match str(a.get("mode", "")):
		"raid":
			_release_party(a)
		"wboss":
			_wb_finish(a, false)
		"rift":
			_rift_end(a, false)


func on_timeout(a: Dictionary) -> void:
	if str(a.get("mode", "")) == "wboss":
		_wb_finish(a, false)
	sys._end_endgame()
	sys._st_dirty = true


# ====================================================================== offline

## Offline di un'attività di fine gioco. `en0` = nemico in campo alla chiusura (vuoto se non c'era).
func offline(a: Dictionary, left: float, report: Dictionary, en0: Dictionary) -> Dictionary:
	match str(a.get("mode", "")):
		"raid":
			return _offline_boss(a, left, report, en0, false)
		"wboss":
			return _offline_boss(a, left, report, en0, true)
		"rift":
			return _offline_rift(a, left, report)
	return {}


func _offline_boss(a: Dictionary, left: float, report: Dictionary, en0: Dictionary, world: bool) -> Dictionary:
	var c := sys
	var mon: Dictionary = ctx_data().get_def("monsters", str(a.monster))
	if mon.is_empty() or left <= 0.0:
		return {}
	var ms := c._scaled(mon, c._era())
	var st := c._stats_for(c.stance_for(mon))
	if not world:
		st = apply_fx(st, a.get("fx", {}))
	var frac := 1.0
	if not en0.is_empty() and float(en0.get("max", 0.0)) > 0.0:
		frac = clampf(float(en0.hp) / float(en0.max), 0.001, 1.0)
	var opts := {"hp0": float(c.state.hp), "hp_frac": frac, "food": c.food_available(), "limit_s": left}
	if not world:
		opts["fx"] = a.get("fx", {})
	var d: Dictionary = {}
	if world:
		d = wb_def(str(a.wb))
		opts["ally_per_s"] = _ally_per_s(d)
		opts["limit_s"] = minf(left, maxf(float(a.left_s), 0.0))
	var res := boss_pass(mon, ms, st, opts)
	if (bool(res.won) or bool(res.timeout)) and c.ctx.rng.chance("combat", death_prob(res, mon, ms, st)):
		res["won"] = false          # colpo fortunato del boss durante lo scontro: stessa probabilità del tick (flusso "combat")
		res["died"] = true
		res["timeout"] = false
	if bool(res.died) and c.ctx.mode_rules().offline_stops_before_death():
		on_stop(a)                    # Estrema: l'Eroe non affronta offline uno scontro che potrebbe ucciderlo (OPEN_QUESTIONS M-2)
		c._end_endgame()
		report["stopped"] = "death_risk"
		return report
	report["monster"] = str(mon.id)
	report["seconds"] = float(res.t)
	var food_used := int(ceil(float(res.food) - 1e-9))
	a["t"] = float(a.get("t", 0.0)) + float(res.t)
	if world:
		a["dealt"] = float(a.dealt) + float(res.dealt)
		a["ally"] = float(a.ally) + float(res.ally)
		a["left_s"] = float(a.left_s) - float(res.t)
	if bool(res.won):
		var mon2 := mon
		var rare := true
		if world:
			mon2 = mon.duplicate()
			mon2["drop_table"] = ""
		c._settle_offline(a, [{"mon": mon2, "n": 1}], 1, 1, food_used, report, [{"swings": res.swings, "hits": res.hits}], rare)
		c.state["hp"] = maxf(1.0, float(res.hp_end))
		if world:
			var info := _wb_finish(a, true)
			report["rows"] = [{"key": "UI_RAID_WB_REPORT", "params": {"boss": Loc.t(mon.name), "tier": _tier_label(str(info.tier))}}]
		else:
			var info2 := _raid_win(a)
			report["rows"] = [{"key": "UI_RAID_OFF_WIN", "params": {"raid": Loc.t(raid_def(str(a.raid)).name)}}]
			report["crates"] = int(report.get("crates", 0)) + int(info2.crates)
			report["gold"] = int(report.get("gold", 0)) + int(info2.gold)
			var itm: Dictionary = report.get("items", {})
			for it in info2.items:
				itm[str(it.id)] = int(itm.get(str(it.id), 0)) + int(it.qty)
			report["items"] = itm
		c._end_endgame()
		c._st_dirty = true
		return report
	if bool(res.died):
		c._consume_food_units(food_used)
		c._push({"k": "die", "m": str(mon.id)})
		c.state["deaths"] = int(c.state.deaths) + 1
		c.ctx.events.player_died.emit(str(mon.id))
		c.state["wounded_s"] = float(c._rules().death_wounded_duration_s)
		c._st_dirty = true
		c.state["hp"] = float(c._stats().hp)
		on_fail(a)
		c._end_endgame()
		report["stopped"] = "death"
		report["died"] = true
		report["food_used"] = food_used
		return report
	# né vittoria né morte: tempo finito (finestra o ore lontano) o risorse finite
	c._consume_food_units(food_used)
	c.state["hp"] = maxf(1.0, float(res.hp_end))
	report["food_used"] = food_used
	if world and (bool(res.timeout) and float(a.left_s) <= EPS):
		_wb_finish(a, false)
		report["rows"] = [{"key": "UI_RAID_WB_REPORT", "params": {"boss": Loc.t(mon.name), "tier": _tier_label(wb_tier_for(d, float(a.dealt) / maxf(float(res.e_max), 1.0) * 100.0))}}]
		c._end_endgame()
		c._st_dirty = true
		return report
	if bool(res.stopped):
		on_stop(a)
		c._end_endgame()
		report["stopped"] = "no_ammo"
		return report
	# l'incontro prosegue al ritorno: nemico rigenerato con la vita residua
	c._sync_sim(mon, ms)
	c._sim.spawn(c.state, a, 1.0)
	(a.enemy as Dictionary)["hp"] = float(res.e_hp)
	(a.enemy as Dictionary)["phase"] = int(res.phase)
	return report


func _tier_label(tier: String) -> String:
	if tier.is_empty():
		return tr("UI_RAID_TIER_NONE")
	return tr("UI_RAID_TIER_" + tier.to_upper())


## Breccia offline: piani in sequenza finché bastano il tempo e il cibo e finché la somma dei rischi di morte dei piani
## resta sotto 1 (stesso criterio degli altri offline: l'eroe muore dopo ~1/p scontri). Ogni piano è valutato col motore
## in modalità attesa; le ricompense (Frammenti, Casse, Guardiani, XP, oro) sono estratte davvero.
func _offline_rift(a: Dictionary, left: float, report: Dictionary) -> Dictionary:
	var c := sys
	var fl := int(a.floor)
	var f0 := fl
	var idx0 := int(a.idx)
	var t_used := 0.0
	var food_used := 0.0
	var food_have := float(c.food_available())
	var hazard := 0.0
	var stop_reason := ""
	var evals: Dictionary = {}
	var cleared: Array = []
	var guard := 0
	while guard < RIFT_FLOORS_CAP:
		guard += 1
		var ev := _rift_floor_eval(fl, evals)
		var frac := 1.0
		if fl == f0 and idx0 > 0:
			frac = 1.0 - float(idx0) / float(rift_monsters_on(fl))
		if t_used + float(ev.t) * frac > left + EPS:
			break
		if float(ev.food) > 0.0 and food_used + float(ev.food) * frac > food_have + EPS:
			stop_reason = "no_food"
			break
		if hazard + float(ev.p) * frac >= 1.0:
			stop_reason = "death_risk" if c.ctx.mode_rules().offline_stops_before_death() else "death"
			break
		t_used += float(ev.t) * frac
		food_used += float(ev.food) * frac
		hazard += float(ev.p) * frac
		cleared.append(fl)
		fl += 1
	var kills := 0
	var gold := 0
	var xp := 0.0
	var era := c._era()
	for cf in cleared:
		for i in rift_monsters_on(int(cf)):
			var mon := rift_mon(int(cf), i)
			kills += 1
			xp += float(mon.xp) * Formulas.era_reward_mult(era)
			gold += c._roll_gold(mon, era)
		_rift_floor_done({}, int(cf))
	var bank: Variant = _bank()
	if bank != null and gold > 0:
		bank.add_gold(gold)
	var sk: Variant = c._skills()
	if sk != null and xp > 0.0:
		sk.add_xp("hero", xp)
	var stats: Variant = c.ctx.state.get("stats")
	if stats is Dictionary:
		stats["gold_earned"] = int(stats.get("gold_earned", 0)) + gold
		stats["kills"] = int(stats.get("kills", 0)) + kills
	if kills > 0:
		var kd: Dictionary = c.state.kills
		kd["rift_shade"] = int(kd.get("rift_shade", 0)) + kills
		c.ctx.events.monsters_killed_batch.emit("rift_shade", kills, [])
	var used_food := int(ceil(food_used - 1e-9))
	c._consume_food_units(used_food)
	report["kills"] = kills
	report["xp"] = xp
	report["gold"] = gold
	report["food_used"] = used_food
	report["seconds"] = t_used
	report["monster"] = "rift_shade"
	report["monster_name"] = rift_def().get("name", "")
	report["rows"] = [{"key": "UI_RAID_OFF_RIFT", "params": {"from": f0, "to": maxi(f0, fl - 1), "n": cleared.size()}}]
	a["floor"] = fl
	if stop_reason == "death":
		c._push({"k": "die", "m": "rift_shade"})
		c.state["deaths"] = int(c.state.deaths) + 1
		c.ctx.events.player_died.emit("rift_shade")
		c.state["wounded_s"] = float(c._rules().death_wounded_duration_s)
		c._st_dirty = true
		c.state["hp"] = float(c._stats().hp)
		_rift_end(a, true)
		c._end_endgame()
		report["stopped"] = "death"
		report["died"] = true
	elif stop_reason == "no_food" or stop_reason == "death_risk":
		_rift_end(a, false)
		c._end_endgame()
		report["stopped"] = stop_reason
	else:
		a["idx"] = 0
		c.state["hp"] = float(c._stats().hp)
	return report


## Valutazione di un piano: tempo (scontri + ricomparse), porzioni di cibo e probabilità di morte. Passaggio rapido in
## sequenza dei mostri del piano, con la vita che passa da uno scontro all'altro.
func _rift_floor_eval(fl: int, cache: Dictionary) -> Dictionary:
	if cache.has(fl):
		return cache[fl]
	var c := sys
	var era := c._era()
	var cfg := c.auto_eat_cfg()
	var fid := c._first_food_or_slot()
	var eating := not fid.is_empty()
	var mx := float(c._stats().hp)
	var thr := mx * float(cfg.threshold_pct) / 100.0
	var hp := (thr + mx * float(cfg.target_pct) / 100.0) * 0.5 if eating else mx
	var t := 0.0
	var food := 0.0
	var respawn := float(Formulas.k().combat.respawn_s)
	var ests: Array = []
	var lethal := false
	var rfx := _rift_fx(fl)
	var st_last: Dictionary = c._stats()
	for i in rift_monsters_on(fl):
		var mon := rift_mon(fl, i)
		var ms := c._scaled(mon, era)
		var st := c._stats_for(c.stance_for(mon))
		if not rfx.is_empty():
			st = apply_fx(st, rfx)
		st_last = st
		var res := boss_pass(mon, ms, st, {"hp0": hp, "food": -1 if eating else 0, "dt": RIFT_PASS_DT, "fx": rfx})
		t += float(res.t) + respawn
		food += float(res.food)
		if not bool(res.won):
			lethal = true
			break
		ests.append(_est_of(res, mon, ms, st))
		hp = minf(mx, float(res.hp_end) + mx * float(st.regen_pct) / 100.0 * respawn)
	var p := 1.0 if lethal else c._death_prob_per_kill(ests, st_last, true)
	var out := {"floor": fl, "t": t, "food": food, "p": p}
	cache[fl] = out
	return out


## Stima per la UI: piano a cui la somma dei rischi arriva a 1 partendo da `start` (con cibo infinito), con tetto.
func rift_estimate_limit(start: int) -> int:
	var key := "lim:%d:%d:%d:%s" % [start, sys._gen, sys._era(), sys._est_food_sig()]
	if _prev_cache.has(key):
		return int(_prev_cache[key])
	var evals: Dictionary = {}
	var hazard := 0.0
	var f := start
	while f < start + RIFT_FLOORS_CAP:
		hazard += float(_rift_floor_eval(f, evals).p)
		if hazard >= 1.0:
			break
		f += 1
	_prev_cache[key] = f
	return f
