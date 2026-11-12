extends GameScreen
## Guardaroba (docs/09 §7): 29 slot in 6 gruppi, una finitura per slot, bonus sempre attivi via Modifiers;
## Reliquiari per le Reliquie ★. Solo presentazione: equipaggiare chiama CrateSystem.equip()/equip_relic().
## Slot vuoti = sagome grigie; a destra, per lo slot scelto: cosa indossi, cosa puoi indossare e da quali casse
## escono le finiture che ti mancano (con «Vai» alla Sala dei Caveau).

const MAX_CHOICES := 50
const TILE := Vector2(90, 84)
const COLS := 4                      # slot per riga in ogni gruppo
const TABS: PackedStringArray = ["worn", "bonus", "reliq"]

var _crates: CrateSystem
var _selected_slot: String = ""
var _signature: String = ""

var _slots_box: VBoxContainer
var _choice_box: VBoxContainer
var _relic_box: VBoxContainer
var _total_box: VBoxContainer
var _summary: Label
var _tab: String = "worn"
var _pages: Dictionary = {}
var _tab_btns: Dictionary = {}


func open(_params: Dictionary) -> void:
	_crates = CrateUi.crates()
	_build()
	_rebuild(true)


func refresh() -> void:
	if _crates != null:
		_rebuild(false)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_pages.clear()
	_tab_btns.clear()
	VaultHead.header(self, "wardrobe", "UI_CRATES_TAB_WARDROBE", "UI_CRATES_WARDROBE_SUB")
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.name = "Tab_" + t
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr("UI_F11_WD_TAB_" + t.to_upper())
		b.pressed.connect(_set_tab.bind(t))
		tabs.add_child(b)
		_tab_btns[t] = b
	_summary = Label.new()
	_summary.theme_type_variation = &"SectionLabel"
	add_child(_summary)

	# --- scheda Indossati: slot per gruppo a sinistra, scelta a destra
	var split := HBoxContainer.new()
	split.name = "PageWorn"
	split.add_theme_constant_override("separation", 10)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_pages["worn"] = split
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(TILE.x * float(COLS) + float(COLS - 1) * 6.0 + 22.0, 0)
	left.size_flags_stretch_ratio = 2.0
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 6)
	left.add_child(_slots_box)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 3.0
	right.custom_minimum_size = Vector2(240, 0)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	_choice_box = VBoxContainer.new()
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_box.add_theme_constant_override("separation", 6)
	right.add_child(_choice_box)

	# --- scheda Bonus attivi
	var bs := ScrollContainer.new()
	bs.name = "PageBonus"
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(bs)
	_pages["bonus"] = bs
	_total_box = VBoxContainer.new()
	_total_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bs.add_child(_total_box)

	# --- scheda Reliquiari
	var rs := ScrollContainer.new()
	rs.name = "PageReliq"
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(rs)
	_pages["reliq"] = rs
	_relic_box = VBoxContainer.new()
	_relic_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_relic_box.add_theme_constant_override("separation", 6)
	rs.add_child(_relic_box)
	_set_tab(_tab)


func _set_tab(t: String) -> void:
	_tab = t
	for k in _pages:
		(_pages[k] as Control).visible = k == t
	for k in _tab_btns:
		(_tab_btns[k] as Button).theme_type_variation = &"AccentButton" if k == t else &""
	_summary.visible = t == "worn"


func _instances() -> Array:
	var bank := CrateUi.bank()
	return bank.list_instances() if bank != null else []


func _signature_now() -> String:
	var parts := PackedStringArray([_selected_slot, str(_crates.state.wardrobe.hash()), str(_crates.state.reliquary.hash()),
		str(_crates.state.relic_slots)])
	var n := 0
	for i in _instances():
		if i.get("kind", "") == "skin" or i.get("kind", "") == "relic":
			n += 1
	parts.append(str(n))
	return "|".join(parts)


func _rebuild(force: bool) -> void:
	var sig := _signature_now()
	if sig == _signature and not force:
		return
	_signature = sig
	_build_slots()
	_build_choices()
	_build_relics()


func _inst(uid: String) -> Dictionary:
	var bank := CrateUi.bank()
	return bank.get_instance(uid) if (bank != null and uid != "") else {}


## Prima finitura dello slot (serve per la sagoma dello slot vuoto).
func _slot_sample(slot: String) -> String:
	for it in DataRegistry.items_by_category("skin"):
		if str(it.skin.slot) == slot:
			return str(it.id)
	return ""


