extends GutTest
## F8 (progetto di interfaccia, docs/ui_redesign/06 §3.8): Combattimento = arena sempre visibile, il resto a sezioni.
## Un solo chip di rischio; fisarmonica con UNA sezione aperta; La Corsa si apre da sola con una scelta in attesa;
## Cibo in una riga (le regole dietro ⓘ); nessun «Sicuro in idle» duplicato; niente battuta fissa; righe di testo ≤ 45.

var _old_dir: String
var _old_seen: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_combat_layout_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_seen = Settings.get_value("seen_intro")
	Settings.set_value("seen_intro", ["combat"])          # senza la frase «a cosa serve» aperta, salvo dove si prova


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("seen_intro", _old_seen)


func _screen() -> GameScreen:
	var s: GameScreen = (load("res://src/ui/screens/CombatScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _new_hero(level: int) -> CombatSystem:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": level, "record_level": level, "stars": 0, "perks": {}, "unlocked": true}
	GameState.data.unlocks.append_array(["feature:combat", "zone:saltreach", "zone:ironroot", "shop:auto_eat_3"])
	return Game.system("combat") as CombatSystem


func _feed(combat: CombatSystem) -> void:
	var bank := Game.system("bank") as BankSystem
	bank.add("food_bleak", 500, "test")
	combat.set_food(0, "food_bleak")


## Tutti i testi visibili (etichette, pulsanti, testo ricco) sotto un nodo.
func _texts(n: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var c := n as Control
	if c != null and not c.is_visible_in_tree():
		return out
	if n is Label:
		out.append(TranslationServer.translate((n as Label).text) if (n as Label).auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else (n as Label).text)
	elif n is Button:
		out.append(TranslationServer.translate((n as Button).text) if (n as Button).auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else (n as Button).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	for ch in n.get_children():
		_texts(ch, out)
	return out


func _count_containing(texts: PackedStringArray, needle: String) -> int:
	var k := 0
	for t in texts:
		if t.contains(needle):
			k += 1
	return k


func _open_fighting(level: int = 30, fed: bool = true) -> Array:
	var combat := _new_hero(level)
	if fed:
		_feed(combat)
	var cs := _screen()
	cs.open({})
	cs._set_section("")
	await wait_process_frames(2)
	assert_true(combat.start("millbrook", ""))
	for i in 60:
		Game.sim.tick(FixedStepClock.STEP)
	cs.refresh()
	await wait_process_frames(2)
	return [cs, combat]


func test_un_solo_chip_di_rischio_e_nessun_sicuro_in_idle_duplicato() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	var combat: CombatSystem = r[1]
	assert_true(cs._risk_chip.visible, "il chip c'è quando si può stimare il rischio")
	var phrases := PackedStringArray([tr("UI_COMBAT_SAFE_GREEN"), tr("UI_COMBAT_SAFE_YELLOW"), tr("UI_COMBAT_SAFE_RED"),
		tr("UI_COMBAT_SAFE_RED_FOOD"), tr("UI_F8_RISK_BAD")])
	for stato in ["con cibo", "senza cibo"]:
		if stato == "senza cibo":
			var bank := Game.system("bank") as BankSystem
			bank.remove("food_bleak", bank.count("food_bleak"))
			cs.refresh()
			await wait_process_frames(2)
		var texts := _texts(cs)
		var tot := 0
		for ph in phrases:
			tot += _count_containing(texts, ph)
		assert_lte(tot, 1, "rischio scritto al più una volta (%s): %s" % [stato, str(texts)])
		assert_lte(_count_containing(texts, tr("UI_COMBAT_SAFE_GREEN")), 1, "«Sicuro in idle» al più una volta (%s)" % stato)
	assert_eq(cs._food_panel._badge.text, "", "il Cibo non ripete il rischio")
	assert_true(combat.in_combat())


func test_niente_battuta_fissa_ne_immagine_nella_colonna_sinistra() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	assert_eq(_count_containing(_texts(cs), tr("UI_COMBAT_FIGHTING")), 0, "«Si combatte da soli…» non c'è più")
	# l'immagine della zona è lo sfondo dell'arena (dentro il palco), non sta sopra l'elenco dei mostri
	assert_true(cs._stage.is_ancestor_of(cs._zone_banner), "sfondo tenue del palco")
	assert_false(cs._monster_list.get_parent().is_ancestor_of(cs._zone_banner))
	assert_true(cs._stage.is_ancestor_of(cs._hero_sprite) and cs._stage.is_ancestor_of(cs._portrait), "i due ritratti stanno nel palco")


func test_arena_grande_eroe_a_sinistra_nemico_a_destra_bersagli_sotto() -> void:
	# revisione grafica 1.0, punto 7: il quadro è l'elemento dominante, eroe e nemico sono nel quadro, i bersagli sotto
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	for n in [cs._monster_list, cs._portrait, cs._hero_sprite, cs._hero_bar, cs._enemy_bar, cs._res_bar]:
		assert_true((n as Control).is_visible_in_tree())
	var hx: float = cs._hero_sprite.global_position.x
	var ex: float = cs._portrait.global_position.x
	assert_lt(hx, ex, "l'eroe sta a sinistra del nemico")
	assert_lt(cs._hero_bar.global_position.x, cs._enemy_bar.global_position.x, "barra dell'eroe a sinistra di quella del nemico")
	assert_lt(cs._stage.global_position.y, 450.0, "l'arena sta in alto, non sotto altre sezioni")
	assert_lt(cs._stage.global_position.y + cs._stage.size.y, cs._monster_list.global_position.y + 1.0, "i bersagli stanno sotto il quadro")
	assert_gte(cs._stage.size.y, cs.ARENA_H_MIN, "il quadro ha almeno l'altezza minima")
	assert_gte(cs._stage.size.x, 0.6 * cs.size.x, "il quadro occupa la larghezza della schermata")
	# i ritratti sono a scala intera della PNG (D-6)
	for t in [cs._hero_sprite, cs._portrait]:
		var tex: Texture2D = (t as TextureRect).texture
		if tex == null:
			continue                              # tra un nemico e l'altro il quadro del mostro è vuoto
		var k: float = (t as TextureRect).size.y / tex.get_size().y
		assert_almost_eq(k, roundf(k), 0.001, "scala intera (×%s)" % k)
		assert_gte(k, 1.0)
	# colpo / massimo / DPS dell'eroe, misurati
	assert_false(cs._hero_hits.text.contains("UI_F8_HITS"))


func test_fisarmonica_una_sola_sezione_aperta() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	var open_now := func() -> Array:
		var a: Array = []
		for id in cs._sec_body:
			if (cs._sec_body[id] as Control).visible:
				a.append(id)
		return a
	assert_eq(open_now.call(), [], "all'inizio tutto chiuso")
	for id in ["loot", "log", "run", "loot"]:
		if not (cs._sec_btn[id] as Button).visible:
			continue
		(cs._sec_btn[id] as Button).pressed.emit()
		assert_eq(open_now.call(), [id], "aprendo «%s» si chiudono le altre" % id)
	(cs._sec_btn["loot"] as Button).pressed.emit()
	assert_eq(open_now.call(), [], "un secondo clic la richiude")
	cs._set_section("")


func test_la_corsa_e_nascosta_se_bloccata_e_si_apre_da_sola_con_una_scelta() -> void:
	var low: Array = await _open_fighting(5)
	var cs0: GameScreen = low[0]
	assert_false((cs0._sec_btn["run"] as Button).visible, "Corsa bloccata: nessuna intestazione")
	Game.stop_game(false)
	var r: Array = await _open_fighting(40)
	var cs: GameScreen = r[0]
	var run := Game.system("run") as RunSystem
	assert_ne(str(run.status().phase), "locked")
	assert_true((cs._sec_btn["run"] as Button).visible)
	assert_eq(cs._open_section, "", "nessuna scelta: la Corsa resta chiusa")
	var perks: Array = []
	for p in DataRegistry.table("run_perks"):
		perks.append(str(p.id))
	run.state["offer"] = perks.slice(0, 3)
	cs.refresh()
	await wait_process_frames(2)
	assert_eq(cs._open_section, "run", "con una scelta in attesa la Corsa si apre da sola")
	assert_true((cs._sec_body["run"] as Control).visible)
	assert_true((cs._run_panel as Control).is_visible_in_tree())
	assert_true((cs._sec_btn["run"] as Button).text.contains("•"), "puntino sull'intestazione")
	# chi la chiude non viene richiamato per la STESSA scelta; con una scelta nuova si riapre
	cs._set_section("log")
	cs.refresh()
	assert_eq(cs._open_section, "log")
	assert_true((cs._sec_btn["run"] as Button).text.contains("•"), "il puntino resta finché la scelta aspetta")
	run.state["offer"] = perks.slice(1, 4)
	cs.refresh()
	assert_eq(cs._open_section, "run", "scelta nuova: si riapre")
	run.state["offer"] = []
	cs.refresh()
	assert_false((cs._sec_btn["run"] as Button).text.contains("•"))
	cs._set_section("")


func test_cibo_in_una_riga_con_le_regole_dietro_l_info() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	var combat: CombatSystem = r[1]
	var fp: FoodPanel = cs._food_panel
	assert_true(fp.compact)
	assert_false(fp._explain_box.visible, "le regole stanno chiuse")
	for lbl in [fp._intro, fp._stock, fp._eat_info, fp._order_note]:
		assert_false((lbl as Control).is_visible_in_tree())
	# slot, cursore, «Mangia ora» e ⓘ sono sulla stessa riga: il centro del cursore cade dentro l'altezza dello slot
	var b0: Control = fp._slot_btns[0]
	var cy: float = fp._eat_slider.global_position.y + fp._eat_slider.size.y * 0.5
	assert_true(cy >= b0.global_position.y and cy <= b0.global_position.y + b0.size.y, "stessa riga")
	assert_true(fp._eat_btn.is_visible_in_tree() and fp._info_btn.is_visible_in_tree())
	assert_string_contains(fp._info_btn.tooltip_text, fp._eat_info.text.substr(0, 20), "le regole sono anche nel tooltip di ⓘ")
	assert_string_contains(fp._info_btn.tooltip_text, NumberFormat.fmt(combat.food_available()), "e la scorta")
	fp._info_btn.button_pressed = true
	assert_true(fp._explain_box.visible, "ⓘ apre le regole")
	assert_true(fp._intro.is_visible_in_tree())
	fp._info_btn.button_pressed = false
	assert_false(fp._explain_box.visible)


func test_tecniche_sempre_visibili_come_caselle_della_hotbar() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	# senza arma la classe non ha tecniche pronte: si prova la costruzione delle caselle con tre tecniche dei dati
	var abs: Array = []
	for ab in DataRegistry.table("abilities"):
		abs.append(ab)
		if abs.size() == 3:
			break
	cs._rebuild_abilities(abs)
	await wait_process_frames(2)
	assert_eq(cs._abil_row.get_child_count(), 3, "una casella per tecnica, senza dover aprire nulla")
	assert_true(cs._abil_row.is_visible_in_tree())
	var texts := _texts(cs._abil_row)
	for ab in abs:
		var found := false
		for t in texts:
			if t.contains(Loc.t(ab.name).left(5)):
				found = true
		assert_true(found, "la casella mostra «%s»" % Loc.t(ab.name))
	# l'icona è a scala 2× esatta di una PNG 32×32
	var icon := (cs._abil_row.get_child(0).get_child(0).get_child(0)) as TextureRect
	assert_eq(icon.custom_minimum_size, Vector2(64, 64))
	assert_eq(icon.texture.get_size(), Vector2(32, 32))
	assert_false(cs.has_method("_abil_toggle"), "niente più ▸ da premere")


func test_frase_a_cosa_serve_solo_alla_prima_visita() -> void:
	Settings.set_value("seen_intro", [])
	var combat := _new_hero(30)
	var cs := _screen()
	cs.open({})
	await wait_process_frames(2)
	assert_true(cs._intro_lbl.visible, "prima visita: la frase si vede")
	assert_true((Settings.get_value("seen_intro") as Array).has("combat"))
	var cs2 := _screen()
	cs2.open({})
	await wait_process_frames(2)
	assert_false(cs2._intro_lbl.visible, "poi resta nel «?»")
	cs2._help_btn.button_pressed = true
	assert_true(cs2._intro_lbl.visible, "il «?» la richiama")
	assert_true(combat != null)


func test_righe_di_testo_della_schermata_entro_il_budget() -> void:
	var r: Array = await _open_fighting()
	var cs: GameScreen = r[0]
	var m: Dictionary = UiCensus.measure(cs, Rect2(Vector2.ZERO, Vector2(1280, 720)))
	var lines := int(m.window.righe_testo)
	gut.p("righe di testo: %d, controlli visibili: %d" % [lines, int(m.window.controlli_visibili)])
	assert_lte(lines, 45, "righe di testo della schermata (era 124)")
