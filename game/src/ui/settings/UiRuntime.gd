class_name UiRuntime
extends Node
## Parti globali dell'interfaccia della 1.0, figlie dell'autoload Settings (nessun altro autoload):
##   - filtro colore per daltonici / alto contrasto (strato sopra a tutto, shader su schermo: solo colore, D-6);
##   - ultimo dispositivo usato (tastiera/mouse o controller) → EventBus.input_device_changed, glifi e barra dei suggerimenti;
##   - F11 (e Alt+Invio): schermo intero / ritorno alla modalità di prima, in qualsiasi schermata, anche nel menù iniziale;
##   - aiuto al fuoco: con il controller (o le frecce) e nessun controllo a fuoco, il primo input porta il fuoco sul primo controllo;
##   - tastiera a schermo: A su un campo di testo col controller;
##   - memorizza la dimensione della finestra quando la si ridimensiona a mano.

const FILTER_LAYER := 127
const SHADER := preload("res://src/ui/settings/vision_filter.gdshader")
const STICK_THRESHOLD := 0.6
const SIZE_SAVE_DELAY := 1.0

var device := "keyboard"
var vision_layer: CanvasLayer
var hints: InputHints
var _filter_rect: ColorRect
var _material: ShaderMaterial
var _previous_mode := "windowed"
var _size_timer: Timer


func _init() -> void:
	name = "UiRuntime"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	vision_layer = CanvasLayer.new()
	vision_layer.name = "VisionFilter"
	vision_layer.layer = FILTER_LAYER
	vision_layer.visible = false
	add_child(vision_layer)
	_filter_rect = ColorRect.new()
	_filter_rect.name = "Rect"
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_filter_rect.material = _material
	vision_layer.add_child(_filter_rect)
	hints = InputHints.new()
	add_child(hints)
	_size_timer = Timer.new()
	_size_timer.one_shot = true
	_size_timer.wait_time = SIZE_SAVE_DELAY
	_size_timer.timeout.connect(_save_window_size)
	add_child(_size_timer)
	get_window().size_changed.connect(_on_window_size_changed)
	get_tree().node_added.connect(_on_node_added)
	apply_vision()


# ------------------------------------------------------------------ filtro colore

func apply_vision() -> void:
	if _material == null:
		return
	var p := Accessibility.filter_params(str(Settings.get_value("colorblind")), bool(Settings.get_value("high_contrast")))
	_material.set_shader_parameter("mode", int(p.mode))
	_material.set_shader_parameter("contrast", float(p.contrast))
	_material.set_shader_parameter("saturation", float(p.saturation))
	vision_layer.visible = bool(p.active)


## Percentuale scritta sulle barre di avanzamento (informazione che non dipende dal colore). Spenta di serie.
func apply_bar_percent() -> void:
	var on := bool(Settings.get_value("bar_percent"))
	for n in get_tree().root.find_children("*", "ProgressBar", true, false):
		style_bar(n as ProgressBar, on)


static func style_bar(b: ProgressBar, on: bool) -> void:
	b.show_percentage = on
	if on:
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		b.add_theme_constant_override("outline_size", 3)
	else:
		b.remove_theme_font_size_override("font_size")
		b.remove_theme_color_override("font_outline_color")
		b.remove_theme_constant_override("outline_size")


# ------------------------------------------------------------------ dispositivo, F11, fuoco

## Il dispositivo che questo evento indica ("" se non indica niente, per esempio un movimento minimo).
static func device_of(event: InputEvent) -> String:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		return "gamepad"
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > STICK_THRESHOLD:
		return "gamepad"
	if event is InputEventKey and (event as InputEventKey).pressed:
		return "keyboard"
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		return "keyboard"
	return ""


func _input(event: InputEvent) -> void:
	var d := device_of(event)
	if not d.is_empty() and d != device:
		device = d
		EventBus.input_device_changed.emit(d)
	if _is_fullscreen_toggle(event):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if _wants_focus(event) and FocusAssist.ensure_focus(get_tree()):
		get_viewport().set_input_as_handled()


static func _is_fullscreen_toggle(event: InputEvent) -> bool:
	if InputBindings.pressed(event, "fullscreen"):
		return true
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.alt_pressed and not k.ctrl_pressed \
		and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)


## Direzioni dell'interfaccia (levetta, croce, frecce, Tab) o, col controller, il pulsante di conferma.
static func _wants_focus(event: InputEvent) -> bool:
	if not ((event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed) or event is InputEventJoypadMotion):
		return false
	for a in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]:
		if event.is_action_pressed(a, false, true):
			return true
	return event is InputEventJoypadButton and InputBindings.matches(event, "pad_confirm")


func toggle_fullscreen() -> void:
	var cur := str(Settings.get_value("window_mode"))
	var nxt := DisplayOptions.toggled_mode(cur, _previous_mode)
	if cur != "fullscreen":
		_previous_mode = cur
	Settings.set_value("window_mode", nxt)


# ------------------------------------------------------------------ dimensione della finestra

func _on_window_size_changed() -> void:
	if _size_timer != null and DisplayOptions.managed():
		_size_timer.start()


func _save_window_size() -> void:
	var win := get_window()
	if win == null or win.mode != Window.MODE_WINDOWED or win.borderless or not DisplayOptions.managed():
		return
	var s := win.size
	if s.x >= DisplayOptions.MIN_WINDOW.x and s.y >= DisplayOptions.MIN_WINDOW.y and s.x <= DisplayOptions.MAX_WINDOW.x \
			and s.y <= DisplayOptions.MAX_WINDOW.y:
		Settings.set_value("window_size", s)


# ------------------------------------------------------------------ tastiera a schermo

func _on_node_added(n: Node) -> void:
	if n is ProgressBar and bool(Settings.get_value("bar_percent")):
		style_bar.call_deferred(n, true)
	if (n is LineEdit or n is TextEdit) and not n.gui_input.is_connected(_on_text_input.bind(n)):
		n.gui_input.connect(_on_text_input.bind(n))


## A (conferma) su un campo di testo col controller: apre la tastiera a schermo.
func _on_text_input(event: InputEvent, field: Control) -> void:
	if device != "gamepad" or not bool(Settings.get_value("osk")):
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and InputBindings.matches(event, "pad_confirm"):
		if OnScreenKeyboard.open_for(field) != null:
			field.accept_event()
