extends GameScreen
## Sala dei Caveau (docs/16 §3.4, docs/09): le casse possedute, contenuto e PROBABILITÀ sempre visibili,
## apri ×1/×5/×10, Apertura rapida, Salta. Presentazione soltanto: l'estrazione avviene in CrateSystem.open()
## PRIMA di qualunque animazione; qui si mostra il risultato già deciso (CLAUDE.md regola 5, docs/24).

const CELL := Vector2(124, 138)
const LIST_W := 214.0                   # larghezza dell'elenco a sinistra
const CHEST_PX := 160.0                 # 5× il PNG da 32 px (scala intera)
const STAGE_MIN_H := 360.0
const COMPACT_H := 700.0                # sotto questa altezza «Apri» sale subito sotto il nome (resta tutto visibile senza scorrere)
const PREROLL_S := 0.42                 # la cassa trema (scena prima del rullo); apertura rapida: la metà

static var quick_open: bool = false     # ricordata per la sessione (non è uno stato di gioco)
static var _contents_open: int = -1     # «Contenuto completo»: -1 = da decidere (aperto alla prima visita), 0 chiuso, 1 aperto

var _crates: CrateSystem
var _selected: String = ""
var _signature: String = ""
var _busy: bool = false
var _results: Array = []

var _list: VBoxContainer
var _detail: VBoxContainer
var _left: ScrollContainer
var _carro: CarroPanel
var _open_panel: PanelContainer
var _reel: CrateReel
var _reel_box: VBoxContainer
var _skip_btn: Button
var _result_label: Label
var _result_extra: Label
var _multi: CrateMultiReveal
var _actions: CrateActions
var _rside: VBoxContainer                # colonna a destra della carta (azioni in colonna)
var _multi_host: VBoxContainer           # ×5/×10: stesse azioni, in fila, sotto la griglia
var _split: HBoxContainer
var _result_row: HBoxContainer
var _card: CrateResultCard
var _glow: ChestPedestal
var _again_btn: Button
var _stage_odds: Label
var _pick_label: Label
var _bulk_btn: Button
var _close_btn: Button
var _open_btns: Array[Button] = []
var _quick_check: CheckBox
var _stage: Control                    # velo a tutto pannello che ospita la cassa che trema (solo scena)
var _chest: TextureRect
var _preroll_on: bool = false
var _compact_built: bool = false


func open(params: Dictionary) -> void:
	_crates = CrateUi.crates()
	_selected = str(params.get("crate", _selected))
	_build()
	_rebuild(true)
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


## Layout compatto: se la finestra cambia altezza oltre la soglia si ricostruisce il dettaglio (mai durante l'apertura).
func _on_resized() -> void:
	if _crates != null and not _busy and _detail != null and is_compact() != _compact_built:
		_build_detail()


## Finestra bassa (1024×576): «Apri» deve restare raggiungibile senza scorrere.
func is_compact() -> bool:
	return is_inside_tree() and get_viewport_rect().size.y < COMPACT_H


func close() -> void:
	_preroll_on = false
	if _reel != null:
		_reel.stop()
	if _multi != null:
		_multi.stop()


func refresh() -> void:
	if _crates == null or _busy:
		return
	_rebuild(false)


func _unhandled_input(event: InputEvent) -> void:
	if _busy and event is InputEventKey and InputBindings.pressed(event, "reel"):
		_on_skip()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ costruzione

