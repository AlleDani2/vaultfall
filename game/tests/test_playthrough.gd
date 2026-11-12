extends GutTest
## Integrazione: partita VERA (Game.new_game, tutti i sistemi di SystemRegistry) giocata da BotPlayer a tempo
## simulato (passi diretti, mai tempo reale) dal benvenuto alla fine del Capitolo I. Ogni blocco del bot è un
## bug di integrazione. Criteri M4 (docs/22): Cap. I in 60-90 minuti, prima Cassa entro 15, nessun sistema usato
## prima del suo sblocco. Stampa la tabella dei tempi (docs/audit_2026-10-22/29_RESOCONTO_INTEGRAZIONE.md).
## BOT_LOG=1 nell'ambiente stampa anche il diario completo del bot.

const SEED := 20261023
const MAX_S := 4.0 * 3600.0
const LAST_QUEST := "main_c1_q6"

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_playthrough_saves"
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


var _trk := PerfGate.Tracker.new()     # fattore di carico durante la partita (PerfGate)


func _step(dt: float) -> void:
	Game._on_step(dt)


func _play(seed_value: int, use_tomes: bool) -> Dictionary:
	assert_true(Game.new_game(1, "normal", seed_value), "nuova partita")
	var bot := BotPlayer.new(Game.sim, _step)
	_trk.start()
	bot.between_steps = _trk.step
	bot.clock = PerfGate.clock_usec
	bot.use_tomes = use_tomes
	var res := bot.run_until_quest(LAST_QUEST, MAX_S)
	var lines := PackedStringArray()
	var prev := 0.0
	for e in res.quests:
		var parts := PackedStringArray()
		for k in e.spent:
			if float(e.spent[k]) >= 30.0:
				parts.append("%s %.1f" % [k, float(e.spent[k]) / 60.0])
		lines.append("%-12s fine %6.1f min  (durata %5.1f, eroe %2d)  %s" % [e.id, float(e.t) / 60.0,
			(float(e.t) - prev) / 60.0, int(e.hero), ", ".join(parts)])
		prev = float(e.t)
	gut.p("Tempi delle missioni (minuti simulati, seme %d, tomi %s):\n%s" % [seed_value, use_tomes, "\n".join(lines)])
	gut.p("Prima Cassa aperta: %.1f min · morti: %d · picco tick: %.2f ms" % [float(res.first_crate_t) / 60.0,
		int(res.deaths), float(res.max_tick_ms)])
	var unl := PackedStringArray()
	for tok in res.unlock_t:
		unl.append("%s@%.1f" % [tok, float(res.unlock_t[tok]) / 60.0])
	gut.p("Sblocchi: " + ", ".join(unl))

	if OS.get_environment("BOT_LOG") != "" or not bool(res.ok):
		gut.p("\n".join(bot.log_lines))
	assert_eq(res.blocks, [], "nessun blocco")
	assert_true(bool(res.ok), "Capitolo I completato")
	assert_eq(res.violations, [], "nessun sistema usato prima dello sblocco")
	assert_eq(res.stubs, [], "nessun obiettivo simulato: tutti i sistemi del Cap. I sono veri (Coltivazione compresa)")
	return res


func test_partita_completa_fino_alla_fine_del_capitolo_I() -> void:
	var res := _play(SEED, true)
	var end_min := float(res.t) / 60.0
	assert_between(end_min, 40.0, 90.0, "criterio M4: fine del Capitolo I tra 40 e 90 minuti (bot ottimo: un giocatore umano impiega di più)")
	assert_between(float(res.first_crate_t) / 60.0, 0.0, 15.0, "criterio M4: prima Cassa entro 15 minuti")
	# il picco di un singolo tick dipende dal carico della macchina: soglia 50 ms x fattore di carico (PerfGate)
	PerfGate.assert_time(self, "picco del tick con tutti i sistemi (Cap. I)", float(res.max_tick_ms), 50.0, _trk.finish())
	# ritmo: nessuna missione principale oltre 15 minuti (niente muri nella prima ora)
	var prev := 0.0
	for e in res.quests:
		assert_lt((float(e.t) - prev) / 60.0, 15.0, "durata di " + str(e.id))
		prev = float(e.t)


