class_name BankExpandDialog
extends AcceptDialog
## «Espandi Deposito» (feedback giocatore 23/10/2026, resoconto 114): compra spazi del Deposito senza passare dall'Emporio.
## Mostra lo stato attuale, tre pacchetti (+1/+5/+10 dai dati: constants.bank.buy_batches) con costo, spazi dopo l'acquisto e il
## MOTIVO se non si può comprare, e il riepilogo di tutte le fonti di spazi (base, cassetti, missioni, Costellazione, reliquie).
## Solo presentazione: prezzi e acquisti vengono da MarketSystem (`bank_expansion`, `buy_bank_slots`), le fonti da BankSystem.

signal changed

var _bank: BankSystem
var _market: MarketSystem
var _box: VBoxContainer


func _init() -> void:
	title = TranslationServer.translate("UI_BANKX_TITLE")
	ok_button_text = TranslationServer.translate("UI_BANKX_CLOSE")
	min_size = Vector2i(600, 0)


func _ready() -> void:
	_bank = Game.system("bank") as BankSystem
	_market = Game.system("market") as MarketSystem
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vh := float((Engine.get_main_loop() as SceneTree).root.get_visible_rect().size.y)
	scroll.custom_minimum_size = Vector2(580, clampf(vh - 200.0, 300.0, 600.0))      # il più alta possibile: a 720p il riepilogo si vede quasi tutto
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	rebuild()


## Ricostruisce il contenuto (dopo ogni acquisto).
func rebuild() -> void:
	if _box == null or _bank == null or _market == null:
		return
	for c in _box.get_children():
		c.queue_free()
	_build_status()
	_build_options()
	_build_sources()


func _dyn(text: String, variation: StringName = &"", font_px: int = 0) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != &"":
		l.theme_type_variation = variation
	if font_px > 0:
		l.add_theme_font_size_override("font_size", font_px)
	return l


## Numero allineato a destra, mai a capo (una colonna stretta non deve spezzare «100» in tre righe).
func _value_label(text: String, variation: StringName) -> Label:
	var l := _dyn(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size.x = 56
	return l


func _build_status() -> void:
	var cap := _bank.capacity()
	var used := _bank.used_slots()
	_box.add_child(_dyn(Loc.tf("UI_BANKX_NOW", {"used": NumberFormat.fmt(used), "cap": NumberFormat.fmt(cap),
		"free": NumberFormat.fmt(maxi(0, cap - used))}), &"SectionLabel"))
	var one := _market.bank_expansion(1)
	_box.add_child(_dyn(Loc.tf("UI_BANKX_GOLD", {"gold": NumberFormat.fmt(float(one.gold)), "price": NumberFormat.fmt(float(one.next_price))}), &"MutedLabel"))


func _build_options() -> void:
	var row := HBoxContainer.new()
	row.name = "Options"
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var batches: Array = DataRegistry.const_value("bank.buy_batches", [1])
	var reason_shown := ""
	for b in batches:
		var n := int(b)
		var q := _market.bank_expansion(n)
		var card := VaultKit.card(FxPalette.GOLD_D if bool(q.ok) else FxPalette.SMOKE)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		v.add_child(_dyn(Loc.tf("UI_BANKX_OPT_1" if n == 1 else "UI_BANKX_OPT_N", {"n": n}), &"SectionLabel"))
		v.add_child(_dyn(Loc.tf("UI_BANKX_OPT_COST", {"cost": NumberFormat.fmt(float(q.cost))})))
		v.add_child(_dyn(Loc.tf("UI_BANKX_OPT_AFTER", {"cap": NumberFormat.fmt(int(q.cap_after))}), &"MutedLabel"))
		var btn := Button.new()
		btn.name = "Buy%d" % n
		btn.text = "UI_BANKX_OPT_BUY"
		btn.theme_type_variation = &"AccentButton"
		btn.disabled = not bool(q.ok)
		btn.pressed.connect(_on_buy.bind(n))
		v.add_child(btn)
		if not bool(q.ok) and reason_shown.is_empty():
			reason_shown = _why(q)
	var why := _dyn(reason_shown, &"MutedLabel")
	why.name = "Why"
	why.add_theme_color_override("font_color", FxPalette.AMBER)
	why.visible = not reason_shown.is_empty()
	_box.add_child(why)
	_box.add_child(_dyn(tr("UI_BANKX_FREE_TIPS"), &"MutedLabel"))


## Perché non si può comprare (il primo pacchetto che non va: di solito è il più grande, quindi quello che manca davvero).
func _why(q: Dictionary) -> String:
	match str(q.reason):
		"gold":
			return Loc.tf("UI_BANKX_WHY_GOLD", {"missing": NumberFormat.fmt(float(q.missing))})
		"max":
			if int(q.left) > 0:
				return Loc.tf("UI_BANKX_WHY_LEFT", {"left": int(q.left)})
			return Loc.tf("UI_BANKX_WHY_MAX", {"max": int(q.max)})
	return tr("UI_BANKX_WHY_OTHER")


func _build_sources() -> void:
	var sep := HSeparator.new()
	_box.add_child(sep)
	_box.add_child(_dyn(tr("UI_BANKX_SRC_TITLE"), &"SectionLabel"))
	var bd := _bank.capacity_breakdown()
	var ps := _bank.permanent_sources()
	var grid := GridContainer.new()
	grid.name = "Sources"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(grid)
	_row(grid, tr("UI_BANKX_SRC_BASE"), str(bd.base), "")
	_row(grid, tr("UI_BANKX_SRC_BOUGHT"), "+" + str(bd.bought), "")
	var qhint := tr("UI_BANKX_SRC_QUESTS_ALL") if int(ps.quest_left) == 0 else Loc.tf("UI_BANKX_SRC_QUESTS_HINT",
		{"slots": int(ps.quest_earned), "total": int(ps.quest_total), "ch": int(ps.quest_next_chapter)})
	_row(grid, tr("UI_BANKX_SRC_QUESTS"), "+" + str(bd.quests), qhint)
	var node: Dictionary = ps.node
	if not node.is_empty():
		_row(grid, Loc.tf("UI_BANKX_SRC_CONST", {"name": Loc.t(node.name)}), "+" + str(bd.constellations),
			Loc.tf("UI_BANKX_SRC_CONST_HINT", {"lv": int(node.level), "max": int(node.max), "per": NumberFormat.fmt(float(node.per))}))
	var relic: Dictionary = ps.relic
	if not relic.is_empty():
		_row(grid, tr("UI_BANKX_SRC_RELIC"), "+" + str(bd.relics),
			Loc.tf("UI_BANKX_SRC_RELIC_HINT", {"name": Loc.t(relic.name), "slots": int(relic.slots)}))
	if int(bd.other) != 0:
		_row(grid, tr("UI_BANKX_SRC_OTHER"), "+" + str(bd.other), "")
	var tot := _dyn(tr("UI_BANKX_SRC_TOTAL"), &"SectionLabel")
	grid.add_child(tot)
	var tv := _value_label(NumberFormat.fmt(int(bd.total)), &"SectionLabel")
	tv.name = "Total"
	grid.add_child(tv)


func _row(grid: GridContainer, name_text: String, value_text: String, hint: String) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_dyn(name_text))
	if not hint.is_empty():
		left.add_child(_dyn(hint, &"MutedLabel"))
	grid.add_child(left)
	grid.add_child(_value_label(value_text, &"MonoLabel"))


func _on_buy(n: int) -> void:
	if _market.buy_bank_slots(n):
		changed.emit()
	rebuild()
