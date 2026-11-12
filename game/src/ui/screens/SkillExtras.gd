class_name SkillExtras
extends VBoxContainer
## Pannello a scomparsa dentro SkillScreen: coda delle azioni, automazione, pozioni (Alchimia) e banchetti (docs/03
## R-AZ-4/5, docs/05 §6). Solo presentazione: la logica è in QueueSystem, PotionSystem e SkillSystem.
## SkillScreen lo crea con setup(skill_id) e lo aggiorna con refresh() (≤ 10 Hz).

const SLOW_EVERY := 5
const MISSING := Color(0.9, 0.4, 0.35)

var _skill_id: String = ""
var _q: QueueSystem
var _pt: PotionSystem
var _sk: SkillSystem
var _toggle: Button
var _body: VBoxContainer
var _open: bool = false
var _counter: int = 0
var _sig: String = ""

var _auto_l: Label
var _slots_l: Label
var _locked_l: Label
var _list: VBoxContainer
var _entry_labels: Array = []
var _add_row: HBoxContainer
var _act_opt: OptionButton
var _mode_opt: OptionButton
var _val_spin: SpinBox
var _add_btn: Button
var _run_btn: Button
var _potion_l: Label
var _potion_opt: OptionButton
var _drink_btn: Button
var _feast_l: Label
var _feast_opt: OptionButton
var _eat_btn: Button
var _actions: Array = []
var _compact: bool = false              # F7: il pulsante «Coda ▾» sta nella testata della schermata, qui resta il corpo


## `compact` (F7): il pulsante non è figlio del pannello; lo prende il chiamante con toggle_button() e lo mette nella testata.
func setup(skill_id: String, compact: bool = false) -> void:
	_compact = compact
	_skill_id = skill_id
	_q = Game.system("queue") as QueueSystem
	_pt = Game.system("potions") as PotionSystem
	_sk = Game.system("skills") as SkillSystem
	if _q == null or _pt == null or _sk == null:
		visible = false
		return
	for a in DataRegistry.actions_for_skill(skill_id):
		if not (str(a.get("kind", "")) in ["crop", "tree"]):
			_actions.append(a)
	_actions.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("level_req", 1)) < int(y.get("level_req", 1)))
	if _actions.is_empty():
		visible = false
		return
	_build()


func _label(text: String, variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	return l


## Il pulsante «Coda ▾» (null se la mansione non ha il pannello). In modalità compatta lo mette il chiamante.
func toggle_button() -> Button:
	return _toggle


func _set_toggle_text(on: bool) -> void:
	if _compact:
		_toggle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_toggle.text = tr("UI_SKILLS_QUEUE_BTN") + (" ▴" if on else " ▾")
	else:
		Disclosure.apply(_toggle, "UI_EXTRAS_TITLE", on)


## Apre il pannello a scomparsa (usato da ReqLink / scorciatoia Q: «focus: queue»).
func open_panel() -> void:
	if _toggle != null:
		_toggle.button_pressed = true


func _build() -> void:
	_toggle = Button.new()
	_toggle.toggle_mode = true
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_toggle_text(false)
	if _compact:
		_toggle.tooltip_text = tr("UI_EXTRAS_TITLE")
	_toggle.toggled.connect(_on_toggled)
	TutorialTargets.mark(_toggle, "extras_toggle")
	if not _compact:
		add_child(_toggle)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)
	# automazione
	_auto_l = _label("", &"MutedLabel")
	_body.add_child(_auto_l)
	# coda
	_body.add_child(_label(tr("UI_EXTRAS_QUEUE_TITLE"), &"SectionLabel"))
	_slots_l = _label("", &"MutedLabel")
	_body.add_child(_slots_l)
	_locked_l = _label(tr("UI_EXTRAS_QUEUE_LOCKED"), &"MutedLabel")
	_body.add_child(_locked_l)
	_list = VBoxContainer.new()
	_body.add_child(_list)
	_add_row = HBoxContainer.new()
	_add_row.add_theme_constant_override("separation", 6)
	_body.add_child(_add_row)
	TutorialTargets.mark(_add_row, "extras_queue")
	_act_opt = OptionButton.new()
	_act_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_act_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in _actions:
		_act_opt.add_item(Loc.t(a.name))
		_act_opt.set_item_metadata(_act_opt.item_count - 1, str(a.id))
	_add_row.add_child(_act_opt)
	_mode_opt = OptionButton.new()
	_mode_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for m in DataRegistry.constants.queue.modes:
		_mode_opt.add_item(tr("UI_EXTRAS_MODE_" + str(m).to_upper()))
		_mode_opt.set_item_metadata(_mode_opt.item_count - 1, str(m))
	_mode_opt.item_selected.connect(_on_mode_selected)
	_add_row.add_child(_mode_opt)
	_val_spin = SpinBox.new()
	_val_spin.min_value = 1
	_val_spin.max_value = 100000
	_val_spin.value = 10
	_val_spin.custom_minimum_size = Vector2(96, 0)
	_add_row.add_child(_val_spin)
	_add_btn = Button.new()
	_add_btn.text = "UI_EXTRAS_ADD"
	_add_btn.pressed.connect(_on_add)
	_add_row.add_child(_add_btn)
	_run_btn = Button.new()
	_run_btn.pressed.connect(_on_run)
	_body.add_child(_run_btn)
	# pozioni
	_body.add_child(_label(tr("UI_EXTRAS_POTION_TITLE"), &"SectionLabel"))
	_potion_l = _label("", &"MutedLabel")
	_body.add_child(_potion_l)
	var pr := HBoxContainer.new()
	_body.add_child(pr)
	TutorialTargets.mark(pr, "extras_potion")
	_potion_opt = OptionButton.new()
	_potion_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_potion_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_potion_opt)
	_drink_btn = Button.new()
	_drink_btn.text = "UI_EXTRAS_DRINK"
	_drink_btn.pressed.connect(_on_drink)
	pr.add_child(_drink_btn)
	# banchetti
	_feast_l = _label("", &"MutedLabel")
	_body.add_child(_feast_l)
	var fr := HBoxContainer.new()
	_body.add_child(fr)
	TutorialTargets.mark(fr, "extras_feast")
	_feast_opt = OptionButton.new()
	_feast_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_feast_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr.add_child(_feast_opt)
	_eat_btn = Button.new()
	_eat_btn.text = "UI_EXTRAS_EAT"
	_eat_btn.pressed.connect(_on_eat)
	fr.add_child(_eat_btn)
	_sync_spin()


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	if _q == null or not visible:
		return
	_counter += 1
	if not _open:
		return
	_refresh_auto()
	_refresh_queue()
	if _counter % SLOW_EVERY == 1:
		_refresh_consumables()
	_refresh_labels()


