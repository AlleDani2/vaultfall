extends GutTest
## Piattaforma (Steam): backend nullo di default, mappa delle 118 imprese, Rich Presence, cloud dei salvataggi come copia dei file.
## Nessuna estensione e nessuna rete: si prova con un finto backend (tests/helpers/fake_platform.gd). Con il backend nullo il gioco
## resta identico (nessun _process, nessuna chiamata).

var _dir: String = ""
var _old_dir: String
var _old_tut: Variant


func before_each() -> void:
	_dir = "user://test_platform_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_old_dir = SaveService.save_dir
	_old_tut = Settings.get_value("tutorials")


func after_each() -> void:
	PlatformService.use_backend(null)
	PlatformService.cloud_enabled_override = -1
	AppConfig.override(null)
	if GameState.active:
		Game.stop_game(false)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("tutorials", _old_tut)
	var d := DirAccess.open(_dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _files() -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(_dir)
	if d != null:
		out = d.get_files()
	out.sort()
	return out


# ---------------------------------------------------------------- backend nullo

func test_default_e_backend_nullo() -> void:
	assert_eq(PlatformService.platform_name(), "null")
	assert_false(PlatformService.is_active())
	assert_false(PlatformService.is_processing(), "senza Steam nessun _process")
	assert_false(PlatformService.unlock("ach_woodcutting_50"))
	var n := PlatformBackend.new()
	assert_false(n.init())
	assert_false(n.unlock_achievement("ACH_X"))
	assert_false(n.has_achievement("ACH_X"))
	assert_false(n.store_stats())
	assert_false(n.set_presence("x"))
	assert_false(n.cloud_enabled())
	assert_false(n.cloud_exists("saves/slot_1.sav"))
	assert_true(n.cloud_read("saves/slot_1.sav").is_empty())
	assert_false(n.cloud_write("saves/slot_1.sav", PackedByteArray([1])))


func test_backend_steam_senza_estensione_non_parte() -> void:
	if SteamBackend.is_available():
		pass_test("l'estensione GodotSteam e' presente in questo ambiente: prova non applicabile")
		return
	var sb := SteamBackend.new()
	assert_false(sb.init())
	assert_false(sb.is_active())
	assert_eq(sb.last_error, "extension_missing")
	assert_false(sb.unlock_achievement("ACH_X"))
	assert_false(sb.cloud_enabled())
	sb.run_callbacks()                       # no-op, nessun errore
	sb.shutdown()


func test_nessun_codice_di_rete_nel_modulo() -> void:
	for f in ["PlatformService", "PlatformBackend", "SteamBackend", "CloudSync", "AppConfig"]:
		var src := FileAccess.get_file_as_string("res://src/platform/%s.gd" % f)
		for banned in ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "PacketPeerUDP", "ENetMultiplayerPeer", "WebSocket"]:
			assert_false(src.contains(banned), "%s non deve usare %s" % [f, banned])


func test_servizio_con_backend_nullo_ignora_gli_eventi() -> void:
	PlatformService.use_backend(null)
	EventBus.achievement_unlocked.emit("ach_woodcutting_50")       # nessun errore, nessun effetto
	assert_false(PlatformService.is_active())


# ---------------------------------------------------------------- mappa delle imprese

func test_tabella_steam_imprese() -> void:
	var ach: Array = DataRegistry.table("achievements")
	var steam: Array = DataRegistry.table("steam_achievements")
	assert_eq(ach.size(), 118)
	assert_eq(steam.size(), 118, "una riga Steam per ogni impresa")
	var api := {}
	var p1 := 0
	var by_id := {}
	for a in ach:
		by_id[str(a.id)] = a
	for s in steam:
		assert_true(by_id.has(str(s.id)), "impresa %s esiste" % s.id)
		var a: Dictionary = by_id[str(s.id)]
		assert_eq(str(s.steam_api_name), str(a.steam_api_name), "ID Steam stabile (derivato dall'id)")
		assert_eq(str(s.steam_api_name), str(s.id).to_upper())
		assert_false(api.has(s.steam_api_name), "ID Steam unico")
		api[s.steam_api_name] = true
		if int(s.phase) == 1:
			p1 += 1
		for lang in ["it", "en"]:
			assert_false(str(s.name[lang]).is_empty())
			assert_false(str(s.desc[lang]).is_empty())
			assert_lt(str(s.name[lang]).length(), 101)
		if bool(a.hidden):
			assert_true(bool(s.hidden), "nascosta nel gioco -> nascosta su Steam")
		assert_eq(str(s.icon_achieved), str(s.steam_api_name) + "_ACHIEVED.png")
	assert_eq(p1, 100, "fase 1 = 100 imprese (limite di Steam)")


