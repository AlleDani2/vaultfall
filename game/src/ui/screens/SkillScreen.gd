extends GameScreen
## Schermata di una mansione (docs/16 §3.1-3.2). Scena unica per tutte: params {"skill": id}.
## Solo presentazione: legge SkillSystem (Game.system("skills")) e ascolta EventBus; i pulsanti chiamano
## start()/stop()/choose_perk(). Aggiornamento ≤ 10 Hz (le righe delle azioni a 2 Hz); animazioni = tweens,
## disattivate o ridotte a testo con Settings "riduci animazioni".

const ICON_SIZE := Vector2(24, 24)
const FX_MAX := 6
const FX_RISE := 28.0
const FX_PAD := 6.0                    # margine del riquadro che contiene le icone animate
const ROWS_EVERY := 5                    # le righe lente (ingredienti, filtri) si aggiornano ogni N refresh
const GOLD := Color(1.0, 0.85, 0.35)
const MISSING := Color(0.9, 0.4, 0.35)
const CARD_MIN_W := 300.0                # carte-azione (revisione grafica 1.0, problema 6): 3 colonne a 1280 logici larghi, 2 se stretto
const CARD_GAP := 8
const CARD_ICON := 2                     # icona dell'oggetto prodotto a scala intera: 2× il PNG da 32 px = 64 px
const COLS_MAX := 4
const SEEN_KEY := "skills_list:"         # voce di Settings.seen_intro (+ id mansione): dalla seconda visita «Solo ciò che posso fare» parte acceso
const FLASH := Color(1.7, 1.55, 0.9)

var _skill_id: String = ""
var _sk: SkillSystem
var _actions: Array = []
var _build_gen: int = 0                  # annulla la costruzione a fette se la schermata viene ricostruita o chiusa
var _rows: Dictionary = {}               # action_id -> {panel, name, info, ingr (testo del suggerimento), yield, mastery_l, mbar, btn, ml, locked, req_box, req_sig, a}
var _counter: int = 0
var _dirty: bool = true
var _fx_count: int = 0
var _last_mastery: Dictionary = {}       # action_id -> livello di maestria visto
var _filter_cat: String = ""
var _cats: PackedStringArray = []
# filtri che arrivano da un requisito mancante cliccato altrove (ReqLink, G37): azioni che producono un oggetto / solo quelle già sbloccate
var _produces: String = ""
var _avail_only: bool = false
var _chip: HBoxContainer
var _chip_l: Label

var _hdr: SkillHeader
var _head_panel: PanelContainer
var _icon: TextureRect
var _title: Label
var _level_l: Label
var _tool_l: Label
var _tool_hint_txt: String = ""
var _tool_hint_ready: bool = false
var _xp_bar: ProgressBar
var _xp_l: Label
var _eta_l: Label
var _active_icon: TextureRect
var _active_name: Label
var _active_bar: SmoothBar
var _active_info: Label
var _stop_btn: Button
var _gain_l: Label
var _full_l: Label
var _perks: SkillPerkPanel            # pannello «Talenti di mansione» (componente condiviso con Coltivazione, Eroe, Taglie)
var _extras: SkillExtras
var _filter: OptionButton
var _search: LineEdit
var _only: CheckBox
var _list: GridContainer
var _scroll: ScrollContainer
var _locked_btn: Button                  # «▸ Bloccate (n) — la prossima: X al Liv N»
var _locked_box: GridContainer           # le carte bloccate: chiuso finché non lo apri
var _locked_open: bool = false
var _empty_l: Label                      # «Niente di fattibile adesso»: appare se il filtro nasconde tutte le righe sbloccate
var _order_sig: String = ""              # firma dell'ordine delle righe (si riordina solo se cambia)
var _locked_info: int = 0
var _next_locked: Dictionary = {}
var _only_default: bool = false          # «Solo ciò che posso fare» acceso di partenza (dalla seconda visita)
var _xp_tween: Tween
var _anim_aid: String = ""             # azione per cui gira il ciclo dell'attrezzo ("" = fermo)
var _anim_dur: float = 0.0


func open(params: Dictionary) -> void:
	_skill_id = str(params.get("skill", ""))
	_tool_hint_ready = false
	_sk = Game.system("skills") as SkillSystem
	if _sk == null or _skill_id.is_empty():
		return
	_produces = str(params.get("produces", ""))
	_avail_only = str(params.get("filter", "")) == "available"
	var seen: Array = Settings.get_value("seen_intro")
	_only_default = seen.has(SEEN_KEY + _skill_id)
	if not _only_default:
		seen = seen.duplicate()
		seen.append(SEEN_KEY + _skill_id)
		Settings.set_value("seen_intro", seen)
	_actions = []
	for a in DataRegistry.actions_for_skill(_skill_id):
		if str(a.get("kind", "")) != "crop":
			_actions.append(a)
	_build()
	EventBus.action_completed.connect(_on_action_completed)
	EventBus.level_up.connect(_on_level_up)
	EventBus.modifiers_changed.connect(_mark_dirty)
	EventBus.state_loaded.connect(_mark_dirty)
	EventBus.locale_changed.connect(_on_locale)
	_update_chip()
	refresh()
	if str(params.get("focus", "")) == "queue" and _extras != null:       # scorciatoia Q: apre la coda azioni
		_extras.open_panel()
		ReqLink.reveal.call_deferred(_extras)


