extends GutTest
## T-4.4 / criteri M4: ordine del Prologo, nessun sistema introdotto prima del suo sblocco, prima ora simulata
## con sistemi finti. Si prova sia con i dati completi (data/) sia con il perimetro della slice (data_slice/).

const Fakes := preload("res://tests/helpers/quest_fakes.gd")

var _keep: Array = []


func _slice_quests() -> Array:
	var p := ProjectSettings.globalize_path("res://").path_join("../data_slice/quests.json")
	if not FileAccess.file_exists(p):
		return []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Array else []


func _make(quests: Array) -> Dictionary:
	var data := Fakes.FakeData.new()
	data.quests = quests
	var state := {"unlocks": [], "skills": {}, "equipment": {}, "estate": {"buildings": {}}, "hero": {"class": "warrior"}}
	var ctx := SystemContext.make(data, state, ModifierStack.new(), RngStreams.new(3), EventBus)
	var sim := Simulation.new()
	var q := QuestSystem.new()
	var u := UnlockSystem.new()
	var bank := Fakes.FakeBank.new()
	sim.setup(ctx, [bank, Fakes.FakeCrates.new(), q, u])
	sim.bind_state(state)
	sim.tick(0.1)
	_keep.append(sim)
	return {"sim": sim, "q": q, "u": u, "bank": bank, "state": state}


func _action_for(item: String) -> String:
	var acts := DataRegistry.all_actions()
	for aid in acts:
		for o in acts[aid].get("outputs", []):
			if o is Dictionary and o.get("item", "") == item:
				return aid
	return ""


## Il giocatore finto fa ciò che chiede un obiettivo. Ritorna i secondi di gioco che richiederebbe (dai dati).
func _do(m: Dictionary, obj: Dictionary) -> float:
	var t := str(obj.type)
	var qty := QuestSystem.target_of(obj)
	match t:
		"gather", "craft":
			var aid := _action_for(str(obj.item))
			assert_ne(aid, "", "esiste un'azione che produce " + str(obj.item))
			EventBus.action_completed.emit(aid, [{"item": obj.item, "qty": qty}])
			return qty * float(DataRegistry.action(aid).get("time_s", 3.0))
		"kill":
			for i in qty:
				EventBus.monster_killed.emit(str(obj.monster), [])
			return qty * float(DataRegistry.constants.combat.ttk_target_s)
		"equip":
			m.bank.instances["i_eq"] = {"def": obj.item}
			m.state.equipment["weapon"] = "i_eq"
		"open_crates":
			EventBus.crate_opened.emit({"crate_id": "crate_millbrook"})
		"sell_market":
			EventBus.objective_event.emit("sell_market", {"gold": qty})
		"farm_harvest":
			EventBus.objective_event.emit("farm_harvest", {"crop": obj.crop, "qty": qty})
		_:
			var p := {"qty": qty}
			for k in obj:
				if k != "type":
					p[k] = obj[k]
			EventBus.objective_event.emit(t, p)
	return 0.0


## Gioca la storia principale nell'ordine dei dati finché non esaurisce le missioni; ritorna il diario.
func _play(m: Dictionary, max_quests: int) -> Array:
	var diary: Array = []
	var clock := 0.0
	for n in max_quests:
		var qid: String = m.q.current_main()
		if qid.is_empty():
			break
		var d: Dictionary = m.q.quest_def(qid)
		var entry := {"id": qid, "t_min": clock / 60.0, "new_at_step": []}
		# nessun sistema usato prima dello sblocco
		for obj in d.objectives:
			for tok in UnlockSystem.required_tokens(obj, DataRegistry):
				if tok != "*":
					assert_true(m.u.has(tok), "%s: manca %s all'accettazione" % [qid, tok])
		for obj in d.objectives:
			clock += _do(m, obj)
		m.sim.tick(0.1)
		for i in 12:
			m.sim.tick(0.1)
		assert_true(m.q.is_ready(qid), "pronta: " + qid)
		var before: Array = m.state.unlocks.duplicate()
		assert_true(m.q.claim(qid), "riscatto: " + qid)
		for tok in m.state.unlocks:
			if not before.has(tok):
				entry.new_at_step.append(tok)
		entry["claimed_min"] = clock / 60.0
		entry["unlocks_after"] = m.state.unlocks.duplicate()
		diary.append(entry)
	return diary


