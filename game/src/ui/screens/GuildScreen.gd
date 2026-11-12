extends GameScreen
## Gilda (docs/11 §5-6, docs/16): schede Apprendisti · Mercenari · Spedizioni. Solo presentazione: legge e comanda
## ApprenticeSystem / MercenarySystem / ExpeditionSystem. Rischio e ricompensa di una spedizione sono SEMPRE visibili
## prima di partire (anteprima = stessi calcoli usati all'estrazione). Aggiornata a ≤10 Hz; le sezioni si ricostruiscono
## solo se cambia la loro firma. Animazioni: tween (impulso alla pressione di un pulsante), niente se "riduci animazioni".
## Restyling UX (110): «a cosa serve» + «cosa fare ora» per scheda, carte con bordo, numeri chiave con unità, stati vuoti con Vai,
## motivo accanto ai pulsanti disattivi, Congeda a due passi. Params: {"tab": 0|1|2} apre la scheda indicata.

const COL_BAD := "#e07070"
const COL_OK := "#a0d8a0"
const PULSE_S := 0.22
const DISMISS_ARM_S := 4.0
const MERC_COLORS := {"common": "#9aa0aa", "uncommon": "#7fb08a"}      # le altre rarità usano i colori del progetto (CrateUi)

var _es: EstateSystem
var _ap: ApprenticeSystem
var _mc: MercenarySystem
var _ex: ExpeditionSystem
var _tabs: TabContainer
var _hint: ScreenKit.KitHint

# Apprendisti
var _ap_stats: HFlowContainer
var _ap_st_slots: ScreenKit.KitStat
var _ap_st_active: ScreenKit.KitStat
var _ap_st_eff: ScreenKit.KitStat
var _ap_box: GridContainer
var _ap_sig := ""
var _ap_rows: Array = []
var _ap_skill_sel: Dictionary = {}
var _ap_skills: Array = []

# Mercenari
var _mc_stats: Control
var _mc_board_sec: Control
var _mc_st_roster: ScreenKit.KitStat
var _mc_st_gold: ScreenKit.KitStat
var _mc_roster_box: VBoxContainer
var _mc_board_box: VBoxContainer
var _mc_roster_sig := ""
var _mc_board_sig := ""
var _mc_dyn: Array = []
var _mc_board_info: Label
var _reroll_btn: Button
var _reroll_reason: Label
var _armed_dismiss := ""

# Spedizioni
var _ex_stats: Control
var _ex_board_head: Control
var _ex_st_active: ScreenKit.KitStat
var _ex_active_box: VBoxContainer
var _ex_board_box: VBoxContainer
var _ex_detail: VBoxContainer
var _ex_active_sig := ""
var _ex_board_sig := ""
var _ex_detail_sig := ""
var _ex_dyn: Array = []
var _selected_offer := ""
var _team_checks: Dictionary = {}
var _preview_label: RichTextLabel
var _pv_power: ScreenKit.KitStat
var _pv_success: ScreenKit.KitStat
var _pv_time: ScreenKit.KitStat
var _pv_bar: SmoothBar
var _start_btn: Button
var _start_reason: Label
var _ex_log_box: VBoxContainer
var _ex_log_sig := ""


func open(params: Dictionary) -> void:
	_es = Game.system("estate") as EstateSystem
	_ap = Game.system("apprentices") as ApprenticeSystem
	_mc = Game.system("mercenaries") as MercenarySystem
	_ex = Game.system("expeditions") as ExpeditionSystem
	var title := Label.new()
	ScreenKit.title_style(title)
	title.text = "UI_MENU_GUILD"
	add_child(title)
	if _es == null or _ap == null or _mc == null or _ex == null:
		var l := Label.new()
		l.text = "UI_GUILD_NO_SYSTEM"
		add_child(l)
		return
	_hint = ScreenKit.intro(self, "UI_RS_GU_PURPOSE", "guild")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_tabs.add_child(_scroll_tab("UI_GUILD_TAB_APPRENTICES", _build_apprentices))
	_tabs.add_child(_scroll_tab("UI_GUILD_TAB_MERCS", _build_mercs))
	_tabs.add_child(_scroll_tab("UI_GUILD_TAB_EXPEDITIONS", _build_expeditions))
	_tabs.set_tab_title(0, tr("UI_GUILD_TAB_APPRENTICES"))
	_tabs.set_tab_title(1, tr("UI_GUILD_TAB_MERCS"))
	_tabs.set_tab_title(2, tr("UI_GUILD_TAB_EXPEDITIONS"))
	_tabs.set_tab_tooltip(0, tr("UI_RS_GU_TIP_TAB_AP"))
	_tabs.set_tab_tooltip(1, tr("UI_RS_GU_TIP_TAB_MC"))
	_tabs.set_tab_tooltip(2, tr("UI_RS_GU_TIP_TAB_EX"))
	_tabs.tab_changed.connect(func(_i: int) -> void: refresh())
	if params.has("tab"):
		_tabs.current_tab = clampi(int(params.tab), 0, 2)
	refresh()


func _scroll_tab(tab_name: String, builder: Callable) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	builder.call(col)
	return sc


func _label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != "":
		l.theme_type_variation = StringName(variation)
	parent.add_child(l)
	return l


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.queue_free()


func _pulse(c: Control) -> void:
	if Settings.get_value("reduce_motion") or not is_inside_tree() or c == null:
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate", Color(1.5, 1.4, 0.9), PULSE_S)
	tw.tween_property(c, "modulate", Color.WHITE, PULSE_S)


