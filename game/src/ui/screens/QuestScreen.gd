extends GameScreen
## Missioni (docs/12, docs/16): capitolo corrente, missioni attive con barre, riscatto con effetto, storia finora.
## Solo presentazione: legge QuestSystem (Game.system("quests")) e chiama claim()/deliver().
## L'elenco si ricostruisce solo quando cambia la composizione (missioni attive/pronte/completate); le barre
## si aggiornano sul posto a ogni refresh (≤ 10 Hz).

const POP_SECONDS := 0.22
const FANFARE_SECONDS := 0.9
const UPCOMING_SHOWN := 3          # quante missioni della storia mostrare in «Prossime»
const GRID_TWO_COLS_W := 1000.0   # sotto questa larghezza utile le carte vanno in una colonna sola
const TAB_QUESTS := 0
const TAB_DISCOVER := 1

@onready var _box: VBoxContainer = %VBox

var _quests: QuestSystem
var _sig: String = ""
var _bars: Array[Dictionary] = []        # {bar, label, qid, idx}
var _history_open: bool = false
var _tab_nodes: Dictionary = {}          # scheda -> nodi dell'elenco che le appartengono
var _tab: int = TAB_QUESTS                # F6: «Da scoprire» ha la sua scheda (compare solo con novità)
var _contracts: ContractsPanel = null     # Commesse giornaliere/settimanali (ContractSystem), se la funzione è aperta
var _focus_quest: String = ""


func open(params: Dictionary) -> void:
	_quests = Game.system("quests") as QuestSystem
	_sig = ""
	_focus_quest = str(params.get("quest", ""))      # da un requisito cliccato altrove (ReqLink, G37): la missione si porta in vista
	_tab = TAB_DISCOVER if str(params.get("tab", "")) == "discover" else TAB_QUESTS      # dalla riga «Da fare» del Riepilogo
	if not resized.is_connected(_fit_grids):
		resized.connect(_fit_grids)
	refresh()


func refresh() -> void:
	if _quests == null:
		return
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_rebuild()
		_reveal_focus()
	_update_bars()
	if _contracts != null and is_instance_valid(_contracts):
		_contracts.refresh()


func _contract_system() -> ContractSystem:
	var cs := Game.system("contracts") as ContractSystem
	return cs if cs != null and cs.is_open() else null


func _reveal_focus() -> void:
	if _focus_quest.is_empty():
		return
	var card: Control = null
	for c in _box.find_children("Card_*", "PanelContainer", true, false):        # l'ultima carta con quell'id (le vecchie sono in coda di rimozione)
		if c.has_meta("qid") and str(c.get_meta("qid")) == _focus_quest:
			card = c as Control
	_focus_quest = ""
	if card != null:
		ReqLink.reveal(card)


func _signature() -> String:
	var parts: PackedStringArray = []
	for a in _quests.active_quests():
		parts.append("%s:%s" % [a.id, a.ready])
	parts.append(str((_quests.state.done as Array).size()))
	parts.append(str(_history_open))
	parts.append(str(_contract_system() != null))
	for d in QuestGuide.discoveries(_quests):
		parts.append(str(d.id))
	parts.append(str((GameState.data.get("unlocks", []) as Array).size()))
	parts.append(Loc.locale())
	return "|".join(parts)


func _update_bars() -> void:
	for b in _bars:
		var pr := _quests.progress_of(b.qid)
		var obj: Dictionary = _quests.quest_def(b.qid).objectives[b.idx]
		var target := QuestSystem.target_of(obj)
		var v := int(pr[b.idx]) if b.idx < pr.size() else 0
		b.bar.max_value = maxf(1.0, float(target))
		b.bar.value = float(v)
		b.label.text = "%s / %s" % [NumberFormat.fmt(v), NumberFormat.fmt(target)]
		if b.get("btn") != null:
			(b.btn as Button).visible = v < target


