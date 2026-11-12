class_name StartBackdrop
extends Control
## Movimento leggero dello sfondo del menù iniziale, SOLO con tween e rettangoli di colore (nessuno sprite nuovo):
## una dozzina di scintille dorate che salgono piano e svaniscono, più un respiro lento del portello del caveau.
## «Riduci animazioni» (Settings.reduce_motion) le ferma e le nasconde; si riaccende da solo se l'impostazione cambia.

const MOTES := 14
const MOTE_COLORS: Array = [Color(0.86, 0.70, 0.30), Color(0.55, 0.70, 0.90), Color(0.86, 0.70, 0.30)]
const BREATH_SECONDS := 5.0
const BREATH_PIXELS := 5.0

var _motes: Array[ColorRect] = []
var _tweens: Array[Tween] = []        # uno per scintilla + l'ultimo per il respiro
var _door: Control
var _door_base_top := 0.0
var _door_base_bottom := 0.0
var _running := false


## `door`: il portello decorativo (si muove di pochi pixel in verticale insieme al respiro).
func setup(door: Control = null) -> void:
	_door = door
	if door != null:
		_door_base_top = door.offset_top
		_door_base_bottom = door.offset_bottom
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	for i in MOTES:
		var m := ColorRect.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := 2.0 if i % 3 != 0 else 3.0
		m.size = Vector2(s, s)
		m.color = MOTE_COLORS[i % MOTE_COLORS.size()]
		m.modulate.a = 0.0
		add_child(m)
		_motes.append(m)
	if EventBus.has_signal("settings_changed"):
		EventBus.settings_changed.connect(func(key: String, _v: Variant) -> void:
			if key == "reduce_motion":
				refresh())
	refresh()


func motion_allowed() -> bool:
	return not bool(Settings.get_value("reduce_motion"))


func is_running() -> bool:
	return _running


## Avvia o ferma in base a «Riduci animazioni» e alla visibilità.
func refresh() -> void:
	if motion_allowed() and is_visible_in_tree():
		_start()
	else:
		_stop()


func _start() -> void:
	if _running:
		return
	_running = true
	_tweens.resize(_motes.size() + 1)
	for i in _motes.size():
		_drift(i)
	_breathe()


func _stop() -> void:
	_running = false
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()
	for m in _motes:
		m.modulate.a = 0.0
	if _door != null:
		_door.offset_top = _door_base_top
		_door.offset_bottom = _door_base_bottom


func _drift(i: int) -> void:
	if not _running:
		return
	var m := _motes[i]
	var w := maxf(size.x, 320.0)
	var h := maxf(size.y, 240.0)
	var seed_f := float((i * 7919) % 100) / 100.0
	m.position = Vector2(w * (0.04 + 0.92 * fmod(seed_f * 3.7 + float(i) * 0.137, 1.0)), h * (0.55 + 0.45 * seed_f))
	m.modulate.a = 0.0
	var dur := 9.0 + 7.0 * fmod(seed_f * 5.3, 1.0)
	var t := create_tween()
	_tweens[i] = t
	t.tween_interval(seed_f * 4.0)
	t.set_parallel(true)
	t.chain().tween_property(m, "position:y", m.position.y - h * 0.5, dur).set_trans(Tween.TRANS_SINE)
	t.tween_property(m, "position:x", m.position.x + (seed_f - 0.5) * 60.0, dur).set_trans(Tween.TRANS_SINE)
	t.tween_property(m, "modulate:a", 0.45, dur * 0.3)
	t.chain().tween_property(m, "modulate:a", 0.0, dur * 0.7)
	t.chain().tween_callback(_drift.bind(i))


func _breathe() -> void:
	if _door == null or not _running:
		return
	var t := create_tween().set_loops()
	_tweens[_motes.size()] = t
	t.tween_method(_set_door_shift, 0.0, BREATH_PIXELS, BREATH_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(_set_door_shift, BREATH_PIXELS, 0.0, BREATH_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_door_shift(v: float) -> void:
	if _door != null and is_instance_valid(_door):
		_door.offset_top = _door_base_top - v
		_door.offset_bottom = _door_base_bottom - v
