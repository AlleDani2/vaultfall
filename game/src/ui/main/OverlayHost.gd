class_name OverlayHost
extends Control
## Finestre modali sopra MainScreen, in fila (una alla volta): benvenuto del primo avvio, tutorial di 3 righe al
## primo sblocco (R-UNL-2), "Bentornato" dopo l'assenza (T-4.5). Gestisce anche F1 = Manuale.
## Solo presentazione: legge QuestSystem (Game.system("quests")) e il resoconto offline.

## Sotto questa durata l'assenza non merita una finestra (solo la notifica di MainScreen).
const WELCOME_BACK_MIN_S := 60.0
const WELCOME_BACK_EMPTY_MAX_S := 600.0     # sotto questa durata, senza novità, niente finestra Bentornato
const HUMOR_TIP_COUNT := 50                 # chiavi UI_HUMOR_TIP_01…50 (localization/parts/humor.csv), come nel Riepilogo
const DIM := Color(0, 0, 0, 0.55)

var _quests: QuestSystem
var _queue: Array[Dictionary] = []
var _active: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quests = Game.system("quests") as QuestSystem
	if _quests == null:
		return
	EventBus.unlocked.connect(_on_unlocked)
	EventBus.offline_progress.connect(_on_offline)
	if _quests.intro_pending():
		_queue.append({"kind": "welcome"})
	_collect_offline()
	_collect_tutorials()
	_next.call_deferred()


## Un solo overlay alla volta: finché il menù di pausa è aperto, benvenuto/tutorial/Bentornato aspettano (nascosti) e
## tornano alla chiusura della pausa.
func _process(_delta: float) -> void:
	var paused := Feedback.is_pause_menu_open()
	if _active != null and is_instance_valid(_active):
		_active.visible = not paused
	if not paused and _active == null and not _queue.is_empty():
		_next()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if Feedback.is_pause_menu_open():
		return
	if k != null and InputBindings.pressed(k, "manual"):
		var main := get_parent()
		var sid: String = str(main.get("current_id")) if main != null and main.get("current_id") != null else ""
		var params := {} if sid.is_empty() or sid == "manual" else {"page": ManualCatalog.page_for_screen(sid)}
		EventBus.screen_requested.emit("manual", params)       # F1: la pagina della schermata in cui sei
		get_viewport().set_input_as_handled()
	elif k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and dismiss_active():
		get_viewport().set_input_as_handled()      # Esc chiude la finestra in primo piano (G23)


## Chiude la finestra aperta come se si premesse il suo pulsante principale (Vai / Ok / Raccogli). false se non c'è.
func dismiss_active() -> bool:
	if _active == null:
		return false
	for n in ["WelcomeGo", "TutorialOk", "WbCollect"]:
		var b := _active.find_child(n, true, false) as Button
		if b != null:
			b.pressed.emit()
			return true
	return false


func is_busy() -> bool:
	return _active != null or not _queue.is_empty()


func _on_unlocked(_token: String) -> void:
	_collect_tutorials()
	_next()


func _on_offline(_seconds: float, _report: Dictionary) -> void:
	_collect_offline()
	_next()


func _collect_offline() -> void:
	var off := _quests.take_offline()
	if not off.is_empty() and float(off.seconds) >= WELCOME_BACK_MIN_S:
		# una breve assenza in cui non è successo niente non merita una finestra (QA-UX A): resta il messaggio nel registro
		if float(off.seconds) < WELCOME_BACK_EMPTY_MAX_S and WelcomeBack.build(float(off.seconds), off.report, DataRegistry, Game.offline_cap_s()).empty:
			return
		_queue.append({"kind": "back", "seconds": float(off.seconds), "report": off.report})


func _collect_tutorials() -> void:
	while _quests.tutorial_pending():
		var token := _quests.take_tutorial()
		if token.is_empty():
			break
		if Settings.get_value("tutorials") and not _replaced_by_guide(token):
			_queue.append({"kind": "tutorial", "token": token})


## Il tutorial guidato (TutorialDirector) ha già un passo con evidenziazione per questo sblocco: niente doppia scheda.
func _replaced_by_guide(token: String) -> bool:
	var ts := Game.system("tutorial") as TutorialSystem
	if ts == null or not ts.active():
		return false
	if TutorialCatalog.covered_tokens().has(token):
		return true
	return token.begins_with("skill:") and not ts.is_seen("g_move2")      # durante i primi passi niente schede in mezzo


func _next() -> void:
	if _active != null or _queue.is_empty() or Feedback.is_pause_menu_open():
		return
	var job: Dictionary = _queue.pop_front()
	match str(job.kind):
		"welcome":
			_active = _welcome()
		"tutorial":
			_active = _tutorial(str(job.token))
		"back":
			_active = _back(float(job.seconds), job.report)
	if _active == null:
		_next()


