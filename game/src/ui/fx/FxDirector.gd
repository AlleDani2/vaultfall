class_name FxDirector
extends Node
## Regista degli effetti globali: ascolta EventBus e mette in scena level up, missioni, imprese, nuovi sblocchi,
## famigli, vendite (monete verso l'oro), Casse trovate. Vive dentro MainScreen (muore con lei) e conosce i bersagli
## del menù (oro, Deposito, voci del menù) registrandoli come ancoraggi di Fx. Solo presentazione: non decide nulla.
## Tutto passa da Fx, quindi rispetta «riduci animazioni» e «Effetti: ridotti» e i limiti dei pool.

const MIN_GAP_MS := 150           # tra due level up consecutivi (l'offline ne può emettere decine)

var _main: Control
var _last_level_ms: int = -1000000
var _last_sell_ms: int = -1000000


func _init(main: Control = null) -> void:
	_main = main
	name = "FxDirector"


func _ready() -> void:
	Fx.ensure()
	Fx.enable_button_feedback(true)
	EventBus.level_up.connect(_on_level_up)
	EventBus.quest_completed.connect(_on_quest_completed)
	EventBus.achievement_unlocked.connect(_on_achievement)
	EventBus.unlocked.connect(_on_unlocked)
	EventBus.pet_found.connect(_on_pet)
	EventBus.crate_found.connect(_on_crate_found)
	EventBus.item_sold.connect(_on_item_sold)
	EventBus.order_completed.connect(_on_order_completed)
	EventBus.expedition_finished.connect(_on_expedition_finished)
	_register_anchors()


## (Ri)registra i bersagli noti: il menù si ricostruisce a ogni sblocco, quindi si rifà prima di ogni uso.
func _register_anchors() -> void:
	if _main == null or not is_instance_valid(_main):
		return
	var gold := _main.get_node_or_null("%GoldIcon") as Control
	if gold != null:
		Fx.register_anchor("gold", gold)
	var act := _main.get_node_or_null("%ActivityBar") as Control
	if act != null:
		Fx.register_anchor("activity", act)
	var btns: Variant = _main.get("_buttons")
	if btns is Dictionary:
		for id in btns:
			if is_instance_valid(btns[id]):
				Fx.register_anchor(str(id), btns[id])


func _screen_center() -> Vector2:
	var cur: Variant = _main.get("_current") if _main != null else null
	if cur is Control and is_instance_valid(cur) and (cur as Control).is_inside_tree():
		return Fx.center_of(cur as Control)
	return Vector2(640, 360)


func _on_level_up(skill: String, level: int) -> void:
	if not Fx.enabled() or not GameState.active:
		return
	var now := Time.get_ticks_msec()
	if now - _last_level_ms < MIN_GAP_MS:
		return
	_last_level_ms = now
	_register_anchors()
	var at := Fx.anchor_pos("skill:" + skill, Fx.anchor_pos("activity"))
	Fx.ring(at, FxPalette.GOLD, 70.0, 0.6, FxPalette.WHITE, 1)
	Fx.burst("star", at, [], 0.9, 1.0, Vector2.ZERO, 1)
	Fx.number(at + Vector2(112, 0), Loc.tf("UI_FX_LEVEL_UP", {"n": level}), FxPalette.GOLD, Fx.NUM_L, 38.0, 1.1, 1)    # «Livello N» che sale
	var btn := Fx.anchor_node("skill:" + skill)
	if btn != null:
		Fx.glow_pulse(btn, FxPalette.GOLD, 3, 0.9, 0.7)
		Fx.shine(btn, FxPalette.WHITE, 0.6, 0.6)


func _on_quest_completed(quest_id: String) -> void:
	if not GameState.active:
		return
	var q := DataRegistry.get_def("quests", quest_id)
	var title := Loc.t(q.get("title", {})) if not q.is_empty() else ""
	Fx.banner(tr("UI_FX_QUEST_DONE"), title, FxPalette.GOLD, null)


func _on_achievement(id: String) -> void:
	if not GameState.active:
		return
	var a := DataRegistry.get_def("achievements", id)
	if a.is_empty():
		return
	Fx.banner(tr("UI_FX_ACHIEVEMENT"), Loc.t(a.get("name", {})), FxPalette.VIOLET, IconLib.icon("achievements", id))


## Nuovo sblocco di sistema: solo i token che aprono una voce del menù ("feature:…").
func _on_unlocked(token: String) -> void:
	if not GameState.active or not token.begins_with("feature:"):
		return
	for e in ScreenRegistry.entries():
		if str(e.get("unlock", "")) == token and str(e.get("scene", "")) != "":
			var title := str(e.get("title_text", "")) if e.has("title_text") else tr(str(e.title))
			Fx.banner(tr("UI_FX_UNLOCK"), title, FxPalette.BLUE, null)
			_register_anchors()
			var btn := Fx.anchor_node(str(e.id))
			if btn != null:
				Fx.glow_pulse(btn, FxPalette.BLUE, 3, 1.0, 0.7)
			return


func _on_pet(pet_id: String) -> void:
	if not GameState.active:
		return
	var p := DataRegistry.get_def("pets", pet_id)
	Fx.banner(tr("UI_FX_PET"), Loc.t(p.get("name", {})) if not p.is_empty() else "", FxPalette.GREEN, IconLib.portrait("pets", pet_id))


func _on_crate_found(_crate_id: String, _source: String) -> void:
	if not Fx.enabled() or not GameState.active:
		return
	_register_anchors()
	var btn := Fx.anchor_node("vault_hall")
	if btn != null:
		Fx.glow_pulse(btn, FxPalette.VIOLET, 2, 0.8, 0.7)
		Fx.burst("glint", Fx.center_of(btn), [FxPalette.VIOLET, FxPalette.WHITE], 0.8, 1.0, Vector2(40, 10))


func _on_item_sold(_def_id: String, _qty: int, gold: int) -> void:
	if gold <= 0 or not Fx.enabled() or not GameState.active:
		return
	var now := Time.get_ticks_msec()
	if now - _last_sell_ms < 250:
		return
	_last_sell_ms = now
	_register_anchors()
	Fx.coins(_screen_center(), Fx.anchor_pos("gold"), 4 if gold < 1000 else 7, Fx.anchor_node("gold"))


func _on_order_completed(_order_id: String) -> void:
	if not Fx.enabled() or not GameState.active:
		return
	_register_anchors()
	Fx.coins(_screen_center(), Fx.anchor_pos("gold"), 6, Fx.anchor_node("gold"))


## Spedizione della Gilda conclusa: monete verso l'oro e un luccichio sulla voce Gilda del menù.
func _on_expedition_finished(_id: String, _result: Dictionary) -> void:
	if not Fx.enabled() or not GameState.active:
		return
	_register_anchors()
	var guild := Fx.anchor_node("guild")
	var from := Fx.center_of(guild) if guild != null else _screen_center()
	Fx.coins(from, Fx.anchor_pos("gold"), 5, Fx.anchor_node("gold"))
	if guild != null:
		Fx.glow_pulse(guild, FxPalette.GOLD, 2, 0.8, 0.6)


func _exit_tree() -> void:
	Fx.clear_all()
