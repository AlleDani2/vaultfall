extends GutTest
## Menù 1.0: schermata del titolo (key art senza modifiche, scala, voci, caricamento), slot (riepilogo, cache, ripristino dai
## backup, conferme), menù di pausa, Crediti e licenze, versione 1.0 senza testi da Alfa, stringhe bilingui senza chiavi nude.

const START := "res://src/ui/start/StartScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old_locale: String
var _old_motion: bool


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_locale = Loc.locale()
	_old_motion = bool(Settings.get_value("reduce_motion"))
	SaveService.save_dir = "user://test_menu_1_0_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	SlotSummary.invalidate()
	MenuIntent.screen = ""
	Settings.set_value("last_slot", 0)
	Settings.set_value("reduce_motion", true)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	Feedback.close_pause_menu()
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	SlotSummary.invalidate()
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("locale", _old_locale)
	Settings.set_value("reduce_motion", _old_motion)
	MenuIntent.screen = ""


func _start() -> Control:
	var s: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	return s


func _make_slot(slot: int) -> void:
	assert_true(Game.new_game(slot, "normal", 7))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	SlotSummary.invalidate()


func _csv_rows() -> Array:
	var rows: Array = []
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() >= 3:
			rows.append(r)
	return rows


# ------------------------------------------------------------------ versione 1.0

func test_versione_1_0_in_un_solo_punto() -> void:
	AppInfo.reload()
	assert_eq(AppInfo.version(), "1.0.0")
	assert_eq(AppInfo.stage(), "", "nessuna fase alfa/beta")
	assert_eq(str(ProjectSettings.get_setting("application/config/version")), "1.0.0")
	assert_eq(str(AppInfo.changelog()[0].version), "1.0.0")


func test_nessun_testo_da_alfa_nell_interfaccia_e_nei_metadati() -> void:
	var bad := RegEx.create_from_string("(?i)\\b(alfa|alpha|cavia|cavie|guinea pig)\\b|valfa|bug (is|e')? ?a gift|ogni bug")
	for r in _csv_rows():
		for i in [1, 2]:
			assert_null(bad.search(str(r[i])), "%s (%d): %s" % [r[0], i, str(r[i]).left(80)])
	for lang in ["it", "en"]:
		assert_null(bad.search(AppInfo.changelog_text(lang)), "Novità " + lang)
	var meta := FileAccess.get_file_as_string("res://version.json") + FileAccess.get_file_as_string("res://changelog.json")
	assert_null(bad.search(meta), "version.json / changelog.json")


func test_il_marchio_non_porta_piu_la_fase() -> void:
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		var s: String = Loc.tf("UI_FB_VERSION", {"v": AppInfo.version_label(), "build": AppInfo.build()})
		assert_false(s.to_lower().contains("alfa"))
		assert_string_contains(s, "1.0.0")


# ------------------------------------------------------------------ stringhe

func test_stringhe_m10_presenti_in_entrambe_le_lingue_e_usate_nel_codice() -> void:
	var have := {}
	for r in _csv_rows():
		have[str(r[0])] = r
	var re := RegEx.create_from_string("\"(UI_M10_[A-Z0-9_]+)\"")
	var used := {}
	for p in ["res://src/ui/start/StartScreen.gd", "res://src/ui/start/SlotSummary.gd", "res://src/feedback/PauseMenu.gd",
			"res://src/ui/screens/CreditsView.gd", "res://src/ui/main/MainScreen.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(p)):
			used[m.get_string(1)] = true
	assert_gt(used.size(), 30)
	for k in used:
		assert_true(have.has(k), "chiave mancante nel CSV: " + k)
		if have.has(k):
			assert_ne(str(have[k][1]).strip_edges(), "", k + " EN vuoto")
			assert_ne(str(have[k][2]).strip_edges(), "", k + " IT vuoto")
	for k in ["UI_M10_COOP", "UI_M10_LOADING", "UI_M10_PAUSE_SAVE", "UI_M10_SLOT_RESTORE"]:
		for lang in ["it", "en"]:
			Settings.set_value("locale", lang)
			assert_ne(tr(k), k, "%s nuda in %s" % [k, lang])


func test_italiano_neutro_rispetto_al_genere_nei_testi_nuovi() -> void:
	var bad := RegEx.create_from_string("(?i)\\b(benvenut[oa]|pront[oa]|stanc[oa]|sicur[oa] di|contento|contenta)\\b")
	for r in _csv_rows():
		if str(r[0]).begins_with("UI_M10_") or str(r[0]).begins_with("UI_FB_"):
			assert_null(bad.search(str(r[2])), "%s: %s" % [r[0], str(r[2]).left(80)])


# ------------------------------------------------------------------ titolo

func test_key_art_e_identica_al_file_dello_store() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path("res://store/store_keyart_wide.png"))
	var b := (load("res://assets/ui/title/title_keyart.png") as Texture2D).get_image()
	assert_not_null(a)
	assert_eq(a.get_size(), b.get_size(), "regola D-6: la dimensione del PNG non cambia")
	assert_eq(a.get_data(), b.get_data(), "regola D-6: i pixel non cambiano")


