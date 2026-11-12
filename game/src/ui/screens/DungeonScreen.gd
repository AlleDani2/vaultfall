extends GameScreen
## Dungeon (docs/05 §8): elenco con accesso (gettone della missione + livello), ondate e boss con le sue meccaniche,
## ricompense, traguardi di completamento, indicatore di rischio, corsa in corso con barra delle ondate. In alto le schede:
## Dungeon, Incursioni (squadra di mercenari), Boss mondiali, La Breccia (RaidPanel, WorldBossPanel, RiftPanel).
## Solo presentazione: legge e comanda CombatSystem.
## Animazioni a tween: scossa del ritratto del boss, striscione di vittoria o fallimento, barra delle ondate che avanza.

const SAFE_COLORS := {"green": Color("5fbf6a"), "yellow": Color("e0b640"), "red": Color("d9544d")}
const MILESTONE_KEYS := {10: "UI_C2_MILESTONE_10", 50: "UI_C2_MILESTONE_50", 250: "UI_C2_MILESTONE_250"}

var _combat: CombatSystem
var _selected: String = ""
var _last_log_id: int = 0
var _sig: String = ""
var _list: VBoxContainer
var _group := ButtonGroup.new()
var _detail: VBoxContainer
var _detail2: VBoxContainer
var _hint: ScreenKit.KitHint
var _purpose: Label
var _enter_reason: Label
var _run_box: VBoxContainer
var _run_title: Label
var _run_bar: ProgressBar
var _run_enemy: Label
var _run_enemy_bar: ProgressBar
var _run_hero_bar: ProgressBar
var _run_hero: Label
var _run_log: Label
var _banner: Label
var _portrait: TextureRect
var _enter_btn: Button
var _leave_btn: Button
var _repeat: CheckButton
var _risk_chip: Control
var _open_state: Dictionary = {}
var _intro: Dictionary = {}
var _fx: Control
var _boss_name_label: Label
var _tab: String = "dungeon"
var _tab_group := ButtonGroup.new()
var _tab_btns: Dictionary = {}
var _pages: Control
var _dungeon_page: Control
var _panels: Dictionary = {}


func open(params: Dictionary) -> void:
	_combat = Game.system("combat") as CombatSystem
	_build()
	var em := _combat.endgame_mode()
	var want := str(params.get("tab", {"raid": "raids", "wboss": "worldboss", "rift": "rift"}.get(em, "dungeon")))
	_selected = str(params.get("dungeon", ""))
	if _selected.is_empty():
		var p := _combat.dungeon_progress()
		_selected = str(p.get("id", "")) if not p.is_empty() else _first_unlocked()
	_last_log_id = _combat.log_last_id()
	_fill_list()
	_sig = ""
	_set_tab(want)
	refresh()


