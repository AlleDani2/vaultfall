class_name ControlsPanel
extends VBoxContainer
## Scheda «Comandi» delle Impostazioni (1.0): ogni scorciatoia da tastiera e ogni pulsante del controller con il suo tasto attuale,
## «Cambia» → «Premi un tasto…» (Esc annulla), conflitti segnalati con scelta «Scambia»/«Annulla», «Ripristina» per voce e
## «Ripristina predefiniti» per tutto. Le scelte stanno in Settings["keybinds"] (InputBindings). Solo presentazione.

const GROUPS: Array[Dictionary] = [
	{"id": "nav", "title": "UI_I10_GRP_NAV"}, {"id": "screens", "title": "UI_I10_GRP_SCREENS"}, {"id": "game", "title": "UI_I10_GRP_GAME"},
	{"id": "window", "title": "UI_I10_GRP_WINDOW"}, {"id": "bank", "title": "UI_I10_GRP_BANK"}, {"id": "pad", "title": "UI_I10_GRP_PAD"},
]

var capturing: String = ""              # id dell'azione in attesa del prossimo tasto/pulsante
var _status: Label
var _conflict_row: HBoxContainer
var _pending: Dictionary = {}           # {id, event} in attesa di «Scambia»
var _list: VBoxContainer
var _buttons: Dictionary = {}           # id azione -> Button «Cambia»


func _ready() -> void:
	name = "ControlsPanel"
	add_theme_constant_override("separation", 8)
	SettingsKit.section(self, "UI_I10_CTL_TITLE")
	SettingsKit.note(self, "UI_I10_CTL_HELP")
	_status = SettingsKit.note(self, "", true)
	_status.name = "Status"
	_status.visible = false
	_conflict_row = HBoxContainer.new()
	_conflict_row.name = "ConflictRow"
	_conflict_row.visible = false
	add_child(_conflict_row)
	SettingsKit.button(_conflict_row, "UI_I10_CTL_SWAP", _on_swap, "SwapButton")
	SettingsKit.button(_conflict_row, "UI_I10_CTL_KEEP_OLD", _clear_message, "KeepButton")
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	SettingsKit.section(self, "UI_I10_PAD_OPTIONS")
	SettingsKit.option(self, "UI_I10_PAD_GLYPHS", ["UI_I10_GLYPHS_AUTO", "Xbox", "PlayStation", "Steam Deck"], ["auto", "xbox", "playstation", "deck"], "pad_glyphs")
	SettingsKit.option(self, "UI_I10_PAD_HINTS", ["UI_I10_HINTS_AUTO", "UI_I10_HINTS_ALWAYS", "UI_I10_HINTS_NEVER"], ["auto", "always", "never"], "pad_hints")
	SettingsKit.check(self, "UI_I10_PAD_OSK", "osk")
	SettingsKit.note(self, "UI_I10_PAD_OSK_NOTE")
	SettingsKit.button(self, "UI_I10_CTL_RESET_ALL", reset_all, "ResetAll")
	EventBus.settings_changed.connect(_on_setting)
	EventBus.locale_changed.connect(func(_l: String) -> void: rebuild.call_deferred())
	rebuild()


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()          # mai free(): la riga può essere quella che sta emettendo «pressed»
	_buttons.clear()
	var style := GamepadGlyphs.current_style()
	for g in GROUPS:
		var any := false
		for e in InputBindings.ACTIONS:
			if str(e.group) == str(g.id):
				if not any:
					any = true
					var h := Label.new()
					h.text = str(g.title)
					h.theme_type_variation = &"SectionLabel"
					_list.add_child(h)
				_add_row(e, style)


