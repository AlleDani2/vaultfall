class_name CrateActions
extends VBoxContainer
## Pulsanti dopo l'apertura di una cassa (docs/09 §6): Equipaggia · Blocca · Fondi · Vendi · Contratto.
## Presentazione soltanto: ogni pulsante chiama CrateSystem (equip, set_locked, fuse, sell) e mostra PRIMA il
## risultato dell'azione (Schegge o oro). Nulla spinge ad aprire altre casse; nessuna posta in gioco.

signal changed(action: String)

var _crates: CrateSystem
var _uid: String = ""
var column: bool = false      # scena di rivelazione: colonna di pulsanti larghi a destra della carta
var _row: Container
var _msg: Label
var equip_btn: Button
var lock_btn: Button
var fuse_btn: Button
var sell_btn: Button
var contract_btn: Button


func setup(crates: CrateSystem, uid: String) -> void:
	_crates = crates
	_uid = uid
	_build()


func current_uid() -> String:
	return _uid


func _build() -> void:
	for c in get_children():
		c.queue_free()
	equip_btn = null
	lock_btn = null
	fuse_btn = null
	sell_btn = null
	contract_btn = null
	if column:
		_row = VBoxContainer.new()
		_row.add_theme_constant_override("separation", 6)
	else:
		_row = HFlowContainer.new()
	_row.name = "ActionRow"
	add_child(_row)
	_msg = Label.new()
	_msg.theme_type_variation = &"MutedLabel"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.visible = false
	add_child(_msg)
	var inst := _crates.instance(_uid) if _crates != null else {}
	if inst.is_empty():
		return
	var kind := str(inst.kind)
	var blocked := _crates.consume_block(_uid)

	if kind == "skin" or kind == "relic":
		equip_btn = _btn("UI_CRATES_EQUIP", _on_equip)
		equip_btn.disabled = _crates.is_in_use(_uid)
		if equip_btn.disabled:
			equip_btn.tooltip_text = CrateUi.tx("UI_CRATES2_ALREADY_EQUIPPED")
	lock_btn = _btn("UI_CRATES2_UNLOCK" if _crates.is_locked(_uid) else "UI_CRATES2_LOCK", _on_lock)
	lock_btn.tooltip_text = CrateUi.tx("UI_CRATES2_LOCK_TIP")

	fuse_btn = Button.new()
	fuse_btn.text = Loc.tf("UI_CRATES2_FUSE", {"n": NumberFormat.fmt(_crates.fuse_value(_uid))})
	fuse_btn.pressed.connect(_on_fuse)
	_row.add_child(fuse_btn)
	_fit(fuse_btn)
	fuse_btn.tooltip_text = CrateUi.tx("UI_CRATES2_FUSE_TIP") if blocked.is_empty() else CrateUi.why(blocked)
	fuse_btn.disabled = not blocked.is_empty()

	var price := _crates.sell_price(_uid)
	sell_btn = Button.new()
	sell_btn.text = Loc.tf("UI_CRATES2_SELL", {"g": NumberFormat.fmt(price)})
	sell_btn.pressed.connect(_on_sell)
	_row.add_child(sell_btn)
	_fit(sell_btn)
	sell_btn.disabled = price <= 0
	sell_btn.tooltip_text = CrateUi.tx("UI_CRATES2_SELL_TIP") if price > 0 else CrateUi.why(blocked if not blocked.is_empty() else "unsellable")

	if kind == "skin":
		contract_btn = _btn("UI_CRATES2_CONTRACT", _on_contract)
		var golden := str(inst.rarity) == "mythic"
		var ok_rar: bool = golden or Array(_crates.rules().tradeup.rarities_in).has(str(inst.rarity))
		if not ok_rar:
			contract_btn.disabled = true
			contract_btn.tooltip_text = CrateUi.why("rarity")
		elif not _crates.contract_unlocked(golden):
			contract_btn.disabled = true
			var tok := CrateSystem.TOKEN_GOLDEN if golden else CrateSystem.TOKEN_TRADEUP
			var hint := UnlockSystem.hint_for(tok, DataRegistry)
			contract_btn.tooltip_text = hint if not hint.is_empty() else CrateUi.why("locked_feature")
		else:
			contract_btn.tooltip_text = CrateUi.tx("UI_CRATES2_CONTRACT_TIP_GOLDEN" if golden else "UI_CRATES2_CONTRACT_TIP")


func _btn(key: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = CrateUi.tx(key)
	b.pressed.connect(cb)
	_row.add_child(b)
	_fit(b)
	return b


## In colonna i pulsanti sono larghi e alti 40 px (gamepad e Steam Deck).
func _fit(b: Button) -> void:
	if column:
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _say(text: String) -> void:
	_msg.text = text
	_msg.visible = true


func _on_equip() -> void:
	var inst := _crates.instance(_uid)
	var ok := false
	if str(inst.get("kind", "")) == "relic":
		ok = _crates.equip_relic(_uid)
		if not ok:
			EventBus.notice.emit("warning", CrateUi.tx("UI_CRATES2_RELIC_FULL"), {})
	else:
		ok = _crates.equip(_uid)
	if ok:
		EventBus.notice.emit("info", CrateUi.tx("UI_CRATES_EQUIPPED"), {})
		changed.emit("equip")
		_build()


func _on_lock() -> void:
	_crates.set_locked(_uid, not _crates.is_locked(_uid))
	changed.emit("lock")
	_build()


## Fondere o vendere un pezzo che conta chiede conferma (Leggendaria o più, Annalista).
func needs_confirm() -> bool:
	var inst := _crates.instance(_uid)
	return CrateSystem.RARITIES.find(str(inst.get("rarity", "rare"))) >= CrateSystem.RARITIES.find("legendary") \
		or bool(inst.get("annalist", false))


func _on_fuse() -> void:
	if needs_confirm():
		CrateUi.confirm(self, Loc.tf("UI_CRATES2_CONFIRM_FUSE", {"name": CrateUi.def_name(str(_crates.instance(_uid).get("def_id", "")))}), do_fuse)
	else:
		do_fuse()


func _on_sell() -> void:
	if needs_confirm():
		CrateUi.confirm(self, Loc.tf("UI_CRATES2_CONFIRM_SELL", {"name": CrateUi.def_name(str(_crates.instance(_uid).get("def_id", "")))}), do_sell)
	else:
		do_sell()


func do_fuse() -> void:
	var n := _crates.fuse(_uid)
	if n > 0:
		_clear_row()
		_say(Loc.tf("UI_CRATES2_FUSED", {"n": NumberFormat.fmt(n)}))
		changed.emit("fuse")


func do_sell() -> void:
	var g := _crates.sell(_uid)
	if g > 0:
		_clear_row()
		_say(Loc.tf("UI_CRATES2_SOLD", {"g": NumberFormat.fmt(g)}))
		changed.emit("sell")


func _clear_row() -> void:
	for c in _row.get_children():
		c.queue_free()


func _on_contract() -> void:
	var inst := _crates.instance(_uid)
	var golden := str(inst.get("rarity", "")) == "mythic"
	EventBus.screen_requested.emit("vault_workshop", {"tab": "contracts", "add": _uid, "golden": golden})
	changed.emit("contract")
