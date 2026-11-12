extends GameScreen
## Schermata Prestigio (docs/13, docs/16): Consigliere unico, Grande Obiettivo, schede per strato (compaiono solo quando
## servono: Stelle · Costellazioni · Tenuta), anteprima "cosa perdi / cosa conservi / cosa guadagni" con numeri veri,
## conferma a DUE passaggi (primo clic arma, secondo conferma entro CONFIRM_MS) ed effetto di soddisfazione a tween.
## Solo presentazione: legge e chiama PrestigeSystem; l'anteprima è quella calcolata dal sistema (identica al risultato).

const CONFIRM_MS := 6000
const GOLD := Color(1.0, 0.85, 0.35)
const LOSE := Color(0.95, 0.5, 0.45)
const KEEP := Color(0.6, 0.75, 0.95)
const GAIN := Color(0.55, 0.9, 0.6)
const FX_STARS := 14
## F10: Consigliere e Grande Obiettivo non sono più pannelli in pila sopra le schede, ma le prime due schede (una alla volta).
const FIXED_TABS := 2
const TAB_ADVISOR := 0
const TAB_GOAL := 1

var _ps: PrestigeSystem
var _dust_l: ScreenKit.KitStat
var _stars_l: ScreenKit.KitStat
var _partners_l: ScreenKit.KitStat
var _adv_text: Label
var _adv_btn: Button
var _goal_l: Label
var _goal_bar: ProgressBar
var _tabs: TabContainer
var _tab_ids: Array = []                 # solo gli strati (Stelle, Costellazioni…): le due schede fisse stanno prima, vedi FIXED_TABS
var _adv_page: Control
# intestazione-evento (revisione grafica 1.0, punto 8) e anteprima/teaser del Consigliere
var _ev_title: Label
var _ev_gain: Label
var _ev_detail: Label
var _ev_bar: SmoothBar
var _ev_btn: Button
var _adv_prev: VBoxContainer
var _adv_prev_hash: int = 0
var _adv_teaser: VBoxContainer
var _goal_page: Control
var _intro: Label
var _sig: String = ""
var _fx: Control

# scheda Stelle
var _star_rows: Dictionary = {}          # skill_id -> {name, lvl, stars, btn}
var _star_sel: String = ""
var _star_box: VBoxContainer
var _star_hash: int = 0
var _star_confirm: Button
var _star_perks: Button
# scheda Costellazioni
var _map: ConstellationMap
var _node_sel: String = ""
var _node_box: VBoxContainer
var _node_hash: int = 0
var _buy1: Button
var _buymax: Button
var _respec_l: Label
var _respec_btn: Button
# scheda Tenuta
var _ref_box: VBoxContainer
var _ref_hash: int = 0
var _ref_confirm: Button
# scheda Ere
var _era_sel: int = 0
var _era_spin: SpinBox
var _era_box: VBoxContainer
var _era_cur_l: Label
var _era_btn: Button
var _era_hash: int = 0
# scheda Prove
var _trial_sel: String = ""
var _trial_banner: Label
var _trial_rows: Dictionary = {}          # trial_id -> {grades, btn}
var _trial_box: VBoxContainer
var _trial_start: Button
var _trial_abandon: Button
var _trial_hash: int = 0
# conferma a due passaggi
var _armed: String = ""
var _armed_at: int = 0


## `params.tab`: id dello strato da mostrare subito ("star", "constellations", "refound", "era", "trials"); se lo strato non è
## ancora visibile resta la prima scheda. Lo usano la barra alta (Polvere Stellare → Costellazioni) e chi apre la schermata da fuori.
func open(params: Dictionary) -> void:
	_ps = Game.system("prestige") as PrestigeSystem
	var title := Label.new()
	ScreenKit.title_style(title)
	title.text = tr("UI_MENU_PRESTIGE")
	add_child(title)
	if _ps == null:
		var nope := Label.new()
		nope.text = tr("UI_PRESTIGE_NO_SYSTEM")
		add_child(nope)
		return
	var intro_row := HBoxContainer.new()
	intro_row.add_theme_constant_override("separation", 10)
	remove_child(title)
	intro_row.add_child(title)
	add_child(intro_row)
	move_child(intro_row, 0)
	_intro = Label.new()
	_intro.text = tr("UI_PRESTIGE_INTRO")
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.theme_type_variation = &"MutedLabel"
	add_child(_intro)
	ScreenKit.cap_text(_intro)
	HeroKit.help_button(intro_row, _intro, "prestige", tr("UI_SCR_HERO_HELP_TIP"))      # D17: alla prima visita aperto, poi nel «?»
	_build_event_header()
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_i: int) -> void: _disarm())
	add_child(_tabs)
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	_build_fixed_tabs()
	# effetti (sopra a tutto, non influenzano il layout)
	_fx = Control.new()
	_fx.top_level = true
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.z_index = 50
	add_child(_fx)
	EventBus.state_loaded.connect(_rebuild_tabs)
	EventBus.locale_changed.connect(_on_locale)
	_rebuild_tabs()
	var want := str(params.get("tab", ""))
	if want != "":
		_goto_tab(want)
	refresh()


func close() -> void:
	for pair in [[EventBus.state_loaded, _rebuild_tabs], [EventBus.locale_changed, _on_locale]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _on_locale(_l: String) -> void:
	_sig = ""
	_star_hash = 0
	_node_hash = 0
	_ref_hash = 0
	_era_hash = 0
	_trial_hash = 0


func _mono(parent: Control) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MonoLabel"
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ intestazione-evento

## La Polvere Stellare in GRANDE, a destra «cosa succede se agisci ora» (guadagno in numeri grandi) e l'unico pulsante pieno della
## schermata. Senza un'azione disponibile mostra il passo più vicino con la sua barra. Solo presentazione: legge `advise()`.
func _build_event_header() -> void:
	var accent := ScreenKit.accent("prestige")
	var panel := PanelContainer.new()
	panel.name = "EventHeader"
	panel.add_theme_stylebox_override("panel", ScreenKit.card_style(accent, 6, true))
	add_child(panel)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 36)
	flow.add_theme_constant_override("v_separation", 10)
	panel.add_child(flow)
	# a sinistra: Polvere Stellare grande + Stelle e Soci
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	flow.add_child(left)
	_dust_l = ScreenKit.stat(left, "UI_RS_PR_ST_DUST", "UI_RS_PR_TIP_DUST", accent.lightened(0.35))
	_dust_l.value_l.add_theme_font_size_override("font_size", UiType.NUMBER_HERO)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 22)
	left.add_child(small)
	_stars_l = ScreenKit.stat(small, "UI_RS_PR_ST_STARS", "UI_RS_PR_TIP_STARS")
	_partners_l = ScreenKit.stat(small, "UI_RS_PR_ST_PARTNERS", "UI_RS_PR_TIP_PARTNERS")
	# al centro: se agisci ora
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size.x = 280
	flow.add_child(mid)
	_ev_title = Label.new()
	_ev_title.theme_type_variation = &"SectionLabel"
	mid.add_child(_ev_title)
	_ev_gain = Label.new()
	_ev_gain.theme_type_variation = &"NumberLabel"
	_ev_gain.add_theme_font_size_override("font_size", UiType.NUMBER_BIG)
	_ev_gain.add_theme_color_override("font_color", accent.lightened(0.35))
	_ev_gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_ev_gain)
	_ev_detail = ScreenKit.muted("")
	mid.add_child(_ev_detail)
	_ev_bar = ScreenKit.bar(mid, accent, 10)
	_ev_bar.visible = false
	# a destra: l'azione
	_ev_btn = Button.new()
	_ev_btn.name = "EventGo"
	_ev_btn.theme_type_variation = &"AccentButton"
	_ev_btn.custom_minimum_size = Vector2(200, 48)
	_ev_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ev_btn.pressed.connect(_on_advisor_go)
	flow.add_child(_ev_btn)


