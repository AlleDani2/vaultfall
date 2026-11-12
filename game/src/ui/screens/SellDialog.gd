class_name SellDialog
extends ConfirmationDialog
## Vendita multipla del Deposito (UI-A G14): filtro per categoria / tier / qualità / rarità, ANTEPRIMA di cosa si vende e
## dell'oro stimato, poi conferma. Non tocca mai oggetti bloccati o indossati (li conta a parte, in chiaro).
## Solo presentazione: raccoglie con SellRules.collect e vende con SellRules.execute (MarketSystem.sell_many / sell_instances).
##
## F17 (docs/ui_redesign/02 §5.5): con setup_selection() la stessa finestra è il PASSAGGIO 2 della vendita a selezione del
## Deposito: elenco di ciò che si vende (quantità per pila, «Tutto/Metà»), oro del Mercato (SellRules.collect_picks: anteprima =
## esito), avvisi (Capolavoro/Eccellente, grado o incastri, «Ti servirà per…»). «Torna indietro» è il pulsante predefinito e ha il
## fuoco; «Vendi» non è mai attivato dal primo Invio (guardia constants.bank.ui.sell_confirm_guard_ms). Nessun annulla dopo.

signal sold(gold: int, pieces: int)

const LIST_MAX := 8

var editor: SellFilterEditor
var preview: Label
var plan: Dictionary = {}
## F17: voci scelte nel Deposito [{def, uid, qty}] (vuoto = vendita per filtro, come prima).
var picks: Array = []
var guard_ms: int = 0
var opened_ms: int = 0
## Orologio (ms): sostituibile nei test.
var clock: Callable = Callable(Time, "get_ticks_msec")
var _help: Label
var _rows: VBoxContainer
var _spins: Dictionary = {}          # def_id -> SpinBox (solo pile)
var _warn: Label


