class_name SettingsKit
extends RefCounted
## Costruttori di righe per le schede delle Impostazioni (etichetta a sinistra, controllo a destra). Ogni controllo scrive solo in
## Settings: nessuna logica di gioco. Le chiavi «UI_...» si traducono da sole (auto-traduzione dei nodi).

const LABEL_W := 340.0                       # etichetta su UNA riga (prima 240: «(+N s)» andava a capo)
const ROW_H := 40.0                          # bersaglio minimo per controller e Steam Deck


static func section(parent: Control, key: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = &"SectionLabel"
	parent.add_child(l)
	return l


static func note(parent: Control, key: String, translated: bool = false) -> Label:
	var l := Label.new()
	if translated:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = key
	l.theme_type_variation = &"MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func row(parent: Control, key: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	r.custom_minimum_size = Vector2(0, ROW_H)
	var l := Label.new()
	l.text = key
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(l)
	parent.add_child(r)
	return r


## Tendina su Settings[setting]: `labels` sono chiavi (si traducono) e `values` i valori da scrivere.
static func option(parent: Control, key: String, labels: Array, values: Array, setting: String) -> OptionButton:
	var ob := OptionButton.new()
	for i in labels.size():
		ob.add_item(str(labels[i]), i)
	ob.selected = maxi(0, values.find(Settings.get_value(setting)))
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(setting, values[i]))
	row(parent, key).add_child(ob)
	return ob


## Riga di una casella (revisione grafica 1.0, problema 13): la casella sta ACCANTO all'etichetta, a sinistra, e l'INTERA riga si
## clicca (anche il testo); riga alta almeno 40 px (controller, Steam Deck). La riga è l'HBox genitore della casella.
const CHECK_ROW_H := 40.0


static func check_row(parent: Control, key: String, tip: String = "") -> CheckBox:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	r.custom_minimum_size = Vector2(0, CHECK_ROW_H)
	var cb := CheckBox.new()
	cb.tooltip_text = tip
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(cb)
	var l := Label.new()
	l.text = key
	l.tooltip_text = tip
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not cb.disabled:
			cb.button_pressed = not cb.button_pressed)
	r.add_child(l)
	parent.add_child(r)
	return cb


static func check(parent: Control, key: String, setting: String) -> CheckBox:
	var cb := check_row(parent, key)
	cb.button_pressed = bool(Settings.get_value(setting))
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(setting, on))
	return cb


static func button(parent: Control, key: String, action: Callable, node_name: String = "") -> Button:
	var b := Button.new()
	b.text = key
	if not node_name.is_empty():
		b.name = node_name
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Contenitore di una scheda: scorrimento verticale con il fuoco che segue il controllo, un po' di margine a destra per la barra.
static func tab_page(name_key: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name_key
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 12)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return [sc, v]
