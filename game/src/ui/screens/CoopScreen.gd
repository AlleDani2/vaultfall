extends GameScreen
## Amici (COOP-1): codici da copiare e incollare, Compagni d'armi, Prova della settimana e classifica LOCALE.
## Solo presentazione: legge e chiama CoopSystem. Nessuna rete. I testi sono chiavi del CSV (localization/parts/coop.csv).

const NOTICE_COLOR_OK := Color(0.55, 0.85, 0.55)
const NOTICE_COLOR_BAD := Color(0.95, 0.55, 0.5)

var _co: CoopSystem
var _name_edit: LineEdit
var _code_out: TextEdit
var _paste: TextEdit
var _feedback: Label
var _copied: Label
var _comp_col: VBoxContainer
var _week_col: VBoxContainer
var _board_col: VBoxContainer
var _sig_comp: String = ""
var _sig_week: String = ""
var _sig_board: String = ""
var _result_msg: String = ""
var _scroll: ScrollContainer


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func open(_params: Dictionary) -> void:
	_co = Game.system("coop") as CoopSystem
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	scroll.add_child(col)
	ScreenKit.title_style(_lab(col, tr("UI_COOP_TITLE"), &"TitleLabel", false))
	if _co == null:
		return
	_co.refresh(_now())
	_lab(col, tr("UI_COOP_INTRO"), &"MutedLabel", false)
	_build_steps(col)
	_build_mine(col)
	_build_paste(col)
	_comp_col = _card(col, tr("UI_COOP_COMP_TITLE"))
	_week_col = _card(col, tr("UI_COOP_WEEK_TITLE"))
	_board_col = _card(col, tr("UI_COOP_BOARD_TITLE"))
	_lab(col, tr("UI_COOP_ETHICS"), &"MutedLabel", false)
	refresh()


func refresh() -> void:
	if _co == null or _comp_col == null:
		return
	var comp_sig := _comp_signature()
	if comp_sig != _sig_comp:
		_sig_comp = comp_sig
		_rebuild_companions()
	var now := _now()
	var wk := CoopWeekly.week_of(now)
	var week_sig := "%s|%s|%s|%s" % [Loc.locale(), str(wk.id), _result_msg, str(_co.my_result(str(wk.id)).get("issued", 0))]
	if week_sig != _sig_week:
		_sig_week = week_sig
		_rebuild_week(wk, now)
	var board_sig := "%s|%s|%d" % [Loc.locale(), str(wk.id), JSON.stringify(_co.state.results.get(str(wk.id), {})).hash()]
	if board_sig != _sig_board:
		_sig_board = board_sig
		_rebuild_board(str(wk.id))


# ------------------------------------------------------------------ pezzi fissi

func _lab(parent: Control, text: String, variation: StringName = &"", dynamic: bool = true) -> Label:
	var l := Label.new()
	if dynamic:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = text
	parent.add_child(l)
	return l


## Scheda con titolo; ritorna il contenitore interno.
func _card(parent: Control, title: String) -> VBoxContainer:
	var v := ScreenKit.card(parent, ScreenKit.accent("coop"), 4)
	v.add_theme_constant_override("separation", 6)
	_lab(v, title, &"SectionLabel", false)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	v.add_child(body)
	return body