func _refresh_event(a: Dictionary) -> void:
	var kind := str(a.kind)
	_ev_btn.visible = kind != "none"
	_ev_bar.visible = false
	_ev_title.text = tr("UI_GSA_PR_NOW")
	_ev_gain.text = ""
	_ev_detail.text = ""
	match kind:
		"star", "rite":
			var sname := Loc.t(DataRegistry.get_def("skills", str(a.skill)).get("name", {}))
			_ev_gain.text = Loc.tf("UI_GSA_PR_GAIN_DUST", {"n": NumberFormat.fmt(float(a.dust))})
			_ev_detail.text = Loc.tf("UI_GSA_PR_DETAIL_XP", {"skill": sname, "from": NumberFormat.fmt_pct(float(a.xp_before)),
				"to": NumberFormat.fmt_pct(float(a.xp_after))})
			_ev_btn.text = tr("UI_GSA_PR_CTA_" + kind.to_upper())
		"refound":
			_ev_gain.text = Loc.tf("UI_GSA_PR_GAIN_PARTNERS", {"n": int(a.partners_gain)})
			_ev_detail.text = Loc.tf("UI_GSA_PR_DETAIL_REFOUND", {"bonus": NumberFormat.fmt_pct(float(a.bonus_after))})
			_ev_btn.text = tr("UI_GSA_PR_CTA_REFOUND")
		"node":
			_ev_title.text = tr("UI_GSA_PR_BUY")
			_ev_gain.text = Loc.t(_ps.node(str(a.node)).get("name", {}))
			_ev_detail.text = Loc.tf("UI_GSA_PR_DETAIL_NODE", {"cost": NumberFormat.fmt(float(a.cost)), "dust": NumberFormat.fmt(float(a.dust))})
			_ev_btn.text = tr("UI_GSA_PR_CTA_NODE")
		_:
			_ev_title.text = tr("UI_GSA_PR_NEXT")
			if a.has("step_skill"):
				var sname2 := Loc.t(DataRegistry.get_def("skills", str(a.step_skill)).get("name", {}))
				_ev_gain.text = Loc.tf("UI_GSA_PR_STEP", {"skill": sname2, "lv": int(a.step_level), "target": int(a.step_target)})
				_ev_detail.text = tr("UI_GSA_PR_STEP_" + str(a.step_kind).to_upper())
				_ev_bar.visible = true
				_ev_bar.set_target(clampf(float(a.step_level) / maxf(1.0, float(a.step_target)), 0.0, 1.0), 0.0)
			else:
				_ev_detail.text = tr("UI_PRESTIGE_ADV_NONE")


## Colonne «Cosa perdi / Cosa conservi / Cosa guadagni» dell'azione consigliata (l'anteprima è quella del sistema, identica al risultato).
func _refresh_adv_preview(a: Dictionary) -> void:
	var kind := str(a.kind)
	var h := 0
	var p: Dictionary = {}
	if kind == "star" or kind == "rite":
		p = _ps.preview_best(str(a.skill))
		h = str(p).hash()
	if h == _adv_prev_hash:
		return
	_adv_prev_hash = h
	_clear(_adv_prev)
	if p.is_empty() or not bool(p.get("ok", false)):
		return
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = tr("UI_GSA_PR_PREVIEW")
	_adv_prev.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_adv_prev.add_child(row)
	_lines(row, "UI_PRESTIGE_LOSE", p.lose, LOSE)
	_lines(row, "UI_PRESTIGE_KEEP", p.keep, KEEP)
	_text_lines(row, "UI_PRESTIGE_GAIN", _gain_texts(p), GAIN)
	var hb := float(p.hours_back)
	var back := Label.new()
	back.theme_type_variation = &"MutedLabel"
	back.text = tr("UI_PRESTIGE_BACK_UNKNOWN") if hb < 0.0 else Loc.tf("UI_PRESTIGE_BACK", {"t": NumberFormat.fmt_time(hb * 3600.0)})
	_adv_prev.add_child(back)


## Strati non ancora aperti, grigi, con cosa sono e come si aprono (si vede cosa arriverà, P9). Si ricostruiscono col cambio degli strati.
func _refresh_teasers(layers: Array) -> void:
	_clear(_adv_teaser)
	var locked: Array = []
	for lid in ["constellations", "refound", "era", "trials"]:
		if not layers.has(lid):
			locked.append(lid)
	if locked.is_empty():
		return
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = tr("UI_GSA_PR_COMING")
	_adv_teaser.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_adv_teaser.add_child(flow)
	for lid in locked:
		var body := ScreenKit.card(flow, Color(ScreenKit.EDGE), 4)
		body.custom_minimum_size.x = 240
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		body.add_child(top)
		var t := Label.new()
		t.text = tr("UI_PRESTIGE_TAB_" + str(lid).to_upper())
		t.theme_type_variation = &"SectionLabel"
		t.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		t.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		top.add_child(ScreenKit.pill(tr("UI_GSA_PR_LOCKED"), Color(ScreenKit.TEXT_DIM)))
		body.add_child(ScreenKit.muted(tr("UI_GSA_PR_TEASE_" + str(lid).to_upper())))


# ------------------------------------------------------------------ schede (solo gli strati che servono)

func _visible_layers() -> Array:
	var out: Array = []
	for lid in ["star", "constellations", "refound", "era", "trials"]:
		if not _ps.layer_visible(lid):
			continue
		# Rifondazione solo se disponibile: o si può fare adesso, o l'hai già fatta (i Soci restano da consultare)
		if lid == "refound" and not (_ps.can_refound().is_empty() or _ps.partners() > 0):
			continue
		out.append(lid)
	return out


