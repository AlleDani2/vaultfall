class_name WorldBossPanel
extends EndgamePanel
## Scheda Boss mondiali (docs/05 §8): finestra a rotazione ogni 4 ore (30 minuti), Corno dell'Adunata per evocarli quando
## si vuole, livelli di contributo Bronzo/Argento/Oro/Platino con ricompense visibili, barra del contributo con i segni dei
## livelli, alleati simulati, tempo residuo. Animazioni a tween: rimbalzo al nuovo livello, scossa del boss, striscione finale.

const TIER_COL := {"bronze": Color("b87a46"), "silver": Color("c8ccd2"), "gold": Color("e0b640"), "platinum": Color("7fd6e8")}

var _selected: String = ""
var _group := ButtonGroup.new()
var _list: VBoxContainer
var _status: Label
var _detail: VBoxContainer
var _open_state: Dictionary = {}
var _run_box: VBoxContainer
var _run_title: Label
var _run_boss: Label
var _run_boss_bar: ProgressBar
var _run_contrib: Label
var _run_contrib_bar: ProgressBar
var _run_marks: Control
var _run_time_bar: ProgressBar
var _run_hero: Label
var _run_hero_bar: ProgressBar
var _run_ally: Label
var _go_rot: Button
var _go_horn: Button
var _summon: Button
var _buy: Button
var _stop_btn: Button
var _horn_label: Label
var _result_card: Control
var _result_label: Label
var _why_rot: Label
var _why_horn: Label
var _why_summon: Label
var _why_buy: Label
var _portrait: TextureRect
var _sig: String = ""
var _last_tier: String = ""


func _build() -> void:
	var root := HBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	left.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)
	_status = CombatUi.text_label("MonoLabel", true)          # stato della finestra (il suggerimento in alto dice la stessa cosa: qui resta per i test e il tooltip)
	_status.visible = false
	right.add_child(_status)
	var rc := ScreenKit.card(right, Color("#e8702a"), 4, true)
	_result_card = ScreenKit.panel_of(rc)
	_result_card.visible = false
	rc.add_child(ScreenKit.label("UI_RS_DU_WB_LAST_RESULT", "SectionLabel"))
	_result_label = CombatUi.text_label("", true)
	rc.add_child(_result_label)
	# incontro in corso
	_run_box = VBoxContainer.new()
	_run_box.add_theme_constant_override("separation", 4)
	right.add_child(_run_box)
	_run_title = CombatUi.text_label("SectionLabel")
	_run_box.add_child(_run_title)
	_run_boss = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_boss)
	_run_boss_bar = CombatUi.bar(Color("b8433b"), 16.0)
	_run_box.add_child(_run_boss_bar)
	_run_contrib = CombatUi.text_label("", true)
	_run_box.add_child(_run_contrib)
	_run_contrib_bar = CombatUi.bar(Color("c8a24a"), 14.0)
	_run_box.add_child(_run_contrib_bar)
	_run_marks = Control.new()                 # segni dei livelli sulla barra del contributo
	_run_marks.custom_minimum_size = Vector2(0, 16)
	_run_marks.draw.connect(_draw_marks)
	_run_box.add_child(_run_marks)
	_run_ally = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_ally)
	_run_time_bar = CombatUi.bar(Color("5b8def"), 8.0)
	_run_box.add_child(_run_time_bar)
	_run_hero = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_hero)
	_run_hero_bar = CombatUi.bar(Color("4f9d5d"), 12.0)
	_run_box.add_child(_run_hero_bar)
	right.add_child(make_banner())
	var act := ScreenKit.card(right, ScreenKit.accent("dungeon"), 4)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	act.add_child(grid)
	_go_rot = Button.new()
	_go_rot.theme_type_variation = &"AccentButton"
	_go_rot.text = "UI_RAID_WB_ATTACK"
	_go_rot.pressed.connect(func() -> void: _enter("rotation"))
	grid.add_child(_go_rot)
	_why_rot = _why_label(grid)
	_go_horn = Button.new()
	_go_horn.theme_type_variation = &"AccentButton"
	_go_horn.text = "UI_RAID_WB_ATTACK_HORN"
	_go_horn.pressed.connect(func() -> void: _enter("horn"))
	grid.add_child(_go_horn)
	_why_horn = _why_label(grid)
	_summon = Button.new()
	_summon.text = "UI_RAID_WB_SUMMON"
	_summon.pressed.connect(_on_summon)
	grid.add_child(_summon)
	_why_summon = _why_label(grid)
	_buy = Button.new()
	_buy.pressed.connect(_on_buy_horn)
	grid.add_child(_buy)
	_why_buy = _why_label(grid)
	_stop_btn = Button.new()
	_stop_btn.text = "UI_RAID_WB_RETREAT"
	_stop_btn.pressed.connect(func() -> void:
		combat.stop()
		_sig = ""
		refresh())
	grid.add_child(_stop_btn)
	_horn_label = CombatUi.text_label("MonoLabel", true)
	_horn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_horn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_horn_label)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	var first := ""
	var bosses := _eg().world_bosses()
	if not bosses.is_empty():
		first = str(bosses[0].id)
	_selected = first
	if combat.endgame_mode() == "wboss":
		_selected = str(combat._act().wb)
	_fill_list()