func _first_unlocked() -> String:
	var pick := ""
	for d in _combat.dungeons():
		if bool(d.unlocked):
			pick = str(d.id)
	if pick.is_empty():
		var all := _combat.dungeons()
		pick = str(all[0].id) if not all.is_empty() else ""
	return pick


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	_intro = EstateDungeonKit.title_row(outer, "UI_MENU_DUNGEON", "UI_RS_DU_PURPOSE_DUNGEON", "dungeon")
	_purpose = _intro.purpose as Label
	ScreenKit.cap_text(_purpose)
	_hint = ScreenKit.KitHint.new()
	_hint.setup(ScreenKit.accent("dungeon"))
	outer.add_child(_hint)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	outer.add_child(tabs)
	outer.move_child(_hint, tabs.get_index() + 1)          # l'avviso (cibo che non basta, nessun dungeon aperto) sta SOTTO le schede: non le sposta
	for t in [["dungeon", "UI_RAID_TAB_DUNGEON", "UI_RS_DU_TIP_TAB_DUNGEON"], ["raids", "UI_RAID_TAB_RAIDS", "UI_RS_DU_TIP_TAB_RAIDS"],
			["worldboss", "UI_RAID_TAB_WB", "UI_RS_DU_TIP_TAB_WB"], ["rift", "UI_RAID_TAB_RIFT", "UI_RS_DU_TIP_TAB_RIFT"]]:
		var tb := Button.new()
		tb.toggle_mode = true
		tb.button_group = _tab_group
		tb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		tb.text = tr(str(t[1]))
		tb.tooltip_text = str(t[2])
		tb.set_meta("name_key", str(t[1]))
		var tid := str(t[0])
		tb.pressed.connect(func() -> void: _set_tab(tid))
		ScreenKit.style_tab(tb, ScreenKit.accent("dungeon"))
		tabs.add_child(tb)
		_tab_btns[tid] = tb
	_pages = Control.new()
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.clip_contents = true
	outer.add_child(_pages)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	_pages.add_child(root)
	_dungeon_page = root
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right)
	# corsa in corso
	_run_box = VBoxContainer.new()
	_run_box.add_theme_constant_override("separation", 4)
	right.add_child(_run_box)
	_run_title = CombatUi.text_label("SectionLabel")
	_run_box.add_child(_run_title)
	_run_bar = CombatUi.bar(Color("c8a24a"), 14.0)
	_run_box.add_child(_run_bar)
	_run_enemy = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_enemy)
	_run_enemy_bar = CombatUi.bar(Color("b8433b"), 12.0)
	_run_box.add_child(_run_enemy_bar)
	_run_hero = CombatUi.text_label("MutedLabel")
	_run_box.add_child(_run_hero)
	_run_hero_bar = CombatUi.bar(Color("4f9d5d"), 12.0)
	_run_box.add_child(_run_hero_bar)
	_run_log = CombatUi.text_label("MutedLabel", true)
	_run_box.add_child(_run_log)
	_banner = CombatUi.text_label("TitleLabel")
	_banner.modulate.a = 0.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(_banner)
	# testata del dungeon scelto (nome, immagine, requisiti), poi AZIONE (Entra) e solo dopo i dettagli
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	var act := ScreenKit.card(right, ScreenKit.accent("dungeon"), 4, true)
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8)
	btns.add_theme_constant_override("v_separation", 6)
	act.add_child(btns)
	_enter_btn = Button.new()
	_enter_btn.theme_type_variation = &"AccentButton"
	_enter_btn.custom_minimum_size = Vector2(200, 48)           # è il fine della pagina: il pulsante più grande
	_enter_btn.pressed.connect(_on_enter)
	btns.add_child(_enter_btn)
	_leave_btn = Button.new()
	_leave_btn.text = "UI_C2_DUNGEON_LEAVE"
	_leave_btn.pressed.connect(func() -> void:
		_combat.stop()
		refresh())
	btns.add_child(_leave_btn)
	_repeat = CheckButton.new()
	_repeat.text = "UI_C2_DUNGEON_REPEAT"
	_repeat.tooltip_text = "UI_RS_DU_TIP_REPEAT"
	_repeat.toggled.connect(func(on: bool) -> void: _combat.set_dungeon_repeat(on))
	btns.add_child(_repeat)
	_enter_reason = ScreenKit.reason_label()
	act.add_child(_enter_reason)
	_detail2 = VBoxContainer.new()
	_detail2.add_theme_constant_override("separation", 8)
	right.add_child(_detail2)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)


## Cambia scheda: la scheda di fine gioco si crea la prima volta che serve.
func _set_tab(tab: String) -> void:
	if not _tab_btns.has(tab):
		tab = "dungeon"
	_tab = tab
	_purpose.text = {"dungeon": "UI_RS_DU_PURPOSE_DUNGEON", "raids": "UI_RS_DU_PURPOSE_RAIDS", "worldboss": "UI_RS_DU_PURPOSE_WB", "rift": "UI_RS_DU_PURPOSE_RIFT"}[tab]
	for k in _tab_btns:
		(_tab_btns[k] as Button).set_pressed_no_signal(k == tab)
	_dungeon_page.visible = tab == "dungeon"
	if tab != "dungeon" and not _panels.has(tab):
		var panel: EndgamePanel
		match tab:
			"raids":
				panel = RaidPanel.new()
			"worldboss":
				panel = WorldBossPanel.new()
			_:
				panel = RiftPanel.new()
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pages.add_child(panel)
		panel.setup(_combat)
		_panels[tab] = panel
	for k in _panels:
		(_panels[k] as Control).visible = k == tab
	refresh()


func _fill_list() -> void:
	CombatUi.clear_children(_list)
	for d in _combat.dungeons():
		_add_row(_list, d)


