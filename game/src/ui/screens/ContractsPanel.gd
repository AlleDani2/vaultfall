class_name ContractsPanel
extends VBoxContainer
## Commesse giornaliere e settimanali (docs/12 §6) dentro la schermata Missioni. Solo presentazione: legge ContractSystem
## e chiama claim() / reroll() / buy(). Si ricostruisce solo quando cambia la composizione; le barre si aggiornano sul posto.
## Anti-FOMO: il testo introduttivo dice chiaramente che nulla va perso e che non c'è nessuna penalità.

var _sys: ContractSystem
var _sig: String = ""
var _bars: Array[Dictionary] = []        # {bar, label, id}
var _shop_open: bool = false


func setup(system: ContractSystem) -> void:
	_sys = system
	add_theme_constant_override("separation", 6)
	refresh()


func refresh() -> void:
	if _sys == null:
		return
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
	for b in _bars:
		var e := _sys.entry(str(b.id))
		if e.is_empty():
			continue
		b.bar.max_value = maxf(1.0, float(e.target))
		b.bar.value = float(e.progress)
		b.label.text = "%s / %s" % [NumberFormat.fmt(int(e.progress)), NumberFormat.fmt(int(e.target))]


func _signature() -> String:
	var parts: PackedStringArray = []
	for period in ["daily", "weekly"]:
		for e in _sys.contracts(period):
			parts.append("%s:%s" % [e.id, int(e.progress) >= int(e.target)])
	parts.append(str(_sys.tokens()))
	parts.append(str(_sys.free_rerolls_left()))
	parts.append(str(_shop_open))
	parts.append(Loc.locale())
	return "|".join(parts)


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_bars.clear()
	_text("UI_CONTRACTS_TITLE", &"SectionLabel", true)
	_text("UI_CONTRACTS_INTRO", &"MutedLabel", true)
	_text(Loc.tf("UI_CONTRACTS_TOKENS", {"n": NumberFormat.fmt(_sys.tokens())}), &"MonoLabel", false)
	for period in ["daily", "weekly"]:
		var list := _sys.contracts(period)
		_text("UI_CONTRACTS_DAILY" if period == "daily" else "UI_CONTRACTS_WEEKLY", &"SectionLabel", true)
		if list.is_empty():
			_text("UI_CONTRACTS_EMPTY", &"MutedLabel", true)
		for e in list:
			add_child(_card(e))
	_add_shop()


func _text(text: String, variation: StringName, translate: bool) -> void:
	var l := Label.new()
	l.text = text
	if not translate:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	add_child(l)


## Testo della commissione: il modello {it,en} con {qty} {item} {zone} {gold} sostituiti nella lingua attiva.
func contract_text(e: Dictionary) -> String:
	var tpl := {}
	for t in DataRegistry.table("contract_templates"):
		if str(t.id) == str(e.tpl):
			tpl = t
	var p: Dictionary = e.get("text_params", {})
	var params := {"qty": NumberFormat.fmt(int(p.get("qty", e.target))), "gold": NumberFormat.fmt(int(p.get("gold", e.target)))}
	if p.has("item"):
		params["item"] = Loc.t(DataRegistry.item(str(p.item)).get("name", p.item))
	if p.has("zone"):
		params["zone"] = Loc.t(DataRegistry.get_def("zones", str(p.zone)).get("name", p.zone))
	return Loc.t(tpl.get("text", "")).format(params)


func _card(e: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Contract_" + str(e.id)
	card.theme_type_variation = &"ContentPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var t := Label.new()
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.text = contract_text(e)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(120, 18)
	row.add_child(bar)
	var num := Label.new()
	num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	num.theme_type_variation = &"MonoLabel"
	num.custom_minimum_size.x = 110
	row.add_child(num)
	v.add_child(row)
	_bars.append({"bar": bar, "label": num, "id": str(e.id)})
	var done := int(e.progress) >= int(e.target)
	var left := _sys.days_left(str(e.id))
	var info := Label.new()
	info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	info.theme_type_variation = &"MutedLabel"
	info.text = Loc.tf("UI_CONTRACTS_REWARD_LINE", {"tokens": _reward_tokens(str(e.period)), "gold": NumberFormat.fmt(int(e.gold))}) \
			+ ("" if left < 0 else "  ·  " + Loc.tf("UI_CONTRACTS_DAYS_LEFT", {"n": left + 1}))
	v.add_child(info)
	if done:
		var b := Button.new()
		b.name = "ClaimContract"
		b.text = "UI_QUESTS_CLAIM"
		b.theme_type_variation = &"AccentButton"
		var cid := str(e.id)
		b.pressed.connect(func() -> void:
			_sys.claim(cid)
			_sig = ""
			refresh())
		v.add_child(b)
	elif str(e.period) == "daily" and int(e.progress) == 0 and _sys.free_rerolls_left() > 0:
		var rb := Button.new()
		rb.name = "RerollContract"
		rb.text = "UI_CONTRACTS_REROLL"
		var rid := str(e.id)
		rb.pressed.connect(func() -> void:
			_sys.reroll(rid)
			_sig = ""
			refresh())
		v.add_child(rb)
	return card


func _reward_tokens(period: String) -> int:
	return int(DataRegistry.rules("contract_rules").get("rewards", {}).get(period, {}).get("commission_token", 0))


func _add_shop() -> void:
	var toggle := Button.new()
	toggle.name = "ContractShopToggle"
	Disclosure.apply(toggle, "UI_CONTRACTS_SHOP", _shop_open)
	toggle.toggle_mode = true
	toggle.button_pressed = _shop_open
	toggle.toggled.connect(func(on: bool) -> void:
		_shop_open = on
		_sig = ""
		refresh())
	add_child(toggle)
	if not _shop_open:
		return
	for v in DataRegistry.rules("contract_rules").get("token_shop", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = "%s — %s" % [Loc.t(DataRegistry.item(str(v.item)).get("name", v.item)), Loc.tf("UI_CONTRACTS_COST", {"n": int(v.tokens)})]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := Button.new()
		b.text = "UI_CONTRACTS_BUY"
		b.disabled = _sys.tokens() < int(v.tokens)
		var item_id := str(v.item)
		b.pressed.connect(func() -> void:
			_sys.buy(item_id)
			_sig = ""
			refresh())
		row.add_child(b)
		add_child(row)