## Scheda «Consigliere»: UN suggerimento col pulsante che porta dove farlo. Scheda «Obiettivo»: il Grande Obiettivo con la barra.
func _build_fixed_tabs() -> void:
	var scroll := ScrollContainer.new()               # la scheda può essere più alta dello spazio: scorre invece di tagliare
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_adv_page = scroll
	var av := VBoxContainer.new()
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_theme_constant_override("separation", 12)
	scroll.add_child(av)
	var card := ScreenKit.card(av, ScreenKit.accent("prestige"), 4, true)
	var ah := Label.new()
	ah.theme_type_variation = &"SectionLabel"
	ah.text = tr("UI_PRESTIGE_ADVISOR")
	card.add_child(ah)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 12)
	card.add_child(arow)
	_adv_text = Label.new()
	_adv_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_adv_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(_adv_text)
	_adv_btn = Button.new()
	_adv_btn.theme_type_variation = &"AccentButton"
	_adv_btn.text = tr("UI_PRESTIGE_ADVISOR_GO")
	_adv_btn.pressed.connect(_on_advisor_go)
	arow.add_child(_adv_btn)
	_adv_prev = VBoxContainer.new()
	_adv_prev.add_theme_constant_override("separation", 8)
	av.add_child(_adv_prev)
	_adv_teaser = VBoxContainer.new()
	_adv_teaser.add_theme_constant_override("separation", 8)
	av.add_child(_adv_teaser)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 6)
	_tabs.add_child(gv)
	_goal_page = gv
	_goal_l = Label.new()
	_goal_l.theme_type_variation = &"MutedLabel"
	_goal_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gv.add_child(_goal_l)
	_goal_bar = ProgressBar.new()
	_goal_bar.show_percentage = false
	_goal_bar.custom_minimum_size = Vector2(0, 12)
	_goal_bar.add_theme_stylebox_override("fill", UiKit.tinted_fill(GOLD))
	_goal_bar.tooltip_text = tr("UI_RS_PR_TIP_GOAL")
	gv.add_child(_goal_bar)
	_tabs.set_tab_title(TAB_ADVISOR, tr("UI_SCR_HERO_PR_TAB_ADVISOR"))
	_tabs.set_tab_title(TAB_GOAL, tr("UI_SCR_HERO_PR_TAB_GOAL"))


func _rebuild_tabs() -> void:
	if _tabs == null:
		return
	var layers := _visible_layers()
	var sig := ",".join(PackedStringArray(layers))
	if sig == _sig:
		return
	_sig = sig
	var cur := _tabs.current_tab
	var keep := ""
	if cur == TAB_ADVISOR or cur == TAB_GOAL:
		keep = "advisor" if cur == TAB_ADVISOR else "goal"
	elif cur - FIXED_TABS >= 0 and cur - FIXED_TABS < _tab_ids.size():
		keep = str(_tab_ids[cur - FIXED_TABS])
	for c in _tabs.get_children():
		if c == _adv_page or c == _goal_page:
			continue
		_tabs.remove_child(c)
		c.queue_free()
	_tab_ids = layers
	_refresh_teasers(layers)
	_star_rows.clear()
	_trial_rows.clear()
	_era_spin = null
	_era_box = null
	_trial_box = null
	_map = null
	for lid in layers:
		match str(lid):
			"star": _build_star_tab()
			"constellations": _build_constellation_tab()
			"refound": _build_refound_tab()
			"era": _build_era_tab()
			"trials": _build_trials_tab()
	_tabs.set_tab_title(TAB_ADVISOR, tr("UI_SCR_HERO_PR_TAB_ADVISOR"))
	_tabs.set_tab_title(TAB_GOAL, tr("UI_SCR_HERO_PR_TAB_GOAL"))
	for i in layers.size():
		_tabs.set_tab_title(i + FIXED_TABS, tr("UI_PRESTIGE_TAB_" + str(layers[i]).to_upper()))
	if keep == "goal":
		_tabs.current_tab = TAB_GOAL
	elif keep != "" and _tab_ids.has(keep):
		_tabs.current_tab = _tab_ids.find(keep) + FIXED_TABS
	else:
		_tabs.current_tab = TAB_ADVISOR
	_star_hash = 0
	_node_hash = 0
	_ref_hash = 0
	_era_hash = 0
	_trial_hash = 0


func _tab_page() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	return v


func _wrapped(parent: Control, key: String, muted: bool = true) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if muted:
		l.theme_type_variation = &"MutedLabel"
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ scheda STELLE

func _build_star_tab() -> void:
	var page := _tab_page()
	_wrapped(page, "UI_PRESTIGE_STAR_INFO")
	# anteprima e conferma IN ALTO: scegliendo una mansione dall'elenco il risultato si vede subito, senza scorrere
	_star_box = VBoxContainer.new()
	_star_box.add_theme_constant_override("separation", 4)
	page.add_child(_star_box)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	page.add_child(bh)
	_star_confirm = Button.new()
	_star_confirm.theme_type_variation = &"AccentButton"
	_star_confirm.pressed.connect(_on_star_confirm)
	bh.add_child(_star_confirm)
	_star_perks = Button.new()
	_star_perks.text = tr("UI_PRESTIGE_REAPPLY")
	_star_perks.tooltip_text = tr("UI_PRESTIGE_REAPPLY_TIP")
	_star_perks.pressed.connect(_on_reapply)
	bh.add_child(_star_perks)
	page.add_child(HSeparator.new())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	page.add_child(list)
	for row in DataRegistry.table("skill_prestige"):
		var sid := str(row.skill)
		var sdef: Dictionary = DataRegistry.get_def("skills", sid)
		var body := ScreenKit.card(list, Color(ScreenKit.EDGE), 4)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		body.add_child(h)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.texture = IconLib.icon("skills", sid)
		h.add_child(icon)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 2)
		h.add_child(mid)
		var top2 := HBoxContainer.new()
		top2.add_theme_constant_override("separation", 8)
		mid.add_child(top2)
		var nm := Label.new()
		nm.text = Loc.t(sdef.get("name", {}))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top2.add_child(nm)
		var st := ScreenKit.pill("", Color(ScreenKit.TEXT_DIM), tr("UI_RS_PR_TIP_ROW_STARS"))
		top2.add_child(st)
		var lvl := _mono(mid)
		var bar := ScreenKit.bar(mid, Color("#98a6ff"), 8)
		bar.tooltip_text = tr("UI_RS_PR_TIP_ROW_BAR")
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 0)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.toggle_mode = false
		btn.pressed.connect(_select_star.bind(sid))
		btn.text = tr("UI_PRESTIGE_PREVIEW_BTN")
		h.add_child(btn)
		_star_rows[sid] = {"lvl": lvl, "stars": st, "btn": btn, "bar": bar, "body": body, "edge": -1}


func _select_star(skill_id: String) -> void:
	_star_sel = skill_id
	_star_hash = 0
	_disarm()
	refresh()
	var sc := _star_box.get_parent().get_parent() as ScrollContainer if _star_box != null and _star_box.get_parent() != null else null
	if sc != null:
		sc.set_deferred("scroll_vertical", 0)        # l'anteprima è in cima: portala in vista