func test_titolo_voci_nell_ordine_giusto() -> void:
	var s := await _start()
	var menu := s.get_node("Margin/Stage/Menu")
	var names: Array = []
	for c in menu.find_children("*", "Button", true, false):      # Nuova/Cooperativa e Impostazioni/Crediti stanno in due righe
		names.append(str(c.name))
	assert_eq(names, ["ContinueButton", "NewGameButton", "CoopButton", "SettingsButton", "CreditsButton", "QuitButton"])
	assert_not_null(s.get_node("KeyArt"))
	assert_eq((s.get_node("KeyArt") as TextureRect).stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	assert_string_contains((s.get_node("Footer/VersionLabel") as Label).text, "1.0.0")
	assert_false(s.find_child("NewsButton", true, false) == null)


func test_titolo_scala_con_la_finestra_e_sta_nello_schermo() -> void:
	var s := await _start()
	var sizes := [Vector2(1024, 576), Vector2(1280, 720), Vector2(1536, 864)]
	var last_w := 0.0
	for v in sizes:
		s.set_anchors_preset(Control.PRESET_TOP_LEFT)
		s.size = v
		s.call("_apply_layout")
		await wait_process_frames(2)
		var menu := s.get_node("Margin/Stage/Menu") as Control
		var title := s.get_node("Margin/Stage/Menu/TitleBox/Title") as Control
		var tw := title.offset_right - title.offset_left
		assert_gte(tw, last_w, "il logo non rimpicciolisce con lo schermo")
		last_w = tw
		assert_lte(menu.get_combined_minimum_size().y, v.y - 20.0, "il menù sta in %s" % str(v))
	assert_gt(last_w, 104.0 * 5.0, "a 1536×864 logici (1080p e 4K) il logo è molto più grande dell'originale")


func test_senza_partite_continua_e_grigio_e_invita_a_cominciare() -> void:
	var s := await _start()
	assert_true((s.get_node("%ContinueButton") as Button).disabled)
	assert_eq(s._home_body.text, tr("UI_UXA_START_FIRST_BODY"))


func test_continua_mostra_l_ultima_partita_sotto_il_pulsante() -> void:
	_make_slot(2)
	var s := await _start()
	assert_false((s.get_node("%ContinueButton") as Button).disabled)
	assert_string_contains(s._home_body.text, "2")
	assert_string_contains(s._home_body.text, tr("UI_M10_TOTAL_LEVEL_SHORT").replace("{n}", "").strip_edges())


func test_caricamento_breve_e_cambio_scena_via_segnale_nei_test() -> void:
	var s := await _start()
	watch_signals(s)
	s.start_new(1)
	assert_signal_emitted_with_parameters(s, "navigate", [MAIN])
	s._show_loading()
	assert_true(s.is_loading(), "la schermata di caricamento si vede")
	s._hide_loading()
	assert_false(s.is_loading())


# ------------------------------------------------------------------ cooperativa

func test_cooperativa_senza_partita_spiega_cosa_fare() -> void:
	var s := await _start()
	s._on_coop()
	assert_eq(s._message.text, tr("UI_M10_COOP_NEEDS_GAME"))
	assert_eq(MenuIntent.screen, "")


func test_cooperativa_bloccata_non_carica_nulla() -> void:
	_make_slot(1)
	var s := await _start()
	watch_signals(s)
	s._on_coop()
	assert_eq(s._message.text, tr("UI_M10_COOP_LOCKED"))
	assert_signal_not_emitted(s, "navigate")
	assert_false(GameState.active)


func test_cooperativa_sbloccata_carica_e_apre_la_lobby() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	(GameState.data.unlocks as Array).append("feature:coop")
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	SlotSummary.invalidate()
	var s := await _start()
	watch_signals(s)
	s._on_coop()
	assert_signal_emitted_with_parameters(s, "navigate", [MAIN])
	assert_eq(MenuIntent.screen, "coop_lobby")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, 900)
	await wait_process_frames(4)
	assert_eq(main.current_id, "coop_lobby", "la partita si apre sulla Lobby")
	assert_eq(MenuIntent.screen, "", "l'intento si consuma")


