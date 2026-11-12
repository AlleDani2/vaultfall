extends GameScreen
## Deposito (docs/16, docs/07 §7): griglia di icone virtualizzata (F16; la lista è la vista alternativa), filtri per categoria, ricerca, ordinamento, dettagli,
## blocco/sblocco. Solo presentazione: legge e comanda BankSystem (Game.system("bank")). Aggiornata a ≤10 Hz
## da MainScreen; la lista si ricostruisce solo se il Deposito, i filtri o la lingua sono cambiati.
## F17 (docs/ui_redesign/02 §5.1–§5.9): barra delle schede (BankTabsBar: Tutto, Armeria, schede del giocatore, Risultati della
## ricerca), modalità selezione / vendita con UN SOLO motore (`_selection`, stato solo UI, mai salvato), vendita a due passaggi
## (SellDialog.setup_selection), ricerca con attesa, accenti, parole in AND e operatori, tasti locali (ShortcutMap.resolve_bank).

const ROW_H := 36.0
const ICON_PX := 28
const DETAIL_ICON_PX := 64
## Griglia (F16, doc 02 §5.3): passo = cella + 4 px. Sotto COMFORT_MIN_W di larghezza utile la densità «auto» è compatta.
const COMFORT_MIN_W := 1100.0
const WHEEL_ROWS_LIST := 3
const MARKET_TOKEN := "feature:market"
## Gruppi del filtro: id, chiave del testo, categorie dei dati (le non elencate vanno in «Altro»).
const GROUPS: Array[Dictionary] = [
	{"id": "all", "key": "UI_BANK_GROUP_ALL", "cats": []},
	{"id": "gear", "key": "UI_BANKG_GROUP_ARMORY", "cats": ["equipment", "tool"]},      # F15: l'Armeria non occupa Spazio
	{"id": "materials", "key": "UI_BANK_GROUP_MATERIALS", "cats": ["material", "seed"]},
	{"id": "supplies", "key": "UI_BANK_GROUP_SUPPLIES", "cats": ["food", "potion", "consumable", "ammo"]},
	{"id": "crates", "key": "UI_BANK_GROUP_CRATES", "cats": ["crate", "key", "openable"]},
	{"id": "collectibles", "key": "UI_BANK_GROUP_COLLECTIBLES", "cats": ["skin", "cosmetic", "relic", "glyph"]},
	{"id": "other", "key": "UI_BANK_GROUP_OTHER", "cats": []},
]
const SORTS: Array[Dictionary] = [
	{"id": "recent", "key": "UI_BANK_SORT_RECENT"},
	{"id": "name", "key": "UI_BANK_SORT_NAME"},
	{"id": "value", "key": "UI_BANK_SORT_VALUE"},
	{"id": "tier", "key": "UI_BANK_SORT_TIER"},
	{"id": "worn", "key": "UI_EQ_BANK_SORT_WORN"},          # FEEDBACK EQUIP-UI: gli indossati in cima
	{"id": "cat", "key": "UI_BANKG_SORT_CAT"},              # F17 (doc 02 §5.6)
	{"id": "qty", "key": "UI_BANKG_SORT_QTY"},
]
const ARMORY := BankTabsBar.ARMORY
const RESULTS := BankTabsBar.RESULTS
## Modalità della selezione (doc 02 §5.5): "" nessuna, "select" (Sposta / Blocca / Vendi…), "sell" (solo vendibili, barra ambra).
const MODE_SELECT := "select"
const MODE_SELL := "sell"
## Gruppi proposti da «Crea schede suggerite» (id di GROUPS; i nomi sono le chiavi bilingui dei gruppi).
const SUGGESTED_GROUPS: PackedStringArray = ["materials", "supplies", "crates", "collectibles"]
const STAT_KEYS := {
	"armor": "UI_BANK_STAT_ARMOR", "ward": "UI_BANK_STAT_WARD", "hp": "UI_BANK_STAT_HP", "ap": "UI_BANK_STAT_AP",
	"evasion": "UI_BANK_STAT_EVASION", "accuracy": "UI_BANK_STAT_ACCURACY", "int": "UI_BANK_STAT_INT",
	"dex": "UI_BANK_STAT_DEX", "str": "UI_BANK_STAT_STR", "vit": "UI_BANK_STAT_VIT", "crit_chance": "UI_BANK_STAT_CRIT",
}
const QUALITY_KEYS := {
	"normal": "UI_BANK_Q_NORMAL", "fine": "UI_BANK_Q_FINE", "excellent": "UI_BANK_Q_EXCELLENT",
	"masterwork": "UI_BANK_Q_MASTERWORK",
}

var _bank: BankSystem
var _entries: Array[Dictionary] = []
var _rev := -1
var _locale := ""
var _dirty := true
var _selected := ""             # chiave dell'elemento scelto: uid (istanza) o def_id (pila)
var _group := "all"
var _sort := "recent"
var _descending := true
var _query := ""
var _only_locked := false
var _only_worn := false
var _eq_sig := ""
var _detail_sig := ""
var _detail_retry := false
var _detail_b: RefCounted          # BankDetail (caricato al primo bisogno)
var _name_cache: Dictionary = {}

var _slots_label: Label
var _value_label: Label
var _help_btn: Button
var _full_label: Label
var _full_row: HBoxContainer
var _carro: Control                # CarroPanel, creato solo quando serve (Carro non vuoto o Deposito pieno)
var _expand_btn: Button
var _full_expand_btn: Button
var _cap_sig := -1
var _cat_btn: MenuButton          # «Categorie ▾»: i gruppi del filtro (Tutte, Materiali, Provviste…)
var _search: LineEdit
var _sort_opt: OptionButton
var _filters_btn: MenuButton       # «Filtri ▾ (n)»: Decrescente, Solo bloccati, Solo equipaggiati
var _sell_btn: MenuButton          # «Vendita ▾»: in blocco, automatica, doppioni
var _detail_panel: PanelContainer  # compare solo con un oggetto selezionato
var _list: VirtualList
var _grid: VirtualGrid             # F16: vista a griglia (predefinita); _list resta la vista alternativa
var _view := "grid"                # "grid" | "list" (Settings.bank_view)
var _compact := false              # densità effettiva della griglia
var _view_btns: Dictionary = {}    # "grid"/"list" -> Button
var _density_btn: Button
var _armory_hint: Label
var _rar_cache: Dictionary = {}
var _empty_label: Label
var _empty_pic: TextureRect
var _detail_box: VBoxContainer
var _group_buttons: Dictionary = {}
# F17: schede, selezione, ricerca
var _tab := ""                     # "" = Tutto, ARMORY, oppure l'id di una scheda del giocatore ("t_0001")
var _tab_scroll: Dictionary = {}   # scheda -> prima riga visibile (si ritrova tornando dai Risultati)
var _fixed_sort: Dictionary = {}   # ordinamento di Tutto e Armeria per la sessione (le schede del giocatore lo salvano)
var _mode := ""
var _selection: Dictionary = {}    # chiave della voce -> {def, uid}
var _pq: Dictionary = {"words": [], "ops": {}}
var _names_cache: Dictionary = {}  # tabelle di nomi per gli operatori della ricerca (per lingua)
var _tabs_bar: BankTabsBar
var _mode_holder: VBoxContainer
var _mode_bar: PanelContainer
var _mode_label: Label
var _mode_exit: Button
var _action_bar: HFlowContainer
var _sel_label: Label
var _move_btn: Button
var _lock_sel_btn: Button
var _sell_sel_btn: Button
var _welcome: PanelContainer
var _empty_btn: Button
var _debounce: Timer
var last_sell_dialog: Window       # ultima anteprima aperta (per i test e la verifica)
var last_tab_dialog: Window
## Finestre caricate solo quando servono (costruzione del Deposito dentro il budget del doc 02 §7.1).
const TAB_DIALOG := "res://src/ui/screens/BankTabDialog.gd"
const SELL_DIALOG := "res://src/ui/screens/SellDialog.gd"
const ITEM_ACTIONS := "res://src/ui/ItemActions.gd"
const ITEM_TIP_BUTTON := "res://src/ui/ItemTipButton.gd"     # solo la vista a lista: la griglia (predefinita) non li usa
var last_popup: PopupMenu

## Voci dei menù «Filtri» e «Vendita» (id dell'elemento nel popup).
const FILTER_DESC := 0
const FILTER_LOCKED := 1
const FILTER_WORN := 2
const SELL_MULTI := 0
const SELL_AUTO := 1
const SELL_DUPES := 2
const SELL_SELECT := 10          # voci di «Azioni ▾» che prima erano pulsanti nella barra
const SELL_MODE := 11
const BAR_CELLS := 10


func open(_params: Dictionary) -> void:
	_bank = Game.system("bank") as BankSystem
	_build()
	_dirty = true
	refresh()


func close() -> void:
	exit_mode()                                  # F17: la modalità vendita/selezione non sopravvive al cambio di schermata
	_name_cache.clear()


func refresh() -> void:
	if _bank == null or _list == null:
		return
	if Loc.locale() != _locale:
		_locale = Loc.locale()
		_name_cache.clear()
		_names_cache = {}                        # nomi degli operatori della ricerca: si rifanno nella lingua nuova
		_dirty = true
	if _bank.revision != _rev:
		_rev = _bank.revision
		_dirty = true
	var cap_now := _bank.capacity()                          # missione riscattata, reliquia, Costellazione: cambia il tetto senza toccare il Deposito
	if cap_now != _cap_sig:
		_cap_sig = cap_now
		_dirty = true
	var eqs := _equip_signature()
	if eqs != _eq_sig:                       # indossare/togliere non cambia il Deposito ma cambia i marcatori «E»
		_eq_sig = eqs
		_dirty = true
	if not _dirty and not _detail_retry:
		return
	if _dirty:
		_dirty = false
		_refresh_header()
		_rebuild_entries()
		_refresh_armory_button()                 # dopo le voci: «Risultati (n)» conta ciò che si vede
	_refresh_detail()