func _on_star_confirm() -> void:
	if _star_sel.is_empty():
		return
	var pv := _ps.preview_best(_star_sel)
	if not bool(pv.ok):
		return
	var rite := str(pv.kind) == "rite"
	var key := ("rite:" if rite else "star:") + _star_sel
	if not _confirm_step(key):
		return
	var p := _ps.do_star(_star_sel, rite)
	if p.is_empty():
		return
	var name_s := Loc.t(DataRegistry.get_def("skills", _star_sel).get("name", {}))
	_celebrate(Loc.tf("UI_PRESTIGE_FX_STAR", {"skill": name_s, "n": int(p.stars_after)}),
		Loc.tf("UI_PRESTIGE_FX_DUST", {"n": NumberFormat.fmt(float(p.dust_gain))}), true, "rite" if rite else "star")
	_star_hash = 0
	_sig = ""
	refresh()


func _on_reapply() -> void:
	if _star_sel.is_empty():
		return
	var n := _ps.reapply_perks(_star_sel)
	EventBus.notice.emit("info", Loc.tf("UI_PRESTIGE_REAPPLIED", {"n": n}), {})
	refresh()


func _refresh_stars() -> void:
	for sid in _star_rows:
		var r: Dictionary = _star_rows[sid]
		var lv := _ps.skill_level(str(sid))
		var req := _ps.star_requirement(str(sid))
		(r.lvl as Label).text = Loc.tf("UI_PRESTIGE_ROW_LEVEL", {"lv": lv, "req": req})
		(r.bar as SmoothBar).set_target(clampf(float(lv) / maxf(1.0, float(req)), 0.0, 1.0), 0.0)
		var ns := _ps.stars(str(sid))
		ScreenKit.set_pill(r.stars, Loc.tf("UI_PRESTIGE_ROW_STAR_ONE" if ns == 1 else "UI_PRESTIGE_ROW_STARS", {"n": ns}), Color(ScreenKit.GOLD) if ns > 0 else Color(ScreenKit.TEXT_DIM))
		var is_ready := _ps.can_star(str(sid)).is_empty() or _ps.can_rite(str(sid)).is_empty()
		(r.btn as Button).text = tr("UI_PRESTIGE_READY_BTN") if is_ready else tr("UI_PRESTIGE_PREVIEW_BTN")
		(r.btn as Button).theme_type_variation = &"AccentButton" if is_ready else &""
		var ek := 2 if str(sid) == _star_sel else (1 if is_ready else 0)
		if int(r.edge) != ek:
			r.edge = ek
			ScreenKit.set_edge(r.body, [Color(ScreenKit.EDGE), Color("#d2b574"), ScreenKit.accent("prestige")][ek])
	if _star_sel.is_empty() or _star_box == null:
		if _star_box != null and _star_hash != 1:
			_star_hash = 1
			_clear(_star_box)
			var pk := ScreenKit.card(_star_box, ScreenKit.accent("prestige"), 4)
			pk.add_child(ScreenKit.label("UI_RS_PR_PICK_T", "SectionLabel"))
			pk.add_child(ScreenKit.muted("UI_PRESTIGE_PICK_SKILL"))
			_star_confirm.visible = false
			_star_perks.visible = false
		return
	var p := _ps.preview_best(_star_sel)
	var h := str(p).hash()
	if h != _star_hash:
		_star_hash = h
		_clear(_star_box)
		_render_star_preview(p)
	var key := ("rite:" if str(p.kind) == "rite" else "star:") + _star_sel
	_star_confirm.visible = bool(p.ok)
	_star_confirm.text = _confirm_text(key, "UI_PRESTIGE_CONFIRM_RITE" if str(p.kind) == "rite" else "UI_PRESTIGE_CONFIRM_STAR")
	_star_perks.visible = _ps.has_perk_memory(_star_sel)


## Righe «Cosa guadagni» di un'anteprima di Stella/Rito (stesse per la scheda Stelle e per il Consigliere).
func _gain_texts(p: Dictionary) -> Array:
	var gains: Array = []
	for g in p.gain:
		gains.append(Loc.tf(str(g.key), g.params))
	if float(p.xp_after) != float(p.xp_before):
		gains.append(Loc.tf("UI_PRESTIGE_GAIN_XP", {"from": NumberFormat.fmt_pct(float(p.xp_before)), "to": NumberFormat.fmt_pct(float(p.xp_after))}))
	if float(p.haste_after) != float(p.haste_before):
		gains.append(Loc.tf("UI_PRESTIGE_GAIN_HASTE", {"from": NumberFormat.fmt_pct(float(p.haste_before)), "to": NumberFormat.fmt_pct(float(p.haste_after))}))
	for m in p.mods:
		var fam := str(m.key).split(":")[0]
		if fam == "skill_xp_pct" or fam == "skill_haste_pct":
			continue
		var fdef: Dictionary = DataRegistry.modifier_family(fam)
		gains.append(Loc.tf("UI_PRESTIGE_GAIN_MOD", {"name": Loc.t(fdef.get("desc", {})),
			"from": NumberFormat.fmt(float(m.before)), "to": NumberFormat.fmt(float(m.after))}))
	for ms in p.milestones:
		if ms.has("desc"):
			gains.append(Loc.t(ms.desc))
		elif ms.has("title"):
			gains.append(tr("UI_PRESTIGE_GAIN_TITLE"))
		elif ms.has("cosmetic"):
			gains.append(tr("UI_PRESTIGE_GAIN_FRAME"))
		elif ms.has("unlock"):
			gains.append(Loc.tf("UI_PRESTIGE_GAIN_UNLOCK", {"what": str(ms.unlock)}))
	return gains


func _render_star_preview(p: Dictionary) -> void:
	var sname := Loc.t(DataRegistry.get_def("skills", str(p.skill)).get("name", {}))
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = Loc.tf("UI_PRESTIGE_PREVIEW_RITE" if str(p.kind) == "rite" else "UI_PRESTIGE_PREVIEW_STAR", {"skill": sname})
	_star_box.add_child(head)
	if not bool(p.ok):
		var why := Label.new()
		why.text = Loc.tf(str(p.reason), {"skill": sname, "req": _ps.star_requirement(str(p.skill)),
			"rite": _ps.rite_level(), "lv": _ps.skill_level(str(p.skill))})
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_star_box.add_child(why)
		return
	_lines(_star_box, "UI_PRESTIGE_LOSE", p.lose, LOSE)
	_lines(_star_box, "UI_PRESTIGE_KEEP", p.keep, KEEP)
	var gains: Array = _gain_texts(p)
	_text_lines(_star_box, "UI_PRESTIGE_GAIN", gains, GAIN)
	var hb := float(p.hours_back)
	var back := Label.new()
	back.theme_type_variation = &"MutedLabel"
	back.text = tr("UI_PRESTIGE_BACK_UNKNOWN") if hb < 0.0 else Loc.tf("UI_PRESTIGE_BACK", {"t": NumberFormat.fmt_time(hb * 3600.0)})
	_star_box.add_child(back)


# ------------------------------------------------------------------ scheda COSTELLAZIONI