# ------------------------------------------------------------------ slot

func test_riepilogo_slot_ha_classe_capitolo_tempo_e_data() -> void:
	Settings.set_value("locale", "it")
	_make_slot(1)
	var info := SlotSummary.get_info(1)
	assert_true(info.ok)
	assert_eq(info.mode, "normal")
	assert_gt(int(info.saved_at_unix), 0)
	assert_eq(int(info.chapter), 0, "la partita comincia dal Prologo")
	assert_string_contains(SlotSummary.chapter_label(0), "Prologo")
	assert_false(SlotSummary.chapter_label(0).contains("("), "senza la battuta tra parentesi")
	assert_eq(SlotSummary.headline(info).split(" · ")[0], "Guerriero", "la classe iniziale")
	assert_eq(SlotSummary.headline({"ok": true, "class_id": "", "chapter": -1}), tr("UI_M10_NO_CLASS"), "senza classe lo dice")
	var det := SlotSummary.details(info)
	assert_string_contains(det, tr("UI_TOTAL_LEVEL"))
	assert_false(det.contains("0,0 s"), "niente «Giocato 0,0 s»")
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		var d := SlotSummary.format_date(1793318400)
		assert_false(d.contains("-"), "niente data ISO: " + d)
		assert_string_contains(d, "2026")


func test_riepilogo_con_classe() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	GameState.data.hero["class"] = "warrior"
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	SlotSummary.invalidate()
	Settings.set_value("locale", "it")
	assert_eq(SlotSummary.class_label(SlotSummary.get_info(1)), "Guerriero")
	assert_string_contains(SlotSummary.headline(SlotSummary.get_info(1)), "Guerriero")


func test_cache_una_sola_decodifica_finche_i_file_non_cambiano() -> void:
	_make_slot(1)
	var n0 := SlotSummary.decode_count
	for i in 6:
		SlotSummary.get_info(1)
	assert_eq(SlotSummary.decode_count, n0 + 1, "sei richieste, una sola lettura completa")
	var s := await _start()
	var n1 := SlotSummary.decode_count
	s.show_slots()
	s.show_slots()
	s._refresh_continue()
	s.best_slot()
	assert_eq(SlotSummary.decode_count, n1, "il menù e le carte riusano la cache")
	# il file cambia: la cache si accorge
	assert_true(Game.load_game(1).ok)
	GameState.data.stats["playtime_s"] = 4242.0
	SaveService.last_saved_unix += 1
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var info := SlotSummary.get_info(1)
	assert_eq(int(float(info.playtime_s)), 4242, "dopo un nuovo salvataggio il riepilogo è aggiornato")
	assert_gt(SlotSummary.decode_count, n1)


func _corrupt_main(slot: int) -> void:
	var f := FileAccess.open(SaveService.slot_path(slot), FileAccess.WRITE)
	f.store_string("questo non e' un salvataggio")
	f.close()
	SlotSummary.invalidate(slot)


func test_slot_con_file_principale_danneggiato_propone_il_ripristino() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	assert_true(SaveService.save_now())
	GameState.data.stats["playtime_s"] = 100.0
	SaveService.last_saved_unix += 1
	assert_true(SaveService.save_now())          # ora esiste bak1
	Game.stop_game(false)
	assert_true(FileAccess.file_exists(SaveService.backup_path(1, 1)))
	_corrupt_main(1)
	var info := SlotSummary.get_info(1)
	assert_true(info.ok, "i dati si leggono dalla copia di sicurezza")
	assert_true(info.recovered)
	var s := await _start()
	s.show_slots()
	await wait_process_frames(1)
	var card := s.find_child("Slot1", true, false)
	assert_not_null(card)
	var restore := card.find_child("RestoreButton", true, false) as Button
	assert_not_null(restore, "«Ripristina la copia» invece del solo «Elimina»")
	assert_not_null(card.find_child("DeleteButton", true, false))
	# conferma, poi ripristino: il file rovinato resta per l'assistenza
	restore.pressed.emit()
	var c := s.get_node("Confirm") as ConfirmationDialog
	assert_true(c.visible)
	assert_eq(c.get_ok_button().text, tr("UI_M10_SLOT_RESTORE"))
	c.hide()
	s._restore_slot(1, int(str(info.source).substr(3)))
	var after := SlotSummary.get_info(1)
	assert_true(after.ok and not after.recovered, "ora il file principale è sano")
	assert_true(FileAccess.file_exists(SaveService.slot_path(1) + SlotSummary.CORRUPT_SUFFIX), "il file danneggiato non si butta")
	assert_eq(s._slot_note, tr("UI_M10_RESTORE_DONE"))


