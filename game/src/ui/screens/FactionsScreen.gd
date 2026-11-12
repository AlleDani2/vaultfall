extends GameScreen
## Fazioni e incarichi di fazione (docs/10 §6, T-5.3, GUILD-2): per ognuna delle 5 fazioni il grado, la barra verso il
## prossimo, i bonus dei gradi e i 6 incarichi della catena (accetta → svolgi → riscuoti). Reputazione e titoli arrivano
## dalle ricompense (QuestSystem.claim → MarketSystem.add_reputation / CompendiumSystem.grant_title).
## Si ricostruisce solo se cambia lo stato degli incarichi o un grado; le barre si aggiornano sul posto.

const DONE_COLOR := Color(0.62, 0.85, 0.52)
const MUTED_ALPHA := 0.62
const SIDE_PX := 170

var _mk: MarketSystem
var _qs: QuestSystem
var _col: VBoxContainer
var _sig: String = ""
var _bars: Array[Dictionary] = []          # {qid, idx, bar, label}
var _fbars: Dictionary = {}                # faction_id -> {bar, label}
static var _open_state: Dictionary = {}    # faction_id -> aperta? (solo per la sessione; vuoto = decide `_default_open`)


func open(_params: Dictionary) -> void:
	_mk = Game.system("market") as MarketSystem
	_qs = Game.system("quests") as QuestSystem
	var title := Label.new()
	ScreenKit.title_style(title)
	title.text = tr("UI_MENU_FACTIONS")
	add_child(title)
	if _mk == null or _qs == null:
		return
	var intro := Label.new()
	intro.text = tr("UI_GUILD2_FAC_INTRO")
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 400
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 10)
	scroll.add_child(_col)
	refresh()


func refresh() -> void:
	if _mk == null or _qs == null or _col == null:
		return
	var parts := PackedStringArray([Loc.locale()])
	for fid in _mk.faction_ids():
		parts.append("%s:%d" % [fid, _mk.rank_index(str(fid))])
		for qid in _qs.faction_quests(str(fid)):
			parts.append(_qs.faction_quest_status(str(qid)))
	var sig := "|".join(parts)
	if sig != _sig:
		_sig = sig
		_rebuild()
	_update_bars()


func _lab(parent: Control, text: String, variation: StringName = &"", dynamic: bool = true) -> Label:
	var l := Label.new()
	if dynamic:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	parent.add_child(l)
	return l


func _rebuild() -> void:
	for c in _col.get_children():
		c.queue_free()
	_bars.clear()
	_fbars.clear()
	for fid in _mk.faction_ids():
		_add_faction(str(fid))


func _add_faction(fid: String) -> void:
	var f: Dictionary = DataRegistry.get_def("factions", fid)
	var panel := PanelContainer.new()
	_col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var icon := VaultKit.pix(IconLib.icon("factions", fid), 1)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(icon)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_lab(hv, Loc.t(f.get("name", fid)), &"SectionLabel")
	var npc := DataRegistry.get_def("npcs", str(f.get("npc", "")))
	_lab(hv, "%s — %s" % [Loc.t(npc.get("name", f.get("npc", ""))), Loc.t(f.get("desc", {}))], &"MutedLabel")
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	var rl := _lab(v, "", &"MonoLabel")
	_fbars[fid] = {"bar": bar, "label": rl}
	# gradi e incarichi in un corpo RIPIEGABILE (apre da solo la fazione con un incarico da fare): niente muro di testo di cinque fazioni
	var body := VBoxContainer.new()
	body.name = "FactionBody_" + fid
	body.add_theme_constant_override("separation", 6)
	body.visible = _is_open(fid)
	v.add_child(body)
	var tog := Button.new()
	tog.name = "FactionToggle_" + fid
	tog.flat = true
	tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tog.text = (Disclosure.OPEN if body.visible else Disclosure.CLOSED) + tr("UI_GB_FAC_DETAILS")
	tog.pressed.connect(func() -> void:
		body.visible = not body.visible
		_open_state[fid] = body.visible
		tog.text = (Disclosure.OPEN if body.visible else Disclosure.CLOSED) + tr("UI_GB_FAC_DETAILS"))
	v.add_child(tog)
	v.move_child(tog, body.get_index())
	_add_ranks(body, f)
	_lab(body, tr("UI_GUILD2_FAC_QUESTS"), &"SectionLabel", false)
	for qid in _qs.faction_quests(fid):
		_add_quest(body, str(qid))


## Aperta se l'utente l'ha scelto; altrimenti solo la PRIMA fazione che ha un incarico da accettare/riscuotere/in corso.
func _is_open(fid: String) -> bool:
	if _open_state.has(fid):
		return bool(_open_state[fid])
	for f2 in _mk.faction_ids():
		for qid in _qs.faction_quests(str(f2)):
			if _qs.faction_quest_status(str(qid)) in ["available", "active", "ready"]:
				return str(f2) == fid
	return false