func _build() -> void:
	for c in get_children():
		c.queue_free()
	VaultHead.header(self, "hall", "UI_MENU_VAULT_HALL", "UI_CRATES_SUBTITLE")
	VaultHead.hall_tabs(self, "hall")
	_carro = CarroPanel.new()                  # Deposito pieno / Carro di Ritiro non vuoto: il premio non si perde, e cosa fare
	_carro.changed.connect(func() -> void: _rebuild(true))
	add_child(_carro)

	# SCENA di apertura: sostituisce elenco e dettaglio finché dura (Salta sempre visibile). Prima la cassa grande che
	# trema, poi il rullo a tutta larghezza, poi UNA carta-risultato con le azioni a destra. Le probabilità restano in vista.
	_open_panel = PanelContainer.new()
	_open_panel.name = "OpenStage"
	_open_panel.visible = false
	_open_panel.custom_minimum_size = Vector2(0, STAGE_MIN_H)
	_open_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_open_panel)
	var shell := VBoxContainer.new()               # scena scorrevole (finestre basse, ×10) + probabilità sempre ancorate in fondo
	shell.add_theme_constant_override("separation", 6)
	_open_panel.add_child(shell)
	var sc_ov := ScrollContainer.new()
	sc_ov.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc_ov.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(sc_ov)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc_ov.add_child(ov)
	_reel_box = VBoxContainer.new()
	ov.add_child(_reel_box)
	_reel = CrateReel.new()
	_reel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reel.finished.connect(_on_reel_finished)
	_reel.tick_sound.connect(_on_tick_sound)
	_reel.reveal_sound.connect(_on_reveal_sound)
	AudioManager.hook_reel(_reel)
	_reel_box.add_child(_reel)
	_skip_btn = Button.new()
	_skip_btn.text = tr("UI_CRATES_SKIP")
	_skip_btn.custom_minimum_size = Vector2(0, 40)
	_skip_btn.pressed.connect(_on_skip)
	ov.add_child(_skip_btn)
	_result_row = HBoxContainer.new()
	_result_row.name = "ResultRow"
	_result_row.add_theme_constant_override("separation", 24)
	_result_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_row.visible = false
	ov.add_child(_result_row)
	_card = CrateResultCard.new()
	_card.name = "ResultCard"
	_result_row.add_child(_card)
	var rside := VBoxContainer.new()
	_rside = rside
	rside.add_theme_constant_override("separation", 8)
	rside.custom_minimum_size = Vector2(340, 0)
	rside.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rside.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_result_row.add_child(rside)
	_result_label = Label.new()
	_result_label.theme_type_variation = &"SectionLabel"
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rside.add_child(_result_label)
	_result_extra = Label.new()
	_result_extra.theme_type_variation = &"MutedLabel"
	_result_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rside.add_child(_result_extra)
	_actions = CrateActions.new()
	_actions.column = true
	_actions.changed.connect(_on_actions_changed)
	rside.add_child(_actions)
	_multi = CrateMultiReveal.new()
	_multi.visible = false
	_multi.finished.connect(_on_multi_finished)
	_multi.selected.connect(_on_multi_selected)
	AudioManager.hook_reel(_multi)
	ov.add_child(_multi)
	_pick_label = Label.new()
	_pick_label.theme_type_variation = &"MutedLabel"
	_pick_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(_pick_label)
	_multi_host = VBoxContainer.new()
	_multi_host.name = "MultiActions"
	ov.add_child(_multi_host)
	var row := HFlowContainer.new()
	row.name = "StageButtons"
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	ov.add_child(row)
	_bulk_btn = Button.new()
	_bulk_btn.custom_minimum_size = Vector2(0, 40)
	_bulk_btn.pressed.connect(_on_bulk_fuse)
	row.add_child(_bulk_btn)
	_again_btn = Button.new()
	_again_btn.name = "OpenAgain"
	_again_btn.custom_minimum_size = Vector2(0, 40)
	_again_btn.pressed.connect(_on_again)
	row.add_child(_again_btn)
	_close_btn = Button.new()
	_close_btn.name = "CloseStage"
	_close_btn.text = tr("UI_CRATES_CLOSE")
	_close_btn.custom_minimum_size = Vector2(0, 40)
	_close_btn.pressed.connect(_on_close_panel)
	row.add_child(_close_btn)
	# le probabilità della cassa restano scritte sotto la scena (regola 5: sempre visibili, anche durante l'apertura)
	_stage_odds = Label.new()
	_stage_odds.name = "StageOdds"
	_stage_odds.theme_type_variation = &"MutedLabel"
	_stage_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage_odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_odds.size_flags_vertical = Control.SIZE_SHRINK_END
	shell.add_child(_stage_odds)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open_panel.add_child(_stage)
	_glow = ChestPedestal.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_glow.offset_left = -ChestPedestal.PEDESTAL_SIZE.x * 0.5
	_glow.offset_right = ChestPedestal.PEDESTAL_SIZE.x * 0.5
	_glow.offset_top = -ChestPedestal.PEDESTAL_SIZE.y * 0.5 - 20.0
	_glow.offset_bottom = ChestPedestal.PEDESTAL_SIZE.y * 0.5 - 20.0
	_glow.visible = false
	_stage.add_child(_glow)
	_chest = TextureRect.new()
	_chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chest.custom_minimum_size = Vector2(CHEST_PX, CHEST_PX)
	_chest.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_chest.offset_left = -CHEST_PX * 0.5
	_chest.offset_right = CHEST_PX * 0.5
	_chest.offset_top = -CHEST_PX * 0.5 - 28.0
	_chest.offset_bottom = CHEST_PX * 0.5 - 28.0
	_chest.visible = false
	_stage.add_child(_chest)

	var split := HBoxContainer.new()
	_split = split
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_left = ScrollContainer.new()
	_left.custom_minimum_size = Vector2(LIST_W, 0)
	_left.size_flags_stretch_ratio = 1.0
	_left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_left)
	_list = VBoxContainer.new()
	_list.name = "CrateCards"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_left.add_child(_list)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 3.0
	right.custom_minimum_size = Vector2(300, 0)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	right.add_child(_detail)

	# avviso legale in UNA riga (il testo completo, docs/24, è nel tooltip): sempre visibile sotto il pannello
	var legal := Label.new()
	legal.name = "LegalLine"
	legal.text = "ⓘ " + tr("UI_F11_LEGAL_SHORT")
	legal.tooltip_text = tr("UI_CRATES_LEGAL")
	legal.mouse_filter = Control.MOUSE_FILTER_STOP
	legal.theme_type_variation = &"MutedLabel"
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(legal)


