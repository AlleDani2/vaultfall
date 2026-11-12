extends GutTest
## 1.0 GAMEPLAY (docs/review_1_0/02, risposta in docs/review_1_0/12_FIX_GAMEPLAY.md): ritmo dei primi capitoli, primo
## mercenario, ritrovamenti secondari offline, testi (genere, nomi, ripetizioni).

const FIRST_TEXTS_BANNED := ["fotogenic", "Spada del Drago", "Sacchetto di Rune", "Una Stella Dorata."]


func _quest(qid: String) -> Dictionary:
	for q in DataRegistry.table("quests"):
		if str(q.id) == qid:
			return q
	return {}


# ------------------------------------------------------------------ ritmo

func test_spada_di_rame_serve_forgiatura_bassa() -> void:
	var a: Dictionary = DataRegistry.action("smith_sword_copper")
	assert_lte(int(a.level_req), 2, "la prima Cassa (main_c0_q4) non deve aspettare molti livelli di Forgiatura")
	assert_eq(int(DataRegistry.action("smith_greatsword_copper").level_req), 7, "gli altri pezzi non cambiano")


func test_sblocchi_del_capitolo_2_spalmati() -> void:
	var u5: Array = _quest("main_c2_q5").unlocks
	assert_false(u5.has("feature:orders") or u5.has("feature:factions"), "Commesse e Fazioni non arrivano insieme alla Borseggio")
	assert_true((_quest("main_c3_q1").unlocks as Array).has("feature:orders"))
	assert_true((_quest("main_c3_q3").unlocks as Array).has("feature:factions"))
	# nessun capitolo 0-3 apre piu' di 4 funzioni/edifici/mansioni con una sola missione, tranne la Tenuta (4 voci coerenti)
	for qid in ["main_c2_q3", "main_c2_q4", "main_c2_q5", "main_c2_q6", "main_c3_q1", "main_c3_q2", "main_c3_q3"]:
		assert_lte((_quest(qid).unlocks as Array).size(), 3, "%s: pochi sblocchi alla volta" % qid)


func test_gemme_dei_primi_tier_si_trovano_in_pochi_minuti() -> void:
	var a: Dictionary = DataRegistry.action("mine_copper")
	var chance := float(a.secondary[0].chance)
	var expected_actions := 3.0 / chance
	assert_lte(expected_actions * float(a.time_s) / 60.0, 8.0, "3 Quarzi in meno di ~8 minuti di scavo")
	assert_almost_eq(float(DataRegistry.action("mine_cobalt").secondary[0].chance), 0.01, 1e-9, "dal tier 4 resta l'1%")


func test_quarzo_offline_conta_per_la_missione() -> void:
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 5))
	var q := Game.system("quests") as QuestSystem
	var done: Array = []
	for qid in q._main_ids:
		if qid == "main_c3_q2":
			break
		done.append(qid)
	q.state.done = done
	q.state.active = []
	q.state.progress = {}
	for t in ["skill:mining", "skill:smithing"]:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)
	q._ensure_accepted()
	assert_eq(q.current_main(), "main_c3_q2")
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start("mine_copper"))
	Game.apply_absence(3600.0)
	assert_eq(int(q.progress_of("main_c3_q2")[0]), 3, "i Quarzi trovati offline contano per «Estrai 3 Quarzi Grezzi»")
	Game.stop_game(false)


# ------------------------------------------------------------------ primo mercenario

func test_prima_assunzione_ha_sempre_un_candidato_comune() -> void:
	for sd in 60:
		var f := EstateFixtures.make(1000 + sd)
		autofree(f.events)
		f.set_levels({"cottage": 10, "tavern": 1})
		f.sim.tick(0.1)
		var commons := 0
		for c in f.mercs.candidates():
			if str(c.rarity) == "common":
				commons += 1
		assert_gte(commons, 1, "seme %d: Taverna vuota = almeno un candidato Comune" % (1000 + sd))


# ------------------------------------------------------------------ testi

func _all_text_it() -> String:
	var out := PackedStringArray()
	for cat in ["equipment", "skin", "openable", "misc"]:
		for it in DataRegistry.items_by_category(cat):
			out.append(Loc.t(it.name))
			out.append(Loc.t(it.get("desc", {})))
	for a in DataRegistry.table("achievements"):
		out.append(Loc.t(a.name))
		out.append(Loc.t(a.get("desc", {})))
	return "\n".join(out)


func test_testi_corretti() -> void:
	var txt := _all_text_it()
	for banned in FIRST_TEXTS_BANNED:
		assert_false(txt.contains(banned), "testo da evitare: %s" % banned)
	assert_false(txt.contains("più largo"), "italiano neutro per genere")


func test_frasi_di_colore_non_si_ripetono_troppo() -> void:
	var counts := {}
	for cat in ["equipment", "skin", "tool", "ammo", "material", "seed"]:
		for it in DataRegistry.items_by_category(cat):
			var d := str(Loc.t(it.get("desc", {})))
			for s in d.split(". "):
				var k := s.strip_edges()
				if k.length() > 25:
					counts[k] = int(counts.get(k, 0)) + 1
	var worst := 0
	var worst_s := ""
	for k in counts:
		if int(counts[k]) > worst:
			worst = int(counts[k])
			worst_s = str(k)
	assert_lte(worst, 14, "nessuna frase di colore oltre 14 volte (peggiore: «%s» %d)" % [worst_s, worst])