func _item_name(id: String) -> String:
	return Loc.t(DataRegistry.item(id).get("name", id))


func _rarity_name(rarity: String) -> String:
	return tr("UI_GUILD_RARITY_" + rarity.to_upper())


func _rarity_color(rarity: String) -> Color:
	return Color(MERC_COLORS[rarity]) if MERC_COLORS.has(rarity) else CrateUi.rarity_color(rarity)


func _role_name(role: String) -> String:
	return Loc.t(_mc.role_name(role))


## Id dell'edificio di un tipo (Accademia = apprentices, Taverna = guild), per i pulsanti «Vai a costruirla».
func _building_of(btype: String) -> String:
	for bid in _es.building_ids():
		if _es.type_of(bid) == btype:
			return str(bid)
	return ""


## Stato vuoto «costruisci l'edificio»: cosa manca, perché serve, pulsante Vai alla Tenuta (carta dell'edificio in vista).
func _need_building(parent: Control, btype: String, what_key: String, why_key: String) -> void:
	var bid := _building_of(btype)
	var acts: Array = []
	if bid != "" and ScreenKit.available("estate"):
		acts.append([tr("UI_RS_GU_GO_BUILD"), ScreenKit.target("estate", {"building": bid})])
	ScreenKit.empty(parent, tr(what_key), tr(why_key), acts, "shelf")


# ================================================================== APPRENDISTI

func _build_apprentices(col: VBoxContainer) -> void:
	_ap_stats = ScreenKit.stat_row(col)
	_ap_st_slots = ScreenKit.stat(_ap_stats, "UI_RS_GU_AP_ST_SLOTS", "UI_RS_GU_AP_TIP_SLOTS")
	_ap_st_active = ScreenKit.stat(_ap_stats, "UI_RS_GU_AP_ST_ACTIVE", "UI_RS_GU_AP_TIP_ACTIVE")
	_ap_st_eff = ScreenKit.stat(_ap_stats, "UI_RS_GU_AP_ST_EFF", "UI_RS_GU_AP_TIP_EFF")
	_ap_box = GridContainer.new()                  # apprendisti a DUE colonne: una carta sola non si stira a tutta la pagina
	_ap_box.columns = 2
	_ap_box.add_theme_constant_override("h_separation", 8)
	_ap_box.add_theme_constant_override("v_separation", 8)
	_ap_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_ap_box)


func _refresh_apprentices() -> void:
	var n := _ap.slots_total()
	_ap_stats.visible = n > 0
	if n > 0:
		_ap_st_slots.set_value(str(n), "")
		_ap_st_slots.set_caption(Loc.tf("UI_RS_GU_AP_CAP_SLOTS", {"lv": _ap.academy_level()}))
		_ap_st_active.set_value("%d / %d" % [_ap.active_count(), n], "")
		_ap_st_eff.set_value(NumberFormat.fmt(100.0 * _ap.efficiency()), "%")
		_ap_st_eff.set_caption(tr("UI_RS_GU_AP_CAP_EFF"))
	var sig_parts := PackedStringArray([str(n)])
	for i in n:
		sig_parts.append(_ap.slot_action(i))
	var sig := "|".join(sig_parts)
	if sig != _ap_sig:
		_ap_sig = sig
		_rebuild_ap_rows(n)
	for r in _ap_rows:
		var i: int = r.i
		(r.bar as SmoothBar).set_target(_ap.slot_progress(i), 0.0)
		var aid := _ap.slot_action(i)
		var stalled := aid != "" and _ap.slot_stalled(i)
		if aid == "":
			ScreenKit.set_pill(r.pill, tr("UI_RS_GU_ST_IDLE"), Color(ScreenKit.TEXT_DIM))
			(r.info as Label).text = tr("UI_RS_GU_AP_IDLE")
			(r.st_c as ScreenKit.KitStat).set_value("-", "")
			(r.st_xp as ScreenKit.KitStat).set_value("-", "")
		else:
			var hr := _ap.hourly(aid)
			(r.st_c as ScreenKit.KitStat).set_value(NumberFormat.fmt(float(hr.get("cycles", 0.0))), tr("UI_RS_GU_UNIT_CYCLES_H"))
			(r.st_xp as ScreenKit.KitStat).set_value(NumberFormat.fmt(float(hr.get("xp", 0.0))), tr("UI_RS_GU_UNIT_XP_H"))
			ScreenKit.set_pill(r.pill, tr("UI_RS_GU_ST_STALLED") if stalled else tr("UI_RS_GU_ST_WORKING"), Color(ScreenKit.WARN) if stalled else Color(ScreenKit.GOOD))
			(r.info as Label).text = (tr("UI_RS_GU_AP_STALLED_WHY") + "\n" + ReqText.missing_inputs_text(DataRegistry.action(aid).get("inputs", []))).strip_edges() if stalled else ""      # con quanto manca
			(r.info as Label).visible = stalled
		if aid == "":
			(r.info as Label).visible = true


