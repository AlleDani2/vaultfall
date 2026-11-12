class_name ParallelsPanel
extends VBoxContainer
## Riquadro «Paralleli» della colonna destra (G22, docs/16 §2): tutto ciò che lavora in parallelo, a colpo d'occhio, con
## barra e conto alla rovescia; un clic apre la schermata giusta. Righe: mansione attiva (con «tempo al livello»), Orto,
## Spedizioni, Apprendisti, Coda azioni. Una riga compare solo se il sistema è sbloccato e ha qualcosa da dire.
## Solo presentazione: `rows()` legge i sistemi e ritorna dati puri (testabili); `refresh()` aggiorna i nodi (≤ 10 Hz).

const ROW_H := 46

var _rows: Dictionary = {}        # id riga -> {btn, title, value, bar}
var _title: Label


func _init() -> void:
	name = "Parallels"
	add_theme_constant_override("separation", 4)
	_title = Label.new()
	_title.theme_type_variation = &"SectionLabel"
	_title.text = "UI_UIB_PARALLELS"
	add_child(_title)


## Dati delle righe da mostrare: [{id, title, value, frac (-1 = nessuna barra), screen, params, tip}].
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not GameState.active:
		return out
	var sk := Game.system("skills") as SkillSystem
	var info := LevelEta.info()
	if not info.is_empty():
		var v := LevelEta.short_text(info)
		out.append({"id": "active", "title": str(info.name), "value": v if not v.is_empty() else Loc.tf("UI_SKILLS_LEVEL", {"n": int(info.level)}),
			"frac": float(info.frac), "screen": "skill:" + str(info.skill), "params": {"skill": str(info.skill)}, "tip": "UI_UIB_PAR_TIP_ACTIVE"})
	elif ActivityText.is_active() and sk != null:
		var zone := ActivityText.combat_zone()          # titolo = zona, valore = «Combattimento»: niente testo lungo da tagliare
		out.append({"id": "active", "title": zone if not zone.is_empty() else str(TranslationServer.translate("UI_MENU_COMBAT")),
			"value": str(TranslationServer.translate("UI_MENU_COMBAT")) if not zone.is_empty() else ActivityText.text(), "frac": -1.0,
			"screen": "combat", "params": {}, "tip": "UI_UIB_PAR_TIP_ACTIVE"})
	var farm := _farm_row(sk)
	if not farm.is_empty():
		out.append(farm)
	var exp_row := _expedition_row()
	if not exp_row.is_empty():
		out.append(exp_row)
	var app := _apprentice_row()
	if not app.is_empty():
		out.append(app)
	var q := _queue_row()
	if not q.is_empty():
		out.append(q)
	return out


## Solo le righe in parallelo (Orto, Spedizioni, Apprendisti): le legge MenuActivity per evidenziare le voci del menù.
static func side_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not GameState.active:
		return out
	for r in [_farm_row(Game.system("skills") as SkillSystem), _expedition_row(), _apprentice_row()]:
		if not (r as Dictionary).is_empty():
			out.append(r)
	return out


static func _farm_row(sk: SkillSystem) -> Dictionary:
	var f := Game.system("farming") as FarmingSystem
	if f == null or sk == null or not sk.is_unlocked("farming"):
		return {}
	var n_ready := 0
	var growing := 0
	var soonest := -1.0
	var soonest_frac := 0.0
	for kd in DataRegistry.table("farming_plots"):
		var kid := str(kd.id)
		for i in f.plot_count(kid):
			if f.is_ready(kid, i):
				n_ready += 1
			elif f.is_growing(kid, i):
				growing += 1
				var rem := float(f.plot(kid, i).remaining_s)
				if soonest < 0.0 or rem < soonest:
					soonest = rem
					soonest_frac = f.growth_fraction(kid, i)
	var planted := n_ready + growing
	var value := TranslationServer.translate("UI_UIB_PAR_FARM_EMPTY")
	var frac := -1.0
	if planted > 0:
		value = Loc.tf("UI_UIB_PAR_FARM", {"ready": n_ready, "n": planted})
		if growing > 0:
			value += " · " + NumberFormat.fmt_time(soonest)
			frac = soonest_frac
		else:
			frac = 1.0
	return {"id": "farm", "title": TranslationServer.translate("UI_UIB_PAR_FARM_TITLE"), "value": value, "frac": frac,
		"screen": "skill:farming", "params": {"skill": "farming"}, "tip": "UI_UIB_PAR_TIP_FARM"}


