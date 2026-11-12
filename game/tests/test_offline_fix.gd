extends GutTest
## QA81 (docs/audit_2026-10-22/qa/81_BOT_TYCOON_AFK.md): correzioni OFFLINE/TENUTA.
##   M1 Dispensa automatica · M3 Carro di Ritiro (Deposito pieno) · M5 mansione di riserva · M4 soglia minima, riferimento
##   di tempo non valido, Bentornato col tempo non contato. Sistemi VERI (Game.new_game) e banco di prova della Tenuta.

var _old_dir: String
var _old_auto: bool
var _last_report: Dictionary = {}


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_offline_fix_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	if EventBus.offline_progress.is_connected(_on_offline):
		EventBus.offline_progress.disconnect(_on_offline)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _on_offline(_s: float, r: Dictionary) -> void:
	_last_report = r


func _open_game(seed_value: int = 81) -> void:
	assert_true(Game.new_game(1, "normal", seed_value))
	for t in ["feature:market", "feature:combat", "skill:woodcutting", "skill:mining"]:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)
	_last_report = {}
	if not EventBus.offline_progress.is_connected(_on_offline):
		EventBus.offline_progress.connect(_on_offline)


func _fill_bank(b: BankSystem) -> String:
	var gear := ""
	for it in DataRegistry.items_by_category("skin"):
		gear = str(it.id)
		break
	var i := 0
	while not b.is_full() and i < 20000:
		b.add_instance({"def": gear, "quality": "normal", "sockets": [], "rank": 0})
		i += 1
	return gear


# ------------------------------------------------------------------ M4: LoadoutSystem senza tick

func test_loadout_non_fa_tick_a_vuoto() -> void:
	_open_game()
	var lo := Game.system("loadouts")
	assert_false(lo.has_tick(), "i set di equipaggiamento sono solo comandi: nessun tick offline")


# ------------------------------------------------------------------ M3: Carro di Ritiro

func test_deposito_pieno_la_produzione_prosegue_e_nulla_si_perde() -> void:
	_open_game()
	var sk := Game.system("skills") as SkillSystem
	var b := Game.system("bank") as BankSystem
	assert_true(sk.start("wc_pine"))
	_fill_bank(b)
	assert_eq(b.free_slots(), 0)
	var xp0 := sk.xp("woodcutting")
	Game.apply_absence(13.0 * 3600.0)
	assert_gt(sk.xp("woodcutting") - xp0, 50000.0, "il Deposito pieno non ferma la produzione offline")
	assert_gt(b.overflow_count(), 0, "i tronchi aspettano nel Carro di Ritiro")
	assert_gt(b.overflow_stacks_count(), 0)
	var sec: Dictionary = (_last_report.get("skills", {}) as Dictionary)
	assert_ne(str(sec.get("stopped", "")), "bank_full", "niente più «Deposito pieno» come perdita")
	var wb := WelcomeBack.build(13.0 * 3600.0, _last_report, DataRegistry, Game.offline_cap_s())
	var txt := ""
	for s in wb.sections:
		txt += "\n".join(s.lines)
	assert_true(txt.contains(NumberFormat.fmt(float(b.overflow_count()))), "il Bentornato dice quanti oggetti aspettano")
	# fatto spazio, il Carro si scarica da solo (nessuna perdita)
	var waiting := b.overflow_count()
	var pine0 := int(b.state.stacks.get("log_pine", 0))
	var inst: Array = b.list_instances()
	for i in 3:
		b.remove_instance(str(inst[i].uid))
	b.tick(0.1)
	assert_gt(int(b.state.stacks.get("log_pine", 0)), pine0, "scaricato nel Deposito")
	assert_lt(b.overflow_count(), waiting)


func test_carro_oltre_il_tetto_vende_e_lo_dice() -> void:
	_open_game()
	var b := Game.system("bank") as BankSystem
	var k: Dictionary = Formulas.k().offline
	var old_cap: Variant = k.overflow_max_instances
	k["overflow_max_instances"] = 2
	var gear := _fill_bank(b)
	Game.sim.offline_running = true
	var gold0 := b.gold()
	for i in 5:
		assert_eq(b.add_instance({"def": gear, "quality": "normal", "sockets": [], "rank": 0}), BankSystem.OVERFLOW_UID)
	Game.sim.offline_running = false
	k["overflow_max_instances"] = old_cap
	assert_eq(b.overflow_instance_count(), 2, "il Carro tiene fino al tetto dei dati")
	assert_gt(b.gold(), gold0, "oltre il tetto il pezzo si vende al prezzo del Mercato")
	var fin := b.finish_offline()
	var rows: Array = fin.get("rows", [])
	assert_eq(rows.size(), 2, "il Bentornato dice sia l'attesa sia la vendita")