# ------------------------------------------------------------------ elenco e dettaglio

func _owned_crates() -> Array:
	var out: Array = []
	var bank := CrateUi.bank()
	if bank == null:
		return out
	for it in DataRegistry.items_by_category("crate"):
		var n: int = bank.count(it.id)
		if n > 0:
			out.append({"id": it.id, "n": n})
	return out


func _signature_now(owned: Array) -> String:
	var parts := PackedStringArray([_selected])
	var bank := CrateUi.bank()
	for o in owned:
		parts.append("%s=%d:%d" % [o.id, o.n, _crates.openable_now(str(o.id))])
		var key: Variant = _crates.crate_def(o.id).get("key")
		if key != null and bank != null:
			parts.append("k%s=%d" % [key, bank.count(str(key))])
		var fam := _crates.pity_family(o.id)
		if not fam.is_empty():
			parts.append("p%d" % int(_crates.state.pity.get(fam, 0)))
	return "|".join(parts)


func _rebuild(force: bool) -> void:
	if _crates == null:
		return
	var owned := _owned_crates()
	if _selected.is_empty() or not _selected_exists(owned):
		_selected = str(owned[0].id) if not owned.is_empty() else ""
	var sig := _signature_now(owned)
	if sig == _signature and not force:
		return
	_signature = sig
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_left.visible = not owned.is_empty()
	for o in owned:
		_list.add_child(_crate_card(o))
	_build_detail()


func _selected_exists(owned: Array) -> bool:
	for o in owned:
		if o.id == _selected:
			return true
	return false


## Riga dell'elenco: icona, nome, quantità e stato della chiave (pronta / manca la chiave). Un solo clic la sceglie.
func _crate_card(o: Dictionary) -> Control:
	var cid: String = o.id
	var sel := cid == _selected
	var p := PanelContainer.new()                  # riga compatta: 32 px d'icona + 3 px di margine (24 casse stanno in ~2 pagine)
	p.add_theme_stylebox_override("panel", VaultKit.style(VaultKit.CARD_BG_SEL if sel else VaultKit.CARD_BG,
		VaultKit.GOLD_BORDER if sel else FxPalette.darken(VaultKit.crate_accent(cid), 0.3), 2 if sel else 1, 3))
	p.name = "CrateCard_" + cid
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := VaultKit.pix(CrateUi.def_icon(cid), 1)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := Label.new()
	n.text = CrateUi.def_name(cid)
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var st := Label.new()
	st.add_theme_font_size_override("font_size", UiType.NOTE)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _crates.openable_now(cid) >= 1:
		st.text = tr("UI_VUX_CARD_READY")
		st.add_theme_color_override("font_color", FxPalette.GREEN)
	else:
		st.text = tr("UI_VUX_CARD_NEED_KEY")
		st.add_theme_color_override("font_color", FxPalette.AMBER)           # «manca la chiave»: attenzione, non pericolo
	v.add_child(st)
	var q := Label.new()
	q.text = "×" + NumberFormat.fmt(o.n)
	q.theme_type_variation = &"NumberLabel"
	q.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	q.add_theme_color_override("font_color", FxPalette.GOLD)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(q)
	VaultKit.make_clickable(p, func() -> void:
		_selected = cid
		_rebuild(true), CrateUi.def_name(cid))
	return p


