class_name RaidPanel
extends EndgamePanel
## Scheda Incursioni (docs/05 §8, docs/11 §8): elenco delle 3 incursioni, boss a 3 fasi con le sue meccaniche, scelta
## della squadra (Difensore, Guaritore, Assaltatore dalla Taverna) con potere/richiesto ed effetti di ruolo, indicatore
## di rischio, ricompense visibili, combattimento in corso con barra del boss a segni di fase, esito con ricompense.
## Animazioni a tween: scossa del boss, lampo sui colpi pesanti, striscione di fase/vittoria/sconfitta, rimbalzo ricompense.

const ROLES: Array = ["defender", "healer", "striker"]
const ROLE_ICON := {"defender": "🛡", "healer": "✚", "striker": "▲"}
const BAR_COL := Color("c8a24a")

var _selected: String = ""
var _group := ButtonGroup.new()
var _list: VBoxContainer
var _detail: VBoxContainer
var _detail2: VBoxContainer
var _go_reason: Label
var _run_box: VBoxContainer
var _run_title: Label
var _run_enemy: Label
var _run_enemy_bar: ProgressBar
var _run_marks: Control
var _run_hero: Label
var _run_hero_bar: ProgressBar
var _run_info: Label
var _party_opts: Dictionary = {}          # ruolo -> OptionButton
var _party_uids: Dictionary = {}          # ruolo -> [uid] nell'ordine delle voci
var _power_bar: ProgressBar
var _power_label: Label
var _fx_label: Label
var _risk: Label
var _go_btn: Button
var _stop_btn: Button
var _auto_btn: Button
var _cd_label: Label
var _portrait: TextureRect
var _sig: String = ""
var _party_sig: String = ""
var _last_phase: int = 0
var _open_state: Dictionary = {}


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
	# combattimento in corso
	_run_box = VBoxContainer.new()
	_run_box.add_theme_constant_override("separation", 4)
	right.add_child(_run_box)
	_run_title = CombatUi.text_label("SectionLabel")
	_run_box.add_child(_run_title)
	_run_enemy = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_enemy)
	_run_enemy_bar = CombatUi.bar(Color("b8433b"), 16.0)
	_run_box.add_child(_run_enemy_bar)
	_run_marks = Control.new()                 # segni delle fasi (66% e 33%) sopra la barra
	_run_marks.custom_minimum_size = Vector2(0, 12)
	_run_marks.draw.connect(_draw_marks)
	_run_box.add_child(_run_marks)
	_run_hero = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_hero)
	_run_hero_bar = CombatUi.bar(Color("4f9d5d"), 12.0)
	_run_box.add_child(_run_hero_bar)
	_run_info = CombatUi.text_label("MutedLabel", true)
	_run_box.add_child(_run_info)
	right.add_child(make_banner())
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	var act := ScreenKit.card(right, ScreenKit.accent("dungeon"), 4, true)
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8)
	btns.add_theme_constant_override("v_separation", 6)
	act.add_child(btns)
	_go_btn = Button.new()
	_go_btn.theme_type_variation = &"AccentButton"
	_go_btn.text = "UI_RAID_START"
	_go_btn.pressed.connect(_on_start)
	btns.add_child(_go_btn)
	_stop_btn = Button.new()
	_stop_btn.text = "UI_RAID_RETREAT"
	_stop_btn.pressed.connect(func() -> void:
		combat.stop()
		_sig = ""
		refresh())
	btns.add_child(_stop_btn)
	_auto_btn = Button.new()
	_auto_btn.text = "UI_RAID_AUTO_PARTY"
	_auto_btn.tooltip_text = "UI_RS_DU_TIP_AUTO_PARTY"
	_auto_btn.pressed.connect(_on_auto)
	btns.add_child(_auto_btn)
	_cd_label = CombatUi.text_label("MonoLabel")
	btns.add_child(_cd_label)
	_go_reason = ScreenKit.reason_label()
	act.add_child(_go_reason)
	_risk = CombatUi.text_label("", true)
	act.add_child(_risk)
	_detail2 = VBoxContainer.new()
	_detail2.add_theme_constant_override("separation", 8)
	right.add_child(_detail2)
	var shop_body := EstateDungeonKit.disclosure(right, "UI_RAID_SHOP_TITLE", _open_state, "shop")
	build_shop(shop_body, "trophy_hall")
	_selected = _first_raid()
	_fill_list()
	_sig = ""


