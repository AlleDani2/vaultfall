extends GameScreen
## Eroe (docs/16): statistiche, classe, attributi, equipaggiamento a slot con confronto, cibo e auto-mangiare.
## Solo presentazione: legge e comanda CombatSystem (e il bank tramite i suoi metodi).

const SLOT_ORDER: PackedStringArray = EquipDoll.SLOTS
const STAT_KEYS: PackedStringArray = ["damage", "armor", "ward", "hp", "ap", "accuracy", "evasion", "str", "dex", "int", "vit", "crit_chance"]
const ATTRS: PackedStringArray = ["str", "dex", "int", "vit"]
const TAB_IDS: PackedStringArray = ["equip", "abilities", "stats", "food", "glyphs"]
const HEAD_STATS: PackedStringArray = ["HP", "ACC", "ARMOR"]      # le tre statistiche chiave della testata (righe di STAT_TIP_KEYS)
const REFRESH_EVERY := 1       # ricostruzione dei pannelli pesanti ogni N refresh (10 Hz → 1 s) se nulla è cambiato

## Ultima scheda aperta: si riapre dove eri rimasto (solo per questa sessione di gioco).
static var _last_tab: String = "equip"

var _combat: CombatSystem
var _tab: String = "equip"
var _tab_btns: Dictionary = {}
var _pages: Dictionary = {}
var _pages_box: VBoxContainer
var _head_class: Label
var _head_chips: Dictionary = {}          # riga (HP, ACC, ARMOR) -> Label
var _head_sig := ""
var _head_help_row: Control
var _help_btn: Button
var _perks: SkillPerkPanel          # talenti di mansione dell'Eroe (ogni 10 livelli)
var _profile: Label                 # GUILD-2: titolo, cornice e compagno scelti nel Compendio
var _stats_box: GridContainer
var _class_opt: OptionButton
var _class_ids: Array = []
var _class_note: Label
var _spec_opt: OptionButton
var _spec_ids: Array = []
var _spec_note: Label
var _auto_abil: CheckButton
var _slot_opts: Array = []
var _slot_ids: Array = []
var _abil_note: Label
var _potion_opt: OptionButton
var _potion_ids: Array = []
var _potion_btn: Button
var _potion_note: Label
var _potion_go: HBoxContainer
var _glyph_note: Label
var _attr_note: Label
var _glyph_item_opt: OptionButton
var _glyph_uids: Array = []
var _glyph_box: VBoxContainer
var _glyph_popup: PopupMenu
var _glyph_pick_uid: String = ""
var _glyph_pick_index: int = 0
var _glyph_pick_ids: Array = []
var _auto_btn: CheckButton
var _attr_box: GridContainer
var _slot_rows: Dictionary = {}          # slot -> {btn}: alias degli slot del paper-doll (test e altre schermate)
var _doll: EquipDoll                     # equipaggiamento a slot disegnati (EquipDoll)
var _food_panel: FoodPanel               # cibo: slot, soglia, scorta (FoodPanel)
var _sig := ""
var _gear_extras: HeroGearExtras     # GAP-MECCANICHE: Rango degli oggetti (G03) e Set di equipaggiamento (G15)
var _stats_sig := ""
var _finish_labels: Dictionary = {}      # slot -> etichetta con nome e colore della finitura (Guardaroba), vive negli slot del doll


func open(_params: Dictionary) -> void:
	_combat = Game.system("combat") as CombatSystem
	_build()
	_sig = ""
	_stats_sig = ""
	refresh()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# F10 (06 §3.14): una testata in una riga (classe e tre statistiche chiave), cinque schede, UNA pagina alla volta.
	# Talenti e Guardaroba hanno la loro voce di menù: qui non sono schede.
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	_build_header(page)
	_profile = Label.new()
	_profile.theme_type_variation = &"MutedLabel"
	_profile.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_profile)
	var tabs: Array = []
	for t in TAB_IDS:
		tabs.append([t, tr("UI_SCR_HERO_TAB_" + str(t).to_upper()), tr("UI_SCR_HERO_TIP_" + str(t).to_upper())])
	_tab_btns = HeroKit.tab_bar(page, tabs, ScreenKit.accent("hero"), _set_tab)
	_pages_box = VBoxContainer.new()
	_pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_pages_box)
	_build_equip_page()
	_build_abilities_page()
	_build_stats_page()
	_build_food_page()
	_build_glyphs_page()
	_set_tab(_last_tab if TAB_IDS.has(_last_tab) else "equip")