## Perché non si apre: UN motivo e UN «Vai» (il più utile), niente vicolo cieco.
func _missing_box(_cid: String, cdef: Dictionary) -> void:
	var bank := CrateUi.bank()
	var box := PanelContainer.new()
	box.name = "WhyDisabled"
	box.add_theme_stylebox_override("panel", VaultKit.style(Color("2a2416"), FxPalette.AMBER, 1, 6))
	_detail.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var gos := HFlowContainer.new()
	if cdef.get("key") != null:
		var kid := str(cdef.key)
		VaultKit.label(v, Loc.tf("UI_VUX_NEED_KEY", {"key": CrateUi.def_name(kid), "n": NumberFormat.fmt(bank.count(kid) if bank != null else 0)}), false, 0, FxPalette.AMBER)
		var src := ReqLink.target_for_item(kid)
		if not src.is_empty():
			_go_btn(gos, tr("UI_VUX_WHERE_KEY"), src, true)
		else:
			_go_btn_if(gos, "shop", "UI_MENU_SHOP", {}, true)
		if gos.get_child_count() == 0:
			_go_btn_if(gos, "quests", "UI_MENU_QUESTS", {}, true)
	elif cdef.has("open_cost"):
		var it := str(cdef.open_cost.item)
		VaultKit.label(v, Loc.tf("UI_VUX_NEED_COST", {"c": int(cdef.open_cost.qty), "item": CrateUi.def_name(it),
			"n": NumberFormat.fmt(bank.count(it) if bank != null else 0)}), false, 0, FxPalette.AMBER)
		_go_btn_if(gos, "events", "UI_MENU_EVENTS", {}, true)
	else:
		VaultKit.label(v, tr("UI_CRATES_NEED_KEY"), false, 0, FxPalette.AMBER)
	if gos.get_child_count() > 0:
		v.add_child(gos)
	else:
		gos.queue_free()


func _go_btn(parent: Control, to_text: String, target: Dictionary, primary: bool) -> void:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = Loc.tf("UI_VUX_GO", {"to": to_text})
	if primary:
		b.theme_type_variation = &"AccentButton"
	b.pressed.connect(ReqLink.go.bind(target))
	parent.add_child(b)


func _go_btn_if(parent: Control, screen_id: String, title_key: String, params: Dictionary, primary: bool) -> void:
	var e := ScreenRegistry.get_entry(screen_id)
	if e.is_empty() or not ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		return
	_go_btn(parent, tr(title_key), {"screen": screen_id, "params": params, "hint": ""}, primary)


