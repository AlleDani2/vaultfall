extends GutTest
## COOP-1: la schermata «Amici» (partita vera): voce di menù sbloccata da feature:coop, codice da copiare, incolla e importa,
## compagni, Prova della settimana e classifica locale, messaggi di errore tradotti.

const Env := preload("res://tests/helpers/coop_env.gd")
const NOW := 1760000000

var _old_dir: String
var _old_auto: bool


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_coop_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Env.free_all()
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _screen() -> GameScreen:
	var s: GameScreen = (load("res://src/ui/screens/CoopScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _friend_code() -> String:
	var f: Object = Env.make(9, 55, "ranger", 6, 1700999999)
	f.coop.set_my_name("Giulia")
	return f.coop.export_hero_code(int(Time.get_unix_time_from_system()))


func test_voce_di_menu_sbloccata_da_feature_coop() -> void:
	var e := ScreenRegistry.get_entry("coop", DataRegistry)
	assert_false(e.is_empty())
	assert_eq(e.section, "progress")
	assert_eq(e.unlock, "feature:coop")
	assert_true(ResourceLoader.exists(e.scene))
	assert_false(ScreenRegistry.is_available(e, []))
	assert_true(ScreenRegistry.is_available(e, ["feature:coop"]))
	assert_ne(tr("UI_MENU_COOP"), "UI_MENU_COOP", "titolo tradotto")


func test_il_primo_raid_sbloccato_apre_la_voce_amici() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	assert_false((GameState.data.unlocks as Array).has("feature:coop"))
	(GameState.data.unlocks as Array).append("raid:collectors_den")
	for i in 15:
		Game.sim.tick(0.1)
	assert_true((GameState.data.unlocks as Array).has("feature:coop"))


func test_schermata_copia_il_codice_importa_e_mostra_i_compagni() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var s := _screen()
	s.open({})
	await wait_process_frames(2)
	s.refresh()
	assert_not_null(s._code_out)
	s._name_edit.text = "Developer"
	s._on_copy_mine()
	assert_true(s._code_out.text.begins_with("VFH1."), "il codice compare nella casella")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		assert_eq(DisplayServer.clipboard_get(), s._code_out.text, "e va negli appunti")
	assert_eq((Game.system("coop") as CoopSystem).my_name(), "Developer")
	assert_ne(s._copied.text, "")
	# incolla un codice rovinato: messaggio d'errore, nessun compagno
	s._paste.text = "VFH1.QUJDRA=="
	s._on_import()
	assert_ne(s._feedback.text, "")
	assert_false(s._feedback.text.begins_with("UI_COOP_ERR"), "errore tradotto, non la chiave")
	assert_eq((Game.system("coop") as CoopSystem).companions().size(), 0)
	for e in get_errors():
		e.handled = true
	# incolla un codice buono
	s._paste.text = _friend_code()
	s._on_import()
	var co := Game.system("coop") as CoopSystem
	assert_eq(co.companions().size(), 1)
	assert_eq(s._paste.text, "", "la casella si svuota")
	assert_true(s._feedback.text.contains("Giulia"))
	s.refresh()
	await wait_process_frames(2)
	assert_eq(s._comp_col.get_child_count(), 2, "la regola e una riga per il compagno")
	# interruttore e congedo
	var cid: String = str(co.companions()[0].id)
	co.set_enabled(cid, false)
	s.refresh()
	assert_false(co.companions()[0].enabled)
	co.remove_companion(cid)
	s.refresh()
	await wait_process_frames(2)
	assert_eq(co.companions().size(), 0)


func test_prova_della_settimana_e_classifica_nella_schermata() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 60, "record_level": 60, "stars": 0, "perks": {}, "unlocked": true}
	var co := Game.system("coop") as CoopSystem
	var s := _screen()
	s.open({})
	await wait_process_frames(2)
	s.refresh()
	assert_false(co.rift_unlocked(), "la Breccia è ancora chiusa")
	s.refresh()
	(GameState.data.unlocks as Array).append("feature:rift")
	s._sig_week = ""
	s.refresh()
	assert_true(co.rift_unlocked())
	s._on_week_run()
	s.refresh()
	await wait_process_frames(2)
	var wk := CoopWeekly.week_of(int(Time.get_unix_time_from_system()))
	assert_false(co.my_result(str(wk.id)).is_empty(), "risultato registrato")
	assert_eq(co.leaderboard(str(wk.id)).size(), 1)
	assert_gt(s._board_col.get_child_count(), 1)
	s._on_copy_result(str(wk.id))
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		assert_true(DisplayServer.clipboard_get().begins_with("VFR1."))
	else:
		assert_true(s._result_msg.begins_with("VFR1."), "senza appunti il codice si mostra a video")
	# la classifica si aggiorna con il risultato di un amico incollato nella casella
	var friend := {"uid": "00000000000000cd", "name": "Marco", "class": "arcanist", "spec": "", "level": 80, "week": str(wk.id),
		"floor": 40, "t": 900.0, "dmg": 5.0e9, "issued": int(Time.get_unix_time_from_system())}
	s._paste.text = CoopCodec.pack("R", 1, friend)
	s._on_import()
	s.refresh()
	await wait_process_frames(2)
	var lb := co.leaderboard(str(wk.id))
	assert_eq(lb.size(), 2)
	assert_eq(lb[0].name, "Marco", "40 piani battono il tuo risultato")
	assert_true(s._feedback.text.contains("Marco"))


func test_apertura_a_partita_nuova_senza_errori() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var s := _screen()
	s.open({})
	for i in 5:
		s.refresh()
		await wait_process_frames(1)
	s.close()
	assert_true(true)