func close() -> void:
	_build_gen += 1
	Fx.tool_stop(_icon, _active_icon)
	_anim_aid = ""
	for pair in [[EventBus.action_completed, _on_action_completed], [EventBus.level_up, _on_level_up],
			[EventBus.modifiers_changed, _mark_dirty], [EventBus.state_loaded, _mark_dirty], [EventBus.locale_changed, _on_locale]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


# ------------------------------------------------------------------ costruzione

func _build() -> void:
	_build_gen += 1
	for c in get_children():
		c.free()
	_rows.clear()
	_anim_aid = ""
	add_theme_constant_override("separation", 8)
	var def: Dictionary = DataRegistry.get_def("skills", _skill_id)
	# testata unica (una riga) + striscia «In corso» (una riga)
	_hdr = SkillHeader.new()
	add_child(_hdr)
	_hdr.setup(_skill_id, Loc.t(def.get("name", {})), Loc.t(def.get("desc", {})), "skill:" + _skill_id)
	_head_panel = _hdr.head_panel
	_icon = _hdr.icon
	_title = _hdr.title
	_level_l = _hdr.level_l
	_tool_l = _hdr.tool_l
	_xp_bar = _hdr.xp_bar
	_xp_l = _hdr.xp_l
	_eta_l = _hdr.eta_l
	_active_icon = _hdr.strip_icon
	_active_name = _hdr.strip_name
	_active_bar = _hdr.strip_bar
	_active_info = _hdr.strip_info
	_gain_l = _hdr.strip_gain
	_stop_btn = _hdr.strip_btn
	_stop_btn.pressed.connect(func() -> void: _sk.stop(); refresh())

	# avviso Deposito pieno: il lavoro si ferma o i ritrovamenti vanno persi, meglio dirlo qui che nel registro
	_full_l = _label(tr("UI_BANK_FULL_BANNER"), &"")
	_full_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_full_l.add_theme_color_override("font_color", MISSING)
	_full_l.visible = false
	add_child(_full_l)

	# tutto il resto scorre insieme (talenti, coda, filtri, azioni): un solo scorrimento, niente liste dentro le liste
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_scroll = sc
	sc.resized.connect(_fit_columns)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	sc.add_child(body)

	# talenti: il pulsante «Talenti •» sta nella testata, le righe dei talenti qui sotto (si aprono con il pulsante)
	_perks = SkillPerkPanel.new()
	_perks.setup(_skill_id, true)
	_perks.changed.connect(func() -> void:
		_dirty = true
		refresh())
	_hdr.add_action_button(_perks.perk_button())
	body.add_child(_perks)

	# coda azioni, automazione, pozioni e banchetti: il pulsante «Coda ▾» sta nella testata, il corpo qui sotto
	_extras = SkillExtras.new()
	_extras.setup(_skill_id, true)
	_hdr.add_action_button(_extras.toggle_button())
	body.add_child(_extras)

	# filtri
	var fr := HBoxContainer.new()
	fr.add_theme_constant_override("separation", 8)
	body.add_child(fr)
	_cats = PackedStringArray()
	for a in _actions:
		var cat := str(a.get("category", ""))
		if not cat.is_empty() and not _cats.has(cat):
			_cats.append(cat)
	_filter = OptionButton.new()
	_filter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_filter.add_item(tr("UI_SKILLS_FILTER_ALL"))
	for c in _cats:
		_filter.add_item(_cat_name(c))
	_filter.item_selected.connect(func(i: int) -> void:
		_filter_cat = "" if i == 0 else _cats[i - 1]
		_apply_filters())
	_filter.visible = _cats.size() > 1
	fr.add_child(_filter)
	_search = LineEdit.new()
	_search.placeholder_text = "UI_SKILLS_SEARCH"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _apply_filters())
	_search.visible = _actions.size() > 12
	fr.add_child(_search)
	_only = CheckBox.new()
	_only.text = "UI_SKILLS_ONLY_CRAFTABLE"
	_only.visible = _has_inputs_any()
	_only.button_pressed = _only.visible and _only_default      # dalla seconda visita parte acceso (solo dove ci sono ricette)
	_only.toggled.connect(func(_on: bool) -> void: _apply_filters())
	fr.add_child(_only)
	fr.visible = _filter.visible or _search.visible or _only.visible       # niente riga vuota (e niente spazio) se non c'è nulla da filtrare

	# chip del filtro che arriva da un requisito cliccato («Produce: Lingotto di Ferro  [Mostra tutte]»)
	_chip = HBoxContainer.new()
	_chip.add_theme_constant_override("separation", 8)
	_chip.visible = false
	_chip_l = _label("", &"SectionLabel")
	_chip.add_child(_chip_l)
	var chip_x := Button.new()
	chip_x.text = "UI_UIB_FILTER_CLEAR"
	chip_x.pressed.connect(_clear_req_filter)
	_chip.add_child(chip_x)
	body.add_child(_chip)

	# elenco azioni: prima le fattibili, poi per livello; le bloccate in un gruppo chiuso sotto
	_list = GridContainer.new()
	_list.name = "CardGrid"
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", CARD_GAP)
	_list.add_theme_constant_override("v_separation", CARD_GAP)
	body.add_child(_list)
	_locked_btn = Button.new()
	_locked_btn.name = "LockedToggle"
	_locked_btn.toggle_mode = true
	_locked_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_locked_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_locked_btn.button_pressed = _locked_open
	_locked_btn.visible = false
	_locked_btn.toggled.connect(func(on: bool) -> void:
		_locked_open = on
		_locked_box.visible = on
		_update_locked_group())
	body.add_child(_locked_btn)
	_locked_box = GridContainer.new()
	_locked_box.name = "LockedRows"
	_locked_box.columns = 2
	_locked_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked_box.add_theme_constant_override("h_separation", CARD_GAP)
	_locked_box.add_theme_constant_override("v_separation", CARD_GAP)
	_locked_box.visible = _locked_open
	body.add_child(_locked_box)
	_empty_l = _label(tr("UI_SKILLS_NONE_FEASIBLE"), &"MutedLabel")
	_empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_l.visible = false
	body.add_child(_empty_l)
	_order_sig = ""
	var sorted_actions := _actions.duplicate()
	sorted_actions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("level_req", 1)) < int(y.get("level_req", 1)))
	_build_gen += 1
	var gen := _build_gen
	var row_n := sorted_actions.size()
	var row_i := 0
	while row_i < row_n:
		var stop := mini(row_n, row_i + ROWS_PER_SLICE) if GameScreen.sliced_builds else row_n
		while row_i < stop:
			_build_row(sorted_actions[row_i])
			row_i += 1
		_dirty = true
		if row_i < row_n:
			await get_tree().process_frame
			if not is_instance_valid(self) or not is_inside_tree() or gen != _build_gen:
				return
	_dirty = true


