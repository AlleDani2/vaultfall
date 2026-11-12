class_name PrestigeSystem
extends GameSystem
## Prestigio a strati (docs/13, regola 9 di CLAUDE.md). id "prestige", stato `prestige`.
##
## STRATI IMPLEMENTATI (pensati per le prime 20-40 ore):
##   Stella di Mansione  reset di UNA mansione (livello -> 1) per bonus permanenti + Polvere Stellare. Requisito: livello 100.
##   Rito                la Stella "di prova" (audit 03 #2): una volta per mansione, già a livello `prestige.rite_level` (50, dai dati).
##                       Stessi bonus e stessa Polvere della prima Stella; serve a far capire il giro "azzero -> torno più forte".
##   Polvere Stellare    valuta `stardust` del Deposito (bank.add_currency / spend_currency): UNICA fonte di verità. Il campo
##                       legacy `prestige.stardust` non si usa. Bonus `stardust_gain_pct` la aumenta.
##   Costellazioni       albero di 35 nodi (data/constellations.json) comprati con la Polvere; passano da Modifiers
##                       (fonte "constellation"). Rimborso totale gratis ogni `respec_free_interval_s` (tempo di gioco), poi a pagamento.
##   Rifondazione        reset della Tenuta per i Soci (+2% produzione ciascuno). Legge `estate.prosperity` (unità a vita) o
##                       `estate.lifetime_units()`; azzera la Tenuta con `estate.reset_for_refounding()` se il sistema esiste.
##   Grandi Obiettivi    premi forti in Polvere (constants.prestige.goals), riscossi da soli, una sola volta.
##   Consigliere         `advise()`: UN solo suggerimento alla volta (Stella > Rito > Rifondazione > Polvere da spendere > niente).
##
##   Ere     (audit 43) era_max/era_current vivono qui (li legge CombatSystem: mostri ×1,35^(N-1), ricompense ×(1+0,3(N-1)) con
##           Formulas.era_*). `preview_era`/`do_select_era` (nulla si perde, ma i mostri si irrobustiscono: l'anteprima lo dice),
##           `on_warden_defeated(era)` la chiama il combattimento quando cade il Custode: sblocca l'Era successiva e paga la
##           Polvere del Custode (5 × era) SOLO alla prima uccisione di ogni Era (regola 9: niente anello Polvere -> danno -> Custodi).
##   Prove   (audit 43) 8 sfide × 5 gradi. `preview_trial`/`start_trial`: si combatte nell'Era I con le restrizioni dei dati; il sistema
##           stesso ascolta uccisioni, morti, cibo mangiato e dungeon completati (EventBus) e promuove/boccia la Prova; premio permanente
##           (Modifiers, fonte `trial:<id>`) + Polvere, una sola volta per grado. Le regole che solo il combattimento può far rispettare
##           (`no_abilities`, `forced_disadvantage`, `monster_hp_mult`) sono esposte da `trial_rules_active()`.
##   Stagioni  post-lancio (docs/27): nessun codice.
##
## Regole: ogni bonus che accelera lo STESSO strato è asintotico (docs/13 §1, dati: curve cap*(1-decay^n)); i nodi con
## livelli infiniti non toccano la velocità delle Stelle. Controlli nel simulatore: tools/balance_sim.py §8-§10.
## Anteprima obbligatoria: preview_*() calcola ESATTAMENTE ciò che do_*() applica (test: test_prestige.gd).
## Le anteprime sono Dictionary con testi come chiavi UI + parametri numerici (il sistema non traduce nulla).

const SRC_STAR := "star:"
const SRC_CONSTELLATION := "constellation"
const SRC_PARTNERS := "prestige:partners"
const DUST := "stardust"
const TOKEN_FEATURE := "feature:prestige"
const HOUSEKEEPING_EVERY_S := 1.0
const SRC_TRIAL := "trial:"
const SRC_TRIAL_ACTIVE := "trial_active"
const TOKEN_TRIALS := "feature:trials"

## Nodi il cui effetto non è collegato a un sistema di gioco: la UI li marca "dormienti" e nei dati hanno max_level 0
## (non si comprano). echo_mult_pct è dormiente per scelta di bilanciamento: applicato per intero porterebbe la Stella a
## ~1,6 h contro il pavimento di 4 h (balance_sim §10); auto_sell_unlock aspetta le regole di vendita automatica (G14).
## G13: monster_drop_pct (CombatSystem), shards_pct (CrateSystem), key_craft_save_pct (SkillSystem, chiavi forgiate) e
## xp_tome_pct (SkillSystem.tome_xp) ora hanno effetto.
const DORMANT_FAMILIES: PackedStringArray = ["echo_mult_pct"]

var _clock_acc: float = 0.0
var _skill_defs: Dictionary = {}


func _init() -> void:
	id = "prestige"
	state_key = "prestige"


# ------------------------------------------------------------------ ciclo di vita

func setup() -> void:
	_skill_defs.clear()
	for s in ctx.data.table("skills"):
		_skill_defs[s.id] = s
	# Callback come metodi (non lambda): un sistema distrutto si scollega da solo (stesso schema di QuestSystem).
	var ev: Object = ctx.events
	if not ev.monster_killed.is_connected(_cb_monster_killed):
		ev.monster_killed.connect(_cb_monster_killed)
		ev.player_died.connect(_cb_player_died)
		ev.item_removed.connect(_cb_item_removed)
		ev.objective_event.connect(_cb_objective_event)
		ev.monsters_killed_batch.connect(_cb_monsters_killed_batch)


## `trials`: id Prova -> gradi superati (0-5). `trial_active`: {} oppure {id, tier, started_s, era_restore} (la Prova in corso).
## `era_kills`: "N" -> uccisioni del Custode nell'Era N. Campi aggiunti all'audit 43: i salvataggi vecchi li ricevono
## dai valori di default in from_state (nessun cambio di forma dei campi già rilasciati, quindi nessuna migrazione di schema).
func default_state() -> Variant:
	return {
		"stardust": 0, "constellations": {}, "era_max": 1, "era_current": 1, "trials": {},
		"rites": {}, "perk_memory": {}, "partners": 0, "partners_basis": 0, "refoundings": 0,
		"stardust_spent": 0, "goals": {}, "clock_s": 0.0, "respec_last_s": -1.0,
		"era_kills": {}, "trial_active": {},
	}


func from_state(section: Variant) -> void:
	state = section
	var base: Dictionary = default_state()
	for k in base:
		if state.has(k) and typeof(state[k]) == TYPE_INT and typeof(base[k]) == TYPE_FLOAT:
			state[k] = float(state[k])
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	for nid in state.constellations.keys():       # nodo rimosso dai dati: ignorato
		if not ctx.data.has_def("constellations", str(nid)):
			state.constellations.erase(nid)
	_refund_retired_levels()
	for sk in state.rites.keys():
		if not _skill_defs.has(str(sk)):
			state.rites.erase(sk)
	state["era_max"] = maxi(1, int(state.era_max))
	state["era_current"] = clampi(int(state.era_current), 1, int(state.era_max))
	_sanitize_eras_and_trials()
	_clock_acc = 0.0
	_absorb_legacy_partners()
	_rebuild_all_modifiers()


## G13: livelli oltre il massimo attuale dei dati (nodo ritirato, es. Vendita Automatica a max 0): tornano Polvere,
## al costo pagato per ciascun livello. Nessun cambio di forma del salvataggio.
func _refund_retired_levels() -> void:
	var refund := 0
	for nid in state.constellations.keys():
		var mx := node_max_level(str(nid))
		var lv := int(state.constellations[nid])
		if mx < 0 or lv <= mx:
			continue
		for l in range(mx, lv):
			refund += node_cost(str(nid), l)
		if mx == 0:
			state.constellations.erase(nid)
		else:
			state.constellations[nid] = mx
	if refund > 0:
		state["stardust_spent"] = maxi(0, int(state.stardust_spent) - refund)
		_add_dust(refund)


## Salvataggi precedenti all'unificazione (audit 42): la Tenuta aveva un suo contatore di Soci (`estate.partners`).
## Si tiene il maggiore dei due (non si somma: erano la stessa Rifondazione contata due volte) e si azzera il vecchio.
func _absorb_legacy_partners() -> void:
	var est: Variant = ctx.state.get("estate")
	if not (est is Dictionary):
		return
	var legacy := int((est as Dictionary).get("partners", 0))
	if legacy <= 0:
		return
	state["partners"] = maxi(int(state.partners), legacy)
	state["partners_basis"] = maxi(int(state.partners_basis), legacy)
	(est as Dictionary)["partners"] = 0


func int_paths() -> PackedStringArray:
	return PackedStringArray(["stardust", "constellations.*", "era_max", "era_current", "partners", "partners_basis",
		"refoundings", "stardust_spent", "era_kills.*", "trials.*", "trial_active.tier", "trial_active.era_restore",
		"trial_active.food_eaten"])


func tick(dt: float) -> void:
	state["clock_s"] = float(state.clock_s) + dt
	_track_trial_engage()
	_check_trial_clock()
	_clock_acc += dt
	if _clock_acc >= HOUSEKEEPING_EVERY_S:
		_clock_acc = 0.0
		_housekeeping()


## Offline: niente tick; solo il tempo di gioco (per il rimborso gratuito) e i controlli periodici.
## Una Prova a tempo («Contro il Tempo») non sopravvive all'offline: è ANNULLATA (niente si perde, l'Era torna) con
## una riga chiara nel Bentornato; le altre restano in corso (il bersaglio battuto offline conta, vedi
## `_cb_monsters_killed_batch`).
func simulate_offline(seconds: float) -> Dictionary:
	var out := {}
	if is_trial_active() and trial_rules_active().has("time_limit_s") and seconds > 0.0:
		var tname := Loc.t(trial_def(str(state.trial_active.id)).get("name", {}))
		trial_fail("UI_TRIALS_FAIL_OFFLINE")
		out = {"rows": [{"key": "UI_TRIALS_WB_CANCELLED", "params": {"name": tname}}]}
	state["clock_s"] = float(state.clock_s) + maxf(0.0, seconds)
	_check_trial_clock()
	_housekeeping()
	return out


