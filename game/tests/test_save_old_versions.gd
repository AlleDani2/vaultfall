extends GutTest
## Salvataggi VECCHI REALI (QA120, CLAUDE.md regola 7 «mai rompere un salvataggio esistente senza migrazione»).
## Tre file scritti dal gioco vero di versioni passate (tests/golden/): schema 1 (v0.1, fine Cap. I), schema 1 e schema 2 giocati dal
## bot di allora fino a main_c3_q1 (estratti dai commit prima di FIX-PROGRESSIONE e prima di Q82-1), piu' due file di schema 3 e 4
## ricavati dallo stesso salvataggio reale di schema 2 con le migrazioni ufficiali (scripts/make_golden_saves.gd): nessuna build
## di quelle versioni e' rimasta nel repository, ma il file e' quello che avrebbero scritto. Per ognuno:
##   1) si caricano con la migrazione e lo stato arriva a SCHEMA_VERSION;
##   2) NESSUN progresso si perde: missioni, XP e livelli, Deposito (pile e istanze), valute, Eroe, sblocchi, equipaggiamento;
##   3) la partita prosegue: tick, un'assenza di 8 h (offline vero), salvataggio e ricarica identici;
##   4) l'estrazione delle Casse, dopo la migrazione v2->v3, e' derivata dal seme principale e non cambia ricaricando.

const FILES: Array = [
	"res://tests/golden/save_v0_1_fine_cap1.sav",
	"res://tests/golden/save_v1_reale_c3q1.sav",
	"res://tests/golden/save_v2_reale_c3q1.sav",
	"res://tests/golden/save_v3_reale_c3q1.sav",
	"res://tests/golden/save_v4_reale_c3q1.sav",
]

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_save_old_%d" % Time.get_ticks_usec()
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


## Scrive il file vecchio nello slot con `saved_at_unix` portato a «adesso - gap_s» (i dati restano quelli del file).
func _install(path: String, slot: int, gap_s: int) -> Dictionary:
	var raw := SaveCodec.decode(FileAccess.get_file_as_bytes(path))
	assert_true(raw.ok, "si decodifica: " + path)
	var d: Dictionary = raw.data
	d["saved_at_unix"] = Clock.now_unix() - gap_s
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	assert_eq(SaveService.write_atomic(slot, SaveCodec.encode(d)), OK)
	return d


func _xp_total(d: Dictionary) -> float:
	var t := 0.0
	for sid in d.get("skills", {}):
		t += float(d.skills[sid].get("xp", 0.0))
	return t


func test_i_file_vecchi_hanno_le_versioni_attese() -> void:
	var versions: Array = []
	for f in FILES:
		versions.append(int(SaveCodec.decode(FileAccess.get_file_as_bytes(f)).data.schema_version))
	assert_eq(versions, [1, 1, 2, 3, 4], "v0.1 = schema 1, i due estratti dai commit = schema 1 e 2, poi i due ricavati per migrazione ufficiale")
	assert_gt(SaveCodec.SCHEMA_VERSION, 2, "se lo schema avanza, aggiungere qui un salvataggio reale della versione corrente")


func test_nessun_progresso_si_perde_nella_migrazione() -> void:
	for f in FILES:
		var old := _install(f, 1, 0)
		var lr := Game.load_game(1)
		assert_true(lr.ok, "%s: %s" % [f, lr.get("error", "")])
		assert_eq(int(GameState.data.schema_version), SaveCodec.SCHEMA_VERSION, f)
		var st: Dictionary = GameState.data
		# missioni completate: tutte quelle del file restano (se ne possono aggiungere, mai togliere)
		var done_now: Array = st.quests.done
		for q in old.quests.done:
			assert_true(done_now.has(q), "%s: missione %s ancora completata" % [f, q])
		# XP e livelli per mansione
		for sid in old.skills:
			assert_gte(float(st.skills[sid].xp), float(old.skills[sid].xp) - 1e-6, "%s: XP di %s" % [f, sid])
			assert_gte(int(st.skills[sid].level), int(old.skills[sid].level), "%s: livello di %s" % [f, sid])
		# Deposito: pile e istanze
		for k in old.bank.stacks:
			assert_eq(int(st.bank.stacks.get(k, 0)) + int((st.bank.get("overflow_stacks", {}) as Dictionary).get(k, 0)), int(old.bank.stacks[k]), "%s: pila %s" % [f, k])
		assert_eq(st.bank.instances.size() + (st.bank.get("overflow_instances", []) as Array).size(), old.bank.instances.size(), "%s: istanze" % f)
		var defs_old: Dictionary = {}
		for i in old.bank.instances:
			defs_old[str(i.get("def", i.get("def_id", "")))] = int(defs_old.get(str(i.get("def", i.get("def_id", ""))), 0)) + 1
		var defs_new: Dictionary = {}
		for i in st.bank.instances:
			defs_new[str(i.get("def", i.get("def_id", "")))] = int(defs_new.get(str(i.get("def", i.get("def_id", ""))), 0)) + 1
		assert_eq(defs_new, defs_old, "%s: stesse istanze per definizione" % f)
		for c in old.currencies:
			assert_eq(int(st.currencies.get(c, 0)), int(old.currencies[c]), "%s: valuta %s" % [f, c])
		assert_eq(int(st.hero.get("deaths", 0)), int(old.hero.get("deaths", 0)), "%s: morti" % f)
		for t in old.unlocks:
			assert_true((st.unlocks as Array).has(t), "%s: sblocco %s" % [f, t])
		assert_eq(st.equipment, old.equipment, "%s: equipaggiamento" % f)
		assert_eq(float(st.stats.get("playtime_s", 0.0)), float(old.stats.get("playtime_s", 0.0)), "%s: tempo di gioco" % f)
		Game.stop_game(false)