func _build_constellation_tab() -> void:
	var page := _tab_page()
	_wrapped(page, "UI_PRESTIGE_CONST_INFO")
	_map = ConstellationMap.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_map)
	_map.setup(_ps)
	_map.node_selected.connect(_on_node_selected)
	_wrapped(page, "UI_PRESTIGE_LEGEND")
	_node_box = VBoxContainer.new()
	_node_box.add_theme_constant_override("separation", 4)
	page.add_child(_node_box)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	page.add_child(bh)
	_buy1 = Button.new()
	_buy1.theme_type_variation = &"AccentButton"
	_buy1.pressed.connect(_on_buy.bind(1))
	bh.add_child(_buy1)
	_buymax = Button.new()
	_buymax.pressed.connect(_on_buy.bind(0))
	bh.add_child(_buymax)
	page.add_child(HSeparator.new())
	_respec_l = Label.new()
	_respec_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_respec_l)
	_respec_btn = Button.new()
	_respec_btn.pressed.connect(_on_respec)
	page.add_child(_respec_btn)
	if _node_sel.is_empty() and not _ps.nodes().is_empty():
		_node_sel = str(_ps.nodes()[0].id)
	_map.set_selected(_node_sel)


func _on_node_selected(node_id: String) -> void:
	_node_sel = node_id
	_node_hash = 0
	_disarm()
	refresh()


func _on_buy(qty: int) -> void:
	if _node_sel.is_empty():
		return
	var q := qty if qty > 0 else maxi(1, _ps.max_buyable(_node_sel))
	var p := _ps.buy_node(_node_sel, q)
	if p.is_empty():
		return
	if _map != null:
		_map.flash(_node_sel)
	var nd := _ps.node(_node_sel)
	_celebrate("", Loc.tf("UI_PRESTIGE_FX_NODE", {"name": Loc.t(nd.get("name", {})), "lv": int(p.level_after)}), false)
	_node_hash = 0
	refresh()


func _on_respec() -> void:
	if not _confirm_step("respec"):
		return
	var p := _ps.respec()
	if p.is_empty():
		return
	EventBus.notice.emit("success", Loc.tf("UI_PRESTIGE_RESPEC_DONE", {"n": NumberFormat.fmt(float(p.refund))}), {})
	_node_hash = 0
	refresh()


func _refresh_constellations() -> void:
	if _map == null:
		return
	_map.refresh()
	var p := _ps.preview_node(_node_sel) if not _node_sel.is_empty() else {}
	var h := (str(p) + str(_ps.dust())).hash()
	if h != _node_hash and not p.is_empty():
		_node_hash = h
		_clear(_node_box)
		_render_node(p)
	if not p.is_empty():
		_buy1.text = Loc.tf("UI_PRESTIGE_BUY1", {"cost": NumberFormat.fmt(float(p.cost))})
		ScreenKit.gate(_buy1, "" if bool(p.ok) else tr(str(p.reason)))
		var mb := int(p.max_buyable)
		var mcost := 0
		for i in mb:
			mcost += _ps.node_cost(_node_sel, int(p.level) + i)
		_buymax.text = Loc.tf("UI_PRESTIGE_BUYMAX", {"n": mb, "cost": NumberFormat.fmt(float(mcost))})
		ScreenKit.gate(_buymax, "" if mb >= 2 else tr("UI_RS_PR_WHY_BUYMAX"))
	var rp := _ps.preview_respec()
	_respec_l.text = Loc.tf("UI_PRESTIGE_RESPEC_INFO", {"refund": NumberFormat.fmt(float(rp.refund)),
		"cost": NumberFormat.fmt(float(rp.cost)), "t": NumberFormat.fmt_time(float(rp.free_in_s))})
	_respec_btn.text = _confirm_text("respec", "UI_PRESTIGE_RESPEC_BTN")
	ScreenKit.gate(_respec_btn, "" if bool(rp.ok) else tr(str(rp.get("reason", "UI_PRESTIGE_REASON_NOTHING_SPENT"))))


func _render_node(p: Dictionary) -> void:
	var nd := _ps.node(str(p.node))
	var box := ScreenKit.card(_node_box, ScreenKit.accent("prestige"), 4, true)
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = Loc.t(nd.get("name", {}))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var mp: Dictionary = nd.get("modifier_per_level", {})
	var eff := Label.new()
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.text = Loc.tf("UI_PRESTIGE_NODE_EFFECT", {"what": BonusSummary.key_title(str(mp.get("key", ""))), "from": NumberFormat.fmt(float(p.effect_before)),
		"to": NumberFormat.fmt(float(p.effect_after)), "lv": int(p.level), "lv2": int(p.level_after)})
	box.add_child(eff)
	var mxl := Label.new()
	mxl.theme_type_variation = &"MutedLabel"
	mxl.text = tr("UI_PRESTIGE_NODE_NOMAX") if int(p.max_level) < 0 else Loc.tf("UI_PRESTIGE_NODE_MAX", {"n": int(p.max_level)})
	box.add_child(mxl)
	if bool(p.dormant):
		var d := Label.new()
		d.text = tr("UI_PRESTIGE_NODE_DORMANT")
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_color_override("font_color", GOLD)
		box.add_child(d)
	if not bool(p.ok):
		var why := Label.new()
		why.text = tr(str(p.reason))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.theme_type_variation = &"MutedLabel"
		box.add_child(why)


# ------------------------------------------------------------------ scheda TENUTA (Rifondazione)

func _build_refound_tab() -> void:
	var page := _tab_page()
	_wrapped(page, "UI_PRESTIGE_REF_INFO")
	_ref_box = VBoxContainer.new()
	_ref_box.add_theme_constant_override("separation", 4)
	page.add_child(_ref_box)
	_ref_confirm = Button.new()
	_ref_confirm.theme_type_variation = &"AccentButton"
	_ref_confirm.pressed.connect(_on_refound)
	page.add_child(_ref_confirm)


func _on_refound() -> void:
	if not _confirm_step("refound"):
		return
	var p := _ps.do_refound()
	if p.is_empty():
		return
	_celebrate(Loc.tf("UI_PRESTIGE_FX_REFOUND", {"n": int(p.partners_gain)}), Loc.tf("UI_PRESTIGE_FX_BONUS", {"p": NumberFormat.fmt_pct(float(p.bonus_after))}), true, "refound")
	_ref_hash = 0
	refresh()


