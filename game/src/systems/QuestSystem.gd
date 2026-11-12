class_name QuestSystem
extends GameSystem
## Missioni (docs/12): storia principale lineare + percorsi di mansione + altre categorie accettate a richiesta.
## Stato `quests`: {"active": [id], "progress": {id: [int per obiettivo]}, "done": [id],
##   "tut_seen": [token], "tut_pending": [token], "intro_seen": bool}. Sezione `contracts` (Commesse): non toccata
##   in questa fase (la slice non le prevede; vedi 24_RESOCONTO_QUESTS.md).
##
## Ciclo di una missione: accettata (sblocca ciò che serve subito + dona gli oggetti che le servono) -> obiettivi
## completati (pronta) -> claim() (ricompense + sblocchi restanti + si accetta la successiva).
## Gli eventi di EventBus vengono ACCODATI e applicati nel tick (ordine fisso, R-AZ-3 punto 8); offline: simulate_offline.
## Tipi di obiettivo: vedi docs/12 §3. Gli eventi "generici" arrivano da EventBus.objective_event(kind, params).

const STATE_RECHECK_S := 1.0
## Chiavi dell'obiettivo che non servono al confronto con i parametri dell'evento.
const RESERVED_KEYS: PackedStringArray = ["type", "qty", "level", "floor", "gold"]
## Se manca nei parametri dell'evento, la chiave dell'obiettivo si considera soddisfatta.
const OPTIONAL_KEYS: PackedStringArray = ["era"]
## Obiettivi verificati sullo stato attuale (R-QU-1): il valore non scende mai.
const STATE_TYPES: PackedStringArray = ["reach_level", "reach_total_level", "build", "equip", "estate_total_levels"]
## Categorie accettate in automatico (le altre con accept()).
const AUTO_KINDS: PackedStringArray = ["main", "skill_path"]
## Fonte Modifiers degli spazi del Deposito delle missioni (regola 4: ogni bonus passa da Modifiers).
const BANK_SLOTS_SOURCE := "quest:bank_slots"

var _defs: Dictionary = {}
var _main_ids: Array = []                # missioni main nell'ordine dei dati
var _queue: Array = []
var _recheck_t: float = 1e9
var _dirty: bool = true
var _tally: Dictionary = {}
var _pending_offline: Dictionary = {}


func _init() -> void:
	id = "quests"
	state_key = "quests"


func default_state() -> Variant:
	return _fresh_state()


static func _fresh_state() -> Dictionary:
	return {"active": [], "progress": {}, "done": [], "tut_seen": [], "tut_pending": [], "intro_seen": false, "seen_screens": []}


func int_paths() -> PackedStringArray:
	return PackedStringArray(["progress.*[]"])


func setup() -> void:
	_defs.clear()
	_main_ids.clear()
	for q in ctx.data.table("quests"):
		_defs[str(q.id)] = q
		if str(q.get("kind", "")) == "main":
			_main_ids.append(str(q.id))
	_reset_tally()
	var ev: Object = ctx.events
	ev.action_completed.connect(_cb_action_completed)
	ev.action_batch_completed.connect(_cb_action_batch_completed)
	ev.monster_killed.connect(_cb_monster_killed)
	ev.monsters_killed_batch.connect(_cb_monsters_killed_batch)
	ev.crate_opened.connect(_cb_crate_opened)
	ev.star_gained.connect(_cb_star_gained)
	ev.objective_event.connect(_cb_objective_event)
	ev.level_up.connect(_cb_level_up)
	ev.estate_changed.connect(_cb_estate_changed)
	ev.unlocked.connect(_cb_unlocked)
	ev.item_gained.connect(_cb_item_gained)
	ev.xp_gained.connect(_cb_xp_gained)
	ev.crate_found.connect(_cb_crate_found)
	ev.offline_progress.connect(_cb_offline_progress)
	ev.state_loaded.connect(_cb_state_loaded)


# Callback di EventBus: metodi (non lambda) perché un sistema distrutto si scollega da solo.
func _cb_action_completed(a: String, o: Array) -> void:
	_on_action_completed(a, o)


func _cb_action_batch_completed(a: String, n: int, o: Array) -> void:
	_on_action_completed(a, o, n)


func _cb_monster_killed(m: String, d: Array) -> void:
	_on_monster_killed(m, d)


func _cb_monsters_killed_batch(m: String, n: int, d: Array) -> void:
	_on_monster_killed(m, d, n)


