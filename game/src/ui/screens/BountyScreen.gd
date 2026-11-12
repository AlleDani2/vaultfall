extends GameScreen
## Taglie (docs/05 §11): bacheca con 3 offerte, un incarico alla volta, avanzamento, Marchi, cambi gratuiti al giorno,
## Ricercati. Solo presentazione: legge e comanda BountySystem (e CombatSystem per "vai a combattere").
## Animazioni a tween: barra dell'incarico che avanza, rimbalzo alla firma, lampo e striscione al completamento.
## Restyling UX (110): suggerimento «cosa fare ora», numeri chiave con unità, carte con bordo per fascia, motivo dei pulsanti spenti,
## sostituzione dell'incarico in corso dichiarata prima di accettare, rinuncia a due passi.

const TIER_COLORS := {"easy": Color("7fcf8a"), "medium": Color("e0b640"), "hard": Color("e08a40"), "legendary": Color("d9544d")}
const ABANDON_ARM_S := 4.0
const OFFER_W := 380.0              # larghezza minima di una carta-offerta: a 1600 px ne stanno tre in fila, a 1280 due

var _bounty: BountySystem
var _combat: CombatSystem
var _sig: String = ""
var _last_completed: int = -1
var _hint: ScreenKit.KitHint
var _st_level: ScreenKit.KitStat
var _st_done: ScreenKit.KitStat
var _st_marks: ScreenKit.KitStat
var _active_box: VBoxContainer
var _active_head: Label
var _open_state: Dictionary = {}
var _intro: Dictionary = {}
var _active_title: Label
var _active_info: Label
var _active_bar: ProgressBar
var _active_portrait: TextureRect
var _active_pill: Control
var _active_stat: ScreenKit.KitStat
var _go_btn: Button
var _go_reason: Label
var _abandon_btn: Button
var _abandon_armed: bool = false
var _offers_box: HFlowContainer
var _banner: Label
var _wanted_note: Label
var _shop_box: VBoxContainer
var _shop_sig: String = ""


var _perks: SkillPerkPanel          # talenti di mansione delle Taglie (ogni 10 livelli)