func test_slot_illeggibile_senza_backup_spiega_e_offre_esportazione() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	for n in range(1, SaveService.BACKUPS + 1):
		DirAccess.remove_absolute(SaveService.backup_path(1, n))
	for extra in SaveService.day_copies(1):      # anche le copie giornaliere e pre-migrazione: qui non ci deve essere NESSUN ripiego
		DirAccess.remove_absolute(str(extra))
	for extra in SaveService.pre_migration_copies(1):
		DirAccess.remove_absolute(str(extra))
	_corrupt_main(1)
	assert_false(SlotSummary.get_info(1).ok)
	var s := await _start()
	s.show_slots()
	await wait_process_frames(1)
	var card := s.find_child("Slot1", true, false)
	assert_null(card.find_child("RestoreButton", true, false), "nessuna copia utilizzabile: niente ripristino finto")
	assert_not_null(card.find_child("SupportExportButton", true, false))
	assert_not_null(card.find_child("DeleteButton", true, false))
	var texts := ""
	for l in card.find_children("*", "Label", true, false):
		texts += (l as Label).text + "\n"
	assert_string_contains(texts, tr("UI_M10_SLOT_NO_BACKUP"))
	var dest := "user://test_menu_1_0_export_%d" % Time.get_ticks_usec()
	var out := SlotSummary.export_for_support(1, dest)
	assert_ne(out, "")
	assert_true(FileAccess.file_exists(out))
	DirAccess.remove_absolute(out)
	DirAccess.remove_absolute(dest)


func test_slot_vuoto_e_carte_senza_battute() -> void:
	var s := await _start()
	s.show_slots()
	await wait_process_frames(1)
	var info := SlotSummary.get_info(3)
	assert_eq(s.describe_slot(info), tr("UI_SLOT_EMPTY"))
	assert_null(s.find_child("Slot3", true, false).find_child("DeleteButton", true, false), "uno slot libero non ha «Elimina»")


func test_conferma_sovrascrittura_e_eliminazione_hanno_pulsante_di_pericolo() -> void:
	_make_slot(1)
	var s := await _start()
	s.show_slots()
	s._on_new_in_slot(1, true)
	var c := s.get_node("Confirm") as ConfirmationDialog
	assert_true(c.visible)
	assert_true(c.get_ok_button().has_theme_stylebox_override("normal"), "pulsante rosso per l'azione distruttiva")
	assert_string_contains(c.dialog_text, tr("UI_OVERWRITE_CONFIRM"))
	c.hide()
	s._ask_delete(1)
	assert_true(c.visible)
	assert_string_contains(c.dialog_text, SlotSummary.headline(SlotSummary.get_info(1)))
	c.hide()
	s._restore_slot(1, 1)             # un ripristino senza copie non è distruttivo
	s._open_confirm("UI_M10_RESTORE_TITLE", "UI_M10_SLOT_RESTORE", "x", Callable(), false)
	assert_false(c.get_ok_button().has_theme_stylebox_override("normal"), "ripristino: stile normale")
	c.hide()


func test_sovrascrivere_non_cancella_senza_conferma() -> void:
	_make_slot(1)
	var s := await _start()
	s.show_slots()
	s._on_new_in_slot(1, true)
	assert_false(GameState.active, "prima della conferma non succede nulla")
	(s.get_node("Confirm") as ConfirmationDialog).hide()
	assert_true(SlotSummary.get_info(1).ok, "lo slot è intatto")


func test_cancella_slot_toglie_anche_il_file_danneggiato_e_aggiorna_la_cache() -> void:
	_make_slot(2)
	assert_true(SlotSummary.get_info(2).ok)
	var s := await _start()
	s._delete_slot(2)
	assert_false(SlotSummary.get_info(2).exists)


