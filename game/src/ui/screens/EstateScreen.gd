extends GameScreen
## Tenuta (docs/11, docs/16 §3.5, progetto di interfaccia 06 §3.10): un solo avviso (solo se serve) con un «Vai», una riga di numeri
## con «Raccogli tutto», e quattro schede: Edifici (carte compatte su 2 colonne, 3 in banda larga) · Dispensa (! se vuota) ·
## Rifondazione (• se disponibile) · Merci in vendita. Ogni carta mostra il solo prossimo traguardo (gli altri nel tooltip) e il
## pulsante di miglioramento con il costo; +1/+10/Max stanno nel menù del pulsante (tasto destro o «▾»).
## Solo presentazione: legge e comanda EstateSystem (Game.system("estate")). Aggiornata a ≤10 Hz da MainScreen; le animazioni
## sono tween e rispettano "riduci animazioni".

const ICON_PX := 64      # = lato del PNG (64x64): scala 1:1, pixel nitidi
const PULSE_S := 0.25
const COL_BAD := "#e0c070"           # «Mancano…»: ambra (attenzione), non rosso: il rosso è solo pericolo (rapporto grafica 22)
const COL_OK := "#a0d8a0"
const POP_GAP_MS := 1600                # al più un «+N» per edificio ogni 1,6 s
const POP_MAX_PER_REFRESH := 3          # e al più 3 per aggiornamento (10 Hz): niente tempesta di numeri
const TABS: Array = ["buildings", "pantry", "refound", "sell"]
const GRID_COLS_NARROW := 1             # colonne delle carte per banda di larghezza (UiBands): stretta 1, normale 2, larga 3
const GRID_COLS_NORMAL := 2
const GRID_COLS_WIDE := 3
const CARD_MIN_W := 395.0               # larghezza minima di una carta: le colonne diminuiscono se non ci stanno

var _e: EstateSystem
var _bank: BankSystem
var _alert: PanelContainer
var _alert_mark: Label
var _alert_text: Label
var _alert_btn: Button
var _alert_sig: String = ""
var _alert_action: Callable = Callable()
var _st_settlers: ScreenKit.KitStat
var _head_pantry: ScreenKit.KitStat
var _st_prod: ScreenKit.KitStat
var _st_storage: ScreenKit.KitStat
var _storage_bar: SmoothBar
var _st_prosperity: ScreenKit.KitStat
var _prosperity_bar: SmoothBar
var _st_partners: ScreenKit.KitStat
var _pantry_note: Label
var _pantry_empty_box: Control
var _refound_reason: Label
var _btn_collect: Button
var _btn_refound: Button
var _confirm: ConfirmationDialog
var _food_opt: OptionButton
var _food_ids: Array = []
var _btn_stock10: Button
var _btn_stock_all: Button
var _sell_box: HFlowContainer
var _sell_sig: String = ""
var _events_label: Label
var _cards: Dictionary = {}
var _levels_seen: Dictionary = {}
var _food_sig: String = ""
var _pantry_tween: Tween
var _chk_auto: CheckBox
var _scroll: ScrollContainer
var _pops_now: int = 0
var _stock_seen: Dictionary = {}        # bid -> unità intere in magazzino all'ultimo refresh (per il «pop» di produzione)
var _stock_acc: Dictionary = {}         # bid -> unità arrivate dall'ultimo «pop» mostrato
var _stock_ms: Dictionary = {}          # bid -> istante dell'ultimo «pop»
var _tab: String = "buildings"
var _tab_group := ButtonGroup.new()
var _tab_btns: Dictionary = {}
var _tab_names: Dictionary = {}
var _pages: Dictionary = {}
var _grid: GridContainer
var _open_state: Dictionary = {}
var _intro: Dictionary = {}


func open(params: Dictionary) -> void:
	_e = Game.system("estate") as EstateSystem
	_bank = Game.system("bank") as BankSystem
	if _e == null:
		var title := Label.new()
		ScreenKit.title_style(title)
		title.text = "UI_MENU_ESTATE"
		add_child(title)
		var l := Label.new()
		l.text = "UI_ESTATE_NO_SYSTEM"
		add_child(l)
		return
	_intro = EstateDungeonKit.title_row(self, "UI_MENU_ESTATE", "UI_RS_ES_PURPOSE", "estate")
	_build_alert()
	_build_numbers(self)
	_build_tabs()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	scroll.resized.connect(func() -> void: _grid.columns = _grid_columns())       # le colonne seguono la larghezza reale
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	for t in TABS:
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 8)
		col.add_child(page)
		_pages[t] = page
	_build_buildings(_pages.buildings)
	_build_pantry(_pages.pantry)
	_build_refound(_pages.refound)
	_build_sell_panel(_pages.sell)
	var focus_bid := str(params.get("building", ""))        # da un requisito cliccato altrove (ReqLink, G37)
	if not focus_bid.is_empty() and _cards.has(focus_bid):
		ReqLink.reveal.call_deferred(_cards[focus_bid].panel as Control)
	_confirm = ConfirmationDialog.new()
	DialogKit.style_confirm(_confirm)
	_confirm.dialog_text = tr("UI_ESTATE_REFOUND_CONFIRM")
	_confirm.confirmed.connect(_do_refound)
	add_child(_confirm)
	var want := str(params.get("tab", "buildings"))
	_set_tab(want if TABS.has(want) else "buildings")
	refresh()


# ------------------------------------------------------------------ costruzione

