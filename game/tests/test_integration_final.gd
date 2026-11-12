extends GutTest
## Integrazione finale (resoconto 47): eventi che prima non avevano una fonte (incarichi di fazione, imprese),
## Prove del Custode (Cassa dell'Era, Essenza d'Era, «Contro il Tempo» offline), sui sistemi VERI.

const _GS := preload("res://src/autoload/GameState.gd")
const MIL := "crate_millbrook"

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_integration_final_%d" % Time.get_ticks_usec()
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


func _new_game(seed_value: int = 11) -> void:
	assert_true(Game.new_game(1, "normal", seed_value))


func _unlock(tokens: Array) -> void:
	for t in tokens:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)


func _step(n: int = 1) -> void:
	for i in n:
		Game._on_step(0.1)


## Finitura nel Deposito con float a metà intervallo (stessa forma delle istanze create da CrateSystem).
func _give_skin(def_id: String) -> String:
	var cr := Game.system("crates") as CrateSystem
	var d := DataRegistry.item(def_id)
	var f := (float(d.skin.float_min) + float(d.skin.float_max)) * 0.5
	var inst := {"def_id": def_id, "kind": "skin", "rarity": d.rarity, "crate": "crate_" + str(d.crate),
		"condition": cr.condition_for_float(f), "float": f, "annalist": false, "seed": 1, "phase": "", "polish": 0, "locked": false}
	return (Game.system("bank") as BankSystem).add_instance(inst)


# ------------------------------------------------------------------ incarichi di fazione con la fonte vera

func test_contratto_e_affinatura_veri_avanzano_gli_incarichi_della_mano_grigia() -> void:
	_new_game()
	_unlock(["feature:factions", "feature:tradeup", "feature:refinery"])
	var qs := Game.system("quests") as QuestSystem
	var cr := Game.system("crates") as CrateSystem
	var comp := Game.system("compendium") as CompendiumSystem
	qs.state.done.append("side_grey_hand_2")
	assert_eq(qs.faction_quest_status("side_grey_hand_3"), "available", "la fonte esiste: niente più «In arrivo»")
	assert_true(qs.accept_faction_quest("side_grey_hand_3"))
	var rares: Array = cr.contents(MIL)["rare"]
	for k in 5:
		var uids: Array = []
		for i in 10:
			uids.append(_give_skin(str(rares[i % rares.size()])))
		assert_false(cr.contract_sign(uids).is_empty(), "contratto %d firmato" % k)
	_step(3)
	assert_eq(qs.faction_quest_status("side_grey_hand_3"), "ready", "5 Contratti di Scambio veri")
	assert_eq(comp.counter("tradeup"), 5, "il Compendio conta i Contratti")
	assert_true(qs.claim("side_grey_hand_3"))
	assert_true(qs.accept_faction_quest("side_grey_hand_4"))
	(Game.system("bank") as BankSystem).add_currency("vault_shard", 100000)
	var epic := _give_skin(str(cr.contents(MIL)["epic"][0]))
	for i in 10:
		assert_true(cr.polish(epic), "lucidatura %d" % i)
	_step(3)
	assert_eq(qs.faction_quest_status("side_grey_hand_4"), "ready", "10 lucidature vere")
	assert_eq(comp.counter("refine_polish"), 10)


func test_incursione_completata_avanza_l_ordine_dei_custodi() -> void:
	_new_game()
	_unlock(["feature:factions"])
	var qs := Game.system("quests") as QuestSystem
	qs.state.done.append("side_order_of_wardens_4")
	assert_eq(qs.faction_quest_status("side_order_of_wardens_5"), "available")
	assert_true(qs.accept_faction_quest("side_order_of_wardens_5"))
	for i in 3:          # stessa forma dell'evento emesso da EndgameCombat a fine incursione (test_raids)
		EventBus.objective_event.emit("complete_raid", {"raid": "collectors_den", "qty": 1, "era": 1})
	_step(3)
	assert_eq(qs.faction_quest_status("side_order_of_wardens_5"), "ready")
	assert_eq((Game.system("compendium") as CompendiumSystem).counter("raid:collectors_den"), 3)


# ------------------------------------------------------------------ imprese che prima restavano a 0

