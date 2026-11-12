class_name CodexMonstersView
extends VBoxContainer
## Scheda «Mostri» del Compendio (docs/15 §2, UI-A G16): uccisioni per mostro e, per ognuno, le caselle dei drop della sua
## tabella (a colori quelle già ottenute, grigie le mancanti). Le probabilità dei drop stanno nel Manuale.

const ROW_H := 30.0
const CELL := Vector2(96, 92)

var _codex: CodexSystem
var _ids: Array = []
var _selected := ""
var _head: Label
var _bar: ProgressBar
var _list: VirtualList
var _detail: VBoxContainer
var _sig := ""


func setup(codex: CodexSystem) -> void:
	_codex = codex
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_head = Label.new()
	_head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_head.theme_type_variation = &"SectionLabel"
	add_child(_head)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 14)
	add_child(_bar)
	var hint := Label.new()
	hint.text = "UI_UIA_CODEX_MON_HELP"
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	_list = VirtualList.new()
	_list.row_height = ROW_H
	_list.custom_minimum_size = Vector2(300, 160)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.make_row = _make_row
	_list.bind_row = _bind_row
	body.add_child(_list)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContentPanel"
	panel.custom_minimum_size.x = 380
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	scroll.add_child(_detail)
	_rebuild()


func refresh() -> void:
	if _signature() != _sig:
		_rebuild()


func _signature() -> String:
	var n := 0
	for m in _ids:
		n += _codex.kills_of(str(m))
	var d := 0
	for k in _codex.state.mon_drops:
		d += (_codex.state.mon_drops[k] as Dictionary).size()
	return "%s|%d|%d|%s" % [Loc.locale(), n, d, _selected]


func _rebuild() -> void:
	_ids = _codex.monster_ids()
	_sig = _signature()
	var p := _codex.monster_progress()
	_head.text = Loc.tf("UI_UIA_CODEX_PROGRESS", {"have": NumberFormat.fmt(int(p.have)), "total": NumberFormat.fmt(int(p.total)),
		"pct": CodexSystem.pct_text(int(p.have), int(p.total))})
	_bar.max_value = maxf(1.0, float(p.total))
	_bar.value = float(p.have)
	_list.set_count(_ids.size())
	_list.rebind()
	_fill_detail()


func _make_row() -> Control:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var h := HBoxContainer.new()
	h.name = "H"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 10)
	b.add_child(h)
	var nm := Label.new()
	nm.name = "Name"
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	var k := Label.new()
	k.name = "Kills"
	k.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	k.theme_type_variation = &"MonoLabel"
	k.custom_minimum_size.x = 110
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(k)
	b.pressed.connect(func() -> void:
		_selected = str(b.get_meta("id", ""))
		_list.rebind()
		_sig = _signature()
		_fill_detail())
	return b


func _bind_row(row: Control, index: int) -> void:
	var id := str(_ids[index])
	var m := DataRegistry.get_def("monsters", id)
	var kills := _codex.kills_of(id)
	row.set_meta("id", id)
	var h: Node = row.get_node("H")
	h.get_node("Name").text = "%s  (%s %d)" % [Loc.t(m.get("name", id)), tr("UI_UIA_CODEX_LV"), int(m.get("level", 0))]
	h.get_node("Kills").text = Loc.tf("UI_UIA_CODEX_KILLS", {"n": NumberFormat.fmt(kills)}) if kills > 0 else tr("UI_UIA_CODEX_MISSING")
	row.modulate = Color(1, 1, 1, 1) if id != _selected else Color(1.0, 0.92, 0.6, 1)
	if kills <= 0:
		row.modulate.a = 0.5


func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected.is_empty():
		var l := Label.new()
		l.text = "UI_UIA_CODEX_MON_PICK"
		l.theme_type_variation = &"MutedLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)
		return
	var m := DataRegistry.get_def("monsters", _selected)
	var kills := _codex.kills_of(_selected)
	var title := Label.new()
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.theme_type_variation = &"SectionLabel"
	title.text = Loc.t(m.get("name", _selected))
	_detail.add_child(title)
	var info := Label.new()
	info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.theme_type_variation = &"MutedLabel"
	info.text = Loc.tf("UI_UIA_CODEX_MON_INFO", {"lv": int(m.get("level", 0)), "kills": NumberFormat.fmt(kills),
		"zone": Loc.t(DataRegistry.get_def("zones", str(m.get("zone", ""))).get("name", str(m.get("zone", ""))))})
	_detail.add_child(info)
	var p := _codex.monster_drop_progress(_selected)
	var dp := Label.new()
	dp.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dp.text = Loc.tf("UI_UIA_CODEX_DROPS", {"have": int(p.have), "total": int(p.total)})
	_detail.add_child(dp)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_detail.add_child(flow)
	for item_id in _codex.drop_slots(_selected):
		flow.add_child(_cell(str(item_id), _codex.drop_got(_selected, str(item_id))))
	if int(p.total) == 0:
		var none := Label.new()
		none.text = "UI_UIA_CODEX_NO_DROPS"
		none.theme_type_variation = &"MutedLabel"
		_detail.add_child(none)


func _cell(item_id: String, got: int) -> Control:
	var d := DataRegistry.item(item_id)
	var b := ItemTipButton.new()
	b.set_item(item_id)
	b.custom_minimum_size = CELL
	b.focus_mode = Control.FOCUS_NONE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	var tex := TextureRect.new()
	var kind := str(d.get("icon", "")).get_base_dir().get_file()
	tex.texture = IconLib.icon(kind if not kind.is_empty() else "items", item_id)
	tex.custom_minimum_size = Vector2(36, 36)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tex)
	var n := Label.new()
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.text = Loc.t(d.get("name", item_id))
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	b.modulate = Color(1, 1, 1, 1) if got > 0 else Color(1, 1, 1, 0.38)
	if got > 0:
		var c := Label.new()
		c.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		c.text = "×" + NumberFormat.fmt(got)
		c.theme_type_variation = &"MonoLabel"
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(c)
	return b
