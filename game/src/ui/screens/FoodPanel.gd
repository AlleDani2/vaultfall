class_name FoodPanel
extends PanelContainer
## Blocco «Cibo» ben visibile (schermate Combattimento ed Eroe): gli SLOT del cibo dell'Eroe, il clic per scegliere dal Deposito
## cosa assegnare, la soglia «mangia sotto X% di vita» con spiegazione, la scorta («dura circa N min» contro il mostro
## scelto), il collegamento al «Sicuro in idle» e, se non c'è cibo, il rimando alla Cucina e al Mercato.
## Con `show_supplies` aggiunge anche le munizioni dell'arma e la pozione di combattimento.
## Modello del gioco (docs/05 §6): ogni slot indica UN tipo di cibo e si mangia da tutte le porzioni di quel tipo nel Deposito,
## dal primo slot che ne ha. Solo presentazione: legge e comanda CombatSystem (set_food, set_eat_pct, eat_food, equip_ammo, use_potion).

signal changed

const SAFE_COLORS := {"green": Color("5fbf6a"), "yellow": Color("e0b640"), "red": Color("d9544d")}
const COL_ACCENT := Color(0.93, 0.76, 0.42)

## Mostro contro cui stimare la durata della scorta («» = nessuno: la stima non compare). Lo imposta la schermata.
var target_monster: String = ""
var show_supplies: bool = false
## F8: modo compatto (schermata Combattimento): UNA riga con titolo, 3 slot, soglia, «Mangia ora» e ⓘ; i paragrafi delle regole
## stanno nel riquadro che si apre con ⓘ (e nel suo tooltip), niente chip «Sicuro in idle» (sta nella testata della schermata).
var compact: bool = false

var _combat: CombatSystem
var _bank: BankSystem
var _title: Label
var _badge: Label
var _intro: Label
var _slots_row: HBoxContainer
var _slot_btns: Array[EquipSlotButton] = []
var _order_note: Label
var _eat_label: Label
var _eat_slider: HSlider
var _eat_btn: Button
var _eat_info: Label
var _info_btn: Button
var _explain_box: VBoxContainer
var _stock: Label
var _empty_box: VBoxContainer
var _empty_lbl: Label
var _go_row: HBoxContainer
var _popup: PopupMenu
var _pick_slot := 0
var _pick_defs: Array = []
var _supplies: VBoxContainer
var _ammo_lbl: Label
var _ammo_btn: Button
var _ammo_clear: Button
var _ammo_popup: PopupMenu
var _ammo_defs: Array = []
var _pot_lbl: Label
var _pot_btn: Button
var _pot_popup: PopupMenu
var _pot_defs: Array = []
var _sig := ""


func _init(with_supplies: bool = false, is_compact: bool = false) -> void:
	show_supplies = with_supplies
	compact = is_compact
	theme_type_variation = &"ContentPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_combat = Game.system("combat") as CombatSystem
	_bank = Game.system("bank") as BankSystem
	_build()
	refresh(true)


