class_name QueueSystem
extends GameSystem
## Coda delle azioni (docs/03 R-AZ-4/5, docs/10 §5, docs/16): azioni di mansione in sequenza con una condizione di fine.
## id "queue", stato "queue": {"entries": [{"action", "mode", "value", "done", "elapsed_s"}], "running": bool}.
##
## Modi (constants.queue.modes): "qty" = N completamenti riusciti · "level" = fino al livello della mansione ·
## "time" = N secondi · "exhaust" = finché finiscono gli ingredienti. La voce 0 è quella in corso.
## Posti: dall'Emporio (3 poi 6, NON cumulativi: vale il massimo posseduto) più le Costellazioni (modificatore
## `action_queue_slots`), più constants.queue.base_slots, con tetto constants.queue.max_slots.
## Se il giocatore avvia a mano un'altra attività, la coda si mette in pausa (running = false) senza perdere le voci.
## Il tempo offline passa da SkillSystem.simulate_offline (offline_cond / offline_commit).

signal changed()


func _init() -> void:
	id = "queue"
	state_key = "queue"


func default_state() -> Variant:
	return {"entries": [], "running": false}


func from_state(section: Variant) -> void:
	if not (section is Dictionary):         # segnaposto vecchio di GameState ("queue": []): si sostituisce
		section = default_state()
		ctx.state[state_key] = section
	state = section
	if not (state.get("entries") is Array):
		state["entries"] = []
	state["running"] = bool(state.get("running", false))
	var clean: Array = []
	for e in state.entries:
		if e is Dictionary and ctx.data.has_action(str(e.get("action", ""))) and str(e.get("mode", "")) in _modes():
			e["value"] = int(e.get("value", 0))
			e["done"] = int(e.get("done", 0))
			e["elapsed_s"] = float(e.get("elapsed_s", 0.0))
			clean.append(e)
	state["entries"] = clean
	if clean.is_empty():
		state["running"] = false


func int_paths() -> PackedStringArray:
	return PackedStringArray(["entries[].value", "entries[].done"])


func _modes() -> Array:
	return ctx.constants().queue.modes


func _skills() -> Object:
	return ctx.get_system("skills")


# ------------------------------------------------------------------ letture

## Posti totali della coda con lo stato attuale (Emporio + Costellazioni).
func slots() -> int:
	var k: Dictionary = ctx.constants().queue
	var total := ctx.modifiers.total_add("action_queue_slots", [])
	var shop_sum := 0.0
	var shop_best := 0.0
	var m := ctx.get_system("market")
	if m != null:
		shop_sum = float(m.shop_effect_total("action_queue_slots"))
		for e in ctx.data.table("shop"):
			if e.get("effect") is Dictionary and (e.effect as Dictionary).has("action_queue_slots") and int(m.owned(str(e.id))) > 0:
				shop_best = maxf(shop_best, float(e.effect.action_queue_slots))
		total = total - shop_sum + shop_best
	return clampi(int(k.base_slots) + int(round(total)), 0, int(k.max_slots))


func entries() -> Array:
	return state.entries


func size() -> int:
	return state.entries.size()


func is_running() -> bool:
	return bool(state.running) and not state.entries.is_empty()


func head() -> Dictionary:
	return state.entries[0] if not state.entries.is_empty() else {}


## "" se la voce si può aggiungere, altrimenti la chiave della ragione.
func can_add(action_id: String, mode: String, value: int) -> String:
	var a: Dictionary = ctx.data.action(action_id)
	if a.is_empty() or str(a.get("kind", "")) in ["crop", "tree"] or str(a.skill) in ["hero", "bounty"]:
		return "UI_QUEUE_REASON_ACTION"
	if bool(a.get("single_craft", false)):       # «una costruzione per volta»: la voce vale sempre 1 passo (più copie = più voci)
		mode = "qty"
		value = 1
	if not (mode in _modes()):
		return "UI_QUEUE_REASON_MODE"
	if mode != "exhaust" and value <= 0:
		return "UI_QUEUE_REASON_VALUE"
	if mode == "exhaust" and (a.get("inputs", []) as Array).is_empty():
		return "UI_QUEUE_REASON_EXHAUST"
	if size() >= slots():
		return "UI_QUEUE_REASON_FULL"
	return ""


# ------------------------------------------------------------------ modifica

func add(action_id: String, mode: String, value: int = 0) -> bool:
	if can_add(action_id, mode, value) != "":
		return false
	if bool(ctx.data.action(action_id).get("single_craft", false)):
		mode = "qty"
		value = 1
	state.entries.append({"action": action_id, "mode": mode, "value": value, "done": 0, "elapsed_s": 0.0})
	changed.emit()
	return true


func remove_at(index: int) -> bool:
	if index < 0 or index >= size():
		return false
	state.entries.remove_at(index)
	if index == 0 and is_running():
		_start_head()           # la voce in corso è stata tolta: parte la successiva (o la coda si chiude)
	if state.entries.is_empty():
		state["running"] = false
	changed.emit()
	return true


func move(index: int, delta: int) -> bool:
	var j := index + delta
	if index < 1 or j < 1 or index >= size() or j >= size():       # la voce 0 è in corso: non si sposta
		return false
	var e: Variant = state.entries[index]
	state.entries[index] = state.entries[j]
	state.entries[j] = e
	changed.emit()
	return true


func clear() -> void:
	state.entries.clear()
	state["running"] = false
	changed.emit()


# ------------------------------------------------------------------ avvio / arresto