func _close() -> void:
	if _active != null:
		_active.queue_free()
		_active = null
	_next.call_deferred()


# ------------------------------------------------------------------ costruzione delle finestre

## Sfondo scurito + pannello centrato; ritorna la VBox del contenuto.
func _modal(min_width: float) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	panel.custom_minimum_size.x = min_width
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	add_child(root)
	_active = root
	if not Settings.get_value("reduce_motion"):
		panel.modulate.a = 0.0
		panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)
	return v


func _text(parent: Control, text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _button(parent: Control, key: String, accent: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = key
	if accent:
		b.theme_type_variation = &"AccentButton"
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _welcome() -> Control:
	var v := _modal(560.0)
	var t := Label.new()
	t.text = "UI_QUESTS_WELCOME_TITLE"
	t.theme_type_variation = &"TitleLabel"
	v.add_child(t)
	for key in ["UI_QUESTS_WELCOME_1", "UI_QUESTS_WELCOME_2", "UI_QUESTS_WELCOME_3"]:
		_text(v, tr(key))
	var go := _button(v, "UI_QUESTS_WELCOME_GO", true, func() -> void:
		_quests.mark_intro_seen()
		_close())
	go.name = "WelcomeGo"
	go.grab_focus.call_deferred()
	return _active


func _tutorial(token: String) -> Control:
	var lines := UnlockSystem.tutorial_lines(token, DataRegistry)
	if lines.is_empty():
		return null
	var v := _modal(520.0)
	var t := _text(v, Loc.tf("UI_QUESTS_TUT_TITLE", {"name": UnlockSystem.token_name(token, DataRegistry)}), &"TitleLabel")
	t.name = "TutorialTitle"
	for l in lines:
		_text(v, l)
	var off := CheckBox.new()
	off.text = "UI_QUESTS_TUT_OFF"
	v.add_child(off)
	var ok := _button(v, "UI_QUESTS_TUT_OK", true, func() -> void:
		if off.button_pressed:
			Settings.set_value("tutorials", false)
		_close())
	ok.name = "TutorialOk"
	ok.grab_focus.call_deferred()
	return _active


func _back(seconds: float, report: Dictionary) -> Control:
	var m := WelcomeBack.build(seconds, report, DataRegistry, Game.offline_cap_s())
	var v := _modal(600.0)
	var t := Label.new()
	t.text = "UI_QUESTS_WB_TITLE"
	t.theme_type_variation = &"TitleLabel"
	v.add_child(t)
	# QA120: il resoconto di una lunga assenza ha anche 25 righe e a 720p usciva dalla finestra (titolo tagliato in alto, pulsante
	# «Raccogli» fuori schermo). Il contenuto sta in uno scorrimento che si ferma all'altezza della finestra; i pulsanti restano sotto.
	var scroll := ScrollContainer.new()
	scroll.name = "WbScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_text(body, m.away)
	if m.empty:
		_text(body, tr("UI_QUESTS_WB_NOTHING"), &"MutedLabel")
	for s in m.sections:
		if not str(s.header).is_empty():
			var h := Label.new()
			h.text = s.header
			h.theme_type_variation = &"SectionLabel"
			body.add_child(h)
		_text(body, "\n".join(s.lines))
	# una battuta a caso (le 50 UI_HUMOR_TIP_NN: prima solo il Riepilogo le mostrava); solo presentazione, nessun effetto sul gioco
	_text(body, tr("UI_HUMOR_TIP_%02d" % (randi() % HUMOR_TIP_COUNT + 1)), &"MutedLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var collect := _button(row, "UI_QUESTS_WB_COLLECT", true, _close)
	collect.name = "WbCollect"
	collect.grab_focus.call_deferred()
	if not (m.ready_quests as Array).is_empty():
		_button(row, "UI_QUESTS_WB_TO_QUESTS", false, func() -> void:
			EventBus.screen_requested.emit("quests", {})
			_close())
	if int(m.crates) > 0:
		_button(row, "UI_QUESTS_WB_TO_CRATES", false, func() -> void:
			EventBus.screen_requested.emit("vault_hall", {})
			_close())
	body.minimum_size_changed.connect(_fit_scroll.bind(scroll, body, v))
	_fit_scroll.call_deferred(scroll, body, v)
	return _active


## L'altezza dello scorrimento del Bentornato: quanto serve al contenuto, ma mai oltre la finestra (resto = titolo + pulsanti).
func _fit_scroll(scroll: ScrollContainer, body: Control, host: Control) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(body) or not is_instance_valid(host) or not scroll.is_inside_tree():
		return
	var want := body.get_combined_minimum_size().y
	var others := host.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	var room := get_viewport_rect().size.y * 0.94 - others - 28.0
	scroll.custom_minimum_size.y = clampf(want, 40.0, maxf(room, 80.0))