func test_fase_delle_imprese_segue_la_configurazione() -> void:
	var fake := TestFakePlatform.new()
	PlatformService.use_backend(fake)
	var phase2 := ""
	for s in DataRegistry.table("steam_achievements"):
		if int(s.phase) == 2:
			phase2 = str(s.id)
			break
	assert_ne(phase2, "")
	AppConfig.override({"steam_achievement_phase": 1})
	assert_false(PlatformService.is_registered(phase2))
	EventBus.achievement_unlocked.emit(phase2)
	assert_true(fake.achievements.is_empty(), "fase 2 non ancora configurata su Steamworks")
	AppConfig.override({"steam_achievement_phase": 2})
	EventBus.achievement_unlocked.emit(phase2)
	assert_true(fake.achievements.has(phase2.to_upper()))


# ---------------------------------------------------------------- imprese verso il finto Steam

func test_sblocco_impresa_arriva_a_steam_e_si_conferma() -> void:
	var fake := TestFakePlatform.new()
	PlatformService.use_backend(fake)
	assert_true(PlatformService.is_active())
	assert_true(PlatformService.is_processing())
	EventBus.achievement_unlocked.emit("ach_woodcutting_50")
	assert_true(fake.achievements.has("ACH_WOODCUTTING_50"))
	assert_eq(fake.stored, 0, "storeStats e' in coda per il prossimo fotogramma")
	PlatformService._process(0.016)
	assert_eq(fake.stored, 1)
	EventBus.achievement_unlocked.emit("ach_woodcutting_50")       # gia' su Steam: non si rimanda
	PlatformService._process(0.016)
	assert_eq(fake.stored, 1)
	EventBus.achievement_unlocked.emit("ach_inesistente")
	assert_eq(fake.achievements.size(), 1)


func test_allineamento_al_caricamento_solo_verso_steam() -> void:
	Settings.set_value("tutorials", false)
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 5))
	(GameState.data["achievements"] as Array).append("ach_total_250")
	(GameState.data["achievements"] as Array).append("ach_first_star")
	var fake := TestFakePlatform.new()
	fake.achievements["ACH_ALTRO"] = true                         # sblocco solo su Steam
	PlatformService.use_backend(fake)                             # allinea subito
	assert_true(fake.achievements.has("ACH_TOTAL_250"))
	assert_true(fake.achievements.has("ACH_FIRST_STAR"))
	assert_eq((GameState.data["achievements"] as Array).size(), 2, "Steam non sblocca mai nulla nel gioco")


# ---------------------------------------------------------------- presenza

func test_rich_presence_testuale_senza_dati_privati() -> void:
	Settings.set_value("tutorials", false)
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	var fake := TestFakePlatform.new()
	PlatformService.use_backend(fake)
	assert_eq(fake.presence, tr("UI_PLAT_PRESENCE_MENU"), "nel menu")
	assert_true(Game.new_game(1, "normal", 5))
	PlatformService.update_presence(true)
	assert_ne(fake.presence, tr("UI_PLAT_PRESENCE_MENU"))
	assert_false(fake.presence.is_empty())
	assert_false(fake.presence.contains("slot"))
	assert_false(fake.presence.contains(_dir))
	var sets := fake.presence_sets
	PlatformService.update_presence()                                # invariato: niente chiamata inutile
	assert_eq(fake.presence_sets, sets)
	Game.stop_game(false)
	assert_eq(fake.presence, tr("UI_PLAT_PRESENCE_MENU"))


func test_presenza_si_taglia_a_250_byte() -> void:
	var t := "à".repeat(300)
	var clipped := SteamBackend._clip(t)
	assert_lte(clipped.to_utf8_buffer().size(), SteamBackend.PRESENCE_MAX_BYTES)
	assert_gt(clipped.length(), 100)