## Sblocco di `feature:prestige` e riscossione dei Grandi Obiettivi.
func _housekeeping() -> void:
	if not _has_unlock(TOKEN_FEATURE):
		var rite_lv := rite_level()
		var show := _has_unlock("feature:skill_prestige") or _has_unlock("feature:constellations")
		if not show:
			for sk in _prestige_skills():
				if _record_level(sk) >= rite_lv:
					show = true
					break
		if show:
			_grant(TOKEN_FEATURE)
	if _has_unlock(TOKEN_FEATURE):
		check_goals()
		if not _has_unlock(TOKEN_TRIALS) and trials_unlocked():
			_grant(TOKEN_TRIALS)


# ------------------------------------------------------------------ costanti e letture di base

func _k() -> Dictionary:
	return ctx.constants().get("prestige", {})


func rite_level() -> int:
	return int(_k()["rite_level"])


func _bank() -> GameSystem:
	return ctx.get_system("bank")


func _skills() -> GameSystem:
	return ctx.get_system("skills")


func _has_unlock(token: String) -> bool:
	return (ctx.state.get("unlocks", []) as Array).has(token)


func _grant(token: String) -> void:
	var u: GameSystem = ctx.get_system("unlock")
	if u != null:
		u.call("grant", token)
	else:
		var list: Array = ctx.state.get("unlocks", [])
		if not list.has(token):
			list.append(token)
			ctx.events.unlocked.emit(token)


func dust() -> int:
	var b := _bank()
	return int(b.call("currency", DUST)) if b != null else 0


func _add_dust(n: int) -> void:
	var b := _bank()
	if b != null and n > 0:
		b.call("add_currency", DUST, n)


func _spend_dust(n: int) -> bool:
	if n <= 0:
		return true
	var b := _bank()
	return b != null and bool(b.call("spend_currency", DUST, n))


## Polvere finale per un guadagno base: `stardust_gain_pct` (add) la aumenta.
func _boost_dust(base: int) -> int:
	var mult := 1.0 + ctx.modifiers.total_add("stardust_gain_pct", []) / 100.0
	return int(floor(float(base) * mult + 1e-9))


func _prestige_skills() -> Array:
	var out: Array = []
	for row in ctx.data.table("skill_prestige"):
		out.append(str(row.skill))
	return out


func _prow(skill_id: String) -> Dictionary:
	return ctx.data.get_def("skill_prestige", skill_id)


func _skill_state(skill_id: String) -> Dictionary:
	return ctx.state.get("skills", {}).get(skill_id, {})


func skill_level(skill_id: String) -> int:
	return int(_skill_state(skill_id).get("level", 1))


func _record_level(skill_id: String) -> int:
	return maxi(int(_skill_state(skill_id).get("record_level", 1)), skill_level(skill_id))


func stars(skill_id: String) -> int:
	return int(_skill_state(skill_id).get("stars", 0))


func stars_total() -> int:
	var t := 0
	for sk in _prestige_skills():
		t += stars(sk)
	return t


# ------------------------------------------------------------------ bonus delle Stelle (via Modifiers)

## Elenco {key, value, mode} dei bonus permanenti di `n` Stelle di una mansione: curve asintotiche
## `cap*(1-decay^n)`, lineari per stella, traguardi (5★, 10★ ...). Fonte unica per Modifiers e per le anteprime.
func star_mods(skill_id: String, n: int) -> Array:
	var out: Array = []
	var row := _prow(skill_id)
	if row.is_empty() or n <= 0:
		return out
	for c in row.get("curves", []):
		out.append({"key": str(c.key), "value": Formulas.star_curve(float(c.cap), float(c.decay), n), "mode": str(c.mode)})
	for l in row.get("per_star_linear", []):
		out.append({"key": str(l.key), "value": float(l.value) * float(n), "mode": str(l.mode)})
	for m in row.get("milestones", []):
		if n >= int(m.stars):
			for mm in m.get("modifiers", []):
				out.append({"key": str(mm.key), "value": float(mm.value), "mode": str(mm.get("mode", "add"))})
	return out


func _refresh_star_source(skill_id: String) -> void:
	ctx.modifiers.set_source(SRC_STAR + skill_id, star_mods(skill_id, stars(skill_id)))


## Somma (add) e prodotto (more) di una famiglia in un elenco di bonus, per gli ambiti dati.
func _family_totals(mods: Array, family: String, scopes: Array) -> Vector2:
	var add := 0.0
	var more := 1.0
	for m in mods:
		var parts := str(m.key).split(":")
		if parts[0] != family:
			continue
		if parts.size() > 1 and not scopes.has(parts[1]):
			continue
		if str(m.mode) == "more":
			more *= 1.0 + float(m.value) / 100.0
		else:
			add += float(m.value)
	return Vector2(add, more)


# ------------------------------------------------------------------ STELLE e RITO

func star_requirement(skill_id: String) -> int:
	return int(_prow(skill_id).get("requires_level", 100))


## "" se la Stella si può ottenere ora, altrimenti la chiave del motivo.
func can_star(skill_id: String) -> String:
	if _prow(skill_id).is_empty() or _skills() == null:
		return "UI_PRESTIGE_REASON_NO_SKILL"
	if skill_level(skill_id) < star_requirement(skill_id):
		return "UI_PRESTIGE_REASON_LEVEL"
	return ""


func rite_done(skill_id: String) -> bool:
	return bool(state.rites.get(skill_id, false))


## Il Rito: livello >= rite_level, mai fatto per questa mansione e nessuna Stella ancora (altrimenti non serve).
func can_rite(skill_id: String) -> String:
	if _prow(skill_id).is_empty() or _skills() == null:
		return "UI_PRESTIGE_REASON_NO_SKILL"
	if (_k().get("rite_excluded_skills", []) as Array).has(skill_id):
		return "UI_PRESTIGE_REASON_RITE_HERO"
	if rite_done(skill_id) or stars(skill_id) > 0:
		return "UI_PRESTIGE_REASON_RITE_DONE"
	if skill_level(skill_id) < rite_level():
		return "UI_PRESTIGE_REASON_RITE_LEVEL"
	return ""


## Anteprima di Stella (rite = false) o Rito (rite = true): cosa perdi, cosa conservi, cosa guadagni.
func preview_star(skill_id: String, rite: bool = false) -> Dictionary:
	var reason := can_rite(skill_id) if rite else can_star(skill_id)
	var n0 := stars(skill_id)
	var n1 := n0 + 1
	var dust_gain := _boost_dust(Formulas.stardust_for_star(n1))
	var before := star_mods(skill_id, n0)
	var after := star_mods(skill_id, n1)
	var mods: Array = _mod_diff(before, after)
	var lvl := skill_level(skill_id)
	var p := {
		"kind": "rite" if rite else "star", "skill": skill_id, "ok": reason.is_empty(), "reason": reason,
		"level_lost": lvl - 1, "stars_before": n0, "stars_after": n1, "dust_gain": dust_gain,
		"mods": mods, "hours_back": estimate_return_hours(skill_id, n1),
		"perks_lost": _perk_count(skill_id), "milestones": _milestones_reached(skill_id, n1),
		"xp_before": _family_totals(before, "skill_xp_pct", [skill_id]).y * 100.0 - 100.0,
		"xp_after": _family_totals(after, "skill_xp_pct", [skill_id]).y * 100.0 - 100.0,
		"haste_before": _family_totals(before, "skill_haste_pct", [skill_id]).x,
		"haste_after": _family_totals(after, "skill_haste_pct", [skill_id]).x,
	}
	var lose: Array = [{"key": "UI_PRESTIGE_LOSE_LEVEL", "params": {"level": lvl}}]
	if p.perks_lost > 0:
		lose.append({"key": "UI_PRESTIGE_LOSE_PERKS", "params": {"n": p.perks_lost}})
	var keep: Array = [{"key": "UI_PRESTIGE_KEEP_STAR", "params": {}}]
	if p.perks_lost > 0:
		keep.append({"key": "UI_PRESTIGE_KEEP_PERKS", "params": {}})
	var gain: Array = [{"key": "UI_PRESTIGE_GAIN_STAR", "params": {"n": n1}},
		{"key": "UI_PRESTIGE_GAIN_DUST", "params": {"n": dust_gain}}]
	p["lose"] = lose
	p["keep"] = keep
	p["gain"] = gain
	return p


## L'anteprima giusta da mostrare per una mansione: Stella se possibile, altrimenti Rito se possibile; se nessuno dei due,
## quello che manca di meno (Rito finché non è fatto e non ci sono Stelle, poi Stella).
func preview_best(skill_id: String) -> Dictionary:
	if can_star(skill_id).is_empty():
		return preview_star(skill_id, false)
	if can_rite(skill_id).is_empty():
		return preview_star(skill_id, true)
	return preview_star(skill_id, not rite_done(skill_id) and stars(skill_id) == 0)


func _mod_diff(before: Array, after: Array) -> Array:
	var b := {}
	for m in before:
		b[str(m.key) + "|" + str(m.mode)] = float(m.value)
	var out: Array = []
	for m in after:
		var k := str(m.key) + "|" + str(m.mode)
		var old: float = float(b.get(k, 0.0))
		if absf(float(m.value) - old) > 1e-9:
			out.append({"key": str(m.key), "mode": str(m.mode), "before": old, "after": float(m.value)})
	return out


func _perk_count(skill_id: String) -> int:
	var n := 0
	for tier in _skill_state(skill_id).get("perks", {}):
		n += str(_skill_state(skill_id).perks[tier]).length()
	return n