func test_online_il_deposito_pieno_usa_il_carro() -> void:
	# resoconto 117: il Carro vale per tutte le fonti, anche con il giocatore presente
	_open_game()
	var b := Game.system("bank") as BankSystem
	var gear := _fill_bank(b)
	assert_eq(b.add_instance({"def": gear}), BankSystem.OVERFLOW_UID, "online il pezzo aspetta nel Carro")
	assert_eq(b.overflow_count(), 1)


func test_carro_sopravvive_al_salvataggio_e_vecchi_salvataggi_si_aprono() -> void:
	_open_game()
	var b := Game.system("bank") as BankSystem
	var gear := _fill_bank(b)
	Game.sim.offline_running = true
	b.add("log_pine", 7, "test")
	b.add_instance({"def": gear})
	Game.sim.offline_running = false
	assert_eq(b.overflow_count(), 8)
	var snap := Game.snapshot(true).duplicate(true)
	var json := JSON.stringify(snap)
	var back: Dictionary = JSON.parse_string(json)
	(back.bank as Dictionary).erase("overflow_stacks")           # salvataggio precedente a QA81
	(back.bank as Dictionary).erase("overflow_instances")
	back.erase("offline_carry_s")
	GameState.replace(back)
	Game.sim.bind_state(GameState.data)
	var b2 := Game.system("bank") as BankSystem
	assert_eq(b2.overflow_count(), 0)
	assert_true(GameState.data.has("offline_carry_s"))


func test_scarico_deterministico() -> void:
	var a := _carro_run()
	var b := _carro_run()
	assert_eq(a, b, "stesso seme, stesso Carro")


func _carro_run() -> Dictionary:
	if GameState.active:
		Game.stop_game(false)
	_open_game(777)
	var sk := Game.system("skills") as SkillSystem
	var bank := Game.system("bank") as BankSystem
	sk.start("wc_pine")
	_fill_bank(bank)
	Game.apply_absence(5.0 * 3600.0)
	return {"stacks": bank.state.overflow_stacks.duplicate(), "xp": sk.xp("woodcutting")}


# ------------------------------------------------------------------ M1: Dispensa automatica

func test_dispensa_vuota_si_rifornisce_dal_deposito() -> void:
	var f := EstateFixtures.make(5)
	f.set_levels({"cottage": 3, "sawmill": 2}, 8, 0.0)
	f.bank.add("food_bleak", 500, "test")
	f.estate.simulate_offline(2.0 * 3600.0)
	var tuning := EstateSystem.tuning()
	var want := 8.0 * float(tuning.pantry_auto_target_h)
	assert_gt(f.estate.pantry(), want * 0.7, "ha preso 24 h di razioni (i coloni in più ne consumano)")
	assert_eq(f.bank.count("food_bleak"), 500 - int(want), "le razioni escono dal Deposito")
	assert_eq(f.estate.food_factor(), 1.0, "mai a digiuno")


func test_dispensa_automatica_rispetta_blocco_e_interruttore() -> void:
	var f := EstateFixtures.make(5)
	f.set_levels({"cottage": 3, "sawmill": 2}, 8, 0.0)
	f.bank.add("food_bleak", 500, "test")
	f.bank.set_def_locked("food_bleak", true)
	f.estate.simulate_offline(3600.0)
	assert_eq(f.bank.count("food_bleak"), 500, "il cibo bloccato non si tocca")
	assert_eq(f.estate.pantry(), 0.0)
	f.bank.set_def_locked("food_bleak", false)
	f.estate.set_pantry_auto(false)
	f.estate.simulate_offline(3600.0)
	assert_eq(f.bank.count("food_bleak"), 500, "interruttore spento: nessun prelievo")
	assert_eq(f.estate.food_factor(), float(DataRegistry.rules("estate_rules").settlers.starving_mult))


func test_dispensa_senza_cibo_degrada_dolcemente_e_il_bentornato_lo_dice() -> void:
	var f := EstateFixtures.make(5)
	f.set_levels({"cottage": 3, "sawmill": 2}, 8, 0.0)
	var rep := f.estate.simulate_offline(3600.0)
	var mult := float(DataRegistry.rules("estate_rules").settlers.starving_mult)
	assert_gt(mult, 0.5, "più dolce del vecchio dimezzamento")
	assert_true(rep.has("stop"))
	assert_eq(int(rep.stop.params.pct), int(round((1.0 - mult) * 100.0)))


func test_dispensa_online_e_offline_coincidono() -> void:
	var a := EstateFixtures.make(5)
	var b := EstateFixtures.make(5)
	for f in [a, b]:
		f.set_levels({"cottage": 3, "sawmill": 2}, 8, 0.0)
		f.bank.add("food_bleak", 500, "test")
	a.run(600.0)
	b.estate.simulate_offline(600.0)
	assert_almost_eq(a.estate.pantry(), b.estate.pantry(), 0.5)
	assert_eq(a.bank.count("food_bleak"), b.bank.count("food_bleak"))