func _build() -> void:
	if compact:
		_build_compact()
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_title = Label.new()
	_title.text = "UI_HERO_FOOD"
	_title.theme_type_variation = &"SectionLabel"
	head.add_child(_title)
	_badge = _wrap(&"")
	_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_badge.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(_badge)
	_intro = _wrap(&"MutedLabel")
	_intro.text = tr("UI_EQ_FOOD_INTRO")
	v.add_child(_intro)
	# corpo in due colonne (nel contenuto stretto a 1280x720 la colonna destra è ~500 px): a sinistra gli slot, a destra la soglia
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 4)
	lcol.custom_minimum_size.x = EquipSlotButton.SIZE_SMALL.x * 3 + 12
	body.add_child(lcol)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 6)
	lcol.add_child(_slots_row)
	var n := _combat.food_slots().size()
	for i in n:
		var b := EquipSlotButton.new("food:%d" % i, true)
		b.pressed.connect(_open_picker.bind(i))
		b.context_requested.connect(func(_p: Vector2) -> void: _clear_slot(i))
		_slots_row.add_child(b)
		_slot_btns.append(b)
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcol.add_theme_constant_override("separation", 4)
	body.add_child(rcol)
	# soglia di auto-mangiare
	_eat_label = _wrap(&"")
	_eat_label.custom_minimum_size = Vector2(120, 0)
	rcol.add_child(_eat_label)
	var eat_row := HBoxContainer.new()
	eat_row.add_theme_constant_override("separation", 8)
	rcol.add_child(eat_row)
	_eat_slider = HSlider.new()
	_eat_slider.custom_minimum_size = Vector2(80, 0)
	_eat_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eat_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_eat_slider.min_value = 1
	_eat_slider.step = 1
	_eat_slider.tooltip_text = "UI_EQ_FOOD_SLIDER_TIP"
	_eat_slider.value_changed.connect(func(val: float) -> void:
		_combat.set_eat_pct(int(val))
		refresh(true))
	eat_row.add_child(_eat_slider)
	_eat_btn = Button.new()
	_eat_btn.text = "UI_HERO_EAT_NOW"
	_eat_btn.pressed.connect(func() -> void:
		_combat.eat_food(true)
		refresh(true))
	eat_row.add_child(_eat_btn)
	# i testi lunghi stanno a tutta larghezza sotto le due colonne (nella colonna stretta a 1280x720 andavano a capo ogni due parole)
	_stock = _wrap(&"")
	v.add_child(_stock)
	_eat_info = _wrap(&"MutedLabel")
	v.add_child(_eat_info)
	_order_note = _wrap(&"MutedLabel")
	_order_note.text = tr("UI_EQ_FOOD_ORDER")
	v.add_child(_order_note)
	_empty_box = VBoxContainer.new()
	_empty_box.add_theme_constant_override("separation", 4)
	v.add_child(_empty_box)
	_empty_lbl = _wrap(&"")
	_empty_lbl.add_theme_color_override("font_color", SAFE_COLORS["red"])
	_empty_box.add_child(_empty_lbl)
	_go_row = HBoxContainer.new()
	_go_row.add_theme_constant_override("separation", 8)
	_empty_box.add_child(_go_row)
	_popup = PopupMenu.new()
	_popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_popup.id_pressed.connect(_on_food_picked)
	add_child(_popup)
	if show_supplies:
		_build_supplies(v)