## Avviso unico (solo se serve): segno + frase + un pulsante. Si mostra e si aggiorna in _refresh_alert().
func _build_alert() -> void:
	_alert = PanelContainer.new()
	_alert.visible = false
	_alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_alert)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_alert.add_child(h)
	_alert_mark = Label.new()
	_alert_mark.text = EstateDungeonKit.WARN_MARK
	_alert_mark.add_theme_color_override("font_color", Color(ScreenKit.WARN))
	h.add_child(_alert_mark)
	_alert_text = Label.new()
	_alert_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alert_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	h.add_child(_alert_text)
	_alert_btn = Button.new()
	_alert_btn.theme_type_variation = &"AccentButton"
	_alert_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_alert_btn.pressed.connect(func() -> void:
		if _alert_action.is_valid():
			_alert_action.call())
	h.add_child(_alert_btn)
	var sb := ScreenKit.card_style(Color(ScreenKit.WARN).darkened(0.25), 4)
	sb.bg_color = Color(0.18, 0.16, 0.10)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_alert.add_theme_stylebox_override("panel", sb)


## Una riga di numeri (coloni · produzione · magazzino con barra) e «Raccogli tutto».
func _build_numbers(parent: Control) -> void:
	var v := ScreenKit.card(parent, ScreenKit.accent("estate"), 4, true)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 22)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	_st_settlers = ScreenKit.stat(row, "", "UI_RS_ES_TIP_SETTLERS")
	_st_prod = ScreenKit.stat(row, "UI_RS_ES_ST_PROD", "UI_RS_ES_TIP_PROD")
	var store := HBoxContainer.new()
	store.add_theme_constant_override("separation", 10)
	store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(store)
	_st_storage = ScreenKit.stat(store, "UI_RS_ES_ST_STORE", "UI_RS_ES_TIP_STORE")
	_storage_bar = ScreenKit.bar(store, Color(ScreenKit.WARN), 12)
	_storage_bar.custom_minimum_size = Vector2(80, 12)
	_storage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	FxBarGhost.attach(_storage_bar)         # il magazzino che si riempie lampeggia, quando si raccoglie lascia la scia
	_btn_collect = Button.new()
	_btn_collect.theme_type_variation = &"AccentButton"
	_btn_collect.text = "UI_ESTATE_COLLECT"
	_btn_collect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn_collect.pressed.connect(_on_collect)
	row.add_child(_btn_collect)


func _build_tabs() -> void:
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	add_child(tabs)
	_tab_names = {"buildings": tr("UI_ESTATE_BUILDINGS"), "pantry": tr("UI_RS_ES_PANTRY_T"), "refound": tr("UI_ESTATE_REFOUND"), "sell": tr("UI_ESTATE_SELL_TITLE")}
	for t in TABS:
		var tid := str(t)
		var b := EstateDungeonKit.tab_button(_tab_group, str(_tab_names[tid]), "", ScreenKit.accent("estate"))
		b.pressed.connect(func() -> void: _set_tab(tid))
		tabs.add_child(b)
		_tab_btns[tid] = b


func _set_tab(tab: String) -> void:
	if not _pages.has(tab):
		tab = "buildings"
	_tab = tab
	for k in _pages:
		(_pages[k] as Control).visible = k == tab
	for k in _tab_btns:
		(_tab_btns[k] as Button).set_pressed_no_signal(k == tab)
	if _scroll != null:
		_scroll.scroll_vertical = 0


func _build_buildings(page: VBoxContainer) -> void:
	_grid = GridContainer.new()
	_grid.columns = GRID_COLS_NORMAL
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	page.add_child(_grid)
	for bid in _e.building_ids():
		_build_card(_grid, str(bid))
	# «Voci dalla Tenuta»: non c'è ancora un'API della Gazzetta (F6): restano qui, in una sezione chiusa
	var ev_body := EstateDungeonKit.disclosure(page, "UI_ESTATE_EVENTS", _open_state, "events")
	_events_label = ScreenKit.muted("")
	ev_body.add_child(_events_label)


func _build_pantry(page: VBoxContainer) -> void:
	var pv := ScreenKit.card(page, Color(ScreenKit.WARN), 4)
	var row := ScreenKit.stat_row(pv)
	_head_pantry = ScreenKit.stat(row, "", "UI_RS_ES_TIP_PANTRY")
	_pantry_note = ScreenKit.muted("")
	pv.add_child(_pantry_note)
	var food_row := HFlowContainer.new()
	food_row.add_theme_constant_override("h_separation", 6)
	pv.add_child(food_row)
	var fl := Label.new()
	fl.text = "UI_ESTATE_STOCK_WITH"
	food_row.add_child(fl)
	_food_opt = OptionButton.new()
	_food_opt.custom_minimum_size = Vector2(220, 0)
	_food_opt.tooltip_text = "UI_RS_ES_TIP_FOOD"
	food_row.add_child(_food_opt)
	_btn_stock10 = Button.new()
	_btn_stock10.text = "UI_ESTATE_STOCK_10"
	_btn_stock10.pressed.connect(_on_stock.bind(10))
	food_row.add_child(_btn_stock10)
	_btn_stock_all = Button.new()
	_btn_stock_all.text = "UI_ESTATE_STOCK_ALL"
	_btn_stock_all.pressed.connect(_on_stock.bind(-1))
	food_row.add_child(_btn_stock_all)
	_chk_auto = CheckBox.new()
	_chk_auto.text = "UI_OFFL_PANTRY_AUTO"
	_chk_auto.tooltip_text = "UI_OFFL_PANTRY_AUTO_TIP"
	_chk_auto.toggled.connect(func(on: bool) -> void: _e.set_pantry_auto(on))
	food_row.add_child(_chk_auto)
	# senza cibo: dice dove procurarselo (un solo messaggio, dentro la scheda)
	var nf := VBoxContainer.new()
	nf.add_theme_constant_override("separation", 4)
	pv.add_child(nf)
	_pantry_empty_box = nf
	var nfl := ScreenKit.label("UI_RS_ES_NOFOOD", "MonoLabel", Color(ScreenKit.BAD))
	nf.add_child(nfl)
	var nfr := HFlowContainer.new()
	nfr.add_theme_constant_override("h_separation", 8)
	nf.add_child(nfr)
	if ScreenKit.available("skill:cooking"):
		nfr.add_child(ScreenKit.go_button(tr("UI_RS_GO_COOK"), ScreenKit.target("skill:cooking")))
	if ScreenKit.available("market"):
		nfr.add_child(ScreenKit.go_button(tr("UI_RS_GO_MARKET"), ScreenKit.target("market")))