func _rebuild_ap_rows(n: int) -> void:
	_clear(_ap_box)
	_ap_rows.clear()
	if n <= 0:
		_need_building(_ap_box, "apprentices", "UI_RS_GU_AP_NONE", "UI_RS_GU_AP_NONE_WHY")
		return
	_ap_skills = _eligible_skills()
	for i in n:
		var cur := _ap.slot_action(i)
		var v := ScreenKit.card(_ap_box, Color(ScreenKit.EDGE), 4)
		var panel := ScreenKit.panel_of(v)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		var nm := _label(top, Loc.tf("UI_GUILD_AP_SLOT", {"n": i + 1}), "SectionLabel")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pill := ScreenKit.pill("", Color(ScreenKit.TEXT_DIM))
		top.add_child(pill)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var cur_skill := str(DataRegistry.action(cur).get("skill", "")) if cur != "" else str(_ap_skill_sel.get(i, ""))
		var so := OptionButton.new()
		so.custom_minimum_size = Vector2(160, 0)
		so.tooltip_text = tr("UI_RS_GU_AP_TIP_SKILL")
		so.add_item(tr("UI_GUILD_AP_PICK_SKILL"))
		so.set_item_metadata(0, "")
		var sel := 0
		for k in _ap_skills.size():
			so.add_item(Loc.t(DataRegistry.get_def("skills", str(_ap_skills[k])).get("name", {})))
			so.set_item_metadata(k + 1, _ap_skills[k])
			if str(_ap_skills[k]) == cur_skill:
				sel = k + 1
		so.select(sel)
		row.add_child(so)
		var ao := OptionButton.new()
		ao.custom_minimum_size = Vector2(220, 0)
		ao.tooltip_text = tr("UI_RS_GU_AP_TIP_ACTION") if cur_skill != "" else tr("UI_RS_GU_AP_TIP_ACTION_LOCK")
		row.add_child(ao)
		var acts: Array = _actions_for(cur_skill)
		ao.add_item(tr("UI_GUILD_AP_PICK_ACTION"))
		ao.set_item_metadata(0, "")
		var asel := 0
		for k in acts.size():
			ao.add_item(Loc.t(DataRegistry.action(str(acts[k])).get("name", {})))
			ao.set_item_metadata(k + 1, acts[k])
			if str(acts[k]) == cur:
				asel = k + 1
		ao.select(asel)
		ao.disabled = cur_skill == ""
		so.item_selected.connect(func(idx: int) -> void:
			_ap_skill_sel[i] = str(so.get_item_metadata(idx))
			if cur != "":
				_ap.unassign(i)
			_ap_sig = "")
		ao.item_selected.connect(func(idx: int) -> void:
			var aid := str(ao.get_item_metadata(idx))
			if aid == "":
				_ap.unassign(i)
			else:
				_ap.assign(i, aid)
			_pulse(panel)
			_ap_sig = "")
		var nums := ScreenKit.stat_row(v)
		var st_c := ScreenKit.stat(nums, "UI_RS_GU_AP_ST_CYCLES", "UI_RS_GU_AP_TIP_CYCLES", Color(ScreenKit.GOLD))
		var st_xp := ScreenKit.stat(nums, "UI_RS_GU_AP_ST_XP", "UI_RS_GU_AP_TIP_XP", Color(ScreenKit.GOLD))
		var bar := ScreenKit.bar(v, Color("#8CCB4E"), 10)
		var info := ScreenKit.muted("")
		v.add_child(info)
		ScreenKit.set_edge(v, Color("#5f8f5f") if cur != "" else Color(ScreenKit.EDGE))
		_ap_rows.append({"i": i, "bar": bar, "info": info, "pill": pill, "st_c": st_c, "st_xp": st_xp})


func _eligible_skills() -> Array:
	var out: Array = []
	for s in DataRegistry.table("skills"):
		var g := str(s.get("group", ""))
		if (ApprenticeSystem.tuning().groups as Array).has(g) and (Game.system("skills") as SkillSystem).is_unlocked(str(s.id)):
			out.append(str(s.id))
	return out


func _actions_for(skill_id: String) -> Array:
	var out: Array = []
	if skill_id == "":
		return out
	for a in DataRegistry.actions_for_skill(skill_id):
		if _ap.can_assign(str(a.id)) == "":
			out.append(str(a.id))
	return out


# ================================================================== MERCENARI

func _build_mercs(col: VBoxContainer) -> void:
	_mc_stats = ScreenKit.stat_row(col)
	var stats := _mc_stats
	_mc_st_roster = ScreenKit.stat(stats, "UI_RS_GU_MC_ST_ROSTER", "UI_RS_GU_MC_TIP_ROSTER")
	_mc_st_gold = ScreenKit.stat(stats, "UI_RS_GU_MC_ST_GOLD", "UI_RS_GU_MC_TIP_GOLD")
	ScreenKit.section(col, "UI_GUILD_MC_ROSTER", "UI_RS_GU_MC_ROSTER_SUB")
	_mc_roster_box = VBoxContainer.new()
	_mc_roster_box.add_theme_constant_override("separation", 6)
	col.add_child(_mc_roster_box)
	_mc_board_sec = VBoxContainer.new()
	_mc_board_sec.add_theme_constant_override("separation", 8)
	col.add_child(_mc_board_sec)
	ScreenKit.section(_mc_board_sec, "UI_GUILD_MC_BOARD", "UI_RS_GU_MC_BOARD_SUB")
	_mc_board_info = ScreenKit.muted("")
	_mc_board_sec.add_child(_mc_board_info)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	_mc_board_sec.add_child(rr)
	_reroll_btn = Button.new()
	_reroll_btn.pressed.connect(func() -> void:
		if _mc.reroll():
			_pulse(_mc_board_box)
		_mc_board_sig = "")
	rr.add_child(_reroll_btn)
	_reroll_reason = ScreenKit.reason_label()
	_reroll_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll_reason.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(_reroll_reason)
	_mc_board_box = VBoxContainer.new()
	_mc_board_box.add_theme_constant_override("separation", 6)
	_mc_board_sec.add_child(_mc_board_box)