func _build_detail() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)               # subito (non solo queue_free): i nomi dei nuovi nodi non vengono rinominati
		c.queue_free()
	_open_btns.clear()
	VaultKit.fade_in(_detail)
	if _selected.is_empty():
		_build_empty()
		return
	var cdef := _crates.crate_def(_selected)
	var bank := CrateUi.bank()
	var accent := VaultKit.crate_accent(_selected)

	# --- scena della Sala: la CASSA GRANDE (5× il PNG) su piedistallo con alone, e a destra nome, probabilità e «Apri»
	var stage := HBoxContainer.new()
	stage.name = "HallStage"
	stage.add_theme_constant_override("separation", 18)
	_detail.add_child(stage)
	stage.add_child(ChestPedestal.new().setup(CrateUi.def_icon(_selected), accent))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 6)
	stage.add_child(tv)
	var head := Label.new()
	head.text = CrateUi.def_name(_selected)
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.name = "CrateName"
	head.theme_type_variation = &"SectionLabel"
	head.add_theme_font_size_override("font_size", UiType.PAGE)
	head.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.45))
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(head)
	var have: int = bank.count(_selected) if bank != null else 0
	var line := Loc.tf("UI_CRATES_HAVE", {"n": NumberFormat.fmt(have)})
	if cdef.get("key") != null:
		line += " · " + Loc.tf("UI_CRATES_KEY_HAVE", {"key": CrateUi.def_name(str(cdef.key)),
			"n": NumberFormat.fmt(bank.count(str(cdef.key)) if bank != null else 0)})
	elif cdef.has("open_cost"):
		line += " · " + Loc.tf("UI_CRATES_COST_HAVE", {"item": CrateUi.def_name(str(cdef.open_cost.item)),
			"c": int(cdef.open_cost.qty), "n": NumberFormat.fmt(bank.count(str(cdef.open_cost.item)) if bank != null else 0)})
	else:
		line += " · " + tr("UI_CRATES_NO_KEY")
	var info := Label.new()
	info.name = "CrateInfo"
	info.text = line
	info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(info)

	# --- PROBABILITÀ (regola 5): SEMPRE visibili, subito sotto il nome, senza alcun clic. Barra + legenda con simbolo e
	# nome (mai solo colore) + pity. Mai dentro un Disclosure, mai sotto un pulsante: nessuna schermata le nasconde.
	var odds_box := VBoxContainer.new()
	odds_box.name = "OddsBox"
	odds_box.add_theme_constant_override("separation", 4)
	tv.add_child(odds_box)
	var rows := _crates.odds(_selected)
	var oh := Label.new()
	oh.text = tr("UI_CRATES_ODDS")
	oh.theme_type_variation = &"SectionLabel"
	odds_box.add_child(oh)
	odds_box.add_child(VaultKit.odds_bar(rows))
	var legend := HFlowContainer.new()
	legend.name = "OddsLegend"
	legend.add_theme_constant_override("h_separation", 14)
	legend.add_theme_constant_override("v_separation", 0)
	odds_box.add_child(legend)
	for r in rows:
		var l := Label.new()
		l.text = "%s   %s" % [CrateUi.rarity_label(str(r.rarity)), CrateUi.pct(float(r.pct))]
		l.add_theme_color_override("font_color", CrateUi.rarity_color(str(r.rarity)))
		legend.add_child(l)
	var pity := _crates.pity_info(_selected)
	var pl := Label.new()
	pl.name = "PityLine"
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pl.theme_type_variation = &"MutedLabel"
	if str(pity.family) != "":
		pl.text = Loc.tf("UI_CRATES_PITY", {"nom": CrateUi.pct(float(pity.nominal_relic_pct)),
			"eff": CrateUi.pct(float(pity.effective_relic_pct)), "mean": int(round(float(pity.mean_openings)))})
		pl.text += "\n" + Loc.tf("UI_CRATES_PITY_COUNT", {"n": int(pity.count), "soft": int(pity.soft_start), "hard": int(pity.hard)})
		if float(pity.next_relic_pct) > float(pity.nominal_relic_pct) + 1e-9:
			pl.text += "\n" + Loc.tf("UI_CRATES_PITY_NEXT", {"p": CrateUi.pct(float(pity.next_relic_pct))})
		var eff_parts := PackedStringArray()
		for r in rows:
			eff_parts.append("%s %s" % [CrateUi.rarity_symbol(str(r.rarity)), CrateUi.pct(float(r.effective_pct))])
		pl.text += "\n" + Loc.tf("UI_CRATES_EFFECTIVE", {"list": " · ".join(eff_parts)})
	else:
		pl.text = tr("UI_CRATES_NO_PITY")
	odds_box.add_child(pl)
	if not rows.is_empty() and float(rows[0].items[0].annalist_pct) > 0.0:
		var al := Label.new()
		al.text = Loc.tf("UI_CRATES_ANNALIST_ODDS", {"p": CrateUi.pct(float(rows[0].items[0].annalist_pct))})
		al.theme_type_variation = &"MutedLabel"
		odds_box.add_child(al)

	# --- azioni: UN solo pulsante primario (Apri); x5 e x10 sono secondari
	var can := _crates.openable_now(_selected)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	tv.add_child(actions)
	for n in [1, 5, 10]:
		var b := Button.new()
		b.text = tr("UI_CRATES_OPEN") if n == 1 else Loc.tf("UI_CRATES_OPEN_N", {"n": n})
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if n == 1:
			b.theme_type_variation = &"AccentButton"
			b.name = "OpenButton"
			b.custom_minimum_size = Vector2(200, 56)           # l'unico pulsante pieno della scena
			b.add_theme_font_size_override("font_size", 20)
		else:
			b.custom_minimum_size = Vector2(76, 44)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = can < n or _busy
		if b.disabled and not _busy and can >= 1:
			b.tooltip_text = Loc.tf("UI_VUX_NEED_N", {"n": n, "have": can})
		b.pressed.connect(_do_open.bind(n))
		actions.add_child(b)
		_open_btns.append(b)
	_quick_check = CheckBox.new()
	_quick_check.text = tr("UI_CRATES_QUICK")
	_quick_check.button_pressed = quick_open
	_quick_check.toggled.connect(func(on: bool) -> void: quick_open = on)
	actions.add_child(_quick_check)
	if can < 1:
		_missing_box(_selected, cdef)
	_compact_built = is_compact()
	if _compact_built:
		tv.move_child(actions, info.get_index() + 1)     # subito sotto nome e chiavi; le probabilità restano subito dopo, in vista

	# --- contenuto completo con la probabilità di ogni oggetto: a UN clic (aperto alla prima visita)
	_build_contents(rows)


