extends GameScreen
## Luoghi Segreti (docs/11 §7, GUILD-2): 10 Frammenti di Mappa rivelano un luogo per 24 h; nella finestra si fanno
## esplorazioni a tempo (XP della mansione e un'ombra di oggetto raro). Solo presentazione: legge SecretSystem.
## Le carte si ricostruiscono quando cambia lo stato (rivelato/esplorazione/frammenti), i numeri si aggiornano sul posto.

var _sc: SecretSystem
var _frag: Label
var _col: VBoxContainer
var _sig: String = ""
var _cards: Dictionary = {}          # spot_id -> {left: Label, runs: Label, bar: ProgressBar, prog: Label}


func open(_params: Dictionary) -> void:
	_sc = Game.system("secrets") as SecretSystem
	var title := Label.new()
	ScreenKit.title_style(title)
	title.text = tr("UI_MENU_SECRETS")
	add_child(title)
	if _sc == null:
		return
	var intro := Label.new()
	intro.text = tr("UI_GUILD2_SEC_INTRO")
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_frag = Label.new()
	_frag.theme_type_variation = &"MonoLabel"
	_frag.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_frag)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 8)
	scroll.add_child(_col)
	refresh()


func refresh() -> void:
	if _sc == null or _col == null:
		return
	_frag.text = Loc.tf("UI_GUILD2_SEC_FRAGMENTS", {"n": _sc.fragments(), "found": _sc.discovered_count(), "total": _sc.spot_ids().size()})
	var parts := PackedStringArray([Loc.locale(), str(_sc.fragments()), _sc.active_spot()])
	for sid in _sc.spot_ids():
		parts.append("%s:%s:%d:%s" % [sid, _sc.is_revealed(str(sid)), _sc.runs_left(str(sid)), _sc.can_reveal(str(sid))])
	var sig := "|".join(parts)
	if sig != _sig:
		_sig = sig
		_rebuild()
	_update()


func _lab(parent: Control, text: String, variation: StringName = &"", dynamic: bool = true) -> Label:
	var l := Label.new()
	if dynamic:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	parent.add_child(l)
	return l


func _rebuild() -> void:
	for c in _col.get_children():
		c.queue_free()
	_cards.clear()
	for sid in _sc.spot_ids():
		_add_card(str(sid))


func _add_card(sid: String) -> void:
	var d := _sc.spot_def(sid)
	var panel := PanelContainer.new()
	_col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var skill := DataRegistry.get_def("skills", str(d.skill))
	var nm := _lab(v, Loc.t(d.name), &"SectionLabel")
	if _sc.is_discovered(sid):
		nm.text = "%s  (%s)" % [Loc.t(d.name), tr("UI_GUILD2_SEC_DISCOVERED")]
	_lab(v, Loc.tf("UI_GUILD2_SEC_REQ", {"skill": Loc.t(skill.get("name", d.skill)), "lv": int(d.level_req), "frag": int(d.map_fragments_required)}), &"MutedLabel")
	var pv := _sc.preview(sid)
	if not pv.is_empty():
		var item := Loc.t(DataRegistry.item(str(pv.bonus_item)).get("name", pv.bonus_item))
		_lab(v, Loc.tf("UI_GUILD2_SEC_PREVIEW", {"min": int(pv.minutes), "xp": NumberFormat.fmt(float(pv.xp)),
			"item": item, "n": NumberFormat.decimal(float(pv.bonus_expected), 1, Loc.locale())}), &"MutedLabel")
	var info := _lab(v, "", &"MonoLabel")
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.visible = false
	v.add_child(bar)
	var prog := _lab(v, "", &"MonoLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var why := _sc.can_reveal(sid)
	if not _sc.is_revealed(sid):
		var b := Button.new()
		b.text = "UI_GUILD2_SEC_REVEAL"
		b.disabled = why != ""
		b.tooltip_text = "" if why == "" else "UI_GUILD2_SEC_WHY_" + why.to_upper()
		b.pressed.connect(_on_reveal.bind(sid))
		row.add_child(b)
		if why != "":
			_lab(row, tr("UI_GUILD2_SEC_WHY_" + why.to_upper()), &"MutedLabel", false).autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		var e := Button.new()
		e.text = "UI_GUILD2_SEC_EXPLORE"
		var ce := _sc.can_explore(sid)
		e.disabled = ce != ""
		e.tooltip_text = "" if ce == "" else "UI_GUILD2_SEC_NO_" + ce.to_upper()
		e.pressed.connect(_on_explore.bind(sid))
		row.add_child(e)
		if ce != "":
			_lab(row, tr("UI_GUILD2_SEC_NO_" + ce.to_upper()), &"MutedLabel", false).autowrap_mode = TextServer.AUTOWRAP_OFF
	_cards[sid] = {"info": info, "bar": bar, "prog": prog}


func _on_reveal(sid: String) -> void:
	_sc.reveal(sid)
	_sig = ""


func _on_explore(sid: String) -> void:
	_sc.explore(sid)
	_sig = ""


func _update() -> void:
	var run := _sc.run_progress()
	for sid in _cards:
		var c: Dictionary = _cards[sid]
		if _sc.is_revealed(str(sid)):
			(c.info as Label).text = Loc.tf("UI_GUILD2_SEC_OPEN", {"t": NumberFormat.fmt_time(_sc.time_left(str(sid))), "runs": _sc.runs_left(str(sid))})
		else:
			(c.info as Label).text = tr("UI_GUILD2_SEC_HIDDEN")
		var active := str(run.spot) == str(sid)
		(c.bar as ProgressBar).visible = active
		(c.prog as Label).visible = active
		if active:
			(c.bar as ProgressBar).max_value = 1.0
			(c.bar as ProgressBar).value = float(run.fraction)
			(c.prog as Label).text = Loc.tf("UI_GUILD2_SEC_RUNNING", {"t": NumberFormat.fmt_time(float(run.left))})
