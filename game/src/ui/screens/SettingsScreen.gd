extends GameScreen
## Impostazioni (docs/16 §7, R-SAV-4; 1.0 a schede): Gioco · Schermo · Audio · Accessibilità · Comandi · Salvataggi e dati.
## Usata come schermata di MainScreen e come pannello del menù iniziale (in_menu = true: pulsante Indietro).
## Ogni controllo scrive in Settings: niente logica qui. LB/RB (o Ctrl+Tab) cambiano scheda; tutte le schede sono navigabili col controller.

signal closed

const TAB_KEYS: Array[String] = ["UI_I10_TAB_GAME", "UI_I10_TAB_SCREEN", "UI_I10_TAB_AUDIO", "UI_I10_TAB_A11Y", "UI_I10_TAB_CONTROLS",
	"UI_I10_TAB_DATA"]

static var last_tab: int = 0               # la scheda aperta l'ultima volta (anche dopo il cambio lingua)

var in_menu: bool = false
var tabs: TabContainer
var display_panel: DisplayPanel
var controls_panel: ControlsPanel
var accessibility_panel: AccessibilityPanel

var _box: VBoxContainer                    # la colonna della scheda in costruzione (le funzioni di riga scrivono qui)
var _import_text: TextEdit
var _import_slot: OptionButton


func open(params: Dictionary) -> void:
	in_menu = bool(params.get("in_menu", in_menu))
	_build()
	if Settings.runtime != null and Settings.runtime.device == "gamepad":
		focus_tabs.call_deferred()


func _ready() -> void:
	EventBus.locale_changed.connect(_on_locale_changed)
	if tabs == null:
		_build()


## Cambio lingua: i testi composti con tr()/Loc nel costruttore (note, statistiche, scorciatoie) restavano nella lingua
## di prima (QA 95). Ricostruzione differita: la tendina della lingua è dentro la pagina e sta ancora emettendo il segnale.
func _on_locale_changed(_l: String) -> void:
	_build.call_deferred()


## Porta il fuoco sulle schede (col controller: da lì si scende ai controlli).
func focus_tabs() -> void:
	if tabs != null and is_instance_valid(tabs):
		tabs.get_tab_bar().grab_focus()


func _build() -> void:
	if tabs != null and is_instance_valid(tabs):
		last_tab = tabs.current_tab
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	if in_menu:
		var back := Button.new()
		back.name = "BackButton"
		back.text = "UI_BACK"
		back.custom_minimum_size = Vector2(120, 40)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.pressed.connect(func() -> void: closed.emit())
		head.add_child(back)
	var title := Label.new()
	title.text = "UI_MENU_SETTINGS"
	ScreenKit.title_style(title)
	head.add_child(title)
	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	_page("UI_I10_TAB_GAME")
	_tab_game()
	_page("UI_I10_TAB_SCREEN")
	display_panel = DisplayPanel.new()
	_box.add_child(display_panel)
	_page("UI_I10_TAB_AUDIO")
	_tab_audio()
	_page("UI_I10_TAB_A11Y")
	accessibility_panel = AccessibilityPanel.new()
	_box.add_child(accessibility_panel)
	_page("UI_I10_TAB_CONTROLS")
	controls_panel = ControlsPanel.new()
	_box.add_child(controls_panel)
	_page("UI_I10_TAB_DATA")
	_tab_data()
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, tr(TAB_KEYS[i]))
	tabs.current_tab = clampi(last_tab, 0, tabs.get_tab_count() - 1)
	tabs.tab_changed.connect(func(i: int) -> void: last_tab = i)


## Aggiunge una pagina (scorrevole) alle schede e ne fa la colonna corrente (_box).
func _page(name_key: String) -> void:
	var p := SettingsKit.tab_page(name_key)
	tabs.add_child(p[0])
	_box = p[1]


# ------------------------------------------------------------------ schede

