class_name DisplayPanel
extends VBoxContainer
## Scheda «Schermo» delle Impostazioni (1.0): modalità (finestra / senza bordi / schermo intero), risoluzione, monitor, VSync,
## limite di fotogrammi e dimensione dell'interfaccia. Ogni scelta si applica subito e resta salvata. Modalità, risoluzione e
## monitor chiedono «Mantieni queste impostazioni?» (10 s) e tornano indietro da sole se non si conferma.
## Il tetto del 125% sulla scala automatica resta (UiScale.SIZE_CHOICES).

var mode_opt: OptionButton
var res_opt: OptionButton
var monitor_opt: OptionButton
var vsync_opt: OptionButton
var fps_opt: OptionButton
var size_opt: OptionButton
var keep_dialog: KeepDisplayDialog
var _syncing := false
var _res_values: Array[Vector2i] = []


func _ready() -> void:
	name = "DisplayPanel"
	add_theme_constant_override("separation", 10)
	SettingsKit.section(self, "UI_I10_SCR_TITLE")
	mode_opt = _option("UI_I10_SCR_MODE", ["UI_I10_SCR_MODE_WINDOWED", "UI_I10_SCR_MODE_BORDERLESS", "UI_I10_SCR_MODE_FULLSCREEN"],
		Array(DisplayOptions.MODES), "window_mode")
	mode_opt.name = "ModeOption"
	mode_opt.tooltip_text = "UI_I10_SCR_MODE_TIP"
	res_opt = OptionButton.new()
	res_opt.name = "ResolutionOption"
	res_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	res_opt.item_selected.connect(_on_resolution)
	SettingsKit.row(self, "UI_I10_SCR_RES").add_child(res_opt)
	if DisplayServer.get_screen_count() > 1:
		monitor_opt = OptionButton.new()
		monitor_opt.name = "MonitorOption"
		monitor_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		for i in DisplayServer.get_screen_count():
			monitor_opt.add_item(DisplayOptions.monitor_text(i), i)
		monitor_opt.selected = clampi(int(Settings.get_value("monitor")), 0, monitor_opt.item_count - 1)
		monitor_opt.item_selected.connect(func(i: int) -> void: _change("monitor", i))
		SettingsKit.row(self, "UI_I10_SCR_MONITOR").add_child(monitor_opt)
	vsync_opt = _option("UI_I10_SCR_VSYNC", ["UI_I10_SCR_VSYNC_OFF", "UI_I10_SCR_VSYNC_ON", "UI_I10_SCR_VSYNC_ADAPTIVE"],
		Array(DisplayOptions.VSYNCS), "vsync")
	vsync_opt.name = "VsyncOption"
	fps_opt = _option("UI_PERF_FPS_CAP", ["30", "60", "120", "144", "UI_I10_SCR_FPS_UNLIMITED"], Array(DisplayOptions.FPS_CAPS), "fps_cap")
	fps_opt.name = "FpsOption"
	_size_option()
	SettingsKit.note(self, "UI_I10_SCR_F11_NOTE")
	SettingsKit.button(self, "UI_I10_SCR_RESET", reset_defaults, "ResetDisplay")
	sync_from_settings()
	EventBus.settings_changed.connect(_on_setting)


func _option(key: String, labels: Array, values: Array, setting: String) -> OptionButton:
	var ob := OptionButton.new()
	for i in labels.size():
		ob.add_item(str(labels[i]), i)
	ob.selected = maxi(0, values.find(Settings.get_value(setting)))
	ob.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			_change(setting, values[i]))
	SettingsKit.row(self, key).add_child(ob)
	return ob