static func _expedition_row() -> Dictionary:
	var ex := Game.system("expeditions") as ExpeditionSystem
	if ex == null or (ex.tavern_level() <= 0 and ex.active().is_empty()):
		return {}
	var act := ex.active()
	if act.is_empty():
		return {"id": "expeditions", "title": TranslationServer.translate("UI_UIB_PAR_EXP_TITLE"), "value": TranslationServer.translate("UI_UIB_PAR_EXP_NONE"),
			"frac": -1.0, "screen": "guild", "params": {}, "tip": "UI_UIB_PAR_TIP_EXP"}
	var soonest := 1e18
	var frac := 0.0
	for a in act:
		var left := ex.time_left(str(a.id))
		if left < soonest:
			soonest = left
			frac = ex.progress(str(a.id))
	return {"id": "expeditions", "title": TranslationServer.translate("UI_UIB_PAR_EXP_TITLE"),
		"value": Loc.tf("UI_UIB_PAR_EXP", {"n": act.size(), "time": NumberFormat.fmt_time(soonest)}), "frac": frac,
		"screen": "guild", "params": {}, "tip": "UI_UIB_PAR_TIP_EXP"}


static func _apprentice_row() -> Dictionary:
	var ap := Game.system("apprentices") as ApprenticeSystem
	if ap == null or ap.slots_total() <= 0:
		return {}
	var n := ap.active_count()
	var value := Loc.tf("UI_UIB_PAR_APP", {"n": n, "max": ap.slots_total()})
	var frac := -1.0
	var best_left := -1.0
	for i in ap.slots_total():
		if ap.slot_action(i).is_empty() or ap.slot_stalled(i):
			continue
		var left := (1.0 - ap.slot_progress(i)) * ap.cycle_s(ap.slot_action(i))
		if best_left < 0.0 or left < best_left:
			best_left = left
			frac = ap.slot_progress(i)
	if best_left >= 0.0:
		value += " · " + NumberFormat.fmt_time(best_left)
	return {"id": "apprentices", "title": TranslationServer.translate("UI_UIB_PAR_APP_TITLE"), "value": value, "frac": frac,
		"screen": "guild", "params": {}, "tip": "UI_UIB_PAR_TIP_APP"}


static func _queue_row() -> Dictionary:
	var q := Game.system("queue") as QueueSystem
	if q == null or q.size() <= 0:
		return {}
	var t := ShortcutMap.queue_target()
	var value := Loc.tf("UI_UIB_PAR_QUEUE_RUN" if q.is_running() else "UI_UIB_PAR_QUEUE_PAUSED", {"n": q.size()})
	return {"id": "queue", "title": TranslationServer.translate("UI_UIB_PAR_QUEUE_TITLE"), "value": value, "frac": -1.0,
		"screen": str(t.get("id", "")), "params": t.get("params", {}), "tip": "UI_UIB_PAR_TIP_QUEUE"}


## Aggiorna i nodi dai dati: crea/toglie le righe solo se cambia l'insieme, altrimenti cambia testi e barre.
func refresh() -> void:
	var data := rows()
	var ids: PackedStringArray = []
	for r in data:
		ids.append(str(r.id))
	if ",".join(ids) != ",".join(PackedStringArray(_rows.keys())):
		_rebuild(ids)
	for r in data:
		var row: Dictionary = _rows[str(r.id)]
		(row.title as Label).text = str(r.title)
		(row.value as Label).text = str(r.value)
		var bar: ProgressBar = row.bar
		bar.visible = float(r.frac) >= 0.0
		bar.value = clampf(float(r.frac), 0.0, 1.0)
		(row.btn as Button).tooltip_text = tr(str(r.tip))
		(row.btn as Button).set_meta("screen", str(r.screen))
		(row.btn as Button).set_meta("params", r.params)
		(row.btn as Button).disabled = str(r.screen).is_empty()
	visible = not data.is_empty()


func row_ids() -> Array:
	return _rows.keys()


func row_button(id: String) -> Button:
	return (_rows[id].btn as Button) if _rows.has(id) else null


func _rebuild(ids: PackedStringArray) -> void:
	for r in _rows.values():
		(r.btn as Button).queue_free()
	_rows.clear()
	for id in ids:
		var btn := Button.new()
		btn.name = "Row_" + id
		btn.flat = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.custom_minimum_size = Vector2(0, ROW_H)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		btn.add_child(v)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(h)
		var t := Label.new()
		t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN       # il titolo resta intero; il valore cede spazio (puntini)
		h.add_child(t)
		var val := Label.new()
		val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		val.theme_type_variation = &"MutedLabel"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.clip_text = true                                      # valori lunghi (zona e mostro): puntini, non tagli secchi
		val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(val)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.step = 0.0
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bar)
		btn.pressed.connect(_on_row_pressed.bind(btn))
		add_child(btn)
		_rows[id] = {"btn": btn, "title": t, "value": val, "bar": bar}


func _on_row_pressed(btn: Button) -> void:
	var screen := str(btn.get_meta("screen", ""))
	if not screen.is_empty():
		EventBus.screen_requested.emit(screen, btn.get_meta("params", {}))