## Il tutorial chiede alla schermata di prepararsi ("extras" = apre il pannello Coda, pozioni e banchetti).
func tut_prepare(what: String) -> void:
	if what == "extras" and _extras != null:
		_extras.open_panel()


func _has_inputs_any() -> bool:
	for a in _actions:
		if a.has("inputs"):
			return true
	return false


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _cat_name(cat: String) -> String:
	var key := "UI_SKILLS_CAT_" + cat.to_upper()
	var t := tr(key)
	return t if t != key else cat.capitalize()


## Carta di un'azione: normale, in esecuzione (bordo verde, 2 px) o bloccata (si attenua con modulate).
func _row_style(active: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.115, 0.15, 0.95)
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2 if active else 1)
	sb.border_color = FxPalette.GREEN if active else Color("#2c303b")
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Colonne della griglia di carte dalla larghezza utile: 3 a 1280 logici, 2 se stretto, 4 se molto largo (colonne, non spazio).
func _fit_columns() -> void:
	if _scroll == null or _list == null:
		return
	var w := _scroll.size.x - 12.0
	var cols := clampi(int((w + CARD_GAP) / (CARD_MIN_W + CARD_GAP)), 1, COLS_MAX)
	if _list.columns != cols:
		_list.columns = cols
	if _locked_box != null and _locked_box.columns != cols:
		_locked_box.columns = cols


## CARTA dell'azione (revisione grafica 1.0, problema 6; wireframe 03_mansione_schede.svg): icona dell'oggetto prodotto (64 px, scala
## intera), nome, «tempo · XP», resa all'ora, Maestria con barra, requisiti mancanti (rossi, cliccabili) e pulsante a tutta larghezza.
## La carta in esecuzione ha il bordo verde e una barra di avanzamento continua in basso.
func _build_row(a: Dictionary) -> void:
	var aid: String = a.id
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(panel)
	TutorialTargets.mark(panel, "row:" + aid)          # tutorial: tutta la carta dell'azione
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var ic := VaultKit.pix(IconLib.icon("items", _main_output(a)), CARD_ICON)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(ic)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 0)
	mid.custom_minimum_size = Vector2(120, 0)
	top.add_child(mid)
	var name_l := _label(Loc.t(a.get("name", {})), &"")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(name_l)
	var info := _label("", &"MutedLabel")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(info)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	v.add_child(right)
	var give_l := _label("", &"")                # «Dà: 1–3 Tronco di Pino (ne hai 53)»: la resa di UNA azione e quanto ne hai, sempre in vista
	give_l.add_theme_font_size_override("font_size", UiType.NOTE)
	right.add_child(give_l)
	var yield_l := _label("", &"MonoLabel")      # «Ogni ora: ~1.206 · 8.400 XP» (va a capo se serve: mai troncata)
	right.add_child(yield_l)
	var ingr_l := RichTextLabel.new()            # «Servono: 2× Carbone (hai 14) · 60× Lino (hai 48, ne mancano 12)»: ambra solo se non basta
	ingr_l.bbcode_enabled = true
	ingr_l.fit_content = true
	ingr_l.scroll_active = false
	ingr_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ingr_l.add_theme_font_size_override("normal_font_size", UiType.NOTE)
	ingr_l.add_theme_font_size_override("bold_font_size", UiType.NOTE)
	ingr_l.meta_clicked.connect(ReqLink.meta_go)      # il materiale che non basta porta a dove si ottiene (G37)
	ingr_l.visible = false
	right.add_child(ingr_l)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	right.add_child(mrow)
	var mastery_l := _label("", &"MutedLabel")
	mrow.add_child(mastery_l)
	var mbar := ProgressBar.new()
	mbar.show_percentage = false
	mbar.min_value = 0.0
	mbar.max_value = 1.0
	mbar.step = 0.0
	mbar.custom_minimum_size = Vector2(56, 8)
	mbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(mbar)
	var req_box := VBoxContainer.new()          # requisiti mancanti cliccabili (G37): vuoto quando non manca nulla
	req_box.add_theme_constant_override("separation", 0)
	req_box.custom_minimum_size = Vector2(0, 0)
	v.add_child(req_box)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_row_pressed.bind(aid))
	v.add_child(btn)
	var prog := SmoothBar.new()                 # avanzamento continuo del ciclo: solo sulla carta in esecuzione
	prog.name = "CardProgress"
	prog.custom_minimum_size = Vector2(0, 6)
	prog.visible = false
	v.add_child(prog)
	TutorialTargets.mark(btn, "action:" + aid)         # tutorial: il pulsante Avvia/Ferma di questa azione
	TutorialTargets.mark(right, "mastery:" + aid)       # tutorial: resa e Maestria dell'azione
	_rows[aid] = {"panel": panel, "name": name_l, "info": info, "ingr": ingr_l, "give": give_l, "yield": yield_l, "ingr_sig": "", "give_sig": "",
		"mastery_l": mastery_l, "mbar": mbar, "btn": btn, "locked": false, "req_box": req_box, "req_sig": "", "a": a,
		"prog": prog, "active": false}
	_fit_columns()


## Etichetta su una riga sola: un testo lungo si tronca con «…» invece di andare a capo e allargare la riga.
func _clip(l: Label) -> void:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.autowrap_mode = TextServer.AUTOWRAP_OFF


func _main_output(a: Dictionary) -> String:
	var outs: Array = a.get("outputs", [])
	if not outs.is_empty():
		return str(outs[0].item)
	var drops: Array = a.get("drops", [])
	return str(drops[0].item) if not drops.is_empty() else "gold"


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	if _sk == null:
		return
	_counter += 1
	_refresh_header()
	_refresh_active()
	var bank := Game.system("bank") as BankSystem
	_full_l.visible = bank != null and bank.is_full()
	var slow := _counter % ROWS_EVERY == 1 or _dirty
	if _dirty:
		_refresh_rows_static()
		_dirty = false
	_refresh_rows_live(slow)
	if _perks != null:
		_perks.refresh()
	if _extras != null:
		_extras.refresh()