# ------------------------------------------------------------------ pausa

func test_menu_di_pausa_voci_e_salvataggio() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	await wait_process_frames(2)
	var names := []
	for b in pm.find_children("*", "Button", true, false):
		names.append(b.name)
	for n in ["ResumeButton", "SaveButton", "SettingsButton", "ManualButton", "ReportButton", "MainMenuButton", "QuitButton"]:
		assert_true(names.has(n), n)
	assert_eq(names[0], "ResumeButton", "«Riprendi» per primo (focus iniziale)")
	(pm.find_child("SaveButton", true, false) as Button).pressed.emit()
	assert_eq((pm.find_child("Status", true, false) as Label).text, tr("UI_M10_PAUSE_SAVED"))
	assert_true(FileAccess.file_exists(SaveService.slot_path(1)), "«Salva adesso» ha scritto lo slot")


func test_esc_apre_e_chiude_il_menu_di_pausa_e_ferma_l_orologio() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, 900)
	await wait_process_frames(2)
	var was := Clock.paused
	assert_true(main.run_shortcut({"type": "escape"}))
	assert_true(Feedback.is_pause_menu_open())
	assert_true(Clock.paused, "in pausa l'orologio è fermo")
	var k := InputEventKey.new()
	k.keycode = KEY_B
	k.pressed = true
	main._unhandled_key_input(k)
	assert_ne(main.current_id, "bank", "con il menù aperto i tasti non arrivano alla schermata sotto")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main._unhandled_key_input(esc)
	assert_false(Feedback.is_pause_menu_open(), "Esc lo chiude")
	assert_eq(Clock.paused, was, "e l'orologio torna com'era")


func test_menu_principale_dalla_pausa_salva_e_chiude_la_partita() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	await wait_process_frames(2)
	(pm.find_child("MainMenuButton", true, false) as Button).pressed.emit()
	assert_false(GameState.active)
	assert_true(FileAccess.file_exists(SaveService.slot_path(1)))


# ------------------------------------------------------------------ crediti

func test_crediti_completi_e_licenze_in_forma_pubblica() -> void:
	var have := {}
	for r in _csv_rows():
		have[str(r[0])] = r
	var all_keys := PackedStringArray()
	for sec in CreditsView.SECTIONS:
		if str(sec[0]) != "":
			all_keys.append(str(sec[0]))
		for k in sec[1]:
			all_keys.append(str(k))
	for sec in CreditsView.LICENSE_SECTIONS:
		all_keys.append(str(sec[0]))
		all_keys.append(str(sec[1]))
	for k in all_keys:
		assert_true(have.has(k), "manca " + k)
	var text := ""
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		for k in all_keys:
			text += tr(k) + "\n"
		assert_string_contains(tr("UI_M10_LIC_GODOT"), "Permission is hereby granted")
		assert_string_contains(tr("UI_M10_LIC_FONTS"), "SIL Open Font License")
	for needle in ["Godot", "Atkinson", "Departure Mono", "Claude", "VAULTFALL"]:
		assert_string_contains(text, needle)
	assert_false(text.to_lower().contains("da verificare"), "niente note interne in forma pubblica")
	assert_false(text.to_lower().contains("dafne"), "niente dediche personali")


func test_crediti_hanno_pulsante_licenze_e_margine_per_la_barra() -> void:
	var v := CreditsView.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	var b := v.find_child("LicensesButton", true, false) as Button
	assert_not_null(b)
	var scroll := v.find_child("CreditsScroll", true, false) as ScrollContainer
	assert_gte((scroll.get_child(0) as MarginContainer).get_theme_constant("margin_right"), 12, "margine destro: la barra non copre il testo")
	var d := CreditsView.show_licenses(self)
	await wait_process_frames(2)
	assert_true(d.visible)
	assert_not_null(d.find_child("*", true, false))
	d.queue_free()


func test_schermata_crediti_dal_titolo() -> void:
	var s := await _start()
	s.show_credits()
	await wait_process_frames(2)
	assert_true((s.get_node("%Panel") as Control).visible)
	assert_false((s.get_node("Margin/Stage/Menu") as Control).visible, "il pannello prende il posto del menù")
	s._unhandled_input(_cancel())
	assert_false((s.get_node("%Panel") as Control).visible, "Esc torna al menù")


func _cancel() -> InputEventAction:
	var a := InputEventAction.new()
	a.action = "ui_cancel"
	a.pressed = true
	return a
