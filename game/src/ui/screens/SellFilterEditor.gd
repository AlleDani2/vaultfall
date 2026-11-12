class_name SellFilterEditor
extends VBoxContainer
## Campi del filtro di vendita (categoria, tier massimo, qualità massima, rarità massima) con anteprima in tempo reale.
## Condiviso dalla vendita multipla e dalle regole automatiche (G14). Emette `filter_changed` a ogni modifica.

signal filter_changed

var _cat: OptionButton
var _tier: SpinBox
var _quality: OptionButton
var _rarity: OptionButton
var _quality_row: HBoxContainer
var _rarity_row: HBoxContainer
var _quality_ids: Array = []
var _silent := false


func _init() -> void:
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	_build()


func _build() -> void:
	if _cat != null:
		return
	_cat = OptionButton.new()
	_cat.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for c in SellRules.CATEGORIES:
		_cat.add_item(tr("UI_UIA_CAT_" + str(c).to_upper()))
	_cat.item_selected.connect(func(_i: int) -> void: _changed())
	add_child(_row("UI_UIA_F_CAT", _cat))
	_tier = SpinBox.new()
	_tier.min_value = 0
	_tier.max_value = 12
	_tier.step = 1
	_tier.value_changed.connect(func(_v: float) -> void: _changed())
	_tier.tooltip_text = "UI_UIA_F_TIER_TIP"
	add_child(_row("UI_UIA_F_TIER", _tier))
	_quality = OptionButton.new()
	_quality.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_quality.add_item(tr("UI_UIA_F_ANY"))
	_quality_ids = [""]
	for q in SellRules.quality_ids():
		_quality.add_item(tr("UI_BANK_Q_" + str(q).to_upper()))
		_quality_ids.append(q)
	_quality.item_selected.connect(func(_i: int) -> void: _changed())
	_quality_row = _row("UI_UIA_F_QUALITY", _quality)
	add_child(_quality_row)
	_rarity = OptionButton.new()
	_rarity.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rarity.add_item(tr("UI_UIA_F_ANY"))
	for r in SellRules.RARITIES:
		_rarity.add_item(tr("UI_UIA_RAR_" + str(r).to_upper()))
	_rarity.item_selected.connect(func(_i: int) -> void: _changed())
	_rarity_row = _row("UI_UIA_F_RARITY", _rarity)
	add_child(_rarity_row)
	_sync_rows()


func _row(key: String, ctrl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = key
	l.custom_minimum_size.x = 150
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	return h


func _sync_rows() -> void:
	var cat := str(SellRules.CATEGORIES[maxi(0, _cat.selected)])
	_quality_row.visible = SellRules.cat_has_quality(cat)
	_rarity_row.visible = SellRules.cat_has_rarity(cat)


func _changed() -> void:
	_sync_rows()
	if not _silent:
		filter_changed.emit()


func get_filter() -> Dictionary:
	if _cat == null:
		_build()
	var f := SellRules.new_filter(str(SellRules.CATEGORIES[maxi(0, _cat.selected)]))
	f.max_tier = int(_tier.value)
	if _quality_row.visible:
		f.max_quality = str(_quality_ids[maxi(0, _quality.selected)])
	if _rarity_row.visible and _rarity.selected > 0:
		f.max_rarity = str(SellRules.RARITIES[_rarity.selected - 1])
	return f


func set_filter(f: Dictionary) -> void:
	if _cat == null:
		_build()
	var c := SellRules.clean(f)
	_silent = true
	_cat.select(maxi(0, SellRules.CATEGORIES.find(c.cat)))
	_tier.value = int(c.max_tier)
	_quality.select(maxi(0, _quality_ids.find(c.max_quality)))
	_rarity.select(0 if str(c.max_rarity) == "" else 1 + SellRules.RARITIES.find(c.max_rarity))
	_silent = false
	_sync_rows()
	filter_changed.emit()