func _build_refound(page: VBoxContainer) -> void:
	var rv := ScreenKit.card(page, Color(ScreenKit.EDGE), 2)
	var help_body := EstateDungeonKit.disclosure(rv, "UI_F9_ES_HOW", _open_state, "refound_help")
	help_body.add_child(ScreenKit.muted("UI_RS_ES_REFOUND_HELP"))
	var rrow := ScreenKit.stat_row(rv)
	_st_prosperity = ScreenKit.stat(rrow, "UI_RS_ES_ST_PROS", "UI_RS_ES_TIP_PROS")
	_st_partners = ScreenKit.stat(rrow, "", "UI_RS_ES_TIP_PARTNERS")
	_prosperity_bar = ScreenKit.bar(rv, Color(ScreenKit.GOLD), 8)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 8)
	rv.add_child(rb)
	_btn_refound = Button.new()
	_btn_refound.text = "UI_ESTATE_REFOUND"
	_btn_refound.pressed.connect(func() -> void: _confirm.popup_centered())
	rb.add_child(_btn_refound)
	_refound_reason = ScreenKit.reason_label()
	_refound_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refound_reason.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.add_child(_refound_reason)


func _build_sell_panel(page: VBoxContainer) -> void:
	page.add_child(ScreenKit.muted("UI_ESTATE_SELL_HINT"))
	_sell_box = HFlowContainer.new()
	_sell_box.add_theme_constant_override("h_separation", 12)
	page.add_child(_sell_box)


## Carta edificio compatta (icona 64 px 1:1): nome e livello, una riga di produzione, barra del PROSSIMO traguardo, pulsante di
## miglioramento col costo. Descrizione e tutti i traguardi nel tooltip; i materiali mancanti (cliccabili) sotto, solo se servono.
func _build_card(parent: Control, bid: String) -> void:
	var d: Dictionary = _e.def_of(bid)
	var body := ScreenKit.card(parent, Color(ScreenKit.EDGE), 4)
	var panel := ScreenKit.panel_of(body)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	body.add_child(h)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED       # mai deformata dall'altezza della scheda
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = IconLib.icon("estate", bid)
	h.add_child(icon)
	var amb := FxAmbient.attach(icon, bid)       # ruote, fumo, luci: disegnati sopra l'icona, fermi se non lavora
	FxUi.card_hover(panel)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	v.add_child(nrow)
	var name_l := Label.new()
	name_l.theme_type_variation = &"SectionLabel"
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART             # mai «Pozzo Miner…»: il nome va a capo
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.custom_minimum_size.x = 72
	nrow.add_child(name_l)
	var ms_l := Label.new()
	ms_l.theme_type_variation = &"MutedLabel"
	nrow.add_child(ms_l)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 6)
	v.add_child(irow)
	var info := Label.new()
	info.theme_type_variation = &"MonoLabel"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART               # l'effetto va a capo, mai «…»
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(72, 0)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	irow.add_child(info)
	var opt: OptionButton = null
	if str(d.type) == "producer":
		opt = OptionButton.new()                                        # selettore della risorsa SOTTO, a larghezza piena (non più «Tronc»)
		opt.item_selected.connect(_on_product.bind(bid))
		opt.fit_to_longest_item = false
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(opt)
	var ms := SmoothBar.new()
	ms.custom_minimum_size = Vector2(40, 8)
	ms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.add_theme_stylebox_override("fill", UiKit.tinted_fill(Color(ScreenKit.GOLD)))
	v.add_child(ms)
	var cost := RichTextLabel.new()
	cost.bbcode_enabled = true
	cost.fit_content = true
	cost.scroll_active = false
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.add_theme_font_size_override("normal_font_size", UiType.NOTE)
	cost.meta_clicked.connect(ReqLink.meta_go)           # il materiale che manca è cliccabile: porta a dove si ottiene (G37)
	v.add_child(cost)
	# pulsante di miglioramento col costo + «▾» (menù +1/+10/Max, anche col tasto destro)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 2)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(btns)
	var b1 := Button.new()
	b1.theme_type_variation = &"AccentButton"
	b1.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b1.custom_minimum_size = Vector2(80, 0)
	b1.pressed.connect(_on_upgrade.bind(bid, 1))
	btns.add_child(b1)
	var arrow := Button.new()
	arrow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	arrow.text = "▾"
	arrow.tooltip_text = tr("UI_F9_ES_MENU_TIP")
	btns.add_child(arrow)
	var menu := PopupMenu.new()
	menu.add_item(tr("UI_ESTATE_BTN_1"), 1)
	menu.add_item(tr("UI_ESTATE_BTN_10"), 10)
	menu.add_item(tr("UI_ESTATE_BTN_MAX"), 11)
	menu.id_pressed.connect(func(id: int) -> void: _on_upgrade(bid, -1 if id == 11 else id))
	panel.add_child(menu)
	arrow.pressed.connect(func() -> void: _popup_menu(menu, arrow))
	b1.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_popup_menu(menu, b1))
	_cards[bid] = {"panel": panel, "body": body, "name": name_l, "info": info, "ms": ms, "ms_l": ms_l, "cost": cost, "opt": opt, "menu": menu,
		"b1": b1, "arrow": arrow, "opt_sig": "", "icon": icon, "amb": amb, "edge": -1}