## Firma di ciò che l'Eroe indossa o ha assegnato (equipaggiamento, utensili, munizioni, slot del cibo).
func _equip_signature() -> String:
	var cb := Game.system("combat") as CombatSystem
	return "%s|%s" % [JSON.stringify(GameState.data.get("equipment", {})), JSON.stringify(cb.food_slots()) if cb != null else ""]


# ------------------------------------------------------------------ costruzione

func _build() -> void:
	for c in get_children():
		c.free()
	_view = str(Settings.get_value("bank_view"))
	if not Settings.BANK_VIEWS.has(_view):
		_view = "grid"
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var head := HBoxContainer.new()                    # titolo a sinistra; spazi, «Espandi» e valore a destra e, se manca posto, a capo
	head.add_theme_constant_override("separation", 16)
	root.add_child(head)
	head.add_child(ScreenKit.title_style(_label("UI_BANK_TITLE", &"TitleLabel")))
	var head_r := HFlowContainer.new()
	head_r.name = "HeadFlow"
	head_r.alignment = FlowContainer.ALIGNMENT_END
	head_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_r.add_theme_constant_override("h_separation", 16)
	head_r.add_theme_constant_override("v_separation", 4)
	head.add_child(head_r)
	_slots_label = _dyn_label(&"MonoLabel")
	head_r.add_child(_slots_label)
	_expand_btn = _make_expand_button("ExpandButton")           # «Espandi Deposito»: sempre in vista, col prezzo del prossimo spazio
	head_r.add_child(_expand_btn)
	TutorialTargets.mark(_expand_btn, "bank_expand_btn")
	_value_label = _dyn_label(&"MonoLabel")
	head_r.add_child(_value_label)
	_help_btn = Button.new()                          # «?»: la regola dello spazio nel Manuale (le valute stanno nella barra alta)
	_help_btn.name = "HelpButton"
	_help_btn.text = "UI_BANK_HELP"
	_help_btn.tooltip_text = "UI_BANK_HELP_TIP"
	_help_btn.flat = true
	_help_btn.pressed.connect(_on_help)
	head_r.add_child(_help_btn)

	_full_row = HBoxContainer.new()                              # avviso «quasi pieno / pieno» con il rimedio a un clic
	_full_row.add_theme_constant_override("separation", 12)
	root.add_child(_full_row)
	_full_label = _label("UI_BANK_FULL_BANNER", &"MutedLabel")
	_full_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_full_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_row.add_child(_full_label)
	_full_expand_btn = _make_expand_button("ExpandBannerButton")
	_full_row.add_child(_full_expand_btn)
	_carro = null                                                # il pannello del Carro si costruisce al primo bisogno (_ensure_carro)
	_build_welcome(root)

	_tabs_bar = BankTabsBar.new()                                # F17: Tutto, Armeria, schede del giocatore, [+], [⋮]
	_tabs_bar.icon_for = _icon_for
	_tabs_bar.tab_chosen.connect(_on_tab_chosen)
	_tabs_bar.create_requested.connect(open_create_tab)
	_tabs_bar.edit_requested.connect(_on_tab_edit)
	_tabs_bar.move_requested.connect(_on_tab_move)
	_tabs_bar.keys_dropped.connect(_on_keys_dropped)
	_tabs_bar.suggested_requested.connect(open_suggested)
	root.add_child(_tabs_bar)
	TutorialTargets.mark(_tabs_bar, "bank_tabs")                # passo f_bank_tabs

	# Rapporto grafica 08 punto 10: i comandi del Deposito stanno in DUE righe prima del primo oggetto: la barra delle schede
	# (Tutto, Armeria, schede del giocatore) e UNA barra compatta con ricerca · categoria · ordine · filtri · azioni · vista.
	# Categorie, vendita e selezione sono menù (nessuna funzione tolta); se manca posto la barra va a capo (720p, scala 125%).
	var tools := HFlowContainer.new()
	tools.name = "ToolsFlow"
	tools.add_theme_constant_override("h_separation", 8)
	tools.add_theme_constant_override("v_separation", 4)
	root.add_child(tools)
	_search = LineEdit.new()
	_search.placeholder_text = "UI_BANK_SEARCH"
	_search.tooltip_text = "UI_BANKG_SEARCH_TIP"                # operatori cat: t: lock: q: rar:
	_search.clear_button_enabled = true
	_search.custom_minimum_size.x = 200
	_search.text_changed.connect(_on_query_typed)
	tools.add_child(_search)
	_debounce = Timer.new()                                      # F17: la ricerca parte dopo l'ultimo tasto (dati: search_debounce_ms)
	_debounce.one_shot = true
	_debounce.wait_time = maxf(0.01, float(_bank.ui_rules().get("search_debounce_ms", 0)) / 1000.0)
	_debounce.timeout.connect(func() -> void: _on_query(_search.text))
	add_child(_debounce)
	_cat_btn = MenuButton.new()                      # categorie: era una riga di pulsanti, ora un menù con spunta sulla scelta
	_cat_btn.name = "CategoryMenu"
	_cat_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var cpop := _cat_btn.get_popup()
	for g in GROUPS:
		if g.id == "gear":
			continue                                 # F17: l'Armeria è la seconda scheda della barra
		cpop.add_radio_check_item(tr("UI_BANKG_CAT_ALL" if g.id == "all" else g.key), _group_menu_id(str(g.id)))
	cpop.id_pressed.connect(func(mid: int) -> void: _on_group(_group_of_menu_id(mid)))
	tools.add_child(_cat_btn)
	_sort_opt = OptionButton.new()
	_sort_opt.tooltip_text = tr("UI_BANK_SORT")      # «Ordina per»: la scritta fissa non occupa più spazio
	for sd in SORTS:
		_sort_opt.add_item(sd.key)
	_sort_opt.item_selected.connect(_on_sort)
	tools.add_child(_sort_opt)
	_filters_btn = MenuButton.new()                  # «Decrescente», «Solo bloccati», «Solo equipaggiati» in un solo menù
	_filters_btn.name = "FiltersMenu"
	_filters_btn.tooltip_text = tr("UI_BANK_FILTERS_TIP")
	_filters_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var fpop := _filters_btn.get_popup()
	fpop.hide_on_checkable_item_selection = false
	fpop.add_check_item(tr("UI_BANK_DESC"), FILTER_DESC)
	fpop.add_check_item(tr("UI_BANK_ONLY_LOCKED"), FILTER_LOCKED)
	fpop.add_check_item(tr("UI_EQ_BANK_FILTER_WORN"), FILTER_WORN)
	fpop.id_pressed.connect(_on_filter_item)
	tools.add_child(_filters_btn)
	_sell_btn = MenuButton.new()                     # «Azioni ▾»: selezione, modalità vendita, vendita in blocco/automatica, doppioni
	_sell_btn.name = "SellMenu"
	_sell_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var spop := _sell_btn.get_popup()
	spop.hide_on_checkable_item_selection = true
	spop.add_item(tr("UI_UIA_SELL_BTN"), SELL_MULTI)
	spop.add_item(tr("UI_UIA_AUTO_BTN"), SELL_AUTO)
	spop.add_item("", SELL_DUPES)                    # testo e stato in _refresh_dupes_button
	spop.set_item_tooltip(SELL_MULTI, tr("UI_UIA_SELL_BTN_TIP"))
	spop.set_item_tooltip(SELL_AUTO, tr("UI_UIA_AUTO_BTN_TIP"))
	spop.add_separator()
	spop.add_check_item(tr("UI_BANKG_SELECT"), SELL_SELECT)          # F17: modalità selezione (S) e modalità vendita (V)
	spop.add_check_item(tr("UI_BANKG_SELLMODE"), SELL_MODE)
	spop.set_item_tooltip(spop.get_item_index(SELL_SELECT), tr("UI_BANKG_SELECT_TIP"))
	spop.id_pressed.connect(_on_sell_item)
	tools.add_child(_sell_btn)
	var vb := HBoxContainer.new()                    # F16: interruttore Griglia / Lista (preferenza salvata nelle Impostazioni)
	vb.name = "ViewToggle"
	vb.add_theme_constant_override("separation", 0)
	var vg := ButtonGroup.new()
	for v in ["grid", "list"]:
		var b := Button.new()
		b.name = "View_" + v
		b.text = "UI_BANKG_VIEW_GRID" if v == "grid" else "UI_BANKG_VIEW_LIST"
		b.tooltip_text = "UI_BANKG_VIEW_TIP"
		b.toggle_mode = true
		b.button_group = vg
		b.button_pressed = v == _view
		b.pressed.connect(_on_view.bind(v))
		vb.add_child(b)
		_view_btns[v] = b
	_density_btn = Button.new()                      # densità della griglia: comoda 64 px / compatta 32 px (terzo segmento della vista)
	_density_btn.name = "DensityButton"
	_density_btn.text = "UI_BANKG_DENSITY_COMPACT"
	_density_btn.tooltip_text = "UI_BANKG_DENSITY_TIP"
	_density_btn.toggle_mode = true
	_density_btn.toggled.connect(_on_density)
	vb.add_child(_density_btn)
	tools.add_child(vb)
	_update_menu_labels()
	_armory_hint = _label("UI_BANKG_ARMORY_LIST_HINT", &"MutedLabel")     # nell'Armeria la lista confronta meglio
	_armory_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_armory_hint.visible = false
	root.add_child(_armory_hint)
	_mode_holder = VBoxContainer.new()                # barre della selezione: si costruiscono al primo uso (BankTabDialog)
	_mode_holder.name = "ModeHolder"
	root.add_child(_mode_holder)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 5.0
	left.custom_minimum_size = Vector2(200, 160)               # la lista non sparisce mai: sotto questa altezza scorre la schermata
	body.add_child(left)
	_grid = VirtualGrid.new()
	_grid.name = "Grid"
	_grid.make_cell = _make_cell
	_grid.bind_cell = _bind_cell
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.add_child(_grid)
	_list = VirtualList.new()
	_list.row_height = ROW_H
	_list.wheel_rows = WHEEL_ROWS_LIST
	_list.make_row = _make_row
	_list.bind_row = _bind_row
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.add_child(_list)
	_apply_density()
	_apply_view_visibility()
	_empty_label = _label("UI_BANK_EMPTY", &"MutedLabel")
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_empty_label)
	_empty_pic = TextureRect.new()                     # scaffale vuoto sotto la scritta
	_empty_pic.texture = UiKit.texture("empty_shelf")
	_empty_pic.stretch_mode = TextureRect.STRETCH_KEEP
	_empty_pic.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_empty_pic.position.y = 48.0
	_empty_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_empty_pic)
	_empty_btn = Button.new()                          # azione dello stato vuoto (doc 02 §5.9): Cancella ricerca, Azzera filtri, Esci…
	_empty_btn.name = "EmptyAction"
	_empty_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_empty_btn.position.y = 160.0
	_empty_btn.visible = false
	_empty_btn.pressed.connect(_on_empty_action)
	left.add_child(_empty_btn)

	var panel := PanelContainer.new()
	_detail_panel = panel
	panel.visible = false                                      # senza oggetto scelto la lista usa tutta la larghezza
	panel.theme_type_variation = &"ContentPanel"
	panel.name = "DetailPanel"
	panel.custom_minimum_size.x = 260                          # si adatta: 2/7 dello spazio con un minimo basso; il contenuto scorre
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.0
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_detail_box)
	if not resized.is_connected(_on_screen_resized):
		resized.connect(_on_screen_resized)