# ------------------------------------------------------------------ M5: mansione di riserva

func _setup_combat_fallback() -> void:
	_open_game()
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start("wc_pine"))
	var cb := Game.system("combat") as CombatSystem
	assert_true(cb.start("millbrook", "hornet_queen"))
	assert_eq(cb.fallback_action(), "wc_pine")


func test_se_il_combattimento_si_ferma_il_tempo_va_alla_mansione() -> void:
	_setup_combat_fallback()
	var sk := Game.system("skills") as SkillSystem
	var cb := Game.system("combat") as CombatSystem
	var xp0 := sk.xp("woodcutting")
	Game.apply_absence(8.0 * 3600.0)
	var c: Dictionary = _last_report.get("combat", {})
	assert_true(str(c.get("stopped", "")) in ["death", "no_food", "death_risk", "no_ammo"], "il combattimento si è fermato: %s" % str(c.get("stopped", "")))
	assert_true(c.has("fallback"))
	assert_gt(sk.xp("woodcutting") - xp0, 1000.0, "il tempo avanzato non va perso")
	assert_eq(sk.current_action(), "wc_pine", "alla fine l'attività è la mansione")
	assert_false(cb.in_combat())
	var wb := WelcomeBack.build(8.0 * 3600.0, _last_report, DataRegistry, Game.offline_cap_s())
	var txt := ""
	for s in wb.sections:
		txt += "\n".join(s.lines) + "\n"
	assert_true(txt.contains(Loc.t(DataRegistry.action("wc_pine").name)), "il Bentornato cita la mansione di riserva")


func test_riserva_spenta_o_assente_il_tempo_resta_inutilizzato_ma_spiegato() -> void:
	_setup_combat_fallback()
	var sk := Game.system("skills") as SkillSystem
	var cb := Game.system("combat") as CombatSystem
	cb.set_safe_fallback(false)
	var xp0 := sk.xp("woodcutting")
	Game.apply_absence(8.0 * 3600.0)
	assert_eq(sk.xp("woodcutting"), xp0, "interruttore spento: vecchio comportamento")
	Game.stop_game(false)
	_open_game()
	var cb2 := Game.system("combat") as CombatSystem
	assert_true(cb2.start("millbrook", "hornet_queen"))
	Game.apply_absence(8.0 * 3600.0)
	var c: Dictionary = _last_report.get("combat", {})
	assert_true(c.has("fallback") and str(c.fallback.action) == "", "nessuna mansione precedente: lo dice")
	var wb := WelcomeBack.build(8.0 * 3600.0, _last_report, DataRegistry, Game.offline_cap_s())
	assert_false(wb.empty)


# ------------------------------------------------------------------ M4: soglia, riferimento, tempo non contato

func test_assenza_brevissima_si_accumula_senza_perdere_nulla() -> void:
	_open_game()
	var sk := Game.system("skills") as SkillSystem
	sk.start("wc_pine")
	var xp0 := sk.xp("woodcutting")
	var min_s := float(Formulas.k().offline.min_apply_s)
	Game.apply_absence(min_s * 0.4)
	assert_eq(sk.xp("woodcutting"), xp0, "sotto la soglia il simulatore non parte")
	assert_almost_eq(float(GameState.data.offline_carry_s), min_s * 0.4, 1e-6)
	Game.apply_absence(min_s * 0.4)
	assert_eq(sk.xp("woodcutting"), xp0)
	Game.apply_absence(min_s * 0.4)       # 1,2 × soglia accumulata: ora si applica TUTTO
	assert_gt(sk.xp("woodcutting"), xp0)
	assert_eq(float(GameState.data.offline_carry_s), 0.0)
	var secs := float(_last_report.get("skills", {}).get("seconds", 0.0))
	assert_almost_eq(secs, min_s * 1.2, 0.5, "il tempo accumulato è stato contato per intero")


func test_riferimento_di_tempo_non_valido_non_regala_il_limite() -> void:
	for bad in [0, -5]:
		var g: Dictionary = Game.offline_gap(100000, bad)
		assert_eq(int(g.elapsed), 0)
		assert_true(bool(g.no_reference))
		assert_false(bool(g.rewound))
	assert_eq(int(Game.offline_gap(5000, 1000).elapsed), 4000)


func test_il_bentornato_dice_il_tempo_non_contato() -> void:
	_open_game()
	var sk := Game.system("skills") as SkillSystem
	sk.start("wc_pine")
	var cap := Game.offline_cap_s()
	Game.apply_absence(cap + 11.0 * 3600.0)
	var wb := WelcomeBack.build(cap, _last_report, DataRegistry, cap)
	var txt := ""
	for s in wb.sections:
		txt += "\n".join(s.lines) + "\n"
	assert_true(txt.contains(NumberFormat.fmt_time(11.0 * 3600.0)), "11 h non contate: %s" % txt)
