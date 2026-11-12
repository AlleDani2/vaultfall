extends GutTest
## Fase F9 del progetto di interfaccia (docs/ui_redesign/06 §3.10, §3.11, §3.15): Tenuta a schede con un solo avviso, Dungeon con il
## rischio come UN chip, Taglie con l'istruzione una volta sola. Ogni fatto compare in un posto solo (D18): qui si CONTANO i testi
## visibili (i tooltip non contano). Gli aspetti dei sistemi restano coperti dai test esistenti (test_estate_ui, test_combat2_ui, test_raids_ui).

var _old_dir: String
var _old_seen: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_estate_dungeon_layout_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_seen = Settings.get_value("seen_intro")
	Settings.set_value("seen_intro", [])
	TranslationServer.set_locale("it")


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("seen_intro", _old_seen)


# ------------------------------------------------------------------ strumenti

func _new_game() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 60, "record_level": 60, "stars": 0, "perks": {}, "unlocks": true, "unlocked": true}
	GameState.data.skills["bounty"] = {"xp": 0.0, "level": 5, "record_level": 5, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "dungeon:cursed_granary", "zone:saltreach", "feature:talents", "feature:bounties", "skill:hero",
		"feature:estate", "feature:prestige", "skill:cooking", "skill:mining", "skill:fishing", "feature:market", "raid:collectors_den", "feature:world_bosses", "feature:rift"])
	for b in EstateFixtures.ALL_BUILDINGS:
		(GameState.data.unlocks as Array).append("building:" + b)


func _estate(pantry: float) -> EstateSystem:
	var e := Game.system("estate") as EstateSystem
	var levels := {"cottage": 10, "sawmill": 12, "mine_shaft": 4, "shopfront": 3, "warehouse": 4, "private_vault": 2, "academy": 15, "tavern": 20}
	for bid in levels:
		e._entry(bid)["level"] = levels[bid]
	e.state.settlers = e.settler_cap()
	e.state.pantry = pantry
	e.set_pantry_auto(false)
	return e


func _screen(path: String, params: Dictionary = {}) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	return s


## Testi visibili della schermata (tradotti, senza bbcode). I tooltip non sono testi visibili.
func _visible_texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var t := ""
		if c is Label:
			t = (c as Label).text
		elif c is Button:
			t = (c as Button).text
		elif c is RichTextLabel:
			t = (c as RichTextLabel).get_parsed_text()
		if t != "":
			out.append(tr(t))
	return out


func _count(root: Node, needle: String) -> int:
	var n := 0
	for t in _visible_texts(root):
		if t.to_lower().contains(needle.to_lower()):
			n += 1
	return n


# ------------------------------------------------------------------ Tenuta

func test_dispensa_vuota_compare_una_volta_sola() -> void:
	_new_game()
	_estate(0.0)
	var s := _screen("res://src/ui/screens/EstateScreen.tscn")
	s.refresh()
	await wait_process_frames(2)
	assert_eq(_count(s, "dispensa vuota"), 1, "l'avviso in cima dice «Dispensa vuota» e basta: %s" % str(_visible_texts(s)))
	assert_eq(_count(s, "vuota"), 1, "nessun'altra «vuota» (etichetta, riga rossa, carta)")
	for tab in ["pantry", "refound", "sell", "buildings"]:
		s._set_tab(tab)
		s.refresh()
		await wait_process_frames(1)
		assert_eq(_count(s, "vuota"), 1, "anche aprendo la scheda %s" % tab)
	assert_true(s._alert.visible, "avviso visibile")
	assert_string_contains((s._tab_btns.pantry as Button).text, "!", "la scheda Dispensa porta il segno")
	# con la Dispensa piena l'avviso sparisce e il segno pure
	(Game.system("estate") as EstateSystem).state.pantry = 500.0
	s.refresh()
	assert_false(s._alert.visible, "niente avviso quando non serve")
	assert_false((s._tab_btns.pantry as Button).text.contains("!"))
	assert_eq(_count(s, "vuota"), 0)


