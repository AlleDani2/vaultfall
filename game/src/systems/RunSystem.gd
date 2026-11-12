class_name RunSystem
extends GameSystem
## La Corsa a scelte del combattimento in zona (CORSA, docs/audit_2026-10-22/91_PROGETTO_CORSA.md, docs/05 §14).
##
## Ogni `kills_per_choice` uccisioni nella zona della Corsa arriva una Scelta di `offers` voci (data/run_perks.json, flusso RNG
## `world`); dopo `max_choices` scelte la comparsa successiva è il Campione della Corsa, che chiude il ciclo. Le voci prese
## passano da Modifiers con la fonte unica `run:perks` (regola add/more), attiva SOLO mentre si combatte nella zona della Corsa.
## Offline la Corsa è in pausa: CombatSystem.simulate_offline chiama suspend() prima di misurare e il contatore non avanza.
##
## Stato posseduto: sezione `run` (additiva: i salvataggi precedenti la ricevono da default_state, SCHEMA_VERSION invariato).
##   zone, kills, picks[], offer[], offer_s, rerolls, banishes, banned[], champion ("" | "due" | "fighting" | "wait"),
##   champ_attempts, champ_kills, mode ("ask" | "auto"), order[famiglie], history[], runs_done, champions
## Nessun numero di bilanciamento qui: tutto da data/run_rules.json.

var _active: bool = false          # la fonte dei modificatori è applicata
var _token_done: bool = false      # token di sblocco già concesso (scheda tutorial una volta sola)
var _perk_index: Dictionary = {}
var last_event: Dictionary = {}     # ultimo evento per la UI (non salvato): {"k": "offer"|"pick"|"champion"|"end", ...}
var event_seq: int = 0


func _init() -> void:
	id = "run"
	state_key = "run"


func setup() -> void:
	_perk_index.clear()
	for p in ctx.data.table("run_perks"):
		_perk_index[str(p.id)] = p


func rules() -> Dictionary:
	return ctx.data.rules("run_rules")


## Chiavi di data/run_rules.json lette dal codice (SENZA numeri di ripiego, regola 2): se ne manca una `rule()` scrive un errore
## chiaro e il test tests/test_run_system.gd fallisce.
const REQUIRED_RULES: PackedStringArray = ["unlock_hero_level", "unlock_token", "kills_per_choice", "max_choices", "offers",
	"max_stacks", "rerolls_per_run", "banishes_per_run", "ask_timeout_s", "default_mode", "modes", "safety_defense_first",
	"rng_stream", "modifier_source", "worse_if_higher", "history_max", "families", "champion.hp_mult", "champion.dmg_mult",
	"champion.reward_mult", "champion.loot_rolls", "champion.crate_chance", "champion.retreat_hp_pct", "champion.max_attempts"]