func _tab_game() -> void:
	_label("UI_SETTINGS_GAME", &"SectionLabel")
	_option("UI_LANGUAGE", ["UI_LANG_IT", "UI_LANG_EN"], ["it", "en"], "locale")
	_option("UI_NUMBER_FORMAT", ["UI_NUMBERS_SHORT", "UI_NUMBERS_FULL", "UI_NUMBERS_SCIENTIFIC"],
		["short", "full", "scientific"], "number_format")
	_option("UI_BANKG_SET_VIEW", ["UI_BANKG_VIEW_GRID", "UI_BANKG_VIEW_LIST"], ["grid", "list"], "bank_view")      # F16
	if OS.is_debug_build():
		_option("UI_SPEED", ["×1", "×10", "×100"], [1.0, 10.0, 100.0], "game_speed")
	_push_section()
	var extras := SettingsExtras.new()
	extras.shortcuts = false
	_box.add_child(extras)        # UI-B: colonna destra, tutorial, Modalità Cozy (le scorciatoie sono nella scheda Comandi)

	# Notifiche per categoria, registro di combattimento e conferma di chiusura (UI-A G19, G20, G21)
	_label("UI_UIA_SET_NOTIFY", &"SectionLabel")
	var note := Label.new()
	note.text = "UI_UIA_SET_NOTIFY_HELP"
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(note)
	for cat in NoticeFilter.CATEGORIES:
		var ncb := _check("UI_UIA_NOTIFY_" + str(cat).to_upper(), NoticeFilter.key_of(cat))
		ncb.get_parent().add_child(LogView.chip(LogCategory.of_notify_category(str(cat)), true))      # stesso colore e sigla del Registro
	_check("UI_UIA_SET_COMBAT_LOG", "combat_log")
	_check("UI_UIA_SET_CONFIRM_QUIT", "confirm_quit")
	if GameState.active and not in_menu:
		var seasonal := Game.system("seasonal") as SeasonalEventSystem
		if seasonal != null:        # eventi stagionali (T-11.3): l'interruttore vive nel salvataggio della partita in corso
			var ecb := SettingsKit.check_row(_box, "UI_EVENTS_SETTING", "UI_EVENTS_SETTING_HINT")
			ecb.button_pressed = seasonal.events_enabled()
			ecb.toggled.connect(func(on: bool) -> void: seasonal.set_events_enabled(on))


func _tab_audio() -> void:
	_label("UI_SETTINGS_AUDIO", &"SectionLabel")
	for k in ["volume_master", "volume_music", "volume_sfx", "volume_ui", "volume_reel"]:
		_slider("UI_" + k.to_upper(), k, 0.0, 1.0, 0.05)
	_check("UI_AUDIO_MUTE_MINIMIZED", "mute_in_background")


func _tab_data() -> void:
	var fb := FeedbackPanel.new()           # versione, Novità, «Segnala un problema», statistiche locali (opt-in)
	fb.in_menu = in_menu
	_box.add_child(fb)
	if GameState.active and not in_menu:
		_label("UI_SAVE_SLOTS", &"SectionLabel")
		var row := HBoxContainer.new()
		var exp_btn := Button.new()
		exp_btn.text = "UI_EXPORT_SAVE"
		exp_btn.pressed.connect(_on_export)
		row.add_child(exp_btn)
		_box.add_child(row)
		_import_text = TextEdit.new()
		_import_text.placeholder_text = tr("UI_IMPORT_PASTE")
		_import_text.custom_minimum_size = Vector2(0, 80)
		_import_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_box.add_child(_import_text)
		var row2 := HBoxContainer.new()
		var l := Label.new()
		l.text = "UI_IMPORT_TARGET_SLOT"
		row2.add_child(l)
		_import_slot = OptionButton.new()
		_import_slot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		for s in range(1, SaveService.SLOTS + 1):
			if s == GameState.slot:
				continue        # lo slot della partita in corso verrebbe sovrascritto dal prossimo salvataggio
			_import_slot.add_item(Loc.tf("UI_SLOT_N", {"n": s}), s)
		row2.add_child(_import_slot)
		var imp_btn := Button.new()
		imp_btn.text = "UI_IMPORT_SAVE"
		imp_btn.pressed.connect(_on_import)
		row2.add_child(imp_btn)
		_box.add_child(row2)
		var row3 := HBoxContainer.new()
		var menu_btn := Button.new()
		menu_btn.text = "UI_MAIN_MENU"
		menu_btn.pressed.connect(func() -> void: Game.stop_game())
		row3.add_child(menu_btn)
		var quit_btn := Button.new()
		quit_btn.text = "UI_QUIT"
		quit_btn.pressed.connect(SaveService.quit_game)
		row3.add_child(quit_btn)
		_box.add_child(row3)