func open(_params: Dictionary) -> void:
	_bounty = Game.system("bounty") as BountySystem
	_combat = Game.system("combat") as CombatSystem
	_build()
	_sig = ""
	refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	_intro = EstateDungeonKit.title_row(outer, "UI_MENU_BOUNTY", "UI_F9_BO_PURPOSE", "bounty")
	ScreenKit.cap_text(_intro.purpose as Label)
	_hint = ScreenKit.KitHint.new()
	_hint.setup(ScreenKit.accent("bounty"))
	outer.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)
	_perks = SkillPerkPanel.new()
	_perks.setup("bounty")
	root.add_child(_perks)
	var stats := ScreenKit.stat_row(root)
	_st_level = ScreenKit.stat(stats, "UI_RS_BO_ST_LEVEL", "UI_RS_BO_TIP_LEVEL")
	_st_done = ScreenKit.stat(stats, "UI_RS_BO_ST_DONE", "UI_RS_BO_TIP_DONE")
	_st_marks = ScreenKit.stat(stats, "UI_RS_BO_ST_MARKS", "UI_RS_BO_TIP_MARKS")
	_banner = CombatUi.text_label("SectionLabel")
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_active_head = CombatUi.label("UI_C2_BOUNTY_ACTIVE", "SectionLabel")
	root.add_child(_active_head)
	_active_box = ScreenKit.card(root, ScreenKit.accent("bounty"), 4, true)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 12)
	_active_box.add_child(arow)
	_active_portrait = TextureRect.new()
	_active_portrait.custom_minimum_size = Vector2(128, 128)            # i ritratti sono 128 px: mostrati 1:1
	_active_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_active_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arow.add_child(_active_portrait)
	var acol := VBoxContainer.new()
	acol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acol.add_theme_constant_override("separation", 4)
	arow.add_child(acol)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	acol.add_child(trow)
	_active_title = CombatUi.text_label("SectionLabel")
	_active_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_active_title)
	_active_pill = ScreenKit.pill("", Color.WHITE)
	trow.add_child(_active_pill)
	_active_stat = ScreenKit.stat(acol, "UI_RS_BO_ST_PROGRESS", "UI_RS_BO_TIP_PROGRESS", Color(ScreenKit.GOLD))
	_active_bar = CombatUi.bar(Color("c8a24a"), 14.0)
	acol.add_child(_active_bar)
	_active_info = CombatUi.text_label("MutedLabel", true)
	acol.add_child(_active_info)
	var abtn := HBoxContainer.new()
	abtn.add_theme_constant_override("separation", 8)
	acol.add_child(abtn)
	_go_btn = Button.new()
	_go_btn.theme_type_variation = &"AccentButton"
	_go_btn.text = "UI_C2_BOUNTY_GO"
	_go_btn.pressed.connect(_on_go)
	abtn.add_child(_go_btn)
	_abandon_btn = Button.new()
	_abandon_btn.flat = true
	_abandon_btn.text = "UI_C2_BOUNTY_ABANDON"
	_abandon_btn.tooltip_text = "UI_RS_BO_TIP_ABANDON"
	_abandon_btn.pressed.connect(_on_abandon)
	abtn.add_child(_abandon_btn)
	_go_reason = ScreenKit.reason_label()
	acol.add_child(_go_reason)
	ScreenKit.section(root, "UI_C2_BOUNTY_BOARD")
	_offers_box = HFlowContainer.new()               # tre carte affiancate (a capo se manca spazio): non più tre fasce da 1300 px
	_offers_box.add_theme_constant_override("h_separation", 10)
	_offers_box.add_theme_constant_override("v_separation", 10)
	root.add_child(_offers_box)
	# regola dei Ricercati e Banco dei Marchi: a richiesta (chiusi)
	var wanted_body := EstateDungeonKit.disclosure(root, "UI_F9_BO_WANTED", _open_state, "wanted")
	_wanted_note = CombatUi.text_label("MutedLabel", true)
	wanted_body.add_child(_wanted_note)
	var shop_body := EstateDungeonKit.disclosure(root, "UI_RS_BO_SHOP_T", _open_state, "shop")
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 4)
	_shop_box.set_meta("shop", "bounty_shop")
	shop_body.add_child(_shop_box)


func _on_abandon() -> void:
	if not _abandon_armed:
		_abandon_armed = true
		_abandon_btn.text = tr("UI_RS_BO_ABANDON_SURE")
		_abandon_btn.flat = false
		if is_inside_tree():
			get_tree().create_timer(ABANDON_ARM_S).timeout.connect(func() -> void:
				if _abandon_armed and is_instance_valid(_abandon_btn):
					_abandon_armed = false
					_abandon_btn.text = tr("UI_C2_BOUNTY_ABANDON")
					_abandon_btn.flat = true)
		return
	_abandon_armed = false
	_abandon_btn.text = tr("UI_C2_BOUNTY_ABANDON")
	_abandon_btn.flat = true
	_bounty.abandon()
	_sig = ""
	refresh()


func refresh() -> void:
	if _bounty == null:
		return
	if _perks != null:
		_perks.refresh()
	var board: Dictionary = DataRegistry.table("bounty_board")[0]
	var w: Dictionary = board.wanted_variant
	_wanted_note.text = Loc.tf("UI_C2_BOUNTY_WANTED_NOTE", {"p": NumberFormat.fmt_pct(_bounty.wanted_chance() * 100.0),
		"hp": NumberFormat.fmt(float(w.hp_mult)), "dmg": NumberFormat.fmt(float(w.dmg_mult)), "marks": int(w.marks)})
	_st_level.set_value(str(_bounty.bounty_level()), "")
	_st_done.set_value(str(int(_bounty.state.completed)), "")
	_st_marks.set_value(NumberFormat.fmt(float(_bounty.state.marks_total)), "")
	var done := int(_bounty.state.completed)
	if _last_completed >= 0 and done > _last_completed:
		_banner.text = tr("UI_C2_BOUNTY_COMPLETED")
		_banner.modulate.a = 1.0
		CombatUi.pop(_banner, 1.25, 0.4)
		if not CombatUi.reduce() and is_inside_tree():
			var tw := _banner.create_tween()
			tw.tween_interval(1.6)
			tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
	_last_completed = done
	_refresh_active()
	var afford := PackedStringArray()
	for i in _bounty.offers().size():
		afford.append(str(_gold() >= _bounty.reroll_cost(i)))
	var sig := "%s|%s|%d|%d|%s" % [JSON.stringify(_bounty.state.offers), str(_bounty.has_active()), _bounty.free_rerolls_left(), _bounty.bounty_level(), ",".join(afford)]
	if sig != _sig:
		_sig = sig
		_fill_offers()
	var bank := Game.system("bank") as BankSystem
	var shop_sig := str(bank.count("bounty_mark")) if bank != null else ""
	if shop_sig != _shop_sig:
		_shop_sig = shop_sig
		EndgamePanel.shop_fill(_combat, _shop_box)
	_refresh_hint()