func _build_slots() -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	for c in _total_box.get_children():
		c.queue_free()
	var totals := {}
	var used := 0
	var slots: Array = _crates.wardrobe_slots()
	var group := ""
	var grid: GridContainer = null
	for s in slots:
		if s.group != group:
			group = s.group
			var gl := Label.new()
			gl.text = CrateUi.group_name(group)
			gl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			gl.theme_type_variation = &"SectionLabel"
			_slots_box.add_child(gl)
			grid = GridContainer.new()
			grid.columns = COLS
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			_slots_box.add_child(grid)
		var uid := _crates.equipped(s.slot)
		var inst := _inst(uid)
		if not inst.is_empty():
			used += 1
			for m in _crates.skin_modifiers(inst):
				totals[m.key] = float(totals.get(m.key, 0.0)) + float(m.value)
		grid.add_child(_slot_tile(str(s.slot), inst))
	for uid in _crates.reliquary():
		for m in _crates.relic_modifiers(_inst(str(uid))):
			totals[m.key] = float(totals.get(m.key, 0.0)) + float(m.value)
	_summary.text = Loc.tf("UI_VUX_WD_SLOTS_FILLED", {"n": used, "t": slots.size()})
	var box := VaultKit.card(FxPalette.GOLD_D)
	box.name = "TotalsCard"
	_total_box.add_child(box)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	box.add_child(tv)
	VaultKit.label(tv, tr("UI_VUX_WD_TOTALS"), false, 0, FxPalette.GOLD)
	if totals.is_empty():
		VaultKit.label(tv, tr("UI_CRATES_TOTALS_NONE"), true)
	for k in totals:
		VaultKit.label(tv, CrateUi.mod_text({"key": k, "value": totals[k]}), false, 13)


## Riquadro di uno slot: icona (finitura indossata, oppure sagoma grigia), nome dello slot, stato.
func _slot_tile(slot: String, inst: Dictionary) -> Control:
	var worn := not inst.is_empty()
	var rar := str(inst.get("rarity", "rare")) if worn else "rare"
	var accent := CrateUi.rarity_color(rar) if worn else FxPalette.SMOKE
	var p := VaultKit.card(accent, slot == _selected_slot, not worn)
	p.name = "Slot_" + slot
	p.custom_minimum_size = TILE
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var tex := CrateUi.def_icon(str(inst.def_id)) if worn else CrateUi.def_icon(_slot_sample(slot))
	var ic := VaultKit.pix(tex, 1)
	if not worn:
		ic.modulate = Color(0.34, 0.36, 0.45, 0.9)        # sagoma grigio-azzurra: si riconosce la forma, ma è chiaramente «non c'è»
	v.add_child(ic)
	var n := Label.new()
	n.text = CrateUi.slot_name(slot)
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var st := Label.new()
	st.add_theme_font_size_override("font_size", UiType.NOTE)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if worn:
		st.text = CrateUi.condition_name(str(inst.condition))
		st.add_theme_color_override("font_color", accent)
		p.tooltip_text = CrateUi.instance_text(inst) + "\n" + CrateUi.mods_text(_crates.skin_modifiers(inst))
	else:
		st.text = tr("UI_VUX_WD_FREE")
		st.theme_type_variation = &"MutedLabel"
		p.tooltip_text = "%s: %s\n%s:\n• %s\n• %s\n• %s" % [CrateUi.slot_name(slot), tr("UI_CRATES_SLOT_EMPTY"),
			tr("UI_VUX_HOW_TO_FILL"), tr("UI_VUX_WD_PICK_STEP_1"), tr("UI_VUX_WD_PICK_STEP_2"), tr("UI_VUX_WD_PICK_STEP_3")]
	v.add_child(st)
	VaultKit.make_clickable(p, func() -> void:
		_selected_slot = slot
		_rebuild(true), p.tooltip_text)
	return p


func _owned_defs() -> Dictionary:
	var d := {}
	for i in _instances():
		if str(i.get("kind", "")) == "skin":
			d[str(i.def_id)] = true
	return d


