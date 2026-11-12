class_name CrateResultCard
extends PanelContainer
## Carta del risultato di una apertura (scena di rivelazione della Sala dei Caveau): UN oggetto, grande, con la cornice
## del colore della rarità. In primo piano solo ciò che conta (rarità con simbolo, nome, condizione a parole, Annalista,
## «nuovo»); i valori tecnici (numero di usura, motivo) stanno dietro il pulsante «i». Nessuna probabilità o esito viene
## nascosto: il risultato era già stato estratto da CrateSystem.open() prima dell'animazione (docs/24).

const CARD_SIZE := Vector2(224, 300)

var _detail: Label
var _info_btn: Button


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## `r` = risultato di CrateSystem.open() (rarity, def_id, kind, instance, is_new).
func setup(r: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_detail = null
	_info_btn = null
	var rarity := str(r.get("rarity", "rare"))
	theme_type_variation = UiKit.rarity_variation(rarity, true)
	var col := CrateUi.rarity_color(rarity)
	var inst: Dictionary = r.get("instance", {}) if r.get("instance") is Dictionary else {}
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var rl := Label.new()
	rl.name = "RarityLine"
	rl.text = CrateUi.rarity_label(rarity)
	rl.add_theme_color_override("font_color", col)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	var ic := VaultKit.pix(CrateUi.def_icon(str(r.get("def_id", ""))), 4)       # 4× = 128 px a scala intera
	ic.name = "ResultIcon"
	v.add_child(ic)
	var nm := Label.new()
	nm.name = "ResultName"
	nm.text = CrateUi.tagged_name(inst) if not inst.is_empty() else CrateUi.def_name(str(r.get("def_id", "")))
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	nm.theme_type_variation = &"SectionLabel"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var sub := CrateUi.instance_summary(inst)
	if not sub.is_empty():
		var sl := Label.new()
		sl.name = "ResultSub"
		sl.text = sub
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sl.theme_type_variation = &"MutedLabel"
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl)
	if bool(r.get("is_new", false)):
		var pr := ScreenKit.pill(str(TranslationServer.translate("UI_CRATES_NEW")), FxPalette.GREEN)
		pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(pr)
	var tech := CrateUi.instance_detail(inst)
	if not tech.is_empty():
		_info_btn = Button.new()
		_info_btn.name = "DetailToggle"
		_info_btn.text = "ⓘ"
		_info_btn.tooltip_text = TranslationServer.translate("UI_GB_DETAIL_TIP")
		_info_btn.custom_minimum_size = Vector2(32, 0)
		_info_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(_info_btn)
		_detail = Label.new()
		_detail.name = "TechDetail"
		_detail.text = tech
		_detail.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_detail.theme_type_variation = &"MutedLabel"
		_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.visible = false
		v.add_child(_detail)
		_info_btn.pressed.connect(func() -> void: _detail.visible = not _detail.visible)


func detail_visible() -> bool:
	return _detail != null and _detail.visible
