extends GutTest
## Colla tra i sistemi VERI (Game.new_game, tutti i sistemi di SystemRegistry): i punti che i test dei singoli
## sistemi provavano solo con sistemi finti (resoconti 20-25, docs/audit_2026-10-22/29_RESOCONTO_INTEGRAZIONE.md).

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_integration_saves"
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 4242))


func after_each() -> void:
	Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _grant(tokens: Array) -> void:
	for t in tokens:
		(Game.system("unlock") as UnlockSystem).grant(str(t))


func _ticks(seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		Game._on_step(0.1)


func test_regalo_di_nuova_partita_dai_dati() -> void:
	var gift: Dictionary = DataRegistry.constants.get("new_game_gift", {})
	assert_false(gift.is_empty(), "constants.new_game_gift esiste (inizio dolce)")
	assert_eq(_bank().gold(), int(gift.gold))
	for e in gift.items:
		assert_eq(_bank().count(str(e.item)), int(e.qty))


func test_una_sola_attivita_tra_mansioni_e_combattimento() -> void:
	_grant(["feature:combat", "zone:millbrook"])
	var sk := Game.system("skills") as SkillSystem
	var cb := Game.system("combat") as CombatSystem
	assert_true(sk.start("wc_pine"))
	assert_true(cb.start("millbrook", "mud_slime"))
	assert_eq(sk.current_action(), "", "il combattimento sostituisce la mansione (stesso Dictionary activity)")
	var logs := _bank().count("log_pine")
	_ticks(30.0)
	assert_eq(_bank().count("log_pine"), logs, "la mansione sostituita non produce più")
	assert_true(sk.start("wc_pine"))
	assert_false(cb.in_combat(), "e viceversa")


func test_forgiachiavi_produce_la_chiave_che_apre_la_cassa() -> void:
	_grant(["skill:keysmithing", "feature:crates"])
	var a: Dictionary = DataRegistry.action("key_key_t1")
	for io in a.inputs:
		_bank().add(str(io.item), int(io.qty))
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start("key_key_t1"), "Forgiachiavi avviabile con gli ingredienti")
	_ticks(float(a.time_s) + 0.2)
	assert_eq(_bank().count("key_t1"), 1, "la chiave forgiata entra nel Deposito")
	var cr := Game.system("crates") as CrateSystem
	cr.grant_crate("crate_millbrook", 1)
	assert_eq(cr.openable("crate_millbrook"), 1)
	var res := cr.open("crate_millbrook", 1, false)
	assert_eq(res.size(), 1)
	assert_eq(_bank().count("key_t1"), 0, "chiave consumata")
	var inst := _bank().get_instance(str(res[0].uid))
	assert_false(inst.is_empty(), "l'oggetto della cassa è un'istanza VERA del Deposito")
	assert_eq(str(inst.def), str(res[0].def_id))
	assert_true(inst.has("rarity") and inst.has("condition"), "il Deposito conserva i campi della Cassa")


func test_finitura_nel_guardaroba_non_si_vende() -> void:
	_grant(["feature:crates", "feature:market"])
	var cr := Game.system("crates") as CrateSystem
	_bank().add("key_t1", 1)
	cr.grant_crate("crate_millbrook", 1)
	var r: Dictionary = cr.open("crate_millbrook", 1, false)[0]
	# il seme e' fisso ma l'esito di una cassa e' una finitura solo con una certa probabilita': si aprono casse finche' ne esce una
	var guard := 0
	while str(r.kind) != "skin" and guard < 200:
		guard += 1
		_bank().add("key_t1", 1)
		cr.grant_crate("crate_millbrook", 1)
		r = cr.open("crate_millbrook", 1, false)[0]
	assert_eq(str(r.kind), "skin", "entro 200 casse esce una finitura da provare nel Guardaroba")
	if str(r.kind) != "skin":
		return
	assert_true(cr.equip(str(r.uid)))
	assert_true(_bank().is_in_use(str(r.uid)))
	assert_eq(_bank().sellable_count(str(r.def_id)), 0, "le finiture indossate non sono vendibili")