# ---------------------------------------------------------------- cloud (copia dei file)

func _cloud(fake: TestFakePlatform) -> CloudSync:
	return CloudSync.new(fake, _dir)


func test_cloud_nullo_non_fa_nulla() -> void:
	_write(_dir.path_join("slot_1.sav"), "AAA")
	var c := CloudSync.new(null, _dir)
	assert_false(c.is_enabled())
	assert_true(c.sync_all().is_empty())
	assert_false(c.upload_slot(1))
	assert_eq(_files(), PackedStringArray(["slot_1.sav"]))


func test_cloud_carica_il_locale_se_il_cloud_e_vuoto() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "PARTITA-UNO")
	_write(_dir.path_join("slot_1.sav.bak1"), "VECCHIA")
	_write(_dir.path_join("slot_1.sav.tmp"), "A META")
	var c := _cloud(fake)
	var r := c.sync_all(2000)
	assert_eq(r["saves/slot_1.sav"], "uploaded")
	assert_eq(r["saves/slot_2.sav"], "skipped")
	assert_eq(fake.files.keys(), ["saves/slot_1.sav"], "solo slot_N.sav: niente .bak/.tmp")
	assert_eq(fake.files["saves/slot_1.sav"].get_string_from_utf8(), "PARTITA-UNO", "byte identici: il formato non cambia")


func test_cloud_scarica_se_manca_in_locale() -> void:
	var fake := TestFakePlatform.new()
	fake.files["saves/slot_2.sav"] = "DAL-CLOUD".to_utf8_buffer()
	fake.stamps["saves/slot_2.sav"] = 500
	var c := _cloud(fake)
	assert_eq(c.sync_slot(2, 2000), "downloaded")
	assert_eq(_read(_dir.path_join("slot_2.sav")), "DAL-CLOUD")
	assert_eq(_files(), PackedStringArray(["slot_2.sav"]), "nessun .tmp residuo")


func test_cloud_piu_recente_sostituisce_ma_tiene_copia_locale() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "LOCALE")
	fake.files["saves/slot_1.sav"] = "NUVOLA".to_utf8_buffer()
	fake.stamps["saves/slot_1.sav"] = int(Time.get_unix_time_from_system()) + 100000
	var c := _cloud(fake)
	assert_eq(c.sync_slot(1, 7777), "downloaded")
	assert_eq(_read(_dir.path_join("slot_1.sav")), "NUVOLA")
	assert_eq(_read(_dir.path_join("slot_1.sav.pre_cloud_7777")), "LOCALE", "la partita locale non si perde")
	assert_eq(fake.files["saves/slot_1.sav"].get_string_from_utf8(), "NUVOLA", "il cloud non e' stato toccato")


func test_cloud_meno_recente_non_sostituisce_il_locale() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "LOCALE-NUOVO")
	fake.files["saves/slot_1.sav"] = "VECCHIO".to_utf8_buffer()
	fake.stamps["saves/slot_1.sav"] = 10
	var c := _cloud(fake)
	assert_eq(c.sync_slot(1, 7777), "uploaded")
	assert_eq(_read(_dir.path_join("slot_1.sav")), "LOCALE-NUOVO")
	assert_eq(fake.files["saves/slot_1.sav"].get_string_from_utf8(), "LOCALE-NUOVO")


func test_cloud_uguale_non_riscrive() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "UGUALE")
	fake.files["saves/slot_1.sav"] = "UGUALE".to_utf8_buffer()
	fake.stamps["saves/slot_1.sav"] = 1
	var c := _cloud(fake)
	assert_eq(c.sync_slot(1), "same")
	assert_eq(fake.writes, 0)
	assert_eq(c.upload_changed(5000), 0, "gia' allineato")


func test_cloud_cloud_illeggibile_non_tocca_il_locale() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "LOCALE")
	fake.files["saves/slot_1.sav"] = PackedByteArray()
	fake.stamps["saves/slot_1.sav"] = 99999999999
	var c := _cloud(fake)
	assert_eq(c.sync_slot(1), "failed")
	assert_eq(_read(_dir.path_join("slot_1.sav")), "LOCALE")


