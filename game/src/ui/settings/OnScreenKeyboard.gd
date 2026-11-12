class_name OnScreenKeyboard
extends Window
## Tastiera a schermo semplice per i campi di testo col controller (Steam Deck, gamepad): una finestra con i tasti, tutti
## raggiungibili col fuoco (croce direzionale/levetta + A). Scrive direttamente nel campo (LineEdit o TextEdit) alla posizione
## del cursore; «Fatto» conferma (invio nel campo), «Annulla»/B/Esc la chiude lasciando il testo com'è.
##   OnScreenKeyboard.open_for(campo)    la apre se il campo è LineEdit/TextEdit e non ce n'è già una

const ROWS: PackedStringArray = ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-", "àèéìòù_/:?"]

var target: Control
var shift := false
var _letters: Array[Button] = []
var _done_btn: Button


## Apre la tastiera per `field`. Ritorna la finestra, o null se il campo non è di testo o ce n'è già una aperta.
static func open_for(field: Control) -> OnScreenKeyboard:
	if not (field is LineEdit or field is TextEdit) or not field.is_inside_tree():
		return null
	var host := field.get_window()
	for c in host.get_children():
		if c is OnScreenKeyboard and not c.is_queued_for_deletion():
			return null
	var k := OnScreenKeyboard.new()
	k.target = field
	host.add_child(k)
	k.popup_below()
	return k


func _init() -> void:
	name = "OnScreenKeyboard"
	exclusive = true
	transient = true
	borderless = true
	unresizable = true
	wrap_controls = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	for r in ROWS:
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 4)
		v.add_child(h)
		for i in r.length():
			var ch := r.substr(i, 1)
			var b := _key(ch)
			b.pressed.connect(_on_char.bind(ch))
			h.add_child(b)
			if not _is_digit(ch):
				_letters.append(b)
	var f := HBoxContainer.new()
	f.alignment = BoxContainer.ALIGNMENT_CENTER
	f.add_theme_constant_override("separation", 4)
	v.add_child(f)
	var sh := _fn("UI_I10_OSK_SHIFT", 96)
	sh.name = "Shift"
	sh.toggle_mode = true
	sh.toggled.connect(func(on: bool) -> void:
		shift = on
		_relabel())
	f.add_child(sh)
	var left := _fn("◂", 52)
	left.pressed.connect(_move.bind(-1))
	f.add_child(left)
	var sp := _fn("UI_I10_OSK_SPACE", 180)
	sp.name = "Space"
	sp.pressed.connect(_on_char.bind(" "))
	f.add_child(sp)
	var right := _fn("▸", 52)
	right.pressed.connect(_move.bind(1))
	f.add_child(right)
	var bs := _fn("⌫", 64)
	bs.name = "Backspace"
	bs.pressed.connect(backspace)
	f.add_child(bs)
	var cancel := _fn("UI_I10_OSK_CANCEL", 96)
	cancel.name = "Cancel"
	cancel.pressed.connect(close)
	f.add_child(cancel)
	_done_btn = _fn("UI_I10_OSK_DONE", 96)
	_done_btn.name = "Done"
	_done_btn.theme_type_variation = &"AccentButton"
	_done_btn.pressed.connect(done)
	f.add_child(_done_btn)
	close_requested.connect(close)


func popup_below() -> void:
	popup()
	var vp := Vector2i(get_parent().get_viewport().get_visible_rect().size) if get_parent() != null else Vector2i(1280, 720)
	var s := get_contents_minimum_size()
	size = Vector2i(s)
	position = Vector2i(maxi(0, (vp.x - size.x) / 2), maxi(0, vp.y - size.y - 12))
	for c in find_children("Key_q", "Button", true, false):
		(c as Button).grab_focus()
		break


func _key(ch: String) -> Button:
	var b := Button.new()
	b.name = "Key_" + (ch if ch.to_lower() >= "a" and ch.to_lower() <= "z" or _is_digit(ch) else "u%d" % ch.unicode_at(0))
	b.set_meta("ch", ch)
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = ch
	b.custom_minimum_size = Vector2(46, 42)
	return b


func _fn(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 42)
	return b


func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


func _relabel() -> void:
	for b in _letters:
		var base := str(b.get_meta("ch"))
		b.text = base.to_upper() if shift else base


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ scrittura nel campo (pubbliche: le usano anche i test)

func _on_char(ch: String) -> void:
	type_text(ch.to_upper() if (shift and not _is_digit(ch)) else ch)


func type_text(t: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target is LineEdit:
		(target as LineEdit).insert_text_at_caret(t)
	elif target is TextEdit:
		(target as TextEdit).insert_text_at_caret(t)


func backspace() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target is LineEdit:
		var le := target as LineEdit
		var c := le.caret_column
		if c > 0:
			le.delete_text(c - 1, c)
			le.caret_column = c - 1
	elif target is TextEdit:
		(target as TextEdit).backspace()


func _move(d: int) -> void:
	if target is LineEdit:
		(target as LineEdit).caret_column += d
	elif target is TextEdit:
		var te := target as TextEdit
		te.set_caret_column(maxi(0, te.get_caret_column() + d))


## Conferma: come premere Invio nel campo, poi chiude.
func done() -> void:
	var t := target
	close()
	if t is LineEdit and is_instance_valid(t):
		(t as LineEdit).text_submitted.emit((t as LineEdit).text)


## Chiude senza altro e restituisce il fuoco al campo.
func close() -> void:
	var t := target
	hide()
	if t != null and is_instance_valid(t) and t.is_inside_tree():
		t.grab_focus.call_deferred()
	queue_free()