func _cb_crate_opened(r: Dictionary) -> void:
	_on_crate_opened(r)


func _cb_star_gained(sk: String) -> void:
	_push("star", {"skill": sk, "qty": 1})


func _cb_objective_event(k: String, p: Dictionary) -> void:
	_push(k, p)


func _cb_level_up(sk: String, lv: int) -> void:
	_on_level_up(sk, lv)


func _cb_estate_changed() -> void:
	_dirty = true


func _cb_unlocked(t: String) -> void:
	_on_unlocked(t)


func _cb_item_gained(d: String, q: int, _src: String) -> void:
	_tally_add("items", d, q)


func _cb_xp_gained(sk: String, a: float) -> void:
	_tally_add("xp", sk, a)


func _cb_crate_found(c: String, _src: String) -> void:
	_tally_add("crates", c, 1)


func _cb_offline_progress(sec: float, rep: Dictionary) -> void:
	_pending_offline = {"seconds": sec, "report": rep}


func _cb_state_loaded() -> void:
	if state != null and ctx.state.get("quests") == state:
		start()


func from_state(section: Variant) -> void:
	state = section
	var base := _fresh_state()
	for k in base:
		if not state.has(k) or typeof(state[k]) != typeof(base[k]):
			state[k] = base[k]
	for q in state.active.duplicate():       # salvataggio incoerente: missione ignota o senza contatori
		if not _defs.has(q):
			state.active.erase(q)
		elif not (state.progress.get(q) is Array) or state.progress[q].size() != _defs[q].get("objectives", []).size():
			var zeros: Array = []
			for _o in _defs[q].get("objectives", []):
				zeros.append(0)
			state.progress[q] = zeros
		else:
			var pr: Array = state.progress[q]
			for i in pr.size():
				pr[i] = int(pr[i])
	_queue.clear()
	_pending_offline = {}
	_reset_tally()
	_recheck_t = 1e9
	_dirty = true
	_apply_reward_mods()


## Fonte Modifiers degli spazi del Deposito regalati dalle missioni riscattate (ricompensa `bank_slots`). Derivata da
## `done` a ogni load/riscatto: nessuno stato nuovo nel salvataggio, e chi aveva già riscattato quelle missioni li riceve.
func _apply_reward_mods() -> void:
	if ctx == null or ctx.modifiers == null or state == null:
		return
	var n := bank_slots_earned()
	ctx.modifiers.set_source(BANK_SLOTS_SOURCE, [{"key": "bank_slots", "value": float(n), "mode": "add"}] if n > 0 else [])


## Spazi del Deposito già ottenuti dalle missioni riscattate.
func bank_slots_earned() -> int:
	var n := 0
	for qid in (state.done as Array):
		n += int(_defs.get(str(qid), {}).get("rewards", {}).get("bank_slots", 0))
	return n


## Tutte le missioni con ricompensa di spazi del Deposito, nell'ordine dei dati: [{quest, chapter, slots, done}].
func bank_slot_rewards() -> Array:
	var out: Array = []
	for qid in _main_ids:
		var s := int(_defs[qid].get("rewards", {}).get("bank_slots", 0))
		if s > 0:
			out.append({"quest": qid, "chapter": int(_defs[qid].get("chapter", 0)), "slots": s, "done": is_done(qid)})
	return out


## Avvio idempotente: accetta la missione principale se non ce n'è una attiva. Da chiamare dopo bind_state
## (lo fa da solo il primo tick o il segnale state_loaded).
func start() -> void:
	_ensure_accepted()
	_check_states()
	_recheck_t = 0.0
	_dirty = false


# ------------------------------------------------------------------ interrogazioni

func quest_def(quest_id: String) -> Dictionary:
	return _defs.get(quest_id, {})


func is_done(quest_id: String) -> bool:
	return (state.done as Array).has(quest_id)


func is_active(quest_id: String) -> bool:
	return (state.active as Array).has(quest_id)


## Valore bersaglio dell'obiettivo (qty, livello, oro, piano…).
static func target_of(obj: Dictionary) -> int:
	match str(obj.get("type", "")):
		"build", "reach_level", "reach_total_level":
			return int(obj.get("level", 1))
		"sell_market":
			return int(obj.get("gold", 1))
		"rift_floor":
			return int(obj.get("floor", 1))
	return int(obj.get("qty", 1))