## Traguardi raggiunti proprio con la Stella n (descrizioni {it,en} o chiave di sblocco).
func _milestones_reached(skill_id: String, n: int) -> Array:
	var out: Array = []
	var row := _prow(skill_id)
	for m in row.get("milestones", []):
		if int(m.stars) == n:
			out.append(m)
	var he: Variant = row.get("hero_extra")
	if he is Dictionary:
		for m in he.get("milestones", []):
			if int(m.stars) == n:
				out.append(m)
	return out


## Esegue Stella o Rito. Ritorna l'anteprima applicata ({} se rifiutato).
func do_star(skill_id: String, rite: bool = false) -> Dictionary:
	var p := preview_star(skill_id, rite)
	if not bool(p.ok):
		return {}
	var sk := _skills()
	var perks: Dictionary = _skill_state(skill_id).get("perks", {}).duplicate(true)
	if not perks.is_empty():
		state.perk_memory[skill_id] = perks
	if int(sk.call("reset_for_star", skill_id)) <= 0:
		return {}
	if rite:
		state.rites[skill_id] = true
	_refresh_star_source(skill_id)
	_add_dust(int(p.dust_gain))
	var n1 := int(p.stars_after)
	var row := _prow(skill_id)
	for m in row.get("milestones", []):
		if int(m.stars) <= n1 and str(m.get("unlock", "")) != "":
			_grant(str(m.unlock))
	var he: Variant = row.get("hero_extra")
	if he is Dictionary:
		for m in he.get("milestones", []):
			if int(m.stars) <= n1:
				_grant(str(m.unlock))
	ctx.events.star_gained.emit(skill_id)
	ctx.events.important_event.emit("rite" if rite else "star")
	check_goals()
	return p


func has_perk_memory(skill_id: String) -> bool:
	return not (state.perk_memory.get(skill_id, {}) as Dictionary).is_empty()


## "Riapplica i talenti" con un clic: rifà le scelte ricordate per i livelli già raggiunti. Ritorna quante.
func reapply_perks(skill_id: String) -> int:
	var sk := _skills()
	var mem: Dictionary = state.perk_memory.get(skill_id, {})
	var n := 0
	for tier_s in mem:
		for letter in str(mem[tier_s]):
			if bool(sk.call("choose_perk", skill_id, int(tier_s), letter)):
				n += 1
	return n


## Ore stimate per tornare al livello richiesto (con l'Eco) dopo aver ottenuto la Stella `stars_after`.
## -1 se la mansione non ha azioni (Eroe, Taglie). Stima: azione migliore per livello, modificatori attuali con i
## bonus delle Stelle sostituiti da quelli futuri, maestria ignorata.
func estimate_return_hours(skill_id: String, stars_after: int) -> float:
	var acts: Array = []
	for a in ctx.data.actions_for_skill(skill_id):
		if a.has("xp") and a.has("time_s") and str(a.get("kind", "")) != "crop" and float(a.time_s) > 0.0:
			acts.append(a)
	if acts.is_empty():
		return -1.0
	var sc: Array = [skill_id, str(_skill_defs.get(skill_id, {}).get("group", "")), "all", "current"]
	var cur := star_mods(skill_id, stars(skill_id))
	var nxt := star_mods(skill_id, stars_after)
	var xp_c := _family_totals(cur, "skill_xp_pct", sc)
	var xp_n := _family_totals(nxt, "skill_xp_pct", sc)
	var hs_c := _family_totals(cur, "skill_haste_pct", sc)
	var hs_n := _family_totals(nxt, "skill_haste_pct", sc)
	var xp_add := ctx.modifiers.total_add("skill_xp_pct", sc) - xp_c.x + xp_n.x
	var xp_more := ctx.modifiers.total_more("skill_xp_pct", sc) / maxf(1e-9, xp_c.y) * xp_n.y
	var hs_add := ctx.modifiers.total_add("skill_haste_pct", sc) - hs_c.x + hs_n.x
	var hs_more := ctx.modifiers.total_more("skill_haste_pct", sc) / maxf(1e-9, hs_c.y) * hs_n.y
	var mult := (1.0 + xp_add / 100.0) * xp_more * (1.0 + hs_add / 100.0) * hs_more
	var target := star_requirement(skill_id)
	var rec := _record_level(skill_id)
	var hours := 0.0
	for lv in range(1, target):
		var best := 0.0
		for a in acts:
			if int(a.get("level_req", 1)) <= lv:
				best = maxf(best, float(a.xp) / float(a.time_s) * 3600.0)
		if best <= 0.0:
			return -1.0
		hours += float(Formulas.xp_to_next(lv)) / (best * mult * Formulas.echo_multiplier(lv, rec))
	return hours


# ------------------------------------------------------------------ COSTELLAZIONI

func nodes() -> Array:
	return ctx.data.table("constellations")


func node(node_id: String) -> Dictionary:
	return ctx.data.get_def("constellations", node_id)


func node_level(node_id: String) -> int:
	return int(state.constellations.get(node_id, 0))


func node_levels_total() -> int:
	var t := 0
	for k in state.constellations:
		t += int(state.constellations[k])
	return t


func is_dormant(node_id: String) -> bool:
	var key := str(node(node_id).get("modifier_per_level", {}).get("key", ""))
	return DORMANT_FAMILIES.has(key.split(":")[0])


## Costo per passare da `level` a `level+1`: ceil(base × crescita^livello).
## Tetto di livelli calcolati in un colpo solo (anteprima/acquisto/max_buyable): protegge i cicli da quantita' assurde.
const MAX_BATCH := 10000


func node_cost(node_id: String, level: int) -> int:
	var nd := node(node_id)
	return int(ceil(float(nd.cost_base) * pow(float(nd.cost_growth), float(level)) - 1e-9))


func node_max_level(node_id: String) -> int:
	var m: Variant = node(node_id).get("max_level")
	return -1 if m == null else int(m)


## Effetto totale di un nodo a un dato livello (in punti %, o unità): 'more' compone livello su livello.
func node_effect(node_id: String, level: int) -> float:
	var mp: Dictionary = node(node_id).get("modifier_per_level", {})
	if mp.is_empty() or level <= 0:
		return 0.0
	if str(mp.mode) == "more":
		return (pow(1.0 + float(mp.value) / 100.0, float(level)) - 1.0) * 100.0
	return float(mp.value) * float(level)


## "" se il livello successivo si può comprare, altrimenti la chiave del motivo.
func can_buy_node(node_id: String) -> String:
	var nd := node(node_id)
	if nd.is_empty():
		return "UI_PRESTIGE_REASON_NO_NODE"
	var req: Variant = nd.get("requires")
	if req is Array and node_level(str(req[0])) < int(req[1]):
		return "UI_PRESTIGE_REASON_NODE_REQ"
	var mx := node_max_level(node_id)
	var lv := node_level(node_id)
	if mx >= 0 and lv >= mx:
		return "UI_PRESTIGE_REASON_NODE_MAX"
	if dust() < node_cost(node_id, lv):
		return "UI_PRESTIGE_REASON_NO_DUST"
	return ""


## Quanti livelli di fila si possono comprare ora (limite di livello massimo e Polvere).
func max_buyable(node_id: String) -> int:
	var nd := node(node_id)
	if nd.is_empty():
		return 0
	var req: Variant = nd.get("requires")
	if req is Array and node_level(str(req[0])) < int(req[1]):
		return 0
	var lv := node_level(node_id)
	var mx := node_max_level(node_id)
	var left := dust()
	var n := 0
	while (mx < 0 or lv + n < mx) and n < MAX_BATCH:
		var c := node_cost(node_id, lv + n)
		if c > left:
			break
		left -= c
		n += 1
	return n


func preview_node(node_id: String, qty: int = 1) -> Dictionary:
	var lv := node_level(node_id)
	var mx := node_max_level(node_id)
	var q := mini(qty, MAX_BATCH)
	if mx >= 0:
		q = mini(q, mx - lv)
	q = maxi(q, 1)
	var cost := 0
	for i in q:
		cost += node_cost(node_id, lv + i)
	var reason := can_buy_node(node_id)
	if reason.is_empty() and dust() < cost:
		reason = "UI_PRESTIGE_REASON_NO_DUST"
	return {"kind": "node", "node": node_id, "ok": reason.is_empty(), "reason": reason, "level": lv, "level_after": lv + q,
		"qty": q, "cost": cost, "effect_before": node_effect(node_id, lv), "effect_after": node_effect(node_id, lv + q),
		"dormant": is_dormant(node_id), "max_level": mx, "max_buyable": max_buyable(node_id),
		"dust_after": dust() - cost}


func buy_node(node_id: String, qty: int = 1) -> Dictionary:
	var p := preview_node(node_id, qty)
	if not bool(p.ok) or not _spend_dust(int(p.cost)):
		return {}
	state.constellations[node_id] = int(p.level_after)
	state["stardust_spent"] = int(state.stardust_spent) + int(p.cost)
	_rebuild_constellation_modifiers()
	ctx.events.important_event.emit("constellation")
	check_goals()
	return p


## Rimborso totale: ogni `respec_free_interval_s` di tempo di gioco gratis (il primo subito), altrimenti costa Polvere.
func respec_cost() -> int:
	return 0 if respec_free_in() <= 0.0 else int(_k()["respec_cost_stardust"])


func respec_free_in() -> float:
	var last := float(state.respec_last_s)
	if last < 0.0:
		return 0.0
	return maxf(0.0, last + float(_k()["respec_free_interval_s"]) - float(state.clock_s))