## Tratti come righe separate (una per tratto) con il loro effetto in numeri: niente riga unica illeggibile.
func _trait_lines(parent: Control, m: Dictionary) -> void:
	for t in m.traits:
		var td := _mc.trait_def(str(t))
		var eff: Array = []
		for k in td.get("effect", {}):
			eff.append(Loc.tf("UI_GUILD_EFF_" + str(k).to_upper(), {"v": NumberFormat.fmt(absf(float(td.effect[k]))),
				"s": "+" if float(td.effect[k]) >= 0.0 else "-"}))
		var l := ScreenKit.label("• %s: %s" % [Loc.t(td.get("name", {})), ", ".join(PackedStringArray(eff))], "MutedLabel")
		parent.add_child(l)


func _refresh_mercs() -> void:
	var tl := _mc.tavern_level()
	_mc_stats.visible = tl > 0
	_mc_board_sec.visible = tl > 0
	_mc_st_roster.set_value("%d / %d" % [_mc.roster().size(), _mc.roster_cap()], "")
	_mc_st_gold.set_value(NumberFormat.fmt(_gold()), tr("UI_ESTATE_GOLD"))
	var rsig := PackedStringArray([str(tl)])
	for m in _mc.roster():
		rsig.append("%s:%d:%d:%s" % [m.uid, int(m.level), int(m.equip_tier), "b" if _mc.is_busy(str(m.uid)) else ("i" if _mc.is_injured(str(m.uid)) else "o")])
		rsig.append("k" if _mc.can_equip_kit(str(m.uid), int(m.equip_tier) + 1) else "-")
	var sig := ",".join(rsig)
	if sig != _mc_roster_sig:
		_mc_roster_sig = sig
		_rebuild_roster()
	var bsig := PackedStringArray([str(tl)])
	for c in _mc.candidates():
		bsig.append(str(c.uid))
		bsig.append(_mc.can_hire(str(c.uid)))
	bsig.append(str(_gold() >= _mc.reroll_cost()))
	var bs := ",".join(bsig)
	if bs != _mc_board_sig:
		_mc_board_sig = bs
		_rebuild_board()
	_mc_board_info.text = Loc.tf("UI_GUILD_MC_NEXT", {"t": NumberFormat.fmt_time(_mc.board_next_s())}) if tl > 0 else ""
	_mc_board_info.visible = tl > 0
	_reroll_btn.text = Loc.tf("UI_GUILD_MC_REROLL", {"cost": NumberFormat.fmt(_mc.reroll_cost())})
	var why := ""
	if tl <= 0:
		why = tr("UI_GUILD_REASON_NOTAVERN")
	elif not _mc.can_reroll():
		why = tr("UI_RS_GU_REROLL_GOLD")
	ScreenKit.gate(_reroll_btn, why, _reroll_reason)
	_reroll_btn.tooltip_text = tr("UI_RS_GU_REROLL_TIP") if why == "" else why
	for d in _mc_dyn:
		var m := _mc.get_merc(str(d.uid))
		if m.is_empty():
			continue
		_paint_status(d.pill, str(d.uid))
		(d.xp as ProgressBar).max_value = _mc.xp_to_next(int(m.level))
		(d.xp as ProgressBar).value = float(m.xp)


func _gold() -> int:
	var b := Game.system("bank") as BankSystem
	return 0 if b == null else b.gold()


func _paint_status(pill: Control, uid: String) -> void:
	if _mc.is_busy(uid):
		ScreenKit.set_pill(pill, tr("UI_GUILD_ST_BUSY"), Color("#7fc8ff"))
	elif _mc.is_injured(uid):
		ScreenKit.set_pill(pill, Loc.tf("UI_GUILD_ST_INJURED", {"t": NumberFormat.fmt_time(_mc.injured_left(uid))}), Color(ScreenKit.BAD))
	else:
		ScreenKit.set_pill(pill, tr("UI_GUILD_ST_READY"), Color(ScreenKit.GOOD))