func _why_label(parent: Control) -> Label:
	var l := ScreenKit.muted("")
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(l)
	return l


func _fill_list() -> void:
	CombatUi.clear_children(_list)
	var win := _eg().wb_window()
	var horn := _eg().wb_horn()
	var accent := ScreenKit.accent("dungeon")
	for w in _eg().world_bosses():
		var wid := str(w.id)
		var pill_text := ""
		var pill_col := Color(ScreenKit.GOOD)
		if (not win.is_empty() and str(win.boss) == wid) or (not horn.is_empty() and str(horn.boss) == wid):
			pill_text = tr("UI_RS_DU_WB_OPEN_NOW")
			pill_col = Color("#e8702a")
		elif not str(w.best).is_empty():
			pill_text = tr("UI_RAID_TIER_" + str(w.best).to_upper())
			pill_col = TIER_COL.get(str(w.best), Color.WHITE)
		var sub := Loc.tf("UI_RS_DU_WB_ROW_SUB", {"lv": int(w.def.level), "h": int(w.def.spawn_every_h)})
		var row := ScreenKit.pick_row(_list, _group, Loc.t(w.def.name), sub, pill_text, pill_col, false, accent, Loc.t(w.def.name) + "\n" + sub)
		row.set_pressed_no_signal(wid == _selected)
		row.pressed.connect(func() -> void:
			_selected = wid
			_sig = ""
			refresh())


func _enter(source: String) -> void:
	if _eg().start_world_boss(source):
		_last_tier = ""
		CombatUi.pop(_go_rot if source == "rotation" else _go_horn)
		var w := _eg().wb_progress()
		if not w.is_empty():
			_selected = str(w.boss)
	else:
		EventBus.notice.emit("warning", tr("UI_RAID_WB_DENIED"), {})
	_sig = ""
	refresh()


func _on_summon() -> void:
	if _eg().summon_world_boss(_selected):
		CombatUi.pop(_summon)
		EventBus.notice.emit("info", tr("UI_RAID_WB_SUMMONED"), {})
	else:
		EventBus.notice.emit("warning", tr("UI_RAID_WB_SUMMON_DENIED"), {})
	_sig = ""
	refresh()


func _on_buy_horn() -> void:
	if _eg().shop_buy("trophy_hall", "rally_horn"):
		CombatUi.pop(_buy)
	else:
		EventBus.notice.emit("warning", tr("UI_RAID_WB_BUY_DENIED"), {})
	_sig = ""
	refresh()


func _horn_count() -> int:
	var bank: Variant = combat.ctx.get_system("bank")
	return int(bank.count("rally_horn")) if bank != null else 0


func _horn_price() -> int:
	for it in _eg().shop_items("trophy_hall"):
		if str(it.item) == "rally_horn":
			return int(it.cost)
	return 0