## F8: una riga sola. [Cibo] [slot 1-2-3] [soglia: etichetta + cursore + «Mangia ora» + ⓘ]. Le regole (intro, scorta, spiegazione,
## ordine degli slot) vanno nel riquadro che ⓘ apre e nel tooltip di ⓘ; la scorta e «non si consuma» anche lì.
func _build_compact() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 4)
	v.add_child(row)
	_title = Label.new()
	_title.text = "UI_HERO_FOOD"
	_title.theme_type_variation = &"SectionLabel"
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 6)
	row.add_child(_slots_row)
	var n := _combat.food_slots().size()
	for i in n:
		var b := EquipSlotButton.new("food:%d" % i, true)
		b.pressed.connect(_open_picker.bind(i))
		b.context_requested.connect(func(_p: Vector2) -> void: _clear_slot(i))
		_slots_row.add_child(b)
		_slot_btns.append(b)
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rcol.custom_minimum_size.x = 230
	rcol.add_theme_constant_override("separation", 4)
	row.add_child(rcol)
	_eat_label = _wrap(&"")
	rcol.add_child(_eat_label)
	var eat_row := HBoxContainer.new()
	eat_row.add_theme_constant_override("separation", 8)
	rcol.add_child(eat_row)
	_eat_slider = HSlider.new()
	_eat_slider.custom_minimum_size = Vector2(80, 0)
	_eat_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eat_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_eat_slider.min_value = 1
	_eat_slider.step = 1
	_eat_slider.tooltip_text = "UI_EQ_FOOD_SLIDER_TIP"
	_eat_slider.value_changed.connect(func(val: float) -> void:
		_combat.set_eat_pct(int(val))
		refresh(true))
	eat_row.add_child(_eat_slider)
	_eat_btn = Button.new()
	_eat_btn.text = "UI_HERO_EAT_NOW"
	_eat_btn.pressed.connect(func() -> void:
		_combat.eat_food(true)
		refresh(true))
	eat_row.add_child(_eat_btn)
	_info_btn = Button.new()
	_info_btn.name = "FoodInfoButton"
	_info_btn.text = "ⓘ"
	_info_btn.toggle_mode = true
	_info_btn.focus_mode = Control.FOCUS_ALL
	_info_btn.toggled.connect(func(on: bool) -> void: _explain_box.visible = on)
	eat_row.add_child(_info_btn)
	# riquadro delle regole: chiuso finché non si preme ⓘ (i tre paragrafi di prima + la scorta)
	_explain_box = VBoxContainer.new()
	_explain_box.add_theme_constant_override("separation", 4)
	_explain_box.visible = false
	v.add_child(_explain_box)
	_badge = _wrap(&"")                       # non si mostra: il rischio sta nel chip della testata (D18)
	_badge.visible = false
	_explain_box.add_child(_badge)
	_intro = _wrap(&"MutedLabel")
	_intro.text = tr("UI_EQ_FOOD_INTRO")
	_explain_box.add_child(_intro)
	_stock = _wrap(&"")
	_explain_box.add_child(_stock)
	_eat_info = _wrap(&"MutedLabel")
	_explain_box.add_child(_eat_info)
	_order_note = _wrap(&"MutedLabel")
	_order_note.text = tr("UI_EQ_FOOD_ORDER")
	_explain_box.add_child(_order_note)
	_empty_box = VBoxContainer.new()
	_empty_box.add_theme_constant_override("separation", 4)
	v.add_child(_empty_box)
	_empty_lbl = _wrap(&"")
	_empty_lbl.add_theme_color_override("font_color", SAFE_COLORS["red"])
	_empty_box.add_child(_empty_lbl)
	_go_row = HBoxContainer.new()
	_go_row.add_theme_constant_override("separation", 8)
	_empty_box.add_child(_go_row)
	_popup = PopupMenu.new()
	_popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_popup.id_pressed.connect(_on_food_picked)
	add_child(_popup)
	if show_supplies:
		_build_supplies(v)


func _build_supplies(v: VBoxContainer) -> void:
	_supplies = VBoxContainer.new()
	_supplies.add_theme_constant_override("separation", 4)
	v.add_child(_supplies)
	_supplies.add_child(HSeparator.new())
	var ammo := HBoxContainer.new()
	ammo.add_theme_constant_override("separation", 8)
	_supplies.add_child(ammo)
	_ammo_lbl = _wrap(&"")
	_ammo_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ammo.add_child(_ammo_lbl)
	_ammo_btn = Button.new()
	_ammo_btn.text = "UI_EQ_SUP_CHOOSE"
	_ammo_btn.pressed.connect(_open_ammo_picker)
	ammo.add_child(_ammo_btn)
	_ammo_clear = Button.new()
	_ammo_clear.text = "UI_EQ_REMOVE"
	_ammo_clear.pressed.connect(func() -> void:
		_combat.unequip("ammo")
		changed.emit()
		refresh(true))
	ammo.add_child(_ammo_clear)
	var pot := HBoxContainer.new()
	pot.add_theme_constant_override("separation", 8)
	_supplies.add_child(pot)
	_pot_lbl = _wrap(&"")
	_pot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pot.add_child(_pot_lbl)
	_pot_btn = Button.new()
	_pot_btn.text = "UI_EQ_SUP_DRINK"
	_pot_btn.pressed.connect(_open_potion_picker)
	pot.add_child(_pot_btn)
	_ammo_popup = PopupMenu.new()
	_ammo_popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ammo_popup.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < _ammo_defs.size() and _combat.equip_ammo(str(_ammo_defs[id])):
			changed.emit()
			refresh(true))
	add_child(_ammo_popup)
	_pot_popup = PopupMenu.new()
	_pot_popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_pot_popup.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < _pot_defs.size() and _combat.use_potion(str(_pot_defs[id])):
			changed.emit()
			refresh(true))
	add_child(_pot_popup)