## Testata: titolo, «Liv N · Classe / Specializzazione» e tre statistiche chiave (PV, Precisione, Armatura) con il tooltip di calcolo.
func _build_header(page: VBoxContainer) -> void:
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 14)
	head.add_theme_constant_override("v_separation", 2)
	page.add_child(head)
	head.add_child(ScreenKit.title_style(_lbl("UI_MENU_HERO", "TitleLabel")))
	_head_class = Label.new()
	_head_class.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_head_class.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_head_class)
	for k in HEAD_STATS:
		var l := Label.new()
		l.theme_type_variation = &"MonoLabel"
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.gui_input.connect(func(ev: InputEvent) -> void:      # clic = elenco dei bonus attivi
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				BonusDialog.open_on(self))
		head.add_child(l)
		_head_chips[str(k)] = l
	_head_help_row = head


## Pagina vuota nel contenitore delle pagine (la scheda scelta è l'unica visibile). Ritorna le colonne.
func _new_page(id: String, columns: int = 1) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.visible = false
	_pages_box.add_child(v)
	_pages[id] = v
	if columns <= 1:
		return [v]
	return _columns(v, columns)


## `n` colonne affiancate dentro `parent`.
func _columns(parent: Control, n: int) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(h)
	var cols: Array = []
	for i in n:
		var c := VBoxContainer.new()
		c.custom_minimum_size = Vector2(260, 0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		c.add_theme_constant_override("separation", 8)
		h.add_child(c)
		cols.append(c)
	return cols


func _build_equip_page() -> void:
	var col: VBoxContainer = _new_page("equip")[0]
	_doll = EquipDoll.new()                  # slot disegnati (paper-doll), elenco dei pezzi compatibili, tasto destro per togliere
	_doll.changed.connect(func() -> void: _sig = "")
	col.add_child(_doll)
	_doll.ensure_built()
	_finish_labels = _doll.finish_labels
	for slot in SLOT_ORDER:                  # alias per i test e per le altre schermate: slot -> {btn}
		_slot_rows[slot] = {"btn": _doll.slot_buttons[slot]}
	_gear_extras = HeroGearExtras.new()      # Rango degli oggetti (G03) e Set di equipaggiamento (G15)
	col.add_child(_gear_extras)
	_help_btn = HeroKit.help_button(_head_help_row, _doll.help_label(), "hero", tr("UI_SCR_HERO_HELP_TIP"))
	_help_btn.toggled.connect(_doll.set_help_visible)


func _build_abilities_page() -> void:
	var cols := _new_page("abilities", 2)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(_lbl("UI_HERO_CLASS", "SectionLabel"))
	_class_opt = _fit(OptionButton.new())
	for c in _combat.build.selectable_classes():
		_class_opt.add_item(Loc.t(c.def.name))
		_class_ids.append(str(c.id))
	_class_opt.item_selected.connect(_on_class_selected)
	left.add_child(_class_opt)
	_class_note = Label.new()
	_class_note.theme_type_variation = &"MutedLabel"
	_class_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	left.add_child(_class_note)
	left.add_child(_lbl("UI_C2_SPEC", "SectionLabel"))
	_spec_opt = _fit(OptionButton.new())
	_spec_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_spec_opt.item_selected.connect(_on_spec_selected)
	left.add_child(_spec_opt)
	_spec_note = CombatUi.text_label("MutedLabel", true)
	left.add_child(_spec_note)
	_perks = SkillPerkPanel.new()            # talenti di mansione dell'Eroe (ogni 10 livelli): a tutta larghezza sotto le colonne
	_perks.setup("hero")
	(_pages["abilities"] as Control).add_child(_perks)
	right.add_child(_lbl("UI_C2_ABILITIES", "SectionLabel"))
	_auto_abil = CheckButton.new()
	_auto_abil.text = "UI_C2_ABILITY_AUTO"
	_auto_abil.toggled.connect(func(on: bool) -> void:
		_combat.build.set_auto_abilities(on)
		_sig = "")
	right.add_child(_auto_abil)
	for i in _combat.build.ability_slots():
		var o := _fit(OptionButton.new())
		o.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		o.item_selected.connect(_on_slot_selected.bind(i))
		var drag_row := AbilityDragRow.new(i)         # priorità delle abilità a trascinamento (UI-A G18)
		drag_row.moved.connect(_on_ability_moved)
		right.add_child(drag_row)
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drag_row.add_child(o)
		drag_row.accept_drops_on(o)
		_slot_opts.append(o)
		_slot_ids.append([])
	_abil_note = CombatUi.text_label("MutedLabel", true)
	right.add_child(_abil_note)


func _build_stats_page() -> void:
	var cols := _new_page("stats", 2)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(_lbl("UI_HERO_ATTRIBUTES", "SectionLabel"))
	_auto_btn = CheckButton.new()
	_auto_btn.text = "UI_HERO_AUTO_ALLOC"
	_auto_btn.toggled.connect(func(on: bool) -> void:
		_combat.set_auto_alloc(on)
		_sig = "")
	left.add_child(_auto_btn)
	_attr_box = GridContainer.new()
	_attr_box.columns = 3
	left.add_child(_attr_box)
	_attr_note = CombatUi.text_label("MutedLabel", true)
	left.add_child(_attr_note)
	right.add_child(_lbl("UI_HERO_STATS", "SectionLabel"))
	_stats_box = GridContainer.new()
	_stats_box.columns = 2
	_stats_box.add_theme_constant_override("h_separation", 16)
	right.add_child(_stats_box)
	var bonus_btn := Button.new()           # tutti i bonus attivi e da dove vengono (rapporto 112)
	bonus_btn.name = "BonusBtn"
	bonus_btn.text = "UI_UIA_BONUS_BTN"
	bonus_btn.tooltip_text = "UI_UIA_BONUS_BTN_TIP"
	bonus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bonus_btn.pressed.connect(func() -> void: BonusDialog.open_on(self))
	right.add_child(bonus_btn)


func _build_food_page() -> void:
	var right: VBoxContainer = _new_page("food")[0]
	_food_panel = FoodPanel.new()            # Cibo: slot, soglia di auto-mangiare, scorta
	right.add_child(_food_panel)
	# pozione di combattimento (cariche = attacchi)
	right.add_child(_lbl("UI_C2_POTION", "SectionLabel"))
	var pot_row := HBoxContainer.new()
	pot_row.add_theme_constant_override("separation", 8)
	right.add_child(pot_row)
	_potion_opt = _fit(OptionButton.new())
	_potion_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_potion_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pot_row.add_child(_potion_opt)
	_potion_btn = Button.new()
	_potion_btn.text = "UI_C2_POTION_DRINK"
	_potion_btn.pressed.connect(_on_drink)
	pot_row.add_child(_potion_btn)
	_potion_note = CombatUi.text_label("MutedLabel", true)
	right.add_child(_potion_note)
	_potion_go = HBoxContainer.new()
	right.add_child(_potion_go)


func _build_glyphs_page() -> void:
	var col: VBoxContainer = _new_page("glyphs")[0]
	col.add_child(_lbl("UI_C2_GLYPHS", "SectionLabel"))
	_glyph_item_opt = _fit(OptionButton.new())
	_glyph_item_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_glyph_item_opt.item_selected.connect(func(_i: int) -> void: _refresh_glyph_rows())
	col.add_child(_glyph_item_opt)
	_glyph_note = CombatUi.text_label("MutedLabel", true)
	col.add_child(_glyph_note)
	_glyph_box = VBoxContainer.new()
	col.add_child(_glyph_box)
	_glyph_popup = PopupMenu.new()
	_glyph_popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_glyph_popup.index_pressed.connect(_on_glyph_picked)
	add_child(_glyph_popup)


## Mostra una sola pagina. `id`: equip · abilities · stats · food · glyphs.
func _set_tab(id: String) -> void:
	if not _pages.has(id):
		id = "equip"
	_tab = id
	_last_tab = id
	for k in _pages:
		(_pages[k] as Control).visible = str(k) == id
	for k in _tab_btns:
		(_tab_btns[k] as Button).set_pressed_no_signal(str(k) == id)
	if _help_btn != null:
		_help_btn.visible = id == "equip"


func current_tab() -> String:
	return _tab


## Menù a tendina che non allarga la colonna: i nomi lunghi vengono tagliati (il nome intero è nell'elenco aperto).
func _fit(o: OptionButton) -> OptionButton:
	o.fit_to_longest_item = false
	o.clip_text = true
	return o


func _lbl(key: String, variation: String) -> Label:
	var l := Label.new()
	l.text = key
	l.theme_type_variation = StringName(variation)
	return l


func _val(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"MonoLabel"
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	return l


# ------------------------------------------------------------------ aggiornamento

## Titolo e compagno scelti nel Compendio (docs/15 §4: il titolo appare accanto al nome dell'Eroe).
func _refresh_profile() -> void:
	var comp := Game.system("compendium") as CompendiumSystem
	if comp == null or _profile == null:
		return
	var parts := PackedStringArray()
	if comp.title_line() != "":
		parts.append("«%s»" % comp.title_line())
	var pet := comp.companion()
	if pet != "":
		parts.append(Loc.tf("UI_GUILD2_HEAD_PET", {"name": Loc.t(DataRegistry.get_def("pets", pet).get("name", pet))}))
	_profile.text = " · ".join(parts)
	_profile.visible = not parts.is_empty()


## Testata: «Liv N · Classe / Specializzazione» e tre statistiche chiave; il tooltip di calcolo si rifà solo se il numero cambia.
func _refresh_header(st: Dictionary) -> void:
	var cls := Loc.t(_combat.class_def().get("name", {}))
	var spec := str(_combat.state.spec)
	if not spec.is_empty():
		cls += " / " + Loc.t(DataRegistry.get_def("classes", spec).get("name", {}))
	_head_class.text = Loc.tf("UI_SCR_HERO_HEADLINE", {"level": int(st.level), "class": cls})
	var vals := {"HP": NumberFormat.fmt(float(st.hp)), "ACC": NumberFormat.fmt(float(st.acc)), "ARMOR": NumberFormat.fmt(float(st.arm))}
	var sig := "%s|%s" % [Loc.locale(), JSON.stringify(vals)]
	if sig == _head_sig:
		return
	_head_sig = sig
	for k in HEAD_STATS:
		var l: Label = _head_chips[k]
		l.text = "%s %s" % [tr("UI_HERO_ST_" + str(k)), vals[k]]
		var tip := _stat_tip(str(k))
		l.tooltip_text = (tip + "\n" + tr("UI_BONUS_STAT_TIP_MORE")) if not tip.is_empty() else ""


func refresh() -> void:
	if _combat == null:
		return
	_refresh_profile()
	if _perks != null:
		_perks.refresh()
	var st := _combat.hero_stats()
	_refresh_header(st)
	var sig := "%s|%s|%d|%s|%s|%s|%s|%s|%s|%s|%s" % [JSON.stringify(GameState.data.get("equipment", {})), str(_combat.state.class),
		_combat.hero_level(), str(_combat.state.auto_alloc), JSON.stringify(_combat.state.attrs), _combat.in_combat(),
		str(_combat.state.spec), str(_combat.state.auto_abilities), JSON.stringify(_combat.state.abilities),
		JSON.stringify(_combat.state.potion), _supplies_sig()]
	_refresh_stats(st)
	_food_panel.refresh()
	_doll.refresh()
	_gear_extras.refresh()
	if sig == _sig:
		return
	if _any_menu_open():
		return                              # un menù a tendina aperto non si ricostruisce: si riprova al prossimo aggiornamento
	_sig = sig
	_refresh_class()
	_refresh_spec()
	_refresh_abilities_ui()
	_refresh_attrs()
	_refresh_potion()
	_refresh_glyphs()


## Un menù a tendina aperto si chiuderebbe da solo se lo si ricostruisse (clear): si aspetta che il giocatore scelga.
func _any_menu_open() -> bool:
	var opts: Array = [_class_opt, _spec_opt, _potion_opt, _glyph_item_opt]
	opts.append_array(_slot_opts)
	for o in opts:
		if o != null and (o as OptionButton).get_popup().visible:
			return true
	return _glyph_popup != null and _glyph_popup.visible


func _refresh_class() -> void:
	_class_opt.select(maxi(0, _class_ids.find(str(_combat.state.class))))
	var cost := _combat.class_change_cost()
	var cc: Dictionary = Formulas.k().combat.rules.class_change
	_class_note.text = tr("UI_HERO_CLASS_FREE") if cost == 0 else Loc.tf("UI_HERO_CLASS_COST", {"gold": NumberFormat.fmt(cost),
		"cd": NumberFormat.fmt_time(float(cc.get("cooldown_s", 0.0))), "window": NumberFormat.fmt_time(float(cc.get("trial_return_s", 0.0)))})
	if float(_combat.state.class_prev_s) > 0.0 and not str(_combat.state.class_prev).is_empty():
		_class_note.text += "  " + Loc.tf("UI_HERO_CLASS_TRIAL", {"class": Loc.t(DataRegistry.get_def("classes", str(_combat.state.class_prev)).name),
			"time": NumberFormat.fmt_time(float(_combat.state.class_prev_s))})
	if float(_combat.state.class_cd_s) > 0.0:
		_class_note.text += "  " + Loc.tf("UI_C2_CLASS_COOLDOWN", {"time": NumberFormat.fmt_time(float(_combat.state.class_cd_s))})
	_class_opt.disabled = _combat.in_combat()
	if _combat.in_combat():
		_class_note.text += "  " + tr("UI_UXC_CLASS_NOT_IN_COMBAT")
	for i in _class_ids.size():
		var ok := _combat.build.class_available(str(_class_ids[i]))
		_class_opt.set_item_disabled(i, not ok)
		var nm := Loc.t(DataRegistry.get_def("classes", str(_class_ids[i])).name)
		_class_opt.set_item_text(i, nm if ok else nm + "  (" + tr("UI_COMBAT_LOCKED") + ")")


## Supplies = pozioni di combattimento e Glifi nel Deposito (per ricostruire i selettori quando cambiano).
func _supplies_sig() -> String:
	var bank: Variant = Game.system("bank")
	if bank == null:
		return ""
	var n := 0
	for it in DataRegistry.items_by_category("potion"):
		if str(it.get("potion", {}).get("scope", "")) == "combat":
			n += int(bank.count(str(it.id))) * 7 + 1
	for it in DataRegistry.items_by_category("glyph"):
		n += int(bank.count(str(it.id))) * 13
	return str(n)


func _refresh_spec() -> void:
	_spec_opt.clear()
	_spec_ids = [""]
	_spec_opt.add_item(tr("UI_C2_SPEC_NONE"))
	var specs := _combat.build.specs_of(str(_combat.state.class))
	for sid in specs:
		var sd: Dictionary = DataRegistry.get_def("classes", str(sid))
		var ok := _combat.build.spec_available(str(sid))
		_spec_opt.add_item(Loc.t(sd.name) if ok else Loc.t(sd.name) + "  (" + tr("UI_COMBAT_LOCKED") + ")")
		_spec_opt.set_item_disabled(_spec_opt.item_count - 1, not ok)
		_spec_ids.append(str(sid))
	_spec_opt.select(maxi(0, _spec_ids.find(str(_combat.state.spec))))
	_spec_opt.disabled = _combat.in_combat() or specs.is_empty()
	if specs.is_empty():
		_spec_note.text = tr("UI_C2_SPEC_HYBRID")
	elif _combat.in_combat():
		_spec_note.text = tr("UI_C2_SPEC_NOT_IN_COMBAT")
	else:
		_spec_note.text = tr("UI_C2_SPEC_HINT")


func _on_spec_selected(idx: int) -> void:
	if not _combat.build.set_spec(str(_spec_ids[idx])):
		EventBus.notice.emit("warning", tr("UI_C2_SPEC_DENIED"), {})
	_sig = ""
	refresh()


func _refresh_abilities_ui() -> void:
	_auto_abil.set_pressed_no_signal(bool(_combat.state.auto_abilities))
	var avail := _combat.build.abilities_available()
	var equipped := _combat.build.abilities_equipped()
	for i in _slot_opts.size():
		var o: OptionButton = _slot_opts[i]
		o.clear()
		var ids: Array = [""]
		o.add_item(tr("UI_HERO_EMPTY"))
		for ab in avail:
			o.add_item("%s  (%d)" % [Loc.t(ab.name), int(ab.cost)])
			ids.append(str(ab.id))
		_slot_ids[i] = ids
		var cur := str(equipped[i].id) if i < equipped.size() else ""
		o.select(maxi(0, ids.find(cur)))
		o.disabled = bool(_combat.state.auto_abilities)
		o.tooltip_text = tr("UI_C2_ABILITY_SLOT_TIP")
	if not _combat.build.class_abilities_enabled():
		_abil_note.text = tr("UI_C2_ABILITY_WRONG_WEAPON")
	elif avail.is_empty():
		_abil_note.text = tr("UI_C2_ABILITY_NONE_YET")
	else:
		_abil_note.text = tr("UI_C2_ABILITY_PRIORITY")


## Trascinamento di una abilità su un'altra riga: cambia la priorità della rotazione.
func _on_ability_moved(from_index: int, to_index: int) -> void:
	var ids: Array = []
	for i in _slot_opts.size():
		var list: Array = _slot_ids[i]
		ids.append(str(list[maxi(0, (_slot_opts[i] as OptionButton).selected)]))
	var order := AbilityDragRow.reorder_ids(ids, from_index, to_index)
	for i in order.size():
		_combat.build.set_slot(i, "")
	var n := 0
	for id in order:
		if not str(id).is_empty():
			_combat.build.set_slot(n, str(id))
			n += 1
	_sig = ""
	refresh()


func _on_slot_selected(idx: int, slot: int) -> void:
	var ids: Array = _slot_ids[slot]
	_combat.build.set_slot(slot, str(ids[idx]))
	_sig = ""
	refresh()


func _refresh_potion() -> void:
	var bank: Variant = Game.system("bank")
	_potion_opt.clear()
	_potion_ids = []
	if bank != null:
		for it in DataRegistry.items_by_category("potion"):
			if str(it.get("potion", {}).get("scope", "")) == "combat" and bank.count(str(it.id)) > 0:
				_potion_opt.add_item("%s ×%d" % [_item_name(str(it.id)), bank.count(str(it.id))])
				_potion_ids.append(str(it.id))
	if _potion_ids.is_empty():
		_potion_opt.add_item(tr("UI_C2_POTION_NONE"))
	_potion_opt.disabled = _potion_ids.is_empty()
	_potion_btn.disabled = _potion_ids.is_empty()
	var pot: Dictionary = _combat.active_potion()
	if not pot.is_empty():
		_potion_note.text = Loc.tf("UI_C2_POTION_ACTIVE", {"name": _item_name(str(pot.def)), "n": int(pot.charges)})
	elif _potion_ids.is_empty():
		_potion_note.text = tr("UI_HERO_POTION_NONE_NOTE")
	else:
		_potion_note.text = tr("UI_C2_POTION_HINT")
	CombatUi.clear_children(_potion_go)
	if _potion_ids.is_empty() and pot.is_empty():
		var alch := ReqLink.target_for_level("alchemy")
		if not alch.is_empty():
			var gb := Button.new()
			gb.text = tr("UI_HERO_GO_ALCHEMY")
			gb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			gb.pressed.connect(ReqLink.go.bind(alch))
			_potion_go.add_child(gb)


func _on_drink() -> void:
	var idx := _potion_opt.selected
	if idx < 0 or idx >= _potion_ids.size():
		return
	if _combat.use_potion(str(_potion_ids[idx])):
		CombatUi.pop(_potion_btn)
	_sig = ""
	refresh()


func _refresh_glyphs() -> void:
	var bank: Variant = Game.system("bank")
	var prev: String = str(_glyph_uids[_glyph_item_opt.selected]) if _glyph_item_opt.selected >= 0 and _glyph_item_opt.selected < _glyph_uids.size() else ""
	_glyph_item_opt.clear()
	_glyph_uids = []
	for slot in SLOT_ORDER:
		var uid := _combat.equipped(slot)
		if slot == "ammo" or uid.is_empty() or bank == null:
			continue
		var info := _combat.sockets_of(uid)
		if int(info.max) <= 0:
			continue
		var inst: Dictionary = bank.get_instance(uid)
		_glyph_item_opt.add_item("%s  (%d/%d)" % [_item_name(str(inst.get("def", ""))), (info.glyphs as Array).size(), int(info.max)])
		_glyph_uids.append(uid)
	if _glyph_uids.is_empty():
		_glyph_item_opt.add_item(tr("UI_C2_GLYPH_NONE"))
	_glyph_note.text = tr("UI_HERO_GLYPH_NOTE_NONE") if _glyph_uids.is_empty() else tr("UI_HERO_GLYPH_NOTE")
	_glyph_item_opt.disabled = _glyph_uids.is_empty()
	var keep := _glyph_uids.find(prev)
	_glyph_item_opt.select(maxi(0, keep))
	_refresh_glyph_rows()


func _refresh_glyph_rows() -> void:
	CombatUi.clear_children(_glyph_box)
	var idx := _glyph_item_opt.selected
	if idx < 0 or idx >= _glyph_uids.size():
		return
	var uid := str(_glyph_uids[idx])
	var info := _combat.sockets_of(uid)
	for i in int(info.max):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_glyph_box.add_child(row)
		var l := CombatUi.text_label("", false)
		l.custom_minimum_size = Vector2(220, 0)
		row.add_child(l)
		var b := Button.new()
		row.add_child(b)
		if i < (info.glyphs as Array).size():
			l.text = _item_name(str(info.glyphs[i]))
			b.text = "UI_C2_GLYPH_REMOVE"
			b.tooltip_text = tr("UI_C2_GLYPH_REMOVE_TIP")
			b.disabled = _combat.in_dungeon()
			b.pressed.connect(func() -> void:
				_combat.unsocket_glyph(uid, i)
				_sig = "")
		else:
			l.text = tr("UI_C2_GLYPH_EMPTY")
			b.text = "UI_C2_GLYPH_SOCKET"
			b.disabled = _combat.in_dungeon()
			b.pressed.connect(_open_glyph_picker.bind(uid, i, b))


func _open_glyph_picker(uid: String, index: int, anchor: Control) -> void:
	var bank: Variant = Game.system("bank")
	_glyph_pick_uid = uid
	_glyph_pick_index = index
	_glyph_pick_ids = []
	_glyph_popup.clear()
	if bank != null:
		for it in DataRegistry.items_by_category("glyph"):
			if bank.count(str(it.id)) > 0:
				_glyph_popup.add_item("%s ×%d" % [_item_name(str(it.id)), bank.count(str(it.id))])
				_glyph_pick_ids.append(str(it.id))
	if _glyph_pick_ids.is_empty():
		_glyph_popup.add_item(tr("UI_C2_GLYPH_NONE_AVAILABLE"))
		_glyph_popup.set_item_disabled(0, true)
	_glyph_popup.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y))
	_glyph_popup.popup()