func _first_raid() -> String:
	var pick := ""
	for r in _eg().raids():
		if bool(r.unlocked):
			pick = str(r.id)
	if pick.is_empty():
		var all := _eg().raids()
		pick = str(all[0].id) if not all.is_empty() else ""
	var a := combat._act()
	if combat.endgame_mode() == "raid":
		pick = str(a.raid)
	return pick


func _fill_list() -> void:
	CombatUi.clear_children(_list)
	var accent := ScreenKit.accent("dungeon")
	for r in _eg().raids():
		var rid := str(r.id)
		var unlocked := bool(r.unlocked)
		var pill_text := ""
		var pill_col := Color(ScreenKit.GOOD)
		if not unlocked:
			pill_text = tr("UI_RS_DU_ST_LOCKED")
			pill_col = Color(ScreenKit.TEXT_DIM)
		elif float(r.cd_s) > 0.0:
			pill_text = NumberFormat.fmt_time(float(r.cd_s))
			pill_col = Color(ScreenKit.WARN)
		elif int(r.clears) > 0:
			pill_text = "×%d" % int(r.clears)
		var sub := Loc.tf("UI_RS_DU_RAID_ROW_SUB", {"lv": int(r.def.level)})
		var row := ScreenKit.pick_row(_list, _group, "%d. %s" % [int(r.def.order), Loc.t(r.def.name)], sub, pill_text, pill_col, not unlocked, accent,
			Loc.t(r.def.name) + "\n" + sub)
		row.set_pressed_no_signal(rid == _selected)
		row.pressed.connect(func() -> void:
			_selected = rid
			_sig = ""
			refresh())


# ------------------------------------------------------------------ squadra

func _party_choice() -> Array:
	var out: Array = []
	for role in ROLES:
		var opt: OptionButton = _party_opts.get(role)
		if opt == null:
			continue
		var i := opt.selected
		var ids: Array = _party_uids.get(role, [])
		if i > 0 and i - 1 < ids.size():
			out.append(str(ids[i - 1]))
	return out


func _fill_party_options(keep: bool) -> void:
	var m: Variant = combat.ctx.get_system("mercenaries")
	if m == null:
		return
	var cands := _eg().party_candidates()
	for role in ROLES:
		var opt: OptionButton = _party_opts.get(role)
		if opt == null:
			continue
		var prev_uid := ""
		var ids: Array = _party_uids.get(role, [])
		if keep and opt.selected > 0 and opt.selected - 1 < ids.size():
			prev_uid = str(ids[opt.selected - 1])
		opt.clear()
		opt.add_item(tr("UI_RAID_NO_ONE"))
		var new_ids: Array = []
		var sel := 0
		for mm in cands:
			if str(mm.role) != role:
				continue
			new_ids.append(str(mm.uid))
			opt.add_item("%s — %s %d — %s %s" % [str(mm.name), tr("UI_COMBAT_LV"), int(mm.level), tr("UI_RAID_POWER"),
				NumberFormat.fmt(float(m.power_of(mm)))])
			if str(mm.uid) == prev_uid:
				sel = new_ids.size()
		_party_uids[role] = new_ids
		opt.select(sel)


func _on_auto() -> void:
	var sug := _eg().suggest_party(_selected)
	for role in ROLES:
		var opt: OptionButton = _party_opts.get(role)
		if opt == null:
			continue
		var ids: Array = _party_uids.get(role, [])
		var pick := 0
		for u in sug:
			var i := ids.find(str(u))
			if i >= 0:
				pick = i + 1
		opt.select(pick)
	refresh()