func preview_respec() -> Dictionary:
	var refund := int(state.stardust_spent)
	var cost := respec_cost()
	var reason := ""
	if refund <= 0:
		reason = "UI_PRESTIGE_REASON_NOTHING_SPENT"
	elif cost > dust():
		reason = "UI_PRESTIGE_REASON_NO_DUST"
	return {"kind": "respec", "ok": reason.is_empty(), "reason": reason, "refund": refund, "cost": cost,
		"free_in_s": respec_free_in(), "net": refund - cost, "dust_after": dust() - cost + refund,
		"levels_lost": node_levels_total()}


func respec() -> Dictionary:
	var p := preview_respec()
	if not bool(p.ok) or not _spend_dust(int(p.cost)):
		return {}
	if int(p.cost) == 0:
		state["respec_last_s"] = float(state.clock_s)
	_add_dust(int(p.refund))
	state.constellations.clear()
	state["stardust_spent"] = 0
	_rebuild_constellation_modifiers()
	ctx.events.important_event.emit("respec")
	return p


func _rebuild_constellation_modifiers() -> void:
	var mods: Array = []
	for nid in state.constellations:
		var lv := int(state.constellations[nid])
		var mp: Dictionary = node(str(nid)).get("modifier_per_level", {})
		if lv <= 0 or mp.is_empty():
			continue
		if str(mp.mode) == "more":
			for i in lv:
				mods.append({"key": str(mp.key), "value": float(mp.value), "mode": "more"})
		else:
			mods.append({"key": str(mp.key), "value": float(mp.value) * float(lv), "mode": str(mp.mode)})
	ctx.modifiers.set_source(SRC_CONSTELLATION, mods)


# ------------------------------------------------------------------ RIFONDAZIONE (Tenuta)

func partners() -> int:
	return int(state.partners)


func _estate() -> GameSystem:
	return ctx.get_system("estate")


func lifetime_units() -> float:
	var e := _estate()
	if e != null and e.has_method("lifetime_units"):
		return float(e.call("lifetime_units"))
	return float(ctx.state.get("estate", {}).get("prosperity", 0.0))


func refound_min_units() -> float:
	return float(ctx.constants().get("estate", {}).get("prestige_min_units", 0.0))


## Soci che si otterrebbero ora: floor((totale a vita − già contati) × (1 + soci_gain_pct/100)).
func refound_gain() -> int:
	var total := Formulas.soci_total(lifetime_units())
	var fresh := maxi(0, total - int(state.partners_basis))
	return int(floor(float(fresh) * (1.0 + ctx.modifiers.total_add("soci_gain_pct", []) / 100.0) + 1e-9))


func can_refound() -> String:
	if lifetime_units() < refound_min_units():
		return "UI_PRESTIGE_REASON_ESTATE_UNITS"
	if refound_gain() < 1:
		return "UI_PRESTIGE_REASON_NO_PARTNERS"
	return ""


func partner_bonus_pct(n: int) -> float:
	return float(ctx.constants().get("estate", {}).get("socio_bonus_pct", 0.0)) * float(n)


func preview_refound() -> Dictionary:
	var reason := can_refound()
	var gain := refound_gain()
	var est: Dictionary = ctx.state.get("estate", {})
	return {"kind": "refound", "ok": reason.is_empty(), "reason": reason, "partners_gain": gain,
		"partners_before": partners(), "partners_after": partners() + gain,
		"bonus_before": partner_bonus_pct(partners()), "bonus_after": partner_bonus_pct(partners() + gain),
		"units": lifetime_units(), "min_units": refound_min_units(),
		"buildings_lost": (est.get("buildings", {}) as Dictionary).size(),
		"lose": [{"key": "UI_PRESTIGE_LOSE_ESTATE", "params": {}}],
		"keep": [{"key": "UI_PRESTIGE_KEEP_ESTATE", "params": {}}],
		"gain": [{"key": "UI_PRESTIGE_GAIN_PARTNERS", "params": {"n": gain}}]}


func do_refound() -> Dictionary:
	var p := preview_refound()
	if not bool(p.ok):
		return {}
	state["partners"] = int(p.partners_after)
	state["partners_basis"] = Formulas.soci_total(lifetime_units())
	state["refoundings"] = int(state.refoundings) + 1
	var e := _estate()
	if e != null and e.has_method("reset_for_refounding"):
		e.call("reset_for_refounding")
	else:
		var est: Dictionary = ctx.state.get("estate", {})
		est["buildings"] = {}
		est["settlers"] = 0
		est["pantry"] = 0.0
		est["storage"] = {}
	_rebuild_partner_modifiers()
	ctx.events.estate_changed.emit()
	ctx.events.objective_event.emit("estate_prestige", {"qty": 1})
	ctx.events.important_event.emit("refounding")
	check_goals()
	return p


func _rebuild_partner_modifiers() -> void:
	var n := partners()
	var mods: Array = []
	if n > 0:
		mods.append({"key": "estate_prod_pct", "value": partner_bonus_pct(n), "mode": "add"})
	ctx.modifiers.set_source(SRC_PARTNERS, mods)


func _rebuild_all_modifiers() -> void:
	for sk in _prestige_skills():
		_refresh_star_source(sk)
	_rebuild_constellation_modifiers()
	_rebuild_partner_modifiers()
	_rebuild_trial_modifiers()
	_refresh_trial_active_mods()


# ------------------------------------------------------------------ GRANDI OBIETTIVI

func goal_progress(goal: Dictionary) -> int:
	match str(goal.type):
		"rites_done": return state.rites.size()
		"stars_total": return stars_total()
		"constellation_levels": return node_levels_total()
		"partners": return partners()
	return 0


## [{id, type, qty, stardust, current, done}] nell'ordine dei dati.
func goals() -> Array:
	var out: Array = []
	for g in _k().get("goals", []):
		var cur := goal_progress(g)
		out.append({"id": str(g.id), "type": str(g.type), "qty": int(g.qty), "stardust": int(g.stardust),
			"current": cur, "done": bool(state.goals.get(str(g.id), false))})
	return out


## Il prossimo Grande Obiettivo non ancora riscosso (il più vicino), o {}.
func next_goal() -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := -1.0
	for g in goals():
		if bool(g.done):
			continue
		var r := minf(1.0, float(g.current) / float(maxi(1, int(g.qty))))
		if r > best_ratio:
			best_ratio = r
			best = g
	return best


## Riscuote da soli gli obiettivi raggiunti. Ritorna gli id riscossi.
func check_goals() -> PackedStringArray:
	var got := PackedStringArray()
	for g in goals():
		if bool(g.done) or int(g.current) < int(g.qty):
			continue
		state.goals[str(g.id)] = true
		_add_dust(int(g.stardust))
		got.append(str(g.id))
		ctx.events.important_event.emit("prestige_goal")
	return got


# ------------------------------------------------------------------ CONSIGLIERE (uno solo, un solo suggerimento)

## I tre campi sempre presenti: kind ("star"|"rite"|"refound"|"node"|"none"), layer, e i numeri dell'azione.
func advise() -> Dictionary:
	if not _has_unlock(TOKEN_FEATURE):
		return {"kind": "none", "layer": ""}
	var best_star := ""
	var best_gain := -1.0
	for sk in _prestige_skills():
		if can_star(sk).is_empty():
			var p := preview_star(sk)
			var g := float(p.xp_after) - float(p.xp_before) + float(p.haste_after) - float(p.haste_before)
			if g > best_gain:
				best_gain = g
				best_star = sk
	if not best_star.is_empty():
		var p2 := preview_star(best_star)
		return {"kind": "star", "layer": "star", "skill": best_star, "dust": p2.dust_gain, "stars_after": p2.stars_after,
			"xp_before": p2.xp_before, "xp_after": p2.xp_after, "hours_back": p2.hours_back}
	var best_rite := ""
	var best_lv := -1
	for sk2 in _prestige_skills():
		if can_rite(sk2).is_empty() and skill_level(sk2) > best_lv:
			best_lv = skill_level(sk2)
			best_rite = sk2
	if not best_rite.is_empty():
		var p3 := preview_star(best_rite, true)
		return {"kind": "rite", "layer": "star", "skill": best_rite, "dust": p3.dust_gain, "stars_after": p3.stars_after,
			"xp_before": p3.xp_before, "xp_after": p3.xp_after, "hours_back": p3.hours_back}
	if layer_visible("refound"):
		var gain := refound_gain()
		var ak: Dictionary = _k().get("advisor", {})
		if can_refound().is_empty() and gain >= int(ak["refound_min_new_partners"]) \
				and (partners() == 0 or float(gain) >= float(ak["refound_min_ratio"]) * float(partners())):
			return {"kind": "refound", "layer": "refound", "partners_gain": gain, "bonus_after": partner_bonus_pct(partners() + gain)}
	if layer_visible("constellations"):
		var pick := ""
		var pick_cost := 0
		for nd in nodes():
			if can_buy_node(str(nd.id)).is_empty():
				var c := node_cost(str(nd.id), node_level(str(nd.id)))
				if pick.is_empty() or c < pick_cost:
					pick = str(nd.id)
					pick_cost = c
		if not pick.is_empty():
			return {"kind": "node", "layer": "constellations", "node": pick, "cost": pick_cost, "dust": dust()}
	var out := {"kind": "none", "layer": ""}
	out.merge(next_step())
	return out


## Il passo più vicino: la mansione più avanti verso il Rito (se non fatto) o la Stella. {} se nessuna.
func next_step() -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := -1.0
	for sk in _prestige_skills():
		var rite_first := not rite_done(sk) and stars(sk) == 0 and not (_k().get("rite_excluded_skills", []) as Array).has(sk)
		var target := rite_level() if rite_first else star_requirement(sk)
		var ratio := float(skill_level(sk)) / float(maxi(1, target))
		if skill_level(sk) < target and ratio > best_ratio:
			best_ratio = ratio
			best = {"step_skill": sk, "step_level": skill_level(sk), "step_target": target, "step_kind": "rite" if rite_first else "star"}
	return best


# ------------------------------------------------------------------ strati visibili