## Una riga = UN pulsante a scelta, su una riga sola («2. Cripta del Sale  ×3», «9. Nido del Tuono · Eroe 88+», «1. … · In corso»):
## zona e livello consigliato stanno nel tooltip e nel dettaglio. Così l'elenco di 10 dungeon pesa 10 controlli, non 100.
func _add_row(parent: Control, d: Dictionary) -> void:
	var did := str(d.id)
	var unlocked := bool(d.unlocked)
	var running := _combat.in_dungeon() and str(_combat.dungeon_progress().get("id", "")) == did
	var sub := Loc.tf("UI_RS_DU_ROW_SUB", {"zone": Loc.t(_combat.zone_def(str(d.def.zone)).get("name", "")), "lv": int(d.def.unlock.hero_level)})
	var tail := ""
	if running:
		tail = " · " + tr("UI_RS_DU_ST_RUNNING")
	elif not unlocked:
		tail = " · " + Loc.tf("UI_F9_DU_ROW_LV", {"lv": int(d.def.unlock.hero_level)})
	elif int(d.clears) > 0:
		tail = "  ×%d" % int(d.clears)
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART        # i nomi lunghi vanno a capo, mai tagliati
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text = "%d. %s%s" % [int(d.def.order), Loc.t(d.def.name), tail]
	b.tooltip_text = Loc.t(d.def.name) + "\n" + sub
	if not unlocked:
		b.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM))
	ScreenKit.style_tab(b, ScreenKit.accent("dungeon"))
	b.set_pressed_no_signal(did == _selected)
	b.pressed.connect(func() -> void:
		_selected = did
		_sig = ""
		refresh())
	parent.add_child(b)


func refresh() -> void:
	if _combat == null:
		return
	if _tab != "dungeon" and _panels.has(_tab):
		(_panels[_tab] as EndgamePanel).refresh()
	var progress := _combat.dungeon_progress()
	_run_box.visible = not progress.is_empty()
	if not progress.is_empty():
		_refresh_run(progress)
	_consume_log()
	var clears := 0
	for d in _combat.dungeons():
		clears += int(d.clears)
	var sig := "%s|%d|%s|%d|%d|%s" % [_selected, clears, str(_combat.in_dungeon()), _combat.hero_level(), _combat.food_available(),
		str(_combat.state.dungeon_repeat)]
	if sig != _sig:
		_sig = sig
		_fill_list()
		_fill_detail()
	_refresh_tab_labels()
	var in_run := _combat.in_dungeon()
	var d := _combat.dungeon_def(_selected)
	_enter_btn.text = tr("UI_C2_DUNGEON_ENTER")
	var why := ""
	if d.is_empty():
		why = tr("UI_RS_DU_WHY_NONE")
	elif not _combat.dungeon_unlocked(_selected):
		why = _lock_reason(d)
	elif in_run and str(progress.get("id", "")) == _selected:
		why = tr("UI_RS_DU_WHY_INSIDE")
	ScreenKit.gate(_enter_btn, why, _enter_reason)
	_leave_btn.disabled = not in_run
	_leave_btn.tooltip_text = "" if in_run else tr("UI_RS_DU_WHY_NOT_INSIDE")
	_repeat.set_pressed_no_signal(bool(_combat.state.dungeon_repeat))
	_refresh_hint(d, in_run)


## Una sola frase sul requisito che manca (livello prima, poi la missione/chiave).
func _lock_reason(d: Dictionary) -> String:
	var need := int(d.unlock.hero_level)
	var now := _combat.hero_unlock_level()
	if now < need:
		return Loc.tf("UI_RS_DU_WHY_LEVEL", {"lv": need, "now": now})
	var qid := str(d.unlock.get("quest", ""))
	if qid != "":
		return Loc.tf("UI_RS_DU_WHY_QUEST", {"quest": Loc.t(DataRegistry.get_def("quests", qid).get("title", qid))})
	return Loc.tf("UI_C2_DUNGEON_LOCKED", {"lv": need})


