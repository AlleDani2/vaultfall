class_name FeedbackPanel
extends VBoxContainer
## Blocco «Assistenza» delle Impostazioni: versione, Novità, Segnala un problema e statistiche locali (opt-in).
## Solo presentazione: le azioni stanno in Feedback / ReportBuilder / SessionStats.

var in_menu: bool = false

var _stats_summary: Label
var _stats_id: Label
var _status: Label
var _confirm: ConfirmationDialog


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_label("UI_FB_SECTION", &"SectionLabel")
	var ver := Label.new()
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.theme_type_variation = &"MutedLabel"
	ver.text = Loc.tf("UI_FB_VERSION", {"v": AppInfo.version_label(), "build": AppInfo.build()})
	add_child(ver)
	_label("UI_FB_SUPPORT_NOTE", &"MutedLabel")
	var row := HBoxContainer.new()
	add_child(row)
	var news := Button.new()
	news.text = "UI_FB_NEWS_TITLE"
	news.pressed.connect(_on_news)
	row.add_child(news)
	var cred := Button.new()
	cred.text = "UI_CRED_BUTTON"
	cred.pressed.connect(func() -> void: CreditsView.show_dialog(self))
	row.add_child(cred)
	var rep := Button.new()
	rep.text = "UI_FB_REPORT_BUTTON"
	rep.theme_type_variation = &"AccentButton"
	rep.tooltip_text = "UI_FB_REPORT_HINT"
	rep.pressed.connect(func() -> void: ReportDialog.show_for(self))
	row.add_child(rep)

	_label("UI_FB_STATS_TITLE", &"SectionLabel")
	_label("UI_FB_STATS_EXPLAIN", &"MutedLabel")
	var cb := CheckBox.new()
	cb.text = "UI_FB_STATS_OPTIN"
	cb.button_pressed = bool(Settings.get_value("stats_opt_in"))
	cb.toggled.connect(_on_optin)
	add_child(cb)
	_stats_id = Label.new()
	_stats_id.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stats_id.theme_type_variation = &"MonoLabel"
	add_child(_stats_id)
	_stats_summary = Label.new()
	_stats_summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stats_summary.theme_type_variation = &"MutedLabel"
	add_child(_stats_summary)
	var row2 := HBoxContainer.new()
	add_child(row2)
	var export_btn := Button.new()
	export_btn.text = "UI_FB_STATS_EXPORT"
	export_btn.pressed.connect(_on_export)
	row2.add_child(export_btn)
	var clr := Button.new()
	clr.text = "UI_FB_STATS_CLEAR"
	clr.pressed.connect(func() -> void: _confirm.popup_centered(Vector2i(480, 160)))
	row2.add_child(clr)
	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_confirm = ConfirmationDialog.new()
	DialogKit.style_confirm(_confirm)
	_confirm.dialog_text = tr("UI_FB_STATS_CLEAR_CONFIRM")
	_confirm.confirmed.connect(_on_clear)
	add_child(_confirm)
	_refresh()


func _label(key: String, variation: StringName) -> void:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)


func _refresh() -> void:
	var s: SessionStats = Feedback.stats
	_stats_id.visible = not s.install_id().is_empty()
	_stats_id.text = Loc.tf("UI_FB_STATS_ID", {"id": s.install_id()})
	if s.has_data():
		var sm := s.summary()
		_stats_summary.text = Loc.tf("UI_FB_STATS_SUMMARY", {"sessions": sm.sessions, "time": NumberFormat.fmt_time(float(sm.active_s))})
	else:
		_stats_summary.text = tr("UI_FB_STATS_EMPTY")


func _on_news() -> void:
	if in_menu or Feedback.current_screen().is_empty():
		NewsView.show_dialog(self)
	else:
		EventBus.screen_requested.emit("news", {})


func _on_optin(on: bool) -> void:
	Settings.set_value("stats_opt_in", on)
	_refresh()


func _on_export() -> void:
	var res := Feedback.export_stats()
	if res.ok:
		_status.text = Loc.tf("UI_FB_STATS_EXPORTED", {"dir": ReportBuilder.scrub(str(res.dir))})
		OS.shell_open(ProjectSettings.globalize_path(str(res.dir)))
	else:
		_status.text = tr("UI_FB_STATS_EXPORT_FAILED")


func _on_clear() -> void:
	Feedback.stats.clear_all()
	_status.text = tr("UI_FB_STATS_CLEARED")
	_refresh()