func progress_of(quest_id: String) -> Array:
	return state.progress.get(quest_id, [])


func is_ready(quest_id: String) -> bool:
	if not is_active(quest_id):
		return false
	var d := quest_def(quest_id)
	var pr := progress_of(quest_id)
	var objs: Array = d.get("objectives", [])
	for i in objs.size():
		if i >= pr.size() or int(pr[i]) < target_of(objs[i]):
			return false
	return true


func ready_count() -> int:
	var n := 0
	for q in state.active:
		if is_ready(q):
			n += 1
	return n


## Missione principale in corso ("" se la storia è finita).
func current_main() -> String:
	for q in state.active:
		if str(_defs.get(q, {}).get("kind", "")) == "main":
			return q
	return ""


## Missioni attive (storia per prima): [{id, kind, chapter, progress, targets, ready}].
func active_quests() -> Array:
	var out: Array = []
	for q in state.active:
		var d := quest_def(q)
		var targets: Array = []
		for o in d.get("objectives", []):
			targets.append(target_of(o))
		out.append({"id": q, "kind": str(d.get("kind", "")), "chapter": int(d.get("chapter", 0) if d.get("chapter") != null else 0),    # gli incarichi di fazione hanno chapter null
			"progress": progress_of(q).duplicate(), "targets": targets, "ready": is_ready(q)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := 0 if a.kind == "main" else 1
		var mb := 0 if b.kind == "main" else 1
		return ma < mb)
	return out


## Frazione 0..1 di avanzamento complessivo della missione.
func fraction(quest_id: String) -> float:
	var objs: Array = quest_def(quest_id).get("objectives", [])
	if objs.is_empty():
		return 1.0
	var pr := progress_of(quest_id)
	var sum := 0.0
	for i in objs.size():
		var t := maxi(1, target_of(objs[i]))
		sum += minf(1.0, float(int(pr[i]) if i < pr.size() else 0) / float(t))
	return sum / float(objs.size())


# ------------------------------------------------------------------ azioni

## Accetta una missione non principale (o una principale fuori ordine nei test). false se già attiva/finita.
func accept(quest_id: String) -> bool:
	if not _defs.has(quest_id) or is_active(quest_id) or is_done(quest_id):
		return false
	var d: Dictionary = _defs[quest_id]
	state.active.append(quest_id)
	var zeros: Array = []
	for _o in d.get("objectives", []):
		zeros.append(0)
	state.progress[quest_id] = zeros
	# sblocca subito solo ciò che serve a svolgere gli obiettivi (gli altri sistemi arrivano alla consegna)
	for t in _early_tokens(d):
		_grant(t)
	# oggetti che servono alla missione stessa (es. la spada da equipaggiare): dati all'accettazione
	for it in _prefilled_items(d):
		_give_item(str(it.item), int(it.get("qty", 1)))
	_dirty = true
	_check_states()
	ctx.events.notice.emit("info", Loc.tf("UI_QUESTS_NEW", {"title": Loc.t(d.get("title", quest_id))}), {"quest": quest_id})
	return true


## Riscatta le ricompense di una missione completata. false se non è pronta.
func claim(quest_id: String) -> bool:
	if not is_ready(quest_id):
		return false
	var d: Dictionary = _defs[quest_id]
	var skip := _prefilled_items(d)
	# Resoconto 117: col Deposito pieno le ricompense non bloccano più la missione (FIX-MEDIO QA2 la teneva "pronta" finché non
	# si liberava posto): gli oggetti che non entrano vanno nel Carro di Ritiro (bank.add) e si scaricano da soli.
	_give_rewards(d.get("rewards", {}), skip)
	var early := _early_tokens(d)
	for t in d.get("unlocks", []):
		if not early.has(t):
			_grant(str(t))
	state.active.erase(quest_id)
	state.progress.erase(quest_id)
	state.done.append(quest_id)
	_apply_reward_mods()
	var bslots := int(d.get("rewards", {}).get("bank_slots", 0))
	if bslots > 0:
		ctx.events.notice.emit("success", Loc.tf("UI_BANKX_QUEST_GAIN", {"n": bslots}), {"reason": "bank_slots", "quest": quest_id})
	ctx.events.quest_completed.emit(quest_id)
	ctx.events.notice.emit("success", Loc.tf("UI_QUESTS_CLAIMED", {"title": Loc.t(d.get("title", quest_id))}), {"quest": quest_id})
	ctx.events.important_event.emit("quest")
	_ensure_accepted()
	_check_states()
	return true


## «Parla con un PNG» (obiettivo `talk`): il giocatore preme «Parla» nella scheda della missione. Emette l'evento
## solo se esiste una missione attiva con un obiettivo `talk` per quel PNG non ancora completato. false altrimenti.
func talk(npc_id: String) -> bool:
	if state == null or not has_open_talk(npc_id):
		return false
	_push("talk", {"npc": npc_id, "qty": 1})
	_flush()
	var npc: Dictionary = ctx.data.get_def("npcs", npc_id)
	ctx.events.notice.emit("info", Loc.tf("UI_QUESTS_TALK_DONE", {"name": Loc.t(npc.get("name", npc_id))}), {"npc": npc_id})
	return true


## true se una missione attiva ha un obiettivo `talk` aperto con questo PNG.
func has_open_talk(npc_id: String) -> bool:
	for q in state.active:
		var objs: Array = _defs.get(q, {}).get("objectives", [])
		var pr := progress_of(q)
		for i in objs.size():
			var o: Dictionary = objs[i]
			if str(o.get("type", "")) == "talk" and str(o.get("npc", "")) == npc_id \
					and (i >= pr.size() or int(pr[i]) < target_of(o)):
				return true
	return false


## Consegna (obiettivo `deliver`): consuma dal Deposito fino a completare l'obiettivo. false se non è possibile.
func deliver(quest_id: String, objective_index: int) -> bool:
	if not is_active(quest_id):
		return false
	var objs: Array = _defs[quest_id].get("objectives", [])
	if objective_index < 0 or objective_index >= objs.size():
		return false
	var obj: Dictionary = objs[objective_index]
	var bank := ctx.get_system("bank")
	if str(obj.get("type", "")) != "deliver" or bank == null:
		return false
	var pr: Array = state.progress[quest_id]
	var need := target_of(obj) - int(pr[objective_index])
	var n := mini(need, int(bank.call("count", str(obj.item))))
	if n <= 0 or not bool(bank.call("remove", str(obj.item), n)):
		return false
	_set_progress(quest_id, objective_index, int(pr[objective_index]) + n)
	return true


## Anteprima ricompense per la UI: [{"kind": "gold|item|crate|tome|unlock", "id": String, "qty": int}].
func reward_preview(quest_id: String) -> Array:
	var d := quest_def(quest_id)
	var out: Array = []
	var r: Dictionary = d.get("rewards", {})
	if int(r.get("gold", 0)) > 0:
		out.append({"kind": "gold", "id": "gold", "qty": int(r.gold)})
	var skip := _prefilled_items(d)
	for it in r.get("items", []):
		if skip.has(it):
			continue
		var cat := str(ctx.data.item(str(it.item)).get("category", ""))
		out.append({"kind": "crate" if cat == "crate" else "item", "id": str(it.item), "qty": int(it.get("qty", 1))})
	var tome: Variant = r.get("xp_tome")
	if tome is Dictionary:
		out.append({"kind": "tome", "id": _tome_id(tome), "qty": 1})
	if int(r.get("bank_slots", 0)) > 0:
		out.append({"kind": "bank_slots", "id": "bank_slots", "qty": int(r.bank_slots)})
	var rep: Variant = r.get("reputation")
	if rep is Dictionary:
		out.append({"kind": "reputation", "id": str(rep.get("faction", "")), "qty": int(rep.get("amount", 0))})
	if str(r.get("title", "")) != "":
		out.append({"kind": "title", "id": str(r.title), "qty": 1})
	if str(r.get("cosmetic", "")) != "":
		out.append({"kind": "cosmetic", "id": str(r.cosmetic), "qty": 1})
	var early := _early_tokens(d)
	for t in d.get("unlocks", []):
		if not early.has(t) and UnlockSystem.has_tutorial(str(t)):
			out.append({"kind": "unlock", "id": str(t), "qty": 1})
	return out


# ------------------------------------------------------------------ incarichi di fazione (GUILD-2, T-5.3)

## Obiettivi per cui nessun sistema emette ancora l'evento: l'incarico si vede ma resta «In arrivo».
## Vuoto dall'integrazione finale (resoconto 47): `tradeup`/`refine_polish` li emette CrateSystem (Contratti e
## Affinatura), `complete_raid` EndgameCombat (Incursioni). Vedi docs/OPEN_QUESTIONS.md G2-1.
const NO_SOURCE_YET: PackedStringArray = []


## I sei incarichi di una fazione, in ordine (id `side_<fazione>_1..6`).
func faction_quests(faction_id: String) -> Array:
	var out: Array = []
	for i in range(1, 7):
		var qid := "side_%s_%d" % [faction_id, i]
		if _defs.has(qid):
			out.append(qid)
	return out


## "available" | "active" | "ready" | "done" | "locked" (requisiti) | "pending" (manca la fonte dell'evento).
func faction_quest_status(quest_id: String) -> String:
	if is_done(quest_id):
		return "done"
	if is_ready(quest_id):
		return "ready"
	if is_active(quest_id):
		return "active"
	var d := quest_def(quest_id)
	if d.is_empty() or not _requires_met(d):
		return "locked"
	for o in d.get("objectives", []):
		if NO_SOURCE_YET.has(str(o.get("type", ""))):
			return "pending"
	return "available"


## Accetta un incarico di fazione se i requisiti sono soddisfatti e la fonte degli eventi esiste.
func accept_faction_quest(quest_id: String) -> bool:
	if faction_quest_status(quest_id) != "available":
		return false
	return accept(quest_id)


# ------------------------------------------------------------------ introduzione e tutorial (UI)

func intro_pending() -> bool:
	return not bool(state.intro_seen)


func mark_intro_seen() -> void:
	state["intro_seen"] = true


## Prossimo tutorial da mostrare (token) o "" . Lo segna come visto.
func take_tutorial() -> String:
	if (state.tut_pending as Array).is_empty():
		return ""
	var t: String = state.tut_pending.pop_front()
	if not (state.tut_seen as Array).has(t):
		state.tut_seen.append(t)
	return t


## Schermate che il giocatore ha già aperto (passi di scoperta, tabella `guides`): serve solo a non riproporle.
func note_screen(screen_id: String) -> void:
	if screen_id.is_empty() or (state.seen_screens as Array).has(screen_id):
		return
	(state.seen_screens as Array).append(screen_id)


func has_seen_screen(screen_id: String) -> bool:
	return (state.seen_screens as Array).has(screen_id)


func tutorial_pending() -> bool:
	return not (state.tut_pending as Array).is_empty()


## Ultimo resoconto offline arrivato (una sola volta): {"seconds": float, "report": Dictionary} o {}.
func take_offline() -> Dictionary:
	var r := _pending_offline
	_pending_offline = {}
	return r


# ------------------------------------------------------------------ ciclo

func tick(dt: float) -> void:
	_flush()
	_recheck_t += dt
	if _dirty or _recheck_t >= STATE_RECHECK_S:
		_recheck_t = 0.0
		_dirty = false
		_ensure_accepted()
		_check_states()
	_reset_tally()


func to_state() -> Variant:
	_flush()
	return state


## Offline: applica gli eventi accodati dai sistemi che girano prima (ordine fisso) e restituisce il resoconto.
## Formato in docs/audit_2026-10-22/24_RESOCONTO_QUESTS.md.
func simulate_offline(_seconds: float) -> Dictionary:
	var before := _snapshot()
	_flush()
	_ensure_accepted()
	_check_states()
	var progressed: Array = []
	var ready: Array = []
	for q in state.active:
		var now: Array = progress_of(q)
		if before.get(q, []) != now:
			progressed.append(q)
		if is_ready(q):
			ready.append(q)
	var rep := {}
	if not progressed.is_empty() or not ready.is_empty():
		rep["progressed"] = progressed
		rep["ready"] = ready
	for k in ["items", "xp", "crates", "levels"]:
		if not (_tally[k] as Dictionary).is_empty():
			rep[k] = _tally[k].duplicate(true)
	return rep


func _snapshot() -> Dictionary:
	var s := {}
	for q in state.active:
		s[q] = progress_of(q).duplicate()
	return s


# ------------------------------------------------------------------ eventi

func _push(kind: String, params: Dictionary) -> void:
	_queue.append([kind, params])


func _on_action_completed(action_id: String, outputs: Array, n: int = 1) -> void:
	var a: Dictionary = ctx.data.action(action_id)
	if a.is_empty():
		return
	var skill := str(a.get("skill", ""))
	_push("skill_actions", {"skill": skill, "qty": n})
	var is_craft: bool = not (a.get("inputs", []) as Array).is_empty()
	if skill == "thievery":
		_push("steal", {"target": action_id, "qty": n})
	for o in outputs:
		var item := _out_item(o)
		var qty := _out_qty(o)
		if item.is_empty() or qty <= 0:
			continue
		if skill == "farming":
			_push("farm_harvest", {"crop": item, "qty": qty * n})
		if is_craft:
			_push("craft", {"item": item, "qty": qty * n, "skill": skill})
			_push("craft_any", {"skill": skill, "qty": qty * n})
			if a.has("category"):
				_push("craft_category", {"category": str(a.category), "skill": skill, "qty": qty * n})
				# il rango è quello dell'oggetto prodotto (glifi: `glyph.rank`), non un campo dell'azione
				var rank := int(ctx.data.item(item).get("glyph", {}).get("rank", 0))
				if rank > 0:
					_push("craft_rank", {"category": str(a.category), "rank": rank, "skill": skill, "qty": qty * n})
		else:
			_push("gather", {"item": item, "qty": qty * n, "skill": skill})


static func _out_item(o: Variant) -> String:
	if o is Dictionary:
		return str(o.get("item", o.get("def_id", o.get("id", ""))))
	if o is Array and o.size() > 0:
		return str(o[0])
	return ""


static func _out_qty(o: Variant) -> int:
	if o is Dictionary:
		return int(o.get("qty", 1))
	if o is Array and o.size() > 1:
		return int(o[1])
	return 1


func _on_monster_killed(monster_id: String, _drops: Array, n: int = 1) -> void:
	var m: Dictionary = ctx.data.get_def("monsters", monster_id)
	_push("kill", {"monster": monster_id, "qty": n})
	_push("kill_any", {"qty": n})
	if not m.is_empty():
		_push("kill_zone", {"zone": str(m.get("zone", "")), "qty": n})
	var cls := str(ctx.state.get("hero", {}).get("class", ""))
	if not cls.is_empty():
		_push("kill_any_as_class", {"cls": cls, "qty": n})


func _on_crate_opened(result: Dictionary) -> void:
	var n := int(result.get("count", 1))
	_push("open_crates", {"crate": str(result.get("crate_id", result.get("crate", ""))), "qty": n})
	if result.has("rarity"):
		_push("obtain_rarity", {"rarity": str(result.rarity), "qty": n})


func _on_level_up(skill: String, level: int) -> void:
	_dirty = true
	_push("levels_gained", {"skill": skill, "qty": 1})
	var lv: Dictionary = _tally.levels
	if lv.has(skill):
		lv[skill][1] = level
	else:
		lv[skill] = [level - 1, level]


func _on_unlocked(token: String) -> void:
	if state == null or not UnlockSystem.has_tutorial(token):
		return
	if (state.tut_seen as Array).has(token) or (state.tut_pending as Array).has(token):
		return
	state.tut_pending.append(token)


func _reset_tally() -> void:
	_tally = {"items": {}, "xp": {}, "crates": {}, "levels": {}}


func _tally_add(section: String, key: String, amount: float) -> void:
	var d: Dictionary = _tally[section]
	if section == "xp":
		d[key] = float(d.get(key, 0.0)) + amount
	else:
		d[key] = int(d.get(key, 0)) + int(amount)


func _flush() -> void:
	if state == null:
		return
	var guard := 0
	while not _queue.is_empty() and guard < 100000:
		var ev: Array = _queue.pop_front()
		_apply_event(str(ev[0]), ev[1])
		guard += 1


func _apply_event(kind: String, params: Dictionary) -> void:
	var cs := ctx.get_system("contracts")        # le Commesse usano gli stessi eventi (ContractSystem, docs/12 §6)
	if cs != null:
		cs.call("apply_event", kind, params)
	for q in state.active.duplicate():
		var objs: Array = _defs.get(q, {}).get("objectives", [])
		for i in objs.size():
			var obj: Dictionary = objs[i]
			if str(obj.get("type", "")) != kind or STATE_TYPES.has(kind):
				continue
			if not _matches(obj, params):
				continue
			var cur := int(state.progress[q][i])
			var nv := cur
			if kind == "rift_floor":
				nv = maxi(cur, int(params.get("floor", 0)))
			elif kind == "sell_market":
				nv = cur + int(params.get("gold", 0))
			else:
				nv = cur + int(params.get("qty", 1))
			_set_progress(q, i, nv)


func _matches(obj: Dictionary, params: Dictionary) -> bool:
	for k in obj:
		if RESERVED_KEYS.has(k):
			continue
		var want: Variant = obj[k]
		if str(want) == "any":
			continue
		if not params.has(k):
			if OPTIONAL_KEYS.has(k):
				continue
			return false
		if not same_value(params[k], want):
			return false
	return true


## Confronto tra un parametro dell'evento e il valore atteso dall'obiettivo: i numeri dei dati JSON arrivano come float
## (5.0), quelli degli eventi come int (5): si confrontano come numeri, il resto come testo.
static func same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


func _set_progress(q: String, i: int, value: int) -> void:
	var objs: Array = _defs[q].get("objectives", [])
	var capped := mini(value, target_of(objs[i]))
	var pr: Array = state.progress[q]
	if capped == int(pr[i]):
		return
	var was_ready := is_ready(q)
	pr[i] = capped
	ctx.events.quest_progress.emit(q, i, capped)
	_dirty = true
	if not was_ready and is_ready(q):
		ctx.events.notice.emit("success", Loc.tf("UI_QUESTS_READY", {"title": Loc.t(_defs[q].get("title", q))}), {"quest": q})


# ------------------------------------------------------------------ obiettivi "di stato"

func _check_states() -> void:
	if state == null:
		return
	for q in state.active.duplicate():
		var objs: Array = _defs.get(q, {}).get("objectives", [])
		for i in objs.size():
			var obj: Dictionary = objs[i]
			if not STATE_TYPES.has(str(obj.get("type", ""))):
				continue
			var cur := int(state.progress[q][i])
			var v := _state_value(obj)
			if v > cur:
				_set_progress(q, i, v)


func _state_value(obj: Dictionary) -> int:
	match str(obj.get("type", "")):
		"reach_level":
			return _skill_level(str(obj.get("skill", "")))
		"reach_total_level":
			# FIX-MEDIO: conta il livello record di ogni mansione, così un Rito o una Stella (che riportano a 1)
			# non fanno arretrare gli obiettivi di livello totale della storia (Cap. VI-X).
			var t := 0
			for s in ctx.state.get("skills", {}).values():
				if s is Dictionary:
					t += maxi(int(s.get("level", 0)), int(s.get("record_level", 0)))
			return t
		"build":
			return int(ctx.state.get("estate", {}).get("buildings", {}).get(str(obj.get("building", "")), {}).get("level", 0))
		"estate_total_levels":
			var n := 0
			for b in ctx.state.get("estate", {}).get("buildings", {}).values():
				if b is Dictionary:
					n += int(b.get("level", 0))
			return n
		"equip":
			return target_of(obj) if _is_equipped(str(obj.get("item", ""))) else 0
	return 0


func _skill_level(skill: String) -> int:
	var sk := ctx.get_system("skills")
	if sk != null and sk.has_method("level"):
		return int(sk.call("level", skill))
	return int(ctx.state.get("skills", {}).get(skill, {}).get("level", 0))


func _is_equipped(item_id: String) -> bool:
	var eq: Variant = ctx.state.get("equipment", {})
	if not (eq is Dictionary):
		return false
	var bank := ctx.get_system("bank")
	for slot in eq:
		var v: Variant = eq[slot]
		var def_id := ""
		if v is String:
			def_id = v
			if bank != null and bank.has_method("get_instance"):
				var inst: Variant = bank.call("get_instance", v)
				if inst is Dictionary and not inst.is_empty():
					def_id = _inst_def(inst)
		elif v is Dictionary:
			def_id = _inst_def(v)
		if def_id == item_id:
			return true
	return false


static func _inst_def(inst: Dictionary) -> String:
	return str(inst.get("def", inst.get("def_id", inst.get("item", inst.get("id", "")))))


# ------------------------------------------------------------------ accettazione e sblocchi

## Accetta la prossima missione principale (e i percorsi di mansione sbloccati) se i requisiti sono soddisfatti.
func _ensure_accepted() -> void:
	if state == null:
		return
	if current_main().is_empty():
		for qid in _main_ids:
			if is_done(qid) or is_active(qid):
				continue
			if _requires_met(_defs[qid]):
				accept(qid)
				break
	for qid in _defs:
		var d: Dictionary = _defs[qid]
		if str(d.get("kind", "")) == "skill_path" and not is_done(qid) and not is_active(qid) \
				and _requires_met(d) and _skill_path_open(d):
			accept(qid)


func _requires_met(d: Dictionary) -> bool:
	for r in d.get("requires", []):
		var rs := str(r)
		if rs.contains(":"):                 # token di sblocco (es. "feature:factions" per gli incarichi di fazione)
			if not _has_unlock(rs):
				return false
		elif not is_done(rs):
			return false
	return true


func _skill_path_open(d: Dictionary) -> bool:
	for o in d.get("objectives", []):
		var sk := str(o.get("skill", ""))
		if not sk.is_empty():
			return _has_unlock("skill:" + sk)
	return false


func _has_unlock(token: String) -> bool:
	var u := ctx.get_system("unlock")
	if u != null:
		return bool(u.call("has", token))
	return (ctx.state.get("unlocks", []) as Array).has(token)


func _grant(token: String) -> void:
	var u := ctx.get_system("unlock")
	if u != null:
		u.call("grant", token)
	else:
		var arr: Array = ctx.state.get("unlocks", [])
		if not arr.has(token):
			arr.append(token)
			ctx.events.unlocked.emit(token)


## Sblocchi concessi all'accettazione: solo quelli che servono agli obiettivi (un sistema alla volta, docs/01 §6).
func _early_tokens(d: Dictionary) -> Array:
	var all: Array = d.get("unlocks", [])
	var need := {}
	for obj in d.get("objectives", []):
		for t in UnlockSystem.required_tokens(obj, ctx.data):
			if t == "*":
				return all.duplicate()
			need[t] = true
	var out: Array = []
	for t in all:
		if need.has(t):
			out.append(t)
	return out


## Oggetti delle ricompense che servono a un obiettivo `equip` della stessa missione (dati all'accettazione).
func _prefilled_items(d: Dictionary) -> Array:
	var wanted := {}
	for obj in d.get("objectives", []):
		if str(obj.get("type", "")) == "equip":
			wanted[str(obj.get("item", ""))] = true
	var out: Array = []
	for it in d.get("rewards", {}).get("items", []):
		if wanted.has(str(it.get("item", ""))) and not out.any(func(x: Dictionary) -> bool: return x.item == it.item):
			out.append(it)
	return out


# ------------------------------------------------------------------ ricompense

func _give_rewards(r: Dictionary, skip: Array) -> void:
	var bank := ctx.get_system("bank")
	var gold := int(r.get("gold", 0))
	if gold > 0:
		if bank != null:
			bank.call("add_gold", gold)
		else:
			push_warning("QuestSystem: sistema bank assente, oro non assegnato")
	var skipped := {}
	for it in r.get("items", []):
		var key := str(it.get("item", ""))
		if skip.any(func(x: Dictionary) -> bool: return x.item == key) and not skipped.has(key):
			skipped[key] = true       # una sola copia è già stata data all'accettazione
			continue
		_give_item(key, int(it.get("qty", 1)))
	var tome: Variant = r.get("xp_tome")
	if tome is Dictionary:
		_give_item(_tome_id(tome), 1)
	# GUILD-2: reputazione di fazione, titolo e cosmetico (prima ignorati)
	var rep: Variant = r.get("reputation")
	if rep is Dictionary:
		var mk := ctx.get_system("market")
		if mk != null:
			mk.call("add_reputation", str(rep.get("faction", "")), int(rep.get("amount", 0)))
	var comp := ctx.get_system("compendium")
	if comp != null:
		if str(r.get("title", "")) != "":
			comp.call("grant_title", str(r.title))
		if str(r.get("cosmetic", "")) != "":
			comp.call("grant_cosmetic", str(r.cosmetic))


func _tome_id(tome: Dictionary) -> String:
	return "tome_xp_" + str(tome.get("size", "small"))


func _give_item(item_id: String, qty: int) -> void:
	if qty <= 0 or not ctx.data.has_item(item_id):
		return
	if str(ctx.data.item(item_id).get("category", "")) == "crate":
		var crates := ctx.get_system("crates")
		if crates != null:
			crates.call("grant_crate", item_id, qty)
			return
	var bank := ctx.get_system("bank")
	if bank != null:
		bank.call("add", item_id, qty, "quest")
	else:
		push_warning("QuestSystem: sistema bank assente, oggetto non assegnato: " + item_id)