## Carte a DUE colonne (una sola se la finestra è stretta): la «Riscatta» non è più larga come la pagina.
func _grid(cards: Array) -> GridContainer:
	var g := GridContainer.new()
	g.name = "QuestGrid"
	g.columns = 2 if size.x >= GRID_TWO_COLS_W else 1
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in cards:
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(c as Control).size_flags_vertical = Control.SIZE_FILL
		g.add_child(c)
	return g


func _fit_grids() -> void:
	var cols := 2 if size.x >= GRID_TWO_COLS_W else 1
	for g in _box.find_children("QuestGrid", "GridContainer", true, false):
		if (g as GridContainer).columns != cols:
			(g as GridContainer).columns = cols


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_bars.clear()
	var active := _quests.active_quests()
	ScreenKit.title_style(_add_label("UI_QUESTS_TITLE", &"TitleLabel"))
	var ds := QuestGuide.discoveries(_quests)
	if ds.is_empty():
		_tab = TAB_QUESTS
	else:
		_add_tabs(ds.size())
	var first_tab_node := _box.get_child_count()      # da qui in poi i nodi appartengono alla scheda «Missioni»
	var meta := PackedStringArray()
	var main_id := _quests.current_main()
	if not main_id.is_empty():
		meta.append(QuestText.chapter_name(int(_quests.quest_def(main_id).get("chapter", 0)), DataRegistry))
	meta.append(Loc.tf("UI_QUESTS_DONE_COUNT", {"n": NumberFormat.fmt((_quests.state.done as Array).size())}))
	_add_text(" · ".join(meta), &"MutedLabel")
	# 1) Da riscattare: tutto ciò che è pronto, in un clic
	var ready_list: Array = []
	var todo: Array = []
	var others: Array = []
	for a in active:
		if a.ready:
			ready_list.append(a)
		elif a.kind == "main":
			todo.append(a)
		else:
			others.append(a)
	if not ready_list.is_empty():
		_add_label("UI_QG_CLAIMABLE", &"SectionLabel")
		if ready_list.size() > 1:
			var all := Button.new()
			all.name = "ClaimAllButton"
			all.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			all.text = Loc.tf("UI_QG_CLAIM_ALL", {"n": ready_list.size()})
			all.theme_type_variation = &"AccentButton"
			all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			all.pressed.connect(_on_claim_all)
			_box.add_child(all)
		var rc: Array = []
		for a in ready_list:
			rc.append(_card(a))
		_box.add_child(_grid(rc))
	# 2) Il prossimo passo (la missione principale) è la prima carta dell'elenco, in evidenza: niente blocco «Da fare ora» a parte
	if todo.is_empty() and ready_list.is_empty():
		_add_text(tr("UI_QUESTS_STORY_END") if not (_quests.state.done as Array).is_empty() else tr("UI_QUESTS_NONE_ACTIVE"), &"")
	for a in todo:
		var c := _card(a)
		(c as PanelContainer).add_theme_stylebox_override("panel", ScreenKit.card_style(Color(ScreenKit.GOLD), 4, true))
		c.set_meta("next_step", true)
		_box.add_child(c)
	# 4) Altre missioni in corso (classe, mansione, fazione, secondarie)
	if not others.is_empty():
		_add_label("UI_QG_OTHER", &"SectionLabel")
		var oc: Array = []
		for a in others:
			oc.append(_card(a))
		_box.add_child(_grid(oc))
	# 5) Prossime della storia
	var up := QuestGuide.upcoming(_quests, UPCOMING_SHOWN)
	if not up.is_empty():
		_add_label("UI_QG_NEXT", &"SectionLabel")
		for q in up:
			_box.add_child(_upcoming_row(q))
	# 6) Commesse giornaliere/settimanali e rimandi alle schede delle Imprese e delle Commesse
	_contracts = null
	var cs := _contract_system()
	if cs != null:
		_contracts = ContractsPanel.new()
		_contracts.name = "ContractsPanel"
		_box.add_child(_contracts)
		_contracts.setup(cs)
	_add_elsewhere()
	_add_history()
	# «Da scoprire»: sistemi sbloccati che nessuna missione introduce, nella loro scheda (sempre costruita, mostrata a richiesta)
	_tab_nodes = {TAB_QUESTS: [], TAB_DISCOVER: []}
	for i in range(first_tab_node, _box.get_child_count()):
		(_tab_nodes[TAB_QUESTS] as Array).append(_box.get_child(i))
	for d in ds:
		var dc := _discovery_card(d)
		_box.add_child(dc)
		(_tab_nodes[TAB_DISCOVER] as Array).append(dc)
	_apply_tab()


