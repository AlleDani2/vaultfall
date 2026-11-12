extends GutTest
## Revisione finale B (docs/review_1_0/33 F-8, docs/24 §7.1): la PRIMA volta che si ospita o si entra in una stanza coop il gioco
## chiede una conferma esplicita sull'indirizzo IP; la conferma è ricordata nelle impostazioni («coop_ip_ack») e non torna più.
## Un file di impostazioni di una versione precedente (senza la chiave) vale «mai confermato».

const MAIN := "res://src/ui/main/MainScreen.tscn"
const CSV_PATH := "res://localization/ui_strings.csv"

var _old_dir := ""
var _dir := ""
var _svc: CoopNetService
var _old_ack := false


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_dir = "user://test_ipack_%d" % Time.get_ticks_usec()
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false
	_svc = CoopNetService.instance()
	_svc.store.dir = _dir + "/coop"
	_old_ack = bool(Settings.get_value("coop_ip_ack"))
	Settings.set_value("coop_ip_ack", false)


func after_each() -> void:
	_svc.leave_room()
	if GameState.active:
		Game.stop_game(false)
	for gid in _svc.store.list_ids():
		_svc.store.delete(gid)
	DirAccess.remove_absolute(_dir + "/coop")
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	_svc.store.dir = CoopGuildStore.DEFAULT_DIR
	Settings.set_value("coop_ip_ack", _old_ack)


func _lobby() -> Node:
	assert_true(Game.new_game(1, "normal", 10))
	Game.system("unlock").grant("feature:coop")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_true(main.show_screen("coop_lobby"))
	await wait_process_frames(1)
	var lobby: Node = main.current_screen()
	lobby._nick.text = "Ale"
	lobby._gname.text = "Amici"
	lobby._port_host.value = 24920 + (Time.get_ticks_usec() % 50)
	return lobby


func test_il_default_e_non_confermato() -> void:
	assert_true(Settings.DEFAULTS.has("coop_ip_ack"))
	assert_false(bool(Settings.DEFAULTS["coop_ip_ack"]), "mai confermato di default")


func test_file_di_impostazioni_vecchio_senza_la_chiave_vale_non_confermato() -> void:
	var old_path := Settings.path
	var tmp := "user://test_ipack_settings_%d.cfg" % Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.SECTION, "number_format", "full")        # file di una versione precedente: altre chiavi, nessuna «coop_ip_ack»
	cfg.set_value(Settings.SECTION, "settings_rev", 2)
	assert_eq(cfg.save(tmp), OK)
	Settings.path = tmp
	Settings.load_settings()
	assert_false(bool(Settings.get_value("coop_ip_ack")), "chiave assente = non confermato")
	assert_eq(str(Settings.get_value("number_format")), "full", "le altre impostazioni restano")
	Settings.set_value("coop_ip_ack", true)
	Settings.load_settings()
	assert_true(bool(Settings.get_value("coop_ip_ack")), "la conferma è ricordata dopo la rilettura del file")
	Settings.path = old_path
	Settings.load_settings()
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(tmp + ".tmp")


func test_ospitare_la_prima_volta_chiede_conferma_e_non_apre_la_stanza() -> void:
	var lobby: Node = await _lobby()
	lobby._on_host()
	await wait_process_frames(1)
	assert_not_null(lobby.ip_ack_dialog, "finestra di conferma aperta")
	assert_eq(_svc.status, CoopNetService.ST_OFFLINE, "finché non confermi non si ospita nulla")
	assert_false(bool(Settings.get_value("coop_ip_ack")))
	lobby.ip_ack_dialog.canceled.emit()
	await wait_process_frames(1)
	assert_eq(_svc.status, CoopNetService.ST_OFFLINE, "annullare non ospita")
	assert_false(bool(Settings.get_value("coop_ip_ack")), "annullare non conta come conferma")


func test_confermare_ricorda_la_scelta_e_poi_non_chiede_piu() -> void:
	var lobby: Node = await _lobby()
	lobby._on_host()
	await wait_process_frames(1)
	var dlg: ConfirmationDialog = lobby.ip_ack_dialog
	assert_not_null(dlg)
	dlg.confirmed.emit()
	await wait_process_frames(1)
	assert_true(bool(Settings.get_value("coop_ip_ack")), "conferma ricordata")
	assert_eq(_svc.status, CoopNetService.ST_HOSTING, "dopo la conferma la stanza si apre")
	_svc.leave_room()
	await wait_process_frames(1)
	lobby._on_host()
	await wait_process_frames(1)
	assert_null(lobby.ip_ack_dialog, "la seconda volta nessuna finestra")
	assert_eq(_svc.status, CoopNetService.ST_HOSTING)


func test_entrare_la_prima_volta_chiede_conferma_prima_di_collegarsi() -> void:
	var lobby: Node = await _lobby()
	lobby._on_join()
	await wait_process_frames(1)
	assert_not_null(lobby.ip_ack_dialog, "anche per entrare serve la conferma")
	assert_eq(_svc.status, CoopNetService.ST_OFFLINE, "nessun collegamento prima della conferma")
	lobby.ip_ack_dialog.canceled.emit()


func test_testi_bilingui_della_conferma() -> void:
	var keys := {}
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			keys[row[0]] = row
	for k in ["UI_COOPNET_IPACK_TITLE", "UI_COOPNET_IPACK_TEXT", "UI_COOPNET_IPACK_OK"]:
		assert_true(keys.has(k), "chiave nel CSV: " + k)
		assert_false(str(keys[k][1]).is_empty() or str(keys[k][2]).is_empty(), "IT ed EN presenti: " + k)
	assert_true(str(keys["UI_COOPNET_IPACK_TEXT"][1]).contains("IP address"))
	assert_true(str(keys["UI_COOPNET_IPACK_TEXT"][2]).contains("indirizzo IP"))