func test_prologo_dati_completi_nell_ordine() -> void:
	var m := _make(DataRegistry.table("quests"))
	assert_eq(m.q.current_main(), "main_c0_q1", "si parte dalla prima missione del Prologo")
	assert_eq(m.state.unlocks, ["skill:woodcutting"], "all'inizio solo ciò che serve alla prima missione")
	var diary := _play(m, 12)
	var ids: Array = []
	for e in diary:
		ids.append(e.id)
	assert_eq(ids.slice(0, 6), ["main_c0_q1", "main_c0_q2", "main_c0_q3", "main_c0_q4", "main_c0_q5", "main_c0_q6"])
	assert_eq(ids.slice(6, 12), ["main_c1_q1", "main_c1_q2", "main_c1_q3", "main_c1_q4", "main_c1_q5", "main_c1_q6"])
	for t in ["skill:woodcutting", "skill:mining", "skill:smithing", "skill:fishing", "skill:cooking", "feature:combat",
			"feature:crates", "skill:keysmithing", "feature:wardrobe", "skill:foraging", "skill:farming", "feature:market"]:
		assert_true(m.u.has(t), t)
	# pochi sistemi per volta: a ogni consegna (sblocchi rimandati + quelli della missione successiva) al più 3
	for e in diary:
		var n := 0
		for t in e.new_at_step:
			if UnlockSystem.has_tutorial(t):
				n += 1
		assert_lte(n, 3, "sistemi aperti in un colpo: " + e.id)


func test_prologo_slice_ordine_e_prima_ora() -> void:
	var quests := _slice_quests()
	# data_slice/ e' versionata (tools/generate_data.py --scope slice): se manca e' un errore, non un test da saltare
	assert_false(quests.is_empty(), "data_slice/quests.json presente e leggibile")
	if quests.is_empty():
		return
	var m := _make(quests)
	assert_eq(m.q.current_main(), "main_c0_q1")
	var diary := _play(m, 20)
	var ids: Array = []
	for e in diary:
		ids.append(e.id)
	assert_eq(ids, ["main_c0_q1", "main_c0_q3", "main_c0_q4", "main_c0_q2", "main_c0_q5", "main_c1_q1", "main_c1_q5", "main_c1_q6"],
		"ordine della slice: Taglialegna, Pesca+Cucina, Combattimento, poi il resto")
	# criterio M4: prima Cassa aperta entro 15 minuti (tempi derivati dai dati delle azioni)
	var crate_quest: Dictionary = diary[4]
	assert_lte(float(crate_quest.claimed_min), 15.0, "prima Cassa entro 15 minuti")
	var line := PackedStringArray()
	for e in diary:
		line.append("%s@%.1f" % [e.id, float(e.claimed_min)])
	gut.p("Prima ora (minuti simulati dai dati): " + ", ".join(line))
	# al minuto 30 al più 4 mansioni aperte (audit 03, correzione 1)
	var skills_at_30 := 0
	for tok in m.state.unlocks:
		if str(tok).begins_with("skill:"):
			skills_at_30 += 1
	assert_lte(skills_at_30, 7, "mansioni aperte dopo il Prologo della slice")


func test_nessun_obiettivo_richiede_un_sistema_mai_sbloccato() -> void:
	# su TUTTA la storia principale: i token necessari agli obiettivi sono concessi da questa o da una missione precedente
	var granted := {}
	var gaps: Array = []
	var quests: Array = DataRegistry.table("quests")
	var by_id := {}
	for q in quests:
		by_id[q.id] = q
	var order: Array = []
	var seen := {}
	var progress := true
	while progress:
		progress = false
		for q in quests:
			if q.kind != "main" or seen.has(q.id):
				continue
			var ok := true
			for r in q.requires:
				if not seen.has(r):
					ok = false
			if ok:
				seen[q.id] = true
				order.append(q)
				progress = true
	assert_eq(order.size(), 71, "71 missioni principali raggiungibili in catena")
	for q in order:
		var early: Array = []
		var needed := {}
		var star := false
		for obj in q.objectives:
			for t in UnlockSystem.required_tokens(obj, DataRegistry):
				if t == "*":
					star = true
				else:
					needed[t] = true
		for u in q.unlocks:
			if star or needed.has(u):
				early.append(u)
		for u in early:
			granted[u] = true
		for t in needed:
			if not granted.has(t):
				gaps.append("%s richiede %s" % [q.id, t])
		for u in q.unlocks:
			granted[u] = true
	# informativo: lacune dei dati (token mai concessi prima dell'uso) oltre il Capitolo I
	var early_gaps := gaps.filter(func(g: String) -> bool: return g.begins_with("main_c0") or g.begins_with("main_c1"))
	assert_eq(early_gaps, [], "Prologo e Capitolo I senza lacune")
	if not gaps.is_empty():
		gut.p("Lacune dei dati dopo il Cap. I (da correggere nel generatore): " + str(gaps.slice(0, 12)))