func _gold() -> int:
	var b := Game.system("bank") as BankSystem
	return 0 if b == null else b.gold()


## L'istruzione «Scegli un incarico… Accetta» compare UNA volta sola, e solo quando c'è da scegliere. Con un incarico in corso parla
## la sua carta (progresso, «Vai a caccia», motivo del blocco); senza incarichi parla lo stato vuoto: la barra sta zitta.
func _refresh_hint() -> void:
	var pick := not _bounty.has_active() and not _bounty.offers().is_empty()
	_hint.visible = pick
	if pick:
		_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_BO_H_PICK"))


func _refresh_active() -> void:
	var has := _bounty.has_active()
	ScreenKit.panel_of(_active_box).visible = has
	_active_head.visible = has
	if not has:
		return
	var act: Dictionary = _bounty.active()
	var o: Dictionary = act.offer
	var mon: Dictionary = DataRegistry.get_def("monsters", str(o.monster))
	_active_portrait.texture = IconLib.portrait("monsters", str(o.monster))
	_active_title.text = "%s  (%s %d)" % [Loc.t(mon.get("name", "")), tr("UI_COMBAT_LV"), int(mon.get("level", 1))]
	var tcol: Color = TIER_COLORS.get(str(o.tier), Color.WHITE)
	ScreenKit.set_pill(_active_pill, Loc.t(_bounty.tier_def(str(o.tier)).get("name", "")), tcol)
	ScreenKit.set_edge(_active_box, tcol)
	_active_stat.set_value("%d / %d" % [int(act.progress), int(o.kills)], tr("UI_RS_BO_UNIT_KILLS"))
	_active_info.text = Loc.tf("UI_RS_BO_ACTIVE_MARKS", {"marks": int(o.marks), "total": int(o.marks) * int(o.kills)})
	CombatUi.set_bar(_active_bar, float(act.progress) / maxf(1.0, float(o.kills)), 0.3)
	var why := ""
	if not _target_reachable(mon):
		why = tr("UI_RS_BO_WHY_ZONE")
	ScreenKit.gate(_go_btn, why, _go_reason)


func _target_reachable(mon: Dictionary) -> bool:
	if str(mon.type) == "dungeon_boss":
		return true
	return _combat.zone_unlocked(str(mon.get("zone", "")))


func _on_go() -> void:
	var act: Dictionary = _bounty.active()
	if act.is_empty():
		return
	var mon: Dictionary = DataRegistry.get_def("monsters", str(act.offer.monster))
	if str(mon.type) == "dungeon_boss":
		var dungeon_id := ""
		for d in DataRegistry.table("dungeons"):
			if str(d.boss) == str(mon.id):
				dungeon_id = str(d.id)
		EventBus.screen_requested.emit("dungeon", {"dungeon": dungeon_id})
		return
	if _combat.start(str(mon.zone), str(mon.id)):
		EventBus.screen_requested.emit("combat", {})