func _on_start() -> void:
	if _eg().start_raid(_selected, _party_choice()):
		CombatUi.pop(_go_btn)
		EventBus.notice.emit("info", tr("UI_RAID_STARTED"), {})
	else:
		EventBus.notice.emit("warning", tr("UI_RAID_DENIED"), {})
	_sig = ""
	refresh()


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	if combat == null:
		return
	var running := combat.endgame_mode() == "raid"
	_run_box.visible = running
	if running:
		_refresh_run()
	_consume_log()
	var rd := _eg().raid_def(_selected)
	var cd := _eg().raid_cd(_selected)
	var party := _party_choice() if not running else (combat._act().get("party", []) as Array)
	var sig := "%s|%s|%d|%d|%s" % [_selected, str(running), combat.hero_level(), int(cd > 0.0), str(_eg().raid_clears(_selected))]
	if sig != _sig:
		_sig = sig
		_fill_list()
		_fill_detail(running)
	if _party_sig != _party_roster_sig():
		_party_sig = _party_roster_sig()
		_fill_party_options(true)
	if is_instance_valid(_power_label) and not rd.is_empty():
		_update_party_summary(party)
	var unlocked := _eg().raid_unlocked(_selected)
	var why := ""
	if rd.is_empty():
		why = tr("UI_RS_DU_WHY_NONE")
	elif not unlocked:
		why = tr("UI_RS_DU_RAID_WHY_LOCKED")
	elif running:
		why = tr("UI_RS_DU_RAID_WHY_RUNNING")
	elif cd > 0.0:
		why = Loc.tf("UI_RS_DU_RAID_WHY_CD", {"time": NumberFormat.fmt_time(cd)})
	ScreenKit.gate(_go_btn, why, _go_reason)
	_stop_btn.disabled = not running
	_stop_btn.tooltip_text = "" if running else tr("UI_RS_DU_WHY_NOT_INSIDE")
	ScreenKit.gate(_auto_btn, tr("UI_RS_DU_RAID_WHY_RUNNING") if running else ("" if not rd.is_empty() else tr("UI_RS_DU_WHY_NONE")))
	_cd_label.text = ""
	for role in ROLES:
		var opt: OptionButton = _party_opts.get(role)
		if opt != null:
			opt.disabled = running
	var shop := _shop_box()
	if shop != null and (shop.get_child_count() == 0 or int(Engine.get_process_frames()) % 30 == 0):
		fill_shop(shop)


func _shop_box() -> VBoxContainer:
	return _find_shop(self)


func _find_shop(n: Node) -> VBoxContainer:
	for c in n.get_children():
		if c is VBoxContainer and c.has_meta("shop"):
			return c
		var r := _find_shop(c)
		if r != null:
			return r
	return null


func _party_roster_sig() -> String:
	var m: Variant = combat.ctx.get_system("mercenaries")
	if m == null:
		return ""
	return "%d|%d" % [_eg().party_candidates().size(), int(m.game_time() / 30.0)]