## Gli strati compaiono solo quando servono (audit 03 #3): id "star", "constellations", "refound", "era", "trials".
func layer_visible(layer_id: String) -> bool:
	if not _has_unlock(TOKEN_FEATURE):
		return false
	match layer_id:
		"star": return true
		"constellations": return stars_total() > 0 or dust() > 0 or node_levels_total() > 0
		"refound": return _has_unlock("feature:estate") or partners() > 0
		"era": return int(state.era_max) > 1
		"trials": return trials_unlocked()
	return false


# ------------------------------------------------------------------ utilità di formula (dati, mai numeri nel codice)

## Valuta una formula dei dati ("5 * era") con le variabili date. 0.0 se la formula non è valida.
func _eval(expr: String, names: PackedStringArray, vals: Array) -> float:
	var ex := Expression.new()
	if ex.parse(expr, names) != OK:
		return 0.0
	var r: Variant = ex.execute(vals, null, false)
	if ex.has_execute_failed():
		return 0.0
	return float(r)


func _era_rules() -> Dictionary:
	return ctx.data.rules("era_rules")


# ------------------------------------------------------------------ ERE DEL MONDO (docs/13 §4)

func era_current() -> int:
	return int(state.era_current)


func era_max() -> int:
	return int(state.era_max)


## Nome dell'Era n nella lingua corrente («Era II — Il Malumore»); oltre le Ere con nome dedicato: «Era n».
func era_name(n: int) -> String:
	var names: Array = _era_rules().get("names", [])
	if n >= 1 and n <= names.size() and names[n - 1] is Dictionary:
		var s := Loc.t(names[n - 1])
		if s != "":
			return s
	return Loc.tf("UI_ERA_HEAD", {"era": n})


## Cambio diretto (nessuna anteprima, nessun evento): 1..era_max, e mai durante una Prova (che si combatte nell'Era I).
func set_era(n: int) -> bool:
	if n < 1 or n > int(state.era_max) or is_trial_active():
		return false
	state["era_current"] = n
	return true


func era_monster_mult(n: int) -> float:
	return Formulas.era_monster_mult(n)


func era_reward_mult(n: int) -> float:
	return Formulas.era_reward_mult(n)


## Bonus della Cassa dell'Era N (formula dei dati di crate_rules; la Cassa stessa la gestisce il sistema Casse).
func era_crate_mult(n: int) -> float:
	var tpl: Dictionary = ctx.data.rules("crate_rules").get("era_crate_template", {})
	return _eval(str(tpl.get("bonus_mult_formula", "1")), PackedStringArray(["era"]), [n])


## Id della Cassa dell'Era consegnata dal Custode battuto nell'Era `era` (modello `crate_rules.era_crate_template`):
## Era II minima (la caduta nell'Era I dà la Cassa della nuova Era II), oltre `max_era` la più alta generata. "" se assente.
func era_crate_id(era: int) -> String:
	var tpl: Dictionary = ctx.data.rules("crate_rules").get("era_crate_template", {})
	if tpl.is_empty():
		return ""
	var n := clampi(era, int(tpl.get("min_era", 2)), int(tpl.get("max_era", 2)))
	var t_id := str(tpl.get("id_pattern", "")).replace("{n}", str(n))
	return t_id if not ctx.data.item(t_id).is_empty() else ""


## Consegna etica della Cassa dell'Era (CrateSystem.grant_crate: finisce nel Deposito come ogni cassa trovata, si apre
## dalla schermata Casse con le probabilità visibili; niente acquisti, nessuna posta).
func _grant_era_crate(era: int) -> void:
	var cid := era_crate_id(era)
	var qty := int(ctx.data.rules("crate_rules").get("era_crate_template", {}).get("per_warden_kill", 1))
	var cr := ctx.get_system("crates")
	if cid.is_empty() or qty <= 0 or cr == null or not cr.has_method("grant_crate"):
		return
	cr.call("grant_crate", cid, qty)
	ctx.events.notice.emit("loot", Loc.tf("UI_ERA_CRATE_NOTICE", {"crate": Loc.t(ctx.data.item(cid).get("name", {})), "n": qty}), {"crate": cid})


## Essenza d'Era per drop nell'Era N (formula `qty_formula` dei dati).
func era_essence_qty(n: int) -> int:
	return int(floor(_eval(str(_era_rules().get("era_essence", {}).get("qty_formula", "1")), PackedStringArray(["era"]), [n]) + 1e-9))


## Ranghi degli oggetti che servono per "stare al passo" con l'Era N: ceil(log(mostri×)/log(×rango)).
func ranks_for_era(n: int) -> int:
	var rm := float(_era_rules().get("item_rank", {}).get("stat_mult_per_rank", 1.0))
	if n <= 1 or rm <= 1.0:
		return 0
	return int(ceil(log(era_monster_mult(n)) / log(rm) - 1e-9))


## Tetto dei ranghi con l'Era massima sbloccata (`cap_per_era` × era_max).
func rank_cap() -> int:
	return int(_era_rules().get("item_rank", {}).get("cap_per_era", 0)) * era_max()


# ------------------------------------------------------------------ RANGO DEGLI OGGETTI (G03, docs/07 §5, docs/13 §4)
# Il pozzo dell'Essenza d'Era: +4% per rango (era_rules.item_rank) SOLO su danno dell'arma, armatura, barriera, vita,
# precisione ed evasione dell'oggetto (CombatSystem._gear_blocks lo applica già). Costo per salire AL rango r:
# Formulas.rank_essence_cost(r) Essenza + Formulas.rank_gold_cost(tier, r) oro. Dall'Era II (eras.rank_min_era),
# massimo rank_cap() = 12 × Era massima. Niente nei dungeon (l'equipaggiamento lì non si tocca).

const ESSENCE := "era_essence"


func rank_min_era() -> int:
	return int(ctx.constants()["eras"]["rank_min_era"])


func ranks_unlocked() -> bool:
	return era_max() >= rank_min_era()


func rank_stat_mult(rank: int) -> float:
	return pow(float(_era_rules().get("item_rank", {}).get("stat_mult_per_rank", 1.0)), float(maxi(0, rank)))


## Vero se l'istanza è un pezzo d'equipaggiamento dell'Eroe (non attrezzi di mansione, finiture o reliquie).
func is_rankable(uid: String) -> bool:
	var b := _bank()
	var inst: Dictionary = b.call("get_instance", uid) if b != null else {}
	if inst.is_empty():
		return false
	var def: Dictionary = ctx.data.item(str(inst.get("def", "")))
	return def.has("equipment") and not def.has("tool")


## Equipaggiamento che può salire di Rango: prima quello indossato, poi il resto per tier (per i selettori della UI).
func rankable_uids() -> Array:
	var b := _bank()
	if b == null:
		return []
	var cb := ctx.get_system("combat")
	var worn: Array = []
	var rest: Array = []
	for inst in b.call("list_instances"):
		var uid := str(inst.get("uid", ""))
		if not is_rankable(uid):
			continue
		if cb != null and bool(cb.call("is_equipped", uid)):
			worn.append(uid)
		else:
			rest.append(uid)
	rest.sort_custom(func(x: String, y: String) -> bool:
		return int(ctx.data.item(str(b.call("get_instance", x).def)).get("tier", 0)) > int(ctx.data.item(str(b.call("get_instance", y).def)).get("tier", 0)))
	return worn + rest


func _rank_quality_mult(inst: Dictionary, def: Dictionary) -> float:
	if not bool(def.get("quality_applies", true)):
		return 1.0
	var q: Variant = inst.get("quality", "normal")
	if q is float or q is int:
		return float(q)
	for e in ctx.data.constants.get("quality", []):
		if e.id == q:
			return float(e.mult)
	return 1.0


## Anteprima ESATTA di un rango in più: costi, motivo del rifiuto e statistiche toccate (prima → dopo, qualità compresa).
func preview_rank_up(uid: String) -> Dictionary:
	var b := _bank()
	var inst: Dictionary = b.call("get_instance", uid) if b != null else {}
	var def: Dictionary = ctx.data.item(str(inst.get("def", ""))) if not inst.is_empty() else {}
	var rank := int(inst.get("rank", 0))
	var tier := maxi(1, int(def.get("tier", 1)))
	var essence := Formulas.rank_essence_cost(rank + 1)
	var gold := Formulas.rank_gold_cost(tier, rank + 1)
	var have_e := int(b.call("count", ESSENCE)) if b != null else 0
	var have_g := int(b.call("gold")) if b != null else 0
	var cb := ctx.get_system("combat")
	var reason := ""
	if inst.is_empty():
		reason = "UI_GAPM_RANK_REASON_NO_ITEM"
	elif not is_rankable(uid):
		reason = "UI_GAPM_RANK_REASON_NOT_GEAR"
	elif not ranks_unlocked():
		reason = "UI_GAPM_RANK_REASON_LOCKED"
	elif rank >= rank_cap():
		reason = "UI_GAPM_RANK_REASON_CAP"
	elif cb != null and bool(cb.call("in_combat_blocking")):
		reason = "UI_GAPM_RANK_REASON_DUNGEON"
	elif have_e < essence:
		reason = "UI_GAPM_RANK_REASON_ESSENCE"
	elif have_g < gold:
		reason = "UI_GAPM_RANK_REASON_GOLD"
	var stats: Array = []
	if not def.is_empty() and def.has("equipment"):
		var eq: Dictionary = def.equipment
		var qm := _rank_quality_mult(inst, def)
		var m0 := rank_stat_mult(rank)
		var m1 := rank_stat_mult(rank + 1)
		for key in _era_rules().get("item_rank", {}).get("applies_to_stats", []):
			var base := 0.0
			if str(key) == "damage" and eq.has("damage"):
				base = float(eq.damage) * qm
			elif (eq.get("stats", {}) as Dictionary).has(key):
				base = float(eq.stats[key]) * qm
			if base > 0.0:
				stats.append({"key": str(key), "before": base * m0, "after": base * m1})
	return {"kind": "rank", "ok": reason.is_empty(), "reason": reason, "uid": uid, "def": str(inst.get("def", "")),
		"rank": rank, "rank_after": rank + 1, "cap": rank_cap(), "min_era": rank_min_era(), "essence": essence, "gold": gold,
		"essence_have": have_e, "gold_have": have_g, "mult_before": rank_stat_mult(rank), "mult_after": rank_stat_mult(rank + 1),
		"stats": stats}


