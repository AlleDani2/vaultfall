extends GutTest
## FIX-MEDIO (QA2, docs/audit_2026-10-22/qa/52_QA2_gioco_medio.md; resoconto 80): Cuore del Caveau sbloccabile (B1),
## rune per l'Arcanista prima del Cap. III (B5), zone non richiuse dalla Stella dell'Eroe, Taverna senza coloni,
## ricompense di missione mai perse col Deposito pieno. Sistemi VERI (Game.new_game).

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_fix_medio_%d" % Time.get_ticks_usec()
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


func _quests() -> QuestSystem:
	return Game.system("quests") as QuestSystem


func _bank() -> Variant:
	return Game.system("bank")


func _unlock(tokens: Array) -> void:
	for t in tokens:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)


## Segna come fatte tutte le missioni principali prima di `stop_id` e rende attiva `stop_id` con gli obiettivi completi.
func _ready_at(stop_id: String) -> void:
	var q := _quests()
	q.state.active.clear()
	q.state.progress.clear()
	for qid in q._main_ids:
		if qid == stop_id:
			break
		if not q.is_done(qid):
			q.state.done.append(qid)
	q.start()
	var objs: Array = q.quest_def(stop_id).get("objectives", [])
	var pr: Array = []
	for o in objs:
		pr.append(QuestSystem.target_of(o))
	q.state.progress[stop_id] = pr


func test_cuore_del_caveau_sbloccato_dal_collezionista() -> void:
	assert_true(Game.new_game(1, "normal", 11))
	var q := _quests()
	assert_true((q.quest_def("main_c10_q5").get("unlocks", []) as Array).has("raid:heart_of_the_vault"),
		"B1: Il Collezionista concede l'incursione finale")
	var raid: Dictionary = DataRegistry.get_def("raids", "heart_of_the_vault")
	assert_eq(str(raid.get("unlock", {}).get("quest", "")), "main_c10_q5", "raids.json allineato")


func test_sacchetto_di_rune_per_l_arcanista() -> void:
	assert_true(Game.new_game(1, "normal", 12))
	var bank: Variant = _bank()
	bank.add_gold(100)
	var mk: Variant = Game.system("market")
	assert_true(mk.buy("buy_rune_pouch", 1), "il Sacchetto si compra all'Emporio")
	var before := int(bank.count("rune_t1"))
	assert_false(bank.open_item("rune_pouch").is_empty())
	assert_eq(int(bank.count("rune_t1")) - before, 250, "contenuto fisso: 250 Rune di Pietra")
	assert_false(bool(DataRegistry.item("rune_pouch").get("tradeable", true)), "non si rivende")


func test_stella_dell_eroe_non_richiude_le_zone() -> void:
	assert_true(Game.new_game(1, "normal", 13))
	var cb := Game.system("combat") as CombatSystem
	var z := cb.zone_def("frostspire")
	var need := int(z.get("unlock", {}).get("hero_level", 1))
	assert_gt(need, 1)
	_unlock(["zone:frostspire"])
	assert_false(cb.zone_unlocked("frostspire"), "Eroe a livello 1 senza record: chiusa")
	GameState.data.skills["hero"]["record_level"] = need
	assert_true(cb.zone_unlocked("frostspire"), "il record dell'Eroe (dopo una Stella) tiene aperta la zona")


func test_taverna_e_accademia_non_usano_coloni() -> void:
	assert_true(Game.new_game(1, "normal", 14))
	var es: Variant = Game.system("estate")
	for b in ["tavern", "academy"]:
		var d: Dictionary = es._b_defs[b]
		assert_false(bool(d.get("uses_settlers", true)), b + " senza coloni (c5_q6 non dipende dai coloni liberi)")
	assert_true(bool(es._b_defs["sawmill"].get("uses_settlers", false)), "i produttori usano ancora i coloni")


func test_ricompensa_non_persa_col_deposito_pieno() -> void:
	assert_true(Game.new_game(1, "normal", 15))
	var q := _quests()
	var bank: Variant = _bank()
	_ready_at("main_c9_q4")
	assert_true(q.is_ready("main_c9_q4"))
	# riempi il Deposito con oggetti non impilabili
	var fillers: Array = []                  # F15: lo Spazio si riempie con pile (l'equipaggiamento sta nell'Armeria)
	for it in DataRegistry.items_by_category("material"):
		if int(bank.free_slots()) <= 0:
			break
		if not bank.state.stacks.has(str(it.id)):
			bank.add(str(it.id), 1)
			fillers.append(str(it.id))
	assert_eq(int(bank.free_slots()), 0)
	# resoconto 117: il Deposito pieno non blocca la missione, la Chiave Celeste aspetta nel Carro di Ritiro e si scarica da sola
	assert_true(q.claim("main_c9_q4"), "Deposito pieno: la missione si riscatta lo stesso")
	assert_eq(int(bank.count("celestial_key")), 1, "la Chiave Celeste c'e' (nel Carro)")
	assert_eq(int(bank.overflow_count()), 1, "aspetta nel Carro di Ritiro")
	assert_false(bank.state.stacks.has("celestial_key"))
	bank.remove(str(fillers[0]), 1)
	bank.tick(0.1)
	assert_eq(int(bank.overflow_count()), 0, "con un posto libero il Carro si scarica")
	assert_true(bank.state.stacks.has("celestial_key"), "la Chiave Celeste arriva nel Deposito")


func test_livello_totale_conta_i_record_dopo_un_rito() -> void:
	assert_true(Game.new_game(1, "normal", 16))
	var q := _quests()
	var obj := {"type": "reach_total_level", "level": 10}
	var wc: Dictionary = GameState.data.skills["woodcutting"]
	wc["level"] = 1
	wc["record_level"] = 1
	var before := q._state_value(obj)
	wc["record_level"] = 50
	assert_eq(q._state_value(obj), before + 49, "il record (50) conta anche se il Rito ha riportato la mansione a 1")