func test_tenuta_ha_le_quattro_schede_e_la_rifondazione_con_puntino() -> void:
	_new_game()
	var e := _estate(500.0)
	var s := _screen("res://src/ui/screens/EstateScreen.tscn")
	s.refresh()
	await wait_process_frames(2)
	for t in ["buildings", "pantry", "refound", "sell"]:
		assert_true(s._tab_btns.has(t), "scheda " + t)
		assert_true(s._pages.has(t), "pagina " + t)
	assert_true((s._tab_btns.refound as Button).visible, "la scheda Rifondazione c'è (Prestigio e Tenuta aperti)")
	assert_false((s._tab_btns.refound as Button).text.contains("•"), "senza i numeri minimi niente puntino")
	e.state.prosperity = 1.0e12
	e.state.lifetime = 1.0e12
	var ps := Game.system("prestige") as PrestigeSystem
	if ps.can_refound() == "":
		s.refresh()
		assert_true((s._tab_btns.refound as Button).text.contains("•"), "Rifondazione disponibile: puntino sulla scheda")
	else:
		fail_test("la Rifondazione deve abilitarsi con prosperita' e totale a 1e12: %s" % ps.can_refound())
	# una sola pagina visibile alla volta
	s._set_tab("pantry")
	var vis := 0
	for t in s._pages:
		vis += 1 if (s._pages[t] as Control).visible else 0
	assert_eq(vis, 1)


func test_carte_edificio_colonne_e_menu_del_pulsante() -> void:
	_new_game()
	_estate(500.0)
	var s := _screen("res://src/ui/screens/EstateScreen.tscn")
	s.refresh()
	await wait_process_frames(2)
	assert_eq(s._grid.columns, s._grid_columns())
	assert_between(s._grid.columns, 1, 3)
	assert_eq(s._cards.size(), (Game.system("estate") as EstateSystem).building_ids().size())
	for bid in s._cards:
		var c: Dictionary = s._cards[bid]
		assert_eq((c.menu as PopupMenu).item_count, 3, "il menù del pulsante ha +1, +10 e Max")
		assert_true((c.b1 as Button).text.contains("▲"), "il pulsante porta il costo")
		# la carta mostra UNA barra di traguardo al massimo e niente descrizione fissa (sta nel tooltip)
		assert_ne((c.panel as Control).tooltip_text, "", "tooltip con descrizione e traguardi")
	var lv0 := (Game.system("estate") as EstateSystem).level_of("sawmill")
	(s._cards.sawmill.menu as PopupMenu).id_pressed.emit(10)
	assert_gte((Game.system("estate") as EstateSystem).level_of("sawmill"), lv0, "la voce +10 comanda il sistema")


func test_intro_alla_prima_visita_poi_dietro_il_punto_interrogativo() -> void:
	_new_game()
	_estate(500.0)
	var s := _screen("res://src/ui/screens/EstateScreen.tscn")
	await wait_process_frames(1)
	assert_true((s._intro.purpose as Control).visible, "prima visita: la frase «a cosa serve» si vede")
	assert_true((Settings.get_value("seen_intro") as Array).has("estate"))
	var s2 := _screen("res://src/ui/screens/EstateScreen.tscn")
	await wait_process_frames(1)
	assert_false((s2._intro.purpose as Control).visible, "seconda visita: richiusa")
	(s2._intro.help as Button).button_pressed = true
	assert_true((s2._intro.purpose as Control).visible, "il «?» la riapre")


# ------------------------------------------------------------------ Dungeon

func test_dungeon_rischio_una_volta_e_nuovo_una_volta() -> void:
	_new_game()
	var s := _screen("res://src/ui/screens/DungeonScreen.tscn", {"dungeon": "cursed_granary"})
	s.refresh()
	await wait_process_frames(2)
	var risks := 0
	for k in ["GREEN", "YELLOW", "RED"]:
		risks += _count(s, tr("UI_COMBAT_SAFE_" + k))
	assert_eq(risks, 1, "il rischio è UN chip: %s" % str(_visible_texts(s)))
	assert_not_null(s._risk_chip, "il chip di rischio esiste per un dungeon aperto")
	assert_eq(_count(s, tr("UI_RS_DU_ST_NEW")), 1, "«Nuovo» una sola volta (sulla scheda): %s" % str(_visible_texts(s)))
	assert_string_contains((s._tab_btns.dungeon as Button).text, tr("UI_RS_DU_ST_NEW"))
	# meccaniche, ondate e record sono sezioni a scomparsa, chiuse
	for key in ["boss", "waves", "record"]:
		assert_false(bool(s._open_state.get(key, false)), "chiusa: " + key)
	assert_eq(_count(s, "▸ " + tr("UI_C2_DUNGEON_WAVES")), 1, "le ondate sono una sezione chiusa")
	assert_eq(_count(s, tr("UI_RS_DU_WAVES_SUB")), 0, "il contenuto delle ondate non si vede finché è chiusa")
	# le quattro schede restano, senza sotto-schede
	for t in ["dungeon", "raids", "worldboss", "rift"]:
		assert_true(s._tab_btns.has(t))