func _rebuild_roster() -> void:
	_clear(_mc_roster_box)
	_mc_dyn.clear()
	if _mc.tavern_level() <= 0:
		_need_building(_mc_roster_box, "guild", "UI_RS_GU_NOTAVERN", "UI_RS_GU_NOTAVERN_WHY")
		return
	if _mc.roster().is_empty():
		var acts: Array = []
		ScreenKit.empty(_mc_roster_box, tr("UI_RS_GU_MC_EMPTY"), tr("UI_RS_GU_MC_EMPTY_WHY"), acts, "shelf")
		return
	for m in _mc.roster():
		var uid := str(m.uid)
		var col := _rarity_color(str(m.rarity))
		var v := ScreenKit.card(_mc_roster_box, col, 4)
		var panel := ScreenKit.panel_of(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		var head := Label.new()
		head.theme_type_variation = &"SectionLabel"
		head.text = str(m.name)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(head)
		top.add_child(ScreenKit.pill(_role_name(str(m.role)), Color("#8a8f9a"), tr("UI_RS_GU_TIP_ROLE")))
		top.add_child(ScreenKit.pill(_rarity_name(str(m.rarity)), col, tr("UI_RS_GU_TIP_RARITY")))
		var status := ScreenKit.pill("", Color(ScreenKit.GOOD))
		top.add_child(status)
		var nums := ScreenKit.stat_row(v)
		var s1 := ScreenKit.stat(nums, "UI_RS_GU_MC_ST_LEVEL", "UI_RS_GU_MC_TIP_LEVEL", Color(ScreenKit.GOLD))
		s1.set_value("%d" % int(m.level), "/ %d" % _mc.max_level(m))
		var s2 := ScreenKit.stat(nums, "UI_RS_GU_MC_ST_POWER", "UI_RS_GU_MC_TIP_POWER", Color(ScreenKit.GOLD))
		s2.set_value(NumberFormat.fmt(_mc.power_of(m)), "")
		var s3 := ScreenKit.stat(nums, "UI_RS_GU_MC_ST_KIT", "UI_RS_GU_MC_TIP_KIT", Color(ScreenKit.GOLD))
		s3.set_value("%d" % int(m.equip_tier), tr("UI_RS_GU_UNIT_TIER"))
		_trait_lines(v, m)
		var xp := ScreenKit.bar(v, Color("#4FA8F5"), 8)
		xp.tooltip_text = tr("UI_RS_GU_MC_TIP_XP")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var next_t := int(m.equip_tier) + 1
		var kit := Button.new()
		kit.text = Loc.tf("UI_GUILD_MC_KIT", {"t": next_t})
		var kit_reason := ""
		if next_t > int(MercenarySystem.tuning().equip_tier_max):
			kit_reason = tr("UI_RS_GU_KIT_MAX")
		elif not _mc.can_equip_kit(uid, next_t):
			kit_reason = Loc.tf("UI_RS_GU_KIT_MISSING", {"t": next_t})
		ScreenKit.gate(kit, kit_reason)
		if kit_reason == "":
			kit.tooltip_text = tr("UI_GUILD_MC_KIT_TIP")
		kit.pressed.connect(func() -> void:
			if _mc.equip_kit(uid, next_t):
				_pulse(panel)
			_mc_roster_sig = "")
		row.add_child(kit)
		var kr := ScreenKit.reason_label()
		kr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kr.theme_type_variation = &"MutedLabel"
		kr.remove_theme_color_override("font_color")
		kr.visible = kit_reason != ""
		kr.text = kit_reason
		row.add_child(kr)
		var bye := Button.new()
		bye.flat = true
		bye.text = "UI_GUILD_MC_DISMISS"
		bye.disabled = _mc.is_busy(uid)
		bye.tooltip_text = tr("UI_RS_GU_DISMISS_BUSY") if bye.disabled else tr("UI_RS_GU_DISMISS_TIP")
		bye.pressed.connect(func() -> void: _on_dismiss(uid, bye))
		row.add_child(bye)
		_mc_dyn.append({"uid": uid, "pill": status, "xp": xp})


## Congedare è definitivo: due passi (la prima pressione chiede conferma e si disarma da sola).
func _on_dismiss(uid: String, btn: Button) -> void:
	if _armed_dismiss == uid:
		_armed_dismiss = ""
		_mc.dismiss(uid)
		_mc_roster_sig = ""
		return
	_armed_dismiss = uid
	btn.text = tr("UI_RS_GU_DISMISS_SURE")
	btn.flat = false
	if is_inside_tree():
		get_tree().create_timer(DISMISS_ARM_S).timeout.connect(func() -> void:
			if _armed_dismiss == uid:
				_armed_dismiss = ""
				if is_instance_valid(btn):
					btn.text = tr("UI_GUILD_MC_DISMISS")
					btn.flat = true)


func _rebuild_board() -> void:
	_clear(_mc_board_box)
	if _mc.tavern_level() <= 0:
		return
	if _mc.candidates().is_empty():
		ScreenKit.empty(_mc_board_box, tr("UI_RS_GU_BOARD_EMPTY"), Loc.tf("UI_RS_GU_BOARD_EMPTY_WHY", {"t": NumberFormat.fmt_time(_mc.board_next_s())}))
		return
	for c in _mc.candidates():
		var uid := str(c.uid)
		var col := _rarity_color(str(c.rarity))
		var v := ScreenKit.card(_mc_board_box, col, 4)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 2)
		row.add_child(left)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		left.add_child(top)
		_label(top, str(c.name), "SectionLabel")
		top.add_child(ScreenKit.pill(_role_name(str(c.role)), Color("#8a8f9a"), tr("UI_RS_GU_TIP_ROLE")))
		top.add_child(ScreenKit.pill(_rarity_name(str(c.rarity)), col, tr("UI_RS_GU_TIP_RARITY")))
		var pw := ScreenKit.stat(left, "UI_RS_GU_MC_ST_POWER", "UI_RS_GU_MC_TIP_POWER", Color(ScreenKit.GOLD))
		pw.set_value(NumberFormat.fmt(_mc.power_of(c)), "")
		_trait_lines(left, c)
		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(170, 0)
		right.add_theme_constant_override("separation", 4)
		row.add_child(right)
		var b := Button.new()
		b.theme_type_variation = &"AccentButton"
		b.text = Loc.tf("UI_GUILD_MC_HIRE", {"cost": NumberFormat.fmt(_mc.hire_cost(str(c.rarity)))})
		var reason := _mc.can_hire(uid)
		var rl := ScreenKit.reason_label()
		ScreenKit.gate(b, tr(reason) if reason != "" else "", rl)
		b.pressed.connect(func() -> void:
			if _mc.hire(uid):
				_pulse(_mc_roster_box)
			_mc_board_sig = ""
			_mc_roster_sig = "")
		right.add_child(b)
		right.add_child(rl)