## Contenuto completo (probabilità per finitura e per rarità): Disclosure, aperta alla prima visita, poi la scelta resta.
func _build_contents(rows: Array) -> void:
	if _contents_open < 0:
		_contents_open = 0 if VaultHead.seen(VaultHead.CONTENTS_ID) else 1
		VaultHead.mark_seen(VaultHead.CONTENTS_ID)
	var btn := Button.new()
	btn.name = "ContentsToggle"
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = tr("UI_CRATES_CONTENTS")
	Disclosure.apply(btn, "UI_F11_CONTENTS", _contents_open == 1)
	_detail.add_child(btn)
	var box := VBoxContainer.new()
	box.name = "ContentsBox"
	box.add_theme_constant_override("separation", 4)
	box.visible = _contents_open == 1
	_detail.add_child(box)
	for r in rows:
		var rl := Label.new()
		rl.text = "%s · %s" % [CrateUi.rarity_label(str(r.rarity)), CrateUi.pct(float(r.pct))]
		rl.add_theme_color_override("font_color", CrateUi.rarity_color(str(r.rarity)))
		box.add_child(rl)
		var g := HFlowContainer.new()
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		box.add_child(g)
		for it in r.items:
			g.add_child(_cell(str(it.def_id), str(r.rarity), CrateUi.pct(float(it.pct)), CrateUi.item_tooltip(r, it)))
	btn.pressed.connect(func() -> void:
		box.visible = not box.visible
		_contents_open = 1 if box.visible else 0
		Disclosure.apply(btn, "UI_F11_CONTENTS", box.visible))


