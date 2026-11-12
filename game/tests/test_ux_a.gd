extends GutTest
## QA-UX gruppo A: scheda «Adesso» del Riepilogo, frecce dei pulsanti a scomparsa, colonna destra del menù iniziale,
## valori degli slider nelle Impostazioni, avviso Deposito pieno, semi predefiniti del Giardino, plurali del Bentornato.

const START := "res://src/ui/start/StartScreen.tscn"
const SUMMARY := "res://src/ui/screens/SummaryScreen.tscn"
const SKILL := "res://src/ui/screens/SkillScreen.tscn"
const FARM := "res://src/ui/screens/FarmScreen.tscn"
const SETTINGS := "res://src/ui/screens/SettingsScreen.tscn"

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ux_a_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 7))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String, params: Dictionary = {}) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	return s


func test_disclosure_freccia_e_testo() -> void:
	assert_true(Disclosure.label("UI_SKILLS_PERKS", false).begins_with(Disclosure.CLOSED))
	assert_true(Disclosure.label("UI_SKILLS_PERKS", true).begins_with(Disclosure.OPEN))
	assert_true(Disclosure.label("UI_SKILLS_PERKS", true).ends_with(tr("UI_SKILLS_PERKS")))


func test_riepilogo_scheda_adesso_a_riposo_e_missione() -> void:
	var s := _open(SUMMARY)
	await wait_process_frames(2)
	s.refresh()
	assert_eq(s._now_l.text, tr("UI_UXA_NOW_IDLE"), "senza attività si dice cosa fare")
	assert_true(s._step_title.text.contains(QuestText.title(
			(Game.system("quests") as QuestSystem).quest_def((Game.system("quests") as QuestSystem).current_main()))), "titolo della missione principale")
	assert_true(s._step_btn.visible and s._step_bar.visible, "barra e pulsante verso le Missioni")
	var sk := Game.system("skills") as SkillSystem
	sk.start("wc_pine")
	s.refresh()
	assert_true(s._now_l.text.contains(ActivityText.text()), "mostra la mansione in corso")
	assert_true(ActivityText.is_active())


func test_menu_iniziale_colonna_destra() -> void:
	Game.stop_game(false)
	SaveService.delete_slot(1)
	var start: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(2)
	assert_true(start._home.visible, "a riposo sotto Continua c'è l'invito a cominciare")
	assert_eq(start._home_body.text, tr("UI_UXA_START_FIRST_BODY"), "senza salvataggi: invito, non una partita")
	start.show_slots()
	assert_false(start._home.is_visible_in_tree(), "con gli slot aperti il menù lascia il posto")
	assert_false(start.get_node("%ContinueButton").has_focus() and start.get_node("%ContinueButton").disabled)


func test_impostazioni_slider_con_valore() -> void:
	var s := _open(SETTINGS)
	await wait_process_frames(1)
	var found := 0
	for l in s.find_children("*", "Label", true, false):
		if (l as Label).text.ends_with("%"):
			found += 1
	assert_gte(found, 5, "i volumi mostrano la percentuale (la dimensione interfaccia è una scelta Automatica/percentuali, F5)")


func test_mansione_avviso_deposito_pieno() -> void:
	var s := _open(SKILL, {"skill": "woodcutting"})
	await wait_process_frames(1)
	s.refresh()
	assert_false(s._full_l.visible)
	var bank := Game.system("bank") as BankSystem
	for id in DataRegistry.all_items():
		if bank.is_full():
			break
		bank.add(str(id), 1, "test")
	assert_true(bank.is_full())
	s.refresh()
	assert_true(s._full_l.visible, "Deposito pieno: avviso sulla mansione")


func test_giardino_seme_predefinito_non_bloccato() -> void:
	var s := _open(FARM)
	await wait_process_frames(1)
	s.refresh()
	for kind in s._sections:
		var opt: OptionButton = s._sections[kind].opt
		var any_ok := false
		for i in opt.item_count:
			any_ok = any_ok or not opt.is_item_disabled(i)
		if any_ok:
			assert_false(opt.is_item_disabled(opt.selected), "il seme scelto di default è usabile al tuo livello: " + str(kind))


func test_bentornato_plurali_al_singolare() -> void:
	var rep := {"market": {"orders": 1, "gazette_total": 1}}
	var n := WelcomeBack.normalize(rep, DataRegistry)
	var keys: Array = []
	for r in n.market.rows:
		keys.append(r.key)
	assert_true(keys.has("UI_UXA_WB_ORDERS_ONE"))
	assert_true(keys.has("UI_UXA_WB_GAZETTE_ONE"))
	var rep2 := {"market": {"orders": 3, "gazette_total": 2}}
	var n2 := WelcomeBack.normalize(rep2, DataRegistry)
	assert_eq(n2.market.rows[0].key, "UI_INTEG_WB_ORDERS")