# ================================================================== SPEDIZIONI

func _build_expeditions(col: VBoxContainer) -> void:
	_ex_stats = ScreenKit.stat_row(col)
	_ex_st_active = ScreenKit.stat(_ex_stats, "UI_RS_GU_EX_ST_ACTIVE", "UI_RS_GU_EX_TIP_ACTIVE")
	ScreenKit.section(col, "UI_GUILD_EX_ACTIVE")
	_ex_active_box = VBoxContainer.new()
	_ex_active_box.add_theme_constant_override("separation", 6)
	col.add_child(_ex_active_box)
	_ex_board_head = VBoxContainer.new()
	col.add_child(_ex_board_head)
	ScreenKit.section(_ex_board_head, "UI_GUILD_EX_BOARD", "UI_RS_GU_EX_BOARD_SUB")
	_ex_board_box = VBoxContainer.new()
	_ex_board_box.add_theme_constant_override("separation", 6)
	col.add_child(_ex_board_box)
	_ex_detail = VBoxContainer.new()
	_ex_detail.add_theme_constant_override("separation", 6)
	col.add_child(_ex_detail)
	ScreenKit.section(col, "UI_GUILD_EX_LOG")
	_ex_log_box = VBoxContainer.new()
	_ex_log_box.add_theme_constant_override("separation", 4)
	col.add_child(_ex_log_box)


func _offer_title(o: Dictionary) -> String:
	return Loc.tf("UI_RS_GU_EX_OFFER", {"type": Loc.t(_ex.type_def(str(o.type)).get("name", {})),
		"zone": Loc.t(_ex.zone_def(str(o.zone)).get("name", {}))})


func _refresh_expeditions() -> void:
	var tl := _ex.tavern_level()
	_ex_stats.visible = tl > 0
	_ex_board_head.visible = tl > 0
	_ex_st_active.set_value("%d / %d" % [_ex.active().size(), _ex.concurrent_cap()], "")
	var asig := PackedStringArray([str(tl)])
	for a in _ex.active():
		asig.append(str(a.id))
	var as_ := ",".join(asig)
	if as_ != _ex_active_sig:
		_ex_active_sig = as_
		_rebuild_active()
	var bsig := PackedStringArray([str(tl)])
	for o in _ex.board():
		bsig.append(str(o.id))
	bsig.append(str(_ex.active().size() >= _ex.concurrent_cap()))
	bsig.append(_selected_offer)
	var bs := ",".join(bsig)
	if bs != _ex_board_sig:
		_ex_board_sig = bs
		_rebuild_ex_board()
	for d in _ex_dyn:
		(d.bar as SmoothBar).set_target(_ex.progress(str(d.id)), 0.0)
		(d.left as ScreenKit.KitStat).set_value(NumberFormat.fmt_time(_ex.time_left(str(d.id))), "")
	_refresh_detail()
	var lg: Array = _ex.log_entries()
	var lsig := "%d|%s" % [lg.size(), str(lg.back().get("id", "")) if not lg.is_empty() else ""]
	if lsig != _ex_log_sig:
		_ex_log_sig = lsig
		_clear(_ex_log_box)
		if lg.is_empty():
			ScreenKit.empty(_ex_log_box, tr("UI_RS_GU_EX_LOG_NONE"), tr("UI_RS_GU_EX_LOG_NONE_WHY"))
		for i in range(lg.size() - 1, maxi(-1, lg.size() - 5), -1):
			_log_card(lg[i])