func _refresh_refound() -> void:
	if _ref_box == null:
		return
	var p := _ps.preview_refound()
	var h := str(p).hash()
	if h != _ref_hash:
		_ref_hash = h
		_clear(_ref_box)
		var head := Label.new()
		head.theme_type_variation = &"SectionLabel"
		head.text = tr("UI_PRESTIGE_REF_PREVIEW")
		_ref_box.add_child(head)
		var cur := Label.new()
		cur.text = Loc.tf("UI_PRESTIGE_REF_CURRENT", {"n": int(p.partners_before), "bonus": NumberFormat.fmt_pct(float(p.bonus_before))})
		_ref_box.add_child(cur)
		if bool(p.ok):
			_lines(_ref_box, "UI_PRESTIGE_LOSE", p.lose, LOSE)
			_lines(_ref_box, "UI_PRESTIGE_KEEP", p.keep, KEEP)
			_text_lines(_ref_box, "UI_PRESTIGE_GAIN", [Loc.tf("UI_PRESTIGE_GAIN_PARTNERS", {"n": int(p.partners_gain)}),
				Loc.tf("UI_PRESTIGE_REF_AFTER", {"n": int(p.partners_after), "bonus": NumberFormat.fmt_pct(float(p.bonus_after))})], GAIN)
		else:
			var why := Label.new()
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.text = Loc.tf(str(p.reason), {"units": NumberFormat.fmt(float(p.units)), "min": NumberFormat.fmt(float(p.min_units))})
			_ref_box.add_child(why)
			if ScreenKit.available("estate"):
				_ref_box.add_child(ScreenKit.go_button(tr("UI_RS_PR_GO_ESTATE"), ScreenKit.target("estate")))
	_ref_confirm.visible = bool(p.ok)
	_ref_confirm.text = _confirm_text("refound", "UI_PRESTIGE_CONFIRM_REFOUND")


# ------------------------------------------------------------------ scheda ERE

func _dec(v: float) -> String:
	return NumberFormat.decimal(v, 2, TranslationServer.get_locale().substr(0, 2))


## Righe di un'anteprima con i numeri decimali già formattati nella lingua attiva (from/to/n).
func _fmt_lines(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		var p: Dictionary = (l.params as Dictionary).duplicate()
		for k in ["from", "to"]:
			if p.has(k) and typeof(p[k]) == TYPE_FLOAT:
				p[k] = _dec(float(p[k]))
		if p.has("n") and typeof(p.n) == TYPE_FLOAT:
			p["n"] = NumberFormat.fmt(float(p.n))
		out.append({"key": l.key, "params": p})
	return out


func _build_era_tab() -> void:
	var page := _tab_page()
	_wrapped(page, "UI_ERA_INTRO")
	_era_cur_l = Label.new()
	_era_cur_l.theme_type_variation = &"MonoLabel"
	_era_cur_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_era_cur_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	page.add_child(row)
	var l := Label.new()
	l.text = tr("UI_ERA_SELECT")
	row.add_child(l)
	_era_spin = SpinBox.new()
	_era_spin.min_value = 1
	_era_spin.step = 1
	_era_spin.rounded = true
	_era_spin.value_changed.connect(_on_era_spin)
	row.add_child(_era_spin)
	_era_box = VBoxContainer.new()
	_era_box.add_theme_constant_override("separation", 4)
	page.add_child(_era_box)
	_era_btn = Button.new()
	_era_btn.theme_type_variation = &"AccentButton"
	_era_btn.pressed.connect(_on_era_switch)
	page.add_child(_era_btn)
	_era_sel = _ps.era_current()
	_era_spin.set_value_no_signal(_era_sel)


func _on_era_spin(v: float) -> void:
	_era_sel = int(v)
	_era_hash = 0
	refresh()


func _on_era_switch() -> void:
	var p := _ps.do_select_era(_era_sel)
	if p.is_empty():
		return
	_celebrate("", _ps.era_name(_era_sel), false)
	_era_hash = 0
	refresh()


func _refresh_era() -> void:
	if _era_box == null or _era_spin == null:
		return
	_era_spin.max_value = _ps.era_max()
	if _era_sel < 1 or _era_sel > _ps.era_max():
		_era_sel = _ps.era_current()
		_era_spin.set_value_no_signal(_era_sel)
	_era_cur_l.text = Loc.tf("UI_ERA_CURRENT_N", {"name": _ps.era_name(_ps.era_current()), "max": _ps.era_max()})
	var p := _ps.preview_era(_era_sel)
	var h := str(p).hash()
	if h != _era_hash:
		_era_hash = h
		_clear(_era_box)
		var head := Label.new()
		head.theme_type_variation = &"SectionLabel"
		head.text = _ps.era_name(_era_sel)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_era_box.add_child(head)
		var st := Label.new()
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.text = Loc.tf("UI_ERA_STATS", {"mm": _dec(float(p.monster_mult)), "rm": _dec(float(p.reward_mult)),
			"ess": int(p.essence_qty), "crate": _dec(float(p.crate_mult))})
		_era_box.add_child(st)
		var rk := Label.new()
		rk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rk.theme_type_variation = &"MutedLabel"
		# Era I (e prime Ere): "servono circa 0 Ranghi" non ha senso, si dice che non servono (QA4 #4)
		rk.text = Loc.tf("UI_ERA_RANKS" if int(p.ranks_needed) > 0 else "UI_FIXC_ERA_RANKS_NONE",
			{"ranks": int(p.ranks_needed), "cap": int(p.rank_cap)})
		_era_box.add_child(rk)
		var wd := Label.new()
		wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wd.text = Loc.tf("UI_ERA_WARDEN", {"era": _era_sel, "kills": int(p.warden_kills), "dust": NumberFormat.fmt(float(p.warden_dust))})
		_era_box.add_child(wd)
		_wrapped(_era_box, "UI_ERA_WARDEN_NOTE")
		_lines(_era_box, "UI_PRESTIGE_LOSE", _fmt_lines(p.lose), LOSE)
		_lines(_era_box, "UI_PRESTIGE_KEEP", p.keep, KEEP)
		_lines(_era_box, "UI_PRESTIGE_GAIN", _fmt_lines(p.gain), GAIN)
		if not bool(p.ok):
			var why := Label.new()
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.text = tr(str(p.reason))
			_era_box.add_child(why)
	_era_btn.visible = bool(p.ok)
	_era_btn.text = Loc.tf("UI_ERA_SWITCH", {"era": _era_sel})


# ------------------------------------------------------------------ scheda PROVE

func _trial_name(id: String) -> String:
	return Loc.t(DataRegistry.get_def("trials", id).get("name", {}))


func _target_name(tgt: Dictionary) -> String:
	if str(tgt.get("kind", "")) == "dungeon":
		return Loc.t(DataRegistry.get_def("dungeons", str(tgt.id)).get("name", {}))
	return Loc.t(DataRegistry.get_def("monsters", str(tgt.get("id", ""))).get("name", {}))


func _build_trials_tab() -> void:
	var page := _tab_page()
	_wrapped(page, "UI_TRIALS_INTRO")
	_trial_banner = Label.new()
	_trial_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trial_banner.add_theme_color_override("font_color", GOLD)
	page.add_child(_trial_banner)
	# anteprima e conferma in alto, come nella scheda Stelle
	_trial_box = VBoxContainer.new()
	_trial_box.add_theme_constant_override("separation", 4)
	page.add_child(_trial_box)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	page.add_child(bh)
	_trial_start = Button.new()
	_trial_start.theme_type_variation = &"AccentButton"
	_trial_start.pressed.connect(_on_trial_start)
	bh.add_child(_trial_start)
	_trial_abandon = Button.new()
	_trial_abandon.text = tr("UI_TRIALS_ABANDON")
	_trial_abandon.pressed.connect(_on_trial_abandon)
	bh.add_child(_trial_abandon)
	page.add_child(HSeparator.new())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	page.add_child(list)
	for tid in _ps.trial_ids():
		var tbody := ScreenKit.card(list, Color(ScreenKit.EDGE), 4)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		tbody.add_child(h)
		var nm := Label.new()
		nm.text = _trial_name(str(tid))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var gr := _mono(h)
		gr.custom_minimum_size = Vector2(110, 0)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 0)
		btn.pressed.connect(_select_trial.bind(str(tid)))
		h.add_child(btn)
		_trial_rows[str(tid)] = {"grades": gr, "btn": btn}
	if _trial_sel.is_empty() and _ps.is_trial_active():
		_trial_sel = str(_ps.trial_active().id)


