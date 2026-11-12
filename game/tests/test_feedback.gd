extends GutTest
## Strumenti di feedback per l'Alfa (FEEDBACK-TOOLS): versione e novità, registro errori ruotato, «Segnala un problema»
## (ZIP locale), statistiche opt-in e cancellazione, strumenti F10 spenti in rilascio.

const MAIN_SCENE := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_stats: SessionStats
var _old_opt: bool
var _tmp: String


func before_each() -> void:
	_tmp = "user://test_feedback_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_tmp)
	_old_dir = SaveService.save_dir
	SaveService.save_dir = _tmp + "/saves"
	SaveService.autosave_enabled = false
	_old_stats = Feedback.stats
	_old_opt = bool(Settings.get_value("stats_opt_in"))
	Feedback.stats = SessionStats.new()
	Feedback.stats.path = _tmp + "/stats/s.json"
	Feedback.simulate_release = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	Feedback.stats = SessionStats.new()
	Settings.set_value("stats_opt_in", _old_opt)
	Feedback.stats = _old_stats
	Feedback.simulate_release = false
	if Feedback.is_dev_menu_open():
		Feedback.toggle_dev_menu()
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	_rm_rf(_tmp)


func _rm_rf(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for s in d.get_directories():
		_rm_rf(dir.path_join(s))
	DirAccess.remove_absolute(dir)


func _new_log(keep: int = 3, max_bytes: int = ErrorLog.MAX_BYTES) -> ErrorLog:
	var l := ErrorLog.new()
	l.dir = _tmp + "/logs"
	l.keep = keep
	l.max_bytes = max_bytes
	return l


func _zip_texts(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	assert_eq(zr.open(path), OK, "lo ZIP si apre")
	var out := {}
	for f in zr.get_files():
		if not f.ends_with("/"):
			out[f] = zr.read_file(f)
	zr.close()
	return out


# ------------------------------------------------------------------ (1) versione e novità

func test_versione_coerente() -> void:
	AppInfo.reload()
	assert_true(AppInfo.version().count(".") == 2, "numero di versione X.Y.Z: " + AppInfo.version())
	var pv := str(ProjectSettings.get_setting("application/config/version"))
	assert_eq(pv, AppInfo.version_tag(), "project.godot e version.json dicono la stessa versione")
	assert_true(AppInfo.build() >= 1)


func test_etichetta_di_rilascio_unica() -> void:
	AppInfo.reload()
	assert_eq(AppInfo.release_label(), "1.0", "il nome del traguardo viene da version.json")
	assert_eq(AppInfo.version_label(), AppInfo.version_tag(), "etichetta mostrata: solo il numero di versione")
	assert_eq(AppInfo.version(), "1.0.0")
	for lang in ["it", "en"]:
		Loc.set_locale(lang)
		var s: String = Loc.tf("UI_FB_VERSION", {"v": AppInfo.version_label(), "build": AppInfo.build()})
		assert_true(s.contains(AppInfo.version()), "titolo/Impostazioni (%s): %s" % [lang, s])
		assert_false(s.to_lower().contains("alfa"), s)


func test_changelog_bilingue() -> void:
	var ch := AppInfo.changelog()
	assert_gt(ch.size(), 0)
	for e in ch:
		var it := AppInfo.entries_of(e, "it")
		var en := AppInfo.entries_of(e, "en")
		assert_gt(it.size(), 0)
		assert_eq(it.size(), en.size(), "stesse voci in IT ed EN")
	assert_eq(str(ch[0].version), AppInfo.version(), "la prima voce è la versione corrente")
	assert_true(AppInfo.changelog_text("it").contains(AppInfo.version()))


func test_schermata_novita_e_versione_nelle_impostazioni() -> void:
	var e := ScreenRegistry.get_entry("news")
	assert_false(e.is_empty())
	var scr: Control = (load(str(e.scene)) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(2)
	assert_true(scr.find_child("*", true, false) != null)
	var settings: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	settings.in_menu = true
	add_child_autofree(settings)
	await wait_process_frames(2)
	var found := false
	for n in settings.find_children("*", "Label", true, false):
		if (n as Label).text.contains(AppInfo.version()):
			found = true
	assert_true(found, "la versione compare nelle Impostazioni")
	assert_true(settings.find_children("*", "FeedbackPanel", true, false).size() == 1 or _has_class(settings, "FeedbackPanel"))


func _has_class(root: Node, cls: String) -> bool:
	for c in root.find_children("*", "VBoxContainer", true, false):
		if c.get_script() != null and c.get_script().get_global_name() == cls:
			return true
	return false


# ------------------------------------------------------------------ (2) registro errori

func test_log_ruotato_ultimi_avvii() -> void:
	var l := _new_log(3)
	for i in 6:
		l.start_session("avvio %d" % i)
		l.add("ERROR", "errore dell'avvio %d" % i, "x.gd:%d" % i)
		l.close()
	var files := l.files()
	assert_eq(files.size(), 3, "al massimo 3 file (avvio corrente + 2 precedenti)")
	assert_true(FileAccess.get_file_as_string(l.current_path()).contains("avvio 5"))
	assert_true(FileAccess.get_file_as_string(l.old_path(1)).contains("avvio 4"))
	assert_true(FileAccess.get_file_as_string(l.old_path(2)).contains("avvio 3"))
	assert_false(FileAccess.file_exists(l.old_path(3)), "i più vecchi sono spariti")


func test_log_dimensione_massima() -> void:
	var l := _new_log(3, 2000)
	l.start_session("test")
	for i in 400:
		l.add("ERROR", "riga numero %d con un po' di testo per fare volume" % i, "f%d.gd:1" % i)
		l.flush()
	l.close()
	var text := FileAccess.get_file_as_string(l.current_path())
	assert_lt(text.length(), 2400, "il file non supera (di molto) il limite")
	assert_true(text.contains("TROPPO LUNGO"), "avviso di troncamento")


func test_log_ripetizioni_e_origine() -> void:
	var l := _new_log()
	l.start_session("test")
	for i in 6:
		l.add("ERROR", "sempre lo stesso", "a.gd:3")
	l.add("ERROR", "altro", "b.gd:1")
	for i in 60:
		l.add("WARNING", "variabile %d" % i, "c.gd:9")
	l.close()
	var text := FileAccess.get_file_as_string(l.current_path())
	assert_true(text.contains("ripetuto 5 volte"), "ripetizioni consecutive raggruppate")
	assert_lt(text.count("variabile"), ErrorLog.PER_SOURCE_MAX + 2, "stessa origine limitata")
	assert_true(text.contains("soppresse"))


func test_log_cattura_avvisi_del_motore() -> void:
	var l := _new_log()
	l.start_session("test")
	var sink := l.make_sink()
	OS.add_logger(sink)
	push_warning("avviso-di-prova-feedback")
	OS.remove_logger(sink)
	l.flush()
	assert_true(FileAccess.get_file_as_string(l.current_path()).contains("avviso-di-prova-feedback"), "push_warning finisce nel registro")


func test_log_non_rallenta() -> void:
	var l := _new_log()
	l.start_session("test")
	# tempo di CPU del thread + fattore di carico (PerfGate): sotto carico (test in parallelo) un limite fisso in ms falliva a caso
	var f0 := PerfGate.load_factor()
	var t0 := PerfGate.clock_usec()
	for i in 5000:
		l.add("ERROR", "errore %d" % (i % 7), "p.gd:%d" % (i % 3))
	var ms := float(PerfGate.clock_usec() - t0) / 1000.0
	PerfGate.assert_time(self, "5000 add() del registro errori", ms, 150.0, PerfGate.factor_around(f0))
	l.close()


# ------------------------------------------------------------------ (3) Segnala un problema

func test_segnalazione_zip_contenuto() -> void:
	assert_true(Game.new_game(1, "normal"))
	var l := _new_log()
	l.start_session("test")
	l.add("ERROR", "errore con percorso " + OS.get_user_data_dir() + "/saves/slot_1.sav", "z.gd:1")
	var rb: Variant = Feedback.new_report("Aprivo una Cassa e il gioco si e' piantato")
	rb.error_log = l
	var lines := PackedStringArray()
	for i in 80:
		lines.append("riga di gioco %d" % i)
	rb.game_lines = lines
	rb.out_dir = _tmp + "/out"
	var res: Variant = rb.build()
	assert_true(res.ok, str(res))
	assert_true(str(res.path).begins_with(_tmp + "/out"))
	var z := _zip_texts(res.path)
	for need in ["LEGGIMI.txt", "riepilogo.txt", "nota_dell_utente.txt", "impostazioni.cfg", "log/registro_errori.txt",
			"log/registro_di_gioco.txt", "salvataggio/slot_1.sav"]:
		assert_true(z.has(need), "nello ZIP: " + need)
	var allowed := ["LEGGIMI.txt", "riepilogo.txt", "nota_dell_utente.txt", "impostazioni.cfg", "log/registro_errori.txt",
		"log/registro_di_gioco.txt", "log/log_del_motore.txt", "salvataggio/slot_1.sav"]
	for k in z:
		assert_true(allowed.has(k), "file non previsto nello ZIP: " + k)
	var summary := (z["riepilogo.txt"] as PackedByteArray).get_string_from_utf8()
	assert_true(summary.contains(AppInfo.version_tag()), "versione")
	assert_true(summary.contains(OS.get_name()), "sistema operativo")
	assert_true(summary.contains("Finestra:"), "risoluzione")
	assert_true(summary.contains("Livello totale"), "livello totale")
	assert_true(summary.contains("Ore giocate"), "ore giocate")
	assert_true(summary.contains("Capitolo"), "capitolo")
	assert_true(summary.contains("Sistemi sbloccati"), "sistemi sbloccati")
	assert_true((z["nota_dell_utente.txt"] as PackedByteArray).get_string_from_utf8().contains("Cassa"), "nota dell'utente")
	var glog := (z["log/registro_di_gioco.txt"] as PackedByteArray).get_string_from_utf8()
	assert_eq(glog.split("\n").size(), 50, "ultime 50 righe")
	assert_true(glog.contains("riga di gioco 79") and not glog.contains("riga di gioco 29"))
	var readme := (z["LEGGIMI.txt"] as PackedByteArray).get_string_from_utf8()
	assert_true(readme.contains("Segnala un problema") and readme.contains("Report a problem"), "LEGGIMI bilingue")
	# la copia dello slot è decodificabile ed è la stessa del file
	var sav: PackedByteArray = z["salvataggio/slot_1.sav"]
	assert_true(SaveCodec.decode(sav).ok, "salvataggio valido")
	assert_eq(sav, FileAccess.get_file_as_bytes(SaveService.slot_path(1)), "copia dello slot")


func test_segnalazione_nessun_dato_personale() -> void:
	assert_true(Game.new_game(1, "normal"))
	var l := _new_log()
	l.start_session("test")
	var home := OS.get_environment("HOME") if OS.get_environment("HOME").length() > 3 else "/home/qualcuno"
	l.add("ERROR", "file " + OS.get_user_data_dir() + "/x e " + home + "/y", "z.gd:1")
	var rb: Variant = Feedback.new_report("")
	rb.error_log = l
	rb.out_dir = _tmp + "/out"
	var res: Variant = rb.build()
	var z := _zip_texts(res.path)
	for entry in z:
		if entry.ends_with(".sav"):
			continue
		var t := (z[entry] as PackedByteArray).get_string_from_utf8()
		assert_false(t.contains(OS.get_user_data_dir()), "niente cartella dati in " + entry)
		if OS.get_environment("HOME").length() > 3 and OS.get_environment("HOME") != "/":
			assert_false(t.contains(OS.get_environment("HOME")), "niente cartella personale in " + entry)
		for env in ["USERNAME", "COMPUTERNAME", "HOSTNAME"]:
			var v := OS.get_environment(env)
			if v.length() >= 5:
				assert_false(t.contains(v), "niente %s in %s" % [env, entry])


func test_segnalazione_senza_partita() -> void:
	var rb: Variant = Feedback.new_report("dal menu")
	rb.error_log = _new_log()
	rb.out_dir = _tmp + "/out"
	var res: Variant = rb.build()
	assert_true(res.ok)
	var z := _zip_texts(res.path)
	assert_false(z.has("salvataggio/slot_1.sav"), "nessuno slot da copiare")
	assert_true((z["riepilogo.txt"] as PackedByteArray).get_string_from_utf8().contains("Nessuna partita"))


func test_nessuna_rete_nel_codice_di_feedback() -> void:
	var forbidden := ["HTTPRequest", "HTTPClient", "StreamPeerTCP", "StreamPeerTLS", "PacketPeerUDP", "UDPServer", "TCPServer",
		"WebSocketPeer", "ENetConnection", "ENetMultiplayerPeer", "WebRTC", "MultiplayerPeer", "http://", "https://", "OS.execute",
		"OS.create_process", "OS.create_instance"]
	var files: Array = []
	var d := DirAccess.open("res://src/feedback")
	for f in d.get_files():
		if f.ends_with(".gd"):
			files.append("res://src/feedback/" + f)
	files.append("res://src/autoload/Feedback.gd")
	files.append("res://src/ui/screens/NewsScreen.gd")
	assert_gt(files.size(), 8)
	for p in files:
		var text := FileAccess.get_file_as_string(p)
		for tok in forbidden:
			if text.contains(tok):
				# il test stesso e i commenti che nominano la rete non contano: cerchiamo solo nel codice
				for line in text.split("\n"):
					if line.contains(tok) and not line.strip_edges().begins_with("#") and not line.contains("##"):
						fail_test("%s usa %s: %s" % [p, tok, line])
	# shell_open apre solo cartelle
	for p in files:
		for line in FileAccess.get_file_as_string(p).split("\n"):
			if line.contains("shell_open("):
				assert_false(line.contains("http"), "shell_open solo su cartelle: " + p)


func test_dialogo_segnalazione_crea_file() -> void:
	assert_true(Game.new_game(2, "normal"))
	var dlg := ReportDialog.new()
	dlg.out_dir = _tmp + "/dlg"
	add_child_autofree(dlg)
	await wait_process_frames(2)
	dlg._note.text = "prova"
	var res := dlg.create_report()
	assert_true(res.ok)
	assert_true(FileAccess.file_exists(res.path))
	assert_true(dlg._folder_btn.visible)


# ------------------------------------------------------------------ (4) statistiche

func test_statistiche_spente_di_default() -> void:
	assert_false(bool(Settings.DEFAULTS["stats_opt_in"]), "spente di default")
	var s := SessionStats.new()
	s.path = _tmp + "/st/s.json"
	assert_false(s.enabled)
	s.begin_session("0.1.0", 1)
	s.tick(10.0, "bank", 1)
	s.on_reward("quest")
	s.on_death(1)
	s.on_exit(1, "bank")
	assert_false(s.has_data(), "spenta: non registra nulla")
	assert_false(s.save_file(), "spenta: non scrive file")
	assert_false(FileAccess.file_exists(s.path))
	assert_eq(s.install_id(), "", "nessun ID finché non si accende")


func test_statistiche_registrano_e_esportano() -> void:
	var s := SessionStats.new()
	s.path = _tmp + "/st/s.json"
	s.set_enabled(true, "2026-10-23")
	assert_eq(s.install_id().length(), 16, "ID casuale di 16 caratteri")
	s.begin_session("0.1.0-alfa", 1)
	s.tick(40.0, "skill:mining", 1)
	s.on_reward("level_up")             # 40 s: meno di 1 minuto
	s.tick(100.0, "bank", 1)
	s.on_reward("quest")                # 100 s: 1-5 minuti
	s.tick(2000.0, "bank", 2)
	s.on_reward("crate")                # oltre 30 minuti
	s.on_death(2)
	s.on_death(2)
	s.on_exit(2, "bank")
	s.note_chapter_reached(2, 3600.0)
	assert_eq(int(s.data.reward_gaps["lt_1m"]), 1)
	assert_eq(int(s.data.reward_gaps["1_5m"]), 1)
	assert_eq(int(s.data.reward_gaps["30_60m"]), 1)
	assert_almost_eq(float(s.data.reward_gap_max_s), 2000.0, 0.01)
	assert_almost_eq(float(s.data.screens["bank"]), 2100.0, 0.01)
	assert_eq(int(s.data.chapters["2"].deaths), 2)
	assert_eq(int(s.data.chapters["2"].exits), 1)
	assert_almost_eq(float(s.data.chapters["2"].first_playtime_s), 3600.0, 0.01)
	assert_true(s.save_file())
	var s2 := SessionStats.new()
	s2.path = s.path
	assert_true(s2.load_file(), "il file si rilegge")
	assert_eq(s2.install_id(), s.install_id())
	assert_eq(int(s2.data.totals.deaths), 2)
	var csv := s.export_csv()
	assert_true(csv.begins_with("section,key,field,value"))
	assert_true(csv.contains("install_id,,%s" % s.install_id()) or csv.contains("info,install_id,,%s" % s.install_id()))
	assert_true(csv.contains("chapters,2,deaths,2"))
	var js: Variant = JSON.parse_string(s.export_json())
	assert_true(js is Dictionary and js.install_id == s.install_id())
	for k in js:
		assert_false(["name", "user", "path", "ip", "text"].has(str(k)), "nessun campo personale: " + str(k))


func test_statistiche_cancella_tutto() -> void:
	var s := SessionStats.new()
	s.path = _tmp + "/st/s.json"
	s.set_enabled(true)
	var old_id := s.install_id()
	s.begin_session("v", 1)
	s.tick(5.0, "bank", 1)
	assert_true(s.save_file())
	assert_true(FileAccess.file_exists(s.path))
	s.clear_all()
	assert_false(FileAccess.file_exists(s.path), "file cancellato")
	assert_false(s.has_data(), "dati azzerati")
	assert_true(s.enabled and s.install_id() != old_id, "la registrazione prosegue con un ID nuovo")
	s.set_enabled(false)
	s.clear_all()
	assert_eq(s.install_id(), "")


func test_statistiche_collegate_a_impostazioni_ed_eventi() -> void:
	assert_false(Feedback.stats.enabled)
	Settings.set_value("stats_opt_in", true)
	assert_true(Feedback.stats.enabled, "l'impostazione accende la registrazione")
	assert_true(Game.new_game(1, "normal"))
	EventBus.player_died.emit("prova")
	EventBus.quest_completed.emit("main_c0_q1")
	assert_eq(int(Feedback.stats.data.totals.deaths), 1)
	assert_eq(int(Feedback.stats.data.rewards.get("quest", 0)), 1)
	var out := Feedback.export_stats(_tmp + "/exp")
	assert_true(out.ok and FileAccess.file_exists(out.csv) and FileAccess.file_exists(out.json))
	Settings.set_value("stats_opt_in", false)
	assert_false(Feedback.stats.enabled, "spenta di nuovo")
	EventBus.player_died.emit("prova")
	assert_eq(int(Feedback.stats.data.totals.deaths), 1, "da spenta non conta")


# ------------------------------------------------------------------ (5) strumenti da sviluppatore

func test_f10_inaccessibile_in_rilascio() -> void:
	assert_false(DevTools.is_enabled(false, ""), "rilascio senza variabile: spento")
	assert_false(DevTools.is_enabled(false, "0"))
	assert_false(DevTools.is_enabled(false, "1"), "VAULTFALL_DEBUG=1 NON accende nulla in un export di rilascio (SHARK 1.0 #10)")
	assert_true(DevTools.is_enabled(true, ""), "build di sviluppo: acceso")
	assert_true(DevTools.is_enabled(true, "1"))
	Feedback.simulate_release = true
	assert_false(Feedback.dev_enabled())
	assert_false(Feedback.handle_key(KEY_F10), "F10 non fa nulla")
	assert_false(Feedback.toggle_dev_menu())
	assert_false(Feedback.is_dev_menu_open(), "nessun menù creato")
	# l'unico punto che crea il menù è Feedback.toggle_dev_menu (dietro il controllo)
	var users := 0
	for p in ["res://src/autoload/Feedback.gd", "res://src/feedback/PauseMenu.gd", "res://src/feedback/FeedbackPanel.gd",
			"res://src/feedback/ReportDialog.gd", "res://src/ui/start/StartScreen.gd", "res://src/ui/screens/SettingsScreen.gd",
			"res://src/ui/main/MainScreen.gd"]:
		var src := FileAccess.get_file_as_string(p)
		users += src.count("DevMenu.new()") + src.count("(load(_DEV_MENU) as GDScript).new()")
	assert_eq(users, 1)
	# caricamento pigro (resoconto 100): l'autoload non nomina le classi dei menù e la costante dell'ambiente coincide
	assert_eq(Feedback.DEV_ENV_VAR, DevTools.ENV_VAR)
	var fb_src := FileAccess.get_file_as_string("res://src/autoload/Feedback.gd")
	for cls in ["DevTools.", "DevMenu.new", "PauseMenu.new", "ReportBuilder.new", "ReportBuilder.default", "ReportBuilder.stamp"]:
		assert_false(fb_src.contains(cls), "Feedback.gd non nomina " + cls)


func test_f10_apre_e_chiude_in_debug() -> void:
	assert_true(Feedback.handle_key(KEY_F10))
	assert_true(Feedback.is_dev_menu_open())
	await wait_process_frames(2)
	assert_true(Feedback.handle_key(KEY_ESCAPE), "Esc chiude il menù F10")
	assert_false(Feedback.is_dev_menu_open())


func test_strumenti_sviluppatore_azioni() -> void:
	assert_true(Game.new_game(1, "normal"))
	var t := DevTools.new()
	var g0 := GameState.gold()
	assert_true(t.give_gold(5000))
	assert_eq(GameState.gold(), g0 + 5000)
	assert_eq(t.give_item("log_pine", 12), 12)
	assert_eq(t.give_item("non_esiste_xyz", 1), 0)
	var lv := t.set_skill_level("woodcutting", 15)
	assert_eq(lv, 15)
	var chapters_before := t.current_chapter()
	var n := t.unlock_chapter(1)
	assert_gt(n, 0, "missioni del prologo riscattate")
	assert_gte(t.current_chapter(), 1)
	assert_gte(t.current_chapter(), chapters_before)
	assert_true(t.skip_time(3600.0) is Dictionary)
	assert_true(t.set_event_date(2026, 12, 24))
	t.clear_event_date()
	assert_false(t.set_event_date(2026, 13, 1))
	assert_true(t.force_save())


func test_carica_salvataggio_di_un_amico_da_zip() -> void:
	assert_true(Game.new_game(1, "normal"))
	var t := DevTools.new()
	t.give_gold(777)
	t.set_skill_level("woodcutting", 12)
	var rb: Variant = Feedback.new_report("")
	rb.error_log = _new_log()
	rb.out_dir = _tmp + "/out"
	var res: Variant = rb.build()
	var gold := GameState.gold()
	var level: int = int(Game.system("skills").call("level", "woodcutting"))
	Game.stop_game(false)
	var r := t.load_friend_save(res.path, 3)
	assert_true(r.ok, str(r))
	assert_eq(GameState.slot, 3)
	assert_eq(GameState.gold(), gold)
	assert_eq(int(Game.system("skills").call("level", "woodcutting")), level)
	var bad := t.load_friend_save(_tmp + "/non_esiste.zip", 3)
	assert_false(bad.ok)


# ------------------------------------------------------------------ menù di pausa

func test_menu_pausa_ha_segnala_un_problema() -> void:
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	await wait_process_frames(2)
	var texts := []
	for b in pm.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	assert_true(texts.has("UI_FB_REPORT_BUTTON"), "pulsante nel menù di pausa")
	assert_true(texts.has("UI_FB_PAUSE_RESUME"))
	var dlg := ReportDialog.new()
	dlg.out_dir = _tmp + "/x"
	add_child_autofree(dlg)
	await wait_process_frames(1)
	assert_not_null(dlg)


func test_stringhe_feedback_bilingui() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	f.get_csv_line()
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0].begins_with("UI_FB_"):
			n += 1
			assert_false(row[1].is_empty() or row[2].is_empty(), "IT ed EN: " + row[0])
			assert_ne(row[1], row[2] if row[1].length() > 40 else "", "tradotto: " + row[0])
	assert_gt(n, 50)
	assert_ne(tr("UI_FB_REPORT_BUTTON"), "UI_FB_REPORT_BUTTON", "la chiave si traduce")