func _mark_dirty() -> void:
	_dirty = true


func _on_locale(_l: String) -> void:
	if _sk != null:
		_build()
		_update_chip()
		refresh()


func _refresh_header() -> void:
	var lv := _sk.level(_skill_id)
	var cap := _sk.level_cap(_skill_id)
	_level_l.text = Loc.tf("UI_SKILLS_LEVEL_MAX" if lv >= cap else "UI_SKILLS_LEVEL", {"n": lv})
	var pr := _sk.xp_progress(_skill_id)
	var need := float(pr[1])
	var frac := 1.0 if need <= 0.0 else clampf(float(pr[0]) / need, 0.0, 1.0)
	_set_xp_bar(frac)
	_xp_l.text = "" if need <= 0.0 else Loc.tf("UI_SKILLS_XP", {"cur": NumberFormat.fmt(float(pr[0])), "need": NumberFormat.fmt(need)})
	_eta_l.text = ""
	var aid := _sk.current_action()
	if need > 0.0 and not aid.is_empty() and _sk.skill_of(aid) == _skill_id:
		var xph: float = float(_sk.hourly(aid).xp)
		if xph > 0.0:
			_eta_l.text = Loc.tf("UI_SKILLS_NEXT_LEVEL", {"time": NumberFormat.fmt_time((need - float(pr[0])) / xph * 3600.0)})
	_xp_l.tooltip_text = _eta_l.text
	_xp_bar.tooltip_text = _eta_l.text
	var tool_type := str(DataRegistry.get_def("skills", _skill_id).get("tool_type", ""))
	_tool_l.visible = not tool_type.is_empty()
	if _tool_l.visible:
		_tool_l.text = _tool_text()
		_tool_l.mouse_filter = Control.MOUSE_FILTER_STOP
		if not _tool_hint_ready:
			_tool_hint_ready = true
			_tool_hint_txt = _tool_hint()          # una volta sola per schermata: scorre tutte le azioni
		_tool_l.tooltip_text = _tool_hint_txt


## Dove si costruisce un attrezzo migliore per questa mansione (dai dati: azioni singole che producono un attrezzo suo).
## QA119: «Attrezzo: di base» non diceva come ottenerne uno migliore.
func _tool_hint() -> String:
	var makers := PackedStringArray()
	for aid in DataRegistry.all_actions():
		var a: Dictionary = DataRegistry.all_actions()[aid]
		if not bool(a.get("single_craft", false)):
			continue
		for o in a.get("outputs", []):
			var it: Dictionary = DataRegistry.item(str(o.get("item", "")))
			if str(it.get("category", "")) == "tool" and str(it.get("tool", {}).get("skill", "")) == _skill_id:
				var nm := ItemUse.skill_name(str(a.skill))
				if not makers.has(nm):
					makers.append(nm)
	if makers.is_empty():
		return ""
	return Loc.tf("UI_SKILLS_TOOL_HINT", {"where": ", ".join(makers)})


func _tool_text() -> String:
	var tools: Dictionary = GameState.data.get("equipment", {}).get("tools", {})
	var uid := str(tools.get(_skill_id, ""))
	var bank: Object = Game.system("bank")
	if not uid.is_empty() and bank != null:
		var inst: Dictionary = bank.get_instance(uid)
		var def: Dictionary = DataRegistry.item(str(inst.get("def", "")))
		if not def.is_empty():
			return Loc.tf("UI_SKILLS_TOOL", {"name": Loc.t(def.name)})
	return tr("UI_SKILLS_TOOL_BASE")


func _set_xp_bar(frac: float) -> void:
	if Settings.get_value("reduce_motion") or not is_inside_tree():
		_xp_bar.value = frac
		return
	if absf(_xp_bar.value - frac) < 0.0005:
		return
	if frac < _xp_bar.value:
		_xp_bar.value = frac               # nuovo livello: la barra riparte
		Fx.bar_flash(_xp_bar)              # ... e brilla d'oro un attimo
		return
	if _xp_tween != null and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_tween = create_tween()
	_xp_tween.tween_property(_xp_bar, "value", frac, 0.2)


func _refresh_active() -> void:
	var aid := _sk.current_action()
	var mine := not aid.is_empty() and _sk.skill_of(aid) == _skill_id
	_stop_btn.visible = mine
	_hdr.strip_dot.text = "●" if mine else "○"
	_active_icon.get_parent().visible = mine
	_active_bar.visible = mine
	_gain_l.visible = mine
	if not mine:
		_active_name.text = tr("UI_SKILLS_IDLE_STRIP")
		_active_info.text = ""
		_active_bar.set_target(0.0, 0.0)
		_sync_tool_anim("", 0.0, false)
		return
	_active_icon.modulate = Color.WHITE
	var a: Dictionary = DataRegistry.action(aid)
	_active_name.text = Loc.tf("UI_SKILLS_IN_PROGRESS", {"name": Loc.t(a.get("name", {}))})
	_active_icon.texture = IconLib.icon("items", _main_output(a))
	var dur := maxf(0.05, float(_sk.profile_of(aid).cycle_s))
	_sync_tool_anim(aid, dur, _sk.stun_remaining() > 0.0)
	if _sk.stun_remaining() > 0.0:
		_active_bar.set_target(0.0, 0.0)
		_active_info.text = Loc.tf("UI_SKILLS_STUNNED", {"time": NumberFormat.fmt_time(_sk.stun_remaining())})
	else:
		_active_bar.set_target(_sk.cycle_fraction(), 1.0 / dur)
		var arow: Dictionary = _rows.get(aid, {})
		if not arow.is_empty():
			(arow.prog as SmoothBar).set_target(_sk.cycle_fraction(), 1.0 / dur)       # avanzamento continuo in fondo alla carta
		_active_info.text = _row_info(aid)
	_active_info.tooltip_text = _active_info.text


