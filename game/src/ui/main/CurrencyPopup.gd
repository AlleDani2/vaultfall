class_name CurrencyPopup
extends AcceptDialog
## Finestra «Valute» (D4, docs/ui_redesign/06 §3.2): si apre dal clic sull'Oro della barra alta. Elenca tutte le valute
## possedute (oro per primo) con quantità e «dove si usa» (la descrizione dell'oggetto-valuta, dai dati). È una finestra
## di dialogo: WindowFit (hook su node_added) la tiene dentro l'area visibile a qualunque risoluzione.
## Solo presentazione: legge BankSystem.currency_ids()/currency(), nessuno stato.

const GOLD_ICON := "res://assets/ui/ui_currency_gold.png"
const MIN_W := 420
const ICON := 28

var _list: VBoxContainer


## Costruisce e mostra la finestra sotto `host` (di solito MainScreen). Ritorna la finestra.
static func open(host: Node) -> CurrencyPopup:
	var d := CurrencyPopup.new()
	host.add_child(d)
	d.build()
	d.popup_centered()
	return d


func _init() -> void:
	name = "CurrencyPopup"
	title = "UI_TOP_CUR_TITLE"
	ok_button_text = "UI_CLOSE"
	min_size = Vector2i(MIN_W, 240)
	exclusive = false


func build() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(MIN_W - 24, 200)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	var intro := Label.new()
	intro.text = "UI_TOP_CUR_INTRO"
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 120
	_list.add_child(intro)
	var bank := Game.system("bank") as BankSystem
	if bank == null:
		return
	for id in bank.currency_ids():
		_list.add_child(_row(bank, str(id)))


## Righe da mostrare: [{id, name, qty, use}] (pura: serve ai test).
static func rows(bank: BankSystem) -> Array:
	var out: Array = []
	if bank == null:
		return out
	for id in bank.currency_ids():
		var sid := str(id)
		if sid == BankSystem.GOLD:
			out.append({"id": sid, "name": TranslationServer.translate("UI_GOLD"), "qty": bank.gold(),
				"use": TranslationServer.translate("UI_TOP_CUR_GOLD_USE")})
		else:
			var def: Dictionary = DataRegistry.item(sid)
			out.append({"id": sid, "name": Loc.t(def.get("name", {})), "qty": bank.currency(sid), "use": Loc.t(def.get("desc", {}))})
	return out


func _row(bank: BankSystem, id: String) -> Control:
	var info: Dictionary = {}
	for r in rows(bank):
		if str(r.id) == id:
			info = r
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var pic := TopCurrency.as_pic(Control.new())
	pic.custom_minimum_size = Vector2(ICON, ICON)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pic.texture = load(GOLD_ICON) as Texture2D if id == BankSystem.GOLD else IconLib.icon("items", id)
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var nm := Label.new()
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.text = str(info.get("name", id))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(nm)
	var qty := Label.new()
	qty.name = "Qty"
	qty.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	qty.theme_type_variation = &"MonoLabel"
	qty.text = NumberFormat.fmt(float(info.get("qty", 0)))
	head.add_child(qty)
	var use := Label.new()
	use.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	use.theme_type_variation = &"MutedLabel"
	use.text = str(info.get("use", ""))
	use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	use.custom_minimum_size.x = 120
	v.add_child(use)
	return h
