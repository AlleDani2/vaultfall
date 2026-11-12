class_name AutoSellDialog
extends AcceptDialog
## Regole di vendita automatica (UI-A G14): elenco delle regole con interruttori, interruttore generale, e un editor per
## aggiungerne di nuove con l'anteprima di ciò che prenderebbero ORA. Sbloccata dal nodo di Costellazione «Vendita
## Automatica» (AssistSystem.auto_sell_unlocked): senza, la finestra spiega come ottenerla.

signal changed

var _assist: AssistSystem
var _list: VBoxContainer
var _editor: SellFilterEditor
var _preview: Label
var _add_btn: Button
var _master: CheckButton
var _dupes: CheckButton
var _locked_note: Label


func _init() -> void:
	title = TranslationServer.translate("UI_UIA_AUTO_TITLE")
	ok_button_text = TranslationServer.translate("UI_UIA_AUTO_CLOSE")
	min_size = Vector2i(520, 0)


func _ready() -> void:
	_assist = Game.system("assist") as AssistSystem
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var help := Label.new()
	help.text = "UI_UIA_AUTO_HELP"
	help.theme_type_variation = &"MutedLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 480
	box.add_child(help)
	_locked_note = Label.new()
	_locked_note.text = "UI_UIA_AUTO_LOCKED"
	_locked_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_locked_note.custom_minimum_size.x = 480
	box.add_child(_locked_note)
	_master = CheckButton.new()
	_master.text = "UI_UIA_AUTO_MASTER"
	_master.toggled.connect(func(on: bool) -> void:
		_assist.set_auto_on(on)
		changed.emit())
	box.add_child(_master)
	_dupes = CheckButton.new()                      # vendita automatica dei doppioni (equipaggiamento e attrezzi uguali oltre il primo)
	_dupes.name = "DupesCheck"
	_dupes.text = "UI_UIA_AUTO_DUPES"
	_dupes.tooltip_text = "UI_UIA_AUTO_DUPES_TIP"
	_dupes.toggled.connect(func(on: bool) -> void:
		_assist.set_auto_dupes(on)
		changed.emit())
	box.add_child(_dupes)
	var rules_title := Label.new()
	rules_title.text = "UI_UIA_AUTO_RULES"
	rules_title.theme_type_variation = &"SectionLabel"
	box.add_child(rules_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	var new_title := Label.new()
	new_title.text = "UI_UIA_AUTO_NEW"
	new_title.theme_type_variation = &"SectionLabel"
	box.add_child(new_title)
	_editor = SellFilterEditor.new()
	box.add_child(_editor)
	_preview = Label.new()
	_preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_preview.theme_type_variation = &"MutedLabel"
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size.x = 480
	box.add_child(_preview)
	_add_btn = Button.new()
	_add_btn.text = "UI_UIA_AUTO_ADD"
	_add_btn.pressed.connect(_on_add)
	box.add_child(_add_btn)
	_editor.filter_changed.connect(_refresh_preview)
	rebuild()


func rebuild() -> void:
	if _assist == null:
		return
	var unlocked := _assist.auto_sell_unlocked()
	_locked_note.visible = not unlocked
	_master.visible = unlocked
	_master.set_pressed_no_signal(_assist.is_auto_on())
	_dupes.visible = unlocked
	_dupes.set_pressed_no_signal(_assist.is_auto_dupes())
	_editor.visible = unlocked
	_preview.visible = unlocked
	_add_btn.visible = unlocked
	for c in _list.get_children():
		c.queue_free()
	var rules := _assist.rules()
	if rules.is_empty():
		var none := Label.new()
		none.text = "UI_UIA_AUTO_NONE"
		none.theme_type_variation = &"MutedLabel"
		_list.add_child(none)
	for i in rules.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var on := CheckBox.new()
		on.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		on.text = SellRules.describe(rules[i])
		on.button_pressed = bool(rules[i].get("on", true))
		on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		on.toggled.connect(func(v: bool) -> void:
			_assist.set_rule_on(i, v)
			changed.emit())
		h.add_child(on)
		var del := Button.new()
		del.text = "UI_UIA_AUTO_DELETE"
		del.pressed.connect(func() -> void:
			_assist.remove_rule(i)
			rebuild()
			changed.emit())
		h.add_child(del)
		_list.add_child(h)
	_refresh_preview()


func _refresh_preview() -> void:
	if _assist == null or not _assist.auto_sell_unlocked():
		return
	var plan := SellRules.collect(Game.system("bank") as BankSystem, Game.system("market") as MarketSystem, _editor.get_filter())
	_preview.text = Loc.tf("UI_UIA_AUTO_PREVIEW", {"n": NumberFormat.fmt(int(plan.pieces)), "gold": NumberFormat.fmt(int(plan.gold))})
	_add_btn.disabled = (_assist.rules() as Array).size() >= AssistSystem.MAX_RULES
	_add_btn.tooltip_text = "UI_UIA_AUTO_FULL" if _add_btn.disabled else ""


func _on_add() -> void:
	if _assist.add_rule(_editor.get_filter()):
		rebuild()
		changed.emit()
	else:
		EventBus.notice.emit("warning", tr("UI_UIA_AUTO_DUP"), {})