func _refresh_rows_static() -> void:
	var lv := _sk.level(_skill_id)
	for a in _actions:
		var aid: String = a.id
		var row: Dictionary = _rows.get(aid, {})
		if row.is_empty():
			continue                 # riga non ancora costruita (costruzione a fette)
		var req := int(a.get("level_req", 1))
		row.locked = lv < req
		row.info.text = _row_sub(aid)
		var hr := _sk.hourly(aid)
		if bool(a.get("single_craft", false)):          # una costruzione per volta: niente «all'ora» (non si ripete da sola)
			row.yield.text = ""
		else:
			row.yield.text = _yield_text(hr)
		(row.yield as Control).visible = not (row.yield.text as String).is_empty()
		(row.yield as Control).tooltip_text = row.yield.text
		_update_amounts(aid, a)
		(row.panel as Control).tooltip_text = _row_tip(aid, a)
		(row.panel as Control).modulate = Color(1, 1, 1, 0.6) if row.locked else Color.WHITE
		_update_req_links(aid, a)
		_update_mastery(aid)
	_reorder_rows()
	_apply_filters()


## Ordine delle righe: «fattibili ora» in alto (sbloccate e con gli ingredienti), poi le sbloccate senza ingredienti, per livello;
## le bloccate vanno nel gruppo chiuso sotto. Si riordina solo quando cambia l'ordine (livello, modificatori), non a ogni
## variazione degli ingredienti: le righe non devono saltare sotto il cursore.
func _reorder_rows() -> void:
	var ok_rows: Array = []
	var other_rows: Array = []
	var locked_rows: Array = []
	for a in _actions:                               # _actions è già in ordine di livello per i dati; ordina per sicurezza
		var row: Dictionary = _rows.get(str(a.id), {})
		if row.is_empty():
			continue
		if row.locked:
			locked_rows.append(a)
		elif _sk.can_start(str(a.id)) == "":
			ok_rows.append(a)
		else:
			other_rows.append(a)
	var by_level := func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("level_req", 1)) < int(y.get("level_req", 1))
	ok_rows.sort_custom(by_level)
	other_rows.sort_custom(by_level)
	locked_rows.sort_custom(by_level)
	var ids := PackedStringArray()
	for a in ok_rows + other_rows:
		ids.append(str(a.id))
	ids.append("|")
	for a in locked_rows:
		ids.append(str(a.id))
	var sig := ",".join(ids)
	if sig == _order_sig:
		return
	_order_sig = sig
	var i := 0
	for a in ok_rows + other_rows:
		_place(_rows[str(a.id)].panel, _list, i)
		i += 1
	i = 0
	for a in locked_rows:
		_place(_rows[str(a.id)].panel, _locked_box, i)
		i += 1
	_locked_info = locked_rows.size()
	_next_locked = locked_rows[0] if not locked_rows.is_empty() else {}


func _place(node: Control, parent: Control, idx: int) -> void:
	if node.get_parent() != parent:
		node.get_parent().remove_child(node)
		parent.add_child(node)
	parent.move_child(node, idx)


## «▸ Bloccate (n) — la prossima: X al Liv N»: conta solo le bloccate che i filtri lasciano passare.
func _update_locked_group() -> void:
	if _locked_btn == null:
		return
	var n := 0
	var first: Dictionary = {}
	for a in _actions:
		var row: Dictionary = _rows.get(str(a.id), {})
		if not row.is_empty() and row.locked and (row.panel as Control).visible:
			n += 1
			if first.is_empty() or int(a.get("level_req", 1)) < int(first.get("level_req", 1)):
				first = a
	_locked_btn.visible = n > 0
	if n == 0:
		return
	var txt := Loc.tf("UI_SKILLS_LOCKED_GROUP", {"n": n, "name": Loc.t(first.get("name", {})), "lv": int(first.get("level_req", 1))})
	_locked_btn.text = (Disclosure.OPEN if _locked_open else Disclosure.CLOSED) + txt


## Testo del pulsante di avvio: per le costruzioni «una per volta» è «Costruisci», e «Costruisci un altro» se ne hai già una.
func _start_text(a: Dictionary) -> String:
	if not bool(a.get("single_craft", false)):
		return "UI_SKILLS_START"
	var bank: Object = Game.system("bank")
	for o in a.get("outputs", []):
		if bank != null and int(bank.count(str(o.get("item", "")))) > 0:
			return "UI_SKILLS_BUILD_ANOTHER"
	return "UI_SKILLS_BUILD"


## Riga sotto il nome: «2,0 s · 4 XP» più, se serve, «una per volta», successo, rischio di bruciare.
func _row_sub(aid: String) -> String:
	var p := _sk.profile_of(aid)
	var parts: PackedStringArray = [Loc.tf("UI_SKILLS_TIME_XP", {"time": NumberFormat.decimal(float(p.duration_s), 1, Loc.locale()) + tr("UI_TIME_S"), "xp": NumberFormat.fmt(float(p.xp))})]
	var a: Dictionary = DataRegistry.action(aid)
	if bool(a.get("single_craft", false)):
		parts.append(tr("UI_SKILLS_ONE_AT_A_TIME"))
	if a.has("success"):
		parts.append(Loc.tf("UI_SKILLS_SUCCESS", {"n": NumberFormat.fmt_pct(float(p.success) * 100.0)}))
	if float(p.burn) > 0.0:
		parts.append(Loc.tf("UI_SKILLS_BURN", {"n": NumberFormat.fmt_pct(float(p.burn) * 100.0)}))
	return " · ".join(parts)


## Come _row_sub, più le probabilità di qualità: sta nella striscia «In corso» e nel suggerimento della riga.
func _row_info(aid: String) -> String:
	var p := _sk.profile_of(aid)
	var out := _row_sub(aid)
	var qt := _quality_text(p)
	if not qt.is_empty():
		out += " · " + qt
	return out