func _popup_menu(menu: PopupMenu, anchor: Control) -> void:
	var r := anchor.get_global_rect()
	menu.popup(Rect2i(Vector2i(int(r.position.x), int(r.end.y)), Vector2i.ZERO))


# ------------------------------------------------------------------ azioni

func _on_upgrade(bid: String, n: int) -> void:
	var done := _e.upgrade_max(bid) if n < 0 else _e.upgrade_many(bid, n)
	if done > 0:
		_pulse(_cards[bid].panel as Control)
		var ic := _cards[bid].icon as Control
		Fx.coins(Fx.anchor_pos("gold", Fx.center_of(ic) + Vector2(0, -120)), Fx.center_of(ic), 4)      # il costo «vola» nell'edificio
		Fx.burst("dust", Fx.center_of(ic), [], 1.0, 1.0, Vector2(ic.size.x * 0.4, 4.0))
		Fx.ring(Fx.center_of(ic), FxPalette.GOLD, 48.0, 0.5)
	refresh()


func _on_product(index: int, bid: String) -> void:
	var opt: OptionButton = _cards[bid].opt
	_e.set_product(bid, str(opt.get_item_metadata(index)))
	refresh()


func _on_collect() -> void:
	var got := _e.collect_all()
	if not got.is_empty():
		_pulse(_storage_bar)
		Fx.coins(Fx.center_of(_storage_bar), Fx.anchor_pos("bank", Fx.center_of(_storage_bar) + Vector2(-260, 0)), 5, Fx.anchor_node("bank"))
	refresh()


func _on_stock(qty: int) -> void:
	var idx := _food_opt.selected
	if idx < 0 or idx >= _food_ids.size():
		return
	var fid := str(_food_ids[idx])
	var n := _bank.count(fid) if qty < 0 else qty
	if _e.stock_pantry(fid, n) > 0:
		_pulse(_head_pantry)
	_food_sig = ""
	refresh()


func _do_refound() -> void:
	if _e.refound():
		for bid in _cards:
			_pulse(_cards[bid].panel as Control)
	refresh()


func _pulse(c: Control) -> void:
	if Settings.get_value("reduce_motion") or not is_inside_tree() or c == null:
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2(1.02, 1.02), PULSE_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate", Color(1.4, 1.3, 0.9), PULSE_S)
	tw.chain().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, PULSE_S)
	tw.tween_property(c, "modulate", Color.WHITE, PULSE_S)


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	if _e == null or _st_settlers == null:
		return
	_grid.columns = _grid_columns()
	_refresh_food()
	_refresh_header()
	_refresh_sell()
	_pops_now = 0
	for bid in _cards:
		_refresh_card(str(bid))
	var lines := PackedStringArray()
	var evlog: Array = _e.event_log()
	for i in range(evlog.size() - 1, maxi(-1, evlog.size() - 4), -1):
		lines.append("• " + tr("UI_ESTATE_EV_" + str(evlog[i].id).to_upper()))
	_events_label.text = "\n".join(lines) if not lines.is_empty() else tr("UI_ESTATE_EVENTS_NONE")


## Colonne delle carte edificio: 1 in banda stretta, 2 in banda normale (1280), 3 in banda larga (06 §3.10, §3.17), ma mai tante
## da stringere le carte sotto CARD_MIN_W.
func _grid_columns() -> int:
	if not is_inside_tree():
		return GRID_COLS_NORMAL
	var cols := GRID_COLS_NORMAL
	match UiBands.band(get_viewport().get_visible_rect().size.x):
		UiBands.BAND_NARROW:
			cols = GRID_COLS_NARROW
		UiBands.BAND_WIDE:
			cols = GRID_COLS_WIDE
	var avail := (_scroll.size.x if _scroll != null else size.x) - 24.0
	while cols > 1 and avail / float(cols) < CARD_MIN_W:
		cols -= 1
	return cols