func _wrap(variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	return l


# ------------------------------------------------------------------ aggiornamento

func _signature() -> String:
	var bank_n := 0
	for it in DataRegistry.items_by_category("food"):
		bank_n += int(_bank.count(str(it.id))) * 3 + 1
	return "%s|%s|%d|%s|%s|%s|%s|%s|%s" % [JSON.stringify(_combat.food_slots()), target_monster, bank_n, str(_combat.state.eat_pct), Loc.locale(),
		str(_combat.hero_level()), JSON.stringify(_combat.auto_eat_cfg()), JSON.stringify(GameState.data.get("equipment", {}).get("ammo", {})),
		str(_combat.active_potion()) + str(_combat.in_combat())]


func refresh(force: bool = false) -> void:
	if _combat == null or _bank == null or not is_inside_tree():
		return
	var sig := _signature()
	# la stima della durata dipende dal Deposito intero (cibo mangiato durante lo scontro): ricalcolo comunque ogni 10 refresh
	if not force and sig == _sig:
		return
	_sig = sig
	var safety := _safety()
	_refresh_slots(safety)
	_refresh_eat()
	_refresh_stock(safety)
	_refresh_empty()
	if show_supplies:
		_refresh_supplies()


func _safety() -> Dictionary:
	if target_monster.is_empty() or _combat.in_dungeon():
		return {}
	return _combat.idle_safety(target_monster)


static func _item_name(def_id: String) -> String:
	return Loc.t(DataRegistry.item(def_id).get("name", def_id))


func _foods_in_bank() -> Array:
	var out: Array = []
	for it in DataRegistry.items_by_category("food"):
		if it.has("food") and _bank.count(str(it.id)) > 0:
			out.append(str(it.id))
	return out


static func _food_silhouette() -> Texture2D:
	var best := ""
	var best_tier := 999
	for it in DataRegistry.items_by_category("food"):
		if it.has("food") and int(it.get("tier", 99)) < best_tier:
			best_tier = int(it.get("tier", 99))
			best = str(it.id)
	return EquipDoll.item_icon(best) if not best.is_empty() else null


## Durata della scorta di un cibo in secondi, contro il mostro scelto. -1 = non si consuma (il mostro non toglie vita).
func _duration_s(safety: Dictionary, def_id: String) -> float:
	if safety.is_empty() or not bool(safety.get("losing", false)):
		return -1.0
	var loss_hp_h := float(safety.food_per_h) * _combat.food_heal(_first_assigned())
	var heal := _combat.food_heal(def_id)
	if loss_hp_h <= 0.0 or heal <= 0.0:
		return -1.0
	return float(_bank.count(def_id)) * heal / loss_hp_h * 3600.0


func _first_assigned() -> String:
	var first: String = str(_combat.food_info().get("def", ""))
	if not first.is_empty():
		return first
	for fid in _combat.food_slots():
		if not str(fid).is_empty():
			return str(fid)
	return ""


func _refresh_slots(safety: Dictionary) -> void:
	var slots := _combat.food_slots()
	var avail := _foods_in_bank()
	for i in _slot_btns.size():
		var b := _slot_btns[i]
		var fid := str(slots[i])
		b.set_slot_name(Loc.tf("UI_EQ_FOOD_SLOT", {"n": i + 1}))
		b.set_selected(false)
		b.set_state_text("")
		if fid.is_empty():
			b.set_frame("slot_common", Color(1.0, 0.9, 0.62) if not avail.is_empty() else Color(1, 1, 1, 0.55))
			b.show_empty(_food_silhouette(), tr("UI_EQ_FOOD_PICK") if not avail.is_empty() else tr("UI_EQ_EMPTY"), not avail.is_empty())
			b.set_item("")
			b.tooltip_text = tr("UI_EQ_FOOD_SLOT_TIP_EMPTY")
		else:
			var qty := _bank.count(fid)
			b.set_frame("slot_rare" if qty > 0 else "slot_common", Color.WHITE if qty > 0 else Color(1, 0.6, 0.55))
			b.show_item(EquipDoll.item_icon(fid), "%s ×%s" % [_item_name(fid), NumberFormat.fmt(qty)])
			b.set_item(fid)
			b.tooltip_text = " "
			var dur := _duration_s(safety, fid)
			if qty <= 0:
				b.set_state_text(tr("UI_EQ_FOOD_SLOT_OUT"), SAFE_COLORS["red"])
			elif dur >= 0.0:
				b.set_state_text(Loc.tf("UI_EQ_FOOD_SLOT_LASTS", {"t": NumberFormat.fmt_time(dur)}), Color(0.82, 0.8, 0.72))
			else:
				b.set_state_text(Loc.tf("UI_EQ_FOOD_SLOT_HEAL", {"heal": NumberFormat.fmt(floorf(_combat.food_heal(fid)))}), Color(0.82, 0.8, 0.72))


func _refresh_eat() -> void:
	var cfg := _combat.auto_eat_cfg()
	var tier_max := _combat.auto_eat_max_pct()     # il massimo non cala quando si abbassa la soglia (cfg.threshold_pct sì)
	var cur := float(cfg.threshold_pct)
	_eat_slider.min_value = 1
	_eat_slider.max_value = maxf(2.0, tier_max)
	_eat_slider.set_value_no_signal(cur)
	_eat_label.text = Loc.tf("UI_HERO_EAT_BELOW", {"pct": int(cur)})
	_eat_info.text = Loc.tf("UI_EQ_FOOD_EXPLAIN", {"target": int(cfg.target_pct), "eff": int(round(float(cfg.efficiency) * 100.0)),
		"max": int(tier_max)})
	_eat_btn.disabled = _combat.food_available() <= 0


func _refresh_stock(safety: Dictionary) -> void:
	var n := _combat.food_available()
	var fi := _combat.food_info()
	var parts := PackedStringArray()
	parts.append(Loc.tf("UI_EQ_FOOD_STOCK", {"n": NumberFormat.fmt(n)}))
	var col := Color(0.92, 0.9, 0.82)
	if bool(fi.blocked):
		parts = PackedStringArray([tr("UI_C3_FOOD_BLOCKED")])
		col = SAFE_COLORS["yellow"]
	elif not safety.is_empty():
		var lvl := str(safety.level)
		if not bool(safety.get("losing", false)):
			parts.append(tr("UI_EQ_FOOD_NOT_USED"))
		else:
			var hours := float(safety.food_hours)
			if n > 0 and hours >= 0.0:
				parts.append(Loc.tf("UI_EQ_FOOD_LASTS", {"t": NumberFormat.fmt_time(hours * 3600.0),
					"name": Loc.t(DataRegistry.get_def("monsters", target_monster).get("name", target_monster))}))
		col = SAFE_COLORS.get(lvl, col)
		var hrs: String = tr("UI_COMBAT_FOOD_INF") if float(safety.food_hours) < 0.0 else NumberFormat.fmt_time(float(safety.food_hours) * 3600.0)
		_badge.tooltip_text = Loc.tf("UI_COMBAT_SAFE_TIP", {"hit": NumberFormat.fmt(float(safety.worst_hit)),
			"thr": NumberFormat.fmt(float(safety.threshold_hp)), "food": hrs})
	elif target_monster.is_empty():
		parts.append(tr("UI_EQ_FOOD_PICK_TARGET"))
	_stock.text = " · ".join(parts)
	_stock.add_theme_color_override("font_color", col)
	# etichetta «Sicuro in idle» accanto al titolo (stesso indicatore della colonna di sinistra); compatto: c'è il chip della testata
	if compact:
		_badge.text = ""
		_refresh_info_tip()
	elif safety.is_empty():
		_badge.text = ""
	else:
		var lvl2 := str(safety.level)
		_badge.text = "● " + tr("UI_COMBAT_SAFE_RED_FOOD" if (lvl2 == "red" and str(safety.get("reason", "")) == "food") else "UI_COMBAT_SAFE_" + lvl2.to_upper())
		_badge.add_theme_color_override("font_color", SAFE_COLORS.get(lvl2, Color.WHITE))


## Tooltip di ⓘ (modo compatto): scorta (con «non si consuma» / «dura circa…») e le regole del Cibo.
func _refresh_info_tip() -> void:
	if _info_btn == null:
		return
	_info_btn.tooltip_text = "\n\n".join(PackedStringArray([_stock.text, _intro.text, _eat_info.text, _order_note.text]))


func _refresh_empty() -> void:
	var n := _combat.food_available()
	var slots_set := false
	for fid in _combat.food_slots():
		slots_set = slots_set or not str(fid).is_empty()
	var avail := _foods_in_bank()
	for c in _go_row.get_children():
		_go_row.remove_child(c)
		c.queue_free()
	if n > 0:
		_empty_box.visible = false
		return
	_empty_box.visible = true
	if not avail.is_empty() and not slots_set:
		_empty_lbl.text = tr("UI_EQ_FOOD_ASSIGN_HINT")
		_empty_lbl.add_theme_color_override("font_color", COL_ACCENT)
		return
	_empty_lbl.text = tr("UI_EQ_FOOD_NONE_GO")
	_empty_lbl.add_theme_color_override("font_color", SAFE_COLORS["red"])
	var cook := ReqLink.target_for_level("cooking")
	if not cook.is_empty():
		_go_row.add_child(_go_button(tr("UI_EQ_GO_COOK"), cook))
	var e := ScreenRegistry.get_entry("market")
	if not e.is_empty() and ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		_go_row.add_child(_go_button(tr("UI_EQ_GO_MARKET"), {"screen": "market", "params": {}, "hint": ""}))


func _go_button(text: String, target: Dictionary) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.pressed.connect(ReqLink.go.bind(target))
	return b


# ------------------------------------------------------------------ scelta del cibo

func _open_picker(slot_index: int) -> void:
	_pick_slot = slot_index
	_pick_defs.clear()
	_popup.clear()
	var cur := str(_combat.food_slots()[slot_index])
	for fid in _foods_in_bank():
		var heal := NumberFormat.fmt(floorf(_combat.food_heal(fid)))
		_popup.add_icon_item(EquipDoll.item_icon(fid), Loc.tf("UI_EQ_FOOD_PICK_ROW", {"name": _item_name(fid),
			"n": NumberFormat.fmt(_bank.count(fid)), "heal": heal}) + ("  ✓" if fid == cur else ""), _pick_defs.size())
		_pick_defs.append(fid)
	if _pick_defs.is_empty():
		_popup.add_item(tr("UI_EQ_FOOD_PICK_NONE"), 999)
		_popup.set_item_disabled(0, true)
	if not cur.is_empty():
		_popup.add_separator()
		_popup.add_item(tr("UI_EQ_FOOD_CLEAR"), 1000)
	var anchor := _slot_btns[slot_index]
	_popup.position = Vector2i(anchor.get_screen_position() + Vector2(0, anchor.size.y))
	_popup.popup()


func _on_food_picked(id: int) -> void:
	if id == 1000:
		_clear_slot(_pick_slot)
		return
	if id < 0 or id >= _pick_defs.size():
		return
	var fid := str(_pick_defs[id])
	# lo stesso cibo in due slot non serve: si sposta
	var slots := _combat.food_slots()
	for i in slots.size():
		if i != _pick_slot and str(slots[i]) == fid:
			_combat.set_food(i, "")
	if _combat.set_food(_pick_slot, fid):
		EventBus.notice.emit("info", Loc.tf("UI_EQ_FOOD_ASSIGNED", {"name": _item_name(fid), "n": _pick_slot + 1}), {})
		changed.emit()
		refresh(true)


func _clear_slot(i: int) -> void:
	if i < 0 or i >= _combat.food_slots().size() or str(_combat.food_slots()[i]).is_empty():
		return
	_combat.set_food(i, "")
	changed.emit()
	refresh(true)


# ------------------------------------------------------------------ munizioni e pozione

func _refresh_supplies() -> void:
	var wstyle := str(_combat.hero_stats().weapon_style)
	var needs_ammo := wstyle == "ranged" or wstyle == "arcane"
	var cur := _combat.equipped("ammo")
	var ammo_row := _ammo_lbl.get_parent() as Control
	ammo_row.visible = needs_ammo or not cur.is_empty()
	if not cur.is_empty():
		_ammo_lbl.text = Loc.tf("UI_EQ_SUP_AMMO", {"name": _item_name(cur), "n": NumberFormat.fmt(_combat.ammo_qty())})
		_ammo_lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	else:
		_ammo_lbl.text = tr("UI_EQ_SUP_AMMO_NONE")
		_ammo_lbl.add_theme_color_override("font_color", SAFE_COLORS["red"] if needs_ammo else Color(0.7, 0.68, 0.62))
	_ammo_clear.visible = not cur.is_empty()
	_ammo_clear.disabled = _combat.in_combat_blocking()
	var pots := _potions_in_bank()
	var act := _combat.active_potion()
	var pot_row := _pot_lbl.get_parent() as Control
	pot_row.visible = not pots.is_empty() or not act.is_empty()
	_pot_lbl.text = tr("UI_C2_POTION_HINT") if act.is_empty() else \
		Loc.tf("UI_C2_POTION_ACTIVE", {"name": _item_name(str(act.def)), "n": int(act.charges)})
	_pot_btn.disabled = pots.is_empty()
	_supplies.visible = ammo_row.visible or pot_row.visible


func _potions_in_bank() -> Array:
	var out: Array = []
	for it in DataRegistry.items_by_category("potion"):
		if str(it.get("potion", {}).get("scope", "")) == "combat" and _bank.count(str(it.id)) > 0:
			out.append(str(it.id))
	return out


func _open_ammo_picker() -> void:
	_ammo_defs.clear()
	_ammo_popup.clear()
	var wstyle := str(_combat.hero_stats().weapon_style)
	if wstyle.is_empty():
		wstyle = "melee"
	for it in DataRegistry.items_by_category("ammo"):
		if _bank.count(str(it.id)) > 0 and str(it.ammo.get("style", "")) == wstyle:
			_ammo_popup.add_icon_item(EquipDoll.item_icon(str(it.id)), "%s ×%s" % [_item_name(str(it.id)), NumberFormat.fmt(_bank.count(str(it.id)))], _ammo_defs.size())
			_ammo_defs.append(str(it.id))
	if _ammo_defs.is_empty():
		_ammo_popup.add_item(tr("UI_EQ_LIST_EMPTY_AMMO"), 999)
		_ammo_popup.set_item_disabled(0, true)
	_ammo_popup.position = Vector2i(_ammo_btn.get_screen_position() + Vector2(0, _ammo_btn.size.y))
	_ammo_popup.popup()


func _open_potion_picker() -> void:
	_pot_defs = _potions_in_bank()
	_pot_popup.clear()
	for i in _pot_defs.size():
		_pot_popup.add_icon_item(EquipDoll.item_icon(str(_pot_defs[i])), "%s ×%s" % [_item_name(str(_pot_defs[i])), NumberFormat.fmt(_bank.count(str(_pot_defs[i])))], i)
	_pot_popup.position = Vector2i(_pot_btn.get_screen_position() + Vector2(0, _pot_btn.size.y))
	_pot_popup.popup()