func _btn(parent: Control, key: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = key
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_steps(col: VBoxContainer) -> void:
	var body := _card(col, tr("UI_COOP_STEPS_TITLE"))
	for k in ["UI_COOP_STEP1", "UI_COOP_STEP2", "UI_COOP_STEP3"]:
		_lab(body, tr(k), &"", false)


func _build_mine(col: VBoxContainer) -> void:
	var body := _card(col, tr("UI_COOP_MY_TITLE"))
	_lab(body, tr("UI_COOP_MY_NAME"), &"MutedLabel", false)
	_name_edit = LineEdit.new()
	_name_edit.max_length = int(_co.rules().code.name_max)
	_name_edit.text = _co.my_name()
	_name_edit.placeholder_text = tr("UI_COOP_MY_NAME_HINT")
	_name_edit.text_submitted.connect(_on_name)
	_name_edit.focus_exited.connect(func() -> void: _on_name(_name_edit.text))
	body.add_child(_name_edit)
	_code_out = TextEdit.new()
	_code_out.editable = false
	_code_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code_out.custom_minimum_size = Vector2(0, 72)
	_code_out.placeholder_text = tr("UI_COOP_MY_CODE_HINT")
	body.add_child(_code_out)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	_btn(row, "UI_COOP_BTN_COPY_MINE", _on_copy_mine)
	_copied = _lab(row, "", &"MutedLabel")
	_lab(body, Loc.tf("UI_COOP_MY_NOTE", {"days": int(_co.rules().companions.valid_days)}), &"MutedLabel")


func _build_paste(col: VBoxContainer) -> void:
	var body := _card(col, tr("UI_COOP_PASTE_TITLE"))
	_paste = TextEdit.new()
	_paste.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_paste.custom_minimum_size = Vector2(0, 72)
	_paste.placeholder_text = tr("UI_COOP_PASTE_HINT")
	body.add_child(_paste)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	_btn(row, "UI_COOP_BTN_PASTE", _on_paste_clip)
	_btn(row, "UI_COOP_BTN_IMPORT", _on_import)
	_feedback = _lab(body, "", &"")


# ------------------------------------------------------------------ azioni

func _on_name(text: String) -> void:
	var n := _co.set_my_name(text)
	if _name_edit.text != n:
		_name_edit.text = n


func _on_copy_mine() -> void:
	_on_name(_name_edit.text)
	var code := _co.export_hero_code(_now())
	_code_out.text = code
	if code.is_empty():
		_copied.text = tr("UI_COOP_ERR_EXPORT")
		return
	_code_out.select_all()                       # anche a mano: Ctrl+C (o tasto destro) sul testo già selezionato
	if _clipboard_ok():
		DisplayServer.clipboard_set(code)
		_copied.text = tr("UI_COOP_COPIED")
	else:
		_copied.text = tr("UI_COOP_COPY_MANUAL")


func _clipboard_ok() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


func _on_paste_clip() -> void:
	if _clipboard_ok():
		_paste.text = DisplayServer.clipboard_get()


func _on_import() -> void:
	var r := _co.import_code(_paste.text, _now())
	if bool(r.ok):
		var msg := Loc.tf("UI_COOP_OK_" + str(r.status).to_upper(), {"name": str(r.name)})
		if int(r.clamped) > 0:
			msg += " " + tr("UI_COOP_CLAMPED")
		_feedback.text = msg
		_feedback.add_theme_color_override("font_color", NOTICE_COLOR_OK)
		_paste.text = ""
	else:
		_feedback.text = Loc.tf("UI_COOP_ERR_" + str(r.error).to_upper(), {"name": str(r.get("name", ""))})
		_feedback.add_theme_color_override("font_color", NOTICE_COLOR_BAD)
	_sig_comp = ""
	_sig_board = ""
	_reveal(_feedback)


## L'esito di «Importa» sta sotto la casella: a 1280x720 spesso oltre il bordo, e il clic sembrava non fare nulla (playtest
## novizio 121). Lo porta in vista (e, dopo un'importazione riuscita, mostra anche l'elenco dei compagni sotto).
func _reveal(c: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _scroll != null and is_instance_valid(_scroll) and is_instance_valid(c):
		_scroll.ensure_control_visible(c)


# ------------------------------------------------------------------ compagni

func _comp_signature() -> String:
	var parts := PackedStringArray([Loc.locale()])
	for c in _co.companions():
		parts.append("%s:%s:%s:%s:%s" % [c.id, c.enabled, c.expired, c.outdated, str(c.sig)])
	return "|".join(parts)


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _rebuild_companions() -> void:
	_clear(_comp_col)
	_lab(_comp_col, tr("UI_COOP_COMP_RULE"), &"MutedLabel", false)
	var list: Array = _co.companions()
	if list.is_empty():
		_lab(_comp_col, tr("UI_COOP_COMP_EMPTY"), &"MutedLabel", false)
		return
	for c in list:
		_add_companion_row(c)


func _class_name_of(cls: String) -> String:
	return Loc.t(DataRegistry.get_def("classes", cls).get("name", cls))


func _role_name(role: String) -> String:
	for r in DataRegistry.rules("mercenary_rules").roles:
		if str(r.id) == role:
			return Loc.t(r.name)
	return role


func _add_companion_row(c: Dictionary) -> void:
	var sh: Dictionary = c.sheet
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_comp_col.add_child(v)
	_lab(v, Loc.tf("UI_COOP_COMP_ROW", {"name": str(sh.name), "cls": _class_name_of(str(sh["class"])), "lv": int(sh.level),
		"role": _role_name(_co.role_of(c))}), &"SectionLabel")
	var st := _co.companion_status(c)
	var st_text := tr("UI_COOP_STATUS_" + st.to_upper())
	if bool(sh.get("cozy", false)):
		st_text += " " + tr("UI_COOP_BOARD_COZY")
	_lab(v, st_text, &"MutedLabel", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var chk := CheckButton.new()
	chk.text = tr("UI_COOP_COMP_ON")
	chk.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chk.button_pressed = bool(c.enabled)
	chk.disabled = bool(c.expired)
	chk.toggled.connect(func(on: bool) -> void:
		_co.set_enabled(str(c.id), on)
		_sig_comp = "")
	row.add_child(chk)
	_btn(row, "UI_COOP_COMP_REMOVE", func() -> void:
		_co.remove_companion(str(c.id))
		_sig_comp = "")


# ------------------------------------------------------------------ Prova della settimana

func _rebuild_week(wk: Dictionary, now: int) -> void:
	_clear(_week_col)
	var info := _co.week_info(now)
	var rd: Dictionary = info.get("rift", {})
	_lab(_week_col, Loc.tf("UI_COOP_WEEK_HEAD", {"id": str(wk.id), "name": Loc.t(rd.get("weekly_name", {}))}), &"SectionLabel")
	_lab(_week_col, tr("UI_COOP_WEEK_INFO"), &"MutedLabel", false)
	_lab(_week_col, Loc.tf("UI_COOP_WEEK_RESETS", {"t": NumberFormat.fmt_time(float(int(wk.end) - now))}), &"MutedLabel")
	for af in rd.get("affixes", []):
		_lab(_week_col, Loc.tf("UI_COOP_WEEK_AFFIX", {"fl": int(af.from_floor), "name": Loc.t(af.name)}), &"")
	var gm: Array = []
	for m in rd.get("guardian_mechanics", []):
		var md := DataRegistry.get_def("boss_mechanics", str(m))
		gm.append(Loc.t(md.get("name", m)) if not md.is_empty() else str(m))
	if not gm.is_empty():
		_lab(_week_col, Loc.tf("UI_COOP_WEEK_GUARD", {"list": ", ".join(PackedStringArray(gm))}), &"")
	var open_ok: bool = _co.rift_unlocked()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_week_col.add_child(row)
	var run := _btn(row, "UI_COOP_BTN_WEEK_RUN", _on_week_run)
	run.disabled = not open_ok
	if not open_ok:
		_lab(row, tr("UI_COOP_WEEK_LOCKED"), &"MutedLabel", false)
	var mine := _co.my_result(str(wk.id))
	if mine.is_empty():
		_lab(_week_col, tr("UI_COOP_WEEK_NONE"), &"MutedLabel", false)
	else:
		_lab(_week_col, Loc.tf("UI_COOP_WEEK_RESULT", {"fl": int(mine.floor), "t": NumberFormat.fmt_time(float(mine.t)),
			"dmg": NumberFormat.fmt(float(mine.dmg))}), &"")
		_btn(_week_col, "UI_COOP_BTN_COPY_RESULT", _on_copy_result.bind(str(wk.id)))
	if not _result_msg.is_empty():
		_lab(_week_col, _result_msg, &"MutedLabel")


func _on_week_run() -> void:
	var r := _co.weekly_run(_now())
	_result_msg = "" if r.is_empty() else tr("UI_COOP_WEEK_DONE")
	_sig_week = ""
	_sig_board = ""


func _on_copy_result(week_id: String) -> void:
	var code := _co.export_result_code(week_id)
	if code.is_empty():
		return
	if _clipboard_ok():
		DisplayServer.clipboard_set(code)
		_result_msg = tr("UI_COOP_COPIED")
	else:
		_result_msg = code
	_sig_week = ""


# ------------------------------------------------------------------ classifica locale

func _rebuild_board(week_id: String) -> void:
	_clear(_board_col)
	var rows := _co.leaderboard(week_id)
	_lab(_board_col, tr("UI_COOP_BOARD_NOTE"), &"MutedLabel", false)
	if rows.is_empty():
		_lab(_board_col, tr("UI_COOP_BOARD_EMPTY"), &"MutedLabel", false)
		return
	for r in rows:
		var text := Loc.tf("UI_COOP_BOARD_ROW", {"rank": int(r.rank), "name": str(r.name), "cls": _class_name_of(str(r["class"])),
			"lv": int(r.level), "fl": int(r.floor), "t": NumberFormat.fmt_time(float(r.t)), "dmg": NumberFormat.fmt(float(r.dmg))})
		if bool(r.get("cozy", false)):
			text += " " + tr("UI_COOP_BOARD_COZY")
		if bool(r.me):
			text += " " + tr("UI_COOP_BOARD_ME")
		_lab(_board_col, text, &"SectionLabel" if bool(r.me) else &"")