func _add_ranks(v: Control, f: Dictionary) -> void:
	var cur := _mk.rank_index(str(f.id))
	var ranks: Array = f.get("ranks", [])
	for i in ranks.size():
		var r: Dictionary = ranks[i]
		var rw := PackedStringArray()
		for rr in f.get("rank_rewards", []):
			if str(rr.rank) == str(r.id):
				for m in rr.get("modifiers", []):
					rw.append(CrateUi.mod_text(m))
				var tid: Variant = rr.get("title")
				if tid != null and str(tid) != "":
					rw.append(Loc.tf("UI_GUILD2_ACH_REWARD_TITLE", {"name": Loc.t(DataRegistry.get_def("titles", str(tid)).get("name", tid))}))
		var line := Loc.tf("UI_GUILD2_FAC_RANK", {"rank": Loc.t(r.name), "rep": NumberFormat.fmt(int(r.rep)),
			"reward": ", ".join(rw) if not rw.is_empty() else tr("UI_GUILD2_NONE")})
		var l := _lab(v, line, &"MutedLabel")
		if i <= cur:
			l.add_theme_color_override("font_color", DONE_COLOR)


func _add_quest(v: Control, qid: String) -> void:
	var d := _qs.quest_def(qid)
	var st := _qs.faction_quest_status(qid)
	var panel := PanelContainer.new()
	panel.modulate.a = 1.0 if st in ["available", "active", "ready"] else MUTED_ALPHA
	v.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var nm := _lab(tv, QuestText.title(d), &"SectionLabel")
	if st == "done":
		nm.add_theme_color_override("font_color", DONE_COLOR)
	_lab(tv, Loc.t(d.get("desc", {})), &"MutedLabel")
	var objs: Array = d.get("objectives", [])
	for i in objs.size():
		_lab(tv, QuestText.objective(objs[i], DataRegistry), &"MonoLabel")
		if st == "active" or st == "ready":
			var pb := ProgressBar.new()
			pb.show_percentage = false
			pb.custom_minimum_size = Vector2(0, 12)
			tv.add_child(pb)
			var pl := _lab(tv, "", &"MonoLabel")
			_bars.append({"qid": qid, "idx": i, "bar": pb, "label": pl})
	var rewards := QuestText.reward_lines(_qs.reward_preview(qid), DataRegistry)
	if not rewards.is_empty():
		_lab(tv, "%s: %s" % [tr("UI_QUESTS_REWARDS"), ", ".join(rewards)], &"MutedLabel")
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_PX, 0)
	h.add_child(side)
	match st:
		"available":
			var b := Button.new()
			b.text = "UI_GUILD2_FQ_ACCEPT"
			b.pressed.connect(_on_accept.bind(qid))
			side.add_child(b)
		"ready":
			var b2 := Button.new()
			b2.text = "UI_GUILD2_FQ_CLAIM"
			b2.pressed.connect(_on_claim.bind(qid))
			side.add_child(b2)
		"done":
			_lab(side, tr("UI_GUILD2_FQ_DONE"), &"", false).add_theme_color_override("font_color", DONE_COLOR)
		"locked":
			_lab(side, tr("UI_GUILD2_FQ_LOCKED"), &"MutedLabel", false)
		"pending":
			_lab(side, tr("UI_GUILD2_FQ_PENDING"), &"MutedLabel", false)


func _on_accept(qid: String) -> void:
	_qs.accept_faction_quest(qid)
	_sig = ""


func _on_claim(qid: String) -> void:
	_qs.claim(qid)
	_sig = ""


func _update_bars() -> void:
	for b in _bars:
		var objs: Array = _qs.quest_def(b.qid).get("objectives", [])
		var pr := _qs.progress_of(b.qid)
		var target := QuestSystem.target_of(objs[b.idx])
		var val := int(pr[b.idx]) if b.idx < pr.size() else 0
		(b.bar as ProgressBar).max_value = maxf(1.0, float(target))
		(b.bar as ProgressBar).value = float(val)
		(b.label as Label).text = "%s / %s" % [NumberFormat.fmt(val), NumberFormat.fmt(target)]
	for fid in _fbars:
		var f: Dictionary = DataRegistry.get_def("factions", str(fid))
		var ranks: Array = f.get("ranks", [])
		var rep := _mk.reputation(str(fid))
		var i := _mk.rank_index(str(fid))
		var fb: Dictionary = _fbars[fid]
		if i + 1 < ranks.size():
			var lo := int(ranks[i].rep)
			var hi := int(ranks[i + 1].rep)
			(fb.bar as ProgressBar).max_value = float(hi - lo)
			(fb.bar as ProgressBar).value = float(rep - lo)
			(fb.label as Label).text = Loc.tf("UI_GUILD2_FAC_NEXT", {"rank": Loc.t(ranks[i].name), "rep": NumberFormat.fmt(rep),
				"need": NumberFormat.fmt(hi), "next": Loc.t(ranks[i + 1].name)})
		else:
			(fb.bar as ProgressBar).max_value = 1.0
			(fb.bar as ProgressBar).value = 1.0
			(fb.label as Label).text = Loc.tf("UI_GUILD2_FAC_MAX", {"rank": Loc.t(ranks[i].name), "rep": NumberFormat.fmt(rep)})