func _label(key: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = key
	if variation != &"":
		l.theme_type_variation = variation
	return l


## Etichetta con testo già pronto (numeri, nomi dai dati): niente traduzione automatica.
func _dyn_label(variation: StringName = &"") -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	return l


# ------------------------------------------------------------------ griglia (F16)

func _make_cell() -> Control:
	var c := ItemCell.new()
	c.pressed.connect(_on_cell_pressed.bind(c))
	c.activated.connect(_on_cell_activated.bind(c))
	c.context_requested.connect(_on_row_context.bind(c))
	c.set_drag_forwarding(_cell_drag.bind(c), Callable(), Callable())     # F17: trascina sulle schede (alternativa: «Sposta in…»)
	return c


func _bind_cell(cell: Control, index: int) -> void:
	var e: Dictionary = _entries[index]
	var ic := cell as ItemCell
	ic.set_meta("key", e.key)
	var uid := str(e.uid)
	var chosen: bool = _selection.has(e.key) if _mode != "" else e.key == _selected
	var veiled: bool = _mode != "" and not is_selectable(e)
	ic.setup(str(e.def), _bank.get_instance(uid) if uid != "" else {}, _icon_for(e.def),
		"" if uid != "" else NumberFormat.fmt_cell(e.qty), int(e.tier), int(e.rank), bool(e.locked), str(e.worn) != "",
		chosen, _rarity_color(str(e.rar)), veiled, _compact)
	var lines := PackedStringArray()
	if uid == "":
		lines.append(Loc.tf("UI_BANKG_QTY_EXACT", {"n": NumberFormat.group_int(float(e.qty), Loc.locale().substr(0, 2))}))
	if veiled:
		lines.append(tr(_unselectable_reason(e)))                 # il motivo del velo si legge nel tooltip (mai solo il colore)
	elif _mode != "" and chosen:
		lines.append(tr("UI_BANKG_CELL_SELECTED"))
	if _results_mode() or _tab == "":
		var tn := _tab_name_of(e)                                  # Risultati: la scheda di origine di ogni casella
		if tn != "":
			lines.append(Loc.tf("UI_BANKG_CELL_TAB", {"name": tn}))
	ic.qty_exact = "\n".join(lines)


func _rarity_color(rar: String) -> Color:
	if rar.is_empty():
		return ItemCell.BORDER
	if not _rar_cache.has(rar):
		_rar_cache[rar] = CrateUi.rarity_color(rar)
	return _rar_cache[rar]


## Densità effettiva: «auto» = comoda da COMFORT_MIN_W px utili in su, compatta sotto; le altre due sono scelte dal giocatore.
func _apply_density() -> void:
	var pref := str(Settings.get_value("bank_density"))
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	_compact = pref == "compact" or (pref == "auto" and w < COMFORT_MIN_W)
	if _density_btn != null:
		_density_btn.set_pressed_no_signal(_compact)
		_density_btn.visible = _view == "grid"
	var cs := ItemCell.COMPACT if _compact else ItemCell.COMFORT
	if _grid != null:
		_grid.set_cell_size(cs.x + 4.0, cs.y + 4.0)


func _on_screen_resized() -> void:
	if _grid == null:
		return
	var was := _compact
	_apply_density()
	if _compact != was:
		_grid.rebind()


func _on_view(v: String) -> void:
	if v == _view:
		return
	_view = v
	Settings.set_value("bank_view", v)
	_apply_view_visibility()
	_apply_density()
	_view_set_count()


func _on_density(on: bool) -> void:
	Settings.set_value("bank_density", "compact" if on else "comfortable")
	_apply_density()
	_grid.rebind()


func _apply_view_visibility() -> void:
	_grid.visible = _view == "grid"
	_list.visible = _view == "list"
	if _density_btn != null:
		_density_btn.visible = _view == "grid"
	for v in _view_btns:
		(_view_btns[v] as Button).set_pressed_no_signal(v == _view)
	_refresh_armory_hint()


func _refresh_armory_hint() -> void:
	if _armory_hint != null:
		_armory_hint.visible = _view == "grid" and _group == "gear"


## Solo la vista attiva ha voci (e quindi nodi): l'altra resta vuota, costo zero.
func _view_set_count() -> void:
	_grid.set_count(_entries.size() if _view == "grid" else 0)
	_list.set_count(_entries.size() if _view == "list" else 0)
	_view_rebind()


func _view_rebind() -> void:
	if _view == "grid":
		_grid.rebind()
	else:
		_list.rebind()


func _on_cell_pressed(cell: Control) -> void:
	if _mode != "":
		toggle_key(str(cell.get_meta("key", "")))            # in modalità selezione il clic inverte la selezione
		return
	_selected = str(cell.get_meta("key", ""))
	_view_rebind()
	_refresh_detail()


## Doppio clic / Invio sulla voce già scelta: azione predefinita SICURA. Mai vende, mai scarta. Per ora: equipaggia un pezzo
## dell'Armeria; per tutto il resto la voce è già scelta e il dettaglio mostra le azioni.
func _on_cell_activated(cell: Control) -> void:
	if _mode != "":
		toggle_key(str(cell.get_meta("key", "")))            # Invio / A sulla voce già scelta: la toglie (mai vendere)
		return
	_on_cell_pressed(cell)
	var e := _selected_entry()
	if e.is_empty() or str(e.uid) == "" or not DataRegistry.item(str(e.def)).has("equipment") or str(e.worn) != "":
		return
	var acts: GDScript = load(ITEM_ACTIONS) as GDScript
	for a: Dictionary in acts.call("available", str(e.def), str(e.uid)):
		if a.id == "equip" and bool(a.get("enabled", true)):
			acts.call("perform", "equip", str(e.def), str(e.uid))
			_mark_dirty()
			return


func _make_row() -> Control:
	var b: Button = (load(ITEM_TIP_BUTTON) as GDScript).new()          # tooltip dell'oggetto con confronto e menù del tasto destro (UI-A G25)
	b.connect("context_requested", _on_row_context.bind(b))
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = false
	var h := HBoxContainer.new()
	h.name = "H"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 10)
	b.add_child(h)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var badge := PanelContainer.new()          # marcatore «E» (equipaggiato): riquadro con bordo, sempre visibile
	badge.name = "Worn"
	badge.theme_type_variation = &"SlotCommon"
	badge.self_modulate = Color(1.0, 0.82, 0.4)
	badge.custom_minimum_size = Vector2(26, 26)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_l := Label.new()
	badge_l.text = "UI_EQ_BANK_BADGE"
	badge_l.add_theme_font_size_override("font_size", UiType.NOTE)
	badge_l.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
	badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_l)
	h.add_child(badge)
	var name_l := _dyn_label()
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(name_l)
	var tag_l := _dyn_label(&"MutedLabel")     # «Elmo», «Secondo anello»… o il codice «#14» che distingue due pezzi uguali
	tag_l.name = "Tag"
	tag_l.add_theme_font_size_override("font_size", UiType.NOTE)
	tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tag_l)
	var lock_l := _label("UI_BANK_LOCKED_TAG", &"MutedLabel")
	lock_l.name = "Lock"
	lock_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(lock_l)
	var qty_l := _dyn_label(&"MonoLabel")
	qty_l.name = "Qty"
	qty_l.custom_minimum_size.x = 90
	qty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(qty_l)
	b.pressed.connect(_on_row_pressed.bind(b))
	return b


