class_name BonusDialog
extends AcceptDialog
## Finestra «Bonus attivi» (docs/14 §4, UI-A G17, rapporto 112): i bonus raggruppati per categoria, ognuno con valore grande,
## nome comprensibile, una frase che spiega a cosa serve, il «tetto» quando c'è e l'elenco (compatto, espandibile) delle
## fonti con il loro nome vero. Cerca per nome, descrizione o fonte. Si ricostruisce da sola quando i bonus cambiano
## (EventBus.modifiers_changed). Solo presentazione: legge ModifierStack tramite BonusSummary.

const GOLD := Color("e0b640")
const VALUE_SIZE := 24
const TITLE_SIZE := UiType.SECTION

var _search: LineEdit
var _count: Label
var _list: VBoxContainer
var _stack: ModifierStack
var _dirty := true
var _open: Dictionary = {}          # chiave del bonus -> elenco fonti espanso (resta aperto quando la lista si ricostruisce)


func _init(stack: ModifierStack = null) -> void:
	_stack = stack if stack != null else Modifiers.stack
	title = TranslationServer.translate("UI_UIA_BONUS_TITLE")
	ok_button_text = TranslationServer.translate("UI_UIA_AUTO_CLOSE")
	min_size = Vector2i(640, 460)


## Apre la finestra sopra `parent` (Riepilogo, Eroe…): un solo punto, così ogni pulsante «Bonus attivi» fa la stessa cosa.
static func open_on(parent: Node, stack: ModifierStack = null) -> BonusDialog:
	var dlg := BonusDialog.new(stack)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	parent.add_child(dlg)
	dlg.popup_centered_clamped(Vector2i(820, 620), 0.92)
	dlg._fit.call_deferred()
	return dlg


## Dimensione e posizione giuste dopo il primo layout: i testi a capo, misurati prima che la finestra abbia una larghezza,
## gonfiano l'altezza della finestra (4000 px e oltre) e poi non si ritira da sola.
func _fit() -> void:
	if not is_inside_tree():
		return
	var vp := get_parent().get_viewport().get_visible_rect().size
	var s := Vector2i(maxi(min_size.x, mini(820, int(vp.x * 0.92))), maxi(min_size.y, mini(620, int(vp.y * 0.92))))
	size = s
	position = Vector2i(maxi(0, int((vp.x - s.x) * 0.5)), maxi(0, int((vp.y - s.y) * 0.5)))


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size.x = 600       # senza una larghezza minima i testi a capo si stringono e il dialogo diventa altissimo
	add_child(box)
	_count = Label.new()
	_count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_count.theme_type_variation = &"SectionLabel"
	box.add_child(_count)
	var help := Label.new()
	help.text = "UI_BONUS_HELP"
	help.theme_type_variation = &"MutedLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	_search = LineEdit.new()
	_search.placeholder_text = "UI_UIA_BONUS_SEARCH"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: rebuild())
	box.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var legend := Label.new()
	legend.text = "UI_BONUS_LEGEND"
	legend.theme_type_variation = &"MutedLabel"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(legend)
	EventBus.modifiers_changed.connect(func() -> void: _dirty = true)
	rebuild()


func _process(_dt: float) -> void:
	if _dirty and visible:
		rebuild()


func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func rebuild() -> void:
	_dirty = false
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var all_rows := BonusSummary.rows(_stack)
	var rows := BonusSummary.rows(_stack, _search.text if _search != null else "")
	var capped := 0
	for r in all_rows:
		if bool(r.capped):
			capped += 1
	var head := Loc.tf("UI_BONUS_COUNT_ONE" if all_rows.size() == 1 else "UI_BONUS_COUNT", {"n": all_rows.size()})
	if capped > 0:
		head += " · " + Loc.tf("UI_BONUS_COUNT_CAPPED", {"n": capped})
	_count.text = head
	if rows.is_empty():
		var none := _label(TranslationServer.translate("UI_UIA_BONUS_NONE" if all_rows.is_empty() else "UI_BONUS_NO_MATCH"), &"MutedLabel")
		_list.add_child(none)
		return
	for g in BonusSummary.groups(rows):
		_list.add_child(_group_header(g))
		for r in g.rows:
			_list.add_child(_card(r))