func _quality_text(p: Dictionary) -> String:
	var q: Array = p.quality
	if q.is_empty():
		return ""
	return Loc.tf("UI_SKILLS_QUALITY", {"a": NumberFormat.fmt_pct(float(q[0]) * 100.0), "b": NumberFormat.fmt_pct(float(q[1]) * 100.0),
		"c": NumberFormat.fmt_pct(float(q[2]) * 100.0), "d": NumberFormat.fmt_pct(float(q[3]) * 100.0)})


## Suggerimento della riga: i DETTAGLI in più rispetto alla carta (resa e ingredienti stanno già in vista): frasi complete di
## quanto manca, ritrovamenti rari con la probabilità e probabilità di qualità.
func _row_tip(aid: String, a: Dictionary) -> String:
	var lines := PackedStringArray()
	var miss := ReqText.missing_inputs_text(a.get("inputs", []))
	if not miss.is_empty():
		lines.append(miss)
	var ing := ReqText.inputs_text(a.get("inputs", []))
	if not ing.is_empty():
		lines.append(ing)
	var rare := _rare_text(a)
	if not rare.is_empty():
		lines.append(rare)
	var qt := _quality_text(_sk.profile_of(aid))
	if not qt.is_empty():
		lines.append(qt)
	return "\n".join(lines)


## Ritrovamenti rari e altri premi dell'azione con la probabilità («Può dare anche: Nido (0,5%)»): solo nel suggerimento.
func _rare_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	for sec in a.get("secondary", []) + a.get("drops", []):
		if sec.has("item"):
			parts.append("%s (%s)" % [ReqText.item_name(str(sec.item)), NumberFormat.fmt_pct(float(sec.get("chance", 0.0)) * 100.0)])
		elif sec.has("pick"):
			for pk in sec.pick:
				parts.append(ReqText.item_name(str(pk.item)))
	return Loc.tf("UI_MSK_ALSO", {"list": ", ".join(parts)}) if not parts.is_empty() else ""


## «Dà: 1–3 Tronco di Pino (ne hai 53)»: ciò che dà UNA azione (quantità dai dati, oro compreso) e quanto ne hai del prodotto.
func _give_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	for o in a.get("outputs", []):
		var id := str(o.get("item", ""))
		parts.append(Loc.tf("UI_MSK_GIVE_ITEM", {"qty": ReqText.qty_text(o.get("qty", 1)), "item": ReqText.item_name(id),
			"have": NumberFormat.fmt(float(ReqText.owned(id)))}))
	if a.has("gold"):
		parts.append(Loc.tf("UI_SKILLS_GOLD_PER_HOUR", {"n": ReqText.qty_text(a.gold)}))
	if parts.is_empty():
		return ""
	return Loc.tf("UI_MSK_GIVES", {"list": ", ".join(parts)})


## «Ogni ora: ~1.206 · 8.400 XP» (il nome del prodotto sta già nella riga «Dà»).
func _yield_text(hr: Dictionary) -> String:
	var parts: PackedStringArray = []
	var items: Dictionary = hr.items
	for k in items:
		parts.append(NumberFormat.fmt(float(items[k])))
		break
	if float(hr.gold) > 0.0:
		parts.append(Loc.tf("UI_SKILLS_GOLD_PER_HOUR", {"n": NumberFormat.fmt(float(hr.gold))}))
	parts.append(Loc.tf("UI_MSK_XP", {"n": NumberFormat.fmt(float(hr.xp))}))
	return Loc.tf("UI_MSK_PER_HOUR", {"list": " · ".join(parts)})


## Aggiorna le quantità della carta (cambiano col Deposito): «Dà …(ne hai N)» e «Servono … (hai M)». Si riscrive solo se il testo cambia.
func _update_amounts(aid: String, a: Dictionary) -> void:
	var row: Dictionary = _rows.get(aid, {})
	if row.is_empty():
		return
	var give := _give_text(a)
	if give != str(row.give_sig):
		row.give_sig = give
		(row.give as Label).text = give
		(row.give as Control).visible = not give.is_empty()
	var ingr: RichTextLabel = row.ingr
	var inputs: Array = a.get("inputs", [])
	var bb := ReqText.inputs_text(inputs, true, true)
	if bb != str(row.ingr_sig):
		row.ingr_sig = bb
		ingr.text = bb
		ingr.visible = not bb.is_empty()
		ingr.tooltip_text = ReqText.missing_inputs_text(inputs)


func _update_mastery(aid: String) -> void:
	var row: Dictionary = _rows.get(aid, {})
	if row.is_empty():
		return
	var ml := _sk.mastery_level(aid)
	var cap := _sk.mastery_cap()
	row.mastery_l.text = Loc.tf("UI_SKILLS_MASTERY_MAX" if ml >= cap else "UI_SKILLS_MASTERY", {"n": ml})
	var pr := _sk.mastery_progress(aid)
	(row.mbar as ProgressBar).value = 1.0 if float(pr[1]) <= 0.0 else clampf(float(pr[0]) / float(pr[1]), 0.0, 1.0)
	if _last_mastery.has(aid) and ml > int(_last_mastery[aid]):
		_pulse(row.mastery_l)
		var mc := Fx.center_of(row.mastery_l as Control)
		Fx.ring(mc, FxPalette.VIOLET, 50.0, 0.5, FxPalette.WHITE, 1)
		Fx.burst("glint", mc, [FxPalette.VIOLET, FxPalette.WHITE, FxPalette.GOLD], 1.0, 1.2, Vector2(30, 8), 1)
	_last_mastery[aid] = ml