## «Nuovo» UNA volta sola, sulla scheda (non su ogni riga): c'è qualcosa di sbloccato e mai completato.
func _refresh_tab_labels() -> void:
	var fresh_dungeon := false
	for dd in _combat.dungeons():
		fresh_dungeon = fresh_dungeon or (bool(dd.unlocked) and int(dd.clears) <= 0)
	var fresh_raid := false
	if _combat.eg != null:
		for r in _combat.eg.raids():
			fresh_raid = fresh_raid or (bool(r.unlocked) and int(r.clears) <= 0)
	for k in _tab_btns:
		var tb: Button = _tab_btns[k]
		var base := tr(str(tb.get_meta("name_key")))
		var mark := ""
		if k == "dungeon" and fresh_dungeon:
			mark = " · " + tr("UI_RS_DU_ST_NEW")
		elif k == "raids" and fresh_raid:
			mark = " " + EstateDungeonKit.DOT_MARK          # il «Nuovo» a parole è uno solo (sulla scheda Dungeon); le Incursioni hanno il puntino
		tb.text = base + mark


## Barra «cosa fare» SOLO se serve: nessun dungeon aperto (con il «Vai») o cibo che non basta davvero (con il «Vai» a procurarselo).
## Il rischio è il chip nel dettaglio e basta (D18); le altre schede mostrano solo i suggerimenti con un'azione o un avviso.
func _refresh_hint(d: Dictionary, in_run: bool) -> void:
	if _tab != "dungeon":
		var h: Array = (_panels[_tab] as EndgamePanel).hint() if _panels.has(_tab) else []
		if h.is_empty() or not (h.size() > 2 or int(h[0]) == int(ScreenKit.Kind.WARN)):
			_hint.visible = false
		else:
			_hint.visible = true
			_hint.show_hint(h[0], str(h[1]), str(h[2]) if h.size() > 2 else "", (h[3] as Dictionary) if h.size() > 3 else {})
		return
	_hint.visible = false
	if in_run:
		return
	var any_open := false
	for dd in _combat.dungeons():
		any_open = any_open or bool(dd.unlocked)
	if not any_open:
		var qid := str(d.unlock.get("quest", "")) if not d.is_empty() else ""
		var t := ReqLink.target_for_quest(qid)
		_hint.visible = true
		_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_DU_H_NONE_OPEN"), tr("UI_RS_GO_QUESTS") if not t.is_empty() else "", t)
		return
	if d.is_empty() or not _combat.dungeon_unlocked(_selected):
		return
	var risk := _combat.dungeon_risk(_selected)
	if risk.is_empty() or float(risk.food_per_run) <= float(risk.food_have):
		return
	_hint.visible = true
	var text := tr("UI_F9_DU_FOOD_NONE") if is_inf(float(risk.food_per_run)) else Loc.tf("UI_F9_DU_FOOD_SHORT", {"need": NumberFormat.fmt(ceilf(float(risk.food_per_run))), "have": int(risk.food_have)})
	if ScreenKit.available("skill:cooking"):
		_hint.show_hint(ScreenKit.Kind.WARN, text, tr("UI_RS_GO_COOK"), ScreenKit.target("skill:cooking"))
	elif ScreenKit.available("market"):
		_hint.show_hint(ScreenKit.Kind.WARN, text, tr("UI_RS_GO_MARKET"), ScreenKit.target("market"))
	else:
		_hint.show_hint(ScreenKit.Kind.WARN, text)


func _refresh_run(p: Dictionary) -> void:
	var d := _combat.dungeon_def(str(p.id))
	_run_title.text = Loc.tf("UI_C2_DUNGEON_WAVE", {"name": Loc.t(d.name), "n": int(p.wave) + 1, "total": int(p.total)})
	CombatUi.set_bar(_run_bar, float(p.wave) / maxf(1.0, float(p.total)), 0.25)
	var a: Dictionary = GameState.data.get("activity", {})
	var e: Dictionary = a.get("enemy", {})
	var st := _combat.hero_stats()
	CombatUi.set_bar(_run_hero_bar, _combat.hp() / maxf(1.0, float(st.hp)))
	_run_hero.text = "%s  %s / %s" % [tr("UI_COMBAT_HERO"), NumberFormat.fmt(floorf(_combat.hp())), NumberFormat.fmt(float(st.hp))]
	if e.is_empty():
		_run_enemy.text = tr("UI_COMBAT_FIGHTING") if float(a.get("revive_s", 0.0)) <= 0.0 else \
			Loc.tf("UI_COMBAT_DEAD", {"time": NumberFormat.fmt_time(float(a.revive_s))})
		CombatUi.set_bar(_run_enemy_bar, 0.0)
		return
	var mon := _combat._enemy_mon(a)
	_run_enemy.text = "%s  (%s %d)  %s / %s" % [Loc.t(mon.name), tr("UI_COMBAT_LV"), int(mon.level),
		NumberFormat.fmt(ceilf(float(e.hp))), NumberFormat.fmt(float(e.get("max", 1.0)))]
	CombatUi.set_bar(_run_enemy_bar, float(e.hp) / maxf(1.0, float(e.get("max", 1.0))))