## Nessuna cassa: spiega a cosa servono, come arrivano e mostra le casse che esistono (sagome, con il loro contenuto).
func _build_empty() -> void:
	var gos: Array = VaultKit.crate_sources()
	var steps := PackedStringArray([tr("UI_VUX_HALL_STEP_1"), tr("UI_VUX_HALL_STEP_2"), tr("UI_VUX_HALL_STEP_3")])
	var preview := HFlowContainer.new()
	preview.name = "GhostCrates"
	preview.add_theme_constant_override("h_separation", 8)
	preview.add_theme_constant_override("v_separation", 8)
	var shown := 0
	for it in DataRegistry.items_by_category("crate"):
		if str(it.get("crate", {}).get("kind", "")) != "zone" or shown >= 6:
			continue
		shown += 1
		var p := VaultKit.card(VaultKit.crate_accent(str(it.id)), false, true)
		p.custom_minimum_size = Vector2(108, 118)
		p.tooltip_text = tr("UI_VUX_GHOST_TIP")
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(v)
		var ic := VaultKit.pix(CrateUi.def_icon(str(it.id)), 2)
		ic.modulate = Color(0.45, 0.45, 0.5, 0.85)
		v.add_child(ic)
		var n := Label.new()
		n.text = CrateUi.def_name(str(it.id))
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		n.add_theme_font_size_override("font_size", UiType.NOTE)
		n.add_theme_color_override("font_color", FxPalette.SMOKE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
		preview.add_child(p)
	VaultKit.empty_card(_detail, IconLib.icon("crates", "crate_millbrook"), tr("UI_VUX_HALL_EMPTY_TITLE"),
		tr("UI_VUX_HALL_EMPTY_WHAT"), steps, gos, preview)
	VaultKit.label(_detail, tr("UI_VUX_HALL_ODDS_NOTE"), true)


func _cell(def_id: String, rarity: String, sub: String, tip: String) -> Control:
	return CrateUi.cell(def_id, rarity, sub, tip, CELL, false, 1)


# ------------------------------------------------------------------ apertura

func _do_open(n: int) -> void:
	if _busy or _crates == null or _selected.is_empty():
		return
	# 1) l'estrazione avviene qui, per intero, PRIMA di qualunque animazione
	_results = _crates.open(_selected, n)
	if _results.is_empty():
		return
	# 2) da qui in poi si mostra soltanto ciò che è già deciso
	_busy = true
	for b in _open_btns:
		b.disabled = true
	_split.visible = false                 # la scena prende il posto di elenco e dettaglio
	_open_panel.visible = true
	_result_label.text = ""
	_result_extra.text = ""
	_result_row.visible = false            # niente spazio vuoto riservato mentre il rullo gira
	_pick_label.text = ""
	_pick_label.visible = false
	_actions.visible = false
	_bulk_btn.visible = false
	_again_btn.visible = false
	_close_btn.visible = false
	_skip_btn.visible = not CrateUi.reduce_motion()
	_stage_odds.text = _odds_line(_selected)
	# scena: la cassa grande trema e si apre (l'esito è già estratto), poi parte il rullo. Livello effetti 0: subito.
	_preroll_on = true
	_chest.texture = CrateUi.def_icon(_selected)
	_glow.setup(null, VaultKit.crate_accent(_selected))
	_glow.visible = Fx.level() > 0
	var dim := Fx.level() > 0
	_reel_box.modulate.a = 0.0 if dim else 1.0
	_multi.modulate.a = 0.0 if dim else 1.0
	FxUi.chest_open(_chest, PREROLL_S * (0.45 if quick_open else 1.0), _after_preroll)


func _after_preroll() -> void:
	_preroll_on = false
	_glow.visible = false
	_reel_box.modulate.a = 1.0
	_multi.modulate.a = 1.0
	if not _busy or _results.is_empty():
		return
	if _results.size() == 1:
		_multi.visible = false
		_multi.stop()
		_reel_box.visible = true
		_skip_btn.visible = not CrateUi.reduce_motion()
		var r: Dictionary = _results[0]
		_reel.play(r.reel, int(r.reel_index), float(r.stop_frac), quick_open)
	else:
		# ×5 / ×10: sequenza rapida dei risultati veri (rarità crescente, la migliore per ultima)
		_reel_box.visible = false
		_multi.visible = true
		_skip_btn.visible = not CrateUi.reduce_motion()
		_multi.play(_results, quick_open)


func _on_skip() -> void:
	if not _busy:
		return
	if _preroll_on:                        # salta la scena della cassa: parte subito il rullo, poi si salta anche quello
		FxUi.finish_chest(_chest, _after_preroll)
	if _multi.visible and _multi.playing:
		_multi.skip()
	elif _reel_box.visible:
		_reel.skip()


func _on_reel_finished() -> void:
	if not _busy or _results.size() != 1:
		return
	var r: Dictionary = _results[0]
	_skip_btn.visible = false
	_reel_box.visible = false              # il rullo ha detto il suo: ora UNA carta grande, con le azioni a destra
	_result_row.visible = true
	_card.setup(r)
	_result_label.text = Loc.tf("UI_CRATES_FOUND", {"name": CrateUi.def_name(str(r.def_id))})
	_result_label.add_theme_color_override("font_color", CrateUi.rarity_color(str(r.rarity)))
	if not CrateUi.reduce_motion():       # piccolo rimbalzo di scala alla rivelazione (soddisfazione, nessuna spinta a riaprire)
		_card.pivot_offset = _card.custom_minimum_size * 0.5
		_card.scale = Vector2(0.92, 0.92)
		_card.create_tween().tween_property(_card, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var extra := PackedStringArray()
	if r.kind == "pet":
		extra.append(tr("UI_CRATES_PET_FOUND"))
	if bool(r.get("carro", false)):               # Deposito pieno: il premio aspetta nel Carro di Ritiro
		extra.append(_carro_line())
	_result_extra.text = "\n".join(extra)
	_result_extra.visible = not extra.is_empty()
	_show_actions(str(r.uid))
	_show_again()
	_close_btn.visible = true
	FxUi.result_frame(_open_panel, str(r.rarity))      # la cornice del risultato pulsa nel colore della rarità


## Probabilità della cassa in UNA riga sotto la scena (rarità con simbolo, percentuali nominali: le stesse della Sala).
func _odds_line(cid: String) -> String:
	var parts := PackedStringArray()
	for r in _crates.odds(cid):
		parts.append("%s %s" % [CrateUi.rarity_label(str(r.rarity)), CrateUi.pct(float(r.pct))])
	return tr("UI_CRATES_ODDS") + ": " + "  ·  ".join(parts)


## «Apri un'altra»: pulsante NEUTRO (non primario, nessun testo che spinge: R-LEG-5). Spento se non si può aprire.
func _show_again() -> void:
	var n := _crates.openable_now(_selected)
	_again_btn.visible = true
	_again_btn.text = Loc.tf("UI_GB_OPEN_AGAIN", {"n": NumberFormat.fmt(n)})
	_again_btn.disabled = n < 1


func _on_again() -> void:
	if _busy and _close_btn.visible:
		_on_close_panel()
		_do_open(1)


## «Deposito pieno: il premio è nel Carro di Ritiro (N pezzi)». N = quanto aspetta ADESSO nel Carro.
func _carro_line() -> String:
	var bank := CrateUi.bank()
	return Loc.tf("UI_CARRO_CRATE_LINE", {"n": NumberFormat.fmt(float(bank.overflow_count()) if bank != null else 0.0)})


## Le azioni stanno a destra della carta (×1, in colonna) o sotto la griglia (×5/×10, in fila): è lo STESSO nodo.
func _place_actions(multi: bool) -> void:
	var host: Node = _multi_host if multi else _rside
	_actions.column = not multi
	if _actions.get_parent() != host:
		if _actions.get_parent() != null:
			_actions.get_parent().remove_child(_actions)
		host.add_child(_actions)
		if not multi:
			host.move_child(_actions, 2)


## Pulsanti Equipaggia · Blocca · Fondi · Vendi · Contratto per il pezzo `uid` (vuoto = famiglio: niente pulsanti).
func _show_actions(uid: String) -> void:
	_place_actions(_results.size() > 1)
	_actions.visible = not uid.is_empty()
	if not uid.is_empty():
		_actions.setup(_crates, uid)


func _on_multi_finished() -> void:
	if not _busy:
		return
	_skip_btn.visible = false
	_result_row.visible = false
	_pick_label.visible = true
	_pick_label.text = tr("UI_CRATES2_PICK_HINT")
	_update_bulk()
	_show_again()
	_close_btn.visible = true
	var best := _multi.best_index()
	if best >= 0:
		_on_multi_selected(best)
		FxUi.result_frame(_open_panel, str(_results[best].rarity))


func _on_multi_selected(index: int) -> void:
	if index < 0 or index >= _results.size():
		return
	var r: Dictionary = _results[index]
	_pick_label.visible = true
	if r.kind == "skin" or r.kind == "relic" or r.kind == "cosmetic":
		var inst: Dictionary = r.instance
		_pick_label.text = (CrateUi.tagged_name(inst) + " · " + CrateUi.instance_summary(inst).replace("\n", " · ")).rstrip(" ·")
		_pick_label.tooltip_text = CrateUi.instance_detail(inst)
	else:
		_pick_label.text = CrateUi.def_name(str(r.def_id)) + " · " + tr("UI_CRATES_PET_FOUND")
		_pick_label.tooltip_text = ""
	if bool(r.get("carro", false)):
		_pick_label.text += "\n" + _carro_line()
	_show_actions(str(r.uid))


func _on_actions_changed(_what: String) -> void:
	_update_bulk()


## «Fondi le Rare di questa apertura»: solo la rarità più comune, solo i pezzi non bloccati e non in uso.
func _bulk_uids() -> Array:
	var out: Array = []
	for r in _results:
		if str(r.rarity) == "rare" and not str(r.uid).is_empty() and _crates.consume_block(str(r.uid)).is_empty():
			out.append(str(r.uid))
	return out


func _update_bulk() -> void:
	var uids := _bulk_uids()
	var total := 0
	for u in uids:
		total += _crates.fuse_value(str(u))
	_bulk_btn.visible = _results.size() > 1 and not uids.is_empty()
	_bulk_btn.text = Loc.tf("UI_CRATES2_BULK_FUSE", {"c": uids.size(), "n": NumberFormat.fmt(total)})
	_bulk_btn.tooltip_text = tr("UI_CRATES2_BULK_FUSE_TIP")


func _on_bulk_fuse() -> void:
	var uids := _bulk_uids()
	if uids.is_empty():
		return
	CrateUi.confirm(self, Loc.tf("UI_CRATES2_CONFIRM_BULK", {"c": uids.size()}), func() -> void:
		var res := _crates.fuse_many(_bulk_uids())
		EventBus.notice.emit("info", Loc.tf("UI_CRATES2_BULK_DONE", {"c": res.n, "n": NumberFormat.fmt(res.shards)}), {})
		_update_bulk()
		if _actions.visible:
			_actions.setup(_crates, _actions.current_uid()))


func _on_close_panel() -> void:
	_busy = false
	_open_panel.visible = false
	_split.visible = true
	_multi.stop()
	_results = []
	_rebuild(true)


# Ganci audio: nessun file, solo segnali che il futuro mixer potrà ascoltare (bus "Reel", docs/21).
func _on_tick_sound(_volume: float, _pitch: float) -> void:
	pass


func _on_reveal_sound(_rarity: String) -> void:
	pass