func _log_card(r: Dictionary) -> void:
	var ok := bool(r.success)
	var v := ScreenKit.card(_ex_log_box, Color("#5f8f5f") if ok else Color("#a85a5a"), 4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(ScreenKit.pill(tr("UI_RS_GU_RES_OK") if ok else tr("UI_RS_GU_RES_FAIL"), Color(ScreenKit.GOOD) if ok else Color(ScreenKit.BAD)))
	_label(top, _offer_title(r), "MonoLabel")
	var rew := PackedStringArray()
	if int(r.gold) > 0:
		rew.append("%s %s" % [NumberFormat.fmt(int(r.gold)), tr("UI_ESTATE_GOLD")])
	for it in r.items:
		rew.append("%s ×%s" % [_item_name(str(it)), NumberFormat.fmt(int(r.items[it]))])
	for c in r.crates:
		rew.append("%s ×%s" % [_item_name(str(c)), NumberFormat.fmt(int(r.crates[c]))])
	for k in r.keys:
		rew.append("%s ×%s" % [_item_name(str(k)), NumberFormat.fmt(int(r.keys[k]))])
	v.add_child(ScreenKit.muted(tr("UI_RS_GU_RES_GOT") + " " + (", ".join(rew) if not rew.is_empty() else tr("UI_GUILD_EX_NOTHING"))))
	if not (r.injured as Array).is_empty():
		var l := ScreenKit.label(Loc.tf("UI_GUILD_EX_INJURED", {"who": ", ".join(PackedStringArray(r.injured))}), "MutedLabel", Color(ScreenKit.BAD))
		v.add_child(l)


func _rebuild_active() -> void:
	_clear(_ex_active_box)
	_ex_dyn.clear()
	if _ex.tavern_level() <= 0:
		_need_building(_ex_active_box, "guild", "UI_RS_GU_NOTAVERN", "UI_RS_GU_NOTAVERN_WHY")
		return
	if _ex.active().is_empty():
		ScreenKit.empty(_ex_active_box, tr("UI_RS_GU_EX_NONE_ACTIVE"), tr("UI_RS_GU_EX_NONE_ACTIVE_WHY"))
		return
	for a in _ex.active():
		var v := ScreenKit.card(_ex_active_box, Color("#7fc8ff"), 4)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		var t := _label(top, _offer_title(a), "SectionLabel")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var left := ScreenKit.stat(top, "UI_RS_GU_EX_ST_LEFT", "UI_RS_GU_EX_TIP_LEFT", Color("#7fc8ff"))
		var names := PackedStringArray()
		for u in a.team:
			names.append(str(_mc.get_merc(str(u)).get("name", "?")))
		v.add_child(ScreenKit.muted(Loc.tf("UI_GUILD_EX_TEAM", {"who": ", ".join(names), "p": NumberFormat.fmt_pct(100.0 * float(a.p_success))})))
		var bar := ScreenKit.bar(v, Color("#7fc8ff"), 12)
		_ex_dyn.append({"id": str(a.id), "bar": bar, "left": left})


func _rebuild_ex_board() -> void:
	_clear(_ex_board_box)
	if _ex.tavern_level() <= 0:
		return
	if _ex.board().is_empty():
		ScreenKit.empty(_ex_board_box, tr("UI_RS_GU_EX_BOARD_EMPTY"), tr("UI_RS_GU_EX_BOARD_EMPTY_WHY"))
		return
	var full := _ex.active().size() >= _ex.concurrent_cap()
	for o in _ex.board():
		var oid := str(o.id)
		var sel := oid == _selected_offer
		var v := ScreenKit.card(_ex_board_box, Color("#d2b574") if sel else Color(ScreenKit.EDGE), 4, sel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 2)
		row.add_child(left)
		_label(left, _offer_title(o), "SectionLabel")
		var pv := _ex.preview(o, [])
		var nums := ScreenKit.stat_row(left)
		var s1 := ScreenKit.stat(nums, "UI_RS_GU_EX_ST_REQ", "UI_RS_GU_EX_TIP_REQ", Color(ScreenKit.GOLD))
		s1.set_value(NumberFormat.fmt(float(pv.required)), tr("UI_RS_GU_UNIT_POWER"))
		var s2 := ScreenKit.stat(nums, "UI_RS_GU_EX_ST_TIME", "UI_RS_GU_EX_TIP_TIME", Color(ScreenKit.GOLD))
		s2.set_value(NumberFormat.fmt_time(_ex.duration_h(int(o.dur_idx)) * 3600.0), "")
		var s3 := ScreenKit.stat(nums, "UI_RS_GU_EX_ST_VALUE", "UI_RS_GU_EX_TIP_VALUE", Color(ScreenKit.GOLD))
		s3.set_value("~" + NumberFormat.fmt(float(pv.value)), tr("UI_ESTATE_GOLD"))
		left.add_child(ScreenKit.muted(Loc.tf("UI_RS_GU_EX_REWARD", {"what": Loc.t(pv.reward_desc), "size": int(o.size)})))
		var b := Button.new()
		b.text = "UI_GUILD_EX_SELECT"
		b.toggle_mode = true
		b.button_pressed = sel
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(110, 0)
		if full:
			b.tooltip_text = tr("UI_RS_GU_EX_FULL_TIP")
		b.pressed.connect(func() -> void:
			_selected_offer = oid
			_ex_detail_sig = ""
			_ex_board_sig = ""
			ReqLink.reveal.call_deferred(_ex_detail))
		row.add_child(b)


func _refresh_detail() -> void:
	var o := _ex.get_offer(_selected_offer)
	if o.is_empty():
		if _ex_detail_sig != "none":
			_ex_detail_sig = "none"
			_clear(_ex_detail)
			_team_checks.clear()
		return
	var sig_parts := PackedStringArray([_selected_offer])
	for m in _mc.roster():
		sig_parts.append("%s%s" % [m.uid, "1" if _mc.is_available(str(m.uid)) else "0"])
	var sig := ",".join(sig_parts)
	if sig != _ex_detail_sig:
		_ex_detail_sig = sig
		_rebuild_detail(o)
	var team: Array = _checked_team()
	var pv := _ex.preview(o, team)
	var reason := _ex.can_start(_selected_offer, team)
	var good: bool = float(pv.power) >= float(pv.required)
	_pv_power.set_value(NumberFormat.fmt(float(pv.power)), "/ %s %s" % [NumberFormat.fmt(float(pv.required)), tr("UI_RS_GU_UNIT_POWER")])
	_pv_power.set_color(Color(ScreenKit.GOOD) if good else Color(ScreenKit.BAD))
	var ps := float(pv.p_success)
	var pcol := Color(ScreenKit.GOOD) if ps >= 0.7 else (Color(ScreenKit.BAD) if ps < 0.4 else Color(ScreenKit.WARN))
	_pv_success.set_value(NumberFormat.fmt_pct(100.0 * ps), "")
	_pv_success.set_color(pcol)
	_pv_time.set_value(NumberFormat.fmt_time(float(pv.duration_s)), "")
	_pv_bar.set_target(ps, 0.0)
	_pv_bar.add_theme_stylebox_override("fill", UiKit.tinted_fill(pcol))
	_preview_label.text = _preview_bbcode(pv)
	ScreenKit.gate(_start_btn, "" if reason == "" else tr(reason), _start_reason)


func _checked_team() -> Array:
	var out: Array = []
	for uid in _team_checks:
		if (_team_checks[uid] as CheckBox).button_pressed:
			out.append(uid)
	return out


func _rebuild_detail(o: Dictionary) -> void:
	var keep: Array = _checked_team()
	_clear(_ex_detail)
	_team_checks.clear()
	var v := ScreenKit.card(_ex_detail, Color("#d2b574"), 4, true)
	_label(v, _offer_title(o), "SectionLabel")
	_label(v, "UI_GUILD_EX_PICK_TEAM", "MutedLabel")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	v.add_child(flow)
	if _mc.roster().is_empty():
		flow.add_child(ScreenKit.go_button(tr("UI_RS_GU_GO_HIRE"), ScreenKit.target("guild", {"tab": 1}), true))
	for m in _mc.roster():
		var uid := str(m.uid)
		var cb := CheckBox.new()
		cb.text = Loc.tf("UI_GUILD_EX_MEMBER", {"name": m.name, "role": _role_name(str(m.role)), "p": NumberFormat.fmt(_mc.power_of(m))})
		cb.disabled = not _mc.is_available(uid)
		cb.button_pressed = keep.has(uid) and not cb.disabled
		if cb.disabled:
			cb.tooltip_text = tr("UI_RS_GU_MEMBER_BUSY")
		flow.add_child(cb)
		_team_checks[uid] = cb
	var nums := ScreenKit.stat_row(v)
	_pv_power = ScreenKit.stat(nums, "UI_RS_GU_PV_POWER", "UI_RS_GU_PV_TIP_POWER")
	_pv_success = ScreenKit.stat(nums, "UI_RS_GU_PV_SUCCESS", "UI_RS_GU_PV_TIP_SUCCESS")
	_pv_time = ScreenKit.stat(nums, "UI_RS_GU_PV_TIME", "UI_RS_GU_PV_TIP_TIME", Color(ScreenKit.GOLD))
	_pv_bar = ScreenKit.bar(v, Color(ScreenKit.GOOD), 10)
	_preview_label = RichTextLabel.new()
	_preview_label.bbcode_enabled = true
	_preview_label.fit_content = true
	_preview_label.scroll_active = false
	v.add_child(_preview_label)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	v.add_child(brow)
	_start_btn = Button.new()
	_start_btn.theme_type_variation = &"AccentButton"
	_start_btn.text = "UI_GUILD_EX_START"
	_start_btn.pressed.connect(func() -> void:
		if _ex.start(_selected_offer, _checked_team()):
			_pulse(_ex_active_box)
			_selected_offer = ""
			_ex_detail_sig = ""
			_ex_board_sig = ""
			_ex_active_sig = "")
	brow.add_child(_start_btn)
	_start_reason = ScreenKit.reason_label()
	_start_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_reason.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(_start_reason)


func _preview_bbcode(pv: Dictionary) -> String:
	var pcol := COL_OK if float(pv.p_success) >= 0.7 else (COL_BAD if float(pv.p_success) < 0.4 else "#e0c070")
	var lines := PackedStringArray()
	lines.append(Loc.tf("UI_GUILD_EX_PV_RISK", {"p": NumberFormat.fmt_pct(100.0 * float(pv.p_success)), "c": pcol,
		"fail": NumberFormat.fmt(float(pv.fail_pct)), "inj": NumberFormat.fmt_pct(100.0 * float(pv.injury_p)),
		"inj_h": NumberFormat.fmt(float(DataRegistry.rules("mercenary_rules").injury.duration_h))}))
	lines.append(Loc.tf("UI_GUILD_EX_PV_REWARD", {"what": Loc.t(pv.reward_desc), "value": NumberFormat.fmt(float(pv.value)),
		"frag": NumberFormat.fmt_pct(100.0 * float(pv.fragment_p))}))
	return "\n".join(lines)


# ================================================================== suggerimento «cosa fare ora»

func _refresh_hint() -> void:
	match _tabs.current_tab:
		0:
			var n := _ap.slots_total()
			if n <= 0:
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_AP_BUILD"))
			elif _ap.active_count() <= 0:
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_AP_FIRST"))
			elif _ap.active_count() < n:
				_hint.show_hint(ScreenKit.Kind.TODO, Loc.tf("UI_RS_GU_H_AP_IDLE", {"n": n - _ap.active_count()}))
			else:
				_hint.show_hint(ScreenKit.Kind.OK, tr("UI_RS_GU_H_AP_OK"))
		1:
			if _mc.tavern_level() <= 0:
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_TAVERN_BUILD"))
			elif _mc.roster().is_empty():
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_MC_FIRST"))
			elif _mc.roster().size() >= _mc.roster_cap():
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_GU_H_MC_FULL"))
			else:
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_GU_H_MC_MORE"), tr("UI_RS_GU_GO_EXPED"), ScreenKit.target("guild", {"tab": 2}))
		2:
			if _ex.tavern_level() <= 0:
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_TAVERN_BUILD"))
			elif _mc.roster().is_empty():
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_EX_NOMERC"), tr("UI_RS_GU_GO_HIRE"), ScreenKit.target("guild", {"tab": 1}))
			elif _ex.active().size() >= _ex.concurrent_cap():
				_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_GU_H_EX_BUSY"))
			elif _selected_offer != "" and not _ex.get_offer(_selected_offer).is_empty():
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_EX_TEAM"))
			else:
				_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_GU_H_EX_PICK"))


# ================================================================== aggiornamento

func refresh() -> void:
	if _tabs == null:
		return
	_refresh_apprentices()
	_refresh_mercs()
	_refresh_expeditions()
	_refresh_hint()