## Mostra i nodi della scheda scelta e nasconde quelli dell'altra (nessuna ricostruzione).
func _apply_tab() -> void:
	for t in _tab_nodes:
		for n in _tab_nodes[t]:
			if is_instance_valid(n):
				(n as Control).visible = int(t) == _tab


## Schede «Missioni» / «Da scoprire (n)»: la seconda compare solo quando ci sono novità da scoprire.
func _add_tabs(n_discover: int) -> void:
	var row := HBoxContainer.new()
	row.name = "QuestTabs"
	row.add_theme_constant_override("separation", 8)
	var grp := ButtonGroup.new()
	for pair in [[TAB_QUESTS, tr("UI_SCR_SUMMARY_Q_TAB_QUESTS"), "TabQuests"],
			[TAB_DISCOVER, Loc.tf("UI_SCR_SUMMARY_Q_TAB_DISCOVER", {"n": n_discover}), "TabDiscover"]]:
		var b := Button.new()
		b.name = str(pair[2])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = str(pair[1])
		b.toggle_mode = true
		b.button_group = grp
		b.set_pressed_no_signal(_tab == int(pair[0]))
		ScreenKit.style_tab(b, ScreenKit.accent("quests"))
		var which := int(pair[0])
		b.pressed.connect(func() -> void:
			_tab = which
			_apply_tab())
		row.add_child(b)
	_box.add_child(row)


func _add_elsewhere() -> void:
	var links: Array = []
	var unlocks: Array = GameState.data.get("unlocks", [])
	for pair in [["compendium", "UI_QG_OPEN_COMPENDIUM"], ["orders", "UI_QG_OPEN_ORDERS"]]:
		var e := ScreenRegistry.get_entry(pair[0])
		if not e.is_empty() and ScreenRegistry.is_available(e, unlocks):
			links.append(pair)
	if links.is_empty():
		return
	_add_label("UI_QG_ELSEWHERE", &"SectionLabel")
	for pair in links:
		var b := Button.new()
		b.name = "Elsewhere_" + str(pair[0])
		b.text = pair[1]
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(EventBus.screen_requested.emit.bind(str(pair[0]), {}))
		_box.add_child(b)


func _on_claim_all() -> void:
	for a in _quests.active_quests():
		if a.ready:
			_quests.claim(str(a.id))
	_sig = ""
	refresh()