func _init() -> void:
	title = TranslationServer.translate("UI_UIA_SELL_TITLE")
	ok_button_text = TranslationServer.translate("UI_UIA_SELL_OK")
	cancel_button_text = TranslationServer.translate("UI_UIA_SELL_CANCEL")
	min_size = Vector2i(480, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var help := Label.new()
	_help = help
	help.text = "UI_UIA_SELL_HELP"
	help.theme_type_variation = &"MutedLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 440
	box.add_child(help)
	editor = SellFilterEditor.new()
	box.add_child(editor)
	preview = Label.new()
	preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.custom_minimum_size = Vector2(440, 90)
	box.add_child(preview)
	editor.filter_changed.connect(update_preview)
	confirmed.connect(_on_confirmed)
	about_to_popup.connect(_on_about_to_popup)


func _ready() -> void:
	if not picks.is_empty():
		update_preview()
		return
	_preselect_category()
	update_preview()


## Passaggio 2 della vendita a selezione (F17). `p` = [{def, uid, qty}]; `guard` = ms in cui il primo Invio è ignorato.
func setup_selection(p: Array, guard: int) -> void:
	picks = p.duplicate(true)
	guard_ms = maxi(0, guard)
	dialog_hide_on_ok = false
	title = Loc.tf("UI_BANKG_SELLP_TITLE", {"n": NumberFormat.fmt(float(picks.size()))})
	ok_button_text = TranslationServer.translate("UI_BANKG_SELLP_OK")
	cancel_button_text = TranslationServer.translate("UI_BANKG_SELLP_BACK")
	editor.visible = false
	_help.text = "UI_BANKG_SELLP_HELP"
	var scroll := ScrollContainer.new()
	scroll.name = "PickRows"
	scroll.custom_minimum_size = Vector2(440, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help.get_parent().add_child(scroll)
	_help.get_parent().move_child(scroll, _help.get_index() + 1)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_warn = Label.new()
	_warn.name = "Warn"
	_warn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.custom_minimum_size.x = 440
	_warn.add_theme_color_override("font_color", Color(0.98, 0.84, 0.4))
	_help.get_parent().add_child(_warn)
	_build_pick_rows()


func _build_pick_rows() -> void:
	var bank := Game.system("bank") as BankSystem
	var per_def: Dictionary = {}
	for p in picks:
		var def_id := str(p.get("def", ""))
		if str(p.get("uid", "")) != "":
			per_def[def_id] = int(per_def.get(def_id, 0)) + 1
			continue
		var row := HBoxContainer.new()
		var nm := Label.new()
		nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		nm.text = Loc.t(DataRegistry.item(def_id).get("name", def_id))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)
		var mx := bank.sellable_count(def_id) if bank != null else 0
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = maxi(mx, 1)
		spin.value = clampi(int(p.get("qty", mx)), 0, mx)
		spin.select_all_on_focus = true
		spin.value_changed.connect(func(_v: float) -> void: _sync_qty(def_id))
		row.add_child(spin)
		_spins[def_id] = spin
		for half in [false, true]:                       # «Tutto» / «Metà»: mai indovinare a mano l'ultima scorta
			var b := Button.new()
			b.text = "UI_BANKG_SELLP_HALF" if half else "UI_BANKG_SELLP_ALL"
			b.pressed.connect(func() -> void: spin.value = floori(mx * 0.5) if half else mx)
			row.add_child(b)
		_rows.add_child(row)
	for d in per_def:
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = "%s ×%s" % [Loc.t(DataRegistry.item(str(d)).get("name", str(d))), NumberFormat.fmt(float(per_def[d]))]
		_rows.add_child(l)


func _sync_qty(def_id: String) -> void:
	for p in picks:
		if str(p.get("def", "")) == def_id and str(p.get("uid", "")) == "":
			p["qty"] = int((_spins[def_id] as SpinBox).value)
	update_preview()


## Quantità di una pila nell'anteprima (per i test e per «Lascia N»).
func set_pick_qty(def_id: String, qty: int) -> void:
	if _spins.has(def_id):
		(_spins[def_id] as SpinBox).value = qty
	else:
		for p in picks:
			if str(p.get("def", "")) == def_id:
				p["qty"] = qty
		update_preview()


func _on_about_to_popup() -> void:
	opened_ms = int(clock.call())
	if not picks.is_empty():
		get_cancel_button().call_deferred("grab_focus")       # «Torna indietro» è il predefinito


## «Vendi»: ignorato se arriva entro guard_ms dall'apertura (Invio ripetuto). Poi vende e chiude.
func _on_confirmed() -> void:
	if picks.is_empty():
		_do_sell()
		return
	if int(clock.call()) - opened_ms < guard_ms:
		return
	update_preview()                                   # il Deposito può essere cambiato: si vende ciò che è vendibile ORA
	_do_sell()
	hide()


## Le azioni in coda o in corso che usano `def_id` come ingrediente (nomi), per l'avviso «Ti servirà per…».
static func needed_for(def_id: String) -> PackedStringArray:
	var ids: Array = []
	var sk := Game.system("skills") as SkillSystem
	if sk != null and sk.current_action() != "":
		ids.append(sk.current_action())
	var q := Game.system("queue") as QueueSystem
	if q != null:
		for e in q.entries():
			ids.append(str(e.get("action", "")))
	var out := PackedStringArray()
	for aid in ids:
		for inp in DataRegistry.action(str(aid)).get("inputs", []):
			if str(inp.get("item", "")) == def_id:
				var nm := Loc.t(DataRegistry.action(str(aid)).get("name", {}))
				if not out.has(nm):
					out.append(nm)
	return out


## La finestra si apre sulla categoria che ha davvero qualcosa da vendere: con il Deposito pieno di materiali, «Attrezzatura»
## (la prima della lista) dava «Non corrisponde niente» e un pulsante spento senza dire dove guardare (QA 95).
func _preselect_category() -> void:
	var bank := Game.system("bank") as BankSystem
	var market := Game.system("market") as MarketSystem
	if bank == null or market == null:
		return
	var best := ""
	var best_n := 0
	for c in SellRules.CATEGORIES:
		var n := int(SellRules.collect(bank, market, SellRules.new_filter(str(c))).pieces)
		if str(c) == str(editor.get_filter().cat) and n > 0:
			return                     # la scelta iniziale va già bene
		if n > best_n:
			best = str(c)
			best_n = n
	if not best.is_empty():
		editor.set_filter(SellRules.new_filter(best))


func update_preview() -> void:
	var bank := Game.system("bank") as BankSystem
	var market := Game.system("market") as MarketSystem
	if not picks.is_empty():
		_update_pick_preview(bank, market)
		return
	plan = SellRules.collect(bank, market, editor.get_filter())
	var lines := PackedStringArray()
	if int(plan.pieces) <= 0:
		lines.append(tr("UI_UIA_SELL_NONE"))
	else:
		lines.append(Loc.tf("UI_UIA_SELL_SUMMARY", {"n": NumberFormat.fmt(int(plan.pieces)), "gold": NumberFormat.fmt(int(plan.gold))}))
		var shown := 0
		for g in plan.groups:
			if shown >= LIST_MAX:
				lines.append(Loc.tf("UI_UIA_SELL_MORE", {"n": (plan.groups as Array).size() - LIST_MAX}))
				break
			lines.append("  %s ×%s" % [Loc.t(DataRegistry.item(str(g.id)).get("name", str(g.id))), NumberFormat.fmt(int(g.qty))])
			shown += 1
	if int(plan.locked) > 0 or int(plan.in_use) > 0:
		lines.append(Loc.tf("UI_UIA_SELL_SAFE", {"locked": int(plan.locked), "use": int(plan.in_use)}))
	preview.text = "\n".join(lines)
	get_ok_button().disabled = int(plan.pieces) <= 0


func _update_pick_preview(bank: BankSystem, market: MarketSystem) -> void:
	plan = SellRules.collect_picks(bank, market, picks, GameState.has_unlock("feature:market"))
	var lines := PackedStringArray()
	if int(plan.pieces) <= 0:
		lines.append(tr("UI_UIA_SELL_NONE"))
	else:
		lines.append(Loc.tf("UI_BANKG_SELLP_SUMMARY", {"n": NumberFormat.fmt(int(plan.pieces)), "gold": NumberFormat.fmt(int(plan.gold))}))
	if int(plan.skipped) > 0:
		lines.append(Loc.tf("UI_BANKG_SELLP_SKIPPED", {"n": int(plan.skipped)}))
	preview.text = "\n".join(lines)
	var warns := PackedStringArray()
	if int((plan.warn as Dictionary).get("quality", 0)) > 0:
		warns.append(Loc.tf("UI_BANKG_SELLP_WARN_QUALITY", {"n": int(plan.warn.quality)}))
	if int((plan.warn as Dictionary).get("ranked", 0)) > 0:
		warns.append(Loc.tf("UI_BANKG_SELLP_WARN_RANKED", {"n": int(plan.warn.ranked)}))
	for st in plan.stacks:
		var need := needed_for(str(st.id))
		if not need.is_empty():
			warns.append(Loc.tf("UI_BANKG_SELLP_WARN_NEEDED", {"name": Loc.t(DataRegistry.item(str(st.id)).get("name", "")),
				"what": ", ".join(need)}))
	if _warn != null:
		_warn.text = "\n".join(warns)
		_warn.visible = not warns.is_empty()
	get_ok_button().disabled = int(plan.pieces) <= 0


func _do_sell() -> void:
	var market := Game.system("market") as MarketSystem
	var pieces := int(plan.pieces)
	var gold := SellRules.execute(market, plan)
	if pieces > 0:
		EventBus.notice.emit("success", Loc.tf("UI_UIA_SELL_DONE", {"n": pieces, "gold": NumberFormat.fmt(gold)}), {"category": "loot"})
	sold.emit(gold, pieces)