func _select_trial(id: String) -> void:
	_trial_sel = id
	_trial_hash = 0
	_disarm()
	refresh()


func _on_trial_start() -> void:
	var id := _trial_sel
	if id.is_empty():
		return
	var tier := mini(_ps.trial_tiers_done(id) + 1, _ps.trial_tier_count(id))
	if not _confirm_step("trial_start"):
		return
	var p := _ps.start_trial(id, tier)
	if p.is_empty():
		return
	# avvia anche lo scontro (il sistema Combattimento è dell'altro agente: qui lo si chiama soltanto)
	var cs: Object = Game.system("combat")
	var tgt: Dictionary = p.target
	var is_dungeon := str(tgt.get("kind", "")) == "dungeon"
	var started := false
	if cs != null:
		if is_dungeon and cs.has_method("start_dungeon"):
			started = bool(cs.call("start_dungeon", str(tgt.id)))
		elif cs.has_method("start"):
			started = bool(cs.call("start", str(tgt.zone), str(tgt.id)))
	if (p.get("rules_raw", {}) as Dictionary).has("time_limit_s"):
		EventBus.notice.emit("warning", tr("UI_TRIALS_TIMED_WARNING"), {})
	_trial_hash = 0
	if started:
		# dopo l'avvio si va dove si combatte: Dungeon per la Maratona, Combattimento per i boss di zona
		EventBus.screen_requested.emit("dungeon" if is_dungeon else "combat", {})
		return
	EventBus.notice.emit("info", tr("UI_TRIALS_FIGHT_HINT"), {})
	refresh()


func _on_trial_abandon() -> void:
	_ps.abandon_trial()
	_trial_hash = 0
	refresh()


func _refresh_trials() -> void:
	if _trial_box == null:
		return
	var active := _ps.trial_active()
	_trial_banner.visible = not active.is_empty()
	if not active.is_empty():
		var tgt := _ps.trial_target(str(active.id), int(active.tier))
		var zd: Dictionary = DataRegistry.get_def("zones", str(tgt.get("zone", "")))
		_trial_banner.text = Loc.tf("UI_TRIALS_ACTIVE_BANNER", {"name": _trial_name(str(active.id)), "tier": int(active.tier),
			"target": _target_name(tgt), "zone": Loc.t(zd.get("name", {}))})
	for ov in _ps.trials_overview():
		var r: Dictionary = _trial_rows.get(str(ov.id), {})
		if r.is_empty():
			continue
		(r.grades as Label).text = Loc.tf("UI_TRIALS_GRADES", {"done": int(ov.done), "n": int(ov.count)})
		var key := "UI_TRIALS_BTN_DETAILS"
		if str(ov.status) == "active":
			key = "UI_TRIALS_BTN_ACTIVE"
		elif str(ov.status) == "complete":
			key = "UI_TRIALS_BTN_COMPLETE"
		(r.btn as Button).text = tr(key)
	var tier := 0
	var p: Dictionary = {}
	if not _trial_sel.is_empty():
		tier = mini(_ps.trial_tiers_done(_trial_sel) + 1, _ps.trial_tier_count(_trial_sel))
		p = _ps.preview_trial(_trial_sel, tier)
	var h := str([p, active]).hash()
	if h != _trial_hash:
		_trial_hash = h
		_clear(_trial_box)
		if p.is_empty():
			_wrapped(_trial_box, "UI_TRIALS_NONE_SELECTED")
		else:
			var head := Label.new()
			head.theme_type_variation = &"SectionLabel"
			head.text = Loc.tf("UI_TRIALS_HEAD", {"name": _trial_name(_trial_sel), "tier": str(p.tier_roman)})
			_trial_box.add_child(head)
			var tgt2: Dictionary = p.target
			var zd2: Dictionary = DataRegistry.get_def("zones", str(p.zone))
			var tl := Label.new()
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.text = Loc.tf("UI_TRIALS_TARGET_DUNGEON" if str(tgt2.get("kind", "")) == "dungeon" else "UI_TRIALS_TARGET_BOSS",
				{"target": _target_name(tgt2), "zone": Loc.t(zd2.get("name", {}))})
			_trial_box.add_child(tl)
			_lines(_trial_box, "UI_TRIALS_RULES", p.rules, GOLD)
			_lines(_trial_box, "UI_PRESTIGE_LOSE", p.lose, LOSE)
			_lines(_trial_box, "UI_PRESTIGE_KEEP", p.keep, KEEP)
			_lines(_trial_box, "UI_PRESTIGE_GAIN", _fmt_lines(p.gain), GAIN)
			if not bool(p.ok):
				var rp: Dictionary = p.reason_params
				var why := Label.new()
				why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				why.text = Loc.tf(str(p.reason), rp)
				_trial_box.add_child(why)
	_trial_start.visible = not p.is_empty() and bool(p.ok)
	_trial_start.text = _confirm_text("trial_start", "UI_TRIALS_START")
	_trial_abandon.visible = not active.is_empty()


# ------------------------------------------------------------------ comuni

func refresh() -> void:
	if _ps == null or _tabs == null:
		return
	_rebuild_tabs()
	_dust_l.set_value(NumberFormat.fmt(float(_ps.dust())), "")
	_stars_l.set_value(str(_ps.stars_total()), "")
	_partners_l.set_value(str(_ps.partners()), "")
	_partners_l.visible = _ps.layer_visible("refound")
	var adv := _ps.advise()
	_refresh_event(adv)
	_refresh_advisor(adv)
	_refresh_goal()
	if _armed != "" and Time.get_ticks_msec() - _armed_at > CONFIRM_MS:
		_disarm()
	if _tab_ids.has("star"):
		_refresh_stars()
	if _tab_ids.has("constellations"):
		_refresh_constellations()
	if _tab_ids.has("refound"):
		_refresh_refound()
	if _tab_ids.has("era"):
		_refresh_era()
	if _tab_ids.has("trials"):
		_refresh_trials()