func _refresh_header() -> void:
	var more_coming := _e.settlers() < _e.settler_cap()
	_st_settlers.set_value(str(_e.settlers()), "/ %d" % _e.settler_cap())
	_st_settlers.set_caption(Loc.tf("UI_RS_ES_CAP_SETTLERS" if more_coming else "UI_RS_ES_CAP_SETTLERS_FULL", {"free": maxi(0, _e.settlers_free()),
		"next": NumberFormat.fmt_time(maxf(0.0, _e.settler_arrival_s() - float(_e.state.settler_s)))}))
	var empty := _e.settlers() > 0 and _e.pantry() <= 0.0
	var hours := _e.pantry_hours()
	_head_pantry.set_value(NumberFormat.fmt(floorf(_e.pantry())), tr("UI_RS_UNIT_RATIONS"))
	_head_pantry.set_color(Color(ScreenKit.BAD) if empty else Color(ScreenKit.GOLD))
	# la parola «vuota» sta in UN posto solo (l'avviso in cima); qui solo il numero e, se c'è, per quanto basta
	_head_pantry.set_caption("" if empty else (Loc.tf("UI_RS_ES_CAP_PANTRY", {"t": NumberFormat.fmt_time(hours * 3600.0)}) if hours < INF else tr("UI_RS_ES_CAP_PANTRY_NOUSE")))
	_set_pantry_warning(empty)
	if _chk_auto.button_pressed != _e.pantry_auto():
		_chk_auto.set_pressed_no_signal(_e.pantry_auto())
	var pct := int(round((1.0 - _e.starving_mult()) * 100.0))
	_pantry_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_pantry_note.text = Loc.tf("UI_F9_ES_PANTRY_RULE", {"pct": pct})
	_st_prod.set_value(NumberFormat.fmt(_e.total_units_per_hour()), tr("UI_RS_UNIT_UNITS_H"))
	var has_shop := _e.level_of_type("seller") > 0
	_st_prod.set_caption(Loc.tf("UI_RS_ES_CAP_PROD_SHOP", {"gold": NumberFormat.fmt(_e.shop_gold_cap_per_h())}) if has_shop else tr("UI_RS_ES_CAP_PROD_NOSHOP"))
	var cap := _e.capacity()
	var tot := _e.stored_total()
	_st_storage.set_value(NumberFormat.fmt(floorf(tot)), "/ %s %s" % [NumberFormat.fmt(cap) if cap < INF else "∞", tr("UI_RS_UNIT_UNITS")])
	_storage_bar.max_value = cap if cap < INF else maxf(1.0, tot)
	_storage_bar.value = tot
	var near_full := cap < INF and tot >= 0.9 * cap
	_st_storage.set_color(Color(ScreenKit.WARN) if near_full else Color(ScreenKit.GOLD))
	_st_storage.set_caption("" if near_full else tr("UI_RS_ES_CAP_STORE"))      # il «quasi pieno» è l'avviso in cima
	var need := float(_e.prestige_min_units())
	var prosperity := float(_e.state.prosperity)
	_st_prosperity.set_value(NumberFormat.fmt(prosperity), "/ %s" % NumberFormat.fmt(need))
	_prosperity_bar.max_value = maxf(1.0, need)
	_prosperity_bar.value = minf(prosperity, need)
	var pend := _e.partners_pending()
	var owned := _e.partners()
	var gain_pct := 0.0 if owned <= 0 else float(pend) / float(owned) * 100.0
	_st_partners.set_value(str(owned), tr("UI_RS_UNIT_PARTNERS"))
	_st_partners.set_caption(Loc.tf("UI_RS_ES_CAP_PARTNERS" if owned > 0 else "UI_RS_ES_CAP_PARTNERS_NEW", {"bonus": NumberFormat.fmt((Game.system("prestige") as PrestigeSystem).partner_bonus_pct(owned)),
		"new": pend, "rel": NumberFormat.fmt(gain_pct)}))
	_btn_collect.disabled = _e.stored_total() < 1.0
	_btn_collect.tooltip_text = tr("UI_RS_ES_COLLECT_EMPTY") if _btn_collect.disabled else tr("UI_RS_ES_COLLECT_NOTE")
	var ps := Game.system("prestige") as PrestigeSystem
	var refound_visible := ps != null and ps.layer_visible("refound")      # la Rifondazione compare solo quando serve (come la scheda del Prestigio)
	var why := ScreenKit.refound_reason(ps)
	ScreenKit.gate(_btn_refound, why, _refound_reason)
	if why == "":
		_btn_refound.tooltip_text = tr("UI_ESTATE_REFOUND_ADVISED") if _e.refound_advised() else tr("UI_ESTATE_REFOUND_TIP")
	_refresh_tabs(empty, refound_visible, refound_visible and why == "")
	_refresh_alert(empty, near_full, pct, cap, tot)


## Schede: «Dispensa !» se vuota, «Rifondazione •» se si può fare adesso (e la scheda c'è solo quando il Prestigio la mostra).
func _refresh_tabs(pantry_empty: bool, refound_visible: bool, refound_ready: bool) -> void:
	(_tab_btns.pantry as Button).text = EstateDungeonKit.tab_text(str(_tab_names.pantry), EstateDungeonKit.WARN_MARK if pantry_empty else "")
	(_tab_btns.pantry as Button).tooltip_text = tr("UI_F9_ES_TAB_PANTRY_WARN") if pantry_empty else ""
	(_tab_btns.refound as Button).text = EstateDungeonKit.tab_text(str(_tab_names.refound), EstateDungeonKit.DOT_MARK if refound_ready else "")
	(_tab_btns.refound as Button).tooltip_text = tr("UI_F9_ES_TAB_REFOUND_READY") if refound_ready else ""
	(_tab_btns.refound as Button).visible = refound_visible
	if not refound_visible and _tab == "refound":
		_set_tab("buildings")
	# l'indicatore sulla scheda resta anche quando la scheda è aperta: la segnala, non la nasconde