func _fill_offers() -> void:
	CombatUi.clear_children(_offers_box)
	var offers := _bounty.offers()
	var has_active := _bounty.has_active()
	for i in offers.size():
		var o: Dictionary = offers[i]
		var mon: Dictionary = DataRegistry.get_def("monsters", str(o.monster))
		var tcol: Color = TIER_COLORS.get(str(o.tier), Color.WHITE)
		var card := ScreenKit.card(_offers_box, tcol, 4)
		ScreenKit.panel_of(card).custom_minimum_size.x = OFFER_W
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 12)
		card.add_child(hrow)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(128, 128)            # i ritratti sono 128 px: mostrati 1:1
		pic.texture = IconLib.portrait("monsters", str(o.monster))
		pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow.add_child(pic)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_theme_constant_override("separation", 4)
		hrow.add_child(box)
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		box.add_child(trow)
		var nm := CombatUi.text_label("SectionLabel", true)
		nm.text = Loc.t(mon.get("name", ""))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(nm)
		trow.add_child(ScreenKit.pill(Loc.t(_bounty.tier_def(str(o.tier)).get("name", "")), tcol, tr("UI_RS_BO_TIP_TIER")))
		box.add_child(ScreenKit.muted(Loc.tf("UI_RS_BO_OFFER_LV", {"lv": int(mon.get("level", 1))})))
		var nums := ScreenKit.stat_row(box)
		var s1 := ScreenKit.stat(nums, "UI_RS_BO_ST_HUNT", "UI_RS_BO_TIP_HUNT", Color(ScreenKit.GOLD))
		s1.set_value(str(int(o.kills)), tr("UI_RS_BO_UNIT_KILLS"))
		var s2 := ScreenKit.stat(nums, "UI_RS_BO_ST_PRIZE", Loc.tf("UI_RS_BO_TIP_PRIZE", {"marks": int(o.marks)}), Color(ScreenKit.GOLD))
		s2.set_value(NumberFormat.fmt(float(int(o.marks) * int(o.kills))), tr("UI_RS_BO_UNIT_MARKS"))
		var bcol := VBoxContainer.new()                   # azioni SOTTO la carta, a tutta larghezza
		bcol.add_theme_constant_override("separation", 4)
		card.add_child(bcol)
		var accept := Button.new()
		accept.theme_type_variation = &"AccentButton"
		accept.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		accept.text = tr("UI_RS_BO_ACCEPT_REPLACE") if has_active else tr("UI_C2_BOUNTY_ACCEPT")
		accept.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		accept.tooltip_text = tr("UI_RS_BO_TIP_REPLACE") if has_active else tr("UI_RS_BO_TIP_ACCEPT")
		accept.pressed.connect(func() -> void:
			if _bounty.accept(i):
				CombatUi.pop(accept)
			_sig = ""
			refresh())
		bcol.add_child(accept)
		var reroll := Button.new()
		reroll.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var cost := _bounty.reroll_cost(i)
		reroll.text = Loc.tf("UI_C2_BOUNTY_REROLL_FREE", {"n": _bounty.free_rerolls_left()}) if cost == 0 \
			else Loc.tf("UI_C2_BOUNTY_REROLL_COST", {"gold": NumberFormat.fmt(cost)})
		var rwhy := ""
		if cost > _gold():
			rwhy = Loc.tf("UI_RS_BO_WHY_REROLL", {"gold": NumberFormat.fmt(cost)})
		ScreenKit.gate(reroll, rwhy)
		if rwhy == "":
			reroll.tooltip_text = tr("UI_RS_BO_TIP_REROLL")
		reroll.pressed.connect(func() -> void:
			if not _bounty.reroll(i):
				EventBus.notice.emit("warning", tr("UI_C2_BOUNTY_REROLL_DENIED"), {})
			_sig = ""
			refresh())
		bcol.add_child(reroll)
		if rwhy != "":
			var rl := ScreenKit.reason_label()
			rl.visible = true
			rl.text = rwhy
			bcol.add_child(rl)
	if offers.is_empty():
		var acts: Array = []
		if ScreenKit.available("combat"):
			acts.append([tr("UI_RS_GO_COMBAT"), ScreenKit.target("combat")])
		ScreenKit.empty(_offers_box, tr("UI_RS_BO_NONE"), tr("UI_RS_BO_NONE_WHY"), acts)
