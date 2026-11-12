extends GutTest
## FIX-PROGRESSIONE (QA5, docs/audit_2026-10-22/qa/55_QA5_coerenza.md): Capitolo XI («Parla con Ilde»), Collegio Arcano
## (craft_category / craft_rank), Commesse giornaliere e settimanali, oggetti apribili, sconto dell'Affinatura, migrazione
## di schema v1 -> v2. Tutto sui sistemi VERI (Game.new_game).

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_progression_fix_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _new_game(seed_value: int = 7) -> void:
	assert_true(Game.new_game(1, "normal", seed_value))


func _unlock(tokens: Array) -> void:
	for t in tokens:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)


func _step(n: int = 1) -> void:
	for i in n:
		Game._on_step(0.1)


func _quests() -> QuestSystem:
	return Game.system("quests") as QuestSystem


# ------------------------------------------------------------------ Capitolo XI

## Porta la storia al punto «tutto fatto fino alla fine del Cap. X».
func _skip_to_epilogue() -> void:
	var q := _quests()
	q.state.active.clear()
	q.state.progress.clear()
	for qid in q._main_ids:
		if qid.begins_with("main_c11"):
			break
		if not q.is_done(qid):
			q.state.done.append(qid)
	q.start()
	_step(3)


func test_capitolo_11_si_sblocca_parlando_con_ilde() -> void:
	_new_game()
	_skip_to_epilogue()
	var q := _quests()
	assert_eq(q.current_main(), "main_c11_q1")
	assert_false(q.is_ready("main_c11_q1"))
	assert_false(q.talk("sefora"), "parlare con un altro PNG non avanza l'obiettivo")
	assert_true(q.has_open_talk("ilde"))
	assert_true(q.talk("ilde"), "il pulsante «Parla» emette l'evento")
	assert_true(q.is_ready("main_c11_q1"))
	assert_false(q.talk("ilde"), "obiettivo già completato: niente doppio evento")
	assert_true(q.claim("main_c11_q1"))
	assert_true(GameState.has_unlock("era:2"), "il Cap. XI porta all'Era 2")
	assert_eq(q.current_main(), "main_c11_q2", "la storia prosegue")


func test_talk_senza_missione_attiva_non_fa_nulla() -> void:
	_new_game()
	assert_false(_quests().talk("ilde"))


# ------------------------------------------------------------------ Collegio Arcano

func test_craft_category_incisione_avanza_il_primo_glifo() -> void:
	_new_game()
	var q := _quests()
	assert_true(q.accept("side_arcane_college_3"))
	for i in 5:
		EventBus.action_completed.emit("rc_glyph_fury_1", [{"item": "glyph_fury_1", "qty": 1}])
	_step(2)
	assert_true(q.is_ready("side_arcane_college_3"), "5 glifi incisi")


func test_craft_rank_conta_solo_il_rango_richiesto() -> void:
	_new_game()
	var q := _quests()
	assert_true(q.accept("side_arcane_college_6"))
	EventBus.action_completed.emit("rc_glyph_fury_4", [{"item": "glyph_fury_4", "qty": 1}])
	_step(2)
	assert_false(q.is_ready("side_arcane_college_6"), "un glifo di rango 4 non basta")
	EventBus.action_completed.emit("rc_glyph_fury_5", [{"item": "glyph_fury_5", "qty": 1}])
	_step(2)
	assert_true(q.is_ready("side_arcane_college_6"), "glifo di rango 5")


# ------------------------------------------------------------------ Commesse

func _contracts() -> ContractSystem:
	return Game.system("contracts") as ContractSystem


func _open_contracts() -> ContractSystem:
	_new_game()
	_unlock(["feature:market", "feature:combat", "feature:crates", "skill:woodcutting", "skill:mining", "skill:fishing", "skill:smithing"])
	var c := _contracts()
	assert_not_null(c)
	assert_true(c.is_open())
	c.tick(1.0)
	return c


func test_commesse_prime_emesse_all_apertura() -> void:
	var c := _open_contracts()
	assert_gt(c.contracts("daily").size(), 0, "ci sono commesse giornaliere")
	assert_lte(c.contracts("daily").size(), 3)
	assert_lte(c.contracts("weekly").size(), 5)
	for e in c.contracts("daily"):
		assert_eq(str(e.period), "daily")
		assert_gt(int(e.target), 0)
		assert_eq(int(e.progress), 0)


func test_commesse_si_accumulano_senza_penalita_e_scadono_in_silenzio() -> void:
	var c := _open_contracts()
	var day := float(DataRegistry.rules("contract_rules").day_s)
	var gold_start := GameState.gold()
	c.simulate_offline(day * 3.0 + 10.0)
	assert_gt(c.contracts("daily").size(), 3, "le giornaliere si accumulano mentre sei via")
	# dopo un mese di assenza restano al massimo quelle degli ultimi 7 giorni (slot x giorni): nessun accumulo infinito
	c.simulate_offline(day * 30.0)
	var rules := DataRegistry.rules("contract_rules")
	assert_lte(c.contracts("daily").size(), int(rules.daily_slots) * int(rules.rollover_days))
	assert_eq(GameState.gold(), gold_start, "nessuna penalità né sottrazione di risorse")


