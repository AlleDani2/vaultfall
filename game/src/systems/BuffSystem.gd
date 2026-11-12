class_name BuffSystem
extends GameSystem
## Effetti a tempo (pozioni, banchetti, eventi): ogni effetto registra i propri modificatori come fonte
## "buff:<id>" in Modifiers finché dura. Il tempo è quello SIMULATO (scorre anche offline).
## È anche il sistema d'esempio di riferimento per README_SISTEMI.md.
##
## Stato (GameState.data.buffs): {"active": {"potion_haste": {"remaining_s": 120.0, "mods": [{key, value, mode}]}}}

const SOURCE_PREFIX := "buff:"

var _prepaid: float = 0.0       # tempo offline già fatto scorrere da advance_offline durante l'offline corrente


func _init() -> void:
	id = "buffs"
	state_key = "buffs"


func default_state() -> Variant:
	return {"active": {}}


func from_state(section: Variant) -> void:
	state = section
	if not state.has("active") or not (state.active is Dictionary):
		state["active"] = {}
	ctx.modifiers.clear_prefix(SOURCE_PREFIX)
	for buff_id in state.active.keys():
		var b: Variant = state.active[buff_id]
		var rem: Variant = b.get("remaining_s", 0.0) if b is Dictionary else null
		if not (b is Dictionary) or not (rem is int or rem is float) or not is_finite(float(rem)) or float(rem) <= 0.0 \
				or not (b.get("mods", []) is Array):
			state.active.erase(buff_id)         # F5: effetto corrotto (durata non finita o forma sbagliata)
			continue
		ctx.modifiers.set_source(SOURCE_PREFIX + buff_id, b.get("mods", []))


## Aggiunge o rinnova un effetto: la durata diventa la maggiore tra quella residua e la nuova.
func add_buff(buff_id: String, duration_s: float, mods: Array) -> void:
	if not is_finite(duration_s) or duration_s <= 0.0:
		return
	var cur: Dictionary = state.active.get(buff_id, {})
	var rem := maxf(float(cur.get("remaining_s", 0.0)), duration_s)
	state.active[buff_id] = {"remaining_s": rem, "mods": mods.duplicate(true)}
	ctx.modifiers.set_source(SOURCE_PREFIX + buff_id, mods)


func remove_buff(buff_id: String) -> void:
	if state.active.has(buff_id):
		state.active.erase(buff_id)
		ctx.modifiers.clear_source(SOURCE_PREFIX + buff_id)


func remaining(buff_id: String) -> float:
	return float(state.active.get(buff_id, {}).get("remaining_s", 0.0))


func tick(dt: float) -> void:
	_advance(dt)


## Secondi mancanti alla scadenza del primo effetto (0 se non ce ne sono). Serve all'offline di SkillSystem per
## spezzare i segmenti quando un banchetto o una pozione a tempo finisce.
func soonest_remaining() -> float:
	var best := 0.0
	for buff_id in state.active:
		var r := float(state.active[buff_id].get("remaining_s", 0.0))
		if best <= 0.0 or r < best:
			best = r
	return best


## Fa scorrere il tempo OFFLINE già "consumato" da un sistema che lo simula a segmenti (SkillSystem). Il resto del
## tempo lo fa simulate_offline, che sottrae quanto già anticipato.
func advance_offline(dt: float) -> void:
	if dt <= 0.0:
		return
	_prepaid += dt
	_advance(dt)


## Versione analitica: un solo passo per tutto il tempo offline (meno quello già anticipato da advance_offline).
func simulate_offline(seconds: float) -> Dictionary:
	var rest := maxf(0.0, seconds - _prepaid)
	_prepaid = 0.0
	var expired := _advance(rest)
	return {"expired": expired} if not expired.is_empty() else {}


func _advance(dt: float) -> Array:
	var expired: Array = []
	if state.active.is_empty():
		return expired
	for buff_id in state.active.keys():
		var b: Dictionary = state.active[buff_id]
		b["remaining_s"] = float(b.remaining_s) - dt
		if b.remaining_s <= 1e-6:       # tolleranza sugli arrotondamenti dei passi da 0,1 s
			expired.append(buff_id)
	for buff_id in expired:
		remove_buff(buff_id)
	return expired