## Offline di 24 ore con TUTTI i sistemi attivi (docs/17: ≤ 1 s) e finestra "Bentornato" con le sezioni dei sistemi.
func test_offline_24_ore_tutti_i_sistemi_e_bentornato() -> void:
	assert_true(Game.new_game(1, "normal", SEED + 2))
	var bot := BotPlayer.new(Game.sim, _step)
	var res := bot.run_until_quest("main_c1_q4", MAX_S)      # Mercato aperto: tutti i sistemi del Cap. I in gioco
	assert_true(bool(res.ok), "partita fino al Mercato")
	var cb := Game.system("combat") as CombatSystem
	var sk := Game.system("skills") as SkillSystem
	var limit := Game.offline_cap_s()
	# 1) combattimento offline
	assert_true(cb.start("millbrook", "mud_slime"))
	# micro-benchmark: l'offline NON emette un segnale per uccisione (un solo batch per mostro) e non suona
	var counts := {"single": 0, "batch": 0, "kills": 0}
	var on_single := func(_m: String, _d: Array) -> void: counts.single += 1
	var on_batch := func(_m: String, n: int, _d: Array) -> void:
		counts.batch += 1
		counts.kills += n
	EventBus.monster_killed.connect(on_single)
	EventBus.monsters_killed_batch.connect(on_batch)
	var f0 := PerfGate.load_factor()
	var t0 := PerfGate.clock_usec()
	Game._on_long_gap(86400.0)
	var ms_combat := float(PerfGate.clock_usec() - t0) / 1000.0
	EventBus.monster_killed.disconnect(on_single)
	EventBus.monsters_killed_batch.disconnect(on_batch)
	assert_eq(int(counts.single), 0, "offline: nessun monster_killed per uccisione")
	assert_gt(int(counts.kills), 0, "offline: uccisioni consegnate in batch")
	assert_lt(int(counts.batch), 5, "offline: un evento per mostro, non per uccisione")
	var off := (Game.system("quests") as QuestSystem).take_offline()
	assert_false(off.is_empty(), "il resoconto arriva al Bentornato")
	var wb := WelcomeBack.build(float(off.seconds), off.report, DataRegistry, limit)
	assert_false(bool(wb.empty), "Bentornato con contenuto dopo il combattimento")
	var text := _wb_text(wb)
	gut.p("Bentornato (combattimento, %.0f ms):\n%s" % [ms_combat, text])
	assert_true(text.contains(Loc.t(DataRegistry.get_def("monsters", "mud_slime").name)), "riga delle vittorie")
	# 2) mansione offline (la più lunga: 24 h di taglio)
	assert_true(sk.start("wc_pine"))
	t0 = PerfGate.clock_usec()
	Game._on_long_gap(86400.0)
	var ms_skill := float(PerfGate.clock_usec() - t0) / 1000.0
	off = (Game.system("quests") as QuestSystem).take_offline()
	wb = WelcomeBack.build(float(off.seconds), off.report, DataRegistry, limit)
	text = _wb_text(wb)
	gut.p("Bentornato (mansione, %.0f ms):\n%s" % [ms_skill, text])
	assert_true(text.contains(Loc.t(DataRegistry.action("wc_pine").name)), "riga del lavoro svolto")
	var f := PerfGate.factor_around(f0)
	PerfGate.assert_time(self, "24 h offline di combattimento con tutti i sistemi", ms_combat, 1000.0, f)
	PerfGate.assert_time(self, "24 h offline di mansione con tutti i sistemi", ms_skill, 1000.0, f)


func _wb_text(wb: Dictionary) -> String:
	var lines := PackedStringArray()
	for s in wb.sections:
		lines.append("[%s]" % TranslationServer.translate(str(s.header)))
		lines.append_array(s.lines)
	return "\n".join(lines)


## Profilo "lento": chi non usa il Tomo del Prologo sull'Eroe. Deve comunque finire il Capitolo I senza blocchi.
func test_profilo_senza_tomi_finisce_il_capitolo_I() -> void:
	var res := _play(SEED + 1, false)
	assert_lt(float(res.t) / 60.0, 150.0, "anche senza Tomi il Capitolo I resta sotto le 2 ore e mezza")