func _fill_detail() -> void:
	CombatUi.clear_children(_detail)
	CombatUi.clear_children(_detail2)
	_portrait = null
	var d := _combat.dungeon_def(_selected)
	if d.is_empty():
		return
	var unlocked := _combat.dungeon_unlocked(_selected)
	var zone := _combat.zone_def(str(d.zone))
	var boss: Dictionary = DataRegistry.get_def("monsters", str(d.boss))
	# testata: nome + UN chip di rischio (il dettaglio dei numeri nel suo tooltip), poi una sola riga di dati
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var title := CombatUi.text_label("SectionLabel")           # titolo di SEZIONE (il titolo di pagina è «Dungeon» in alto)
	title.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	title.add_theme_font_size_override("font_size", UiType.PAGE)
	title.text = Loc.t(d.name)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var risk := _combat.dungeon_risk(_selected)
	if unlocked and not risk.is_empty():
		var lvl := str(risk.level)
		var food_txt: String = tr("UI_COMBAT_FOOD_INF") if is_inf(float(risk.food_per_run)) else NumberFormat.fmt(ceilf(float(risk.food_per_run)))
		var tip := Loc.tf("UI_C2_DUNGEON_RISK_TIP", {"hit": NumberFormat.fmt(float(risk.worst_hit)),
			"thr": NumberFormat.fmt(float(risk.threshold_hp)), "food": food_txt, "have": int(risk.food_have),
			"time": NumberFormat.fmt_time(float(risk.run_time))})
		_risk_chip = EstateDungeonKit.risk_chip(lvl, tr("UI_COMBAT_SAFE_" + lvl.to_upper()), tip)
		_risk_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(_risk_chip)
	else:
		_risk_chip = null
	var sub := ScreenKit.muted("")
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.text = Loc.tf("UI_F9_DU_SUB", {"rooms": (d.waves as Array).size() + 1, "zone": Loc.t(zone.get("name", "")), "boss": Loc.t(boss.name),
		"lv": int(boss.level), "n": _combat.dungeon_clears(_selected)})
	_detail.add_child(sub)
	_detail.add_child(CombatUi.banner_rect(str(d.get("banner", ""))))
	# requisiti (solo se bloccato): spunta verde/rossa con strada per ottenerli
	if not unlocked:
		var rq := ScreenKit.card(_detail, Color("#a85a5a"), 4)
		rq.add_child(ScreenKit.label("UI_RS_DU_REQS", "SectionLabel"))
		var need := int(d.unlock.hero_level)
		var now := _combat.hero_unlock_level()
		ScreenKit.req_row(rq, now >= need, Loc.tf("UI_RS_DU_REQ_LEVEL", {"lv": need, "now": now}), ScreenKit.target("combat") if ScreenKit.available("combat") else {}, tr("UI_RS_GO_COMBAT"))
		var qid := str(d.unlock.get("quest", ""))
		if qid != "":
			var qdone := ((GameState.data.get("quests", {}) as Dictionary).get("done", []) as Array).has(qid)
			ScreenKit.req_row(rq, qdone and (GameState.data.get("unlocks", []) as Array).has("dungeon:" + _selected),
				Loc.tf("UI_RS_DU_REQ_QUEST", {"quest": Loc.t(DataRegistry.get_def("quests", qid).get("title", qid))}), ReqLink.target_for_quest(qid), tr("UI_RS_GO_QUESTS"))
	# premi (sempre visibili: sono ciò che si decide)
	_detail2.add_child(CombatUi.label("UI_C2_DUNGEON_REWARD", "SectionLabel"))          # sotto «Entra»: prima l'azione, poi i dettagli
	_reward_chips(_detail2, d, boss)
	# boss e meccaniche: a richiesta
	var boss_body := EstateDungeonKit.disclosure(_detail2, "UI_F9_DU_BOSS_MECH", _open_state, "boss")
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	boss_body.add_child(brow)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(128, 128)
	_portrait.texture = IconLib.portrait("monsters", str(boss.id))
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	brow.add_child(_portrait)
	var bcol := VBoxContainer.new()
	bcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcol.add_theme_constant_override("separation", 4)
	brow.add_child(bcol)
	_boss_name_label = CombatUi.text_label("MonoLabel")
	_boss_name_label.text = "%s  (%s %d)" % [Loc.t(boss.name), tr("UI_COMBAT_LV"), int(boss.level)]
	bcol.add_child(_boss_name_label)
	if boss.has("desc"):
		var bd := CombatUi.text_label("MutedLabel", true)
		bd.text = Loc.t(boss.desc)
		bcol.add_child(bd)
	var mech: Dictionary = _combat.mechanics()
	for mid in boss.get("mechanics", []):
		var m: Dictionary = mech.get(str(mid), {})
		ScreenKit.mech_row(bcol, Loc.t(m.get("name", "")), Loc.t(m.get("desc", "")))
	# ondate: ogni mostro una sola volta, con quante volte compare
	var waves_body := EstateDungeonKit.disclosure(_detail2, "UI_C2_DUNGEON_WAVES", _open_state, "waves")
	waves_body.add_child(ScreenKit.muted("UI_RS_DU_WAVES_SUB"))
	var order: Array = []
	var count: Dictionary = {}
	for w in d.waves:
		var mid := str(w.monster)
		if not count.has(mid):
			order.append(mid)
		count[mid] = int(count.get(mid, 0)) + 1
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	waves_body.add_child(flow)
	for mid in order:
		var wm: Dictionary = DataRegistry.get_def("monsters", str(mid))
		var txt := Loc.t(wm.get("name", ""))
		if int(count[mid]) > 1:
			txt += " ×%d" % int(count[mid])
		ScreenKit.chip(flow, txt)
	ScreenKit.chip(flow, Loc.t(boss.name), null, tr("UI_RS_DU_TIP_FINAL_BOSS"), Color("#e0b640"))
	# record: traguardi di completamento
	var rec_body := EstateDungeonKit.disclosure(_detail2, "UI_F9_DU_RECORD", _open_state, "record")
	rec_body.add_child(ScreenKit.muted("UI_RS_DU_MILESTONES_SUB"))
	var clears := _combat.dungeon_clears(_selected)
	for ms in d.get("mastery_milestones", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rec_body.add_child(row)
		var l := CombatUi.text_label("", true)
		l.custom_minimum_size = Vector2(150, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = Loc.tf(str(MILESTONE_KEYS.get(int(ms.completions), "UI_C2_MILESTONE_10")), {"n": int(ms.completions)})
		row.add_child(l)
		var b := CombatUi.bar(Color("c8a24a") if clears < int(ms.completions) else Color("5fbf6a"), 10.0)
		b.custom_minimum_size = Vector2(90, 10)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.value = minf(1.0, float(clears) / float(ms.completions))
		row.add_child(b)
		var cl := CombatUi.text_label("MonoLabel")
		cl.custom_minimum_size = Vector2(70, 0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.text = "%d / %d" % [mini(clears, int(ms.completions)), int(ms.completions)]
		row.add_child(cl)


## Ricompense come riquadri con icona (oro, oggetti, casse, unici del boss) invece di una riga di testo.
func _reward_chips(parent: Control, d: Dictionary, boss: Dictionary) -> void:
	var scopes: Array = [str(d.id), "all"]
	var r: Dictionary = d.completion_reward
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	var gold := Modifiers.apply(float(r.get("gold", 0)), "dungeon_loot_pct", scopes)
	ScreenKit.chip(flow, Loc.tf("UI_C2_REWARD_GOLD", {"n": NumberFormat.fmt(gold)}), IconLib.ui("ui_currency_gold"), tr("UI_RS_DU_TIP_REWARD_GOLD"), Color("#c8a24a"))
	for it in r.get("items", []):
		var q: Variant = it.get("qty", 1)
		var qt := "%d–%d" % [int(q[0]), int(q[1])] if q is Array else str(int(q))
		var iid := str(it.item)
		ScreenKit.chip(flow, "%s ×%s" % [Loc.t(DataRegistry.item(iid).get("name", iid)), qt], ScreenKit.item_icon(iid))
	for c in r.get("crates", []):
		var cid := str(c.id)
		ScreenKit.chip(flow, "%s ×%d" % [Loc.t(DataRegistry.item(cid).get("name", cid)), int(c.get("qty", 1))], ScreenKit.item_icon(cid))
	var uniq: Array = boss.get("unique_drops", [])
	if not uniq.is_empty():
		parent.add_child(ScreenKit.muted("UI_RS_DU_UNIQUES_SUB"))
		var uf := HFlowContainer.new()
		uf.add_theme_constant_override("h_separation", 6)
		uf.add_theme_constant_override("v_separation", 6)
		parent.add_child(uf)
		for uid in uniq:
			ScreenKit.chip(uf, Loc.t(DataRegistry.item(str(uid)).get("name", str(uid))), ScreenKit.item_icon(str(uid)), "", Color("#c65aa8"))


func _reward_label(d: Dictionary) -> Label:
	var l := CombatUi.text_label("", true)
	var scopes: Array = [str(d.id), "all"]
	var r: Dictionary = d.completion_reward
	var parts: PackedStringArray = []
	var gold := Modifiers.apply(float(r.get("gold", 0)), "dungeon_loot_pct", scopes)
	parts.append(Loc.tf("UI_C2_REWARD_GOLD", {"n": NumberFormat.fmt(gold)}))
	for it in r.get("items", []):
		var q: Variant = it.get("qty", 1)
		var qt := "%d–%d" % [int(q[0]), int(q[1])] if q is Array else str(int(q))
		parts.append("%s ×%s" % [Loc.t(DataRegistry.item(str(it.item)).get("name", str(it.item))), qt])
	for c in r.get("crates", []):
		parts.append("%s ×%d" % [Loc.t(DataRegistry.item(str(c.id)).get("name", str(c.id))), int(c.get("qty", 1))])
	var boss: Dictionary = DataRegistry.get_def("monsters", str(d.boss))
	var uniq: PackedStringArray = []
	for uid in boss.get("unique_drops", []):
		uniq.append(Loc.t(DataRegistry.item(str(uid)).get("name", str(uid))))
	var txt := "; ".join(parts)
	if not uniq.is_empty():
		txt += "\n" + Loc.tf("UI_C2_REWARD_UNIQUES", {"list": ", ".join(uniq)})
	l.text = txt
	return l


func _on_enter() -> void:
	if _combat.start_dungeon(_selected):
		CombatUi.pop(_enter_btn)
	else:
		EventBus.notice.emit("warning", tr("UI_C2_DUNGEON_DENIED"), {})
	_sig = ""
	refresh()


func _consume_log() -> void:
	for e in _combat.log_since(_last_log_id):
		_last_log_id = int(e.id)
		match str(e.k):
			"dungeon_done":
				_show_banner(tr("UI_C2_DUNGEON_CLEARED"), Color("e0b640"))
				CombatUi.pop(_banner, 1.3, 0.4)
				var dname := Loc.t(_combat.dungeon_def(str(e.d)).get("name", ""))
				_run_log.text = Loc.tf("UI_C2_LOG_DUNGEON_DONE", {"name": dname, "gold": NumberFormat.fmt(float(e.gold))}) \
					+ "\n" + CombatUi.run_text(e.get("run", {}), dname)
				_sig = ""
			"dungeon_failed":
				_show_banner(tr("UI_C2_DUNGEON_FAILED"), Color("d9544d"))
				CombatUi.shake(_banner, 12.0, 0.35)
				_run_log.text = tr("UI_C2_LOG_DUNGEON_FAIL")
				_sig = ""
			"kill":
				_run_log.text = Loc.tf("UI_COMBAT_LOG_KILL", {"name": Loc.t(DataRegistry.get_def("monsters", str(e.m)).get("name", "")),
					"xp": NumberFormat.fmt(float(e.xp)), "gold": NumberFormat.fmt(float(e.gold))})
			"heavy":
				CombatUi.flash(_run_hero_bar, Color(1.6, 0.6, 0.6), 0.3)
				if _portrait != null:
					CombatUi.shake(_portrait, 8.0, 0.25)
			"mech":
				_run_log.text = tr(str(CombatUi.MECH_LOG.get(str(e.m), "UI_C2_LOG_MECH_HEAVY")))
				if _portrait != null:
					CombatUi.shake(_portrait, 6.0, 0.2)


func _show_banner(text: String, col: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0
	if CombatUi.reduce() or not is_inside_tree():
		return
	var tw := _banner.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
