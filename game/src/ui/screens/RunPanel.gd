class_name RunPanel
extends PanelContainer
## Riquadro della Corsa a scelte nella schermata Combattimento (CORSA, resoconto 91). Solo presentazione: legge RunSystem e
## chiama choose/reroll/banish/set_mode/move_family. Si aggiorna da solo a 10 Hz; nascosto finché la Corsa è bloccata.

const REFRESH_S := 0.1
const COL_GAIN := Color("7fcf8a")
const COL_COST := Color("e08a7a")
const COL_FAMILY := {"offense": Color("e0a050"), "defense": Color("6fa8dc"), "loot": Color("e0c050"), "technique": Color("b48ee0")}

var _run: RunSystem
var _acc: float = 0.0
var _title: Label
var _auto: CheckButton
var _progress: Label
var _bar: ProgressBar
var _picks: Label
var _info: Label
var _offer_box: VBoxContainer
var _offer_title: Label
var _cards: HBoxContainer
var _reroll: Button
var _timer: Label
var _order_lbl: Label
var _order_row: HFlowContainer
var _offer_sig: String = ""
var _order_sig: String = ""


func _ready() -> void:
	_run = Game.system("run") as RunSystem
	theme_type_variation = &"CardPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	_title = CombatUi.label("UI_RUN_TITLE", "SectionLabel")
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(_title)
	_progress = CombatUi.text_label("MutedLabel", true)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_progress)
	_auto = CheckButton.new()
	_auto.text = "UI_RUN_MODE_AUTO"
	_auto.tooltip_text = tr("UI_RUN_MODE_TIP")
	_auto.toggled.connect(func(on: bool) -> void:
		if _run != null:
			_run.set_mode("auto" if on else "ask"))
	head.add_child(_auto)
	_bar = CombatUi.bar(Color("c8a24a"), 10.0)
	v.add_child(_bar)
	_picks = CombatUi.text_label("", true)
	_picks.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_picks)
	_info = CombatUi.text_label("MutedLabel", true)
	v.add_child(_info)
	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 6)
	v.add_child(_offer_box)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 8)
	_offer_box.add_child(orow)
	_offer_title = CombatUi.text_label("SectionLabel")
	_offer_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_offer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orow.add_child(_offer_title)
	_reroll = Button.new()
	_reroll.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_reroll.tooltip_text = tr("UI_RUN_REROLL_TIP")
	_reroll.pressed.connect(func() -> void:
		if _run != null and _run.reroll():
			_refresh(true))
	orow.add_child(_reroll)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	_offer_box.add_child(_cards)
	_timer = CombatUi.text_label("MutedLabel", true)
	_offer_box.add_child(_timer)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	v.add_child(prow)
	_order_lbl = CombatUi.text_label("MutedLabel", true)
	_order_lbl.tooltip_text = tr("UI_RUN_ORDER_TIP")
	_order_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	_order_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_order_lbl)
	_order_row = HFlowContainer.new()
	_order_row.add_theme_constant_override("h_separation", 4)
	prow.add_child(_order_row)
	_refresh(true)


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= REFRESH_S:
		_acc = 0.0
		_refresh(false)


func _fam_name(fid: String) -> String:
	if _run == null:
		return fid
	for f in _run.rule("families"):
		if str(f.id) == fid:
			return Loc.t(f.name)
	return fid


static func mod_line(m: Dictionary) -> String:
	var fam := str(m.key).split(":")[0]
	var v := float(m.value)
	var num := ("+" if v >= 0.0 else "−") + NumberFormat.fmt(absf(v))
	return Loc.tf("UI_RUN_MOD_" + fam.to_upper(), {"v": num})


func _mods_bb(mods: Array) -> String:
	var lines := PackedStringArray()
	for m in mods:
		var col := COL_GAIN if _run.is_gain(m) else COL_COST
		lines.append("[color=#%s]%s[/color]" % [col.to_html(false), mod_line(m)])
	return "\n".join(lines)