func _bind_row(row: Control, index: int) -> void:
	var e: Dictionary = _entries[index]
	row.set_meta("key", e.key)
	row.call("set_item", str(e.def), _bank.get_instance(str(e.uid)) if str(e.uid) != "" else {})
	var h: Node = row.get_node("H")
	h.get_node("Icon").texture = _icon_for(e.def)
	h.get_node("Name").text = e.label
	h.get_node("Worn").modulate.a = 1.0 if str(e.worn) != "" else 0.0     # il posto resta riservato: i nomi restano allineati
	var tag_l: Label = h.get_node("Tag")
	var tag := ""
	if str(e.worn) != "":
		tag = str(e.worn_name)
		tag_l.add_theme_color_override("font_color", Color(0.93, 0.76, 0.42))
	else:
		tag = str(e.get("code", ""))
		tag_l.remove_theme_color_override("font_color")
	tag_l.text = tag
	tag_l.visible = tag != ""
	h.get_node("Lock").visible = e.locked
	h.get_node("Qty").text = NumberFormat.fmt(e.qty)
	var chosen: bool = _selection.has(e.key) if _mode != "" else e.key == _selected
	row.modulate = Color(1.0, 0.92, 0.6, 1) if chosen else Color(1, 1, 1, 1)
	if _mode != "" and not is_selectable(e):
		row.modulate = Color(0.55, 0.55, 0.55, 1)                 # velo nella lista: il motivo è nel dettaglio e nel menù


# ------------------------------------------------------------------ dati della lista

func _item_name(def_id: String) -> String:
	return _info(def_id).name


## Dati fissi di un oggetto usati dall'elenco (nome, nome minuscolo, valore, grado, gruppo del filtro, equipaggiabile):
## calcolati una volta per definizione, non una per riga a ogni ricostruzione. Si svuota cambiando lingua.
func _info(def_id: String) -> Dictionary:
	var c: Variant = _name_cache.get(def_id)
	if c != null:
		return c
	var def: Dictionary = DataRegistry.item(def_id)
	var nm := Loc.t(def.get("name", {}))
	var info := {"name": nm, "sort_name": nm.to_lower(), "value": float(def.get("value", 0)), "tier": int(def.get("tier", 0)),
		"group": _group_of(def), "equip": def.has("equipment"), "rar": str(def.get("rarity", "")),
		"cat": str(def.get("category", ""))}             # "norm" (nome per la ricerca) si calcola alla prima ricerca
	_name_cache[def_id] = info
	return info


func _group_of(def: Dictionary) -> String:
	var cat := str(def.get("category", ""))
	for g in GROUPS:
		if g.cats.has(cat):
			return g.id
	return "other"


func _icon_for(def_id: String) -> Texture2D:
	var path := str(DataRegistry.item(def_id).get("icon", ""))
	var kind := path.get_base_dir().get_file()
	return IconLib.icon(kind if not kind.is_empty() else "items", def_id)


func _quality_label(q: String) -> String:
	return tr(QUALITY_KEYS[q]) if QUALITY_KEYS.has(q) else q


func _rebuild_entries() -> void:
	_entries.clear()
	var q := _query.strip_edges().to_lower()
	_pq = BankSystem.parse_search(_query, _search_names()) if not q.is_empty() else {"words": [], "ops": {}}
	var cb := Game.system("combat") as CombatSystem
	var food_slots: Array = cb.food_slots() if cb != null else []
	var ammo_def := cb.equipped("ammo") if cb != null else ""
	for def_id in _bank.state.stacks:
		var info := _info(def_id)
		var locked := _bank.is_def_locked(def_id)
		# pile in uso: il cibo assegnato agli slot e le munizioni indossate (il resto delle munizioni sta nello slot dell'Eroe)
		var worn_name := ""
		var worn_tip := ""
		if food_slots.has(def_id):
			var n := food_slots.find(def_id) + 1
			worn_name = Loc.tf("UI_EQ_FOOD_SLOT", {"n": n})
			worn_tip = Loc.tf("UI_EQ_BANK_FOOD_BADGE_TIP", {"n": n})
		elif def_id == ammo_def and not def_id.is_empty():
			worn_name = tr("UI_HERO_SLOT_AMMO")
			worn_tip = Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": worn_name})
		var akey := BankSystem.tab_key(def_id, "")
		if not _passes(info, locked, q, not worn_name.is_empty(), akey, ""):
			continue
		_entries.append({"key": def_id, "akey": akey, "def": def_id, "uid": "", "qty": int(_bank.state.stacks[def_id]), "cat": info.cat,
			"label": info.name, "sort_name": info.sort_name, "locked": locked,
			"value": info.value, "tier": info.tier, "recent": _bank.recency_of_stack(def_id),
			"worn": "food" if food_slots.has(def_id) else ("ammo" if def_id == ammo_def and not def_id.is_empty() else ""),
			"worn_name": worn_name, "worn_tip": worn_tip, "worn_n": 1 if not worn_name.is_empty() else 0, "code": "",
			"rank": 0, "rar": info.rar})
	# nomi uguali (due «Manopole di Rame» normali): il codice breve «#14» le distingue sempre, in elenco e nel dettaglio
	var labels: Array[String] = []                 # un'etichetta per istanza, calcolata una volta sola
	var label_count: Dictionary = {}
	for inst in _bank.state.instances:
		var lab := ItemLabel.label_from(_item_name(inst.def), inst)
		labels.append(lab)
		label_count[lab] = int(label_count.get(lab, 0)) + 1
	var worn_map: Dictionary = cb.worn_slot_map() if cb != null else {}
	var slot_names: Dictionary = {}                 # slot -> [testo, suggerimento] (pochi slot: si traducono una volta)
	var idx := 0
	for inst in _bank.state.instances:
		var label := labels[idx]
		idx += 1
		var info := _info(inst.def)
		var worn_slot := str(worn_map.get(inst.uid, ""))
		if not worn_slot.is_empty() and not slot_names.has(worn_slot):
			var sn := ItemLabel.slot_name(worn_slot)
			slot_names[worn_slot] = [sn, Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": sn})]
		var ukey := BankSystem.tab_key("", str(inst.uid))
		if not _passes(info, bool(inst.locked), q, not worn_slot.is_empty(), ukey, str(inst.get("quality", "")), str(inst.get("rarity", info.rar))):
			continue
		var dup: bool = info.equip and int(label_count.get(label, 0)) > 1
		var uid: String = inst.uid
		_entries.append({"key": uid, "akey": ukey, "def": inst.def, "uid": uid, "qty": 1, "label": label, "cat": info.cat,
			"sort_name": info.sort_name, "locked": bool(inst.locked), "value": info.value,
			"tier": info.tier, "recent": uid.substr(2).to_int(),
			"worn": worn_slot, "worn_name": slot_names[worn_slot][0] if not worn_slot.is_empty() else "",
			"worn_n": 1 if not worn_slot.is_empty() else 0,
			"worn_tip": slot_names[worn_slot][1] if not worn_slot.is_empty() else "",
			"code": ItemLabel.short_id(uid) if dup else "", "rank": int(inst.get("rank", 0)),
			"rar": str(inst.get("rarity", info.rar))})
	if _mode == MODE_SELL:                             # il motivo del velo: una volta per ricostruzione, non per cella disegnata
		var market := Game.system("market") as MarketSystem
		var open_m := GameState.has_unlock(MARKET_TOKEN)
		for e in _entries:
			e["why"] = SellRules.block_reason(_bank, market, str(e.def), str(e.uid), open_m)
	_sort_entries()
	_view_set_count()
	_refresh_empty_state()
	_refresh_mode_bars()


## Ordina `_entries` per il criterio scelto; a parità: nome, poi chiave (ordine totale, risultato deterministico).
## Si ordinano tuple [criterio, nome, chiave, posizione] con l'ordinamento nativo (molto più rapido di un confronto in GDScript).
func _sort_entries() -> void:
	var n := _entries.size()
	if n < 2:
		return
	var by_name := _sort == "name" or _sort == "cat"
	var field := "worn_n" if _sort == "worn" else _sort
	var tuples: Array = []
	tuples.resize(n)
	for i in n:
		var e: Dictionary = _entries[i]
		if by_name:
			tuples[i] = [e.sort_name, e.key, i] if _sort == "name" else [str(e.cat) + "|" + str(e.sort_name), e.key, i]
		else:
			var v: Variant = e[field]
			tuples[i] = [-v if _descending else v, e.sort_name, e.key, i]
	tuples.sort()
	if by_name and _descending:                       # nomi al contrario, ma a parità di nome la chiave resta crescente
		tuples.reverse()
		var s0 := 0
		while s0 < n:
			var s1 := s0 + 1
			while s1 < n and tuples[s1][0] == tuples[s0][0]:
				s1 += 1
			if s1 - s0 > 1:
				var run := tuples.slice(s0, s1)
				run.reverse()
				for k in run.size():
					tuples[s0 + k] = run[k]
			s0 = s1
	var sorted: Array[Dictionary] = []
	sorted.resize(n)
	for i in n:
		sorted[i] = _entries[(tuples[i] as Array).back()]
	_entries = sorted


func _passes(info: Dictionary, locked: bool, q: String, worn: bool, akey: String = "", quality: String = "", rar: String = "") -> bool:
	if _only_locked and not locked:
		return false
	if _only_worn and not worn:
		return false
	if not q.is_empty():
		# F17 (doc 02 §5.7): la ricerca attraversa TUTTE le schede e l'Armeria (scheda virtuale «Risultati»); gli altri filtri restano
		if not info.has("norm"):
			info["norm"] = BankSystem.search_norm(str(info.name))
		return BankSystem.search_matches(_pq, {"name": info.norm, "cat": info.cat, "tier": info.tier, "locked": locked,
			"q": quality, "rar": rar if rar != "" else str(info.rar)})
	if _group != "all" and info.group != _group:
		return false
	# F15 (R-SP-7): «Tutto» senza filtri = le caselle che occupano Spazio; l'Armeria sta nella sua scheda. Con «Solo equipaggiati»
	# invece «Tutto» attraversa anche l'Armeria.
	if _group == "all" and info.group == "gear" and not _only_worn:
		return false
	if _tab != "" and _tab != ARMORY and _bank.tab_of(akey) != _tab:
		return false                                       # scheda del giocatore: solo le voci assegnate a lei
	return true


# ------------------------------------------------------------------ intestazione e dettagli

## Pannello del Carro di Ritiro: creato (e compilato) solo la prima volta che il Deposito è pieno o il Carro non è vuoto.
func _ensure_carro() -> void:
	if _carro != null or _bank == null or not (_bank.overflow_count() > 0 or _bank.is_full()):
		return
	_carro = (load("res://src/ui/screens/CarroPanel.gd") as GDScript).new()
	_carro.changed.connect(_mark_dirty)
	_full_row.get_parent().add_child(_carro)
	_full_row.get_parent().move_child(_carro, _full_row.get_index() + 1)


func _refresh_header() -> void:
	_ensure_carro()
	var used := _bank.used_slots()
	var cap := _bank.capacity()
	var filled := clampi(roundi(float(BAR_CELLS) * float(used) / float(maxi(cap, 1))), 0, BAR_CELLS)
	if used > 0 and filled == 0:
		filled = 1
	_slots_label.text = Loc.tf("UI_BANK_SLOTS_BAR", {"bar": "▰".repeat(filled) + "▱".repeat(BAR_CELLS - filled),
		"used": NumberFormat.fmt(used), "cap": NumberFormat.fmt(cap)})
	_value_label.text = Loc.tf("UI_BANK_TOTAL_VALUE", {"v": NumberFormat.fmt(_bank.total_value())})
	_refresh_armory_button()
	_refresh_expand_buttons()
	_full_row.visible = _bank.nearly_full()                     # il Deposito PIENO lo racconta il pannello del Carro di Ritiro
	_refresh_welcome()
	_full_label.text = Loc.tf("UI_BANK_NEARLY_BANNER", {"used": NumberFormat.fmt(_bank.used_slots()), "cap": NumberFormat.fmt(_bank.capacity())})
	_refresh_dupes_button()
	_update_menu_labels()


## La barra delle schede (F17): «Armeria» porta il contatore (es. «Armeria 87/300»: l'equipaggiamento non conta come Spazio),
## «Tutto» le caselle che occupano Spazio, ogni scheda le sue caselle; «Risultati (n)» solo con una ricerca attiva.
func _refresh_armory_button() -> void:
	if _tabs_bar == null:
		return
	var at := Loc.tf("UI_BANKG_GROUP_ARMORY_N", {"used": NumberFormat.fmt(_bank.gear_used()), "cap": NumberFormat.fmt(_bank.gear_cap())})
	var tip := Loc.tf("UI_BANKG_GROUP_ARMORY_TIP", {"cap": NumberFormat.fmt(_bank.gear_cap())})
	var add_tip := tr("UI_BANKG_TAB_ADD_TIP") if _bank.can_add_tab() else Loc.tf("UI_BANKG_TAB_MAX", {"n": _bank.max_tabs()})
	_tabs_bar.update_bar(_bank.tabs(), _bank.tab_counts(), _bank.used_slots(), at, tip, _entries.size() if _results_mode() else -1,
		RESULTS if _results_mode() else _tab, _bank.can_add_tab(), add_tip)
	_group_buttons["gear"] = _tabs_bar.buttons.get(ARMORY)
	_cat_btn.visible = not _results_mode() and _tab != ARMORY            # categorie: non servono nell'Armeria né nei Risultati


func _selected_entry() -> Dictionary:
	for e in _entries:
		if e.key == _selected:
			return e
	return {}


## Firma dei dati che il dettaglio mostra: oggetto scelto, quantità, blocco, equipaggiamento, lingua. NON l'oro né il valore
## totale (cambiano a ogni azione completata): ricostruire il dettaglio distruggeva il menù a tendina aperto (Tomo dell'Esperienza).
func _detail_signature() -> String:
	var e := _selected_entry()
	if e.is_empty():
		return "none|" + Loc.locale()
	var def: Dictionary = DataRegistry.item(str(e.def))
	var gold := ""
	if def.has("equipment") or def.has("hourglass"):          # Rango e Clessidra dipendono da ciò che si può pagare
		gold = str(int(_bank.currency(BankSystem.GOLD)))
	var cb := Game.system("combat") as CombatSystem
	var chk := str(cb.equip_check(str(e.uid)).get("ok", "")) if (cb != null and str(e.uid) != "" and def.has("equipment")) else ""
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [e.key, e.qty, e.locked, e.worn, e.label, Loc.locale(), chk, gold,
		GameState.has_unlock(MARKET_TOKEN)]


## True se nel dettaglio c'è un menù a tendina aperto o un campo con il focus: non si tocca finché l'utente ci sta lavorando.
func _detail_busy() -> bool:
	if _detail_box == null:
		return false
	for c in _detail_box.find_children("*", "OptionButton", true, false):
		if (c as OptionButton).get_popup().visible:
			return true
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f != null and (f is LineEdit or f is SpinBox) and _detail_box.is_ancestor_of(f)


## Il costruttore del pannello di dettaglio sta in BankDetail.gd, caricato alla prima selezione (il Deposito si apre dentro il budget).
func _detail_builder() -> RefCounted:
	if _detail_b == null:
		_detail_b = (load("res://src/ui/screens/BankDetail.gd") as GDScript).new(self, _bank)
	return _detail_b


func _refresh_detail() -> void:
	if _detail_panel != null:
		_detail_panel.visible = not _selected_entry().is_empty()
	var sig := _detail_signature()
	if sig == _detail_sig:
		_detail_retry = false
		return                                   # niente di rilevante è cambiato: il dettaglio resta com'è (popup aperti inclusi)
	if _detail_busy():
		_detail_retry = true                     # riprova al prossimo aggiornamento, quando il popup si è chiuso
		return
	_detail_retry = false
	_detail_sig = sig
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)               # fuori subito, liberato dopo: il pulsante premuto può ricostruire il dettaglio
		c.queue_free()
	var e := _selected_entry()
	if e.is_empty():
		return
	_detail_builder().build(e)