func _refresh_advisor(a: Dictionary) -> void:
	_refresh_adv_preview(a)
	var kind := str(a.kind)
	_adv_btn.visible = kind != "none"
	_adv_text.add_theme_color_override("font_color", Color(ScreenKit.TEXT_DIM) if kind == "none" else Color("#e6e1d6"))
	match kind:
		"star", "rite":
			var sname := Loc.t(DataRegistry.get_def("skills", str(a.skill)).get("name", {}))
			_adv_text.text = Loc.tf("UI_PRESTIGE_ADV_" + kind.to_upper(), {"skill": sname, "dust": NumberFormat.fmt(float(a.dust)),
				"from": NumberFormat.fmt_pct(float(a.xp_before)), "to": NumberFormat.fmt_pct(float(a.xp_after))})
		"refound":
			_adv_text.text = Loc.tf("UI_PRESTIGE_ADV_REFOUND", {"n": int(a.partners_gain), "bonus": NumberFormat.fmt_pct(float(a.bonus_after))})
		"node":
			_adv_text.text = Loc.tf("UI_PRESTIGE_ADV_NODE", {"name": Loc.t(_ps.node(str(a.node)).get("name", {})),
				"cost": NumberFormat.fmt(float(a.cost)), "dust": NumberFormat.fmt(float(a.dust))})
		_:
			if a.has("step_skill"):
				var sname2 := Loc.t(DataRegistry.get_def("skills", str(a.step_skill)).get("name", {}))
				_adv_text.text = Loc.tf("UI_PRESTIGE_ADV_NEXT_" + str(a.step_kind).to_upper(), {"skill": sname2, "lv": int(a.step_level), "target": int(a.step_target)})
			else:
				_adv_text.text = tr("UI_PRESTIGE_ADV_NONE")


func _refresh_goal() -> void:
	var g := _ps.next_goal()
	_goal_l.visible = not g.is_empty()
	_goal_bar.visible = not g.is_empty()
	_tabs.set_tab_hidden(TAB_GOAL, g.is_empty())
	if g.is_empty():
		return
	_goal_l.text = Loc.tf("UI_PRESTIGE_GOAL", {"name": tr("UI_PRESTIGE_" + str(g.id).to_upper()), "cur": NumberFormat.fmt(float(g.current)),
		"qty": NumberFormat.fmt(float(g.qty)), "dust": NumberFormat.fmt(float(g.stardust))})
	_goal_bar.max_value = float(g.qty)
	_goal_bar.value = minf(float(g.current), float(g.qty))


func _on_advisor_go() -> void:
	var a := _ps.advise()
	match str(a.kind):
		"star", "rite":
			_star_sel = str(a.skill)
			_star_hash = 0
			_goto_tab("star")
		"refound":
			_goto_tab("refound")
		"node":
			_node_sel = str(a.node)
			_node_hash = 0
			if _map != null:
				_map.set_selected(_node_sel)
			_goto_tab("constellations")
	_disarm()
	refresh()


func _goto_tab(layer_id: String) -> void:
	var i := _tab_ids.find(layer_id)
	if i >= 0:
		_tabs.current_tab = i + FIXED_TABS


# conferma a due passaggi: il primo clic arma (testo "Sicuro?"), il secondo entro CONFIRM_MS esegue
func _confirm_step(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if _armed == key and now - _armed_at <= CONFIRM_MS:
		_disarm()
		return true
	_armed = key
	_armed_at = now
	refresh()
	return false


func _disarm() -> void:
	_armed = ""


func is_armed(key: String) -> bool:
	return _armed == key


func _confirm_text(key: String, base_key: String) -> String:
	if _armed == key:
		return tr("UI_PRESTIGE_SURE")
	return tr(base_key)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _lines(parent: Control, title_key: String, lines: Array, color: Color) -> void:
	var texts: Array = []
	for l in lines:
		texts.append(Loc.tf(str(l.key), l.params))
	_text_lines(parent, title_key, texts, color)


func _text_lines(parent: Control, title_key: String, texts: Array, color: Color) -> void:
	if texts.is_empty():
		return
	var v := ScreenKit.card(parent, color.darkened(0.2), 4)
	var t := Label.new()
	t.theme_type_variation = &"SectionLabel"
	t.text = tr(title_key)
	t.add_theme_color_override("font_color", color)
	v.add_child(t)
	for s2 in texts:
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = "• " + str(s2)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)


# ------------------------------------------------------------------ effetto di soddisfazione (tween)

## Lampo, scritta che "pompa" e pioggia di stelline. Con "riduci animazioni" resta solo la notifica.
func _celebrate(big: String, small: String, burst: bool = true, kind: String = "star") -> void:
	EventBus.notice.emit("success", (big + " " + small).strip_edges(), {})
	# cerimonia breve e saltabile con Spazio (src/ui/fx); se parte, sostituisce il vecchio lampo con le stelline
	if burst and Fx.ceremony(big, small, FxPalette.GOLD if kind != "refound" else FxPalette.VIOLET, kind):
		return
	if Settings.get_value("reduce_motion") or _fx == null or not is_inside_tree():
		return
	_fx.global_position = global_position
	_fx.size = size
	var center := size * 0.5
	if burst:
		var flash := ColorRect.new()
		flash.color = Color(1.0, 0.95, 0.7, 0.55)
		flash.size = size
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(flash)
		var tf := create_tween()
		tf.tween_property(flash, "color:a", 0.0, 0.6)
		tf.tween_callback(flash.queue_free)
		for i in FX_STARS:
			var s := Label.new()
			s.text = "*"
			s.add_theme_color_override("font_color", GOLD)
			s.add_theme_font_size_override("font_size", 22)
			s.position = center
			_fx.add_child(s)
			var ang := TAU * float(i) / float(FX_STARS)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(s, "position", center + Vector2(cos(ang), sin(ang)) * (120.0 + 14.0 * float(i % 3)), 0.9) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "modulate:a", 0.0, 0.9)
			tw.chain().tween_callback(s.queue_free)
	var l := Label.new()
	l.text = big if not big.is_empty() else small
	l.add_theme_font_size_override("font_size", 30 if burst else 20)
	l.add_theme_color_override("font_color", GOLD)
	l.size = Vector2(size.x, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, center.y - 40.0)
	l.pivot_offset = Vector2(size.x * 0.5, 20)
	l.scale = Vector2(0.6, 0.6)
	_fx.add_child(l)
	var tl := create_tween()
	tl.tween_property(l, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tl.tween_property(l, "scale", Vector2.ONE, 0.12)
	tl.tween_interval(0.9)
	tl.tween_property(l, "modulate:a", 0.0, 0.5)
	tl.tween_callback(l.queue_free)
	if big != "" and small != "":
		var l2 := Label.new()
		l2.text = small
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.size = Vector2(size.x, 30)
		l2.position = Vector2(0, center.y + 6.0)
		l2.modulate.a = 0.0
		_fx.add_child(l2)
		var t2 := create_tween()
		t2.tween_interval(0.25)
		t2.tween_property(l2, "modulate:a", 1.0, 0.25)
		t2.tween_interval(0.8)
		t2.tween_property(l2, "modulate:a", 0.0, 0.5)
		t2.tween_callback(l2.queue_free)
