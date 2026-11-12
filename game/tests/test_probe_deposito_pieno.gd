extends GutTest
## Sonda breve del resoconto 117 (docs/audit_2026-10-22/117_RESOCONTO_DEPOSITO_PIENO.md): il bot (BotPlayer, la base dei bot
## QA101/QA111) completa le missioni dove il report 111 lo trovava FERMO per il Deposito pieno:
##   main_c7_q5 «apri Casse» (fermo 3 corse su 3, una per oltre 77 h): chiavi e Casse in mano, Deposito pieno di Finiture;
##   main_c4_q1 (bot AFK fermo ~540 h): Deposito pieno, Casse e chiavi che non si aprivano, niente cibo.
## Partita VERA (Game.new_game) con le missioni precedenti segnate come fatte; il Deposito e' riempito di pezzi BLOCCATI (il bot
## non puo' venderli: niente scappatoie) e Casse/chiavi finiscono nel Carro di Ritiro.

const Fx = preload("res://tests/helpers/sim_fixtures.gd")
const MAX_S := 3.0 * 3600.0

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_probe_deposito_%d" % Time.get_ticks_usec()
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


func _step(dt: float) -> void:
	Game._on_step(dt)


## Missioni principali precedenti a `stop_id` fatte (con i loro sblocchi) e `stop_id` attiva con progresso zero.
func _arrive_at(stop_id: String, hero_level: int) -> void:
	var q := Game.system("quests") as QuestSystem
	q.state.active.clear()
	q.state.progress.clear()
	for qid in q._main_ids:
		if qid == stop_id:
			break
		if not q.is_done(qid):
			q.state.done.append(qid)
		for tok in q.quest_def(qid).get("unlocks", []):
			if not (GameState.data.unlocks as Array).has(tok):
				GameState.data.unlocks.append(tok)
	q.start()
	var sk := Game.system("skills") as SkillSystem
	var guard := 0
	while sk.level("hero") < hero_level and guard < 400:
		guard += 1
		var p: Array = sk.xp_progress("hero")
		sk.add_xp("hero", maxf(1.0, float(p[1]) - float(p[0]) + 1.0), false)


## Riempie lo Spazio di PILE BLOCCATE (il bot non le vende) e verifica che il Deposito sia pieno. F15: l'equipaggiamento non
## occupa Spazio (sta nell'Armeria), quindi per riempire il Deposito servono pile.
func _fill_locked(b: BankSystem) -> void:
	for it in DataRegistry.items_by_category("material"):
		if b.is_full():
			break
		var id := str(it.id)
		if not b.state.stacks.has(id):
			b.add(id, 1, "probe")
			b.set_def_locked(id, true)
	assert_true(b.is_full(), "Deposito pieno")


func _run_bot(quest_id: String) -> Dictionary:
	var bot := BotPlayer.new(Game.sim, _step)
	var res := bot.run_until_quest(quest_id, MAX_S)
	var b := Game.system("bank") as BankSystem
	gut.p("%s: %s in %.1f min simulati · Deposito %d/%d · Carro %d pezzi · blocchi %d" % [quest_id, "COMPLETATA" if bool(res.ok) else "NON completata",
		float(res.t) / 60.0, b.used_slots(), b.capacity(), b.overflow_count(), (res.blocks as Array).size()])
	if not bool(res.ok):
		gut.p("\n".join(bot.log_lines.slice(maxi(0, bot.log_lines.size() - 25))))
	return res


func test_c7_q5_si_completa_con_il_deposito_pieno() -> void:
	assert_true(Game.new_game(1, "normal", 117075))
	_arrive_at("main_c7_q5", 40)
	var b := Game.system("bank") as BankSystem
	b.add_gold(200000)
	_fill_locked(b)
	b.add("crate_millbrook", 30, "probe")
	b.add("key_t1", 30, "probe")
	assert_gt(b.overflow_stacks_count(), 0, "Casse e chiavi aspettano nel Carro di Ritiro")
	var res := _run_bot("main_c7_q5")
	assert_true(bool(res.ok), "main_c7_q5 completata con il Deposito pieno")
	assert_eq(res.blocks, [], "nessun blocco del bot")
	assert_lt(float(res.t), 3600.0, "in meno di un'ora simulata (prima: oltre 77 h)")
	assert_lt(b.count("crate_millbrook"), 30, "le Casse sono state aperte")
	assert_gt(int(Game.system("crates").state.opened), 9, "almeno 10 Casse aperte a Deposito pieno")


func test_c7_q5_chiavi_comprate_all_emporio_a_deposito_pieno() -> void:
	# la variante del report 111: nessuna chiave in mano, Deposito pieno, le chiavi si comprano all'Emporio
	assert_true(Game.new_game(1, "normal", 117076))
	_arrive_at("main_c7_q5", 40)
	var b := Game.system("bank") as BankSystem
	b.add_gold(200000)
	_fill_locked(b)
	b.add("crate_millbrook", 12, "probe")
	var res := _run_bot("main_c7_q5")
	assert_true(bool(res.ok), "main_c7_q5 completata comprando le chiavi con il Deposito pieno")
	assert_eq(res.blocks, [])


func test_c4_q1_si_completa_con_il_deposito_pieno_e_senza_cibo() -> void:
	assert_true(Game.new_game(1, "normal", 117041))
	_arrive_at("main_c4_q1", 28)
	var b := Game.system("bank") as BankSystem
	b.add_gold(50000)
	# equipaggiamento adatto al tier: il bot lo indossa da solo (_equip_best), poi il Deposito si riempie di pezzi bloccati
	for gid in Fx.gear_ids("warrior", 3):
		b.add_instance({"def": str(gid), "quality": "normal", "sockets": [], "rank": 0})
	_fill_locked(b)
	b.add("crate_millbrook", 40, "probe")           # Casse e chiavi che non si potevano aprire
	b.add("key_t1", 40, "probe")
	var res := _run_bot("main_c4_q1")
	assert_true(bool(res.ok), "main_c4_q1 completata con il Deposito pieno")
	assert_gt(b.overflow_count(), 0, "cio' che il bot produce o trova a Deposito pieno aspetta nel Carro (nulla perso)")
	assert_eq(res.blocks, [], "nessun blocco del bot")