func test_la_partita_prosegue_e_dopo_8_ore_di_assenza_nulla_si_rompe() -> void:
	for f in FILES:
		var old := _install(f, 1, 8 * 3600)
		var xp0 := _xp_total(old)
		var lr := Game.load_game(1)
		assert_true(lr.ok, "%s: %s" % [f, lr.get("error", "")])
		assert_almost_eq(float(lr.offline_s), 8.0 * 3600.0, 2.0, "%s: 8 h contate" % f)
		assert_gte(_xp_total(GameState.data), xp0 - 1e-6, "%s: l'XP non scende" % f)
		# sessione attiva di 5 minuti con i sistemi veri
		for i in 3000:
			Game._on_step(0.1)
		assert_gte(_xp_total(GameState.data), xp0 - 1e-6, "%s: l'XP non scende dopo i tick" % f)
		# salvataggio e ricarica: stesso stato (a parte il riferimento di tempo)
		var a: Dictionary = Game.snapshot(true).duplicate(true)
		assert_eq(SaveService.save_data(1, a), OK)
		Game.stop_game(false)
		var lr2 := Game.load_game(1)
		assert_true(lr2.ok, "%s: ricarica" % f)
		assert_eq(str(lr2.get("source", "main")), "main", f)
		var b: Dictionary = Game.snapshot(true)
		assert_eq(b.bank.stacks.size(), a.bank.stacks.size(), "%s: pile uguali dopo la ricarica" % f)
		assert_eq(b.quests.done, a.quests.done, "%s: missioni uguali dopo la ricarica" % f)
		assert_eq(b.currencies, a.currencies, "%s: valute uguali dopo la ricarica" % f)
		assert_eq(_xp_total(b), _xp_total(a), "%s: XP uguale dopo la ricarica" % f)
		Game.stop_game(false)


func test_il_menu_legge_i_vecchi_slot_e_li_riscrive_alla_versione_corrente() -> void:
	# ogni file copiato come lo troverebbe il giocatore: il menu lo elenca con modalita', livello e ore di gioco
	for f in FILES:
		SaveService.delete_slot(1)
		DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
		assert_eq(SaveService.write_atomic(1, FileAccess.get_file_as_bytes(f)), OK)
		var info := SaveService.slot_info(1)
		assert_true(info.exists and info.ok, "%s: %s" % [f, str(info)])
		assert_eq(info.mode, "normal")
		assert_gt(int(info.total_level), 5, "livello totale letto dal vecchio file")
		assert_gt(int(info.saved_at_unix), 0)
		assert_eq(info.source, "main")
		# caricare e salvare riscrive il file alla versione corrente; il menu continua a leggerlo
		assert_true(Game.load_game(1).ok)
		assert_true(SaveService.save_now())
		Game.stop_game(false)
		var raw := SaveCodec.decode(FileAccess.get_file_as_bytes(SaveService.slot_path(1)))
		assert_eq(int(raw.data.schema_version), SaveCodec.SCHEMA_VERSION, "%s: riscritto alla versione corrente" % f)
		assert_true(SaveService.slot_info(1).ok)


func test_copia_pre_migrazione_dei_file_reali_una_per_versione_e_mai_sovrascritta() -> void:
	# SHARK 1.0 #1: aprire un salvataggio vecchio ne conserva una copia identica (.pre_vN); riaprirlo o salvare non la tocca
	for f in FILES:
		SaveService.delete_slot(1)
		var orig := FileAccess.get_file_as_bytes(f)
		var ver := int(SaveCodec.decode(orig).data.schema_version)
		DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
		assert_eq(SaveService.write_atomic(1, orig), OK)
		var pre := SaveService.pre_migration_path(1, ver)
		assert_false(FileAccess.file_exists(pre), "prima dell'apertura nessuna copia")
		assert_true(Game.load_game(1).ok)
		assert_true(FileAccess.file_exists(pre), "%s: copia .pre_v%d creata" % [f, ver])
		assert_eq(FileAccess.get_file_as_bytes(pre), orig, "%s: identica all'originale" % f)
		assert_true(SaveService.save_now())
		assert_true(SaveService.save_now())
		Game.stop_game(false)
		assert_true(Game.load_game(1).ok)
		assert_eq(FileAccess.get_file_as_bytes(pre), orig, "%s: salvare e riaprire non sovrascrive la copia" % f)
		Game.stop_game(false)


func test_estrazione_delle_casse_stabile_dopo_la_migrazione() -> void:
	# dal v2 in giu': draw_seed derivato dal seme principale; ricaricare non cambia l'esito di una Cassa (Q82-1)
	for f in [FILES[1], FILES[2], FILES[3], FILES[4]]:
		_install(f, 1, 0)
		assert_true(Game.load_game(1).ok)
		var cs := Game.system("crates") as CrateSystem
		var seed_a := str(cs.state.get("draw_seed", ""))
		assert_true(RngStreams.is_u64_string(seed_a) and seed_a != "0", "%s: seme di estrazione valido" % f)
		assert_true(SaveService.save_now())
		Game.stop_game(false)
		assert_true(Game.load_game(1).ok)
		assert_eq(str((Game.system("crates") as CrateSystem).state.get("draw_seed", "")), seed_a, "%s: seme invariato dopo salva/ricarica" % f)
		Game.stop_game(false)