## Perché la «Vendita rapida» è spenta ("" = si può). Ogni caso ha il suo testo: mai un pulsante grigio senza spiegazione.
## F17: la regola è UNA sola (SellRules.block_reason), la stessa della modalità vendita e della selezione.
func _sell_block_reason(e: Dictionary, _def: Dictionary, market: GameSystem) -> String:
	return SellRules.block_reason(_bank, market as MarketSystem, str(e.def), str(e.uid), GameState.has_unlock(MARKET_TOKEN))


func _dupes_plan(fresh: bool = false) -> Dictionary:
	return PlanMemo.dupes(_bank, Game.system("market") as MarketSystem, GameState.has_unlock(MARKET_TOKEN), fresh)


func _refresh_dupes_button() -> void:
	if _sell_btn == null:
		return
	var plan := _dupes_plan()
	var pop := _sell_btn.get_popup()
	pop.set_item_text(SELL_DUPES, Loc.tf("UI_BANK_DUPES_BTN", {"n": int(plan.pieces), "gold": NumberFormat.fmt(float(plan.gold))}))
	pop.set_item_disabled(SELL_DUPES, int(plan.pieces) <= 0)
	if int(plan.pieces) > 0:
		pop.set_item_tooltip(SELL_DUPES, tr("UI_BANK_DUPES_TIP"))
	elif int(plan.skipped) > 0:
		pop.set_item_tooltip(SELL_DUPES, tr("UI_BANK_DUPES_NEEDS_MARKET"))
	else:
		pop.set_item_tooltip(SELL_DUPES, tr("UI_BANK_DUPES_NONE"))


func _on_sell_dupes() -> void:
	var plan := _dupes_plan(true)
	if int(plan.pieces) <= 0:
		return
	var gold := SellRules.execute_dupes(_bank, Game.system("market") as MarketSystem, plan)
	EventBus.notice.emit("success", Loc.tf("UI_BANK_DUPES_DONE", {"n": int(plan.pieces), "gold": NumberFormat.fmt(gold)}), {})
	_mark_dirty()


func _add_line(text: String, muted: bool) -> void:
	var l := _dyn_label(&"MutedLabel" if muted else &"")
	l.text = tr(text) if text.begins_with("UI_") else text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(l)


# ------------------------------------------------------------------ interazione

