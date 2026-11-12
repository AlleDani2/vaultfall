extends GameScreen
## Giardino (docs/04 §11, docs/16): Orto e Frutteto come griglie di appezzamenti con timer che si animano.
## Semina rapida (un seme scelto per sezione, "Semina tutto"), raccolta rapida ("Raccogli tutto"), appezzamenti
## automatici (con 1 Stella in Coltivazione) e acquisto di nuovi appezzamenti. Solo presentazione: tutta la logica è in
## FarmingSystem. Aggiornamento ≤ 10 Hz; i timer sono SmoothBar (tween), spenti con "riduci animazioni".

const ICON_SIZE := Vector2(44, 44)
const FX_MAX := 6
const GOLD := Color(1.0, 0.85, 0.35)
const READY_TINT := Color(0.85, 1.15, 0.85)
const MISSING := Color(0.9, 0.4, 0.35)
const SLOW_EVERY := 5                     # il menù dei semi si ricostruisce ogni N refresh

var _fm: FarmingSystem
var _sk: SkillSystem
var _sections: Dictionary = {}            # kind -> {box, grid, title, opt, plant_all, buy, hint, sig}
var _cards: Dictionary = {}               # "kind:idx" -> {panel, icon, name, bar, time, btn, auto, state}
var _counter: int = 0
var _fx_count: int = 0
var _dirty: bool = true
var _last_card: Control

var _hdr: SkillHeader
var _head: PanelContainer
var _level_l: Label
var _xp_bar: ProgressBar
var _xp_l: Label
var _ready_l: Label
var _harvest_all: Button
var _perks: SkillPerkPanel                  # talenti di mansione (ogni 10 livelli), stesso pannello di SkillScreen


func open(_params: Dictionary) -> void:
	_fm = Game.system("farming") as FarmingSystem
	_sk = Game.system("skills") as SkillSystem
	if _fm == null or _sk == null:
		return
	_build()
	EventBus.action_completed.connect(_on_action_completed)
	EventBus.state_loaded.connect(_mark_dirty)
	EventBus.modifiers_changed.connect(_mark_dirty)
	EventBus.locale_changed.connect(_on_locale)
	_fm.changed.connect(_mark_dirty)
	refresh()