func test_dungeon_banner_del_cibo_solo_se_il_cibo_non_basta() -> void:
	_new_game()
	var combat := Game.system("combat") as CombatSystem
	var s := _screen("res://src/ui/screens/DungeonScreen.tscn", {"dungeon": "cursed_granary"})
	s.refresh()
	await wait_process_frames(2)
	var risk := combat.dungeon_risk("cursed_granary")
	var short := float(risk.food_per_run) > float(risk.food_have)
	assert_eq(s._hint.visible, short, "la barra compare solo se il cibo non basta davvero")
	# con molto cibo la barra sparisce
	(Game.system("bank") as BankSystem).add("food_bleak", 5000, "test")
	s._sig = ""
	s.refresh()
	var risk2 := combat.dungeon_risk("cursed_granary")
	assert_eq(s._hint.visible, float(risk2.food_per_run) > float(risk2.food_have))


func test_schede_di_fine_gioco_niente_nuovo_sulle_righe() -> void:
	_new_game()
	var s := _screen("res://src/ui/screens/DungeonScreen.tscn", {"tab": "raids"})
	s.refresh()
	await wait_process_frames(2)
	assert_lte(_count(s, tr("UI_RS_DU_ST_NEW")), 1, "«Nuovo» al più una volta, sulla scheda Incursioni")
	for t in ["worldboss", "rift", "dungeon"]:
		s._set_tab(t)
		s.refresh()
		await wait_process_frames(1)
		assert_lte(_count(s, tr("UI_RS_DU_ST_NEW")), 1, t)


# ------------------------------------------------------------------ Taglie

func test_taglie_istruzione_una_volta_e_niente_riquadri_vuoti() -> void:
	_new_game()
	var s := _screen("res://src/ui/screens/BountyScreen.tscn")
	s.refresh()
	await wait_process_frames(2)
	var b := Game.system("bounty") as BountySystem
	assert_gt(b.offers().size(), 0)
	assert_eq(_count(s, "Accetta»"), 1, "l'istruzione «Scegli un incarico… Accetta» una volta sola: %s" % str(_visible_texts(s)))
	assert_eq(_count(s, "scegline uno"), 0, "l'introduzione non ripete l'istruzione")
	assert_eq(_count(s, tr("UI_RS_BO_NONE")), 0, "stato vuoto assente se ci sono incarichi")
	assert_eq(_count(s, tr("UI_RS_BO_NO_ACTIVE")), 0, "niente riquadro «nessun incarico in corso»")
	# con un incarico in corso l'istruzione non serve più
	assert_true(b.accept(0))
	s._sig = ""
	s.refresh()
	assert_eq(_count(s, "Accetta»"), 0)
	assert_false(s._hint.visible)


func test_testi_nuovi_bilingui() -> void:
	var keys := ["UI_F9_INTRO_TIP", "UI_F9_ES_HOW", "UI_F9_ES_MENU_TIP", "UI_F9_ES_PANTRY_RULE", "UI_F9_ES_ALERT_PANTRY", "UI_F9_ES_ALERT_FULL", "UI_F9_ES_GO_PANTRY",
		"UI_F9_ES_CARD_NAME", "UI_F9_ES_MS", "UI_F9_ES_MS_MAX", "UI_F9_ES_TIP_MS", "UI_F9_ES_MISSING", "UI_F9_ES_PROD", "UI_F9_DU_SUB", "UI_F9_DU_BOSS_MECH",
		"UI_F9_DU_RECORD", "UI_F9_DU_FOOD_SHORT", "UI_F9_DU_FOOD_NONE", "UI_F9_RIFT_INFO", "UI_F9_BO_WANTED", "UI_F9_BO_PURPOSE"]
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for k in keys:
			assert_ne(TranslationServer.translate(k), k, "%s manca in %s" % [k, loc])
	TranslationServer.set_locale("it")
