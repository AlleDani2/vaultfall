class_name GoalPanel
extends HBoxContainer
## «Obiettivo attuale» in forma di STRISCIA di una riga (F3 del progetto di interfaccia, docs/ui_redesign/06 §3.4, D10):
## «◎ titolo · testo breve (ellissi) · barra · n/N · [Vai: …]». Mostra la prossima missione principale (o quella da riscattare);
## il tooltip del testo porta il «Come» completo. Solo presentazione: tutta la logica di testo e bersagli vive in QuestGuide.
## Il testo si ricalcola a 1 Hz, la barra a ogni refresh (≤ 10 Hz).
##
## `visible` dice solo «c'è un obiettivo»: il contenitore (RightRail, «GoalStrip») decide se la striscia si vede nella
## schermata corrente (nascosta in Riepilogo e Missioni, dove l'obiettivo è già nel contenuto).
## Il passo «Da scoprire» non sta più qui (resta nella Guida): `goal().discover` è ancora calcolato da QuestGuide.

const TEXT_EVERY := 10                # refresh tra un ricalcolo del testo e l'altro (10 Hz -> 1 Hz)
const STRIP_H := 28.0                 # altezza della striscia
const BAR_W := 90.0

var _text: Label
var _bar: ProgressBar
var _num: Label
var _go: Button
var _goal: Dictionary = {}
var _n: int = TEXT_EVERY
var _sig: String = ""


func _init() -> void:
	name = "GoalPanel"
	add_theme_constant_override("separation", 8)
	custom_minimum_size.y = STRIP_H
	_text = Label.new()
	_text.name = "GoalText"
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text.custom_minimum_size.x = 60
	_text.clip_text = true
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text.mouse_filter = Control.MOUSE_FILTER_PASS         # serve al tooltip con il «Come» completo
	add_child(_text)
	_bar = ProgressBar.new()
	_bar.name = "GoalBar"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(BAR_W, 8)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_bar)
	_num = Label.new()
	_num.name = "GoalNum"
	_num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_num.theme_type_variation = &"MonoLabel"
	_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_num)
	_go = Button.new()
	_go.name = "GoButton"
	_go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_go.theme_type_variation = &"AccentButton"
	_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_go.custom_minimum_size = Vector2(64, STRIP_H - 4.0)
	_go.add_theme_font_size_override("font_size", 14)
	_compact_button_style(_go)
	_go.pressed.connect(_on_go)
	TutorialTargets.mark(_go, "goal_go")                 # il tutorial guidato può evidenziarlo
	add_child(_go)
	visible = false


## Il pulsante «Vai» sta in una riga da 28 px: bordo e riempimento piatti, margini stretti (il telaio del tema è più alto).
static func _compact_button_style(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#4a3a18") if st != "hover" else Color("#5d4a1f")
		sb.border_color = Color("#c9a24a")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		if st == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color("#f0d9a0")
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(st, sb)


func goal() -> Dictionary:
	return _goal


## Aggiorna la striscia. `force` ricalcola subito il testo (test, cambio lingua).
func refresh(force: bool = false) -> void:
	var quests := Game.system("quests") as QuestSystem
	if quests == null or not GameState.active:
		visible = false
		return
	_n += 1
	var sig := "%s|%d" % [Loc.locale(), (GameState.data.get("unlocks", []) as Array).size()]
	if force or _n >= TEXT_EVERY or sig != _sig:
		_n = 0
		_sig = sig
		_goal = QuestGuide.current_goal(quests)
		_apply_text()
	_apply_progress(quests)


func _apply_text() -> void:
	var g := _goal
	var kind := str(g.kind)
	visible = kind != "none"
	var is_quest := kind == "quest"
	_bar.visible = is_quest
	_num.visible = is_quest
	_go.visible = is_quest or kind == "claim"
	match kind:
		"quest", "claim":
			var line := "◎ " + str(g.title)
			var obj := str(g.obj_text)
			if is_quest and not obj.is_empty():
				line += " · " + obj
			_text.text = line
			_text.tooltip_text = Loc.tf("UI_RAIL_GOAL_TIP", {"how": str(g.how)}) if not str(g.how).is_empty() else ""
			var t: Dictionary = g.target
			_go.text = tr("UI_QUESTS_CLAIM") if kind == "claim" else (QuestGuide.go_label(t) if not t.is_empty() else tr("UI_UXA_NOW_OPEN_QUESTS"))
			_go.tooltip_text = str(g.get("why", ""))
		"end":
			_text.text = "◎ " + tr("UI_QUESTS_STORY_END")
			_text.tooltip_text = ""


func _apply_progress(quests: QuestSystem) -> void:
	if str(_goal.get("kind", "")) != "quest":
		return
	var qid := str(_goal.qid)
	var d := quests.quest_def(qid)
	var objs: Array = d.get("objectives", [])
	var pr := quests.progress_of(qid)
	for i in objs.size():
		var tg := QuestSystem.target_of(objs[i])
		var cur := int(pr[i]) if i < pr.size() else 0
		if cur < tg:
			_bar.max_value = maxf(1.0, float(tg))
			_bar.value = float(cur)
			_num.text = "%s/%s" % [NumberFormat.fmt(cur), NumberFormat.fmt(tg)]
			return


func _on_go() -> void:
	var t: Dictionary = _goal.get("target", {})
	if str(_goal.get("kind", "")) == "quest" and not t.is_empty():
		ReqLink.go(t)
	elif str(_goal.get("kind", "")) == "claim" and Game.system("quests") != null and (Game.system("quests") as QuestSystem).claim(str(_goal.qid)):
		refresh(true)             # playtest novizio 121: il pulsante «Riscatta» ritira DAVVERO la ricompensa (prima apriva solo Missioni)
	else:
		EventBus.screen_requested.emit("quests", {"quest": str(_goal.get("qid", ""))})