func _refresh_rows_live(slow: bool) -> void:
	var active := _sk.current_action()
	for a in _actions:
		var aid: String = a.id
		var row: Dictionary = _rows.get(aid, {})
		if row.is_empty():
			continue
		var btn: Button = row.btn
		btn.text = "UI_SKILLS_STOP" if aid == active else _start_text(a)
		btn.disabled = row.locked
		var is_active: bool = aid == active
		if is_active != bool(row.get("active", false)):
			row["active"] = is_active
			(row.panel as PanelContainer).add_theme_stylebox_override("panel", _row_style(is_active))
			(row.prog as Control).visible = is_active
			if is_active:                           # «Ferma» si distingue da «Avvia»: testo di avviso (rosso chiaro)
				btn.add_theme_color_override("font_color", FxPalette.RED_L)
			else:
				btn.remove_theme_color_override("font_color")
		if aid == active:
			_update_mastery(aid)
			if _sk.mastery_level(aid) != int(row.get("ml", -1)):
				row["ml"] = _sk.mastery_level(aid)
				_dirty = true                # il livello di maestria cambia velocità e resa: ricalcola
	if slow:
		for a in _actions:
			var aid2: String = a.id
			var row2: Dictionary = _rows.get(aid2, {})
			if row2.is_empty():
				continue
			if (row2.panel as Control).visible:
				_update_amounts(aid2, a)                                       # «ne hai N» / «hai M» cambiano col Deposito
			if a.has("inputs"):
				(row2.panel as Control).tooltip_text = _row_tip(aid2, a)
		if _only.button_pressed:
			_apply_filters()


func _apply_filters() -> void:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	for a in _actions:
		var aid: String = a.id
		var row: Dictionary = _rows.get(aid, {})
		if row.is_empty():
			continue
		var keep := true
		if not _filter_cat.is_empty() and str(a.get("category", "")) != _filter_cat:
			keep = false
		if keep and not q.is_empty() and not Loc.t(a.get("name", {})).to_lower().contains(q):
			keep = false
		if keep and _only != null and _only.button_pressed and not row.locked and _sk.can_start(aid) != "":      # le bloccate stanno nel gruppo chiuso
			keep = false
		if keep and not _produces.is_empty() and not _outputs_item(a, _produces):
			keep = false
		if keep and _avail_only and row.locked:
			keep = false
		(row.panel as Control).visible = keep
	_update_empty_hint()
	_update_locked_group()


func _update_empty_hint() -> void:
	if _empty_l == null:
		return
	var any_unlocked := false
	var any_visible := false
	for a in _actions:
		var row: Dictionary = _rows.get(str(a.id), {})
		if row.is_empty() or row.locked:
			continue
		any_unlocked = true
		any_visible = any_visible or (row.panel as Control).visible
	_empty_l.visible = any_unlocked and not any_visible and _only != null and _only.button_pressed


func _outputs_item(a: Dictionary, item_id: String) -> bool:
	return QuestGuide.action_yields(a, item_id)      # prodotto o ritrovamento raro (es. Quarzo Grezzo nella Miniera)


## Requisito di livello mancante come testo cliccabile (G37): «Richiede livello 30 (il tuo: 25)» porta alle azioni che si possono già
## fare. Gli ingredienti che non bastano stanno nella riga «Servono…» (ambra e cliccabili verso dove si ottengono, vedi _update_amounts).
## Si ricostruisce solo se cambia il testo.
func _update_req_links(aid: String, a: Dictionary) -> void:
	var row: Dictionary = _rows.get(aid, {})
	if row.is_empty():
		return
	var cur := _sk.level(_skill_id)
	var sig := "L%d,%d" % [int(a.get("level_req", 1)), cur] if row.locked else "-"
	if sig == row.req_sig:
		return
	row.req_sig = sig
	var box: VBoxContainer = row.req_box
	box.custom_minimum_size.x = 0.0
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if row.locked:
		var txt := ReqText.level_text(int(a.get("level_req", 1)), cur)
		var lk := ReqLink.link(txt, ReqLink.target_for_level(_skill_id))
		lk.tooltip_text = ReqText.level_sentence(Loc.t(DataRegistry.get_def("skills", _skill_id).get("name", {})), int(a.get("level_req", 1)), cur)
		box.add_child(_red(lk))