func _fill_detail(running: bool) -> void:
	CombatUi.clear_children(_detail)
	CombatUi.clear_children(_detail2)
	_portrait = null
	_party_opts.clear()
	var rd := _eg().raid_def(_selected)
	if rd.is_empty():
		return
	var unlocked := _eg().raid_unlocked(_selected)
	var zone := combat.zone_def(str(rd.zone))
	var title := CombatUi.text_label("TitleLabel")
	title.text = Loc.t(rd.name)
	_detail.add_child(title)
	_detail.add_child(CombatUi.banner_rect(str(rd.get("banner", ""))))
	var boss: Dictionary = DataRegistry.get_def("monsters", str(rd.boss))
	var stats := ScreenKit.stat_row(_detail)
	var s1 := ScreenKit.stat(stats, "UI_RS_DU_ST_BOSS", "UI_RS_DU_TIP_BOSS")
	s1.set_value(str(int(boss.level)), "")
	s1.set_caption(Loc.t(boss.name))
	var s2 := ScreenKit.stat(stats, "UI_RS_DU_ST_CLEARS", "UI_RS_DU_TIP_CLEARS")
	s2.set_value(str(_eg().raid_clears(_selected)), tr("UI_RS_DU_UNIT_TIMES"))
	s2.set_caption(Loc.t(zone.get("name", "")))
	var s3 := ScreenKit.stat(stats, "UI_RS_DU_ST_COOLDOWN", "UI_RS_DU_TIP_COOLDOWN")
	s3.set_value(str(int(rd.cooldown_h)), tr("UI_RS_DU_UNIT_HOURS"))
	if not unlocked:
		EndgamePanel.lock_card(combat, _detail, rd.unlock)
	# squadra
	var pc := ScreenKit.card(_detail, Color(ScreenKit.EDGE), 4)
	pc.add_child(CombatUi.label("UI_RAID_PARTY", "SectionLabel"))
	pc.add_child(ScreenKit.muted("UI_RS_DU_PARTY_SUB"))
	var m: Variant = combat.ctx.get_system("mercenaries")
	if m == null or (m.roster() as Array).is_empty():
		var acts: Array = []
		if ScreenKit.available("guild"):
			acts.append([tr("UI_RS_GU_GO_HIRE"), ScreenKit.target("guild", {"tab": 1})])
		ScreenKit.empty(pc, tr("UI_RS_DU_NO_MERCS"), tr("UI_RS_DU_NO_MERCS_WHY"), acts)
	var party_now: Array = combat._act().get("party", []) if running else []
	for role in ROLES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		pc.add_child(row)
		var rl := CombatUi.text_label("MonoLabel", false)
		rl.custom_minimum_size = Vector2(130, 0)
		rl.text = "%s %s" % [str(ROLE_ICON[role]), Loc.t(m.role_name(role)) if m != null else role]
		rl.tooltip_text = tr("UI_RS_DU_TIP_ROLE_" + str(role).to_upper())
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(rl)
		var opt := OptionButton.new()
		opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.clip_text = true
		opt.item_selected.connect(func(_i: int) -> void: refresh())
		row.add_child(opt)
		_party_opts[role] = opt
	_fill_party_options(false)
	if running:
		# durante l'incursione si mostra la squadra scelta (le voci sono disabilitate)
		for role in ROLES:
			var opt2: OptionButton = _party_opts[role]
			for u in party_now:
				var ids: Array = _party_uids.get(role, [])
				var i := ids.find(str(u))
				if i >= 0:
					opt2.select(i + 1)
	_power_label = CombatUi.text_label("MonoLabel")
	pc.add_child(_power_label)
	_power_bar = CombatUi.bar(BAR_COL, 12.0)
	pc.add_child(_power_bar)
	_fx_label = CombatUi.text_label("MutedLabel", true)
	pc.add_child(_fx_label)
	_update_party_summary(_party_choice() if not running else party_now)
	# boss e ricompense (sotto l'azione)
	_detail2.add_child(CombatUi.label("UI_RAID_REWARD", "SectionLabel"))
	_reward_chips(_detail2, rd, boss)
	var boss_body := EstateDungeonKit.disclosure(_detail2, "UI_F9_DU_BOSS_MECH", _open_state, "boss")
	_portrait = EndgamePanel.boss_card(boss_body, boss, combat.mechanics(), _phases_text(boss))


## Ricompense a riquadri con icona + riga delle ricompense non-oggetto (essenza, XP dei mercenari).
func _reward_chips(parent: Control, rd: Dictionary, boss: Dictionary) -> void:
	var r: Dictionary = rd.completion_reward
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	ScreenKit.chip(flow, Loc.tf("UI_C2_REWARD_GOLD", {"n": NumberFormat.fmt(float(r.get("gold", 0)))}), IconLib.ui("ui_currency_gold"), "", Color("#c8a24a"))
	for it in r.get("items", []):
		var q: Variant = it.get("qty", 1)
		var qt := "%d–%d" % [int(q[0]), int(q[1])] if q is Array else str(int(q))
		var iid := str(it.item)
		ScreenKit.chip(flow, "%s ×%s" % [Loc.t(DataRegistry.item(iid).get("name", iid)), qt], ScreenKit.item_icon(iid))
	for c in r.get("crates", []):
		var cid := str(c.id)
		ScreenKit.chip(flow, "%s ×%d" % [Loc.t(DataRegistry.item(cid).get("name", cid)), int(c.get("qty", 1))], ScreenKit.item_icon(cid))
	ScreenKit.chip(flow, Loc.tf("UI_RS_DU_RAID_ESSENCE", {"n": int(DataRegistry.rules("era_rules").get("era_essence", {}).get("drop", {}).get("raid_boss", 0)) * combat._era()}),
		IconLib.ui("ui_currency_era_essence"), tr("UI_RS_DU_TIP_ESSENCE"), Color("#7fc8ff"))
	ScreenKit.chip(flow, Loc.tf("UI_RS_DU_RAID_MERC_XP", {"n": int(rd.get("merc_xp", 0))}), null, tr("UI_RS_DU_TIP_MERC_XP"), Color("#4FA8F5"))
	var uniq: Array = boss.get("unique_drops", [])
	if not uniq.is_empty():
		parent.add_child(ScreenKit.muted(Loc.tf("UI_RS_DU_RAID_UNIQUES_SUB", {"p": NumberFormat.fmt_pct(5.0)})))
		var uf := HFlowContainer.new()
		uf.add_theme_constant_override("h_separation", 6)
		uf.add_theme_constant_override("v_separation", 6)
		parent.add_child(uf)
		for uid in uniq:
			ScreenKit.chip(uf, Loc.t(DataRegistry.item(str(uid)).get("name", str(uid))), ScreenKit.item_icon(str(uid)), "", Color("#c65aa8"))