func test_attrezzo_equipaggiato_da_il_bonus_alla_mansione() -> void:
	_grant(["feature:combat"])
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("woodcutting", 5000.0)           # livello ≥ 10 (requisito dell'ascia di bronzo)
	var uid := _bank().add_instance({"def": "axe_bronze"})
	var before := Modifiers.total_add("skill_haste_pct", ["woodcutting"])
	assert_true((Game.system("combat") as CombatSystem).equip(uid), "equip() di un attrezzo passa a equip_tool")
	assert_eq(str(GameState.data.equipment.tools.woodcutting), uid)
	assert_gt(Modifiers.total_add("skill_haste_pct", ["woodcutting"]), before, "bonus registrato da refresh_tools()")
	assert_true(_bank().is_in_use(uid), "attrezzo in uso: non vendibile")


func test_mercato_non_vende_l_equipaggiamento_indossato_e_conta_per_le_missioni() -> void:
	_grant(["feature:combat", "feature:market"])
	var uid := _bank().add_instance({"def": "sword_copper"})
	assert_true((Game.system("combat") as CombatSystem).equip(uid))
	var mk := Game.system("market") as MarketSystem
	assert_eq(mk.sell("sword_copper", 1), 0, "la spada indossata non si vende")
	assert_false(_bank().get_instance(uid).is_empty())
	watch_signals(EventBus)
	_bank().add("log_pine", 50)
	var gold := mk.sell("log_pine", 50)
	assert_gt(gold, 0)
	assert_signal_emitted_with_parameters(EventBus, "objective_event", ["sell_market", {"gold": gold}])


func test_spazi_del_deposito_comprati_all_emporio() -> void:
	_grant(["feature:market"])
	var mk := Game.system("market") as MarketSystem
	var cap := _bank().capacity()
	_bank().add_gold(10000)
	assert_true(mk.buy("bank_slot", 2))
	assert_eq(_bank().capacity(), cap + 2, "modificatore bank_slots del Mercato letto da capacity()")


func test_istanza_forgiata_emette_item_gained_e_conta_per_craft() -> void:
	_grant(["skill:smithing"])
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("smithing", 500.0)
	_bank().add("bar_copper", 2)
	watch_signals(EventBus)
	assert_true(sk.start("smith_sword_copper"))
	_ticks(3.2)
	assert_signal_emitted(EventBus, "item_gained", "il Deposito annuncia l'istanza forgiata")
	assert_eq(_bank().count("sword_copper"), 1)


func test_tomo_dell_esperienza_si_usa() -> void:
	_grant(["skill:hero"])
	var sk := Game.system("skills") as SkillSystem
	_bank().add("tome_xp_small", 1)
	var xp0 := sk.xp("hero")
	var expect := sk.tome_xp("tome_xp_small", "hero")
	assert_gt(expect, 0.0)
	assert_true(sk.use_tome("tome_xp_small", "hero"))
	assert_almost_eq(sk.xp("hero") - xp0, expect, 1e-6)
	assert_eq(_bank().count("tome_xp_small"), 0)
	assert_false(sk.use_tome("tome_xp_small", "hero"), "niente tomo, niente XP")


func test_riscatto_missione_con_il_deposito_vero() -> void:
	var q := Game.system("quests") as QuestSystem
	var qid := q.current_main()
	var obj: Dictionary = q.quest_def(qid).objectives[0]
	EventBus.action_completed.emit("wc_pine", [{"item": "log_pine", "qty": QuestSystem.target_of(obj)}])
	_ticks(0.2)
	var gold0 := _bank().gold()
	assert_true(q.claim(qid))
	assert_eq(_bank().gold(), gold0 + int(q.quest_def(qid).rewards.gold), "oro della ricompensa nel Deposito")


func test_a_partita_chiusa_i_sistemi_non_ascoltano() -> void:
	Game.stop_game(false)
	EventBus.crate_found.emit("crate_millbrook", "test")      # nessun errore, nessun Deposito toccato
	assert_false((Game.system("crates") as CrateSystem).enabled)
	assert_true(Game.new_game(1, "normal", 1))
	assert_true((Game.system("crates") as CrateSystem).enabled)
