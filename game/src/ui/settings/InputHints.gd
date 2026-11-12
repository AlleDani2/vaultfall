class_name InputHints
extends CanvasLayer
## Barra dei suggerimenti dei pulsanti (1.0, docs/review_1_0/03 punto 3): in basso, piccola e trasparente ai clic, mostra
## «A Conferma · B Indietro · LB RB Schede · Menu Menù · X Sabbia» con i glifi dello stile scelto. Appare quando si usa il
## controller (o sempre / mai, a scelta in Impostazioni → Comandi). Solo presentazione: legge InputBindings e Settings.

var _panel: PanelContainer
var _row: HBoxContainer
var device := "keyboard"


func _init() -> void:
	layer = 100
	name = "InputHints"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"ContentPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate = Color(1, 1, 1, 0.94)
	add_child(_panel)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 18)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_row)
	EventBus.input_device_changed.connect(_on_device)
	EventBus.settings_changed.connect(_on_setting)
	EventBus.locale_changed.connect(func(_l: String) -> void: rebuild())
	EventBus.game_started.connect(func(_s: int, _n: bool) -> void: rebuild())
	rebuild()


func _on_device(d: String) -> void:
	device = d
	rebuild()


func _on_setting(key: String, _v: Variant) -> void:
	if key == "pad_glyphs" or key == "pad_hints" or key == "keybinds" or key == "push_enabled":
		rebuild()


## I suggerimenti da mostrare: [{"ids": [azioni], "text": chiave}]. «Menù» e «Sabbia» solo in partita.
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"ids": ["pad_confirm"], "text": "UI_I10_HINT_CONFIRM"},
		{"ids": ["pad_back"], "text": "UI_I10_HINT_BACK"},
		{"ids": ["pad_tab_prev", "pad_tab_next"], "text": "UI_I10_HINT_TABS"},
	]
	if GameState.active:
		out.append({"ids": ["pad_menu"], "text": "UI_I10_HINT_MENU"})
		if bool(Settings.get_value("push_enabled")):
			out.append({"ids": ["pad_sand"], "text": "UI_I10_HINT_SAND"})
	return out


func should_show() -> bool:
	var mode := str(Settings.get_value("pad_hints"))
	return mode == "always" or (mode == "auto" and device == "gamepad")


func rebuild() -> void:
	if _row == null:
		return
	for c in _row.get_children():
		c.free()
	_panel.visible = should_show()
	if not _panel.visible:
		return
	var st := GamepadGlyphs.current_style()
	for it in items():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for id in it.ids:
			for ev in InputBindings.events_of(str(id)):
				if ev is InputEventJoypadButton:
					h.add_child(GamepadGlyphs.make(int((ev as InputEventJoypadButton).button_index), st))
					break
		var l := Label.new()
		l.text = str(it.text)
		l.theme_type_variation = &"MutedLabel"
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		_row.add_child(h)
	_place.call_deferred()


func _place() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
