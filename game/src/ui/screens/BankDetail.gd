extends RefCounted
## Pannello di dettaglio del Deposito (F18: estratto da BankScreen per ridurre il costo di apertura; si carica alla prima selezione).
## Solo presentazione: legge BankSystem e costruisce i controlli dentro `s._detail_box`; le azioni restano nella schermata.

const ITEM_USE := "res://src/ui/ItemUse.gd"
const GAP_MECH := "res://src/ui/screens/GapMechUi.gd"

var s: Control                       # BankScreen
var bank: BankSystem


func _init(screen: Control, b: BankSystem) -> void:
	s = screen
	bank = b


func build(e: Dictionary) -> void:
	var def: Dictionary = DataRegistry.item(e.def)
	var icon := TextureRect.new()
	icon.texture = s._icon_for(e.def)
	icon.custom_minimum_size = Vector2(s.DETAIL_ICON_PX, s.DETAIL_ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s._detail_box.add_child(icon)
	var title: Label = s._dyn_label(&"SectionLabel")
	title.text = s._item_name(e.def)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s._detail_box.add_child(title)
	s._add_line(Loc.tf("UI_BANK_D_TIER", {"t": int(def.get("tier", 0))}), true)
	_add_worn_status(e, def)
	_add_use_lines(str(e.def))                                # «A cosa serve» / «Come si usa», generati dai dati (ItemUse)
	var desc := Loc.t(def.get("desc", {}))
	if not desc.is_empty():
		s._add_line(desc, false)
	s._add_line(Loc.tf("UI_BANK_D_QTY", {"n": NumberFormat.fmt(e.qty)}), false)
	var unit := float(def.get("value", 0))
	s._add_line(Loc.tf("UI_BANK_D_VALUE", {"v": NumberFormat.fmt(unit), "total": NumberFormat.fmt(unit * e.qty)}), false)
	if def.has("equipment"):
		_add_equipment(def.equipment, bank.get_instance(e.uid) if e.uid != "" else {})
		_add_compare(str(e.def), bank.get_instance(str(e.uid)) if str(e.uid) != "" else {})
	if def.has("tome"):
		_add_tome_use(e.def)
	if def.has("open_table"):
		var open_btn := Button.new()
		open_btn.name = "OpenButton"
		open_btn.text = "UI_BANK_OPEN"
		open_btn.pressed.connect(func() -> void:
			if not bank.open_item(str(e.def)).is_empty():
				s._mark_dirty())
		s._detail_box.add_child(open_btn)
	if def.has("tool") and e.uid != "":
		_add_tool_equip(e.uid, def)
	if def.has("hourglass"):                                   # G05: Clessidra del Custode
		s._detail_box.add_child((load(GAP_MECH) as GDScript).call("hourglass_box", s._mark_dirty))
	if def.has("equipment") and e.uid != "":                   # G03: Rango degli oggetti
		s._detail_box.add_child((load(GAP_MECH) as GDScript).call("rank_box", e.uid, s._mark_dirty))
	# azioni
	var lock_btn := Button.new()
	lock_btn.text = "UI_BANK_UNLOCK" if e.locked else "UI_BANK_LOCK"
	lock_btn.pressed.connect(s._on_toggle_lock)
	s._detail_box.add_child(lock_btn)
	var sell_btn := Button.new()
	sell_btn.name = "SellButton"
	sell_btn.text = "UI_BANK_QUICK_SELL"
	var market: GameSystem = Game.system("market")
	var why: String = s._sell_block_reason(e, def, market)
	sell_btn.disabled = why != ""
	sell_btn.tooltip_text = why                                # il motivo si legge nel tooltip...
	if why == "":
		sell_btn.pressed.connect(s._on_quick_sell)
	s._detail_box.add_child(sell_btn)
	if why != "":                                               # ...e anche scritto sotto il pulsante (mai un pulsante spento muto)
		s._add_line(why, true)
	_add_dupes_detail(e)
	# Scarta (GUILD-2): libera spazio; rispetta oggetti bloccati e in uso (equipaggiati / Guardaroba / Reliquiario)
	var discard_btn := Button.new()
	discard_btn.text = "UI_GUILD2_BANK_DISCARD"
	var can_n: int = s._discardable(e)
	discard_btn.disabled = can_n <= 0
	discard_btn.tooltip_text = "UI_GUILD2_BANK_DISCARD_HELP" if can_n > 0 else "UI_GUILD2_BANK_DISCARD_BLOCKED"
	discard_btn.pressed.connect(s._on_discard)
	s._detail_box.add_child(discard_btn)
	if e.locked:
		s._add_line("UI_BANK_LOCK_HELP", true)


## «A cosa serve» e «Come si usa» (ItemUse, dai dati) + per gli attrezzi il confronto con quello in uso.
func _add_use_lines(def_id: String) -> void:
	s._add_line(Loc.tf("UI_BANK_D_PURPOSE", {"text": str((load(ITEM_USE) as GDScript).call("purpose", def_id))}), false)
	var how: String = (load(ITEM_USE) as GDScript).call("howto", def_id)
	if how != "":
		s._add_line(how, true)
	var st: String = (load(ITEM_USE) as GDScript).call("tool_status", def_id)
	if st != "":
		s._add_line(st, false)
	s._add_line(str((load(ITEM_USE) as GDScript).call("market_line", def_id)), true)


## Doppioni di questo oggetto: quanti sono e il pulsante per venderli/riciclarli (il primo resta sempre).
func _add_dupes_detail(e: Dictionary) -> void:
	if str(e.uid) == "":
		return
	var n := 0
	for u in bank.duplicate_uids():
		if str(bank.get_instance(str(u)).get("def", "")) == str(e.def):
			n += 1
	if n <= 0:
		return
	s._add_line(Loc.tf("UI_BANK_D_DUPES", {"n": n + 1, "extra": n}), false)


## Stato «indossato» ben visibile nel dettaglio (FEEDBACK EQUIP-UI): in quale slot, il codice che distingue due pezzi uguali,
## e i pulsanti per equipaggiare / togliere senza passare dalla schermata Eroe.
func _add_worn_status(e: Dictionary, def: Dictionary) -> void:
	var cb := Game.system("combat") as CombatSystem
	var wearable: bool = str(e.uid) != "" and (def.has("equipment") or def.has("tool"))
	if str(e.worn) != "":
		var l: Label = s._dyn_label(&"SectionLabel")
		if str(e.worn) == "food":
			l.text = Loc.tf("UI_EQ_BANK_D_FOOD", {"n": cb.food_slots().find(str(e.def)) + 1}) if cb != null else ""
		elif str(e.worn) == "ammo":
			l.text = Loc.tf("UI_EQ_BANK_BADGE_TIP", {"slot": tr("UI_HERO_SLOT_AMMO")})
		else:
			l.text = Loc.tf("UI_EQ_BANK_D_WORN", {"slot": str(e.worn_name)})
		l.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s._detail_box.add_child(l)
	elif wearable:
		s._add_line("UI_EQ_BANK_D_NOT_WORN", true)
	if str(e.uid) != "":
		s._add_line(Loc.tf("UI_EQ_BANK_D_ID", {"id": ItemLabel.short_id(str(e.uid))}), true)
		var fin := _finish_of(str(e.uid))
		if not fin.is_empty():
			s._add_line(Loc.tf("UI_EQ_BANK_D_FINISH", {"name": fin}), true)
	if not wearable or cb == null or def.has("tool"):
		return                                  # gli attrezzi hanno già il loro pulsante «Usa come attrezzo»
	var b := Button.new()
	b.name = "WornButton"
	if str(e.worn) != "":
		b.text = "UI_EQ_BANK_UNEQUIP"
		b.disabled = cb.in_combat_blocking() or str(e.worn).begins_with("tool:")
		b.pressed.connect(func() -> void:
			if cb.worn_slot(str(e.uid)) != "":
				cb.unequip(cb.worn_slot(str(e.uid)))
			s._mark_dirty())
	else:
		var chk := cb.equip_check(str(e.uid))
		b.text = "UI_EQ_BANK_EQUIP"
		b.theme_type_variation = &"AccentButton"
		b.disabled = not bool(chk.ok)
		if not bool(chk.ok):
			var why := str(chk.why)
			b.tooltip_text = Loc.tf(why, chk.args) if why != "UI_EQ_WHY_WORN" else ""
		else:
			b.tooltip_text = Loc.tf("UI_EQ_BANK_EQUIP_WHERE", {"slot": ItemLabel.slot_name(str(chk.slot))})
		b.pressed.connect(func() -> void:
			if cb.equip(str(e.uid)):
				EventBus.notice.emit("info", Loc.tf("UI_EQ_EQUIPPED_NOTICE", {"name": ItemLabel.label(bank.get_instance(str(e.uid))),
					"slot": ItemLabel.slot_name(cb.worn_slot(str(e.uid)))}), {})
			s._mark_dirty())
	s._detail_box.add_child(b)


## Finitura del Guardaroba montata su questo pezzo: nome (con simbolo di rarità) o «» se nessuna.
func _finish_of(uid: String) -> String:
	var cb := Game.system("combat") as CombatSystem
	var slot := cb.worn_slot(uid) if cb != null else ""
	return ItemLabel.finish_text(slot) if not slot.is_empty() else ""


## Tomo dell'Esperienza (ricompense delle missioni): scelta della mansione sbloccata e anteprima degli XP.
func _add_tome_use(item_id: String) -> void:
	var sk := Game.system("skills") as SkillSystem
	if sk == null:
		return
	var opt := OptionButton.new()
	opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	opt.fit_to_longest_item = false
	var ids: Array = []
	for sd in DataRegistry.table("skills"):
		if sk.is_unlocked(str(sd.id)):
			ids.append(str(sd.id))
			opt.add_item("%s (+%s XP)" % [Loc.t(sd.name), NumberFormat.fmt(sk.tome_xp(item_id, str(sd.id)))])
	if ids.is_empty():
		return
	s._add_line("UI_INTEG_TOME_PICK", true)
	s._detail_box.add_child(opt)
	var use := Button.new()
	use.text = "UI_INTEG_TOME_USE"
	use.pressed.connect(func() -> void:
		if opt.selected >= 0 and sk.use_tome(item_id, str(ids[opt.selected])):
			s._mark_dirty())
	s._detail_box.add_child(use)


## Attrezzo di mansione (ascia, piccone…): si mette in uso da qui (prima nessuna schermata lo permetteva).
func _add_tool_equip(uid: String, def: Dictionary) -> void:
	var cb: GameSystem = Game.system("combat")
	if cb == null or not cb.has_method("equip_tool"):
		return
	var skill := str(def.tool.get("skill", ""))
	var in_use := str(GameState.data.get("equipment", {}).get("tools", {}).get(skill, "")) == uid
	var b := Button.new()
	b.text = "UI_INTEG_TOOL_IN_USE" if in_use else "UI_INTEG_TOOL_EQUIP"
	b.disabled = in_use
	b.pressed.connect(func() -> void:
		if bool(cb.call("equip_tool", uid)):
			s._mark_dirty())
	s._detail_box.add_child(b)


## Statistiche base dell'oggetto, scalate dalla qualità dell'istanza (come Formulas.hero_stats; il grado non è
## ancora applicato: arriva con l'Era II).
func _add_equipment(eq: Dictionary, inst: Dictionary) -> void:
	var mult := 1.0
	var quality := str(inst.get("quality", ""))
	if not quality.is_empty():
		for qd in DataRegistry.constants.get("quality", []):
			if qd.id == quality:
				mult = float(qd.mult)
		s._add_line(Loc.tf("UI_BANK_D_QUALITY", {"q": s._quality_label(quality)}), false)
	s._add_line(Loc.tf("UI_BANK_D_SLOT", {"slot": tr("UI_BANK_SLOT_" + str(eq.get("slot", "")).to_upper()), "lv": int(eq.get("level_req", 1))}), true)
	if eq.has("damage"):
		s._add_line(Loc.tf("UI_BANK_D_DAMAGE", {"d": NumberFormat.fmt(float(eq.damage) * mult),
			"s": NumberFormat.decimal(float(eq.get("attack_interval_s", 0.0)), 1, Loc.locale())}), false)
	for k in eq.get("stats", {}):
		var v := float(eq.stats[k])
		var shown := NumberFormat.fmt_pct(v * 100.0) if k == "crit_chance" else NumberFormat.decimal(v * mult, 1, Loc.locale())
		s._add_line("%s %s" % [tr(s.STAT_KEYS.get(k, "UI_BANK_STAT_OTHER")) if s.STAT_KEYS.has(k) else str(k), shown], false)
	for m in eq.get("modifiers", []):
		var fam: Dictionary = DataRegistry.modifier_family(str(m.key).split(":")[0])
		s._add_line("%s: %s" % [Loc.t(fam.get("desc", {})) if not fam.is_empty() else str(m.key), NumberFormat.fmt(float(m.value))], false)


## Confronto con ciò che l'eroe indossa nello stesso slot (docs/16 §4): differenze verdi/rosse sulle statistiche.
func _add_compare(def_id: String, inst: Dictionary) -> void:
	var c := ItemTooltip.build(def_id, inst)
	if c.is_empty() or not bool(c.has_compare):
		return
	var head: Label = s._dyn_label(&"SectionLabel")
	head.text = Loc.tf("UI_UIA_TIP_VS", {"name": c.compare_name})
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s._detail_box.add_child(head)
	if (c.compare as Array).is_empty():
		s._add_line("UI_UIA_TIP_SAME", true)
	for r in c.compare:
		var l: Label = s._dyn_label()
		l.text = str(r.text)
		l.add_theme_color_override("font_color", Color("7fcf8a") if float(r.diff) > 0.0 else Color("d9544d"))
		s._detail_box.add_child(l)