## Sezione «Sabbia del Custode» (F14, docs/ui_redesign/03 §7.4): pulsante, Clic assistito (tieni premuto / interruttore /
## automatico) con la sua cadenza, «+N s» e suono. Ogni controllo scrive solo in Settings.
func _push_section() -> void:
	_label("UI_PUSH_SAND", &"SectionLabel")
	var note := Label.new()
	note.text = "UI_PUSH_SET_HELP"
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(note)
	_check("UI_PUSH_SET_ENABLED", "push_enabled")
	_option("UI_PUSH_ASSIST", ["UI_PUSH_ASSIST_OFF", "UI_PUSH_ASSIST_HOLD", "UI_PUSH_ASSIST_TOGGLE", "UI_PUSH_ASSIST_AUTO"],
		Array(Settings.PUSH_ASSIST_MODES), "push_assist")
	var r: Array = Settings.RANGES["push_assist_rate"]
	var s := HSlider.new()
	s.name = "PushAssistRate"
	s.min_value = float(r[0])
	s.max_value = float(r[1])
	s.step = 1.0
	s.custom_minimum_size = Vector2(220, 0)
	s.value = float(Settings.get_value("push_assist_rate"))
	var val := Label.new()
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.theme_type_variation = &"MonoLabel"
	val.custom_minimum_size = Vector2(80, 0)
	val.text = Loc.tf("UI_PUSH_RATE_VALUE", {"n": int(s.value)})
	s.value_changed.connect(func(v: float) -> void:
		val.text = Loc.tf("UI_PUSH_RATE_VALUE", {"n": int(v)})
		Settings.set_value("push_assist_rate", int(v)))
	var row := _row("UI_PUSH_ASSIST_RATE")
	row.add_theme_constant_override("separation", 10)
	row.add_child(s)
	row.add_child(val)
	_check("UI_PUSH_SET_FLOATERS", "push_floaters")
	_check("UI_PUSH_SET_SOUND", "push_sound")


# ------------------------------------------------------------------ controller: LB/RB cambiano scheda

func _unhandled_input(event: InputEvent) -> void:
	var j := event as InputEventJoypadButton
	if j == null or not j.pressed or tabs == null or not is_visible_in_tree():
		return
	if InputBindings.matches(j, "pad_tab_prev"):
		switch_tab(-1)
		get_viewport().set_input_as_handled()
	elif InputBindings.matches(j, "pad_tab_next"):
		switch_tab(1)
		get_viewport().set_input_as_handled()


## Passa alla scheda accanto (in giro). Pubblica: la usano anche i test.
func switch_tab(step: int) -> void:
	tabs.current_tab = posmod(tabs.current_tab + step, tabs.get_tab_count())
	last_tab = tabs.current_tab


# ------------------------------------------------------------------ costruttori di riga (scrivono in _box)

func _label(key: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _row(key: String) -> HBoxContainer:
	return SettingsKit.row(_box, key)


func _option(key: String, labels: Array, values: Array, setting: String) -> OptionButton:
	return SettingsKit.option(_box, key, labels, values, setting)


func _check(key: String, setting: String) -> CheckBox:
	return SettingsKit.check(_box, key, setting)


func _slider(key: String, setting: String, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(220, 0)
	s.value = float(Settings.get_value(setting))
	var val := Label.new()
	val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	val.theme_type_variation = &"MonoLabel"
	val.custom_minimum_size = Vector2(56, 0)
	val.text = "%d%%" % int(round(s.value * 100.0))
	s.value_changed.connect(func(v: float) -> void:
		val.text = "%d%%" % int(round(v * 100.0))
		Settings.set_value(setting, v))
	var row := _row(key)
	row.add_theme_constant_override("separation", 10)
	row.add_child(s)
	row.add_child(val)
	return s


func _on_export() -> void:
	DisplayServer.clipboard_set(SaveService.export_current())
	EventBus.notice.emit("info", tr("UI_COPIED"), {})


func _on_import() -> void:
	# Messaggio per codice d'errore e conferma se lo slot e' occupato: li gestisce SaveService.
	SaveService.import_with_confirm(_import_text.text, _import_slot.get_selected_id(), func(res: Dictionary) -> void:
		if res.ok:
			_import_text.text = "")