## Pulsante «Espandi Deposito»: apre la finestra di acquisto (BankExpandDialog). Il testo mostra il prezzo del prossimo spazio.
func _make_expand_button(node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.theme_type_variation = &"AccentButton"
	b.tooltip_text = tr("UI_BANKX_BTN_TIP")
	b.pressed.connect(open_expand)
	return b


func _refresh_expand_buttons() -> void:
	var market := Game.system("market") as MarketSystem
	var q: Dictionary = market.bank_expansion(1) if market != null else {}
	var txt := tr("UI_BANKX_BTN")
	if not q.is_empty() and int(q.max) >= 0 and int(q.owned) >= int(q.max):
		txt = tr("UI_BANKX_BTN_MAX")
	elif not q.is_empty():
		txt = Loc.tf("UI_BANKX_BTN_PRICE", {"price": NumberFormat.fmt(float(q.next_price))})
	for b in [_expand_btn, _full_expand_btn]:
		if b != null:
			b.text = txt
			b.tooltip_text = tr("UI_BANKX_BTN_TIP")


func open_expand() -> void:
	var dlg = (load("res://src/ui/screens/BankExpandDialog.gd") as GDScript).new()
	dlg.changed.connect(_mark_dirty)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _mark_dirty() -> void:
	_dirty = true
	refresh()


## Gruppo di categorie. «gear» = la scheda Armeria (compatibilità: l'Armeria era un gruppo prima di F17).
## Voci del menù «Categorie»: l'id numerico è la posizione del gruppo in GROUPS.
func _group_menu_id(gid: String) -> int:
	for i in GROUPS.size():
		if GROUPS[i].id == gid:
			return i
	return 0


func _group_of_menu_id(mid: int) -> String:
	return str(GROUPS[clampi(mid, 0, GROUPS.size() - 1)].id)


## Testo e spunta del menù «Categorie ▾» dal gruppo attivo (l'Armeria è una scheda: nel menù conta come «tutte»).
func _sync_group_ui() -> void:
	if _cat_btn == null:
		return
	var gid := "all" if _group == "gear" else _group
	var pop := _cat_btn.get_popup()
	for i in pop.item_count:
		pop.set_item_checked(i, pop.get_item_id(i) == _group_menu_id(gid))
	var name_key := "UI_BANKG_CAT_ALL" if gid == "all" else str(GROUPS[_group_menu_id(gid)].key)
	_cat_btn.text = tr("UI_GM_CAT_MENU") if gid == "all" else Loc.tf("UI_GM_CAT_MENU_ON", {"name": tr(name_key)})
	_cat_btn.tooltip_text = tr("UI_GM_CAT_TIP")


func _on_group(id: String) -> void:
	if id == "gear":
		_select_tab(ARMORY)
		return
	if _tab == ARMORY:
		_tab = ""
	_group = id
	_sync_group_ui()
	_refresh_armory_hint()
	_mark_dirty()


## Ricerca applicata subito (la chiama l'attesa dopo l'ultimo tasto, e i test). Svuotarla torna alla scheda di prima.
func _on_query(text: String) -> void:
	var was := _results_mode()
	if not was and not text.strip_edges().is_empty():
		_remember_scroll()
	_query = text
	_mark_dirty()
	if was and not _results_mode():
		_restore_scroll()


## Ogni tasto nel campo: la ricerca vera parte dopo constants.bank.ui.search_debounce_ms (una sola ricostruzione per parola).
func _on_query_typed(_text: String) -> void:
	if _debounce != null and _debounce.is_inside_tree():
		_debounce.start()
	else:
		_on_query(_search.text)


func _on_sort(index: int) -> void:
	_sort = SORTS[index].id
	_descending = _sort == "recent" or _sort == "value" or _sort == "tier" or _sort == "worn" or _sort == "qty"
	_store_sort()
	_update_menu_labels()
	_mark_dirty()


func _on_only_locked(on: bool) -> void:
	_only_locked = on
	_update_menu_labels()
	_mark_dirty()


func _on_only_worn(on: bool) -> void:
	_only_worn = on
	_update_menu_labels()
	_mark_dirty()


func _on_descending(on: bool) -> void:
	_descending = on
	_store_sort()
	_update_menu_labels()
	_mark_dirty()


## Filtri attivi = «Solo bloccati» e «Solo equipaggiati» (l'ordine decrescente è una direzione, non un filtro).
func active_filter_count() -> int:
	return (1 if _only_locked else 0) + (1 if _only_worn else 0)


## Voce scelta nel menù «Filtri»: le tre voci sono interruttori.
func _on_filter_item(id: int) -> void:
	match id:
		FILTER_DESC:
			_on_descending(not _descending)
		FILTER_LOCKED:
			_on_only_locked(not _only_locked)
		FILTER_WORN:
			_on_only_worn(not _only_worn)


## Voce scelta nel menù «Vendita»: apre gli stessi dialoghi di prima.
func _on_sell_item(id: int) -> void:
	match id:
		SELL_SELECT:
			toggle_mode(MODE_SELECT)
		SELL_MODE:
			toggle_mode(MODE_SELL)
		SELL_MULTI:
			open_multi_sell()
		SELL_AUTO:
			open_auto_sell()
		SELL_DUPES:
			_on_sell_dupes()


## Testi dei due menù: «Filtri ▾ (n)» col numero dei filtri attivi, «Vendita ▾»; spunte allineate allo stato.
func _update_menu_labels() -> void:
	if _filters_btn == null:
		return
	var n := active_filter_count()
	_filters_btn.text = Loc.tf("UI_BANK_FILTERS_N", {"n": n}) if n > 0 else tr("UI_BANK_FILTERS")
	var fpop := _filters_btn.get_popup()
	fpop.set_item_text(fpop.get_item_index(FILTER_DESC), tr("UI_BANK_DESC"))
	fpop.set_item_text(fpop.get_item_index(FILTER_LOCKED), tr("UI_BANK_ONLY_LOCKED"))
	fpop.set_item_text(fpop.get_item_index(FILTER_WORN), tr("UI_EQ_BANK_FILTER_WORN"))
	fpop.set_item_checked(fpop.get_item_index(FILTER_DESC), _descending)
	fpop.set_item_checked(fpop.get_item_index(FILTER_LOCKED), _only_locked)
	fpop.set_item_checked(fpop.get_item_index(FILTER_WORN), _only_worn)
	_sell_btn.text = tr("UI_GM_ACTIONS")
	_filters_btn.tooltip_text = tr("UI_BANK_FILTERS_TIP")          # i MenuButton non si traducono da soli: seguono la lingua qui
	_sell_btn.tooltip_text = tr("UI_GM_ACTIONS_TIP")
	var spop := _sell_btn.get_popup()
	spop.set_item_text(SELL_MULTI, tr("UI_UIA_SELL_BTN"))
	spop.set_item_text(SELL_AUTO, tr("UI_UIA_AUTO_BTN"))
	spop.set_item_text(spop.get_item_index(SELL_SELECT), tr("UI_BANKG_SELECT"))
	spop.set_item_text(spop.get_item_index(SELL_MODE), tr("UI_BANKG_SELLMODE"))
	_sync_group_ui()
	_sort_opt.tooltip_text = tr("UI_BANK_SORT")


## «?»: apre la pagina del Manuale (spazio del Deposito) tramite la schermata principale.
func _on_help() -> void:
	var n: Node = get_parent()
	while n != null and not n.has_method("open_help"):
		n = n.get_parent()
	if n != null:
		n.call("open_help")


func _on_row_pressed(row: Control) -> void:
	if _mode != "":
		toggle_key(str(row.get_meta("key", "")))
		return
	_selected = str(row.get_meta("key", ""))
	_view_rebind()
	_refresh_detail()


## Tasto destro su una riga: menù contestuale (equipaggia, blocca, vendi, fondi, confronta, scarta).
func _on_row_context(pos: Vector2, row: Control) -> void:
	_selected = str(row.get_meta("key", ""))
	_view_rebind()
	_refresh_detail()
	var e := _selected_entry()
	if e.is_empty():
		return
	var extras: Array = []
	if _bank.can_assign(str(e.akey)):                       # F17: «Sposta in scheda…» (l'alternativa al trascinamento)
		extras.append({"text": tr("UI_BANKG_MOVE_TO"), "call": func() -> void: open_move_menu([str(e.akey)], pos)})
	if DataRegistry.item(str(e.def)).has("equipment"):
		extras.append({"text": tr("UI_UIA_ACT_COMPARE"), "call": _show_compare})
	if _discardable(e) > 0:
		extras.append({"text": tr("UI_GUILD2_BANK_DISCARD"), "call": _on_discard})
	(load("res://src/ui/ItemActions.gd") as GDScript).popup(self, pos, str(e.def), str(e.uid), _mark_dirty, extras)


## «Confronta»: il confronto con l'indossato sta nel pannello dei dettagli (e nel tooltip): lo si rimette in vista.
func _show_compare() -> void:
	_refresh_detail()


func open_multi_sell() -> void:
	var dlg = (load("res://src/ui/screens/SellDialog.gd") as GDScript).new()
	dlg.sold.connect(func(_g: int, _n: int) -> void: _mark_dirty())
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func open_auto_sell() -> void:
	var dlg = (load("res://src/ui/screens/AutoSellDialog.gd") as GDScript).new()
	dlg.changed.connect(_mark_dirty)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _on_toggle_lock() -> void:
	var e := _selected_entry()
	if e.is_empty():
		return
	if e.uid != "":
		_bank.set_instance_locked(e.uid, not e.locked)
	else:
		_bank.set_def_locked(e.def, not e.locked)
	_mark_dirty()


## Quanti pezzi della voce selezionata si possono scartare (0 = nessuno: bloccato, in uso, valuta o oggetto-missione).
func _discardable(e: Dictionary) -> int:
	if e.uid != "":
		return 1 if (not bool(e.locked) and _bank.discardable_count(e.def) > 0 and not _bank.is_in_use(e.uid)
			and not _bank.get_instance(e.uid).is_empty()) else 0
	return _bank.discardable_count(e.def)


func _on_discard() -> void:
	var e := _selected_entry()
	if e.is_empty():
		return
	var max_n := _discardable(e)
	if max_n <= 0:
		return
	var dlg := ConfirmationDialog.new()
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = tr("UI_GUILD2_BANK_DISCARD_TITLE")
	dlg.ok_button_text = tr("UI_GUILD2_BANK_DISCARD_OK")
	dlg.cancel_button_text = tr("UI_GUILD2_BANK_DISCARD_CANCEL")
	var box := VBoxContainer.new()
	var msg := Label.new()
	msg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(360, 0)
	msg.text = Loc.tf("UI_GUILD2_BANK_DISCARD_ASK", {"name": _item_name(e.def)})
	box.add_child(msg)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = max_n
	spin.value = max_n
	spin.visible = max_n > 1
	box.add_child(spin)
	dlg.add_child(box)
	dlg.confirmed.connect(_do_discard.bind(str(e.def), str(e.uid), spin))
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _do_discard(def_id: String, uid: String, spin: SpinBox) -> void:
	var n := 0
	if uid != "":
		n = 1 if _bank.discard_instance(uid) else 0
	else:
		n = _bank.discard(def_id, int(spin.value))
	if n > 0:
		EventBus.notice.emit("info", Loc.tf("UI_GUILD2_BANK_DISCARDED", {"n": n, "name": _item_name(def_id)}), {})
	_mark_dirty()


func _on_quick_sell() -> void:
	var e := _selected_entry()
	var market: GameSystem = Game.system("market")
	if e.is_empty() or market == null:
		return
	var sold: int = market.call("sell_instances", [e.uid]) if str(e.uid) != "" else market.call("sell", e.def, _bank.sellable_count(e.def))
	if sold > 0:
		EventBus.notice.emit("success", Loc.tf("UI_BANK_SOLD_NOTICE", {"gold": NumberFormat.fmt(sold)}), {})
	_mark_dirty()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or _search == null or not is_visible_in_tree() or not _focus_here():
		return
	var act := ShortcutMap.resolve_bank(event)
	if act.is_empty():
		return
	if _do_key_action(act):
		get_viewport().set_input_as_handled()


## Gamepad (doc 02 §5.2): LB/RB cambiano scheda, Y apre Ordina.
func _unhandled_input(event: InputEvent) -> void:
	var j := event as InputEventJoypadButton
	if j == null or not j.pressed or not is_visible_in_tree() or not _focus_here():
		return
	var act := ""
	var f := get_viewport().gui_get_focus_owner()
	if InputBindings.matches(j, "pad_confirm") and f is ItemCell and _grid.is_ancestor_of(f):
		# A sulla casella a fuoco: sceglie (in selezione: inverte); sulla voce già scelta, l'azione sicura (mai vendere)
		if _mode == "" and str(f.get_meta("key", "")) == _selected:
			_on_cell_activated(f)
		else:
			_on_cell_pressed(f)
		get_viewport().set_input_as_handled()
		return
	if InputBindings.matches(j, "pad_tab_prev"):
		act = "tab_prev"
	elif InputBindings.matches(j, "pad_tab_next"):
		act = "tab_next"
	elif InputBindings.matches(j, "pad_context"):
		act = "sort"
	if act != "" and _do_key_action(act):
		get_viewport().set_input_as_handled()


## I tasti del Deposito valgono solo con il fuoco nel Deposito (o senza fuoco), mai mentre si scrive altrove o c'è una finestra.
func _focus_here() -> bool:
	if not is_inside_tree():
		return false
	var f := get_viewport().gui_get_focus_owner()
	return f == null or is_ancestor_of(f)


func _do_key_action(act: String) -> bool:
	return _tabdlg().key_action(self, act)


## Esc a catena (doc 02 §5.2): prima la ricerca, poi la selezione, poi il dettaglio. Niente da chiudere = la scorciatoia globale.
func escape_chain() -> bool:
	if not _query.is_empty():
		_search.text = ""
		_on_query("")
		return true
	if _mode != "":
		exit_mode()
		return true
	if not _selected.is_empty():
		_selected = ""
		_view_rebind()
		_refresh_detail()
		return true
	return false


# ------------------------------------------------------------------ F17: barre della modalità, benvenuto, stati vuoti

## Avviso di benvenuto una tantum (doc 02 §7.6): UNA riga da banner (rapporto 08 punto 10: prima 150 px di testo prima dei comandi),
## dentro la schermata, non una finestra che interrompe. Il testo lungo di prima sta nel tooltip; «Ok, ho capito» lo chiude per sempre.
func _build_welcome(root: Control) -> void:
	_welcome = PanelContainer.new()
	_welcome.name = "TabsWelcome"
	_welcome.theme_type_variation = &"ContentPanel"
	_welcome.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_welcome.add_child(h)
	var t := _label("UI_GM_BANK_NOTICE", &"MutedLabel")
	t.name = "WelcomeText"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = 0
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.tooltip_text = "\n".join([tr("UI_BANKG_WELCOME_T"), "• " + tr("UI_BANKG_WELCOME_1"), "• " + tr("UI_BANKG_WELCOME_2"), "• " + tr("UI_BANKG_WELCOME_3")])
	h.add_child(t)
	var sug := Button.new()
	sug.name = "WelcomeSuggested"
	sug.text = "UI_BANKG_SUGGEST_BTN"
	sug.pressed.connect(open_suggested)
	h.add_child(sug)
	var ok := Button.new()
	ok.name = "WelcomeOk"
	ok.text = "UI_BANKG_WELCOME_OK"
	ok.theme_type_variation = &"AccentButton"
	ok.pressed.connect(dismiss_welcome)
	h.add_child(ok)
	root.add_child(_welcome)


func dismiss_welcome() -> void:
	_bank.mark_tabs_intro_done()
	if _welcome != null:
		_welcome.visible = false


func _refresh_welcome() -> void:
	if _welcome != null:
		_welcome.visible = not _bank.tabs_intro_done() and (_bank.used_slots() > 0 or _bank.gear_used() > 0)


## Stato vuoto della vista (doc 02 §5.9): un testo che spiega e, quando serve, UNA azione.
func _refresh_empty_state() -> void:
	var empty := _entries.is_empty()
	var sell_none := _mode == MODE_SELL and not empty and not _any_selectable()
	_empty_label.visible = empty or sell_none
	_empty_pic.visible = empty
	_empty_btn.visible = false
	_empty_btn.set_meta("act", "")
	if not (empty or sell_none):
		return
	var act := ""
	if sell_none:
		_empty_label.text = "UI_BANKG_EMPTY_SELL"
		act = "exit"
	elif _results_mode():
		_empty_label.text = Loc.tf("UI_BANKG_EMPTY_SEARCH", {"q": _query.strip_edges()})
		act = "clear_search"
	elif active_filter_count() > 0 or _group != "all":
		_empty_label.text = "UI_BANK_NO_MATCH"
		act = "clear_filters"
	elif _tab == ARMORY:
		_empty_label.text = "UI_BANKG_EMPTY_ARMORY"
		act = "go_smithing"
	elif _is_user_tab(_tab):
		_empty_label.text = "UI_BANKG_EMPTY_TAB"
		act = "select_move"
	else:
		_empty_label.text = "UI_BANK_EMPTY"
		act = "go_skills"
	_empty_btn.text = "UI_BANKG_EMPTY_ACT_" + act.to_upper()
	_empty_btn.set_meta("act", act)
	_empty_btn.visible = true


func _on_empty_action() -> void:
	_tabdlg().empty_action(self)


func _go_screen(id: String, params: Dictionary) -> void:
	_tabdlg().go_screen(self, id, params)


# ------------------------------------------------------------------ F17: schede

func _results_mode() -> bool:
	return not _query.strip_edges().is_empty()


func _is_user_tab(tab_id: String) -> bool:
	return tab_id != "" and not tab_id.begins_with("~") and _bank.tab_index(tab_id) >= 0


## Scheda corrente per la barra e per i test: "" = Tutto, ARMORY, id del giocatore, RESULTS con una ricerca attiva.
func current_tab() -> String:
	return RESULTS if _results_mode() else _tab


func _tab_name_of(e: Dictionary) -> String:
	var tid := _bank.tab_of(str(e.get("akey", "")))
	if tid == "":
		return tr("UI_BANKG_GROUP_ARMORY") if _results_mode() and _bank.is_gear_def(str(e.def)) else ""
	return str(_bank.get_tab(tid).get("name", ""))


func _on_tab_chosen(tab_id: String) -> void:
	if tab_id == RESULTS:
		return
	_select_tab(tab_id)


## Apre una scheda. Scegliere una scheda mentre i Risultati sono aperti chiude la ricerca.
func _select_tab(tab_id: String) -> void:
	if tab_id != "" and tab_id != ARMORY and not _is_user_tab(tab_id):
		tab_id = ""
	if _results_mode():
		_query = ""
		if _search != null:
			_search.text = ""
	elif tab_id != _tab:
		_remember_scroll()
	_tab = tab_id
	if tab_id == ARMORY:
		_group = "gear"
	elif _group == "gear":
		_group = "all"
	_sync_group_ui()
	_load_sort()
	_refresh_armory_hint()
	_mark_dirty()
	_restore_scroll()


func cycle_tab(dir: int) -> void:
	_tabdlg().cycle_tab(self, dir)


func _remember_scroll() -> void:
	if _grid != null:
		_tab_scroll[_tab] = _grid.first_row()


func _restore_scroll() -> void:
	if _grid != null and _view == "grid":
		_grid.scroll_to_row(int(_tab_scroll.get(_tab, 0)))


## Ordinamento per scheda (doc 02 §5.6): le schede del giocatore lo salvano nella partita; Tutto e Armeria per la sessione.
func _store_sort() -> void:
	if _is_user_tab(_tab):
		_bank.set_tab_sort(_tab, _sort, _descending)
	else:
		_fixed_sort[_tab] = {"id": _sort, "desc": _descending}


func _load_sort() -> void:
	var so: Dictionary = _bank.get_tab(_tab).get("sort", {}) if _is_user_tab(_tab) else _fixed_sort.get(_tab, {})
	if so.is_empty():
		return
	for i in SORTS.size():
		if SORTS[i].id == str(so.get("id", "")):
			_sort = SORTS[i].id
			_descending = bool(so.get("desc", true))
			if _sort_opt != null:
				_sort_opt.select(i)
	_update_menu_labels()


## Le finestre delle schede vivono in BankTabDialog.gd (caricata al primo uso: il Deposito si apre dentro il budget).
func _tabdlg() -> Variant:
	return load(TAB_DIALOG) as GDScript


## [+] / «Nuova scheda…» (finestra in BankTabDialog, caricata solo quando serve).
func open_create_tab(keys: Array = []) -> Window:
	return _tabdlg().create_flow(self, keys)


func open_edit_tab(tab_id: String) -> Window:
	return _tabdlg().edit_flow(self, tab_id)


func _popup_dialog(dlg: Window) -> void:
	if dlg is AcceptDialog:
		(dlg as AcceptDialog).canceled.connect(dlg.queue_free)
		(dlg as AcceptDialog).confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _on_tab_edit(tab_id: String, what: String) -> void:
	match what:
		"rename", "icon":
			open_edit_tab(tab_id)
		"delete":
			ask_delete_tab(tab_id)
		"lock_all":
			ask_lock_tab(tab_id)


func _on_tab_move(tab_id: String, delta: int) -> void:
	if _bank.move_tab(tab_id, delta):
		_mark_dirty()
		var b: Button = _tabs_bar.buttons.get(tab_id)
		if b != null and b.is_inside_tree():
			b.grab_focus()                         # Alt+←/→ di seguito: il fuoco resta sulla scheda che si sposta


func ask_delete_tab(tab_id: String) -> ConfirmationDialog:
	return _tabdlg().delete_flow(self, tab_id)


func _do_delete_tab(tab_id: String) -> void:
	_bank.delete_tab(tab_id)
	if _tab == tab_id:
		_tab = ""
	_mark_dirty()


func ask_lock_tab(tab_id: String) -> ConfirmationDialog:
	return _tabdlg().lock_flow(self, tab_id)


func lock_tab(tab_id: String) -> int:
	return _tabdlg().lock_all(self, tab_id)


## Rilascio di caselle trascinate: su una scheda = sposta; su Tutto = togli dalla scheda; su [+] = nuova scheda con quelle voci.
func _on_keys_dropped(tab_id: String, keys: Array) -> void:
	if tab_id == BankTabsBar.NEW:
		open_create_tab(keys)
		return
	if tab_id == ARMORY or tab_id == RESULTS:
		return
	_announce_move(_bank.assign_to_tab(keys, tab_id), tab_id)
	_mark_dirty()


func _announce_move(n: int, tab_id: String) -> void:
	if n <= 0:
		return
	if tab_id == "":
		EventBus.notice.emit("info", Loc.tf("UI_BANKG_MOVED_OUT", {"n": n}), {})
	else:
		EventBus.notice.emit("info", Loc.tf("UI_BANKG_MOVED", {"n": n, "name": str(_bank.get_tab(tab_id).get("name", ""))}), {})


func _cell_drag(_at: Vector2, cell: Control) -> Variant:
	return _tabdlg().cell_drag(self, _at, cell)


func _entry_by_key(key: String) -> Dictionary:
	for e in _entries:
		if e.key == key:
			return e
	return {}


## Menù «Sposta in…» (Maiusc+M, pulsante della selezione, tasto destro).
func open_move_menu(keys: Array, at: Vector2) -> PopupMenu:
	return _tabdlg().move_menu(self, keys, at)


## Voci da spostare: la selezione (in modalità) o la voce scelta; solo quelle assegnabili (il gear resta nell'Armeria).
func _move_keys() -> Array:
	var out: Array = []
	if _mode != "" and not _selection.is_empty():
		for k in _selection:
			var ak := BankSystem.tab_key(str(_selection[k].def), str(_selection[k].uid))
			if _bank.can_assign(ak):
				out.append(ak)
	elif not _selected_entry().is_empty():
		var e := _selected_entry()
		if _bank.can_assign(str(e.akey)):
			out.append(str(e.akey))
	return out


func suggested_plan() -> Array:
	return _tabdlg().suggested_plan(self)


func open_suggested() -> ConfirmationDialog:
	return _tabdlg().suggested_flow(self)


func apply_suggested(plan: Array) -> int:
	return _tabdlg().apply_suggested(self, plan)


# ------------------------------------------------------------------ F17: selezione unica, modalità vendita (doc 02 §5.5)

func toggle_mode(m: String) -> void:
	if _mode == m:
		exit_mode()
	else:
		enter_mode(m)


## Entra in selezione ("select") o in vendita ("sell": solo con il Mercato sbloccato; il motivo altrimenti è detto).
func enter_mode(m: String) -> bool:
	if m == MODE_SELL and not GameState.has_unlock(MARKET_TOKEN):
		EventBus.notice.emit("info", tr("UI_BANK_SELL_NEEDS_MARKET"), {})
		_refresh_mode_bars()
		return false
	_mode = m
	_selection.clear()
	_mark_dirty()
	return true


func exit_mode() -> void:
	if _mode == "" and _selection.is_empty():
		return
	_mode = ""
	_selection.clear()
	if _grid != null:
		_mark_dirty()


func mode() -> String:
	return _mode


func is_selectable(e: Dictionary) -> bool:
	if _mode != MODE_SELL:
		return true
	if not e.has("why"):
		e["why"] = SellRules.block_reason(_bank, Game.system("market") as MarketSystem, str(e.def), str(e.uid), GameState.has_unlock(MARKET_TOKEN))
	return str(e.why) == ""


func _unselectable_reason(e: Dictionary) -> String:
	return str(e.get("why", "")) if not is_selectable(e) else ""


func _any_selectable() -> bool:
	for e in _entries:
		if is_selectable(e):
			return true
	return false


## Clic / Spazio in modalità: inverte la selezione della voce (le non selezionabili restano fuori, il tooltip dice perché).
func toggle_key(key: String) -> void:
	var e := _entry_by_key(key)
	if e.is_empty() or not is_selectable(e):
		return
	if _selection.has(key):
		_selection.erase(key)
	else:
		_selection[key] = {"def": str(e.def), "uid": str(e.uid)}
	_view_rebind()
	_refresh_mode_bars()


## Ctrl+A / «Seleziona tutto visibile»: tutte le voci della vista attuale che si possono selezionare (solo dizionario, nessun nodo).
func select_all_visible() -> void:
	if _mode == "":
		return
	for e in _entries:
		if is_selectable(e):
			_selection[e.key] = {"def": str(e.def), "uid": str(e.uid)}
	_view_rebind()
	_refresh_mode_bars()


func clear_selection() -> void:
	_selection.clear()
	_view_rebind()
	_refresh_mode_bars()


func selection_keys() -> Array:
	return _selection.keys()


func lock_selection() -> void:
	_tabdlg().lock_selection(self)


func selection_picks() -> Array:
	return _tabdlg().selection_picks(self)


func open_selection_sell() -> Window:
	return _tabdlg().sell_flow(self)


func _refresh_mode_bars() -> void:
	if _sell_btn == null:
		return
	var market_open := GameState.has_unlock(MARKET_TOKEN)
	var spop := _sell_btn.get_popup()
	var si := spop.get_item_index(SELL_SELECT)
	var mi := spop.get_item_index(SELL_MODE)
	spop.set_item_checked(si, _mode == MODE_SELECT)
	spop.set_item_checked(mi, _mode == MODE_SELL)
	spop.set_item_disabled(mi, not market_open)
	spop.set_item_tooltip(mi, tr("UI_BANKG_SELLMODE_TIP") if market_open else tr("UI_BANK_SELL_NEEDS_MARKET"))
	if _mode_bar == null:
		if _mode == "":
			return
		_tabdlg().build_mode_bars(self, _mode_holder)
	_mode_bar.visible = _mode != ""
	_action_bar.visible = _mode != ""
	if _mode == "":
		return
	_mode_label.text = tr("UI_BANKG_SELLMODE_BAR") if _mode == MODE_SELL else tr("UI_BANKG_SELECT_BAR")
	_mode_exit.text = tr("UI_BANKG_SELLMODE_EXIT") if _mode == MODE_SELL else tr("UI_BANKG_SELECT_EXIT")
	var plan := SellRules.collect_picks(_bank, Game.system("market") as MarketSystem, selection_picks(), market_open)
	_sel_label.text = Loc.tf("UI_BANKG_SEL_COUNT", {"n": NumberFormat.fmt(float(_selection.size())), "gold": NumberFormat.fmt(float(plan.gold))}) \
		if market_open else Loc.tf("UI_BANKG_SEL_COUNT_NOGOLD", {"n": NumberFormat.fmt(float(_selection.size()))})
	_move_btn.visible = _mode == MODE_SELECT
	_move_btn.disabled = _move_keys().is_empty()
	_lock_sel_btn.visible = _mode == MODE_SELECT
	_lock_sel_btn.disabled = _selection.is_empty()
	_lock_sel_btn.text = tr("UI_BANKG_LOCK_SEL")
	_sell_sel_btn.disabled = int(plan.pieces) <= 0
	_sell_sel_btn.tooltip_text = "" if market_open else tr("UI_BANK_SELL_NEEDS_MARKET")


func _search_names() -> Dictionary:
	return _tabdlg().search_names(self)