## Chiavi richieste assenti dalle regole (vuoto = tutto a posto).
static func missing_rule_keys(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for path in REQUIRED_RULES:
		var cur: Variant = r
		for part in path.split("."):
			if cur is Dictionary and (cur as Dictionary).has(part):
				cur = cur[part]
			else:
				out.append(path)
				break
	return out


## Legge una regola per percorso («champion.hp_mult»). Mancante = errore chiaro (nessun valore di ripiego nel codice).
func rule(path: String) -> Variant:
	var cur: Variant = rules()
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			push_error("RunSystem: manca la regola «%s» in data/run_rules.json" % path)
			return null
	return cur


func perk(pid: String) -> Dictionary:
	if _perk_index.is_empty():
		setup()
	return _perk_index.get(pid, {})


func default_state() -> Variant:
	var order: Array = []
	for f in rule("families"):
		order.append(str(f.id))
	return {"zone": "", "kills": 0, "picks": [], "offer": [], "offer_s": 0.0, "rerolls": 0, "banishes": 0, "banned": [],
		"champion": "", "champ_attempts": 0, "champ_kills": 0, "mode": str(rule("default_mode")), "order": order,
		"history": [], "runs_done": 0, "champions": 0}


func from_state(section: Variant) -> void:
	state = section
	var d: Dictionary = default_state()
	for k in d:
		if not state.has(k) or typeof(state[k]) != typeof(d[k]):
			state[k] = d[k]
	# voci sparite dai dati (versioni future): via, senza rompere il salvataggio
	for key in ["picks", "offer", "banned"]:
		var clean: Array = []
		for pid in state[key]:
			if not perk(str(pid)).is_empty():
				clean.append(str(pid))
		state[key] = clean
	if not (rule("modes") as Array).has(str(state.mode)):
		state["mode"] = str(rule("default_mode"))
	var fams: Array = d.order
	var fam_order: Array = []
	for f in state.order:
		if fams.has(str(f)) and not fam_order.has(str(f)):
			fam_order.append(str(f))
	for f in fams:
		if not fam_order.has(f):
			fam_order.append(f)
	state["order"] = fam_order
	_active = false
	_token_done = false
	if ctx.modifiers != null:
		ctx.modifiers.clear_source(_source())


func int_paths() -> PackedStringArray:
	return PackedStringArray(["kills", "rerolls", "banishes", "champ_attempts", "champ_kills", "runs_done", "champions"])


## Interi «morbidi» (GameSystem.soft_int_paths): voci dello storico delle Corse.
func soft_int_paths() -> PackedStringArray:
	return PackedStringArray(["history[].picks"])


## Offline: la Corsa non avanza e non agisce (91 §3.9). Niente tick a passi fissi.
func simulate_offline(_seconds: float) -> Dictionary:
	suspend()
	return {}


func has_tick() -> bool:
	return true


# ====================================================================== accesso

func _combat() -> Variant:
	return ctx.get_system("combat")


func _source() -> String:
	return str(rule("modifier_source"))


func unlocked() -> bool:
	var c: Variant = _combat()
	return c != null and int(c.hero_level()) >= int(rule("unlock_hero_level"))


## Zona in cui si combatte adesso in modalità zona ("" se non si combatte in una zona).
func _fight_zone() -> String:
	var a: Variant = ctx.state.get("activity", {})
	if not (a is Dictionary) or str(a.get("type", "")) != "combat":
		return ""
	if not (str(a.get("mode", "")) in ["", "zone"]):
		return ""
	var c: Variant = _combat()
	if c != null and not (c.trial_rules() as Dictionary).is_empty():
		return ""
	return str(a.get("zone", ""))


func is_active() -> bool:
	return _active


func picks() -> Array:
	return state.picks


func stacks() -> Dictionary:
	var out := {}
	for pid in state.picks:
		out[pid] = int(out.get(pid, 0)) + 1
	return out


func offer() -> Array:
	return state.offer


## Riepilogo per la UI: stato, avanzamento, voci, Campione.
func status() -> Dictionary:
	var zone := _fight_zone()
	var phase := "locked"
	if unlocked():
		if zone.is_empty():
			phase = "paused"
		elif not str(state.zone).is_empty() and zone != str(state.zone):
			phase = "new_zone"
		else:
			phase = "active"
	return {"phase": phase, "zone": str(state.zone), "kills": int(state.kills), "per_choice": int(rule("kills_per_choice")),
		"picks": (state.picks as Array).size(), "max": int(rule("max_choices")), "offer": (state.offer as Array).duplicate(),
		"offer_left_s": maxf(0.0, float(rule("ask_timeout_s")) - float(state.offer_s)), "mode": str(state.mode),
		"champion": str(state.champion), "champ_kills": int(state.champ_kills), "rerolls_left": rerolls_left(),
		"banishes_left": banishes_left(), "unlock_level": int(rule("unlock_hero_level"))}


func rerolls_left() -> int:
	return maxi(0, int(rule("rerolls_per_run")) - int(state.rerolls))


func banishes_left() -> int:
	return maxi(0, int(rule("banishes_per_run")) - int(state.banishes))


## Modificatori correnti della Corsa (somma delle voci prese, ognuna × accumuli), nel formato di Modifiers.
func current_mods() -> Array:
	var sums := {}
	var keys: Array = []
	for pid in state.picks:
		for m in perk(str(pid)).get("modifiers", []):
			var k := str(m.key)
			if not sums.has(k):
				keys.append(k)
			sums[k] = float(sums.get(k, 0.0)) + float(m.value)
	var out: Array = []
	for k in keys:
		if absf(float(sums[k])) > 1e-9:
			out.append({"key": k, "value": float(sums[k]), "mode": "add"})
	return out


## true se il valore positivo della famiglia è un malus (run_rules.worse_if_higher): per i colori del pannello.
func is_gain(m: Dictionary) -> bool:
	var worse: Array = rule("worse_if_higher")
	return (float(m.value) > 0.0) != worse.has(str(m.key).split(":")[0])


# ====================================================================== ciclo

func tick(dt: float) -> void:
	if state == null:
		return
	var zone := _fight_zone()
	var want := false
	if not _token_done and unlocked():
		_grant_token()
	if not zone.is_empty() and unlocked():
		if str(state.zone) != zone:
			_end_run("zone")
			state["zone"] = zone
		want = true
	_set_active(want)
	if (state.offer as Array).is_empty():
		return
	if str(state.mode) == "auto":
		auto_pick()
	elif want:
		state["offer_s"] = float(state.offer_s) + dt
		if float(state.offer_s) >= float(rule("ask_timeout_s")):
			auto_pick()


## Al livello di sblocco: token `feature:run` (UnlockSystem, idempotente) -> scheda tutorial al primo sblocco.
func _grant_token() -> void:
	_token_done = true
	var tok := str(rule("unlock_token"))
	var un: Variant = ctx.get_system("unlock")
	if not tok.is_empty() and un != null:
		un.grant(tok)


## Toglie la fonte dei modificatori (offline, prove): la Corsa resta salvata com'è.
func suspend() -> void:
	_set_active(false)


func _set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if ctx.modifiers == null:
		return
	if on:
		var mods := current_mods()
		if mods.is_empty():
			ctx.modifiers.clear_source(_source())
		else:
			ctx.modifiers.set_source(_source(), mods)
	else:
		ctx.modifiers.clear_source(_source())


func _refresh_source() -> void:
	if _active and ctx.modifiers != null:
		var mods := current_mods()
		if mods.is_empty():
			ctx.modifiers.clear_source(_source())
		else:
			ctx.modifiers.set_source(_source(), mods)


func _emit(e: Dictionary) -> void:
	event_seq += 1
	e["id"] = event_seq
	last_event = e


## Una uccisione nella zona (chiamata da CombatSystem._kill per i mostri non Campione).
func on_kill() -> void:
	if not _active:
		return
	var kpc := int(rule("kills_per_choice"))
	if str(state.champion) == "wait":
		state["champ_kills"] = int(state.champ_kills) + 1
		if int(state.champ_kills) >= kpc:
			state["champion"] = "due"
			state["champ_kills"] = 0
			_emit({"k": "champion_due"})
		return
	if (state.picks as Array).size() >= int(rule("max_choices")) or not (state.offer as Array).is_empty():
		return
	state["kills"] = mini(kpc, int(state.kills) + 1)
	if int(state.kills) >= kpc:
		_make_offer()


func _available(exclude: Array) -> Array:
	var st := stacks()
	var out: Array = []
	for p in ctx.data.table("run_perks"):
		var pid := str(p.id)
		if (state.banned as Array).has(pid) or exclude.has(pid):
			continue
		if int(st.get(pid, 0)) >= int(rule("max_stacks")):
			continue
		out.append(pid)
	return out


func _draw(n: int, exclude: Array) -> Array:
	var pool := _available(exclude)
	var out: Array = []
	var stream := str(rule("rng_stream"))
	while out.size() < n and not pool.is_empty():
		var i: int = ctx.rng.randi_range(stream, 0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


func _make_offer() -> void:
	state["kills"] = 0
	state["offer"] = _draw(int(rule("offers")), [])
	state["offer_s"] = 0.0
	if not (state.offer as Array).is_empty():
		_emit({"k": "offer"})
		if ctx.events != null and str(state.mode) == "ask":
			ctx.events.notice.emit("info", Loc.tf("UI_RUN_NOTICE_OFFER", {"n": (state.picks as Array).size() + 1}), {"section": "combat"})


## Sceglie la voce `index` dell'offerta corrente.
func choose(index: int) -> bool:
	var off: Array = state.offer
	if index < 0 or index >= off.size():
		return false
	var pid := str(off[index])
	(state.picks as Array).append(pid)
	state["offer"] = []
	state["offer_s"] = 0.0
	_refresh_source()
	_emit({"k": "pick", "perk": pid})
	if (state.picks as Array).size() >= int(rule("max_choices")):
		state["champion"] = "due"
		state["champ_attempts"] = 0
		state["champ_kills"] = 0
		_emit({"k": "champion_due"})
	return true


## «Rilancia»: tre voci nuove (una volta per Corsa).
func reroll() -> bool:
	if rerolls_left() <= 0 or (state.offer as Array).is_empty():
		return false
	var old: Array = (state.offer as Array).duplicate()
	var fresh := _draw(old.size(), old)
	if fresh.size() < old.size():
		fresh = _draw(old.size(), [])
	state["offer"] = fresh
	state["rerolls"] = int(state.rerolls) + 1
	_emit({"k": "offer"})
	return true


## «Escludi»: toglie la voce `index` da questa Corsa e la sostituisce (una volta per Corsa).
func banish(index: int) -> bool:
	var off: Array = state.offer
	if banishes_left() <= 0 or index < 0 or index >= off.size():
		return false
	var pid := str(off[index])
	(state.banned as Array).append(pid)
	var repl := _draw(1, off)
	if repl.is_empty():
		off.remove_at(index)
	else:
		off[index] = repl[0]
	state["banishes"] = int(state.banishes) + 1
	_emit({"k": "offer"})
	return true


func set_mode(mode: String) -> void:
	if (rule("modes") as Array).has(mode):
		state["mode"] = mode


## Sposta una famiglia nella priorità di «Scegli per me» (delta -1 = più in alto).
func move_family(fam: String, delta: int) -> void:
	var fam_order: Array = state.order
	var i := fam_order.find(fam)
	var j := i + delta
	if i < 0 or j < 0 or j >= fam_order.size():
		return
	fam_order[i] = fam_order[j]
	fam_order[j] = fam


## Priorità effettiva: quella del giocatore, con la Difesa in testa se «Sicuro in idle» è rosso (run_rules.safety_defense_first).
func effective_order() -> Array:
	var fam_order: Array = (state.order as Array).duplicate()
	if bool(rule("safety_defense_first")) and _unsafe():
		fam_order.erase("defense")
		fam_order.push_front("defense")
	return fam_order


func _unsafe() -> bool:
	var c: Variant = _combat()
	if c == null:
		return false
	var a: Variant = ctx.state.get("activity", {})
	var mid := str(a.get("monster", "")) if a is Dictionary else ""
	if mid.is_empty() and a is Dictionary:
		mid = str((a.get("enemy", {}) as Dictionary).get("id", "")) if a.get("enemy") is Dictionary else ""
	if mid.is_empty():
		return false
	var s: Dictionary = c.idle_safety(mid)
	return str(s.get("level", "green")) == "red"


## Indice della voce che «Scegli per me» prenderebbe: la famiglia più alta nella priorità, a parità la prima offerta.
func auto_index() -> int:
	var off: Array = state.offer
	if off.is_empty():
		return -1
	var fam_order := effective_order()
	var best := 0
	var best_rank := 1 << 20
	for i in off.size():
		var rnk := fam_order.find(str(perk(str(off[i])).get("family", "")))
		if rnk < 0:
			rnk = fam_order.size()
		if rnk < best_rank:
			best_rank = rnk
			best = i
	return best


func auto_pick() -> bool:
	var i := auto_index()
	return i >= 0 and choose(i)


# ====================================================================== Campione

## true se la prossima comparsa nella zona deve essere il Campione della Corsa.
func champion_due() -> bool:
	return _active and (str(state.champion) == "due" or str(state.champion) == "fighting")


func champion_rules() -> Dictionary:
	return rule("champion")


func on_champion_spawn() -> void:
	state["champion"] = "fighting"
	_emit({"k": "champion"})


## Esito del Campione: vinto (premio già consegnato da CombatSystem) o ritirato.
func on_champion_result(won: bool) -> void:
	if won:
		state["champions"] = int(state.champions) + 1
		_end_run("champion")
		return
	state["champ_attempts"] = int(state.champ_attempts) + 1
	if int(state.champ_attempts) >= int(rule("champion.max_attempts")):
		_end_run("champion_fled")
	else:
		state["champion"] = "wait"
		state["champ_kills"] = 0
		_emit({"k": "champion_fled"})


func _end_run(reason: String) -> void:
	var had := not (state.picks as Array).is_empty() or int(state.kills) > 0
	if had:
		var hist: Array = state.history
		hist.push_front({"zone": str(state.zone), "picks": (state.picks as Array).size(), "end": reason})
		while hist.size() > int(rule("history_max")):
			hist.pop_back()
		if reason == "champion" or reason == "champion_fled":
			state["runs_done"] = int(state.runs_done) + 1
		_emit({"k": "end", "reason": reason})
	state["kills"] = 0
	state["picks"] = []
	state["offer"] = []
	state["offer_s"] = 0.0
	state["rerolls"] = 0
	state["banishes"] = 0
	state["banned"] = []
	state["champion"] = ""
	state["champ_attempts"] = 0
	state["champ_kills"] = 0
	_refresh_source()