func close() -> void:
	for pair in [[EventBus.action_completed, _on_action_completed], [EventBus.state_loaded, _mark_dirty],
			[EventBus.modifiers_changed, _mark_dirty], [EventBus.locale_changed, _on_locale]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	if _fm != null and _fm.changed.is_connected(_mark_dirty):
		_fm.changed.disconnect(_mark_dirty)


# ------------------------------------------------------------------ costruzione

func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _build() -> void:
	for c in get_children():
		c.free()
	_sections.clear()
	_cards.clear()
	add_theme_constant_override("separation", 10)
	# stessa testata e stessa striscia delle altre mansioni (F7); la striscia dice quanti appezzamenti sono pronti
	_hdr = SkillHeader.new()
	add_child(_hdr)
	_hdr.setup("farming", tr("UI_FARM_TITLE"), tr("UI_FARM_SUBTITLE"), "skill:farming", false)
	_head = _hdr.head_panel
	_level_l = _hdr.level_l
	_xp_bar = _hdr.xp_bar
	_xp_l = _hdr.xp_l
	_ready_l = _hdr.strip_name
	_hdr.strip_icon.get_parent().visible = false
	_hdr.strip_bar.visible = false
	_hdr.strip_info.visible = false
	_hdr.strip_gain.visible = false
	_harvest_all = _hdr.strip_btn
	_harvest_all.text = "UI_FARM_HARVEST_ALL"
	_harvest_all.theme_type_variation = &"AccentButton"
	_harvest_all.pressed.connect(_on_harvest_all)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	sc.add_child(body)
	_perks = SkillPerkPanel.new()
	_perks.setup("farming", true)
	_perks.changed.connect(_mark_dirty)
	_hdr.add_action_button(_perks.perk_button())          # «Talenti •» nella testata, le righe dei talenti sotto
	body.add_child(_perks)
	for kid in _fm.kinds():
		_build_section(body, str(kid))
	_dirty = true


func _build_section(parent: Control, kind: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var title := _label(Loc.t(DataRegistry.get_def("farming_plots", kind).get("name", {})), &"SectionLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label(tr("UI_FARM_SEED_PICK"), &"MutedLabel"))
	var opt := OptionButton.new()
	opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	opt.custom_minimum_size = Vector2(240, 0)
	top.add_child(opt)
	var plant_all := Button.new()
	plant_all.text = "UI_FARM_PLANT_ALL"
	plant_all.pressed.connect(_on_plant_all.bind(kind))
	top.add_child(plant_all)
	var info := _label("", &"")             # resa del seme scelto: quanto dà, quanto ne hai, quanto cresce, XP (sempre in vista)
	info.add_theme_font_size_override("font_size", UiType.NOTE)
	box.add_child(info)
	var seeds := RichTextLabel.new()        # «Servono: 1× Seme di Patata (ne hai 6)»: ambra solo se non bastano
	seeds.bbcode_enabled = true
	seeds.fit_content = true
	seeds.scroll_active = false
	seeds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seeds.add_theme_font_size_override("normal_font_size", UiType.NOTE)
	seeds.meta_clicked.connect(ReqLink.meta_go)
	box.add_child(seeds)
	var grid := HFlowContainer.new()        # a capo se la finestra è stretta (QA overflow 107)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var hint := _label("", &"MutedLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var buy := Button.new()
	buy.alignment = HORIZONTAL_ALIGNMENT_LEFT
	buy.pressed.connect(_on_buy.bind(kind))
	box.add_child(buy)
	_sections[kind] = {"box": box, "grid": grid, "title": title, "opt": opt, "plant_all": plant_all, "buy": buy, "hint": hint, "count": -1, "info": info, "seeds": seeds}
	_rebuild_cards(kind)


## Ricrea le carte degli appezzamenti del tipo (all'inizio e quando se ne compra uno).
func _rebuild_cards(kind: String) -> void:
	var s: Dictionary = _sections[kind]
	var grid: HFlowContainer = s.grid
	for c in grid.get_children():
		c.free()
	for key in _cards.keys():
		if str(key).begins_with(kind + ":"):
			_cards.erase(key)
	for i in _fm.plot_count(kind):
		_build_card(kind, i, grid)
	s["count"] = _fm.plot_count(kind)


func _build_card(kind: String, idx: int, grid: HFlowContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(170, 0)
	grid.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.pivot_offset = ICON_SIZE / 2.0
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var name_l := _label("", &"")
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var bar := SmoothBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	v.add_child(bar)
	var time_l := _label("", &"MonoLabel")
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(time_l)
	var btn := Button.new()
	btn.pressed.connect(_on_card_pressed.bind(kind, idx))
	v.add_child(btn)
	var auto := CheckBox.new()
	auto.text = "UI_FARM_AUTO"
	auto.toggled.connect(_on_auto_toggled.bind(kind, idx))
	v.add_child(auto)
	_cards["%s:%d" % [kind, idx]] = {"panel": panel, "icon": icon, "name": name_l, "bar": bar, "time": time_l, "btn": btn,
		"auto": auto, "state": "", "crop": "?"}


# ------------------------------------------------------------------ aggiornamento

func _mark_dirty() -> void:
	_dirty = true


func _on_locale(_l: String) -> void:
	if _fm != null:
		_build()
		refresh()


func refresh() -> void:
	if _fm == null:
		return
	_counter += 1
	var slow := _dirty or _counter % SLOW_EVERY == 1
	_refresh_header()
	if _perks != null:
		_perks.refresh()
	for kind in _sections:
		var s: Dictionary = _sections[kind]
		if int(s.count) != _fm.plot_count(kind):
			_rebuild_cards(kind)
			slow = true
		for i in _fm.plot_count(kind):
			_refresh_card(kind, i)
		if slow:
			_refresh_section(kind)
	_dirty = false


func _refresh_header() -> void:
	var lv := _sk.level("farming")
	_level_l.text = Loc.tf("UI_FARM_LEVEL", {"n": lv})
	var pr := _sk.xp_progress("farming")
	var need := float(pr[1])
	_xp_bar.value = 1.0 if need <= 0.0 else clampf(float(pr[0]) / need, 0.0, 1.0)
	_xp_l.text = "" if need <= 0.0 else Loc.tf("UI_SKILLS_XP", {"cur": NumberFormat.fmt(float(pr[0])), "need": NumberFormat.fmt(need)})
	var n := _fm.ready_count()
	_ready_l.text = Loc.tf("UI_FARM_READY_N", {"n": n}) if n > 0 else tr("UI_FARM_IN_PROGRESS_NONE")
	_hdr.strip_dot.text = "●" if n > 0 else "○"
	_harvest_all.disabled = n == 0


func _refresh_card(kind: String, idx: int) -> void:
	var c: Dictionary = _cards.get("%s:%d" % [kind, idx], {})
	if c.is_empty():
		return
	var pl := _fm.plot(kind, idx)
	var crop := str(pl.crop)
	var st := "empty"
	if crop != "":
		st = "ready" if _fm.is_ready(kind, idx) else "growing"
	var btn: Button = c.btn
	var bar: SmoothBar = c.bar
	var auto: CheckBox = c.auto
	if crop != str(c.crop):
		c["crop"] = crop
		if crop == "":
			(c.icon as TextureRect).texture = IconLib.icon("skills", "farming")      # germoglio spento: il riquadro non resta nudo
			(c.icon as TextureRect).modulate = Color(1, 1, 1, 0.3)
			(c.name as Label).text = tr("UI_FARM_EMPTY")
		else:
			(c.icon as TextureRect).modulate = Color.WHITE
			var a: Dictionary = DataRegistry.action(crop)
			(c.icon as TextureRect).texture = IconLib.icon("items", str(a.outputs[0].item))
			(c.name as Label).text = Loc.t(a.name)
	match st:
		"empty":
			bar.set_target(0.0, 0.0)
			(c.time as Label).text = ""
			btn.text = "UI_FARM_PLANT"
			var aid := _selected_action(kind)
			var why := _fm.can_plant(kind, idx, aid) if aid != "" else "UI_FARM_REASON_UNKNOWN"
			btn.disabled = why != ""
			btn.tooltip_text = _why_text(aid, why)            # perché non si può seminare (semi finiti, livello...) con le quantità
			btn.visible = true
		"growing":
			var total := maxf(1.0, float(pl.total_s))
			bar.set_target(_fm.growth_fraction(kind, idx), 1.0 / total)
			(c.time as Label).text = Loc.tf("UI_FARM_GROWING", {"time": NumberFormat.fmt_time(float(pl.remaining_s))})
			btn.visible = false
		"ready":
			bar.set_target(1.0, 0.0)
			(c.time as Label).text = tr("UI_FARM_READY")
			btn.text = "UI_FARM_HARVEST"
			btn.disabled = false
			btn.visible = true
	if st != str(c.state):
		c["state"] = st
		(c.panel as Control).modulate = READY_TINT if st == "ready" else Color.WHITE
		if st == "ready":
			_pulse(c.icon)
	auto.visible = _fm.can_automate()
	auto.set_pressed_no_signal(bool(pl.auto))


func _refresh_section(kind: String) -> void:
	var s: Dictionary = _sections[kind]
	# menù dei semi
	var opt: OptionButton = s.opt
	var keep := _selected_action(kind)
	var bank: Object = Game.system("bank")
	if not opt.get_popup().visible:                # un menù aperto non si ricostruisce (si chiuderebbe da solo)
		opt.clear()
		var lv := _sk.level("farming")
		var sel := -1
		var first_ok := -1
		for a in _fm.actions_for(kind):
			var aid := str(a.id)
			var have := int(bank.count(str(a.seed))) if bank != null else 0
			var txt := Loc.tf("UI_FARM_SEED_OPT", {"name": Loc.t(a.name), "n": have, "lv": int(a.level_req)})
			opt.add_item(txt)
			var i := opt.item_count - 1
			opt.set_item_metadata(i, aid)
			var usable := lv >= int(a.level_req)
			opt.set_item_disabled(i, not usable)
			if usable and first_ok < 0 and have > 0:
				first_ok = i
			if aid == keep:
				sel = i
		if sel < 0:
			sel = first_ok
		if sel < 0:                                  # nessun seme in Deposito: la prima coltura che il livello permette, non la più alta
			for j in opt.item_count:
				if not opt.is_item_disabled(j):
					sel = j
					break
		if sel < 0:
			sel = 0
		if opt.item_count > 0:
			opt.select(sel)
	(s.plant_all as Button).disabled = keep == "" and opt.item_count == 0
	# acquisto appezzamenti
	var cost := _fm.next_plot_cost(kind)
	var buy: Button = s.buy
	buy.visible = true
	if cost > 0:
		buy.text = Loc.tf("UI_FARM_BUY_PLOT", {"cost": NumberFormat.fmt(float(cost))})
		buy.disabled = bank != null and int(bank.gold()) < cost
	else:
		buy.text = tr("UI_FARM_MAXED")
		buy.disabled = true
	var hint: Label = s.hint
	hint.text = tr("UI_FARM_AUTO_ON") if _fm.can_automate() else tr("UI_FARM_AUTO_LOCKED")
	var cur := _selected_action(kind)
	if cur != "" and _fm.can_plant(kind, 0, cur) == "UI_FARM_REASON_SEEDS":
		hint.text = _why_text(cur, "UI_FARM_REASON_SEEDS") + "\n" + hint.text
	_refresh_seed_info(s, cur)


## Resa del seme scelto, in vista: «Per raccolto: ~7 Patata (ne hai 12) · cresce in 10 min · XP: 133 semina + 533 raccolto» e,
## sotto, «Servono: 1× Seme di Patata (ne hai 6)» (ambra se non bastano). Numeri dai dati e da FarmingSystem.
func _refresh_seed_info(s: Dictionary, aid: String) -> void:
	var info: Label = s.info
	var seeds: RichTextLabel = s.seeds
	var a: Dictionary = DataRegistry.action(aid) if aid != "" else {}
	if a.is_empty() or (a.get("outputs", []) as Array).is_empty():
		info.text = ""
		seeds.text = ""
		info.visible = false
		seeds.visible = false
		return
	var item := str(a.outputs[0].item)
	info.text = Loc.tf("UI_MSK_FARM_YIELD", {"n": NumberFormat.fmt(roundf(_fm.expected_yield(aid))), "item": ReqText.item_name(item),
		"have": NumberFormat.fmt(float(ReqText.owned(item))), "time": NumberFormat.fmt_time(_fm.grow_time(aid)),
		"plant": NumberFormat.fmt(float(a.get("xp_plant", 0))), "harv": NumberFormat.fmt(float(a.get("xp_harvest", 0)))})
	info.visible = true
	var bb := ReqText.inputs_text([{"item": str(a.seed), "qty": int(a.get("seeds_per_plant", 1))}], true, true)
	if bb != seeds.text:
		seeds.text = bb
	seeds.visible = true


## Motivo del rifiuto con le quantità: semi («Ti mancano 3 Seme di Patata: ne servono 4, ne hai 1») e livello.
func _why_text(aid: String, why: String) -> String:
	var a: Dictionary = DataRegistry.action(aid) if aid != "" else {}
	if a.is_empty():
		return why
	if why == "UI_FARM_REASON_SEEDS":
		return ReqText.missing_sentence(str(a.seed), int(a.get("seeds_per_plant", 1)), ReqText.owned(str(a.seed)))
	if why == "UI_FARM_REASON_LEVEL":
		return ReqText.level_sentence(Loc.t(DataRegistry.get_def("skills", "farming").get("name", {})), int(a.level_req), _fm.level())
	return why


func _selected_action(kind: String) -> String:
	if not _sections.has(kind):
		return ""
	var opt: OptionButton = _sections[kind].opt
	var i := opt.selected
	return str(opt.get_item_metadata(i)) if i >= 0 and i < opt.item_count else ""


# ------------------------------------------------------------------ azioni

func _on_card_pressed(kind: String, idx: int) -> void:
	_last_card = (_cards.get("%s:%d" % [kind, idx], {}) as Dictionary).get("panel")
	if _fm.is_ready(kind, idx):
		_warn_if_blocked(1 if _fm.harvest(kind, idx) else 0)
	else:
		var aid := _selected_action(kind)
		if aid != "" and not _fm.plant(kind, idx, aid):
			EventBus.notice.emit("warning", tr(_why_text(aid, _fm.can_plant(kind, idx, aid))), {})
	_dirty = true
	refresh()


func _on_plant_all(kind: String) -> void:
	var aid := _selected_action(kind)
	if aid == "":
		return
	if _fm.plant_all(kind, aid) == 0:
		var why := "UI_FARM_REASON_BUSY"
		for i in _fm.plot_count(kind):
			var r := _fm.can_plant(kind, i, aid)
			if r != "" and r != "UI_FARM_REASON_BUSY":
				why = r
				break
		EventBus.notice.emit("warning", tr(_why_text(aid, why)), {})
	_dirty = true
	refresh()


func _on_harvest_all() -> void:
	_last_card = null
	_warn_if_blocked(_fm.harvest_all())
	_dirty = true
	refresh()


## Raccolto impossibile perché il Deposito è pieno: il sistema avvisa solo la prima volta; chi preme il pulsante
## deve sentirsi rispondere ogni volta (QA 95: «Raccogli» che non fa niente, senza dire perché).
func _warn_if_blocked(done: int) -> void:
	if done > 0 or _fm.ready_count() <= 0:
		return
	var bank := Game.system("bank") as BankSystem
	if bank != null and bank.is_full():
		EventBus.notice.emit("warning", tr("UI_SKILLS_STOP_BANK_FULL"), {"reason": "bank_full"})


func _on_buy(kind: String) -> void:
	_fm.buy_plot(kind)
	_dirty = true
	refresh()


func _on_auto_toggled(on: bool, kind: String, idx: int) -> void:
	_fm.set_auto(kind, idx, on)


func _on_action_completed(action_id: String, outputs: Array) -> void:
	if not is_inside_tree() or str(DataRegistry.action(action_id).get("skill", "")) != "farming":
		return
	if Settings.get_value("reduce_motion"):
		return
	for o in outputs:
		if int(o.get("qty", 0)) > 0:
			var nm := Loc.t(DataRegistry.item(str(o.item)).get("name", str(o.item)))
			_floater(Loc.tf("UI_FARM_HARVESTED", {"n": int(o.qty), "item": nm}))
			break


## "+7 Patata" che sale dalla carta raccolta (o dall'intestazione per la raccolta rapida/automatica).
func _floater(text: String) -> void:
	if _fx_count >= FX_MAX:
		return
	_fx_count += 1
	var anchor: Control = _last_card if (_last_card != null and is_instance_valid(_last_card)) else _head
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.top_level = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	var base := anchor.global_position + Vector2(randf_range(6.0, maxf(8.0, anchor.size.x * 0.6)), 6.0)
	l.global_position = base
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", base.y - 36.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(_fx_done.bind(l))


func _fx_done(l: Label) -> void:
	_fx_count = maxi(0, _fx_count - 1)
	if is_instance_valid(l):
		l.queue_free()


func _pulse(node: Control) -> void:
	if Settings.get_value("reduce_motion") or node == null or not is_inside_tree():
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.25, 1.25), 0.08)
	tw.tween_property(node, "scale", Vector2.ONE, 0.14)