func _add_row(e: Dictionary, style: String) -> void:
	var id := str(e.id)
	var r := HBoxContainer.new()
	r.name = "Row_" + id
	r.add_theme_constant_override("separation", 10)
	var name_l := Label.new()
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.text = row_title(e)
	name_l.custom_minimum_size = Vector2(250, 0)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(name_l)
	if str(e.kind) == InputBindings.KIND_PAD:
		var gh := HBoxContainer.new()
		gh.custom_minimum_size = Vector2(120, 0)
		for ev in InputBindings.events_of(id):
			if ev is InputEventJoypadButton:
				gh.add_child(GamepadGlyphs.make(int((ev as InputEventJoypadButton).button_index), style))
		r.add_child(gh)
	else:
		var k := Label.new()
		k.name = "Keys"
		k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		k.theme_type_variation = &"MonoLabel"
		k.text = InputBindings.label_for(id)
		k.custom_minimum_size = Vector2(160, 0)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(k)
	var fixed := bool(e.get("fixed", false))
	var b := Button.new()
	b.name = "Change"
	b.text = "UI_I10_CTL_FIXED_SHORT" if fixed else "UI_I10_CTL_CHANGE"
	b.disabled = fixed
	b.custom_minimum_size = Vector2(120, 0)
	b.pressed.connect(begin_capture.bind(id))
	r.add_child(b)
	_buttons[id] = b
	var rs := Button.new()
	rs.name = "Reset"
	rs.text = "↺"
	rs.tooltip_text = "UI_I10_CTL_RESET_ONE"
	rs.disabled = fixed or InputBindings.is_default(id)
	rs.pressed.connect(func() -> void:
		var res := InputBindings.reset_one(id)
		_clear_message()
		var names: PackedStringArray = []
		for o in res.swapped:
			names.append(row_title(InputBindings.entry(str(o))))
		if not names.is_empty():
			_show_message(Loc.tf("UI_FIN_CTL_RESET_SWAP", {"names": ", ".join(names)}), false))
	r.add_child(rs)
	_list.add_child(r)


## Titolo della riga: il testo dell'azione (con il numero per le voci del menù).
static func row_title(e: Dictionary) -> String:
	var t := TranslationServer.translate(str(e.text))
	return t.format({"n": e.get("n", 0)})


## Comincia ad aspettare il prossimo tasto (o pulsante, per le azioni del controller).
func begin_capture(id: String) -> void:
	_clear_message()
	capturing = id
	set_process_input(true)
	var b := _buttons.get(id) as Button
	if b != null:
		b.text = "UI_I10_CTL_PRESS" if str(InputBindings.entry(id).kind) == InputBindings.KIND_KEY else "UI_I10_CTL_PRESS_PAD"


func cancel_capture() -> void:
	capturing = ""
	rebuild()


func _input(event: InputEvent) -> void:
	if capturing.is_empty():
		return
	var kind := str(InputBindings.entry(capturing).kind)
	if kind == InputBindings.KIND_KEY:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		get_viewport().set_input_as_handled()
		if k.keycode == KEY_ESCAPE:
			cancel_capture()
			return
		if InputBindings.MODIFIER_KEYS.has(int(k.keycode)):
			return                                         # solo un modificatore: si aspetta il tasto vero
		capture_event(k)
	else:
		var j := event as InputEventJoypadButton
		if j == null or not j.pressed:
			return
		get_viewport().set_input_as_handled()
		capture_event(j)


## Assegna l'evento catturato all'azione in attesa (pubblica: la usano i test). Gestisce rifiuti e conflitti.
func capture_event(ev: InputEvent) -> void:
	var id := capturing
	capturing = ""
	var res := InputBindings.assign(id, ev, false)
	if bool(res.ok):
		_clear_message()
		return
	if str(res.reason) == "conflict":
		_pending = {"id": id, "event": ev}
		var names: PackedStringArray = []
		for o in res.conflicts:
			names.append(row_title(InputBindings.entry(str(o))))
		_show_message(Loc.tf("UI_I10_CTL_CONFLICT", {"key": _event_text(ev), "names": ", ".join(names)}), true)
	else:
		_show_message(TranslationServer.translate(str(res.reason)), false)
	rebuild()


func _event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return InputBindings.key_text(ev as InputEventKey)
	if ev is InputEventJoypadButton:
		return GamepadGlyphs.button_label(int((ev as InputEventJoypadButton).button_index), GamepadGlyphs.current_style())
	return "?"


func _on_swap() -> void:
	if not _pending.is_empty():
		InputBindings.assign(str(_pending.id), _pending.event as InputEvent, true)
	_clear_message()


func _show_message(text: String, with_choices: bool) -> void:
	_status.text = text
	_status.visible = true
	_conflict_row.visible = with_choices


func _clear_message() -> void:
	_pending = {}
	capturing = ""
	if _status != null:
		_status.visible = false
		_conflict_row.visible = false
	rebuild()


func reset_all() -> void:
	InputBindings.reset_all()
	_clear_message()


func _on_setting(key: String, _v: Variant) -> void:
	if key == "keybinds" or key == "pad_glyphs":
		rebuild()
