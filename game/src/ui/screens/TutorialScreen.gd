extends GameScreen
## Guida (menù Progresso): checklist «Dinamiche scoperte x/N» con un pulsante «Mostrami» per ogni voce già sbloccata, che
## porta alla schermata giusta e rimette in evidenza il controllo. Qui si riaccende o si spegne il tutorial.
## Solo presentazione: stato in TutorialSystem, schede in TutorialDirector (MainScreen.tutorial()).

const ROW_SEP := 6

var _ts: TutorialSystem
var _count: Label
var _bar: ProgressBar
var _note: Label
var _auto: CheckBox
var _list: VBoxContainer
var _sig: String = ""


func _ready() -> void:
	name = "TutorialScreen"
	add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = "UI_TUT_GUIDE_TITLE"
	ScreenKit.title_style(t)
	add_child(t)
	var intro := Label.new()
	intro.text = "UI_TUT_GUIDE_INTRO"
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_count = Label.new()
	_count.name = "GuideCount"
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.theme_type_variation = &"SectionLabel"
	add_child(_count)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	add_child(_bar)
	_note = Label.new()
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_note.theme_type_variation = &"MutedLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_auto = CheckBox.new()
	_auto.name = "GuideAuto"
	_auto.text = "UI_TUT_AUTO"
	_auto.tooltip_text = "UI_TUT_AUTO_TIP"
	_auto.toggled.connect(_on_auto)
	row.add_child(_auto)
	var restart := Button.new()
	restart.name = "GuideRestart"
	restart.text = "UI_TUT_RESTART"
	restart.pressed.connect(_on_restart)
	row.add_child(restart)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", ROW_SEP)
	sc.add_child(_list)
	_ts = Game.system("tutorial") as TutorialSystem
	EventBus.locale_changed.connect(func(_l: String) -> void: _sig = "")
	_rebuild()


func open(_params: Dictionary) -> void:
	_sig = ""
	_rebuild()


func refresh() -> void:
	_rebuild()


func _director() -> TutorialDirector:
	var n: Node = self
	while n != null:
		if n.has_method("tutorial"):
			return n.call("tutorial") as TutorialDirector
		n = n.get_parent()
	return null


func _signature() -> String:
	var parts := PackedStringArray()
	for s in TutorialCatalog.STEPS:
		parts.append("%s%d%d" % [s.id, 1 if _ts.is_seen(str(s.id)) else 0, 1 if _ts.available(str(s.id)) else 0])
	return "%s|%s|%s" % ["".join(parts), str(_ts.state.off), str(Settings.get_value("tutorials"))]


func _rebuild() -> void:
	if _ts == null:
		return
	var sig := _signature()
	if sig == _sig:
		return
	_sig = sig
	var c := _ts.counts()
	_count.text = Loc.tf("UI_TUT_GUIDE_COUNT", c)
	_bar.max_value = maxf(1.0, float(c.total))
	_bar.value = float(c.seen)
	_note.visible = _ts.finished()
	_note.text = tr("UI_TUT_FINISHED")
	_auto.set_pressed_no_signal(bool(Settings.get_value("tutorials")) and not bool(_ts.state.off))
	for ch in _list.get_children():
		ch.free()
	for cat in TutorialCatalog.CATS:
		var head := Label.new()
		head.text = "UI_TUT_CAT_" + str(cat).to_upper()
		head.theme_type_variation = &"SectionLabel"
		_list.add_child(head)
		for s in TutorialCatalog.STEPS:
			if str(s.cat) == cat:
				_add_row(s)


func _add_row(s: Dictionary) -> void:
	var sid := str(s.id)
	var seen := _ts.is_seen(sid)
	var avail := _ts.available(sid)
	var h := HBoxContainer.new()
	h.name = "Row_" + sid
	h.add_theme_constant_override("separation", 10)
	_list.add_child(h)
	var st := Label.new()
	st.custom_minimum_size.x = 96
	st.text = "UI_TUT_STATE_SEEN" if seen else ("UI_TUT_STATE_NEW" if avail else "UI_TUT_STATE_LOCKED")
	if not seen:
		st.theme_type_variation = &"MutedLabel"
	h.add_child(st)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text = tr(TutorialCatalog.title_key(sid))
	mid.add_child(title)
	if not avail:
		var why := Label.new()
		why.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		why.theme_type_variation = &"MutedLabel"
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var hint := UnlockSystem.hint_for(str(s.get("token", "")), DataRegistry) if not str(s.get("token", "")).is_empty() else ""
		why.text = tr(hint) if not hint.is_empty() else tr("UI_TUT_UNLOCK_GENERIC")
		mid.add_child(why)
	var b := Button.new()
	b.name = "Show_" + sid
	b.text = "UI_TUT_SHOW"
	b.disabled = not avail
	b.pressed.connect(_on_show.bind(sid))
	h.add_child(b)


func _on_show(sid: String) -> void:
	var d := _director()
	if d == null:
		return
	var s := TutorialCatalog.get_step(sid)
	var scr := str(s.get("screen", ""))
	if not scr.is_empty():
		EventBus.screen_requested.emit(scr, {})
	d.show_step(sid)


func _on_auto(on: bool) -> void:
	Settings.set_value("tutorials", on)
	if _ts != null:
		_ts.set_off(not on)
	_sig = ""
	_rebuild()


func _on_restart() -> void:
	var d := _director()
	if d != null:
		d.restart()
	_sig = ""
	_rebuild()