func _build_choices() -> void:
	for c in _choice_box.get_children():
		c.queue_free()
	VaultKit.fade_in(_choice_box)
	if _selected_slot.is_empty():
		VaultKit.label(_choice_box, tr("UI_F11_WD_PICK_HINT"), true).name = "PickHint"
		_build_ready_to_wear()
		return
	var head := Label.new()
	head.text = Loc.tf("UI_CRATES_CHOICES", {"slot": CrateUi.slot_name(_selected_slot)})
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.theme_type_variation = &"SectionLabel"
	_choice_box.add_child(head)
	var slot := _selected_slot
	var worn_uid := _crates.equipped(slot)
	if worn_uid != "":
		var wi := _inst(worn_uid)
		if not wi.is_empty():
			_choice_box.add_child(_choice_row(wi, true, false))
		var off := Button.new()
		off.text = tr("UI_CRATES_UNEQUIP")
		off.pressed.connect(func() -> void:
			_crates.unequip(slot)
			_rebuild(true))
		_choice_box.add_child(off)
	var cands: Array = []
	for i in _instances():
		if i.get("kind", "") != "skin":
			continue
		var d := DataRegistry.item(str(i.def_id))
		if d.is_empty() or str(d.skin.slot) != _selected_slot or str(i.uid) == worn_uid:
			continue
		var mods := _crates.skin_modifiers(i)
		cands.append({"inst": i, "bonus": float(mods[0].value) if not mods.is_empty() else 0.0})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.bonus > b.bonus)
	if cands.is_empty() and worn_uid == "":
		VaultKit.label(_choice_box, tr("UI_VUX_WD_NONE_OWNED"), true)
	for k in mini(cands.size(), MAX_CHOICES):
		_choice_box.add_child(_choice_row(cands[k].inst, false, k == 0 and worn_uid == ""))
	if cands.size() > MAX_CHOICES:
		var more := Label.new()
		more.text = Loc.tf("UI_CRATES_MORE", {"n": cands.size() - MAX_CHOICES})
		more.theme_type_variation = &"MutedLabel"
		more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_choice_box.add_child(more)
	_build_where(slot)


## Pannello di destra senza slot scelto: mai un riquadro vuoto. Le finiture migliori che hai e NON indossi ancora, ciascuna con il
## suo «Indossa» (revisione grafica 1.0, problema correlato al 33: stati vuoti che dicono cosa fare).
func _build_ready_to_wear() -> void:
	var cands: Array = []
	for i in _instances():
		if i.get("kind", "") != "skin" or _crates.is_in_use(str(i.uid)):
			continue
		var mods := _crates.skin_modifiers(i)
		cands.append({"inst": i, "bonus": float(mods[0].value) if not mods.is_empty() else 0.0})
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.bonus > b.bonus)
	CrateUi.section(_choice_box, tr("UI_GB_WD_READY"))
	for k in mini(cands.size(), 5):
		_choice_box.add_child(_choice_row(cands[k].inst, false, k == 0))


## Riga di una finitura: icona, nome nel colore della rarità, condizione, bonus, pulsante «Indossa» (o «indossata»).
func _choice_row(inst: Dictionary, worn: bool, primary: bool) -> Control:
	var rar := str(inst.get("rarity", "rare"))
	var p := VaultKit.card(CrateUi.rarity_color(rar), worn)
	p.tooltip_text = CrateUi.instance_text(inst) + "\n" + CrateUi.mods_text(_crates.skin_modifiers(inst))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(VaultKit.pix(CrateUi.def_icon(str(inst.def_id)), 1))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var n := Label.new()
	n.text = CrateUi.tagged_name(inst)
	n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	n.add_theme_color_override("font_color", CrateUi.rarity_color(rar))
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var mods := _crates.skin_modifiers(inst)
	var bonus := CrateUi.num(float(mods[0].value), 2) if not mods.is_empty() else "0"
	var sub := Label.new()
	sub.text = "%s%s · +%s" % [CrateUi.condition_name(str(inst.condition)), " ✎" if bool(inst.get("annalist", false)) else "", bonus]
	sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	sub.theme_type_variation = &"MutedLabel"
	v.add_child(sub)
	if worn:
		var w := Label.new()
		w.text = tr("UI_VUX_WD_WORN")
		w.theme_type_variation = &"MutedLabel"
		h.add_child(w)
	else:
		var b := Button.new()
		b.text = tr("UI_VUX_WD_EQUIP")
		if primary:
			b.theme_type_variation = &"AccentButton"
		var uid := str(inst.uid)
		b.pressed.connect(func() -> void:
			_crates.equip(uid)
			_rebuild(true))
		h.add_child(b)
	return p


## «Ancora da trovare»: per lo slot scelto, quali casse hanno finiture che non possiedi, con Vai alla Sala dei Caveau.
func _build_where(slot: String) -> void:
	var owned := _owned_defs()
	var by_crate := {}
	for it in DataRegistry.items_by_category("skin"):
		if str(it.skin.slot) != slot:
			continue
		var cid := "crate_" + str(it.get("crate", ""))
		if DataRegistry.item(cid).is_empty():
			continue
		if not by_crate.has(cid):
			by_crate[cid] = {"total": 0, "have": 0}
		by_crate[cid].total += 1
		if owned.has(str(it.id)):
			by_crate[cid].have += 1
	if by_crate.is_empty():
		return
	var h := Label.new()
	h.text = tr("UI_VUX_WD_TO_FIND")
	h.theme_type_variation = &"SectionLabel"
	_choice_box.add_child(h)
	var shown := 0
	for cid in by_crate:
		if by_crate[cid].have >= by_crate[cid].total or shown >= 8:
			continue
		shown += 1
		var p := VaultKit.card(VaultKit.crate_accent(str(cid)), false, true)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		p.add_child(row)
		var ic := VaultKit.pix(CrateUi.def_icon(str(cid)), 1)
		ic.modulate = Color(0.6, 0.6, 0.65)
		row.add_child(ic)
		var l := Label.new()
		l.text = "%s · %d/%d" % [CrateUi.def_name(str(cid)), int(by_crate[cid].have), int(by_crate[cid].total)]
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var hall := ScreenRegistry.get_entry("vault_hall")
		if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
			var go := Button.new()
			go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			go.text = Loc.tf("UI_VUX_GO", {"to": tr("UI_MENU_VAULT_HALL")})
			var target := {"screen": "vault_hall", "params": {"crate": str(cid)}, "hint": ""}
			go.pressed.connect(ReqLink.go.bind(target))
			row.add_child(go)
		_choice_box.add_child(p)