## Avviso UNICO e solo se serve (il più urgente), con un «Vai». Dispensa vuota: la parola «vuota» compare solo qui.
func _refresh_alert(pantry_empty: bool, near_full: bool, pct: int, cap: float, tot: float) -> void:
	var text := ""
	var btn := ""
	var action := Callable()
	var sig := ""
	if pantry_empty:
		text = Loc.tf("UI_F9_ES_ALERT_PANTRY", {"pct": pct})
		if not _food_ids.is_empty():
			btn = tr("UI_F9_ES_GO_PANTRY")
			action = func() -> void: _set_tab("pantry")
			sig = "pantry_food"
		elif ScreenKit.available("skill:cooking"):
			btn = tr("UI_RS_GO_COOK")
			action = func() -> void: ScreenKit.go(ScreenKit.target("skill:cooking"))
			sig = "pantry_cook"
		elif ScreenKit.available("market"):
			btn = tr("UI_RS_GO_MARKET")
			action = func() -> void: ScreenKit.go(ScreenKit.target("market"))
			sig = "pantry_market"
		else:
			sig = "pantry_none"
	elif near_full:
		text = Loc.tf("UI_F9_ES_ALERT_FULL", {"n": NumberFormat.fmt(floorf(tot)), "cap": NumberFormat.fmt(cap)})
		sig = "full"
	_alert.visible = text != ""
	if text == "":
		return
	var full_sig := "%s|%s|%s" % [sig, text, btn]
	if full_sig == _alert_sig:
		return
	_alert_sig = full_sig
	_alert_text.text = text
	_alert_btn.text = btn
	_alert_btn.visible = btn != ""
	_alert_action = action


func _set_pantry_warning(on: bool) -> void:
	if on and (_pantry_tween == null or not _pantry_tween.is_valid()) and not Settings.get_value("reduce_motion") and is_inside_tree():
		_pantry_tween = UiAnim.color_loop(_head_pantry, &"modulate", Color.WHITE, Color(1.5, 0.7, 0.7), 0.6)
	elif not on and _pantry_tween != null:
		_pantry_tween.kill()
		_pantry_tween = null
		_head_pantry.modulate = Color.WHITE


func _refresh_food() -> void:
	var ids: Array = []
	if _bank != null:
		for k in (_bank.state.stacks as Dictionary):
			if str(DataRegistry.item(str(k)).get("category", "")) == "food":
				ids.append(str(k))
	ids.sort()
	var sig := ",".join(PackedStringArray(ids))
	if sig != _food_sig and not _food_opt.get_popup().visible:
		_food_sig = sig
		var keep := _food_opt.selected
		_food_ids = ids
		_food_opt.clear()
		for fid in ids:
			_food_opt.add_item("%s ×%s" % [Loc.t(DataRegistry.item(str(fid)).get("name", fid)), NumberFormat.fmt(_bank.count(str(fid)))])
		if keep >= 0 and keep < ids.size():
			_food_opt.select(keep)
	elif sig == _food_sig:
		for i in ids.size():
			_food_opt.set_item_text(i, "%s ×%s" % [Loc.t(DataRegistry.item(str(ids[i])).get("name", ids[i])), NumberFormat.fmt(_bank.count(str(ids[i])))])
	var has := not ids.is_empty()
	_pantry_empty_box.visible = not has
	ScreenKit.gate(_btn_stock10, "" if has else tr("UI_RS_ES_NOFOOD_SHORT"))
	ScreenKit.gate(_btn_stock_all, "" if has else tr("UI_RS_ES_NOFOOD_SHORT"))
	_food_opt.disabled = not has


func _refresh_sell() -> void:
	var items: Array = []
	for bid in _e.building_ids():
		if _e.type_of(bid) == "producer" and _e.level_of(bid) > 0:
			var p := _e.product_of(bid)
			if p != "" and not items.has(p):
				items.append(p)
	for it in _e.state.storage:
		if not items.has(it):
			items.append(it)
	var sig := ",".join(PackedStringArray(items)) + "|" + str(_e.level_of_type("seller") > 0)
	if sig == _sell_sig:
		return
	_sell_sig = sig
	for c in _sell_box.get_children():
		c.queue_free()
	if _e.level_of_type("seller") <= 0:
		var l := ScreenKit.muted("UI_ESTATE_SELL_NONE")
		l.custom_minimum_size = Vector2(380, 0)
		_sell_box.add_child(l)
		for bid in _e.building_ids():
			if _e.type_of(bid) == "seller" and _cards.has(bid):
				_sell_box.add_child(ScreenKit.go_button(tr("UI_RS_ES_GO_SHOP"), ScreenKit.target("estate", {"building": bid}), true))
		return
	for it in items:
		var cb := CheckBox.new()
		cb.text = Loc.t(DataRegistry.item(str(it)).get("name", it))
		cb.button_pressed = _e.is_listed(str(it))
		cb.toggled.connect(func(on: bool) -> void: _e.set_listed(str(it), on))
		_sell_box.add_child(cb)