func _refresh_auto() -> void:
	var stars := int(GameState.data.get("skills", {}).get(_skill_id, {}).get("stars", 0))
	var need := int(DataRegistry.constants.automation.stars)
	var has_inputs := false         # l'automazione riguarda solo le azioni che consumano ingredienti
	var mastered: PackedStringArray = []
	for a in DataRegistry.actions_for_skill(_skill_id):
		if a.has("inputs"):
			has_inputs = true
			if _sk != null and _sk.is_mastered(str(a.id)):
				mastered.append(Loc.t(a.get("name", {})))
	if stars >= need:
		_auto_l.text = tr("UI_EXTRAS_AUTO_ON")
	elif not mastered.is_empty():
		_auto_l.text = Loc.tf("UI_EXTRAS_AUTO_MASTERED", {"list": ", ".join(mastered)})
	elif not has_inputs:
		_auto_l.text = tr("UI_EXTRAS_AUTO_NOINPUT")
	else:
		_auto_l.text = tr("UI_EXTRAS_AUTO_LOCKED")
	_auto_l.remove_theme_color_override("font_color")


func _refresh_queue() -> void:
	var slots := _q.slots()
	_locked_l.visible = slots <= 0
	_slots_l.visible = slots > 0
	_add_row.visible = slots > 0
	_run_btn.visible = slots > 0
	_slots_l.text = Loc.tf("UI_EXTRAS_QUEUE_SLOTS", {"n": _q.size(), "max": slots})
	_add_btn.disabled = _q.size() >= slots
	_run_btn.text = tr("UI_EXTRAS_STOP_QUEUE") if _q.is_running() else tr("UI_EXTRAS_START_QUEUE")
	_run_btn.disabled = _q.size() == 0
	# struttura: ricostruita solo se cambiano le voci
	var parts := PackedStringArray()
	for e in _q.entries():
		parts.append("%s:%s:%d" % [e.action, e.mode, int(e.value)])
	var sig := ",".join(parts)
	if sig != _sig:
		_sig = sig
		_rebuild_entries()


func _rebuild_entries() -> void:
	for c in _list.get_children():
		c.queue_free()
	_entry_labels.clear()
	var entries := _q.entries()
	for i in entries.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list.add_child(row)
		var l := _label("", &"")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_entry_labels.append(l)
		if i > 0:
			var up := Button.new()
			up.text = "UI_EXTRAS_UP"
			up.pressed.connect(_on_up.bind(i))
			row.add_child(up)
		var rm := Button.new()
		rm.text = "UI_EXTRAS_REMOVE"
		rm.pressed.connect(_on_remove.bind(i))
		row.add_child(rm)