func test_cloud_upload_a_frequenza_limitata_e_flush_all_uscita() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "V1")
	var c := _cloud(fake)
	assert_true(c.upload_slot(1, 1000, true))
	assert_eq(fake.writes, 1)
	_write(_dir.path_join("slot_1.sav"), "VERSIONE-DUE")
	assert_eq(c.upload_changed(1050), 0, "meno di MIN_UPLOAD_GAP_S dall'ultimo")
	assert_eq(fake.writes, 1)
	assert_eq(c.upload_changed(1000 + int(CloudSync.MIN_UPLOAD_GAP_S) + 1), 1)
	assert_eq(fake.files["saves/slot_1.sav"].get_string_from_utf8(), "VERSIONE-DUE")
	_write(_dir.path_join("slot_1.sav"), "VERSIONE-TRE")
	assert_eq(c.flush(1100), 1, "all'uscita si carica subito")
	assert_eq(fake.files["saves/slot_1.sav"].get_string_from_utf8(), "VERSIONE-TRE")
	assert_eq(c.flush(1200), 0)


func test_cloud_scrittura_rifiutata_non_segna_come_allineato() -> void:
	var fake := TestFakePlatform.new()
	fake.refuse_write = true
	_write(_dir.path_join("slot_1.sav"), "X")
	var c := _cloud(fake)
	assert_false(c.upload_slot(1, 1000, true))
	fake.refuse_write = false
	assert_eq(c.flush(1001), 1)


func test_cloud_spento_da_configurazione() -> void:
	var fake := TestFakePlatform.new()
	_write(_dir.path_join("slot_1.sav"), "X")
	PlatformService.cloud_enabled_override = 0
	PlatformService.use_backend(fake)
	PlatformService.cloud.save_dir = _dir
	EventBus.save_completed.emit(true)
	assert_eq(fake.writes, 0)


func test_servizio_carica_nel_cloud_dopo_un_salvataggio() -> void:
	var fake := TestFakePlatform.new()
	PlatformService.cloud_enabled_override = 1
	SaveService.save_dir = _dir
	PlatformService.use_backend(fake)
	_write(_dir.path_join("slot_3.sav"), "SALVATAGGIO")
	EventBus.save_completed.emit(true)
	assert_true(fake.files.has("saves/slot_3.sav"))
	EventBus.save_completed.emit(false)                              # salvataggio fallito: niente
	assert_eq(fake.writes, 1)


# ---------------------------------------------------------------- configurazione unica

func test_app_config_un_solo_punto() -> void:
	AppConfig.override({"support_url": "https://example.test/aiuto", "support_email": "a@b.test"})
	assert_eq(AppConfig.support_contact(), "https://example.test/aiuto")
	assert_true(AppConfig.has_support())
	AppConfig.override({"support_email": "a@b.test"})
	assert_eq(AppConfig.support_contact(), "a@b.test")
	AppConfig.override({})
	assert_false(AppConfig.has_support())
	assert_false(AppConfig.open_support(), "nessun contatto: niente da aprire")
	assert_true(AppConfig.is_safe_url("https://x.y"))
	assert_true(AppConfig.is_safe_url("mailto:<email removed>"))
	assert_false(AppConfig.is_safe_url("file:///etc/passwd"))
	assert_false(AppConfig.is_safe_url("javascript:alert(1)"))
	AppConfig.override(null)
	assert_eq(AppConfig.steam_achievement_phase(), 1, "il file nel pacchetto parte dalla fase 1")


func test_finestra_segnalazione_mostra_il_contatto_configurato() -> void:
	AppConfig.override({"support_email": "aiuto@esempio.test"})
	var dlg := ReportDialog.new()
	add_child_autofree(dlg)
	await get_tree().process_frame
	var found := false
	for n in dlg.find_children("*", "Label", true, false):
		if (n as Label).text.contains("aiuto@esempio.test"):
			found = true
	assert_true(found, "il contatto di assistenza compare nella finestra")
	assert_false(tr("UI_FB_REPORT_INTRO").to_lower().contains("gave you"))
	assert_false(tr("UI_FB_REPORT_DONE").to_lower().contains("gave you"))