func _refresh(force: bool) -> void:
	if _run == null or not is_inside_tree():
		return
	var st := _run.status()
	visible = str(st.phase) != "locked"
	if not visible:
		return
	_title.tooltip_text = Loc.tf("UI_RUN_HINT", {"k": int(st.per_choice), "o": int(_run.rule("offers")), "max": int(st.max)})
	_auto.set_pressed_no_signal(str(st.mode) == "auto")
	var n := int(st.picks)
	if n >= int(st.max):
		_progress.text = Loc.tf("UI_RUN_PROGRESS_FULL", {"n": n, "max": int(st.max)})
		CombatUi.set_bar(_bar, 1.0)
	else:
		_progress.text = Loc.tf("UI_RUN_PROGRESS", {"n": n, "max": int(st.max), "k": maxi(0, int(st.per_choice) - int(st.kills))})
		CombatUi.set_bar(_bar, float(st.kills) / maxf(1.0, float(st.per_choice)))
	# voci prese
	var stk := _run.stacks()
	if stk.is_empty():
		_picks.text = tr("UI_RUN_PICKS_NONE")
		_picks.tooltip_text = ""
	else:
		var names := PackedStringArray()
		for pid in stk:
			var nm := Loc.t(_run.perk(str(pid)).get("name", pid))
			names.append(nm + (" ×%d" % int(stk[pid]) if int(stk[pid]) > 1 else ""))
		_picks.text = Loc.tf("UI_RUN_PICKS", {"list": ", ".join(names)})
		var tl := PackedStringArray([tr("UI_RUN_TOTAL_TIP")])
		for m in _run.current_mods():
			tl.append(mod_line(m))
		_picks.tooltip_text = "\n".join(tl)
	# stato: pausa, Campione, ultima Corsa
	var zname := Loc.t(DataRegistry.get_def("zones", str(st.zone)).get("name", ""))
	var info := ""
	match str(st.phase):
		"paused":
			info = Loc.tf("UI_RUN_PAUSED", {"zone": zname, "n": n}) if not str(st.zone).is_empty() and n > 0 else tr("UI_RUN_PAUSED_NONE")
	var ch := str(st.champion)
	if ch == "due":
		info = Loc.tf("UI_RUN_CHAMPION_DUE", {"hp": NumberFormat.fmt(float(_run.rule("champion.hp_mult"))), "r": NumberFormat.fmt(float(_run.rule("champion.reward_mult")))})
	elif ch == "fighting":
		info = tr("UI_RUN_CHAMPION_FIGHT")
	elif ch == "wait":
		info = Loc.tf("UI_RUN_CHAMPION_WAIT", {"k": maxi(0, int(st.per_choice) - int(st.champ_kills))})
	if info.is_empty():
		var hist: Array = _run.state.history
		if not hist.is_empty():
			var h0: Dictionary = hist[0]
			info = Loc.tf("UI_RUN_LAST", {"zone": Loc.t(DataRegistry.get_def("zones", str(h0.zone)).get("name", "")), "n": int(h0.picks),
				"end": tr("UI_RUN_END_" + str(h0.end).to_upper())})
	_info.text = info
	_info.visible = not info.is_empty()
	# offerta
	var off: Array = st.offer
	_offer_box.visible = not off.is_empty()
	if not off.is_empty():
		var auto_i := _run.auto_index()
		var sig := "%s|%d|%d" % [",".join(PackedStringArray(off)), auto_i, _run.banishes_left()]
		if force or sig != _offer_sig:
			_offer_sig = sig
			_build_cards(off, auto_i)
		_offer_title.text = Loc.tf("UI_RUN_OFFER_TITLE", {"n": n + 1, "max": int(st.max)})
		_offer_title.tooltip_text = Loc.tf("UI_RUN_ODDS", {"p": "1/%d" % maxi(1, _available_count())})
		_reroll.text = Loc.tf("UI_RUN_REROLL", {"n": int(st.rerolls_left)})
		_reroll.disabled = int(st.rerolls_left) <= 0
		_timer.visible = str(st.mode) == "ask" and auto_i >= 0
		if _timer.visible:
			_timer.text = Loc.tf("UI_RUN_OFFER_TIMER", {"s": int(ceilf(float(st.offer_left_s))),
				"name": Loc.t(_run.perk(str(off[auto_i])).get("name", ""))})
	else:
		_offer_sig = ""
	# priorità
	var fam_order := _run.effective_order()
	var osig := ",".join(PackedStringArray(_run.state.order)) + "|" + ",".join(PackedStringArray(fam_order))
	if force or osig != _order_sig:
		_order_sig = osig
		var names2 := PackedStringArray()
		for f in fam_order:
			names2.append(_fam_name(str(f)))
		_order_lbl.text = Loc.tf("UI_RUN_ORDER", {"list": " › ".join(names2)})
		CombatUi.clear_children(_order_row)
		var own: Array = _run.state.order
		for i in range(1, own.size()):
			var fid := str(own[i])
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = "▲ " + _fam_name(fid)
			b.tooltip_text = Loc.tf("UI_RUN_ORDER_UP", {"name": _fam_name(fid)})
			b.pressed.connect(func() -> void:
				_run.move_family(fid, -1)
				_refresh(true))
			_order_row.add_child(b)


func _available_count() -> int:
	var n := 0
	var stk := _run.stacks()
	for p in DataRegistry.table("run_perks"):
		if not (_run.state.banned as Array).has(str(p.id)) and int(stk.get(str(p.id), 0)) < int(_run.rule("max_stacks")):
			n += 1
	return n


func _build_cards(off: Array, auto_i: int) -> void:
	CombatUi.clear_children(_cards)
	for i in off.size():
		var p := _run.perk(str(off[i]))
		var card := PanelContainer.new()
		card.theme_type_variation = &"ContentPanel"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cards.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		card.add_child(cv)
		var name_l := CombatUi.text_label("SectionLabel", true)
		name_l.text = Loc.t(p.get("name", ""))
		cv.add_child(name_l)
		var fam_l := CombatUi.text_label("", true)
		var fid := str(p.get("family", ""))
		fam_l.text = _fam_name(fid)
		fam_l.add_theme_color_override("font_color", COL_FAMILY.get(fid, Color.WHITE))
		cv.add_child(fam_l)
		var mods := RichTextLabel.new()
		mods.bbcode_enabled = true
		mods.fit_content = true
		mods.scroll_active = false
		mods.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		mods.text = _mods_bb(p.get("modifiers", []))
		cv.add_child(mods)
		var desc := CombatUi.text_label("MutedLabel", true)
		desc.text = Loc.t(p.get("desc", ""))
		cv.add_child(desc)
		if i == auto_i:
			var mark := CombatUi.text_label("MutedLabel", true)
			mark.text = tr("UI_RUN_AUTO_MARK")
			cv.add_child(mark)
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 6)
		cv.add_child(brow)
		var take := Button.new()
		take.text = "UI_RUN_TAKE"
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == auto_i:
			take.theme_type_variation = &"AccentButton"
		var idx := i
		take.pressed.connect(func() -> void:
			if _run.choose(idx):
				_refresh(true))
		brow.add_child(take)
		if _run.banishes_left() > 0:
			var ban := Button.new()
			ban.text = "UI_RUN_BANISH"
			ban.tooltip_text = Loc.tf("UI_RUN_BANISH_TIP", {"n": _run.banishes_left()})
			ban.pressed.connect(func() -> void:
				if _run.banish(idx):
					_refresh(true))
			brow.add_child(ban)