## Suggerimento «cosa fare ora» per la scheda Incursioni.
func hint() -> Array:
	var m: Variant = combat.ctx.get_system("mercenaries")
	var any_open := false
	for r in _eg().raids():
		any_open = any_open or bool(r.unlocked)
	if combat.endgame_mode() == "raid":
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_RAID_RUNNING")]
	if not any_open:
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_RAID_LOCKED")]
	if m == null or (m.roster() as Array).is_empty():
		return [ScreenKit.Kind.TODO, tr("UI_RS_DU_H_RAID_NOMERC"), tr("UI_RS_GU_GO_HIRE"), ScreenKit.target("guild", {"tab": 1})]
	if _eg().raid_cd(_selected) > 0.0:
		return [ScreenKit.Kind.INFO, Loc.tf("UI_RS_DU_H_RAID_CD", {"time": NumberFormat.fmt_time(_eg().raid_cd(_selected))})]
	return [ScreenKit.Kind.TODO, tr("UI_RS_DU_H_RAID_READY")]


func _phases_text(boss: Dictionary) -> String:
	var parts: PackedStringArray = []
	var i := 1
	for ph in boss.get("phases", []):
		parts.append(Loc.tf("UI_RAID_PHASE_ROW", {"n": i, "pct": int(ph.hp_pct), "style": tr("UI_RAID_STYLE_" + str(ph.style).to_upper())}))
		i += 1
	return tr("UI_RAID_PHASES") + " " + "  ·  ".join(parts) if not parts.is_empty() else ""


func _update_party_summary(party: Array) -> void:
	var prev := _eg().raid_preview(_selected, party)
	if prev.is_empty():
		return
	var fx: Dictionary = prev.fx
	_power_label.text = Loc.tf("UI_RAID_POWER_LINE", {"p": NumberFormat.fmt(float(fx.power)), "r": NumberFormat.fmt(float(fx.required)),
		"pct": NumberFormat.fmt_pct(float(fx.ratio) * 100.0), "h": NumberFormat.fmt(float(fx.get("hero_power", 0.0))), "m": NumberFormat.fmt(float(fx.power) - float(fx.get("hero_power", 0.0)))})
	var f := float(fx.ratio)
	CombatUi.set_bar(_power_bar, f / 1.5)
	CombatUi.set_bar_color(_power_bar, CombatUi.COL_SAFE["green"] if f >= 1.0 else (CombatUi.COL_SAFE["yellow"] if f >= 0.6 else CombatUi.COL_SAFE["red"]))
	var rr: Dictionary = DataRegistry.rules("mercenary_rules").get("raid_roles", {})
	_fx_label.text = Loc.tf("UI_RAID_FX_LINE", {
		"dr": NumberFormat.fmt_pct(absf(float(rr.defender.dmg_taken_pct)) * float(fx.defender)),
		"heal": NumberFormat.decimal(float(rr.healer.regen_pct_per_s) * float(fx.healer), 2, Loc.locale()),
		"dmg": NumberFormat.fmt_pct(float(rr.striker.dmg_pct) * float(fx.striker))})
	var level := str(prev.level)
	EndgamePanel.paint_risk(_risk, level, Loc.tf("UI_RAID_RISK_" + level.to_upper(), {"win": NumberFormat.fmt_pct(float(prev.p_win) * 100.0)}))
	_risk.tooltip_text = Loc.tf("UI_RAID_RISK_TIP", {"time": NumberFormat.fmt_time(float(prev.time_s)), "food": int(prev.food),
		"have": int(prev.food_have), "hit": NumberFormat.fmt(float(prev.worst_hit)), "min": NumberFormat.fmt_pct(float(prev.hp_min_pct))})


# ------------------------------------------------------------------ combattimento in corso