func _group_header(g: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = g.color
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var tag := _label(str(g.tag))
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.add_theme_color_override("font_color", LogCategory.ON_COLOR)
	badge.add_child(tag)
	row.add_child(badge)
	var name_l := _label(str(g.label), &"SectionLabel")
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name_l)
	var n := _label("(%d)" % (g.rows as Array).size(), &"MutedLabel")
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(n)
	return row


func _card(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ContentPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	# valore grande
	var val := _label(str(r.total))
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	val.custom_minimum_size.x = 120
	val.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	val.add_theme_font_size_override("font_size", VALUE_SIZE)
	val.add_theme_color_override("font_color", GOLD if bool(r.capped) else Color("f0d9a0"))
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	val.tooltip_text = str(r.blurb)
	h.add_child(val)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	v.add_child(title_row)
	var t := _label(str(r.title))
	t.add_theme_font_size_override("font_size", TITLE_SIZE)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(t)
	if bool(r.has_more):
		var chip := _label(TranslationServer.translate("UI_BONUS_MORE_CHIP"), &"MutedLabel")
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_theme_color_override("font_color", Color("8fd0f0"))
		chip.tooltip_text = TranslationServer.translate("UI_BONUS_MORE_TIP")
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		title_row.add_child(chip)
	if bool(r.capped):
		var lim := _label(TranslationServer.translate("UI_BONUS_CAP_CHIP"))
		lim.autowrap_mode = TextServer.AUTOWRAP_OFF
		lim.add_theme_color_override("font_color", GOLD)
		title_row.add_child(lim)
	v.add_child(_label(str(r.blurb), &"MutedLabel"))
	if not str(r.cap_note).is_empty():
		v.add_child(_cap_bar(r))
	v.add_child(_sources(r))
	return card


func _cap_bar(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = float(r.cap_ratio)
	bar.custom_minimum_size = Vector2(90, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(r.capped):
		bar.add_theme_stylebox_override("fill", UiKit.tinted_fill(GOLD))
	row.add_child(bar)
	var l := _label(str(r.cap_note), &"MutedLabel")
	if bool(r.capped):
		l.add_theme_color_override("font_color", GOLD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


## Fonti: una sola si legge in riga («Da: Evento: …»); più fonti stanno in un pulsante a freccia che le apre.
func _sources(r: Dictionary) -> Control:
	var srcs: Array = r.sources
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	if srcs.size() == 1:
		box.add_child(_label(Loc.tf("UI_BONUS_FROM_ONE", {"src": str(srcs[0].label)}), &"MutedLabel"))
		return box
	var key := str(r.key)
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.tooltip_text = TranslationServer.translate("UI_BONUS_FROM_TIP")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	for s in srcs:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var amount := _label(str(s.text), &"MonoLabel")
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.custom_minimum_size.x = 70
		if bool(s.more):
			amount.add_theme_color_override("font_color", Color("8fd0f0"))
		line.add_child(amount)
		var nm := _label(str(s.label), &"MutedLabel")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(nm)
		list.add_child(line)
	list.visible = bool(_open.get(key, false))
	var title_key := "UI_BONUS_FROM_MANY"
	var refresh_btn := func() -> void:
		Disclosure.apply(btn, title_key, list.visible)
		btn.text += " (%d)" % srcs.size()
	refresh_btn.call()
	btn.pressed.connect(func() -> void:
		list.visible = not list.visible
		_open[key] = list.visible
		refresh_btn.call())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(btn)
	var names: PackedStringArray = []
	for s in srcs:
		names.append(str(s.label))
	var preview := _label(", ".join(names), &"MutedLabel")      # elenco compatto: i nomi, tagliati con «…»
	preview.autowrap_mode = TextServer.AUTOWRAP_OFF
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.clip_text = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.x = 40
	preview.visible = not list.visible
	btn.pressed.connect(func() -> void: preview.visible = not list.visible)
	head.add_child(preview)
	box.add_child(head)
	box.add_child(list)
	return box