func _on_glyph_picked(idx: int) -> void:
	if idx < 0 or idx >= _glyph_pick_ids.size():
		return
	_combat.socket_glyph(_glyph_pick_uid, str(_glyph_pick_ids[idx]))
	_sig = ""
	refresh()


func _on_class_selected(idx: int) -> void:
	if not _combat.set_class(str(_class_ids[idx])):
		EventBus.notice.emit("warning", tr("UI_HERO_CLASS_DENIED"), {})
	_sig = ""
	refresh()


func _refresh_attrs() -> void:
	_auto_btn.set_pressed_no_signal(bool(_combat.state.auto_alloc))
	if bool(_combat.state.auto_alloc):
		_attr_note.text = tr("UI_HERO_ATTR_NOTE_AUTO")
	elif _combat.in_combat():
		_attr_note.text = tr("UI_HERO_ATTR_NOTE_COMBAT")
	else:
		_attr_note.text = tr("UI_HERO_ATTR_NOTE_MANUAL")
	for c in _attr_box.get_children():
		c.queue_free()
	var attrs: Dictionary = _combat.hero_stats().attrs
	for a in ATTRS:
		_attr_box.add_child(_lbl("UI_HERO_STAT_" + a.to_upper(), "MutedLabel"))
		_attr_box.add_child(_val(NumberFormat.fmt(float(attrs[a]))))
		if bool(_combat.state.auto_alloc):
			# il «+» nascosto non occupava la cella e la griglia a 3 colonne si sfalsava (Forza | Destrezza / 5 | Intelletto...)
			_attr_box.add_child(Control.new())
			continue
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = _combat.free_points() <= 0 or _combat.in_combat()
		plus.pressed.connect(func() -> void:
			_combat.allocate(a, 1)
			_sig = "")
		_attr_box.add_child(plus)
	if not bool(_combat.state.auto_alloc):
		_attr_box.add_child(_lbl("UI_HERO_FREE_POINTS", "MutedLabel"))
		_attr_box.add_child(_val(str(_combat.free_points())))
		_attr_box.add_child(Control.new())


