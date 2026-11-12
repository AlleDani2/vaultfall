class_name CarroPanel
extends PanelContainer
## Pannello del Carro di Ritiro (resoconto 117): dice con chiarezza che il Deposito è pieno e dove sono finiti i premi, e offre
## i rimedi a un clic: «Vendi i doppioni», «Vendi le Finiture in eccesso», «Vendita automatica», «Espandi Deposito».
## Mostrato nel Deposito e nella Sala dei Caveau solo quando serve (Carro non vuoto o Deposito pieno). Nessun numero qui:
## tetto e filtro consigliato vengono dai dati (BankSystem.overflow_cap, BankSystem.recommended_sell_rule).

signal changed

var _bank: BankSystem
var _title: Label
var _body: Label
var _dupes_btn: Button
var _skins_btn: Button
var _auto_btn: Button
var _expand_btn: Button
var _sig: String = ""
var _acc: float = 0.0


func _ready() -> void:
	name = "CarroPanel"
	_bank = Game.system("bank") as BankSystem
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_title = Label.new()
	_title.name = "CarroTitle"
	_title.theme_type_variation = &"SectionLabel"
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_body = Label.new()
	_body.name = "CarroBody"
	_body.theme_type_variation = &"MutedLabel"
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_body)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	_dupes_btn = _button(row, "CarroDupesButton", _on_dupes)
	_skins_btn = _button(row, "CarroSkinsButton", _on_skins)
	_auto_btn = _button(row, "CarroAutoButton", _on_auto)
	_expand_btn = _button(row, "CarroExpandButton", _on_expand)
	_expand_btn.theme_type_variation = &"AccentButton"
	refresh(true)