func _build_relics() -> void:
	for c in _relic_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = Loc.tf("UI_CRATES_RELIQUARY", {"used": _crates.reliquary().size(), "n": _crates.relic_slots()})
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.theme_type_variation = &"SectionLabel"
	_relic_box.add_child(head)
	var slots := HFlowContainer.new()
	slots.name = "ReliquarySlots"
	slots.add_theme_constant_override("h_separation", 6)
	slots.add_theme_constant_override("v_separation", 6)
	_relic_box.add_child(slots)
	for uid in _crates.reliquary():
		var inst := _inst(str(uid))
		if inst.is_empty():
			continue
		var p := VaultKit.card(CrateUi.rarity_color("relic"), true)
		p.custom_minimum_size = Vector2(150, 76)
		p.tooltip_text = CrateUi.instance_text(inst) + "\n" + CrateUi.mods_text(_crates.relic_modifiers(inst))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(hb)
		hb.add_child(VaultKit.pix(CrateUi.def_icon(str(inst.def_id)), 1))
		var l := Label.new()
		l.text = CrateUi.tagged_name(inst)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_font_size_override("font_size", UiType.NOTE)
		l.add_theme_color_override("font_color", CrateUi.rarity_color("relic"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		var off := Button.new()
		off.text = tr("UI_CRATES_UNEQUIP")
		var u := str(uid)
		off.pressed.connect(func() -> void:
			_crates.unequip_relic(u)
			_rebuild(true))
		v.add_child(off)
		slots.add_child(p)
	var free_n := _crates.relic_slots() - _crates.reliquary().size()
	for k in maxi(0, free_n):
		var g := VaultKit.card(FxPalette.SMOKE, false, true)
		g.custom_minimum_size = Vector2(150, 76)
		g.tooltip_text = tr("UI_VUX_WD_RELIC_FREE")
		var gl := Label.new()
		gl.text = "★"
		gl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		gl.theme_type_variation = &"MutedLabel"
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_child(gl)
		slots.add_child(g)
	if free_n > 0:
		var n := 0
		var any_relic := false
		for i in _instances():
			if i.get("kind", "") == "relic":
				any_relic = true
				if not _crates.reliquary().has(i.uid) and n < MAX_CHOICES:
					n += 1
					_relic_box.add_child(_relic_option(i))
		if n == 0:
			var gos: Array = []
			var hall := ScreenRegistry.get_entry("vault_hall")
			if not hall.is_empty() and ScreenRegistry.is_available(hall, GameState.data.get("unlocks", [])):
				gos.append({"text": tr("UI_MENU_VAULT_HALL"), "primary": false, "target": {"screen": "vault_hall", "params": {}, "hint": ""}})
			var steps := PackedStringArray([tr("UI_VUX_WD_RELIC_STEP")])
			VaultKit.empty_card(_relic_box, IconLib.icon("relics", "relic_millbrook_1"),
				tr("UI_VUX_WD_RELIC_TITLE") if not any_relic else tr("UI_CRATES_NO_RELICS"),
				tr("UI_VUX_WD_RELIC_WHAT"), steps, gos)


func _relic_option(i: Dictionary) -> Control:
	var p := VaultKit.card(CrateUi.rarity_color("relic"))
	p.tooltip_text = CrateUi.instance_text(i) + "\n" + CrateUi.mods_text(_crates.relic_modifiers(i))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(VaultKit.pix(CrateUi.def_icon(str(i.def_id)), 1))
	var l := Label.new()
	l.text = "%s · %s" % [CrateUi.tagged_name(i), CrateUi.condition_name(str(i.condition))]
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_color_override("font_color", CrateUi.rarity_color("relic"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Button.new()
	b.text = tr("UI_VUX_WD_EQUIP")
	var u := str(i.uid)
	b.pressed.connect(func() -> void:
		_crates.equip_relic(u)
		_rebuild(true))
	h.add_child(b)
	return p
