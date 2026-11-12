extends GutTest
## EventsScreen (T-11.3): evento in corso/prossimo con conto alla rovescia, missioni, Negozio, Cassa con probabilità, Eco, interruttore.

const SCENE := "res://src/ui/screens/EventsScreen.tscn"

var _old_dir: String
var _old_locale: String
var _sys: SeasonalEventSystem


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_locale = TranslationServer.get_locale()
	SaveService.save_dir = "user://test_seasonal_ui_saves"
	SaveService.autosave_enabled = false
	TranslationServer.set_locale("en")
	assert_true(Game.new_game(1, "normal", 515))
	_sys = Game.system("seasonal") as SeasonalEventSystem
	_sys.set_wall(SeasonalEventSystem.unix_of(2026, 10, 25, 12), 0)
	(Game.system("unlock") as UnlockSystem).grant("feature:crates")


func after_each() -> void:
	_sys.wall_source = SeasonalEventSystem.system_wall
	Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	TranslationServer.set_locale(_old_locale)


func _screen() -> GameScreen:
	var scr: GameScreen = load(SCENE).instantiate()
	add_child_autofree(scr)
	scr.open({})
	scr.refresh()
	return scr


func _texts(n: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if n is Label:
		out.append(tr((n as Label).text))
	elif n is Button:
		out.append(tr((n as Button).text))
	for c in n.get_children():
		_texts(c, out)
	return out


func _buttons(n: Node, out: Array = []) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)
	return out


func _has(texts: PackedStringArray, needle: String) -> bool:
	for t in texts:
		if t.contains(needle):
			return true
	return false


func test_registrata_nel_menu_e_con_scena() -> void:
	var found := false
	for e in ScreenRegistry.entries():
		if e.id == "events":
			found = true
			assert_true(ResourceLoader.exists(str(e.scene)))
			assert_eq(e.unlock, "feature:crates")
	assert_true(found)


func test_evento_in_corso_con_conto_alla_rovescia_missioni_negozio_e_probabilita() -> void:
	var scr := _screen()
	var t := _texts(scr)
	assert_true(_has(t, "Happening now: Lantern Night"))
	assert_true(_has(t, "Ends in"))
	assert_true(_has(t, "Missions"))
	assert_true(_has(t, "Shop: fixed prices"))
	assert_true(_has(t, "Odds, exactly what the draw uses"))
	assert_true(_has(t, "%"), "probabilità visibili")
	assert_true(_has(t, "Temporary bonus"))
	assert_true(_has(t, "Missed something? You lose nothing"))
	for line in t:
		assert_false(line.begins_with("UI_"), "chiave non tradotta: " + line)
	var odds_lines := 0
	for line in t:
		if line.contains("items)") or line.contains(" item)"):     # «1 item» al singolare (Loc.fix_plural)
			odds_lines += 1
	assert_eq(odds_lines, _sys.crate_odds("lantern_night").size())


func test_italiano() -> void:
	TranslationServer.set_locale("it")
	var scr := _screen()
	var t := _texts(scr)
	assert_true(_has(t, "In corso: Notte delle Lanterne"))
	assert_true(_has(t, "Missioni"))
	assert_true(_has(t, "Probabilità"))


func test_fuori_dalle_date_prossimo_evento_ed_eco() -> void:
	_sys.set_wall(SeasonalEventSystem.unix_of(2026, 6, 1, 12), 0)
	var scr := _screen()
	var t := _texts(scr)
	assert_true(_has(t, "No event right now") or _has(t, "Echo of"), "stato fuori dalle date")
	assert_true(_has(t, "Next: Sun Regatta"), "prossimo evento con conto alla rovescia")
	# scelgo un altro evento e lo metto in Eco
	for b in _buttons(scr):
		if (b as Button).text == "Frost Feast":
			(b as Button).pressed.emit()
	scr.refresh()
	var btn: Button = null
	for b in _buttons(scr):
		if (b as Button).text == tr("UI_EVENTS_ECHO_USE"):
			btn = b
	assert_not_null(btn)
	if btn == null:
		return
	btn.pressed.emit()
	scr.refresh()
	assert_eq(_sys.echo_event(), "frost_feast")


func test_riscuote_missione_e_compra_dal_negozio() -> void:
	var scr := _screen()
	EventBus.monsters_killed_batch.emit("mud_slime", 100, [])
	scr.refresh()
	var claim: Button = null
	for b in _buttons(scr):
		if tr((b as Button).text).begins_with("Claim +") and not (b as Button).disabled:
			claim = b
	assert_not_null(claim, "missione completata: pulsante attivo")
	if claim == null:
		return
	claim.pressed.emit()
	assert_eq((Game.system("bank") as BankSystem).count("event_wax"), 10)
	scr.refresh()
	var buy: Button = null
	for b in _buttons(scr):
		if tr((b as Button).text) == "Buy for 25":
			buy = b
	assert_not_null(buy, "pulsante di acquisto del primo cosmetico")
	if buy == null:
		return
	assert_true(buy.disabled, "10 unità non bastano ancora per 25")
	(Game.system("bank") as BankSystem).add("event_wax", 30, "test")
	scr.refresh()
	buy = null
	for b in _buttons(scr):
		if tr((b as Button).text) == "Buy for 25" and not (b as Button).is_queued_for_deletion():
			buy = b
	assert_false(buy.disabled)
	buy.pressed.emit()
	assert_true(_sys.is_owned("item", "cosmetic_event_lantern_night_1"))


func test_interruttore_eventi() -> void:
	var scr := _screen()
	var off: Button = null
	for b in _buttons(scr):
		if tr((b as Button).text) == "Turn events off":
			off = b
	assert_not_null(off)
	if off == null:
		return
	off.pressed.emit()
	scr.refresh()
	assert_false(_sys.events_enabled())
	var t := _texts(scr)
	assert_true(_has(t, "Events are turned off"))
	assert_true(_has(t, "Nothing is lost"))
	var on: Button = null
	for b in _buttons(scr):
		if tr((b as Button).text) == "Turn events on":
			on = b
	assert_not_null(on)
	if on == null:
		return
	on.pressed.emit()
	scr.refresh()
	assert_true(_sys.events_enabled())


func test_interruttore_nelle_impostazioni() -> void:
	var scene: PackedScene = load("res://src/ui/screens/SettingsScreen.tscn")
	var scr: Node = scene.instantiate()
	add_child_autofree(scr)
	scr.call("open", {})
	var box: CheckBox = null
	for n in scr.find_children("*", "CheckBox", true, false):
		if (n as CheckBox).tooltip_text == "UI_EVENTS_SETTING_HINT":
			box = n
	assert_not_null(box, "interruttore degli eventi nelle Impostazioni")
	if box == null:
		return
	assert_true(box.button_pressed)
	box.button_pressed = false
	assert_false(_sys.events_enabled())