## Sale di un rango (spende Essenza e oro). Ritorna l'anteprima applicata, {} se rifiutato.
func do_rank_up(uid: String) -> Dictionary:
	var p := preview_rank_up(uid)
	var b := _bank()
	if not bool(p.ok) or b == null:
		return {}
	if not bool(b.call("remove", ESSENCE, int(p.essence))):
		return {}
	if not bool(b.call("spend_gold", int(p.gold))):
		b.call("add", ESSENCE, int(p.essence), "refund")
		return {}
	b.call("set_instance_rank", uid, int(p.rank_after))
	var cb := ctx.get_system("combat")
	if cb != null and cb.has_method("on_build_changed"):
		cb.call("on_build_changed")          # statistiche ricalcolate subito (non al controllo di ogni secondo)
	ctx.events.objective_event.emit("item_rank", {"rank": int(p.rank_after), "qty": 1})
	ctx.events.important_event.emit("item_rank")
	return p


## Polvere BASE del Custode dell'Era N (senza `stardust_gain_pct`): formula `stardust_per_warden_kill`.
func warden_dust_base(era: int) -> int:
	return int(floor(_eval(str(_era_rules().get("stardust_per_warden_kill", "0")), PackedStringArray(["era"]), [era]) + 1e-9))


func warden_kills(era: int) -> int:
	return int(state.era_kills.get(str(era), 0))


## Polvere che darebbe ORA un Custode dell'Era N (prima uccisione = piena; poi `stardust_repeat_pct` %, di default 0).
func warden_dust_now(era: int) -> int:
	var base := warden_dust_base(era)
	if warden_kills(era) > 0:
		base = int(floor(float(base) * float(_era_rules().get("stardust_repeat_pct", 0)) / 100.0 + 1e-9))
	return _boost_dust(base)


## Scheda del Custode di un'Era per la UI e per il combattimento.
func warden_info(era: int) -> Dictionary:
	return {"era": era, "kills": warden_kills(era), "first_done": warden_kills(era) > 0,
		"dust_now": warden_dust_now(era), "unlocks_next": era == era_max(),
		"can_fight": era >= 1 and era <= era_max() and not is_trial_active()}


## Anteprima del cambio di Era (nessun reset: i progressi restano). `lose` = il prezzo (mostri più duri), `gain` = ricompense.
func preview_era(n: int) -> Dictionary:
	var cur := era_current()
	var reason := ""
	if is_trial_active():
		reason = "UI_ERA_REASON_TRIAL"
	elif n < 1:
		reason = "UI_ERA_REASON_INVALID"
	elif n > era_max():
		reason = "UI_ERA_REASON_LOCKED"
	elif n == cur:
		reason = "UI_ERA_REASON_SAME"
	var mm := era_monster_mult(maxi(1, n))
	var mm0 := era_monster_mult(cur)
	var rm := era_reward_mult(maxi(1, n))
	var rm0 := era_reward_mult(cur)
	var lose: Array = []
	var gain: Array = []
	if n > cur:
		var d_ranks := ranks_for_era(n) - ranks_for_era(cur)
		lose.append({"key": "UI_ERA_LOSE_HARDER" if d_ranks > 0 else "UI_FIXC_ERA_LOSE_HARDER_NORANK", "params": {"from": mm0, "to": mm,
			"ranks": d_ranks}})
		gain.append({"key": "UI_ERA_GAIN_REWARDS", "params": {"from": rm0, "to": rm}})
		gain.append({"key": "UI_ERA_GAIN_ESSENCE", "params": {"qty": era_essence_qty(n)}})
	elif n < cur and n >= 1:
		lose.append({"key": "UI_ERA_LOSE_REWARDS", "params": {"from": rm0, "to": rm}})
		gain.append({"key": "UI_ERA_GAIN_EASIER", "params": {"from": mm0, "to": mm}})
	return {"kind": "era", "ok": reason.is_empty(), "reason": reason, "era": n, "current": cur, "max": era_max(),
		"monster_mult": mm, "monster_mult_before": mm0, "reward_mult": rm, "reward_mult_before": rm0,
		"essence_qty": era_essence_qty(maxi(1, n)), "crate_mult": era_crate_mult(maxi(1, n)),
		"ranks_needed": ranks_for_era(maxi(1, n)), "rank_cap": rank_cap(),
		"warden_dust": warden_dust_now(maxi(1, n)), "warden_kills": warden_kills(maxi(1, n)),
		"lose": lose, "keep": [{"key": "UI_ERA_KEEP_ALL", "params": {}}], "gain": gain}


## Cambia Era (selettore). Ritorna l'anteprima applicata, o {} se rifiutato.
func do_select_era(n: int) -> Dictionary:
	var p := preview_era(n)
	if not bool(p.ok) or not set_era(n):
		return {}
	ctx.events.important_event.emit("era_select")
	return p


## IL COMBATTIMENTO LA CHIAMA quando cade il Custode del Caveau nell'Era `era` (vedi docs/audit_2026-10-22/43).
## - Ignorata (ritorna 0) se l'Era non è sbloccata (`era` > era_max), `era` < 1 o c'è una Prova in corso.
## - Paga la Polvere del Custode ("5 × era") alla PRIMA uccisione di quell'Era; le successive `stardust_repeat_pct` % (0): vedi regola 9.
## - Se `era == era_max` sblocca l'Era successiva (una sola volta) ed emette `objective_event("era")` per le imprese.
## Ritorna la Polvere accreditata.
func on_warden_defeated(era: int) -> int:
	if era < 1 or era > int(state.era_max) or is_trial_active():
		return 0
	var d := warden_dust_now(era)          # prima del conteggio: decide prima volta / ripetizione
	var first := warden_kills(era) == 0
	state.era_kills[str(era)] = warden_kills(era) + 1
	_add_dust(d)
	_grant_era_crate(era)
	if era == int(state.era_max):
		state["era_max"] = era + 1
		ctx.events.objective_event.emit("era", {"era": era + 1, "qty": 1})
		ctx.events.notice.emit("success", Loc.tf("UI_ERA_UNLOCKED_N", {"name": era_name(era + 1), "dust": d}), {"era": era + 1})
		ctx.events.important_event.emit("era")
	elif first:
		ctx.events.important_event.emit("warden")
	check_goals()
	return d


# ------------------------------------------------------------------ PROVE DEL CUSTODE (docs/13 §6)

func trial_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t in ctx.data.table("trials"):
		out.append(str(t.id))
	return out


func trial_def(trial_id: String) -> Dictionary:
	return ctx.data.get_def("trials", trial_id)


func trial_tier_count(trial_id: String) -> int:
	return (trial_def(trial_id).get("tiers", []) as Array).size()


## Gradi superati (0..N) di una Prova.
func trial_tiers_done(trial_id: String) -> int:
	return int(state.trials.get(trial_id, 0))


func trials_unlocked() -> bool:
	if _has_unlock(TOKEN_TRIALS):
		return true
	var done: Array = ctx.state.get("quests", {}).get("done", [])
	for t in ctx.data.table("trials"):
		var q := str((t.get("unlock", {}) as Dictionary).get("quest", ""))
		if not q.is_empty() and done.has(q):
			return true
	return false


func is_trial_active() -> bool:
	# `state` è null in un sistema non agganciato a una partita (es. rimasto collegato a EventBus dopo un test)
	return state is Dictionary and not ((state as Dictionary).get("trial_active", {}) as Dictionary).is_empty()


## Copia della Prova in corso: {id, tier, started_s, era_restore} o {}.
func trial_active() -> Dictionary:
	return (state.trial_active as Dictionary).duplicate(true)


func _zone_of_index(idx: int) -> Dictionary:
	for z in ctx.data.table("zones"):
		if int(z.get("order", 0)) == idx:
			return z
	return {}


## Bersaglio di un grado: {kind: "boss"|"dungeon", id, zone}. Boss di zona, o il dungeon della zona se la Prova è `dungeon`.
func trial_target(trial_id: String, tier: int) -> Dictionary:
	var tiers: Array = trial_def(trial_id).get("tiers", [])
	if tier < 1 or tier > tiers.size():
		return {}
	var z := _zone_of_index(int(tiers[tier - 1].zone_index))
	if z.is_empty():
		return {}
	if bool(trial_def(trial_id).get("rules", {}).get("dungeon", false)):
		for d in ctx.data.table("dungeons"):
			if str(d.get("zone", "")) == str(z.id):
				return {"kind": "dungeon", "id": str(d.id), "zone": str(z.id)}
		return {}
	for mid in z.get("monsters", []):
		if str(ctx.data.get_def("monsters", str(mid)).get("type", "")) == "boss":
			return {"kind": "boss", "id": str(mid), "zone": str(z.id)}
	return {}


## Regole risolte di un grado (es. "tier_zona - 3" -> numero). Da dare al combattimento.
func trial_rules(trial_id: String, tier: int) -> Dictionary:
	var rules: Dictionary = (trial_def(trial_id).get("rules", {}) as Dictionary).duplicate(true)
	var tiers: Array = trial_def(trial_id).get("tiers", [])
	if tier >= 1 and tier <= tiers.size():
		rules.merge((tiers[tier - 1].get("rules", {}) as Dictionary).duplicate(true), true)      # regole del singolo grado
	var tgt := trial_target(trial_id, tier)
	if rules.has("max_gear_tier"):
		var z: Dictionary = ctx.data.get_def("zones", str(tgt.get("zone", "")))
		rules["max_gear_tier"] = maxi(1, int(_eval(str(rules.max_gear_tier).replace("tier_zona", "tier_z"),
			PackedStringArray(["tier_z"]), [int(z.get("tier", 1))])))
	return rules


