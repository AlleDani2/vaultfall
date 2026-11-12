extends GutTest
## Revisione grafica 1.0, schermate B (rapporto 08, problemi 6, 9, 13, 14, 17, 18, 26, 29 e correlati): Sala dei Caveau con cassa
## grande e scena di apertura, carte-mansione, Missioni a due colonne, Emporio a pillole, Mercato a tabella, Slot a tre carte,
## Crediti a schede, caselle delle Impostazioni accanto all'etichetta. Le REGOLE ETICHE (CLAUDE.md regola 5, docs/24) restano
## verificate qui: probabilità visibili anche durante l'apertura, risultato estratto prima, «apri un'altra» non è primario e
## non spinge, nessun valore tecnico in primo piano ma sempre raggiungibile.

const CRATE := "crate_millbrook"
const FORBIDDEN: PackedStringArray = ["per un pelo", "riprova", "close call", "try again", "jackpot", "scommetti", "bet "]

var _old_dir: String
var _old_reduce: bool
var _old_locale: String


func before_each() -> void:
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_locale = Loc.locale()
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_grafica_b_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	Settings.set_value("reduce_motion", true)
	Settings.set_value("locale", "it")


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	Settings.set_value("locale", _old_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	SlotSummary.invalidate()
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _start(extra: Array = []) -> void:
	assert_true(Game.new_game(1, "normal", 77))
	var u := Game.system("unlock") as UnlockSystem
	for t in ["feature:crates", "feature:market", "feature:wardrobe"] + extra:
		u.grant(str(t))
	(Game.system("bank") as BankSystem).state.slots_bought = 5000


func _hall(n_crates: int = 12) -> GameScreen:
	_start()
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, n_crates)
	bank.add("key_t1", n_crates)
	var scr: GameScreen = (load("res://src/ui/screens/VaultHallScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"crate": CRATE})
	await wait_process_frames(3)
	return scr


## Monta la schermata in un riquadro di 1300×700 (area di contenuto tipica): non si imposta `size` su nodi con le ancore a tutto schermo.
func _mount(path: String, params: Dictionary = {}) -> GameScreen:
	var scr: GameScreen = (load("res://src/ui/screens/%s.tscn" % path) as PackedScene).instantiate()
	var host := Control.new()
	add_child_autofree(host)
	host.size = Vector2(1300, 700)
	host.add_child(scr)
	scr.open(params)
	return scr


func _texts(n: Node, only_visible: bool = true) -> String:
	var out := ""
	if n is CanvasItem and only_visible and not (n as CanvasItem).visible:
		return out
	if n is Label:
		out += (n as Label).text + "\n"
	if n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _texts(c, only_visible)
	return out


# ------------------------------------------------------------------ Sala dei Caveau

func test_sala_ha_la_cassa_grande_a_scala_intera_e_un_solo_pulsante_pieno() -> void:
	var scr := await _hall()
	var big := scr.find_child("ChestBig", true, false) as TextureRect
	assert_not_null(big, "la cassa grande")
	assert_eq(big.custom_minimum_size, Vector2(160, 160), "5× il PNG da 32 px: scala INTERA (regola 10)")
	assert_eq(big.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	var open := scr.find_child("OpenButton", true, false) as Button
	assert_gte(open.custom_minimum_size.y, 56.0, "«Apri» alto almeno 56 px")
	assert_eq(open.theme_type_variation, &"AccentButton")
	var accents := 0
	for b in scr.find_child("HallStage", true, false).find_children("*", "Button", true, false):
		if (b as Button).theme_type_variation == &"AccentButton":
			accents += 1
	assert_eq(accents, 1, "UN solo pulsante pieno nella scena")


func test_probabilita_sempre_visibili_nella_sala_e_durante_la_scena() -> void:
	var scr := await _hall()
	var crates := Game.system("crates") as CrateSystem
	var box := scr.find_child("OddsBox", true, false) as Control
	assert_true(box.is_visible_in_tree(), "probabilità visibili nella sala, senza clic")
	scr._do_open(1)
	assert_false(scr._split.visible, "la scena prende il posto di elenco e dettaglio…")
	var line := scr.find_child("StageOdds", true, false) as Label
	assert_true(line.is_visible_in_tree(), "…ma le probabilità restano scritte sotto la scena")
	for r in crates.odds(CRATE):
		assert_string_contains(line.text, CrateUi.pct(float(r.pct)), "%s mostrata durante l'apertura" % str(r.rarity))
	scr._on_close_panel()
	assert_true(scr._split.visible, "chiusa la scena torna la sala")
	assert_true((scr.find_child("OddsBox", true, false) as Control).is_visible_in_tree())


func test_scena_di_apertura_risultato_prima_e_carta_con_dettagli_dietro_la_i() -> void:
	var scr := await _hall()
	var crates := Game.system("crates") as CrateSystem
	scr._do_open(1)
	assert_eq(int(crates.state.opened), 1, "estratto PRIMA di qualunque animazione (docs/24)")
	await wait_process_frames(2)
	var card := scr._card as CrateResultCard
	assert_true(card.is_visible_in_tree(), "carta-risultato")
	assert_gte(card.custom_minimum_size.y, 300.0)
	var icon := card.find_child("ResultIcon", true, false) as TextureRect
	assert_eq(icon.custom_minimum_size, Vector2(128, 128), "icona 4× (scala intera)")
	var r: Dictionary = scr._results[0]
	var inst: Dictionary = r.instance
	var tech := CrateUi.instance_detail(inst)
	assert_ne(tech, "")
	var shown := _texts(scr._open_panel)
	assert_false(shown.contains(NumberFormat.decimal(float(inst.float), 4, "it")), "il numero di usura non è in primo piano")
	assert_false(shown.contains(Loc.tf("UI_CRATES_PATTERN", {"n": int(inst.seed)})), "né il motivo")
	assert_string_contains(shown, CrateUi.condition_name(str(inst.condition)), "la condizione sì, a parole")
	(card.find_child("DetailToggle", true, false) as Button).pressed.emit()
	assert_true(card.detail_visible(), "dietro la «i» i valori tecnici ci sono")
	assert_string_contains(_texts(card), tech)
	scr._on_close_panel()


func test_apri_un_altra_e_neutro_e_senza_parole_che_spingono() -> void:
	var scr := await _hall()
	scr._do_open(1)
	await wait_process_frames(2)
	var again := scr.find_child("OpenAgain", true, false) as Button
	assert_not_null(again)
	assert_ne(again.theme_type_variation, &"AccentButton", "non è il pulsante primario (R-LEG-5: nessuna spinta)")
	var low := _texts(scr._open_panel).to_lower()
	for w in FORBIDDEN:
		assert_false(low.contains(w), "parola vietata: " + w)
	assert_false(again.disabled)
	var opened := int((Game.system("crates") as CrateSystem).state.opened)
	again.pressed.emit()
	assert_eq(int((Game.system("crates") as CrateSystem).state.opened), opened + 1, "apre UNA cassa, estratta prima come sempre")
	scr._on_close_panel()


func test_x10_le_azioni_stanno_sotto_la_griglia_e_sono_le_stesse() -> void:
	var scr := await _hall()
	scr._do_open(10)
	await wait_process_frames(3)
	assert_eq(scr._multi.visible_count(), 10)
	assert_eq(scr._actions.get_parent(), scr._multi_host, "×10: azioni in fila sotto la griglia")
	assert_false(scr._actions.column)
	scr._on_close_panel()
	scr._do_open(1)
	await wait_process_frames(2)
	assert_eq(scr._actions.get_parent(), scr._rside, "×1: azioni in colonna a destra della carta")
	assert_true(scr._actions.column)
	scr._on_close_panel()


func test_riempitivi_del_rullo_con_probabilita_reali_restano_60_con_vincitore_alla_52() -> void:
	var scr := await _hall()
	scr._do_open(1)
	var r: Dictionary = scr._results[0]
	assert_eq((r.reel as Array).size(), 60)
	assert_eq(int(r.reel_index), 52)
	assert_eq(str((r.reel as Array)[52].d), str(r.def_id), "il vincitore è quello estratto")
	scr._on_close_panel()


func test_banner_in_alto_a_destra_non_copre_il_titolo() -> void:
	var host := Control.new()
	add_child_autofree(host)
	host.size = Vector2(1600, 900)
	var b := FxBanner.new()
	host.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(1)
	var w := b._w()
	var x := b._x()
	assert_gte(x, 1600.0 - w - 70.0, "ancorato a destra")
	assert_lte(x + w, 1600.0 - 52.0, "fuori dal binario destro")
	assert_gt(x, 800.0 - w * 0.5, "non più centrato")


# ------------------------------------------------------------------ Mansioni

func test_mansione_a_carte_con_pulsante_largo_e_barra_sulla_carta_attiva() -> void:
	_start()
	var scr: GameScreen = (load("res://src/ui/screens/SkillScreen.tscn") as PackedScene).instantiate()
	var host := Control.new()
	add_child_autofree(host)
	host.size = Vector2(1100, 700)
	host.add_child(scr)
	scr.open({"skill": "woodcutting"})
	await wait_process_frames(3)
	assert_true(scr._list is GridContainer, "griglia di carte")
	assert_gte(scr._list.columns, 2)
	var row: Dictionary = scr._rows["wc_pine"]
	assert_gte((row.panel as Control).size.y, 120.0)
	assert_gte((row.btn as Button).size.y, 40.0)
	(Game.system("skills") as SkillSystem).start("wc_pine")
	scr.refresh()
	await wait_process_frames(2)
	assert_true((row.prog as Control).visible, "barra continua sulla carta in esecuzione")


# ------------------------------------------------------------------ Missioni, Emporio, Mercato

func test_missioni_a_due_colonne_con_ricompense_a_icone_e_riscatta_compatto() -> void:
	_start()
	var qs := Game.system("quests") as QuestSystem
	var qid := qs.current_main()
	var obj: Dictionary = qs.quest_def(qid).objectives[0]
	qs.state.progress[qid] = [QuestSystem.target_of(obj)] if (qs.state.progress.get(qid, []) as Array).size() <= 1 else qs.state.progress[qid]
	var scr := _mount("QuestScreen")
	await wait_process_frames(3)
	var grids := scr.find_children("QuestGrid", "GridContainer", true, false)
	for g in grids:
		assert_eq((g as GridContainer).columns, 2, "due colonne a 1300 px")
	var chips := scr.find_children("RewardChips", "HFlowContainer", true, false)
	assert_gt(chips.size(), 0, "ricompense come chip con icona e quantità")
	for cb in scr.find_children("ClaimButton", "Button", true, false):
		assert_lt((cb as Button).size.x, 400.0, "«Riscatta» non è largo come la pagina")


func test_emporio_stato_a_pillola_senza_rosso_e_carte_a_due_colonne() -> void:
	_start()
	var scr := _mount("ShopScreen")
	await wait_process_frames(3)
	scr.refresh()
	var grid := scr.find_child("ShopGrid_upgrades", true, false) as GridContainer
	assert_not_null(grid)
	assert_eq(grid.columns, 2)
	var pills := scr.find_children("StatusPill", "PanelContainer", true, false)
	assert_gt(pills.size(), 5, "una pillola di stato per carta")
	for p in pills:
		var l := (p as Control).get_child(0) as Label
		var c := l.get_theme_color("font_color")
		assert_false(c.r > 0.85 and c.g < 0.55 and c.b < 0.5, "niente rosso per «ti manca l'oro»: «%s»" % l.text)
	var go_any := scr.find_children("*", "AccentButton", true, false)
	assert_not_null(go_any)


func test_mercato_e_una_tabella_con_prezzo_in_colonna() -> void:
	_start()
	var bank := Game.system("bank") as BankSystem
	bank.add("log_pine", 14)
	bank.add("plank_pine", 5)
	var scr := _mount("MarketScreen")
	await wait_process_frames(3)
	var t := scr.find_child("MarketTable", true, false) as Tree
	assert_not_null(t)
	assert_eq(t.columns, 4)
	assert_gt(t.get_root().get_child_count(), 0)
	var first := t.get_root().get_first_child()
	assert_true(first.get_text(1).begins_with("×"), "quantità in colonna")
	assert_false(first.get_text(0).contains("—"), "il prezzo non è più dentro il nome")
	assert_ne(first.get_text(2), "", "prezzo in colonna")
	assert_true(first.is_selected(0), "mai una schermata vuota: parte dal primo oggetto")


# ------------------------------------------------------------------ Impostazioni, Slot, Crediti

func test_impostazioni_casella_accanto_all_etichetta_e_riga_cliccabile() -> void:
	var holder := VBoxContainer.new()
	add_child_autofree(holder)
	var cb := SettingsKit.check_row(holder, "UI_SETTINGS_GAME")
	var row := cb.get_parent() as HBoxContainer
	assert_eq(row.get_child(0), cb, "la casella è a SINISTRA, prima dell'etichetta")
	assert_gte(row.custom_minimum_size.y, 40.0, "riga da 40 px (controller)")
	var label := row.get_child(1) as Label
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_STOP)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	var before := cb.button_pressed
	label.gui_input.emit(ev)
	assert_eq(cb.button_pressed, not before, "un clic sul testo spunta la casella")


func test_slot_tre_carte_affiancate_con_azioni_sotto_e_elimina_spento() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	SlotSummary.invalidate()
	var s: Control = (load("res://src/ui/start/StartScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	s.show_slots()
	await wait_process_frames(2)
	var list := s.find_child("SlotList", true, false) as GridContainer
	assert_not_null(list)
	assert_eq(list.get_child_count(), 3)
	var c1 := s.find_child("Slot1", true, false)
	assert_not_null(c1.find_child("SlotLevel", true, false), "livello totale in grande")
	var load_b := c1.find_child("LoadButton", true, false) as Button
	var del_b := c1.find_child("DeleteButton", true, false) as Button
	assert_eq(load_b.theme_type_variation, &"AccentButton", "«Continua» primaria")
	assert_true(del_b.has_theme_color_override("font_color"), "«Elimina» in rosso spento")
	assert_gte(load_b.custom_minimum_size.y, 40.0)
	var empty := s.find_child("Slot3", true, false)
	assert_eq((empty.find_child("NewButton", true, false) as Button).theme_type_variation, &"AccentButton", "slot libero: Nuova partita primaria")
	assert_null(empty.find_child("DeleteButton", true, false))


func test_crediti_a_schede_con_riquadro_ambra_per_l_ia() -> void:
	var v := CreditsView.new()
	v.with_back = false
	add_child_autofree(v)
	await wait_process_frames(2)
	var grid := v.find_child("CreditsGrid", true, false) as GridContainer
	assert_not_null(grid)
	assert_eq(grid.get_child_count(), CreditsView.SECTIONS.size() - 1, "una scheda per sezione col titolo")
	var amber := 0
	for c in grid.get_children():
		var sb := (c as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		if sb.border_color == FxPalette.AMBER:
			amber += 1
	assert_eq(amber, 1, "l'uso di strumenti di IA ha il suo riquadro")


# ------------------------------------------------------------------ Tenuta e testi

func test_tenuta_nome_e_effetto_vanno_a_capo_senza_puntini() -> void:
	_start(["feature:estate"])
	var scr := _mount("EstateScreen")
	await wait_process_frames(3)
	scr.refresh()
	for bid in scr._cards:
		var c: Dictionary = scr._cards[bid]
		assert_eq((c.name as Label).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "%s: nome a capo" % bid)
		assert_eq((c.info as Label).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "%s: effetto a capo" % bid)
		assert_false((c.info as Label).clip_text, "%s: mai «…»" % bid)
		if c.opt != null:
			assert_false((c.opt as OptionButton).clip_text, "%s: selettore della risorsa a larghezza piena" % bid)


func test_stringhe_nuove_bilingui() -> void:
	var f := FileAccess.open("res://../localization/parts/grafica_schermate_b.csv", FileAccess.READ)
	assert_not_null(f)
	if f == null:
		return
	f.get_csv_line()
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or row[0].is_empty():
			continue
		n += 1
		assert_ne(row[1].strip_edges(), "", row[0] + " EN")
		assert_ne(row[2].strip_edges(), "", row[0] + " IT")
		for loc in ["it", "en"]:
			Settings.set_value("locale", loc)
			assert_ne(str(TranslationServer.translate(row[0])), row[0], "%s tradotta in %s" % [row[0], loc])
	assert_gt(n, 8)