func _refresh_card(bid: String) -> void:
	var c: Dictionary = _cards[bid]
	var d: Dictionary = _e.def_of(bid)
	var lv := _e.level_of(bid)
	var unlocked := _e.is_unlocked(bid)
	(c.panel as Control).modulate.a = 1.0 if unlocked or lv > 0 else 0.7
	(c.name as Label).text = Loc.tf("UI_F9_ES_CARD_NAME", {"name": Loc.t(d.name), "lv": lv})
	if not _levels_seen.has(bid):
		_levels_seen[bid] = lv
	elif int(_levels_seen[bid]) != lv:
		_levels_seen[bid] = lv
		_pulse(c.panel as Control)
	(c.info as Label).text = _info_text(bid, d, lv)
	(c.info as Label).tooltip_text = _info_tip(bid, d, lv)
	_fx_breathe(c.icon as Control, lv > 0 and (str(d.type) == "producer" or str(d.type) == "seller"))
	(c.amb as FxAmbient).active = lv > 0
	if str(d.type) == "producer":
		_fx_produce(bid, lv)
	var nxt := _e.milestone_next(lv)
	var ms: SmoothBar = c.ms
	var ms_l: Label = c.ms_l
	if str(d.type) == "producer" or str(d.type) == "seller":
		ms.visible = true
		ms_l.visible = true
		if nxt > 0:
			var prev := 0
			for m in DataRegistry.constants.estate.milestones:
				if int(m) <= lv:
					prev = int(m)
			ms.set_target(clampf(float(lv - prev) / float(nxt - prev), 0.0, 1.0), 0.0)
			ms_l.text = Loc.tf("UI_F9_ES_MS", {"a": lv, "b": nxt})
		else:
			ms.set_target(1.0, 0.0)
			ms_l.text = tr("UI_F9_ES_MS_MAX")
	else:
		ms.visible = false
		ms_l.visible = false
	# costo e pulsante: l'oro sta sul pulsante, i materiali (cliccabili se mancano) sotto, solo se servono
	var cost: Dictionary = _e.cost_of(bid)
	var reason := _e.can_upgrade(bid)
	var cost_txt := _cost_bbcode(cost, reason) if unlocked else _locked_bbcode(d)
	(c.cost as RichTextLabel).text = cost_txt
	(c.cost as RichTextLabel).visible = cost_txt != ""
	var ok := reason == ""
	var why := "" if ok else _why_text(reason, cost)
	var b1: Button = c.b1
	b1.text = "▲ %s %s" % [NumberFormat.fmt(int(cost.gold)), tr("UI_ESTATE_GOLD")] if unlocked else "▲ —"
	ScreenKit.gate(b1, why)
	b1.tooltip_text = (tr("UI_RS_ES_TIP_B1") + "\n" + _cost_tip(cost)) if ok else (why + "\n" + _cost_tip(cost) if unlocked else why)
	var menu: PopupMenu = c.menu
	for i in menu.item_count:
		menu.set_item_disabled(i, not ok)
	(c.panel as Control).tooltip_text = _card_tooltip(d)
	var state_key := 3 if not unlocked and lv <= 0 else (2 if ok else (1 if lv > 0 else 0))
	if int(c.edge) != state_key:
		c.edge = state_key
		var edge: Color = [Color(ScreenKit.EDGE), Color("#5f8f5f"), Color("#d2b574"), Color("#555a66")][state_key]
		ScreenKit.set_edge(c.body, edge)
	var opt: OptionButton = c.opt
	if opt != null:
		var options: Array = _e.product_options(bid)
		var chosen := _e.product_of(bid)
		var sig := ",".join(PackedStringArray(options)) + "|" + chosen
		if sig != str(c.opt_sig) and not opt.get_popup().visible:
			c.opt_sig = sig
			opt.clear()
			for i in options.size():
				opt.add_item(Loc.t(DataRegistry.item(str(options[i])).get("name", options[i])))
				opt.set_item_metadata(i, options[i])
				if str(options[i]) == chosen:
					opt.select(i)
			opt.tooltip_text = tr("UI_ESTATE_PRODUCT") + " " + opt.get_item_text(opt.selected) if opt.selected >= 0 else tr("UI_ESTATE_PRODUCT")
		opt.disabled = options.size() <= 1 or lv <= 0


## Produzione che «pop»: quando in magazzino arrivano unità intere del prodotto, sopra l'edificio sale un «+N» e l'icona fa
## un piccolo rimbalzo. Rate-limit per edificio e per aggiornamento; solo se l'icona si vede davvero nello scorrimento.
func _fx_produce(bid: String, lv: int) -> void:
	var item := _e.product_of(bid)
	var cur := int(floor(_e.stored(item))) if (lv > 0 and item != "") else 0
	var prev: int = int(_stock_seen.get(bid, cur))
	_stock_seen[bid] = cur
	if cur > prev:
		_stock_acc[bid] = int(_stock_acc.get(bid, 0)) + (cur - prev)
	var acc: int = int(_stock_acc.get(bid, 0))
	if acc <= 0 or _pops_now >= POP_MAX_PER_REFRESH or not Fx.enabled():
		return
	var now := Time.get_ticks_msec()
	if now - int(_stock_ms.get(bid, -100000)) < POP_GAP_MS:
		return
	var icon := _cards[bid].icon as Control
	var at := Fx.center_of(icon) + Vector2(0, -icon.size.y * 0.4)
	if _scroll == null or not icon.is_visible_in_tree() or _scroll.get_global_rect().size.y <= 56.0 or not _scroll.get_global_rect().grow_individual(0.0, -56.0, 0.0, 0.0).has_point(at):
		return                                # fuori dallo scorrimento (o troppo vicino al bordo): il numero finirebbe sull'intestazione
	_stock_ms[bid] = now
	_stock_acc[bid] = 0
	_pops_now += 1
	Fx.number(at, "+" + NumberFormat.fmt(float(acc)), FxPalette.GREEN, Fx.NUM_S, 26.0, 0.9)
	Fx.pop(icon, 1.14, 0.2)
	Fx.burst("glint", Fx.center_of(icon), [FxPalette.GOLD, FxPalette.WHITE], 0.6, 0.6, icon.size * 0.3)


## L'edificio «respira» (luce lenta sull'icona) finché lavora; si avvia/spegne solo al cambio di stato (refresh a 10 Hz).
func _fx_breathe(icon: Control, on: bool) -> void:
	if icon == null or FxGlowPulse.is_active(icon) == on:
		return
	Fx.breathe(icon, on)


## Tooltip della carta: descrizione e TUTTI i traguardi di livello (sulla carta c'è solo il prossimo).
func _card_tooltip(d: Dictionary) -> String:
	var ms: PackedStringArray = []
	for m in DataRegistry.constants.estate.milestones:
		ms.append(str(int(m)))
	var tip := Loc.t(d.get("desc", {}))
	if str(d.type) == "producer" or str(d.type) == "seller":
		tip += "\n" + Loc.tf("UI_F9_ES_TIP_MS", {"list": ", ".join(ms)})
	return tip


