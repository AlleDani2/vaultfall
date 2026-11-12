class_name RiftPanel
extends EndgamePanel
## Scheda La Breccia (docs/05 §9): piani infiniti (livello 100 + piano, ×1,06 di statistiche per piano), 5 mostri a piano e
## un Guardiano ogni 10, affissi cumulativi, Frammenti e Casse della Breccia, ripartenza dopo ogni Guardiano battuto, piano
## massimo. Animazioni a tween: barra del piano, striscione di piano/Guardiano superato, scossa del mostro, rimbalzo Frammenti.

const AFFIX_KEYS := {"hp_pct": "UI_RAID_AFFIX_HP", "dmg_pct": "UI_RAID_AFFIX_DMG", "evasion_pct": "UI_RAID_AFFIX_EVA",
	"lifesteal_pct": "UI_RAID_AFFIX_LS", "defense_pct": "UI_RAID_AFFIX_DEF"}

var _stats: Label
var _st_best: ScreenKit.KitStat
var _st_guard: ScreenKit.KitStat
var _st_runs: ScreenKit.KitStat
var _st_deaths: ScreenKit.KitStat
var _st_shards: ScreenKit.KitStat
var _lock_box: Control
var _go_reason: Label
var _start_opt: OptionButton
var _start_ids: Array = []
var _go_btn: Button
var _stop_btn: Button
var _estimate: Label
var _run_box: VBoxContainer
var _run_title: Label
var _run_floor_bar: ProgressBar
var _run_enemy: Label
var _run_enemy_bar: ProgressBar
var _run_hero: Label
var _run_hero_bar: ProgressBar
var _run_affix: Label
var _run_log: Label
var _info: VBoxContainer
var _shop: VBoxContainer
var _open_state: Dictionary = {}
var _locked: Label
var _sig: String = ""
var _last_floor: int = 0
var _shards_run: int = 0


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)
	var lk := ScreenKit.card(root, Color("#a85a5a"), 4)
	_lock_box = ScreenKit.panel_of(lk)
	_locked = CombatUi.text_label("", true)
	_locked.add_theme_color_override("font_color", CombatUi.COL_WARN)
	lk.add_child(_locked)
	var rq := str(_eg().rift_def().get("unlock", {}).get("quest", ""))
	var rt := ReqLink.target_for_quest(rq)
	if not rt.is_empty():
		lk.add_child(ScreenKit.go_button(tr("UI_RS_GO_QUESTS"), rt, true))
	_stats = CombatUi.text_label("MonoLabel", true)           # resta per compatibilità: il testo completo è nel tooltip dei numeri
	_stats.visible = false
	root.add_child(_stats)
	var srow := ScreenKit.stat_row(root)
	_st_best = ScreenKit.stat(srow, "UI_RS_DU_RIFT_ST_BEST", "UI_RS_DU_RIFT_TIP_BEST")
	_st_guard = ScreenKit.stat(srow, "UI_RS_DU_RIFT_ST_GUARD", "UI_RS_DU_RIFT_TIP_GUARD")
	_st_runs = ScreenKit.stat(srow, "UI_RS_DU_RIFT_ST_RUNS", "UI_RS_DU_RIFT_TIP_RUNS")
	_st_deaths = ScreenKit.stat(srow, "UI_RS_DU_RIFT_ST_DEATHS", "UI_RS_DU_RIFT_TIP_DEATHS")
	_st_shards = ScreenKit.stat(srow, "UI_RS_DU_RIFT_ST_SHARDS", "UI_RS_DU_RIFT_TIP_SHARDS")
	root.add_child(make_banner())
	_run_box = VBoxContainer.new()
	_run_box.add_theme_constant_override("separation", 4)
	root.add_child(_run_box)
	_run_title = CombatUi.text_label("SectionLabel")
	_run_box.add_child(_run_title)
	_run_floor_bar = CombatUi.bar(Color("c8a24a"), 12.0)
	_run_box.add_child(_run_floor_bar)
	_run_enemy = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_enemy)
	_run_enemy_bar = CombatUi.bar(Color("b8433b"), 14.0)
	_run_box.add_child(_run_enemy_bar)
	_run_hero = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_hero)
	_run_hero_bar = CombatUi.bar(Color("4f9d5d"), 12.0)
	_run_box.add_child(_run_hero_bar)
	_run_affix = CombatUi.text_label("", true)
	_run_box.add_child(_run_affix)
	_run_log = CombatUi.text_label("MutedLabel", true)
	_run_log.visible = false
	root.add_child(_run_log)
	var act := ScreenKit.card(root, ScreenKit.accent("dungeon"), 4, true)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	act.add_child(row)
	row.add_child(CombatUi.label("UI_RAID_RIFT_START_FROM", ""))
	_start_opt = OptionButton.new()
	_start_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_start_opt.item_selected.connect(func(_i: int) -> void:
		_sig = ""
		refresh())
	row.add_child(_start_opt)
	_go_btn = Button.new()
	_go_btn.theme_type_variation = &"AccentButton"
	_go_btn.text = "UI_RAID_RIFT_ENTER"
	_go_btn.pressed.connect(_on_enter)
	row.add_child(_go_btn)
	_stop_btn = Button.new()
	_stop_btn.text = "UI_RAID_RIFT_LEAVE"
	_stop_btn.pressed.connect(func() -> void:
		combat.stop()
		_sig = ""
		refresh())
	row.add_child(_stop_btn)
	_go_reason = ScreenKit.reason_label()
	act.add_child(_go_reason)
	_estimate = CombatUi.text_label("", true)
	act.add_child(_estimate)
	_info = EstateDungeonKit.disclosure(root, "UI_F9_RIFT_INFO", _open_state, "info")
	var shop_body := EstateDungeonKit.disclosure(root, "UI_RAID_SHOP_RIFT_TITLE", _open_state, "shop")
	_shop = build_shop(shop_body, "rift_market")
	_fill_info()
	_fill_start_options()