func refresh() -> void:
	if combat == null:
		return
	var running := combat.endgame_mode() == "wboss"
	_run_box.visible = running
	var win := _eg().wb_window()
	var horn := _eg().wb_horn()
	var unlocked := _eg().wb_unlocked()
	if running:
		_refresh_run()
	_consume_log()
	# stato della finestra
	if not unlocked:
		_status.text = tr("UI_RAID_WB_LOCKED")
		_status.add_theme_color_override("font_color", CombatUi.COL_WARN)
	elif not win.is_empty():
		_status.text = Loc.tf("UI_RAID_WB_OPEN", {"boss": Loc.t(_eg().wb_def(str(win.boss)).name), "time": NumberFormat.fmt_time(float(win.left_s))})
		_status.add_theme_color_override("font_color", CombatUi.COL_SAFE["green"])
	else:
		var nx := _eg().wb_next()
		_status.text = Loc.tf("UI_RAID_WB_NEXT", {"boss": Loc.t(_eg().wb_def(str(nx.boss)).name), "time": NumberFormat.fmt_time(float(nx.in_s))})
		_status.remove_theme_color_override("font_color")
	var sig := "%s|%s|%s|%d|%d|%s" % [_selected, str(running), str(win.get("boss", "")) + str(horn.get("boss", "")), _horn_count(),
		combat.hero_level(), str(_eg().world_bosses().map(func(w: Dictionary) -> String: return str(w.best) + str(w.kills)))]
	if sig != _sig:
		_sig = sig
		_fill_list()
		_fill_detail()
	var hc := _horn_count()
	var price := _horn_price()
	var bank: Variant = combat.ctx.get_system("bank")
	var seals := int(bank.count("raid_seal")) if bank != null else 0
	var why_rot := ""
	if not unlocked:
		why_rot = tr("UI_RS_DU_WB_WHY_LOCKED")
	elif running:
		why_rot = tr("UI_RS_DU_WB_WHY_RUNNING")
	elif win.is_empty():
		var nx2 := _eg().wb_next()
		why_rot = Loc.tf("UI_RS_DU_WB_WHY_NO_WINDOW", {"time": NumberFormat.fmt_time(float(nx2.in_s))})
	ScreenKit.gate(_go_rot, why_rot, _why_rot)
	_why_rot.visible = true
	_why_rot.text = why_rot if why_rot != "" else tr("UI_RS_DU_WB_OK_ROT")
	_go_horn.visible = not horn.is_empty()
	_why_horn.visible = not horn.is_empty()
	ScreenKit.gate(_go_horn, tr("UI_RS_DU_WB_WHY_RUNNING") if running else ("" if unlocked else tr("UI_RS_DU_WB_WHY_LOCKED")), _why_horn)
	_why_horn.visible = not horn.is_empty()
	_why_horn.text = Loc.tf("UI_RS_DU_WB_HORN_OK", {"boss": Loc.t(_eg().wb_def(str(horn.boss)).name), "time": NumberFormat.fmt_time(float(horn.left_s))}) if not horn.is_empty() and not running else _why_horn.text
	_stop_btn.disabled = not running
	_stop_btn.tooltip_text = "" if running else tr("UI_RS_DU_WHY_NOT_INSIDE")
	var why_sum := ""
	if not unlocked:
		why_sum = tr("UI_RS_DU_WB_WHY_LOCKED")
	elif running:
		why_sum = tr("UI_RS_DU_WB_WHY_RUNNING")
	elif not horn.is_empty():
		why_sum = tr("UI_RS_DU_WB_WHY_HORN_ACTIVE")
	elif hc <= 0:
		why_sum = tr("UI_RS_DU_WB_WHY_NO_HORN")
	ScreenKit.gate(_summon, why_sum, _why_summon)
	_why_summon.visible = true
	_why_summon.text = why_sum if why_sum != "" else tr("UI_RS_DU_WB_OK_SUMMON")
	_buy.text = Loc.tf("UI_RAID_WB_BUY", {"n": price})
	var why_buy := ""
	if bank == null or seals < price:
		why_buy = Loc.tf("UI_RS_DU_WB_WHY_SEALS", {"n": price, "have": seals})
	ScreenKit.gate(_buy, why_buy, _why_buy)
	_why_buy.visible = true
	_why_buy.text = why_buy if why_buy != "" else tr("UI_RS_DU_WB_OK_BUY")
	_horn_label.text = Loc.tf("UI_RAID_WB_HORNS", {"n": hc})