func _info_text(bid: String, d: Dictionary, lv: int) -> String:
	match str(d.type):
		"producer":
			var item := _e.product_of(bid)
			if lv <= 0 or item == "":
				return Loc.tf("UI_F9_ES_PROD_NONE", {"g": _e.grade_of(bid)})
			return Loc.tf("UI_F9_ES_PROD", {"n": NumberFormat.fmt(_e.units_per_hour(bid))})
		"housing":
			return Loc.tf("UI_ESTATE_HOUSING", {"cap": _e.settler_cap()})
		"storage":
			return Loc.tf("UI_ESTATE_STORAGE", {"cap": NumberFormat.fmt(_e.base_capacity())})
		"seller":
			return Loc.tf("UI_ESTATE_SELLER", {"n": NumberFormat.fmt(_e.shop_units_per_hour()), "pct": NumberFormat.fmt(_e.shop_sell_pct()),
				"gold": NumberFormat.fmt(_e.shop_gold_cap_per_h())})
		"crate_gen":
			return Loc.tf("UI_ESTATE_VAULT", {"t": NumberFormat.fmt_time(_e.vault_interval_s())}) if lv > 0 else tr("UI_ESTATE_VAULT_NONE")
		"apprentices":
			var ap := Game.system("apprentices") as ApprenticeSystem
			return Loc.tf("UI_ESTATE_ACADEMY", {"slots": ap.slots_total() if ap != null else 0,
				"eff": NumberFormat.fmt(100.0 * (ap.efficiency() if ap != null else 0.0))})
		"guild":
			var mc := Game.system("mercenaries") as MercenarySystem
			var ex := Game.system("expeditions") as ExpeditionSystem
			return Loc.tf("UI_ESTATE_TAVERN", {"roster": mc.roster_cap() if mc != null else 0, "exp": ex.concurrent_cap() if ex != null else 0})
	return ""


## Tooltip della riga di produzione: grado e tier massimo dei produttori, il testo intero per gli altri edifici.
func _info_tip(bid: String, d: Dictionary, lv: int) -> String:
	if str(d.type) == "producer" and lv > 0 and _e.product_of(bid) != "":
		return Loc.tf("UI_F9_ES_PROD_TIP", {"g": _e.grade_of(bid), "t": _e.tier_limit(bid)})
	return _info_text(bid, d, lv)          # gli altri edifici: la riga intera (sulla carta può essere accorciata con «…»)


## Edificio bloccato: dice quale missione lo sblocca e porta lì (G37).
func _locked_bbcode(d: Dictionary) -> String:
	var qid := str(d.get("unlock", {}).get("quest", ""))
	var t := ReqLink.target_for_quest(qid)
	if t.is_empty():
		return tr("UI_ESTATE_LOCKED")
	var qname := Loc.t(DataRegistry.get_def("quests", qid).get("title", qid))
	return tr("UI_ESTATE_LOCKED") + "  " + ReqLink.bbcode(Loc.tf("UI_UIB_REQ_QUEST_LINK", {"quest": qname}), t)


## Materiali del prossimo livello (l'oro è sul pulsante): verdi se ci sono, rossi e cliccabili se mancano; più il motivo dei coloni.
func _cost_bbcode(cost: Dictionary, reason: String) -> String:
	var missing: Array = []
	for it in cost.items:
		var have := _bank.count(str(it)) if _bank != null else 0
		if have < int(cost.items[it]):
			missing.append(it)
	var s := ""
	if not missing.is_empty():
		var first := str(missing[0])
		var piece := ReqText.piece(first, int(cost.items[first]), _bank.count(first) if _bank != null else 0).replace("[", "[lb]")
		s = tr("UI_F9_ES_MISSING") + " " + ReqLink.bbcode(piece, ReqLink.target_for_item(first), COL_BAD)      # manca: porta a dove si ottiene
		if missing.size() > 1:
			s += " [color=%s]+%d[/color]" % [COL_BAD, missing.size() - 1]
	if reason == "UI_ESTATE_REASON_SETTLERS":
		s += ("  " if s != "" else "") + "[color=%s]%s[/color]" % [COL_BAD, tr(reason)]
	return s


## Perché non si può migliorare, con le quantità: «Ti mancano 120 oro: ne servono 500, ne hai 380» / «Ti mancano 3 Asse: ne servono 10, ne hai 7».
func _why_text(reason: String, cost: Dictionary) -> String:
	if reason == "UI_ESTATE_REASON_GOLD" and _bank != null:
		return ReqText.gold_sentence(int(cost.gold), int(_bank.gold()))
	if reason == "UI_ESTATE_REASON_MATERIALS" and _bank != null:
		var lines := PackedStringArray()
		for it in cost.items:
			var have := int(_bank.count(str(it)))
			if have < int(cost.items[it]):
				lines.append(ReqText.missing_sentence(str(it), int(cost.items[it]), have))
		if not lines.is_empty():
			return "\n".join(lines)
	return tr(reason)


## Tutti i materiali del prossimo livello, con quanti ne hai (tooltip del pulsante).
func _cost_tip(cost: Dictionary) -> String:
	var lines := PackedStringArray()
	for it in cost.items:
		var have := _bank.count(str(it)) if _bank != null else 0
		lines.append("%s %s" % ["✓" if have >= int(cost.items[it]) else "✗", ReqText.piece(str(it), int(cost.items[it]), have)])
	return "\n".join(lines)


func close() -> void:
	if _pantry_tween != null:
		_pantry_tween.kill()
