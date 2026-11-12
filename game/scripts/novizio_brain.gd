extends "res://scripts/bot_player.gd"
## Cervello del bot NOVIZIO (QA 95): riusa la pianificazione di BotPlayer (che cosa serve per la missione: quale
## mansione, quale zona, quali ingredienti) ma NON esegue nulla: i compiti scelti vengono restituiti alla UI,
## che li esegue premendo pulsanti. Le azioni «dirette» di BotPlayer (riscatto, apertura casse, equipaggiamento,
## pulizia del Deposito...) sono spente: le fa il bot con i clic.

var ui_task: Dictionary = {}


func _claim_ready() -> void:
	pass


func _open_crates() -> void:
	pass


func _equip_best() -> void:
	pass


func _tidy_bank() -> void:
	pass


func _eat_if_needed() -> void:
	pass


func _harvest_ready() -> void:
	pass


func _side_activities() -> void:
	pass


func _apply(task: Dictionary) -> void:
	ui_task = task


func decide_now(play_s: float) -> Dictionary:
	t = play_s
	ui_task = {}
	_decide()
	return ui_task


func _plan_equip(item: String) -> Dictionary:
	if not _has("feature:combat"):
		return {}
	for inst in _bank().state.instances:
		if str(inst.def) == item:
			if _combat().is_equipped(str(inst.uid)):
				return {"kind": "none"}
			return {"kind": "ui_equip", "item": item, "uid": str(inst.uid)}
	return _plan_produce(item, 1, 0)


func _plan_sell(gold_left: int) -> Dictionary:
	if not _has("feature:market"):
		return {}
	return {"kind": "ui_sell", "gold": gold_left}


func _task_for(qid: String, idx: int, obj: Dictionary, left: int) -> Dictionary:
	var type := str(obj.get("type", ""))
	if type == "talk":
		return {"kind": "ui_talk", "npc": str(obj.get("npc", ""))}
	if type == "deliver":
		if _bank().count(str(obj.item)) > 0:
			return {"kind": "ui_deliver", "qid": qid, "idx": idx}
	return super._task_for(qid, idx, obj, left)