func test_commessa_completata_non_scade_e_si_riscatta() -> void:
	var c := _open_contracts()
	var day := float(DataRegistry.rules("contract_rules").day_s)
	var e: Dictionary = c.contracts("daily")[0]
	var id := str(e.id)
	# completa l'obiettivo con l'evento giusto
	var obj: Dictionary = e.obj
	var params := {"qty": int(e.target)}
	for k in obj:
		if k != "type" and k != "qty":
			params[k] = obj[k]
	if str(obj.type) == "sell_market":
		params = {"gold": int(e.target)}
	EventBus.objective_event.emit(str(obj.type), params)
	_step(2)
	assert_true(c.is_complete(id), "la commessa è completata dall'evento")
	c.simulate_offline(day * 20.0)
	assert_false(c.entry(id).is_empty(), "una commessa finita non scade finché non la riscatti")
	var gold0 := GameState.gold()
	var tok0 := c.tokens()
	assert_true(c.claim(id))
	assert_eq(c.tokens(), tok0 + int(DataRegistry.rules("contract_rules").rewards.daily.commission_token))
	assert_gt(GameState.gold(), gold0)
	assert_true(c.entry(id).is_empty())


func test_commesse_cambio_gratuito_una_volta_al_giorno() -> void:
	var c := _open_contracts()
	var first: Dictionary = c.contracts("daily")[0]
	assert_eq(c.free_rerolls_left(), 1)
	assert_true(c.reroll(str(first.id)))
	assert_eq(c.free_rerolls_left(), 0)
	var second: Dictionary = c.contracts("daily")[1]
	assert_false(c.reroll(str(second.id)), "un solo cambio gratuito al giorno")


func test_negozio_dei_gettoni() -> void:
	var c := _open_contracts()
	var bank := Game.system("bank") as BankSystem
	assert_false(c.buy("key_t1"), "senza Gettoni non si compra")
	bank.add("commission_token", 20, "test")
	assert_true(c.buy("key_t1"))
	assert_eq(bank.count("key_t1"), 1)
	assert_eq(c.tokens(), 14)


func test_commesse_stato_sopravvive_al_salvataggio() -> void:
	var c := _open_contracts()
	var n := c.contracts("daily").size()
	SaveService.save_now()
	assert_true(bool(Game.load_game(1).ok))
	assert_eq(_contracts().contracts("daily").size(), n)


# ------------------------------------------------------------------ oggetti apribili, Affinatura, migrazione

func test_nido_e_tesoro_si_aprono() -> void:
	_new_game()
	var bank := Game.system("bank") as BankSystem
	bank.add("bird_nest", 1, "test")
	var r := bank.open_item("bird_nest")
	assert_false(r.is_empty())
	assert_eq(bank.count("bird_nest"), 0, "consumato")
	assert_eq((r.items as Array).size(), 1)
	bank.add("sunken_treasure", 1, "test")
	var g0 := GameState.gold()
	var r2 := bank.open_item("sunken_treasure")
	assert_eq((r2.items as Array).size(), 2, "due estrazioni")
	assert_gte(GameState.gold() - g0, 50)
	assert_true(bank.open_item("bird_nest").is_empty(), "niente da aprire")


func test_sconto_affinatura_letto_dal_modificatore() -> void:
	_new_game()
	var cr := Game.system("crates") as CrateSystem
	var inst := {"rarity": "legendary", "polish": 0}
	var base := cr.polish_cost(inst)
	assert_gt(base, 1)
	Modifiers.set_source("test:refine", [{"key": "refine_cost_reduction_pct", "value": 30.0, "mode": "add"}])
	var cut := cr.polish_cost(inst)
	assert_lt(cut, base, "il modificatore riduce il costo")
	assert_gte(cut, int(ceil(float(base) * 0.7)) - 1)


func test_migrazione_v1_a_v2() -> void:
	assert_gte(SaveCodec.SCHEMA_VERSION, 2)
	var old := {"schema_version": 1, "relics": [], "settings_snapshot": {}, "contracts": {"daily": [], "weekly": [], "tokens": 4.0}}
	var res := SaveCodec.migrate(old)
	assert_eq(res.error, "")
	assert_eq(int(res.data.schema_version), SaveCodec.SCHEMA_VERSION)
	assert_false(res.data.has("relics"))
	assert_false(res.data.has("settings_snapshot"))
	assert_eq(int(res.data.contracts.tokens), 4)


func test_bot_completa_il_primo_obiettivo_del_capitolo_11() -> void:
	# il bot gioca come un giocatore: preme «Parla» (QuestSystem.talk), riscatta e arriva all'Era 2
	_new_game(31)
	_skip_to_epilogue()
	var bot := BotPlayer.new(Game.sim, func(dt: float) -> void: Game._on_step(dt))
	var res := bot.run_until_quest("main_c11_q1", 600.0)
	assert_true(bool(res.ok), "main_c11_q1 completata dal bot")
	assert_true(GameState.has_unlock("era:2"))
	assert_eq(_quests().current_main(), "main_c11_q2")


func test_obiettivi_con_numeri_json_float_combaciano_con_gli_eventi_int() -> void:
	# i dati JSON portano 2.0, gli eventi 2: prima main_c11_q5 (complete_raid era=2) non poteva mai avanzare
	assert_true(QuestSystem.same_value(2, 2.0))
	assert_true(QuestSystem.same_value(5, 5.0))
	assert_false(QuestSystem.same_value(5, 4.0))
	assert_true(QuestSystem.same_value("glyphs", "glyphs"))
	assert_false(QuestSystem.same_value("a", "b"))
