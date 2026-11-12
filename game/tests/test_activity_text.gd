extends GutTest
## ActivityText: testo dell'attività corrente. Difetto I1: con la Breccia (zona senza nome) non devono comparire
## separatori doppi, iniziali o finali, né in italiano né in inglese.

var _old_dir: String
var _old_locale: Variant
var _old_ts_locale: String = ""
var _old_tut: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_activity_text_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_locale = Settings.get_value("locale")
	_old_ts_locale = TranslationServer.get_locale()
	_old_tut = Settings.get_value("tutorials")
	Settings.set_value("tutorials", false)
	assert_true(Game.new_game(1, "normal", 7))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("locale", _old_locale)
	TranslationServer.set_locale(_old_ts_locale)
	Settings.set_value("tutorials", _old_tut)


func _set_act(d: Dictionary) -> void:
	var a: Dictionary = GameState.data.activity
	a.clear()
	a.merge(d)


func _assert_clean(t: String, ctx: String) -> void:
	assert_false(t.is_empty(), ctx + ": non vuoto")
	assert_false(t.contains("· ·"), ctx + ": niente doppio separatore -> " + t)
	assert_false(t.contains("·  ·"), ctx + ": niente doppio separatore spaziato -> " + t)
	assert_false(t.strip_edges().begins_with("·"), ctx + ": niente separatore iniziale -> " + t)
	assert_false(t.strip_edges().ends_with("·"), ctx + ": niente separatore finale -> " + t)
	assert_eq(t, t.strip_edges(), ctx + ": niente spazi ai bordi")


func test_riposo() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		_set_act({})
		assert_eq(ActivityText.text(), TranslationServer.translate("UI_SKILLS_TOPBAR_IDLE"))
		assert_false(ActivityText.is_active())


func test_mansione() -> void:
	var sk := Game.system("skills") as SkillSystem
	var aid := ""
	for id in DataRegistry.all_actions():
		if sk.can_start(str(id)).is_empty():
			aid = str(id)
			break
	assert_false(aid.is_empty(), "in una partita nuova almeno una mansione e' avviabile")
	if aid.is_empty():
		return
	assert_true(sk.start(aid))
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		_assert_clean(ActivityText.text(), "mansione " + loc)
		assert_true(ActivityText.is_active())


func test_combattimento_normale_e_casi_vuoti() -> void:
	var zone_id := "millbrook"
	var cases := {
		"normale": {"type": "combat", "mode": "zone", "zone": zone_id, "monster": "mud_slime"},
		"mostro a caso": {"type": "combat", "mode": "zone", "zone": zone_id, "monster": ""},
		"breccia": {"type": "combat", "mode": "rift", "zone": "", "monster": ""},
		"breccia con mostro": {"type": "combat", "mode": "rift", "zone": "", "monster": "mud_slime"},
		"boss mondiale": {"type": "combat", "mode": "wboss", "zone": "", "monster": "mud_slime"},
		"incursione": {"type": "combat", "mode": "raid", "zone": "", "monster": ""},
		"dungeon": {"type": "combat", "mode": "dungeon", "zone": "", "monster": ""},
		"zona sconosciuta": {"type": "combat", "mode": "zone", "zone": "non_esiste", "monster": "non_esiste"},
		"tutto vuoto": {"type": "combat", "mode": "", "zone": "", "monster": ""},
		"senza modo": {"type": "combat", "zone": "", "monster": ""},
	}
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for k in cases:
			_set_act(cases[k])
			_assert_clean(ActivityText.text(), "%s/%s" % [k, loc])
		_set_act(cases["normale"])
		var t := ActivityText.text()
		assert_true(t.contains(Loc.t(DataRegistry.get_def("zones", zone_id).name)), "contiene la zona: " + t)
		assert_true(t.contains(Loc.t(DataRegistry.get_def("monsters", "mud_slime").name)), "contiene il mostro: " + t)
		_set_act(cases["breccia"])
		var rift := ActivityText.text()
		assert_true(rift.contains(str(TranslationServer.translate("UI_RAID_TAB_RIFT"))), "Breccia con il suo nome: " + rift)
		_set_act(cases["boss mondiale"])
		assert_true(ActivityText.text().contains(str(TranslationServer.translate("UI_RAID_TAB_WB"))))