## Avvia la coda dalla prima voce. false se vuota o nessuna voce è avviabile.
func start() -> bool:
	if state.entries.is_empty():
		return false
	state["running"] = true
	if not _start_head():
		state["running"] = false
		return false
	return true


## Mette in pausa la coda (le voci restano); l'attività in corso non viene toccata.
func pause() -> void:
	if bool(state.running):
		state["running"] = false
		changed.emit()


## Ferma la coda E l'attività in corso.
func stop() -> void:
	state["running"] = false
	var sk := _skills()
	if sk != null:
		sk.stop()
	changed.emit()


# ------------------------------------------------------------------ avanzamento

## Chiamata da SkillSystem dopo ogni ciclo risolto. true se l'attività in corso è stata cambiata o chiusa.
func on_cycle(action_id: String, success: bool) -> bool:
	if not is_running():
		return false
	var h: Dictionary = state.entries[0]
	if str(h.action) != action_id:
		return false
	if success:
		h["done"] = int(h.done) + 1
	if _head_satisfied(h) or (success and bool(ctx.data.action(action_id).get("single_craft", false))):
		_finish_head()
		return true
	return false


## Coda ferma: nessun tick da simulare (l'offline delle voci in corso lo guida SkillSystem via offline_cond/commit).
func simulate_offline(seconds: float) -> Dictionary:
	if not is_running():
		return {}
	return super.simulate_offline(seconds)


func tick(dt: float) -> void:
	if not is_running():
		return
	var sk := _skills()
	if sk == null:
		return
	var h: Dictionary = state.entries[0]
	var cur: String = sk.current_action()
	if cur.is_empty():
		# l'attività si è fermata da sola (ingredienti finiti, banca piena…): la voce è chiusa o saltata
		if _activity_type() == "combat":
			state["running"] = false
			return
		_finish_head(str(h.mode) != "exhaust")
		return
	if cur != str(h.action):
		state["running"] = false          # l'utente ha scelto altro a mano: pausa
		changed.emit()
		return
	if sk.is_waiting():
		sk.stop()                         # con una coda l'attesa non serve: si passa alla voce successiva
		_finish_head(str(h.mode) != "exhaust")
		return
	h["elapsed_s"] = float(h.elapsed_s) + dt
	if _head_satisfied(h):
		_finish_head()


func _activity_type() -> String:
	return str(ctx.state.get("activity", {}).get("type", ""))


func _head_satisfied(h: Dictionary) -> bool:
	match str(h.mode):
		"qty":
			return int(h.done) >= int(h.value)
		"level":
			var sk := _skills()
			return sk != null and int(sk.level(str(ctx.data.action(str(h.action)).skill))) >= int(h.value)
		"time":
			return float(h.elapsed_s) >= float(h.value)
	return false


## Toglie la voce in corso e avvia la successiva. `skipped` = la voce è stata saltata (non completata): avviso.
func _finish_head(skipped: bool = false) -> void:
	if not state.entries.is_empty():
		var h: Dictionary = state.entries[0]
		if skipped:
			ctx.events.notice.emit("warning", tr("UI_QUEUE_SKIPPED"), {"action": h.action})
		state.entries.remove_at(0)
	if state.entries.is_empty() or not _start_head():
		state["running"] = false
		var sk := _skills()
		if sk != null and sk.current_action() != "":
			sk.stop()
		ctx.events.notice.emit("info", tr("UI_QUEUE_DONE"), {"section": "skills"})
	changed.emit()


## Avvia la voce 0, scartando quelle già soddisfatte o non avviabili. false se la coda si esaurisce.
func _start_head() -> bool:
	var sk := _skills()
	while not state.entries.is_empty():
		var h: Dictionary = state.entries[0]
		h["done"] = 0
		h["elapsed_s"] = 0.0
		if not _head_satisfied(h) and sk != null and sk.start(str(h.action)):
			return true
		ctx.events.notice.emit("warning", tr("UI_QUEUE_SKIPPED"), {"action": h.action})
		state.entries.remove_at(0)
	return false


# ------------------------------------------------------------------ offline (usato da SkillSystem.simulate_offline)

## Condizione di fine della voce in corso per l'offline: {} se la coda non guida questa azione.
## Chiavi: max_n (cicli ancora da fare) · until_level · max_s (secondi) · exhaust.
func offline_cond(action_id: String) -> Dictionary:
	if not is_running() or str(state.entries[0].action) != action_id:
		return {}
	var h: Dictionary = state.entries[0]
	if bool(ctx.data.action(action_id).get("single_craft", false)):
		return {"max_n": maxf(0.0, 1.0 - float(int(h.done)))}
	match str(h.mode):
		"qty":
			return {"max_n": maxf(0.0, float(int(h.value) - int(h.done)))}
		"level":
			return {"until_level": int(h.value)}
		"time":
			return {"max_s": maxf(0.0, float(h.value) - float(h.elapsed_s))}
	return {"exhaust": true}


## Registra quanto è stato fatto offline sulla voce 0; se `ended` la chiude e avvia la successiva.
func offline_commit(action_id: String, cycles: float, used_s: float, ended: bool) -> void:
	if not is_running() or str(state.entries[0].action) != action_id:
		return
	var h: Dictionary = state.entries[0]
	h["done"] = int(h.done) + int(floor(cycles + 1e-6))
	h["elapsed_s"] = float(h.elapsed_s) + used_s
	if ended:
		_finish_head(false)