## Suggerimento «cosa fare ora» per la scheda La Breccia.
func hint() -> Array:
	if not _eg().rift_unlocked():
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_RIFT_LOCKED")]
	if combat.endgame_mode() == "rift":
		return [ScreenKit.Kind.INFO, tr("UI_RS_DU_H_RIFT_RUNNING")]
	return [ScreenKit.Kind.TODO, tr("UI_RS_DU_H_RIFT_READY")]


func _fill_start_options() -> void:
	var prev := _selected_start()
	_start_opt.clear()
	_start_ids = _eg().rift_start_options()
	var sel := 0
	for f in _start_ids:
		_start_opt.add_item(Loc.tf("UI_RAID_RIFT_FLOOR", {"n": int(f)}))
		if int(f) == prev:
			sel = _start_opt.item_count - 1
	_start_opt.select(sel)


func _selected_start() -> int:
	var i := _start_opt.selected if _start_opt != null else -1
	return int(_start_ids[i]) if i >= 0 and i < _start_ids.size() else 1


func _fill_info() -> void:
	CombatUi.clear_children(_info)
	var rd := _eg().rift_def()
	if rd.is_empty():
		return
	_info.add_child(CombatUi.label("UI_RAID_RIFT_RULES", "SectionLabel"))
	var sh: Dictionary = rd.shards
	var cc: Dictionary = rd.crate_chance
	var rc := ScreenKit.card(_info, Color(ScreenKit.EDGE), 4)
	rc.add_child(ScreenKit.muted(Loc.tf("UI_RS_DU_RIFT_LEVEL_RULE", {"lvl": int(rd.floor_level_base)})))
	var nums := ScreenKit.stat_row(rc)
	var a1 := ScreenKit.stat(nums, "UI_RS_DU_RIFT_R_MONSTERS", "UI_RS_DU_RIFT_TIP_R_MONSTERS", Color(ScreenKit.GOLD))
	a1.set_value(str(int(rd.monsters_per_floor)), tr("UI_RS_DU_RIFT_UNIT_PER_FLOOR"))
	var a2 := ScreenKit.stat(nums, "UI_RS_DU_RIFT_R_GUARD", "UI_RS_DU_RIFT_TIP_R_GUARD", Color(ScreenKit.GOLD))
	a2.set_value(str(int(rd.guardian_every)), tr("UI_RS_DU_RIFT_UNIT_FLOORS"))
	var a3 := ScreenKit.stat(nums, "UI_RS_DU_RIFT_R_SHARDS", "UI_RS_DU_RIFT_TIP_R_SHARDS", Color(ScreenKit.GOLD))
	a3.set_value(str(int(sh.base)), tr("UI_RS_DU_RIFT_UNIT_PER_FLOOR"))
	a3.set_caption(Loc.tf("UI_RS_DU_RIFT_CAP_SHARDS", {"per": int(sh.per_floors)}))
	var a4 := ScreenKit.stat(nums, "UI_RS_DU_RIFT_R_CRATE", "UI_RS_DU_RIFT_TIP_R_CRATE", Color(ScreenKit.GOLD))
	a4.set_value(NumberFormat.fmt_pct(float(cc.base) * 100.0), tr("UI_RS_DU_RIFT_UNIT_PER_FLOOR"))
	a4.set_caption(Loc.tf("UI_RS_DU_RIFT_CAP_CRATE", {"cf": NumberFormat.fmt_pct(float(cc.per_floor) * 100.0), "cm": NumberFormat.fmt_pct(float(cc.max) * 100.0)}))
	rc.add_child(ScreenKit.muted(Loc.tf("UI_RS_DU_RIFT_GUARD_REWARD", {"guard": EndgamePanel.items_text(rd.guardian_rewards, false)})))
	_info.add_child(CombatUi.label("UI_RAID_RIFT_AFFIXES", "SectionLabel"))
	_info.add_child(ScreenKit.muted("UI_RS_DU_RIFT_AFFIX_SUB"))
	for af in rd.affixes:
		var v := ScreenKit.card(_info, Color("#8a8f9a"), 3)
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 10)
		v.add_child(arow)
		arow.add_child(ScreenKit.pill(Loc.tf("UI_RS_DU_RIFT_FROM", {"n": int(af.from_floor)}), Color("#e0b640")))
		var nm := CombatUi.text_label("", true)
		nm.text = Loc.t(af.name)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arow.add_child(nm)
		var ef := CombatUi.text_label("MonoLabel")
		ef.text = _affix_text(af)
		arow.add_child(ef)