## Riga "Come fare": testo che va a capo + pulsante «Vai» (se c'è un bersaglio). `primary` = pulsante in evidenza.
func _howto_row(text: String, target: Dictionary, primary: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 160
	row.add_child(l)
	if not target.is_empty():
		var b := Button.new()
		b.name = "GoButton" if primary else "GoExtra"
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = QuestGuide.go_label(target) if primary else tr("UI_QG_GO")
		b.tooltip_text = ReqLink.tr_hint(target)
		if primary:
			b.theme_type_variation = &"AccentButton"
			TutorialTargets.mark(b, "quest_go")
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(ReqLink.go.bind(target))
		row.add_child(b)
	return row


## Blocco «Come fare»: per ogni obiettivo ancora da raggiungere, l'istruzione esplicita, il «Vai» e le righe di dettaglio
## (ingredienti, livello che manca, zona chiusa) ciascuna con la sua fonte.
func _howto_block(d: Dictionary, a: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "HowTo"
	box.add_theme_constant_override("separation", 4)
	# niente intestazione «Come fare»: l'istruzione col suo «Vai» si capisce da sola (F6, un elemento in meno per carta)
	var objs: Array = d.get("objectives", [])
	var pr := _quests.progress_of(str(a.id))
	var seen_text: Dictionary = {}
	var blocks: Array = []                    # [{i, h}] una istruzione per obiettivo ancora da raggiungere
	for i in objs.size():
		if i < pr.size() and int(pr[i]) >= QuestSystem.target_of(objs[i]):
			continue
		var h := QuestGuide.howto(objs[i])
		if seen_text.has(str(h.text)):            # due obiettivi con la stessa istruzione (livello + azioni): una volta sola
			continue
		seen_text[str(h.text)] = true
		blocks.append({"i": i, "h": h})
	var shown := 0
	for bl in blocks:
		var i: int = bl.i
		var h: Dictionary = bl.h
		# l'istruzione dice a quale obiettivo si riferisce solo se ce n'è più d'una: con una sola, l'obiettivo è già nelle righe sopra
		# (F6: l'obiettivo non si ripete)
		if blocks.size() > 1:
			var og := Label.new()
			og.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			og.theme_type_variation = &"SectionLabel"
			og.text = QuestText.objective(objs[i], DataRegistry)
			box.add_child(og)
		box.add_child(_howto_row(str(h.text), h.target, shown == 0))
		for ex in h.extra:
			var r := _howto_row(str(ex.text), ex.target, false)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", 14)
			m.add_child(r)
			box.add_child(m)
		shown += 1
	return box


func _discovery_card(g: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Discover_" + str(g.id)
	card.theme_type_variation = &"ContentPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := Label.new()
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.theme_type_variation = &"SectionLabel"
	head.text = str(g.title)
	v.add_child(head)
	v.add_child(_howto_row(str(g.text), g.target, true))
	var why := Label.new()
	why.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	why.theme_type_variation = &"MutedLabel"
	why.text = "%s: %s" % [tr("UI_QG_WHY_LABEL"), g.why]
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(why)
	return card


func _upcoming_row(q: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Upcoming_" + str(q.id)
	box.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.text = QuestText.title(q)
	box.add_child(t)
	var why := QuestGuide.why(q)
	var lock := QuestGuide.lock_reason(q, _quests)
	var line := why if lock.is_empty() else (str(lock.text) + ("  ·  " + why if not why.is_empty() else ""))
	if not line.is_empty():
		var m := Label.new()
		m.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		m.theme_type_variation = &"MutedLabel"
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.text = line
		box.add_child(m)
	return box


func _add_label(key: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = key
	if variation != &"":
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _add_text(text: String, variation: StringName) -> void:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	_box.add_child(l)


func _card(a: Dictionary) -> Control:
	var d := _quests.quest_def(a.id)
	var card := PanelContainer.new()
	card.name = "Card_" + str(a.id)
	card.set_meta("qid", str(a.id))
	card.theme_type_variation = &"ContentPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := Label.new()
	head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	head.theme_type_variation = &"SectionLabel"
	head.text = QuestText.title(d)
	v.add_child(head)
	var giver_name := Loc.t(DataRegistry.get_def("npcs", str(d.get("giver", ""))).get("name", ""))
	if not giver_name.is_empty():
		var g := Label.new()
		g.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		g.theme_type_variation = &"MutedLabel"
		g.text = Loc.tf("UI_QUESTS_GIVER", {"name": giver_name})
		v.add_child(g)
	var desc := Label.new()
	desc.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	desc.text = Loc.t(d.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var objs: Array = d.get("objectives", [])
	for i in objs.size():
		v.add_child(_objective_row(a.id, i, objs[i]))
	if not a.ready:
		v.add_child(_howto_block(d, a))
		var wy := QuestGuide.why(d)
		if not wy.is_empty():
			var wl := Label.new()
			wl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			wl.theme_type_variation = &"MutedLabel"
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.text = wy
			v.add_child(wl)
	var preview: Array = []
	for rp in _quests.reward_preview(a.id):
		if str(rp.kind) != "unlock" or a.ready:        # gli sblocchi sono già nella riga «Sblocca» sopra
			preview.append(rp)
	var foot := HBoxContainer.new()               # ricompense a sinistra (icone con quantità), «Riscatta» compatto a destra
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	if not preview.is_empty():
		var rb := VBoxContainer.new()
		rb.add_theme_constant_override("separation", 2)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(rb)
		var r := Label.new()
		r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		r.theme_type_variation = &"MutedLabel"
		r.text = tr("UI_QUESTS_REWARDS")
		rb.add_child(r)
		rb.add_child(QuestText.reward_chips(preview, DataRegistry))
	else:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(sp)
	if a.ready:
		var b := Button.new()
		b.name = "ClaimButton"
		b.text = "UI_QUESTS_CLAIM"
		b.theme_type_variation = &"AccentButton"
		b.custom_minimum_size = Vector2(180, 40)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_claim.bind(str(a.id), card, b))
		foot.add_child(b)
	return card


func _objective_row(qid: String, idx: int, obj: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var text := Label.new()
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.text = QuestText.objective(obj, DataRegistry)
	text.custom_minimum_size.x = 140
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(70, 18)
	row.add_child(bar)
	var num := Label.new()
	num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	num.theme_type_variation = &"MonoLabel"
	num.custom_minimum_size.x = 76
	row.add_child(num)
	var action_btn: Button = null          # «Consegna» / «Parla»: sparisce a obiettivo completato (PT118: restava cliccabile a 1 / 1)
	if str(obj.get("type", "")) == "deliver":
		var b := Button.new()
		b.name = "DeliverButton"
		b.text = "UI_QUESTS_DELIVER"
		b.pressed.connect(func() -> void:
			_quests.deliver(qid, idx)
			_sig = "")
		row.add_child(b)
		action_btn = b
	if str(obj.get("type", "")) == "talk":
		var tb := Button.new()
		tb.name = "TalkButton"
		tb.text = "UI_QUESTS_TALK"
		var npc := str(obj.get("npc", ""))
		tb.pressed.connect(func() -> void:
			_quests.talk(npc)
			_sig = "")
		row.add_child(tb)
		action_btn = tb
	_bars.append({"bar": bar, "label": num, "qid": qid, "idx": idx, "btn": action_btn})
	return row


## Riscatto con effetto: la scheda "scatta" e brilla, sale la scritta di congratulazioni, poi si consegna.
func _on_claim(qid: String, card: Control, button: Button) -> void:
	button.disabled = true
	if Settings.get_value("reduce_motion") or not is_inside_tree():
		_do_claim(qid)
		return
	card.pivot_offset = card.size / 2.0
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "scale", Vector2(1.03, 1.03), POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate", Color(1.5, 1.4, 0.9), POP_SECONDS)
	tw.chain().tween_callback(_do_claim.bind(qid))
	_fanfare(card.global_position + Vector2(card.size.x / 2.0 - 40.0, 0.0))


func _do_claim(qid: String) -> void:
	if _quests != null and _quests.claim(qid):
		_sig = ""
		refresh()


func _fanfare(at: Vector2) -> void:
	var l := Label.new()
	l.text = "UI_QUESTS_CLAIM_FANFARE"
	l.theme_type_variation = &"TitleLabel"
	l.top_level = true
	l.z_index = 50
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", at.y - 48.0, FANFARE_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, FANFARE_SECONDS).set_delay(FANFARE_SECONDS * 0.4)
	tw.chain().tween_callback(l.queue_free)


func _add_history() -> void:
	var done_main: Array = []
	for q in _quests.state.done:
		if str(_quests.quest_def(q).get("kind", "")) == "main":
			done_main.append(q)
	if done_main.is_empty():
		return
	var toggle := Button.new()
	Disclosure.apply(toggle, "UI_QUESTS_HISTORY", _history_open)
	toggle.toggle_mode = true
	toggle.button_pressed = _history_open
	toggle.toggled.connect(func(on: bool) -> void:
		_history_open = on
		_sig = "")
	_box.add_child(toggle)
	if not _history_open:
		return
	done_main.reverse()
	for q in done_main:
		var d := _quests.quest_def(q)
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = &"MutedLabel"
		l.text = "%s — %s" % [QuestText.title(d), Loc.t(d.get("desc", ""))]
		_box.add_child(l)