func _button(parent: Control, node_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _process(dt: float) -> void:
	_acc += dt
	if _acc >= 0.5:
		_acc = 0.0
		refresh(false)


## true se il pannello ha qualcosa da dire (Carro non vuoto o Deposito pieno).
static func needed(bank: BankSystem) -> bool:
	return bank != null and (bank.overflow_count() > 0 or bank.is_full())


func _market_ok() -> bool:
	return GameState.has_unlock(AssistSystem.MARKET_TOKEN)


func _dupes_plan(fresh: bool = false) -> Dictionary:
	return PlanMemo.dupes(_bank, Game.system("market") as MarketSystem, _market_ok(), fresh)


func _skins_plan(fresh: bool = false) -> Dictionary:
	var f := _bank.recommended_sell_rule()
	if f.is_empty() or not _market_ok():
		return {"pieces": 0, "gold": 0}
	return PlanMemo.rule(_bank, Game.system("market") as MarketSystem, _market_ok(), f, fresh)


func refresh(force: bool) -> void:
	if _bank == null:
		return
	visible = needed(_bank)
	if not visible:                       # niente da dire: nessun piano di vendita da calcolare (scorrono tutto il Deposito)
		_sig = ""
		return
	var dp := _dupes_plan(force)
	var sp := _skins_plan(force)
	var assist := Game.system("assist") as AssistSystem
	var market := Game.system("market") as MarketSystem
	var q: Dictionary = market.bank_expansion(1) if market != null else {}
	var sig := "%d|%d|%d|%d|%d|%d|%d|%d|%s" % [_bank.revision, _bank.overflow_count(), _bank.overflow_gear_count(), int(dp.pieces), int(sp.pieces), 1 if _bank.is_full() else 0,
		1 if (assist != null and assist.recommended_active()) else 0, 1 if (assist != null and assist.auto_sell_unlocked()) else 0, str(q.get("next_price", 0))]
	if sig == _sig and not force:
		return
	_sig = sig
	var waiting := _bank.overflow_count()
	var gear_waiting := _bank.overflow_gear_count()          # F15: il Carro ragiona per classe (Spazio / Armeria)
	if waiting > 0:
		var only_gear := gear_waiting == waiting
		_title.text = Loc.tf("UI_BANKG_CARRO_TITLE_GEAR" if only_gear else "UI_CARRO_TITLE_N", {"n": NumberFormat.fmt(float(waiting))})
		var gear_line := Loc.tf("UI_BANKG_CARRO_GEAR", {"n": NumberFormat.fmt(float(gear_waiting)),
			"used": NumberFormat.fmt(float(_bank.gear_used())), "cap": NumberFormat.fmt(float(_bank.gear_cap()))})
		if only_gear:
			_body.text = gear_line
		else:
			_body.text = Loc.tf("UI_CARRO_BODY", {"skins": NumberFormat.fmt(float(_bank.overflow_skin_count())),
				"cap": NumberFormat.fmt(float(_bank.overflow_cap()))})
			if gear_waiting > 0:
				_body.text += " " + gear_line
	else:
		_title.text = tr("UI_CARRO_TITLE_EMPTY")
		_body.text = tr("UI_CARRO_BODY_EMPTY")
	_dupes_btn.text = Loc.tf("UI_BANK_DUPES_BTN", {"n": int(dp.pieces), "gold": NumberFormat.fmt(float(dp.gold))})
	_dupes_btn.disabled = int(dp.pieces) <= 0
	_dupes_btn.tooltip_text = tr("UI_BANK_DUPES_TIP") if int(dp.pieces) > 0 else (tr("UI_BANK_DUPES_NEEDS_MARKET") if int(dp.get("skipped", 0)) > 0 else tr("UI_BANK_DUPES_NONE"))
	_skins_btn.text = Loc.tf("UI_CARRO_SKINS_BTN", {"n": int(sp.pieces), "gold": NumberFormat.fmt(float(sp.gold))})
	_skins_btn.disabled = int(sp.pieces) <= 0
	_skins_btn.tooltip_text = tr("UI_CARRO_SKINS_TIP") if _market_ok() else tr("UI_BANK_DUPES_NEEDS_MARKET")
	if assist != null and assist.recommended_active():
		_auto_btn.text = tr("UI_CARRO_AUTO_ON")
		_auto_btn.disabled = true
		_auto_btn.tooltip_text = tr("UI_CARRO_AUTO_ON_TIP")
	else:
		_auto_btn.text = tr("UI_CARRO_AUTO_BTN")
		_auto_btn.disabled = false
		_auto_btn.tooltip_text = tr("UI_CARRO_AUTO_TIP") if (assist != null and assist.auto_sell_unlocked()) else tr("UI_CARRO_AUTO_LOCKED_TIP")
	var maxed: bool = not q.is_empty() and int(q.max) >= 0 and int(q.owned) >= int(q.max)
	_expand_btn.text = tr("UI_BANKX_BTN_MAX") if maxed else Loc.tf("UI_BANKX_BTN_PRICE", {"price": NumberFormat.fmt(float(q.get("next_price", 0)))})
	_expand_btn.tooltip_text = tr("UI_BANKX_BTN_TIP")


func _on_dupes() -> void:
	var plan := _dupes_plan(true)
	if int(plan.pieces) <= 0:
		return
	var gold := SellRules.execute_dupes(_bank, Game.system("market") as MarketSystem, plan)
	EventBus.notice.emit("success", Loc.tf("UI_BANK_DUPES_DONE", {"n": int(plan.pieces), "gold": NumberFormat.fmt(gold)}), {})
	_done()


func _on_skins() -> void:
	var plan := _skins_plan(true)
	if int(plan.pieces) <= 0:
		return
	var gold := SellRules.execute(Game.system("market") as MarketSystem, plan)
	EventBus.notice.emit("success", Loc.tf("UI_UIA_AUTOSOLD", {"n": int(plan.pieces), "gold": NumberFormat.fmt(gold)}), {"category": "loot"})
	_done()


## Un clic: se la vendita automatica è sbloccata attiva la regola consigliata; altrimenti apre la finestra che spiega come ottenerla.
func _on_auto() -> void:
	var assist := Game.system("assist") as AssistSystem
	if assist != null and assist.auto_sell_unlocked():
		if assist.enable_recommended():
			EventBus.notice.emit("success", tr("UI_CARRO_AUTO_DONE"), {})
		_done()
		return
	var dlg: AcceptDialog = (load("res://src/ui/screens/AutoSellDialog.gd") as GDScript).new()     # caricata al clic: il pannello si apre senza compilarla
	dlg.connect("changed", _done)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _on_expand() -> void:
	var dlg: AcceptDialog = (load("res://src/ui/screens/BankExpandDialog.gd") as GDScript).new()
	dlg.connect("changed", _done)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _done() -> void:
	refresh(true)
	changed.emit()