## Regole della Prova IN CORSO (o {}): è il contratto con CombatSystem (`no_abilities`, `forced_disadvantage`, `monster_hp_mult`...).
func trial_rules_active() -> Dictionary:
	if not is_trial_active():
		return {}
	return trial_rules(str(state.trial_active.id), int(state.trial_active.tier))


## Motivo (chiave UI) per cui il grado non si può iniziare, "" se si può. `params` riceve i parametri del testo.
func can_start_trial(trial_id: String, tier: int, params: Dictionary = {}) -> String:
	var def := trial_def(trial_id)
	if def.is_empty() or tier < 1 or tier > trial_tier_count(trial_id):
		return "UI_TRIALS_REASON_INVALID"
	if not trials_unlocked():
		return "UI_TRIALS_REASON_LOCKED"
	if is_trial_active():
		return "UI_TRIALS_REASON_ACTIVE"
	var done := trial_tiers_done(trial_id)
	if tier <= done:
		return "UI_TRIALS_REASON_DONE"
	if tier > done + 1:
		return "UI_TRIALS_REASON_ORDER"
	var tgt := trial_target(trial_id, tier)
	if tgt.is_empty():
		return "UI_TRIALS_REASON_INVALID"
	var combat := ctx.get_system("combat")
	if combat != null and combat.has_method("zone_unlocked") and not bool(combat.call("zone_unlocked", str(tgt.zone))):
		return "UI_TRIALS_REASON_ZONE"
	var gear := _gear_violation(trial_rules(trial_id, tier))
	if not gear.is_empty():
		params["tier"] = int(trial_rules(trial_id, tier).get("max_gear_tier", 0))
		return gear
	return ""


## Righe `{key, params}` che descrivono le restrizioni (chiavi UI_TRIALS_RULE_<REGOLA>).
func trial_rule_lines(rules: Dictionary) -> Array:
	var out: Array = []
	for k in rules:
		var v: Variant = rules[k]
		if typeof(v) == TYPE_BOOL and not bool(v):
			continue
		var n := 0
		match str(k):
			"time_limit_s": n = int(v)
			"max_food": n = int(v)
			"max_gear_tier": n = int(v)
			"hp_mult": n = int(round((1.0 - float(v)) * 100.0))
			"monster_hp_mult": n = int(round((float(v) - 1.0) * 100.0))
		out.append({"key": "UI_TRIALS_RULE_" + str(k).to_upper(), "params": {"n": n}})
	return out


## Anteprima obbligatoria prima di iniziare: restrizioni, cosa si perde (niente), cosa si conserva, cosa si guadagna.
func preview_trial(trial_id: String, tier: int) -> Dictionary:
	var rp: Dictionary = {}
	var reason := can_start_trial(trial_id, tier, rp)
	var def := trial_def(trial_id)
	var tiers: Array = def.get("tiers", [])
	var td: Dictionary = tiers[tier - 1] if tier >= 1 and tier <= tiers.size() else {}
	var rules := trial_rules(trial_id, tier) if not td.is_empty() else {}
	var tgt := trial_target(trial_id, tier)
	var reward: Dictionary = td.get("reward", {})
	var dust_final := _boost_dust(int(reward.get("stardust", 0)))
	var gain: Array = []
	for m in reward.get("modifiers", []):
		gain.append({"key": "UI_TRIALS_GAIN_BONUS", "params": {"desc": _mod_label(str(m.key)), "n": float(m.value)}})
	if dust_final > 0:
		gain.append({"key": "UI_PRESTIGE_GAIN_DUST", "params": {"n": dust_final}})
	var lose: Array = []
	if era_current() > 1:
		lose.append({"key": "UI_TRIALS_LOSE_ERA", "params": {"era": era_current()}})
	return {"kind": "trial", "ok": reason.is_empty(), "reason": reason, "reason_params": rp, "id": trial_id, "tier": tier,
		"tier_roman": str(td.get("tier", "")), "zone": str(tgt.get("zone", "")), "target": tgt, "rules": trial_rule_lines(rules),
		"rules_raw": rules, "reward_modifiers": reward.get("modifiers", []), "reward_dust": dust_final,
		"lose": lose, "keep": [{"key": "UI_TRIALS_KEEP_ALL", "params": {}}], "gain": gain,
		"era_restore": era_current()}


## Testo breve di un modificatore dal catalogo ("+% danno inflitto" -> "danno inflitto").
func _mod_label(key: String) -> String:
	var fam := key.split(":")[0]
	for e in ctx.data.table("modifier_catalog"):
		if str(e.get("family", "")) == fam:
			var t := Loc.t(e.get("desc", {}))
			if t.begins_with("+% "):
				t = t.substr(3)
			var cut := t.find(" (")
			return t if cut < 0 else t.substr(0, cut)
	return fam


## Inizia il grado (la UI poi avvia il combattimento). Ritorna l'anteprima, {} se rifiutato. Si gioca nell'Era I;
## l'Era scelta torna da sola a fine Prova (riuscita, fallita o abbandonata).
func start_trial(trial_id: String, tier: int) -> Dictionary:
	var p := preview_trial(trial_id, tier)
	if not bool(p.ok):
		return {}
	var forced := int(_k().get("trials", {}).get("era", 1))
	# G39: `started_s` resta "adesso" finché il bersaglio non compare (engaged = false): il cronometro di «Contro il Tempo»
	# parte dal boss in campo, non dal clic su Inizia (CombatSystem.trial_status legge started_s e non cambia).
	state["trial_active"] = {"id": trial_id, "tier": tier, "started_s": float(state.clock_s), "era_restore": era_current(),
		"engaged": false}
	state["era_current"] = clampi(forced, 1, era_max())
	_refresh_trial_active_mods()
	ctx.events.important_event.emit("trial_start")
	return p


## Fine senza premio (morte, tempo, regola violata, abbandono): niente si perde, l'Era torna com'era. Ritorna true se c'era una Prova.
func trial_fail(reason_key: String = "UI_TRIALS_FAIL_ABANDON") -> bool:
	if not is_trial_active():
		return false
	var t_id := str(state.trial_active.id)
	_end_trial()
	ctx.events.notice.emit("warning", Loc.tf("UI_TRIALS_FAIL_NOTICE", {"name": Loc.t(trial_def(t_id).get("name", {})), "why": tr(reason_key)}), {"trial": t_id})
	ctx.events.important_event.emit("trial_fail")
	return true


func abandon_trial() -> bool:
	return trial_fail("UI_TRIALS_FAIL_ABANDON")


## Chiamata dal combattimento (o dagli eventi che il sistema ascolta già) alla vittoria sul bersaglio.
## `info` opzionale: {"elapsed_s": float, "ate_food": bool, "used_abilities": bool, "retreated": bool} per le regole che il
## combattimento conosce meglio. Ritorna {"ok": true, id, tier, dust, finished_all} oppure {"ok": false, "reason": chiave}.
func on_trial_won(info: Dictionary = {}) -> Dictionary:
	if not is_trial_active():
		return {"ok": false, "reason": "UI_TRIALS_REASON_NONE"}
	var t_id := str(state.trial_active.id)
	var tier := int(state.trial_active.tier)
	var rules := trial_rules(t_id, tier)
	var why := ""
	var elapsed := float(info.get("elapsed_s", float(state.clock_s) - float(state.trial_active.started_s)))
	if rules.has("time_limit_s") and elapsed > float(rules.time_limit_s):
		why = "UI_TRIALS_FAIL_TIME"
	elif bool(rules.get("no_food", false)) and bool(info.get("ate_food", false)):
		why = "UI_TRIALS_FAIL_FOOD"
	elif bool(rules.get("no_abilities", false)) and bool(info.get("used_abilities", false)):
		why = "UI_TRIALS_FAIL_ABILITIES"
	elif bool(rules.get("dungeon", false)) and bool(info.get("retreated", false)):
		why = "UI_TRIALS_FAIL_RETREAT"
	else:
		why = _gear_violation(rules)
		if not why.is_empty():
			why = why.replace("REASON", "FAIL")
	if not why.is_empty():
		trial_fail(why)
		return {"ok": false, "reason": why}
	var td: Dictionary = (trial_def(t_id).tiers as Array)[tier - 1]
	var reward: Dictionary = td.get("reward", {})
	var dust_gain := _boost_dust(int(reward.get("stardust", 0)))
	state.trials[t_id] = maxi(trial_tiers_done(t_id), tier)
	_add_dust(dust_gain)
	_end_trial()
	_rebuild_trial_modifiers()
	var all_max := true
	for tid in trial_ids():
		if trial_tiers_done(tid) < trial_tier_count(tid):
			all_max = false
			break
	ctx.events.objective_event.emit("challenge", {"qty": 1})
	if all_max:
		ctx.events.objective_event.emit("challenge_all_max", {"qty": 1})
	ctx.events.notice.emit("success", Loc.tf("UI_TRIALS_WON_NOTICE", {"name": Loc.t(trial_def(t_id).get("name", {})), "tier": str(td.get("tier", "")), "dust": dust_gain}), {"trial": t_id})
	ctx.events.important_event.emit("trial")
	check_goals()
	return {"ok": true, "id": t_id, "tier": tier, "dust": dust_gain, "finished_all": all_max}


## Chiude la Prova in corso ripristinando l'Era e togliendo i modificatori temporanei.
func _end_trial() -> void:
	var restore := int(state.trial_active.get("era_restore", 1))
	state["trial_active"] = {}
	state["era_current"] = clampi(restore, 1, era_max())
	_refresh_trial_active_mods()