## Requisito mancante: rosso come negli altri avvisi (resta cliccabile).
func _red(c: Control) -> Control:
	if c is Button:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			c.add_theme_color_override(k, MISSING)
		c.add_theme_font_size_override("font_size", 14)
		(c as Button).clip_text = true                          # un requisito lungo non allarga la carta (il testo intero è nel suggerimento)
		(c as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		(c as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:      # senza margini: due requisiti stanno nella riga da 56 px
			var e := StyleBoxEmpty.new()
			e.content_margin_top = 1
			e.content_margin_bottom = 1
			c.add_theme_stylebox_override(st, e)
	elif c is Label:
		c.add_theme_color_override("font_color", MISSING)
		(c as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # a capo: non allarga la carta
		(c as Label).custom_minimum_size.x = 80
	return c


func _update_chip() -> void:
	_chip.visible = not _produces.is_empty() or _avail_only
	if not _produces.is_empty():
		_chip_l.text = Loc.tf("UI_UIB_FILTER_PRODUCES", {"item": Loc.t(DataRegistry.item(_produces).get("name", _produces))})
	elif _avail_only:
		_chip_l.text = tr("UI_UIB_FILTER_AVAILABLE")


func _clear_req_filter() -> void:
	_produces = ""
	_avail_only = false
	_update_chip()
	_apply_filters()


## Motivo del rifiuto con le quantità: «Ti mancano 12 Lino: ne servono 60, ne hai 48» / «Serve il livello 30 in Taglialegna: il tuo è 25».
func _refusal_text(aid: String, reason: String) -> String:
	var a: Dictionary = DataRegistry.action(aid)
	if reason == "UI_SKILLS_REASON_MATERIALS":
		var t := ReqText.missing_inputs_text(a.get("inputs", []))
		if not t.is_empty():
			return t.replace("\n", " ")
	elif reason == "UI_SKILLS_REASON_LEVEL":
		return ReqText.level_sentence(Loc.t(DataRegistry.get_def("skills", _skill_id).get("name", {})), int(a.get("level_req", 1)), _sk.level(_skill_id))
	return tr(reason)


func _on_row_pressed(aid: String) -> void:
	if _sk.current_action() == aid:
		_sk.stop()
	elif not _sk.start(aid):
		var reason := _sk.can_start(aid)
		if not reason.is_empty():
			EventBus.notice.emit("warning", _refusal_text(aid, reason), {})
	refresh()


# ------------------------------------------------------------------ effetti di soddisfazione

## Riquadro che CONTIENE un'icona animata: margine di FX_PAD px attorno e `clip_contents`, così ciò che si muove (dondolio
## dell'attrezzo, schiacciamento della risorsa) non esce mai dal proprio posto né tocca il testo vicino (rapporto 104).
func _clip_box(icon: TextureRect, side: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(side + 2.0 * FX_PAD, side + 2.0 * FX_PAD)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(FX_PAD))
	return box


func _on_action_completed(action_id: String, outputs: Array) -> void:
	if _sk == null or _sk.skill_of(action_id) != _skill_id or not is_inside_tree():
		return
	var animated := _anim_aid == action_id and Fx.enabled()
	if animated:                                     # l'attrezzo colpisce, il bersaglio incassa; poi un nuovo ciclo
		Fx.tool_strike(_icon, _active_icon, _skill_id)
		Fx.tool_start(_icon, _active_icon, _skill_id, _anim_dur, 0.0)
	var text := ""
	var qty := 0
	for o in outputs:
		if int(o.get("qty", 0)) > 0:
			qty = int(o.qty)
			var item := str(o.item)
			var nm := tr("UI_SKILLS_GOLD") if item == "gold" else Loc.t(DataRegistry.item(item).get("name", item))
			text = Loc.tf("UI_SKILLS_GAIN", {"n": int(o.qty), "item": nm})
			break
	if text.is_empty():
		return
	_gain_l.text = text
	_fx_action(outputs)
	if Settings.get_value("reduce_motion"):
		return
	# un solo «+N» breve sopra la risorsa (il testo completo sta già nella riga «+1 Tronco»): niente testi sovrapposti
	_floater("+" + NumberFormat.fmt(qty), GOLD, 16, Fx.center_of(_active_icon) + Vector2(0.0, -ICON_SIZE.y * 0.5 - 14.0))
	if not animated:
		_pulse(_active_icon)


func _on_level_up(skill: String, level: int) -> void:
	if skill != _skill_id or not is_inside_tree():
		return
	_dirty = true
	if Settings.get_value("reduce_motion"):
		return
	_floater(Loc.tf("UI_SKILLS_LEVEL_UP_FX", {"n": level}), GOLD, 26)
	var hc := Fx.center_of(_head_panel)
	Fx.ring(hc, GOLD, 120.0, 0.7, Color.WHITE, 2)
	Fx.burst("star", hc, [], 1.2, 1.2, Vector2(_head_panel.size.x * 0.3, 8.0), 2)
	var tw := create_tween()
	_head_panel.modulate = FLASH
	tw.tween_property(_head_panel, "modulate", Color.WHITE, 0.8)


## Tiene allineato il ciclo dell'attrezzo con l'azione in corso: parte (a metà ciclo se serve) al cambio di azione o di
## durata, si ferma se l'azione non è più questa mansione o il personaggio è stordito. Il colpo vero lo dà il completamento.
func _sync_tool_anim(aid: String, dur: float, stunned: bool) -> void:
	if aid.is_empty() or stunned or not Fx.enabled():
		if not _anim_aid.is_empty() or Fx.enabled() == false:
			Fx.tool_stop(_icon, _active_icon)
		_anim_aid = ""
		return
	if aid == _anim_aid and absf(dur - _anim_dur) < 0.01:
		return
	_anim_aid = aid
	_anim_dur = dur
	Fx.tool_start(_icon, _active_icon, _skill_id, dur, clampf(_sk.cycle_fraction(), 0.0, 1.0) * dur)


## Completamento di un'azione: particelle tematiche della mansione sull'icona attiva, barra che brilla (SmoothBar) e il
## primo oggetto prodotto che vola, con scia, verso la voce Deposito del menù.
func _fx_action(outputs: Array) -> void:
	if _active_icon == null or not _active_icon.is_inside_tree() or not Fx.enabled():
		return
	var c := Fx.center_of(_active_icon)
	Fx.job(_skill_id, c, 0.6)                 # particelle piccole e vicine: restano attorno alla risorsa
	for o in outputs:
		var item := str(o.get("item", ""))
		if int(o.get("qty", 0)) > 0 and item != "gold" and not item.is_empty():
			Fx.fly(IconLib.icon("items", item), c, Fx.anchor_pos("bank", c + Vector2(-260, -40)), 0.75, GOLD, "glint",
				Fx.anchor_node("bank"), 0.05, 20.0)
			break


## "+1 Tronco" che sale e svanisce. top_level: i container non lo spostano.
func _floater(text: String, color: Color, font_px: int, at: Vector2 = Vector2.INF) -> void:
	if _fx_count >= FX_MAX:
		return
	_fx_count += 1
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.top_level = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", font_px)
	add_child(l)
	var base := _active_bar.global_position + Vector2(randf_range(0.0, maxf(8.0, _active_bar.size.x * 0.5)), -8.0)
	if at != Vector2.INF:
		base = at - Vector2(l.get_combined_minimum_size().x * 0.5, 0.0)      # centrato sul punto
	l.global_position = base
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", base.y - FX_RISE, 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(func() -> void:
		_fx_count = maxi(0, _fx_count - 1)
		l.queue_free())


func _pulse(node: Control) -> void:
	if Settings.get_value("reduce_motion") or node == null or not is_inside_tree():
		return
	node.pivot_offset = node.size / 2.0
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.18, 1.18), 0.07)
	tw.tween_property(node, "scale", Vector2.ONE, 0.11)