func _refresh_stats(st: Dictionary) -> void:
	var rows: Array = [
		["LEVEL", str(st.level)],
		["HP", "%s / %s" % [NumberFormat.fmt(floorf(_combat.hp())), NumberFormat.fmt(float(st.hp))]],
		["MAX_HIT", "%s – %s" % [NumberFormat.fmt(float(st.min_hit)), NumberFormat.fmt(float(st.max_hit))]],
		["INTERVAL", NumberFormat.fmt_time(float(st.interval))],
		["AP", NumberFormat.fmt(float(st.ap))],
		["ACC", NumberFormat.fmt(float(st.acc))],
		["EVA", NumberFormat.fmt(float(st.eva))],
		["ARMOR", NumberFormat.fmt(float(st.arm))],
		["WARD", NumberFormat.fmt(float(st.ward))],
		["CRIT", NumberFormat.fmt_pct(float(st.crit) * 100.0)],
		["CRITD", NumberFormat.fmt_pct(float(st.critd) * 100.0)],
		["REGEN", NumberFormat.fmt_pct(float(st.regen_pct)) + "/s"],
	]
	var stats_sig := "%s|%s" % [Loc.locale(), JSON.stringify(rows)]
	if stats_sig == _stats_sig:
		return                              # niente da rifare: i tooltip di calcolo costano (UI-A G18)
	_stats_sig = stats_sig
	for c in _stats_box.get_children():
		c.queue_free()
	for r in rows:
		var name_l := _lbl("UI_HERO_ST_" + str(r[0]), "MutedLabel")
		var val_l := _val(str(r[1]))
		var tip := _stat_tip(str(r[0]))
		if not tip.is_empty():              # tooltip di calcolo (UI-A G18): da dove viene il numero
			tip += "\n" + tr("UI_BONUS_STAT_TIP_MORE")
			for l in [name_l, val_l]:
				(l as Label).mouse_filter = Control.MOUSE_FILTER_STOP
				(l as Label).tooltip_text = tip
				(l as Label).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				(l as Label).gui_input.connect(func(ev: InputEvent) -> void:      # clic = elenco dei bonus attivi
					var mb := ev as InputEventMouseButton
					if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
						BonusDialog.open_on(self))
		_stats_box.add_child(name_l)
		_stats_box.add_child(val_l)


## Riga del pannello -> statistica di StatBreakdown.
const STAT_TIP_KEYS := {"HP": "hp", "MAX_HIT": "max_hit", "INTERVAL": "interval", "AP": "ap", "ACC": "acc", "EVA": "eva",
	"ARMOR": "arm", "WARD": "ward", "CRIT": "crit", "CRITD": "critd", "REGEN": "regen_pct"}


func _stat_tip(row_key: String) -> String:
	if not STAT_TIP_KEYS.has(row_key):
		return ""
	return str(StatBreakdown.explain(_combat, str(STAT_TIP_KEYS[row_key])).get("formula", ""))


func _item_name(def_id: String) -> String:
	return Loc.t(DataRegistry.item(def_id).get("name", def_id))