## «Dimensione interfaccia» (F5): Automatica · 80% · 90% · 100% · 110% · 125%. Il tetto della scala automatica resta il 125%.
func _size_option() -> void:
	size_opt = OptionButton.new()
	size_opt.name = "UiSizeOption"
	for i in UiScale.SIZE_CHOICES.size():
		size_opt.add_item("UI_SCALE_AUTO" if i == 0 else "%d%%" % int(round(float(UiScale.SIZE_CHOICES[i][1]) * 100.0)), i)
	size_opt.selected = UiScale.size_index(bool(Settings.get_value("ui_scale_auto")), float(Settings.get_value("ui_scale")))
	size_opt.item_selected.connect(func(i: int) -> void:
		if _syncing:
			return
		Settings.set_value("ui_scale_auto", bool(UiScale.SIZE_CHOICES[i][0]))
		Settings.set_value("ui_scale", float(UiScale.SIZE_CHOICES[i][1])))
	size_opt.tooltip_text = "UI_SCALE_HELP"
	SettingsKit.row(self, "UI_SCALE_LABEL").add_child(size_opt)
	SettingsKit.note(self, "UI_SCALE_HELP")


## Scrive un valore dello schermo; se è dei cambi «rischiosi» chiede conferma.
func _change(key: String, value: Variant) -> void:
	var before := DisplayOptions.snapshot()
	if not Settings.set_value(key, value):
		return
	if DisplayOptions.RISKY_KEYS.has(key) and DisplayOptions.managed():
		ask_keep(before)


func ask_keep(before: Dictionary) -> void:
	if keep_dialog != null and is_instance_valid(keep_dialog):
		keep_dialog.seconds_left = DisplayOptions.KEEP_SECONDS            # un altro cambio: si riparte da 10, "prima" resta il primo
		return
	Settings.set_value("display_revert", before)       # se il gioco si chiude adesso, al riavvio si torna a «prima»
	Settings.flush()                                   # su disco subito: la scrittura ritardata non deve far perdere il «prima»
	keep_dialog = KeepDisplayDialog.show_for(self, before)


func _on_resolution(i: int) -> void:
	if _syncing or i < 0 or i >= _res_values.size():
		return
	_change("window_size", _res_values[i])


## Rimette ai predefiniti tutto ciò che sta in questa scheda (e chiede conferma se cambia la finestra).
func reset_defaults() -> void:
	var before := DisplayOptions.snapshot()
	var risky := false
	for k in DisplayOptions.KEYS:
		if Settings.get_value(k) != Settings.DEFAULTS[k]:
			risky = risky or DisplayOptions.RISKY_KEYS.has(k)
		Settings.set_value(k, Settings.DEFAULTS[k])
	Settings.set_value("ui_scale_auto", true)
	Settings.set_value("ui_scale", 1.0)
	if risky and DisplayOptions.managed():
		ask_keep(before)


func _fill_resolutions() -> void:
	res_opt.clear()
	_res_values.clear()
	var screen := clampi(int(Settings.get_value("monitor")), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var scr_size := DisplayServer.screen_get_size(screen)
	if scr_size.x <= 0:
		scr_size = Vector2i(1920, 1080)
	var cur: Vector2i = Settings.get_value("window_size")
	_res_values = DisplayOptions.resolution_choices(scr_size, cur)
	for r in _res_values:
		res_opt.add_item(DisplayOptions.size_text(r))
	res_opt.selected = maxi(0, _res_values.find(cur))


## Allinea i controlli alle impostazioni (F11 o un ripristino le hanno cambiate da fuori).
func sync_from_settings() -> void:
	_syncing = true
	mode_opt.selected = maxi(0, Array(DisplayOptions.MODES).find(Settings.get_value("window_mode")))
	_fill_resolutions()
	res_opt.disabled = str(Settings.get_value("window_mode")) != "windowed"
	vsync_opt.selected = maxi(0, Array(DisplayOptions.VSYNCS).find(Settings.get_value("vsync")))
	fps_opt.selected = maxi(0, Array(DisplayOptions.FPS_CAPS).find(Settings.get_value("fps_cap")))
	size_opt.selected = UiScale.size_index(bool(Settings.get_value("ui_scale_auto")), float(Settings.get_value("ui_scale")))
	if monitor_opt != null:
		monitor_opt.selected = clampi(int(Settings.get_value("monitor")), 0, monitor_opt.item_count - 1)
	_syncing = false


func _on_setting(key: String, _v: Variant) -> void:
	if DisplayOptions.KEYS.has(key) or key == "ui_scale" or key == "ui_scale_auto":
		sync_from_settings()