func _refresh_run() -> void:
	var a := combat._act()
	var rd := _eg().raid_def(str(a.raid))
	_run_title.text = "%s — %s" % [Loc.t(rd.name), NumberFormat.fmt_time(float(a.get("t", 0.0)))]
	var e: Dictionary = a.get("enemy", {})
	var st := combat.hero_stats()
	CombatUi.set_bar(_run_hero_bar, combat.hp() / maxf(1.0, float(st.hp)))
	_run_hero.text = "%s  %s / %s" % [tr("UI_COMBAT_HERO"), NumberFormat.fmt(floorf(combat.hp())), NumberFormat.fmt(float(st.hp))]
	var mon := combat._enemy_mon(a)
	if e.is_empty():
		_run_enemy.text = tr("UI_COMBAT_FIGHTING") if float(a.get("revive_s", 0.0)) <= 0.0 else \
			Loc.tf("UI_COMBAT_DEAD", {"time": NumberFormat.fmt_time(float(a.revive_s))})
		CombatUi.set_bar(_run_enemy_bar, 0.0)
	else:
		var ph := int(e.get("phase", 0))
		var styles: Array = mon.get("phases", [])
		var sty := str(styles[clampi(ph, 0, styles.size() - 1)].style) if not styles.is_empty() else str(mon.style)
		_run_enemy.text = "%s  %s / %s  ·  %s %d/%d (%s)" % [Loc.t(mon.name), NumberFormat.fmt(ceilf(float(e.hp))),
			NumberFormat.fmt(float(e.get("max", 1.0))), tr("UI_RAID_PHASE"), ph + 1, maxi(1, styles.size()),
			tr("UI_RAID_STYLE_" + sty.to_upper())]
		CombatUi.set_bar(_run_enemy_bar, float(e.hp) / maxf(1.0, float(e.get("max", 1.0))))
		if ph != _last_phase:
			_last_phase = ph
			show_banner(Loc.tf("UI_RAID_PHASE_BANNER", {"n": ph + 1, "style": tr("UI_RAID_STYLE_" + sty.to_upper())}), CombatUi.COL_ABILITY)
			if _portrait != null:
				CombatUi.shake(_portrait, 10.0, 0.3)
	var fx: Dictionary = a.get("fx", {})
	_run_info.text = Loc.tf("UI_RAID_RUN_INFO", {"ratio": NumberFormat.fmt_pct(float(fx.get("ratio", 0.0)) * 100.0),
		"n": (a.get("party", []) as Array).size()})
	_run_marks.queue_redraw()


func _draw_marks() -> void:
	var w := _run_marks.size.x
	for pct in Formulas.k().combat.rules.raid_phase_hp_pct:
		var x := w * float(pct) / 100.0
		_run_marks.draw_line(Vector2(x, 0), Vector2(x, 10), Color(1, 1, 1, 0.7), 2.0)


func _consume_log() -> void:
	for e in combat.log_since(_last_log_id):
		_last_log_id = int(e.id)
		match str(e.k):
			"raid_start":
				_last_phase = 0
			"raid_done":
				show_banner(tr("UI_RAID_VICTORY"), CombatUi.COL_WARN, 2.4)
				_run_info.text = Loc.tf("UI_RAID_LOG_DONE", {"gold": NumberFormat.fmt(float(e.gold)), "time": NumberFormat.fmt_time(float(e.t)),
					"items": EndgamePanel.items_text(e.items, false)})
				_sig = ""
			"raid_failed":
				show_banner(tr("UI_RAID_DEFEAT"), CombatUi.COL_HURT, 2.4)
				if _portrait != null:
					CombatUi.shake(_portrait, 12.0, 0.35)
				_run_info.text = Loc.tf("UI_RAID_LOG_FAIL", {"n": (e.injured as Array).size()})
				_sig = ""
			"stance":
				show_banner(Loc.tf("UI_C3_STANCE_BANNER", {"style": tr("UI_RAID_STYLE_" + str(e.style).to_upper())}), CombatUi.COL_ABILITY)
			"heavy":
				CombatUi.flash(_run_hero_bar, Color(1.6, 0.6, 0.6), 0.3)
				if _portrait != null:
					CombatUi.shake(_portrait, 8.0, 0.25)
			"mech":
				if _portrait != null:
					CombatUi.shake(_portrait, 6.0, 0.2)