## Modificatori permanenti dei gradi superati: fonte `trial:<id>` (add: somma di `value` per grado).
func _rebuild_trial_modifiers() -> void:
	for t in ctx.data.table("trials"):
		var sums: Dictionary = {}
		var done := trial_tiers_done(str(t.id))
		var tiers: Array = t.get("tiers", [])
		for i in mini(done, tiers.size()):
			for m in tiers[i].get("reward", {}).get("modifiers", []):
				var key := "%s|%s" % [m.key, m.get("mode", "add")]
				sums[key] = float(sums.get(key, 0.0)) + float(m.value)
		var mods: Array = []
		for key in sums:
			var parts := str(key).split("|")
			mods.append({"key": parts[0], "value": sums[key], "mode": parts[1]})
		ctx.modifiers.set_source(SRC_TRIAL + str(t.id), mods)


## Modificatori TEMPORANEI della Prova in corso. Solo `hp_mult` si può applicare da qui (combat_hp_pct, letto dal combattimento).
func _refresh_trial_active_mods() -> void:
	var mods: Array = []
	if is_trial_active():
		var r := trial_rules_active()
		if r.has("hp_mult"):
			mods.append({"key": "combat_hp_pct", "value": (float(r.hp_mult) - 1.0) * 100.0, "mode": "add"})
	ctx.modifiers.set_source(SRC_TRIAL_ACTIVE, mods)


## Nel caricamento: toglie ciò che non esiste più nei dati e chiude una Prova incoerente restituendo l'Era (reset sicuro).
func _sanitize_eras_and_trials() -> void:
	for k in state.era_kills.keys():
		if int(str(k)) < 1 or int(state.era_kills[k]) < 0:
			state.era_kills.erase(k)
	for tid in state.trials.keys():
		if trial_def(str(tid)).is_empty():
			state.trials.erase(tid)
		else:
			state.trials[tid] = clampi(int(state.trials[tid]), 0, trial_tier_count(str(tid)))
	var ta: Dictionary = state.trial_active
	if ta.is_empty():
		return
	var ok := ta.has("id") and ta.has("tier") and not trial_def(str(ta.id)).is_empty() \
		and int(ta.tier) >= 1 and int(ta.tier) <= trial_tier_count(str(ta.id)) and int(ta.tier) == trial_tiers_done(str(ta.id)) + 1
	if not ok:
		var restore := int(ta.get("era_restore", state.era_current))
		state["trial_active"] = {}
		state["era_current"] = clampi(restore, 1, int(state.era_max))
	else:
		ta["started_s"] = minf(float(ta.get("started_s", 0.0)), float(state.clock_s))
		ta["era_restore"] = clampi(int(ta.get("era_restore", 1)), 1, int(state.era_max))


## Violazione di equipaggiamento ("" = a posto): chiave UI_TRIALS_REASON_GEAR_* (diventa UI_TRIALS_FAIL_GEAR_* a Prova in corso).
func _gear_violation(rules: Dictionary) -> String:
	var armor_slots: Array = _k().get("trials", {}).get("armor_slots", [])
	for slot in ctx.state.get("equipment", {}):
		if str(slot) == "ammo":
			continue
		var def_id := _equipped_def(str(slot))
		if def_id.is_empty():
			continue
		if bool(rules.get("no_armor", false)) and armor_slots.has(str(slot)):
			return "UI_TRIALS_REASON_GEAR_ARMOR"
		if rules.has("max_gear_tier") and int(ctx.data.item(def_id).get("tier", 1)) > int(rules.max_gear_tier):
			return "UI_TRIALS_REASON_GEAR_TIER"
	return ""


## Divieto di indossare `def_id` DURANTE la Prova in corso (QA82 R2: prima la regola si controllava solo alla vittoria, quindi
## si poteva combattere con l'armatura e toglierla prima del colpo finale). "" = permesso o nessuna Prova; altrimenti la chiave UI.
func trial_equip_block(def_id: String) -> String:
	if not is_trial_active():
		return ""
	var rules := trial_rules_active()
	var d: Dictionary = ctx.data.item(def_id)
	var slot := str((d.get("equipment", {}) as Dictionary).get("slot", ""))
	if bool(rules.get("no_armor", false)) and (_k().get("trials", {}).get("armor_slots", []) as Array).has(slot):
		return "UI_TRIALS_REASON_GEAR_ARMOR"
	if rules.has("max_gear_tier") and int(d.get("tier", 1)) > int(rules.max_gear_tier):
		return "UI_TRIALS_REASON_GEAR_TIER"
	return ""


func _equipped_def(slot: String) -> String:
	var v: Variant = ctx.state.get("equipment", {}).get(slot, "")
	if v is Dictionary:
		return str((v as Dictionary).get("def", ""))
	var uid := str(v)
	if uid.is_empty():
		return ""
	var b := _bank()
	if b != null and b.has_method("get_instance"):
		var inst: Variant = b.call("get_instance", uid)
		if inst is Dictionary:
			return str((inst as Dictionary).get("def", ""))
	return ""


## G39: finché il bersaglio della Prova non è in campo il cronometro resta fermo (started_s segue l'orologio). I salvataggi
## con una Prova avviata prima di G39 non hanno `engaged`: valgono come già ingaggiati (comportamento di allora).
func _track_trial_engage() -> void:
	if not is_trial_active() or trial_engaged():
		return
	state.trial_active["started_s"] = float(state.clock_s)
	if _trial_target_on_field():
		state.trial_active["engaged"] = true


func trial_engaged() -> bool:
	return is_trial_active() and bool(state.trial_active.get("engaged", true))


## Il bersaglio è in campo: il boss di zona è il nemico corrente, o si sta combattendo nel dungeon della Prova.
func _trial_target_on_field() -> bool:
	var act: Variant = ctx.state.get("activity", {})
	if not (act is Dictionary) or str(act.get("type", "")) != "combat":
		return false
	var tgt := trial_target(str(state.trial_active.id), int(state.trial_active.tier))
	if str(tgt.get("kind", "")) == "dungeon":
		return str(act.get("dungeon", "")) == str(tgt.get("id", ""))
	var en: Variant = act.get("enemy", {})
	return en is Dictionary and str(en.get("id", "")) == str(tgt.get("id", ""))


## Scaduto il tempo della Prova (a ogni tick e dopo l'offline).
func _check_trial_clock() -> void:
	if not is_trial_active():
		return
	var r := trial_rules_active()
	if r.has("time_limit_s") and float(state.clock_s) - float(state.trial_active.started_s) > float(r.time_limit_s):
		trial_fail("UI_TRIALS_FAIL_TIME")


# Eventi del gioco che decidono la Prova in corso (metodi, non lambda).
func _cb_monster_killed(monster_id: String, _drops: Array) -> void:
	if not is_trial_active():
		return
	var tgt := trial_target(str(state.trial_active.id), int(state.trial_active.tier))
	if str(tgt.get("kind", "")) == "boss" and str(tgt.id) == monster_id:
		on_trial_won({})


## Offline (uccisioni in blocco): il bersaglio di una Prova SENZA tempo battuto mentre si è via vale la vittoria.
func _cb_monsters_killed_batch(monster_id: String, count: int, _drops: Array) -> void:
	if count <= 0 or not is_trial_active() or trial_rules_active().has("time_limit_s"):
		return
	# QA82 O1: l'offline non conosce le meccaniche del boss e faceva passare anche Prove che dal vivo uccidono l'Eroe in pochi
	# secondi (Vetro V). La vittoria in assenza vale solo se lo scontro simulato con le regole della Prova e' vinto.
	var cb := ctx.get_system("combat")
	var tgt := trial_target(str(state.trial_active.id), int(state.trial_active.tier))
	if cb != null and cb.has_method("trial_boss_safe") and str(tgt.get("kind", "")) == "boss" and str(tgt.get("id", "")) == monster_id \
			and not bool(cb.call("trial_boss_safe", monster_id)):
		ctx.events.notice.emit("warning", tr("UI_TRIALS_OFFLINE_UNSAFE"), {"trial": str(state.trial_active.id)})
		return
	_cb_monster_killed(monster_id, [])


func _cb_player_died(_cause: String) -> void:
	if is_trial_active():
		trial_fail("UI_TRIALS_FAIL_DEATH")


func _cb_item_removed(def_id: String, qty: int) -> void:
	if not is_trial_active() or str(ctx.data.item(def_id).get("category", "")) != "food":
		return
	var r := trial_rules_active()
	if bool(r.get("no_food", false)):
		trial_fail("UI_TRIALS_FAIL_FOOD")
	elif r.has("max_food"):                       # porzioni concesse ai gradi alti del Digiuno
		state.trial_active["food_eaten"] = int(state.trial_active.get("food_eaten", 0)) + maxi(1, qty)
		if int(state.trial_active.food_eaten) > int(r.max_food):
			trial_fail("UI_TRIALS_FAIL_FOOD")


func _cb_objective_event(kind: String, params: Dictionary) -> void:
	if kind != "complete_dungeon" or not is_trial_active():
		return
	var tgt := trial_target(str(state.trial_active.id), int(state.trial_active.tier))
	if str(tgt.get("kind", "")) == "dungeon" and str(tgt.id) == str(params.get("dungeon", "")):
		on_trial_won({})


## Riepilogo per la UI: una riga per Prova.
func trials_overview() -> Array:
	var out: Array = []
	for t in ctx.data.table("trials"):
		var t_id := str(t.id)
		var done := trial_tiers_done(t_id)
		var cnt := trial_tier_count(t_id)
		var status := "complete" if done >= cnt else "ready"
		if is_trial_active() and str(state.trial_active.id) == t_id:
			status = "active"
		out.append({"id": t_id, "done": done, "count": cnt, "next": mini(done + 1, cnt), "status": status})
	return out