func test_piatti_bruciati_veri_contano_per_l_impresa() -> void:
	_new_game()
	_unlock(["skill:cooking"])
	var sk := Game.system("skills") as SkillSystem
	var bank := Game.system("bank") as BankSystem
	var comp := Game.system("compendium") as CompendiumSystem
	bank.add("fish_raw_bleak", 400, "test")
	assert_true(sk.start("cook_bleak"))
	_step(6000)
	var burnt := bank.count("burnt_food")
	assert_gt(burnt, 0, "a livello 1 qualcosa brucia")
	assert_eq(comp.counter("burnt"), burnt, "ogni piatto bruciato conta (anche quelli già nel Deposito)")
	# offline analitico: un solo evento con la quantità
	var before := comp.counter("burnt")
	Game._on_long_gap(1800.0)
	assert_eq(comp.counter("burnt") - before, bank.count("burnt_food") - burnt, "anche offline")


func test_capolavoro_classi_sfida_e_prove_alimentano_le_imprese() -> void:
	_new_game()
	var comp := Game.system("compendium") as CompendiumSystem
	# Capolavoro: lo emette SkillSystem quando un pezzo esce di qualità (qui l'evento con la stessa forma)
	EventBus.objective_event.emit("craft_quality", {"quality": "masterwork", "qty": 1})
	assert_eq(comp.counter("quality:masterwork"), 1)
	assert_eq(comp._current_of({"type": "craft_quality", "quality": "masterwork", "qty": 1}), 1)
	# classi: dalle missioni di classe completate (vale anche per i salvataggi vecchi)
	var qs := Game.system("quests") as QuestSystem
	for q in ["class_paladin", "class_berserker", "class_spellblade"]:
		qs.state.done.append(q)
	assert_eq(comp._current_of({"type": "classes_unlocked", "qty": 9}), 3)
	# Sfida dei Collezionisti: le vittorie sono nello stato delle Casse
	(Game.system("crates") as CrateSystem)._challenge_state().wins = 4
	assert_eq(comp._current_of({"type": "collectors_challenge_wins", "qty": 5}), 4)
	# Prove: tutte al massimo
	var ps := Game.system("prestige") as PrestigeSystem
	assert_eq(comp._current_of({"type": "challenge_all_max", "qty": 1}), 0)
	for tid in ps.trial_ids():
		ps.state.trials[tid] = ps.trial_tier_count(tid)
	assert_eq(comp._current_of({"type": "challenge_all_max", "qty": 1}), 1)


func test_qualita_vera_da_skill_system_emette_l_evento() -> void:
	_new_game()
	var got: Array = []
	var on_obj := func(k: String, p: Dictionary) -> void:
		if k == "craft_quality":
			got.append(p)
	EventBus.objective_event.connect(on_obj)
	var sk := Game.system("skills") as SkillSystem
	sk._bank_give("sword_copper", 2, "masterwork", "test")
	sk._bank_give("sword_copper", 1, "normal", "test")
	EventBus.objective_event.disconnect(on_obj)
	assert_eq(got, [{"quality": "masterwork", "qty": 2}], "un evento per blocco, solo per le qualità superiori")


# ------------------------------------------------------------------ Prove: Cassa dell'Era, Essenza, offline

func _world() -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var bus: Node = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	autofree(bus)
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(5), bus)
	var sim := Simulation.new()
	var ps := PrestigeSystem.new()
	var cr := CrateSystem.new()
	sim.setup(ctx, [BankSystem.new(), SkillSystem.new(), UnlockSystem.new(), cr, ps])
	sim.bind_state(state)
	state.quests.done.append("main_c5_q5")
	for g in DataRegistry.constants.prestige.goals:
		state.prestige.goals[str(g.id)] = true
	return {"sim": sim, "state": state, "ps": ps, "cr": cr, "bus": bus, "bank": sim.get_system("bank")}