func _refresh_labels() -> void:
	var entries := _q.entries()
	for i in mini(entries.size(), _entry_labels.size()):
		var e: Dictionary = entries[i]
		var nm := Loc.t(DataRegistry.action(str(e.action)).get("name", {}))
		var txt := ""
		match str(e.mode):
			"qty":
				txt = Loc.tf("UI_EXTRAS_ENTRY_QTY", {"name": nm, "done": int(e.done), "value": int(e.value)})
			"level":
				txt = Loc.tf("UI_EXTRAS_ENTRY_LEVEL", {"name": nm, "value": int(e.value)})
			"time":
				txt = Loc.tf("UI_EXTRAS_ENTRY_TIME", {"name": nm, "done": NumberFormat.fmt_time(float(e.elapsed_s)), "total": NumberFormat.fmt_time(float(e.value))})
			_:
				txt = Loc.tf("UI_EXTRAS_ENTRY_EXHAUST", {"name": nm})
		if i == 0 and _q.is_running():
			txt = "> " + txt
		(_entry_labels[i] as Label).text = txt
	# pozione e banchetto attivi
	var slot := _pt.slot_for_skill(_skill_id)
	if slot.is_empty():
		_potion_l.text = tr("UI_EXTRAS_POTION_NONE_SKILL")
	elif _pt.charges(slot) > 0:
		var nm2 := Loc.t(DataRegistry.item(_pt.item_in(slot)).get("name", {}))
		_potion_l.text = Loc.tf("UI_EXTRAS_POTION_ACTIVE", {"name": nm2, "n": _pt.charges(slot)})
	else:
		_potion_l.text = tr("UI_EXTRAS_POTION_NONE")
	var feast := _pt.feast_item()
	if feast.is_empty():
		_feast_l.text = tr("UI_EXTRAS_FEAST_NONE")
	else:
		_feast_l.text = Loc.tf("UI_EXTRAS_FEAST_ACTIVE", {"name": Loc.t(DataRegistry.item(feast).get("name", {})), "time": NumberFormat.fmt_time(_pt.feast_remaining())})


func _refresh_consumables() -> void:
	if _potion_opt.get_popup().visible or _feast_opt.get_popup().visible:
		return                                     # un menù aperto non si ricostruisce: si aggiorna dopo che si è chiuso
	var bank: Object = Game.system("bank")
	var slot := _pt.slot_for_skill(_skill_id)
	var keep_p := _selected(_potion_opt)
	_potion_opt.clear()
	if bank != null and not slot.is_empty():
		for it in DataRegistry.items_by_category("potion"):
			var n := int(bank.count(str(it.id)))
			if n > 0 and slot in _pt.slots_for(str(it.id)):
				_potion_opt.add_item("%s (x%d)" % [Loc.t(it.name), n])
				_potion_opt.set_item_metadata(_potion_opt.item_count - 1, str(it.id))
				if str(it.id) == keep_p:
					_potion_opt.select(_potion_opt.item_count - 1)
	_potion_opt.visible = _potion_opt.item_count > 0
	_drink_btn.visible = _potion_opt.item_count > 0
	var keep_f := _selected(_feast_opt)
	_feast_opt.clear()
	if bank != null:
		for it in DataRegistry.items_by_category("food"):
			if not (it.get("feast") is Dictionary):
				continue
			var n2 := int(bank.count(str(it.id)))
			if n2 > 0:
				_feast_opt.add_item("%s (x%d)" % [Loc.t(it.name), n2])
				_feast_opt.set_item_metadata(_feast_opt.item_count - 1, str(it.id))
				if str(it.id) == keep_f:
					_feast_opt.select(_feast_opt.item_count - 1)
	_feast_opt.visible = _feast_opt.item_count > 0
	_eat_btn.visible = _feast_opt.item_count > 0


func _selected(opt: OptionButton) -> String:
	var i := opt.selected
	return str(opt.get_item_metadata(i)) if i >= 0 and i < opt.item_count else ""


func _sync_spin() -> void:
	var mode := _selected(_mode_opt)
	_val_spin.visible = mode != "exhaust"
	if mode == "level":
		_val_spin.min_value = 2
		_val_spin.max_value = DataRegistry.constants.level_cap
		_val_spin.value = clampf(float(_sk.level(_skill_id) + 1), 2.0, float(DataRegistry.constants.level_cap))
	elif mode == "time":
		_val_spin.min_value = 1
		_val_spin.max_value = 1440
		_val_spin.suffix = tr("UI_EXTRAS_MIN_SUFFIX")
	else:
		_val_spin.min_value = 1
		_val_spin.max_value = 100000
		_val_spin.suffix = ""


# ------------------------------------------------------------------ azioni

func _on_toggled(on: bool) -> void:
	_open = on
	_body.visible = on
	_set_toggle_text(on)


func _on_mode_selected(_i: int) -> void:
	_sync_spin()


func _on_up(i: int) -> void:
	_q.move(i, -1)


func _on_remove(i: int) -> void:
	_q.remove_at(i)


func _on_add() -> void:
	var aid := _selected(_act_opt)
	var mode := _selected(_mode_opt)
	var v := int(_val_spin.value)
	if mode == "time":
		v *= 60                        # la voce è in minuti, lo stato in secondi
	var why := _q.can_add(aid, mode, v)
	if why != "":
		EventBus.notice.emit("warning", tr(why), {})
		return
	_q.add(aid, mode, v)


func _on_run() -> void:
	if _q.is_running():
		_q.stop()
	else:
		_q.start()


func _on_drink() -> void:
	var item := _selected(_potion_opt)
	if item != "":
		_pt.drink(item, _pt.slot_for_skill(_skill_id) if _pt.slots_for(item).size() > 1 else "")
		_counter = 0


func _on_eat() -> void:
	var item := _selected(_feast_opt)
	if item != "":
		_pt.eat_feast(item)
		_counter = 0
