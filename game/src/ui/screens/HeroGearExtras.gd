class_name HeroGearExtras
extends VBoxContainer
## Parte della schermata Eroe aggiunta da GAP-MECCANICHE: «Rango» degli oggetti (G03) e «Set» di equipaggiamento (G15).
## HeroScreen la aggiunge in una riga e chiama refresh(); qui dentro si ricostruisce solo quando cambia qualcosa.

var _rank_head: Control
var _rank_help: Label
var _rank_opt: OptionButton
var _sets_head: Control
var _rank_uids: Array = []
var _rank_box: VBoxContainer
var _sets_box: VBoxContainer
var _sig := ""
var _sel_uid := ""


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# --- Rango
	_rank_head = CombatUi.label("UI_GAPM_RANK_SECTION", "SectionLabel")
	add_child(_rank_head)
	_rank_help = CombatUi.text_label("MutedLabel", true)
	_rank_help.text = tr("UI_GAPM_RANK_HELP")
	add_child(_rank_help)
	_rank_opt = OptionButton.new()
	_rank_opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rank_opt.fit_to_longest_item = false
	_rank_opt.clip_text = true
	_rank_opt.item_selected.connect(func(i: int) -> void:
		_sel_uid = str(_rank_uids[i]) if i >= 0 and i < _rank_uids.size() else ""
		_sig = "")
	add_child(_rank_opt)
	_rank_box = VBoxContainer.new()
	add_child(_rank_box)
	# --- Set
	_sets_head = CombatUi.label("UI_GAPM_SET_SECTION", "SectionLabel")
	add_child(_sets_head)
	_sets_box = VBoxContainer.new()
	_sets_box.add_theme_constant_override("separation", 4)
	add_child(_sets_box)
	refresh()


func _signature() -> String:
	var bank := Game.system("bank") as BankSystem
	var lo := Game.system("loadouts") as LoadoutSystem
	return "%d|%s|%s|%d|%s|%d" % [bank.revision if bank != null else 0, JSON.stringify(GameState.data.get("equipment", {})),
		_sel_uid, lo.slot_count() if lo != null else 0, JSON.stringify(lo.state) if lo != null else "",
		(Game.system("prestige") as PrestigeSystem).era_max() if Game.system("prestige") != null else 0]


func refresh() -> void:
	if not is_inside_tree() or not GameState.active:
		return
	var sig := _signature()
	if sig == _sig:
		return
	_sig = sig
	_refresh_rank()
	_refresh_sets()


func _name_of(uid: String) -> String:
	var bank := Game.system("bank") as BankSystem
	var inst: Dictionary = bank.get_instance(uid) if bank != null else {}
	var nm := Loc.t(DataRegistry.item(str(inst.get("def", ""))).get("name", {}))
	if int(inst.get("rank", 0)) > 0:
		nm += " +%d" % int(inst.rank)
	return nm


func _refresh_rank() -> void:
	if _rank_opt.get_popup().visible:
		_sig = ""                                  # menù aperto: si riprova al prossimo aggiornamento
		return
	var ps := Game.system("prestige") as PrestigeSystem
	# il Rango si mostra solo dall'Era II (nessuna meccanica prima del suo sblocco)
	var on := ps != null and ps.ranks_unlocked()
	_rank_head.visible = on
	_rank_help.visible = on
	_rank_box.visible = on
	_rank_opt.clear()
	if not on:
		_rank_opt.visible = false
		return
	_rank_uids = ps.rankable_uids() if ps != null else []
	var cb := Game.system("combat") as CombatSystem
	for uid in _rank_uids:
		var worn := cb != null and cb.is_equipped(str(uid))
		_rank_opt.add_item(("● " if worn else "") + _name_of(str(uid)))
	if not _rank_uids.has(_sel_uid):
		_sel_uid = str(_rank_uids[0]) if not _rank_uids.is_empty() else ""
	_rank_opt.select(_rank_uids.find(_sel_uid))
	_rank_opt.visible = not _rank_uids.is_empty()
	CombatUi.clear_children(_rank_box)
	if _rank_uids.is_empty():
		var l := CombatUi.text_label("MutedLabel", true)
		l.text = tr("UI_GAPM_RANK_NONE")
		_rank_box.add_child(l)
		return
	_rank_box.add_child(GapMechUi.rank_box(_sel_uid, func() -> void: _sig = ""))


func _refresh_sets() -> void:
	CombatUi.clear_children(_sets_box)
	var lo := Game.system("loadouts") as LoadoutSystem
	if lo == null:
		return
	var n := lo.slot_count()
	# senza Rastrelliera comprata la scheda non compare (l'Emporio la descrive già)
	_sets_head.visible = n > 0
	if n <= 0:
		return
	for i in n:
		_sets_box.add_child(_set_row(lo, i))


func _set_row(lo: LoadoutSystem, i: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var s := lo.get_set(i)
	var name_l := CombatUi.text_label("", false)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	if s.is_empty():
		name_l.text = Loc.tf("UI_GAPM_SET_EMPTY", {"n": i + 1})
		name_l.theme_type_variation = &"MutedLabel"
	else:
		var nm := str(s.get("name", ""))
		name_l.text = nm if not nm.is_empty() else Loc.tf("UI_GAPM_SET_DEFAULT_NAME", {"n": i + 1})
		var miss := lo.missing_slots(i).size()
		name_l.text += "  " + Loc.tf("UI_GAPM_SET_PIECES", {"n": (s.get("gear", {}) as Dictionary).size()})
		if miss > 0:
			name_l.text += "  " + Loc.tf("UI_GAPM_SET_MISSING", {"n": miss})
	row.add_child(name_l)
	var save := Button.new()
	save.text = "UI_GAPM_SET_SAVE"
	save.tooltip_text = "UI_GAPM_SET_SAVE_HELP"
	save.pressed.connect(func() -> void:
		var go := func() -> void:
			lo.save_set(i)
			EventBus.notice.emit("success", Loc.tf("UI_GAPM_SET_SAVED", {"n": i + 1}), {})
			_sig = ""
		if s.is_empty():
			go.call()
		else:
			CrateUi.confirm(self, Loc.tf("UI_GAPM_SET_OVERWRITE", {"n": i + 1}), go))
	row.add_child(save)
	var wear := Button.new()
	wear.text = "UI_GAPM_SET_APPLY"
	var why := lo.can_apply(i)
	wear.disabled = not why.is_empty()
	wear.tooltip_text = why if not why.is_empty() else "UI_GAPM_SET_APPLY_HELP"
	wear.pressed.connect(func() -> void:
		var r := lo.apply_set(i)
		if bool(r.ok):
			var k := "UI_GAPM_SET_APPLIED" if (r.missing as Array).is_empty() and (r.failed as Array).is_empty() else "UI_GAPM_SET_APPLIED_PART"
			EventBus.notice.emit("info", Loc.tf(k, {"n": int(r.worn), "skip": (r.missing as Array).size() + (r.failed as Array).size()}), {})
		_sig = "")
	row.add_child(wear)
	var clear := Button.new()
	clear.text = "UI_GAPM_SET_CLEAR"
	clear.disabled = s.is_empty()
	clear.pressed.connect(func() -> void:
		CrateUi.confirm(self, Loc.tf("UI_GAPM_SET_CLEAR_CONFIRM", {"n": i + 1}), func() -> void:
			lo.clear_set(i)
			_sig = ""))
	row.add_child(clear)
	return row