func test_custode_consegna_la_cassa_dell_era_con_probabilita_visibili() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var bank: BankSystem = w.bank
	var cr: CrateSystem = w.cr
	assert_eq(ps.era_crate_id(1), "crate_era_2", "la caduta nell'Era I dà la Cassa della nuova Era II")
	assert_eq(ps.era_crate_id(5), "crate_era_5")
	assert_eq(ps.era_crate_id(40), "crate_era_12", "oltre l'ultima generata si usa la più alta")
	ps.on_warden_defeated(1)
	assert_eq(bank.count("crate_era_2"), 1, "consegnata nel Deposito con CrateSystem.grant_crate")
	ps.on_warden_defeated(2)
	assert_eq(bank.count("crate_era_2"), 2, "una per ogni caduta (anche le ripetute, che non pagano Polvere)")
	# probabilità: le stesse di ogni cassa, somma 100, mostrate dalla schermata (odds del dato)
	var odds: Dictionary = cr.crate_def("crate_era_2").odds
	var tot := 0.0
	for k in odds:
		tot += float(odds[k])
	assert_almost_eq(tot, 100.0, 1e-6)
	assert_eq(odds, cr.crate_def("crate_rift").odds)
	assert_eq(cr.crate_def("crate_era_2").key, null, "premio del Custode: si apre senza chiave, mai con denaro (E47-1)")
	assert_eq(cr.openable("crate_era_2"), 2)
	# l'esito si estrae prima dell'animazione come per ogni cassa
	var res := cr.open("crate_era_2", 1, false)
	assert_eq(res.size(), 1)
	assert_false(str(res[0].get("def_id", "")).is_empty())
	# bonus dell'Era: Schegge della fusione × (1 + 0,25·(N−1))
	if not str(res[0].get("uid", "")).is_empty():
		var base := int(DataRegistry.rules("crate_rules").dismantle_shards.get(str(res[0].rarity), 0))
		assert_eq(cr.fuse_value(str(res[0].uid)), maxi(1, roundi(base * 1.25)))
	# durante una Prova il Custode non consegna nulla (on_warden_defeated la ignora)
	ps.start_trial("trial_silence", 1)
	ps.on_warden_defeated(1)
	assert_eq(bank.count("crate_era_2"), 1)


func test_prova_a_tempo_annullata_offline_con_riga_nel_bentornato() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_race", 1)
	assert_true(ps.is_trial_active())
	var rep: Dictionary = ps.simulate_offline(120.0)
	assert_false(ps.is_trial_active(), "annullata, non sospesa")
	assert_eq(ps.era_current(), 1, "l'Era torna com'era")
	assert_eq(str(rep.rows[0].key), "UI_TRIALS_WB_CANCELLED", "messaggio chiaro nel Bentornato")
	var wb := WelcomeBack.build(120.0, {"prestige": rep}, DataRegistry, 86400.0)
	assert_false(bool(wb.empty), "la riga compare nel Bentornato")
	# una Prova senza tempo resta in corso e il bersaglio battuto offline vale la vittoria
	ps.start_trial("trial_silence", 1)
	assert_true(ps.simulate_offline(3600.0).is_empty())
	assert_true(ps.is_trial_active())
	var tgt := ps.trial_target("trial_silence", 1)
	w.bus.monsters_killed_batch.emit(str(tgt.id), 3, [])
	assert_false(ps.is_trial_active(), "vinta offline")
	assert_eq(ps.trial_tiers_done("trial_silence"), 1)


func test_prova_a_tempo_non_si_vince_con_le_uccisioni_offline() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_race", 1)
	var tgt := ps.trial_target("trial_race", 1)
	w.bus.monsters_killed_batch.emit(str(tgt.id), 1, [])
	assert_eq(ps.trial_tiers_done("trial_race"), 0)


func test_essenza_d_era_di_elite_boss_e_dungeon_senza_doppioni() -> void:
	_new_game()
	var cb := Game.system("combat") as CombatSystem
	var elite := {}
	var boss := {}
	var dboss := {}
	var normal := {}
	for m in DataRegistry.table("monsters"):
		match str(m.get("type", "")):
			"elite": elite = m
			"boss": boss = m
			"dungeon_boss": dboss = m
			"normal": normal = m
	assert_eq(cb.era_essence_drop(boss, ""), 0, "senza le Ere sbloccate niente Essenza")
	_unlock(["feature:eras"])
	GameState.data.prestige.era_max = 4
	GameState.data.prestige.era_current = 3
	assert_eq(cb.era_essence_drop(boss, ""), 3, "boss di zona: 1 porzione × Era")
	assert_eq(cb.era_essence_drop(dboss, "dungeon"), 9, "boss di dungeon: 3 porzioni × Era")
	assert_eq(cb.era_essence_drop(normal, ""), 0)
	assert_eq(cb.era_essence_drop(dboss, "raid"), 0, "le incursioni la danno a fine incursione (EndgameCombat)")
	assert_eq(cb.era_essence_drop(dboss, "rift"), 0, "la Breccia la dà ai Guardiani")
	var n := 0
	for i in 2000:
		n += cb.era_essence_drop(elite, "")
	assert_between(float(n) / 2000.0, 0.25 * 3 * 0.85, 0.25 * 3 * 1.15, "élite: 25% × Era")
	# uccisione vera di un boss di zona: l'Essenza arriva nel Deposito
	var bank := Game.system("bank") as BankSystem
	var before := bank.count("era_essence")
	cb._kill({"mode": "zone", "enemy": {}}, boss)
	assert_eq(bank.count("era_essence") - before, 3)
