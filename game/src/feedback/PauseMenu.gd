class_name PauseMenu
extends CanvasLayer
## Menù di pausa (tasto Esc nella schermata principale): Riprendi · Salva adesso · Impostazioni · Manuale ·
## Segnala un problema · Menù principale · Esci dal gioco. Il focus parte su «Riprendi» (si usa anche da tastiera o controller).
## L'orologio di gioco resta fermo finché è aperto (lo gestisce Feedback.toggle_pause_menu / close_pause_menu);
## Esc lo chiude (lo gestisce MainScreen). «Menù principale» ed «Esci» salvano prima di chiudere.

var _report_btn: Button
var _status: Label


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(340, 0)
	panel.add_child(v)
	var t := Label.new()
	t.text = "UI_FB_PAUSE_TITLE"
	t.theme_type_variation = &"TitleLabel"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := _button(v, "UI_FB_PAUSE_RESUME", Feedback.close_pause_menu, "ResumeButton")
	resume.theme_type_variation = &"AccentButton"
	_button(v, "UI_M10_PAUSE_SAVE", _save, "SaveButton")
	_button(v, "UI_MENU_SETTINGS", _go.bind("settings"), "SettingsButton")
	_button(v, "UI_M10_PAUSE_MANUAL", _go.bind("manual"), "ManualButton")
	_report_btn = _button(v, "UI_FB_REPORT_BUTTON", _report, "ReportButton")
	v.add_child(HSeparator.new())
	for b in [_button(v, "UI_MAIN_MENU", _to_main_menu, "MainMenuButton"), _button(v, "UI_M10_PAUSE_QUIT", _quit, "QuitButton")]:
		b.add_theme_color_override("font_color", UiKit.DANGER.lightened(0.45))      # le azioni che escono dalla partita: rosso spento
	_status = Label.new()
	_status.name = "Status"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.theme_type_variation = &"MutedLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = Loc.tf("UI_M10_VERSION", {"v": AppInfo.version()})
	v.add_child(_status)
	resume.grab_focus.call_deferred()


func _button(parent: Control, key: String, action: Callable, node_name: String = "") -> Button:
	var b := Button.new()
	b.text = key
	if not node_name.is_empty():
		b.name = node_name
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _go(screen_id: String) -> void:
	Feedback.close_pause_menu()
	EventBus.screen_requested.emit(screen_id, {})


func _save() -> void:
	_status.text = tr("UI_M10_PAUSE_SAVED") if SaveService.save_now() else tr("UI_SAVE_FAILED") + " " + tr("UI_QA120_SAVE_FAILED_HINT")


func _report() -> void:
	ReportDialog.show_for(self)


func _to_main_menu() -> void:
	Feedback.close_pause_menu()
	Game.stop_game()


func _quit() -> void:
	Feedback.close_pause_menu()
	SaveService.request_quit()