func _fill_detail() -> void:
	CombatUi.clear_children(_detail)
	_portrait = null
	var d := _eg().wb_def(_selected)
	if d.is_empty():
		return
	var boss: Dictionary = DataRegistry.get_def("monsters", str(d.boss))
	var title := CombatUi.text_label("TitleLabel")
	title.text = Loc.t(d.name)
	_detail.add_child(title)
	var boss_body := EstateDungeonKit.disclosure(_detail, "UI_F9_DU_BOSS_MECH", _open_state, "boss")
	_portrait = EndgamePanel.boss_card(boss_body, boss, combat.mechanics(), Loc.tf("UI_RAID_WB_SUB", {"h": int(d.spawn_every_h), "m": int(d.window_min),
		"allies": NumberFormat.decimal(float(d.simulated_allies_dps_pct_of_hp_per_min), 1, Loc.locale())}))
	_detail.add_child(CombatUi.label("UI_RAID_WB_TIERS", "SectionLabel"))
	_detail.add_child(ScreenKit.muted("UI_RS_DU_WB_TIERS_SUB"))
	var best := tier_index(str(combat.state.wb.best.get(_selected, "")))
	var i := 0
	for t in d.contribution_tiers:
		var tcol: Color = TIER_COL.get(str(t.id), Color.WHITE)
		var v := ScreenKit.card(_detail, tcol, 4, i <= best)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var nm := CombatUi.text_label("SectionLabel")
		nm.custom_minimum_size = Vector2(90, 0)
		nm.text = tr("UI_RAID_TIER_" + str(t.id).to_upper())
		nm.add_theme_color_override("font_color", tcol)
		row.add_child(nm)
		var pc := ScreenKit.stat(row, "UI_RS_DU_WB_TIER_NEED", "UI_RS_DU_WB_TIP_TIER", Color(ScreenKit.GOLD))
		pc.set_value(NumberFormat.fmt_pct(float(t.damage_pct)), "")
		pc.custom_minimum_size = Vector2(100, 0)
		var rw := ScreenKit.muted(EndgamePanel.items_text(d.rewards.get(str(t.id), [])))
		rw.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		rw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rw)
		if i <= best:
			row.add_child(ScreenKit.pill(tr("UI_RS_DU_WB_REACHED"), Color(ScreenKit.GOOD)))
		i += 1
	var note := CombatUi.label("UI_RAID_WB_NOTE", "MutedLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(note)
	var kills := CombatUi.text_label("MutedLabel")
	kills.text = Loc.tf("UI_RAID_WB_KILLS", {"n": int(combat.state.wb.kills.get(_selected, 0))})
	_detail.add_child(kills)


## Suggerimento «cosa fare ora» per la scheda Boss mondiali.
func hint() -> Array:
	if not _eg().wb_unlocked():
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_WB_LOCKED")]
	if combat.endgame_mode() == "wboss":
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_WB_RUNNING")]
	var win := _eg().wb_window()
	if not win.is_empty():
		return [ScreenKit.Kind.TODO, Loc.tf("UI_RS_DU_H_WB_OPEN", {"boss": Loc.t(_eg().wb_def(str(win.boss)).name), "time": NumberFormat.fmt_time(float(win.left_s))})]
	var nx := _eg().wb_next()
	return [ScreenKit.Kind.INFO, Loc.tf("UI_RS_DU_H_WB_WAIT", {"boss": Loc.t(_eg().wb_def(str(nx.boss)).name), "time": NumberFormat.fmt_time(float(nx.in_s))})]


static func tier_index(tier: String) -> int:
	return EndgameCombat.TIER_IDS.find(tier)


func _refresh_run() -> void:
	var w := _eg().wb_progress()
	if w.is_empty():
		return
	var d := _eg().wb_def(str(w.boss))
	var a := combat._act()
	_run_title.text = "%s — %s" % [Loc.t(d.name), NumberFormat.fmt_time(float(a.get("t", 0.0)))]
	var st := combat.hero_stats()
	CombatUi.set_bar(_run_hero_bar, combat.hp() / maxf(1.0, float(st.hp)))
	_run_hero.text = "%s  %s / %s" % [tr("UI_COMBAT_HERO"), NumberFormat.fmt(floorf(combat.hp())), NumberFormat.fmt(float(st.hp))]
	_run_boss.text = "%s  —  %s" % [Loc.t(d.name), NumberFormat.fmt_pct(float(w.hp_pct))]
	CombatUi.set_bar(_run_boss_bar, float(w.hp_pct) / 100.0)
	var top := float(d.contribution_tiers[d.contribution_tiers.size() - 1].damage_pct)
	CombatUi.set_bar(_run_contrib_bar, float(w.pct) / top)
	var cur := str(w.tier)
	var tier_txt := tr("UI_RAID_TIER_" + cur.to_upper()) if not cur.is_empty() else tr("UI_RAID_TIER_NONE")
	var nxt: Dictionary = w.next
	var next_txt := Loc.tf("UI_RAID_WB_NEXT_TIER", {"tier": tr("UI_RAID_TIER_" + str(nxt.id).to_upper()), "pct": NumberFormat.fmt_pct(float(nxt.damage_pct))}) \
		if not nxt.is_empty() else tr("UI_RAID_WB_MAX_TIER")
	_run_contrib.text = Loc.tf("UI_RAID_WB_CONTRIB", {"pct": NumberFormat.decimal(float(w.pct), 2, Loc.locale()), "dealt": NumberFormat.fmt(float(w.dealt)),
		"tier": tier_txt, "next": next_txt})
	CombatUi.set_bar_color(_run_contrib_bar, TIER_COL.get(cur, Color("c8a24a")))
	_run_ally.text = Loc.tf("UI_RAID_WB_ALLIES", {"pct": NumberFormat.decimal(float(w.ally_pct), 1, Loc.locale())})
	var win_total := float(d.window_min) * 60.0
	CombatUi.set_bar(_run_time_bar, float(w.left_s) / win_total)
	_run_time_bar.tooltip_text = Loc.tf("UI_RAID_WB_TIME_LEFT", {"time": NumberFormat.fmt_time(float(w.left_s))})
	if cur != _last_tier:
		if not cur.is_empty():
			show_banner(Loc.tf("UI_RAID_WB_TIER_BANNER", {"tier": tier_txt}), TIER_COL.get(cur, Color.WHITE), 1.4)
			CombatUi.pop(_run_contrib_bar, 1.12, 0.3)
		_last_tier = cur
	_run_marks.queue_redraw()


func _draw_marks() -> void:
	var d := _eg().wb_def(_selected)
	if d.is_empty():
		return
	var w := _run_marks.size.x
	var top := float(d.contribution_tiers[d.contribution_tiers.size() - 1].damage_pct)
	for t in d.contribution_tiers:
		var x := w * float(t.damage_pct) / top
		_run_marks.draw_line(Vector2(x, 0), Vector2(x, 10), TIER_COL.get(str(t.id), Color.WHITE), 3.0)


func _consume_log() -> void:
	for e in combat.log_since(_last_log_id):
		_last_log_id = int(e.id)
		match str(e.k):
			"wb_done":
				var tier := str(e.tier)
				var txt := Loc.tf("UI_RAID_WB_DONE", {"tier": tr("UI_RAID_TIER_" + tier.to_upper()) if not tier.is_empty() else tr("UI_RAID_TIER_NONE"),
					"pct": NumberFormat.decimal(float(e.pct), 2, Loc.locale()), "items": EndgamePanel.items_text(e.items, false) + (" + " if not (e.items as Array).is_empty() and not (e.crates as Array).is_empty() else "") + _crates_text(e.crates)})
				show_banner(tr("UI_RAID_WB_VICTORY") if bool(e.killed) else tr("UI_RAID_WB_ENDED"), TIER_COL.get(tier, CombatUi.COL_HURT), 2.6)
				_status.text = txt
				_sig = ""
			"heavy":
				CombatUi.flash(_run_hero_bar, Color(1.6, 0.6, 0.6), 0.3)
				if _portrait != null:
					CombatUi.shake(_portrait, 8.0, 0.25)
			"mech":
				if _portrait != null:
					CombatUi.shake(_portrait, 6.0, 0.2)


func _crates_text(crates: Array) -> String:
	var by: Dictionary = {}
	for c in crates:
		by[str(c)] = int(by.get(str(c), 0)) + 1
	var parts: PackedStringArray = []
	for k in by:
		parts.append("%s ×%d" % [Loc.t(DataRegistry.item(str(k)).get("name", str(k))), int(by[k])])
	return ", ".join(parts)