func _affix_text(af: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in af.effect:
		parts.append(Loc.tf(str(AFFIX_KEYS.get(str(k), "UI_RAID_AFFIX_HP")), {"n": int(af.effect[k])}))
	return ", ".join(parts)


func _on_enter() -> void:
	if _eg().start_rift(_selected_start()):
		_shards_run = 0
		_last_floor = 0
		CombatUi.pop(_go_btn)
	else:
		EventBus.notice.emit("warning", tr("UI_RAID_RIFT_DENIED"), {})
	_sig = ""
	refresh()


func refresh() -> void:
	if combat == null:
		return
	var running := combat.endgame_mode() == "rift"
	_run_box.visible = running
	var rf: Dictionary = combat.state.rift
	var unlocked := _eg().rift_unlocked()
	_locked.text = "" if unlocked else tr("UI_RAID_RIFT_LOCKED")
	_lock_box.visible = not unlocked
	_stats.text = Loc.tf("UI_RAID_RIFT_STATS", {"best": int(rf.best), "g": int(rf.guardian), "runs": int(rf.runs), "deaths": int(rf.deaths),
		"shards": NumberFormat.fmt(float(rf.shards))})
	_st_best.set_value(str(int(rf.best)), tr("UI_RS_DU_RIFT_UNIT_FLOOR"))
	_st_guard.set_value(str(int(rf.guardian)), tr("UI_RS_DU_RIFT_UNIT_FLOOR"))
	_st_runs.set_value(str(int(rf.runs)), "")
	_st_deaths.set_value(str(int(rf.deaths)), "")
	_st_shards.set_value(NumberFormat.fmt(float(rf.shards)), "")
	if running:
		_refresh_run()
	_consume_log()
	var sig := "%d|%d|%s|%d|%d" % [int(rf.guardian), combat.hero_level(), str(running), combat.food_available(), _selected_start()]
	if sig != _sig:
		_sig = sig
		_fill_start_options()
		var start := _selected_start()
		if unlocked and not running:
			var lim := _eg().rift_estimate_limit(start)
			_estimate.text = Loc.tf("UI_RAID_RIFT_ESTIMATE", {"n": lim}) if lim < start + EndgameCombat.RIFT_FLOORS_CAP else tr("UI_RAID_RIFT_ESTIMATE_MAX")
		else:
			_estimate.text = ""
		fill_shop(_shop)
	ScreenKit.gate(_go_btn, tr("UI_RS_DU_RIFT_WHY_LOCKED") if not unlocked else (tr("UI_RS_DU_RIFT_WHY_RUNNING") if running else ""), _go_reason)
	_stop_btn.disabled = not running
	_stop_btn.tooltip_text = "" if running else tr("UI_RS_DU_WHY_NOT_INSIDE")
	_start_opt.disabled = running
	_start_opt.tooltip_text = tr("UI_RS_DU_RIFT_TIP_START")


func _refresh_run() -> void:
	var a := combat._act()
	var fl := int(a.floor)
	var total := _eg().rift_monsters_on(fl)
	var idx := int(a.idx)
	var guardian := idx >= int(_eg().rift_def().monsters_per_floor)
	_run_title.text = Loc.tf("UI_RAID_RIFT_RUN", {"floor": fl, "i": mini(idx + 1, total), "n": total}) + ("  —  " + tr("UI_RAID_RIFT_GUARDIAN") if guardian else "")
	CombatUi.set_bar(_run_floor_bar, float(idx) / float(maxi(1, total)), 0.25)
	var st := combat.hero_stats()
	CombatUi.set_bar(_run_hero_bar, combat.hp() / maxf(1.0, float(st.hp)))
	_run_hero.text = "%s  %s / %s" % [tr("UI_COMBAT_HERO"), NumberFormat.fmt(floorf(combat.hp())), NumberFormat.fmt(float(st.hp))]
	var e: Dictionary = a.get("enemy", {})
	if e.is_empty():
		_run_enemy.text = tr("UI_COMBAT_FIGHTING") if float(a.get("revive_s", 0.0)) <= 0.0 else \
			Loc.tf("UI_COMBAT_DEAD", {"time": NumberFormat.fmt_time(float(a.revive_s))})
		CombatUi.set_bar(_run_enemy_bar, 0.0)
	else:
		var mon := combat._enemy_mon(a)
		_run_enemy.text = "%s  (%s %d)  %s / %s" % [Loc.t(mon.name), tr("UI_COMBAT_LV"), int(mon.level),
			NumberFormat.fmt(ceilf(float(e.hp))), NumberFormat.fmt(float(e.get("max", 1.0)))]
		CombatUi.set_bar(_run_enemy_bar, float(e.hp) / maxf(1.0, float(e.get("max", 1.0))))
	var parts: PackedStringArray = []
	for af in _eg().rift_affixes(fl):
		parts.append(Loc.t(af.name))
	_run_affix.text = Loc.tf("UI_RAID_RIFT_ACTIVE_AFFIXES", {"list": ", ".join(parts) if not parts.is_empty() else tr("UI_RAID_RIFT_NO_AFFIX")})
	_last_floor = fl


func _consume_log() -> void:
	for e in combat.log_since(_last_log_id):
		_last_log_id = int(e.id)
		match str(e.k):
			"rift_floor":
				var shards := 0
				for it in e["items"]:
					if str(it.id) == "rift_shard":
						shards += int(it.qty)
				_shards_run += shards
				_run_log.visible = true
				_run_log.text = Loc.tf("UI_RAID_RIFT_LOG_FLOOR", {"floor": int(e.floor), "items": EndgamePanel.items_text(e["items"], false),
					"crates": (e["crates"] as Array).size(), "total": _shards_run})
				if bool(e.guardian):
					show_banner(Loc.tf("UI_RAID_RIFT_GUARDIAN_DOWN", {"floor": int(e.floor)}), CombatUi.COL_WARN, 2.2)
				else:
					show_banner(Loc.tf("UI_RAID_RIFT_FLOOR_DONE", {"floor": int(e.floor)}), CombatUi.COL_HEAL, 0.8)
				CombatUi.pop(_run_floor_bar, 1.1, 0.25)
				_sig = ""
			"rift_end":
				show_banner(tr("UI_RAID_RIFT_END_DIED") if bool(e.died) else tr("UI_RAID_RIFT_END"), CombatUi.COL_HURT if bool(e.died) else CombatUi.COL_WARN, 2.2)
				_run_log.visible = true
				_run_log.text = Loc.tf("UI_RAID_RIFT_LOG_END", {"floor": int(e.floor), "total": _shards_run})
				_sig = ""
			"heavy", "mech":
				CombatUi.flash(_run_hero_bar, Color(1.6, 0.6, 0.6), 0.3)
