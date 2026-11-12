extends GutTest
## Restyling della Sala dei Caveau e del gruppo Mercato/Emporio/Commesse (feedback giocatore: «Album e Guardaroba non mi
## aprono nulla»): nessuna scheda è un vicolo cieco, ogni scheda vuota spiega a cosa serve e come si riempie, le schede
## bloccate dicono perché, i pulsanti Apri/Vai funzionano, nessun testo fisso e nessuna icona a scala frazionaria.

const CRATE := "crate_millbrook"

var _old_reduce: bool
var _old_dir: String


func before_each() -> void:
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_vault_ux_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("reduce_motion", true)


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _start(tokens: Array) -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var u := Game.system("unlock") as UnlockSystem
	for t in tokens:
		u.grant(str(t))


func _screen(path: String, params: Dictionary = {}) -> GameScreen:
	var scr: GameScreen = (load("res://src/ui/screens/%s.tscn" % path) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open(params)
	return scr


func _text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	if n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _text(c)
	return out


func _buttons(n: Node, out: Array = []) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)
	return out


# ------------------------------------------------------------------ il bug: clic che non fa nulla

func test_schede_chiuse_hanno_lucchetto_tooltip_e_vai_al_clic() -> void:
	_start(["feature:crates"])                   # Contratti, Affinatura e Sfida sono ancora chiuse
	var scr := _screen("VaultHallScreen")
	await wait_process_frames(2)
	# Album e Guardaroba hanno la loro voce nel menù: non si ripetono come schede della Sala (un posto solo)
	assert_null(scr.find_child("Tab_album", true, false))
	assert_null(scr.find_child("Tab_wardrobe", true, false))
	assert_null(scr.find_child("LockedStrip", true, false), "niente più barra «Ancora chiuse» ripetuta")
	var tabs := scr.find_child("Tabs", true, false)
	assert_eq(tabs.get_child_count(), 5, "Casse · Contratti · Affinatura · Banco · Sfida")
	watch_signals(EventBus)
	for id in ["contracts", "refine", "challenge"]:
		var b := scr.find_child("Tab_" + id, true, false) as Button
		assert_not_null(b)
		assert_true(b.has_meta("locked"), "%s: chiusa" % id)
		assert_ne(b.tooltip_text, "", "%s: il tooltip dice come si sblocca" % id)
		assert_not_null(b.icon, "%s: lucchetto" % id)
		if not b.disabled:
			b.pressed.emit()
	assert_signal_emitted(EventBus, "screen_requested", "il clic su una scheda chiusa porta alla missione che la sblocca")


func test_ogni_scheda_aperta_cambia_davvero_schermata() -> void:
	# con tutto sbloccato, il clic su una scheda emette screen_requested con una schermata che esiste ed è disponibile
	_start(["feature:crates", "feature:wardrobe", "feature:tradeup", "feature:refinery", "feature:collectors_challenge"])
	var scr := _screen("VaultHallScreen")
	await wait_process_frames(2)
	var unlocks: Array = GameState.data.get("unlocks", [])
	for t in CrateUi.TAB_DEFS:
		var b := scr.find_child("Tab_" + str(t.id), true, false) as Button
		if not VaultHead.HALL_TABS.has(str(t.id)):
			assert_null(b, "%s: non è una scheda della Sala" % t.id)
			continue
		assert_not_null(b)
		if t.id != "hall":
			assert_false(b.disabled, "%s: sbloccata" % t.id)
			assert_false(b.has_meta("locked"))
		var entry := ScreenRegistry.get_entry(str(t.screen))
		assert_false(entry.is_empty(), "schermata registrata: " + str(t.screen))
		assert_true(ScreenRegistry.is_available(entry, unlocks),
			"%s: se la scheda è cliccabile la schermata DEVE essere disponibile (altrimenti il clic non fa nulla)" % t.id)


func test_schede_e_registro_dei_token_coincidono() -> void:
	# nessuna scheda può essere più «aperta» della schermata a cui porta
	for t in CrateUi.TAB_DEFS:
		var entry := ScreenRegistry.get_entry(str(t.screen))
		var need := str(entry.get("unlock", ""))
		if need != "" and need != str(t.token) and (t.id == "album" or t.id == "wardrobe"):
			fail_test("la scheda %s richiede '%s' ma la schermata '%s'" % [t.id, t.token, need])
	pass_test("ok")


# ------------------------------------------------------------------ stati vuoti utili

func test_sala_vuota_spiega_come_riempirla_con_vai_e_anteprima() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var scr := _screen("VaultHallScreen")
	await wait_process_frames(2)
	var card := scr.find_child("EmptyCard", true, false)
	assert_not_null(card, "scheda Casse vuota: carta esplicativa, non uno spazio vuoto")
	var t := _text(card)
	assert_string_contains(t, str(TranslationServer.translate("UI_VUX_HALL_EMPTY_TITLE")))
	assert_string_contains(t, str(TranslationServer.translate("UI_VUX_HOW_TO_FILL")), "«come si riempie»")
	assert_string_contains(t, str(TranslationServer.translate("UI_VUX_PREVIEW")), "anteprima delle casse")
	assert_not_null(scr.find_child("GhostCrates", true, false), "sagome delle casse che esistono")
	var gos := 0
	for b in _buttons(card):
		if (b as Button).text.begins_with(str(TranslationServer.translate("UI_VUX_GO")).substr(0, 4)):
			gos += 1
	assert_gt(gos, 0, "almeno un pulsante Vai")


func test_album_vuoto_mostra_sagome_e_progresso() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var scr := _screen("AlbumScreen")
	await wait_process_frames(2)
	assert_not_null(scr.find_child("EmptyCard", true, false), "spiegazione dell'Album bianco")
	var grid := scr.find_child("SlotGrid", true, false)
	assert_not_null(grid, "le sagome da completare restano visibili")
	assert_gt(grid.get_child_count(), 5)
	var crates := Game.system("crates") as CrateSystem
	var total := 0
	for cid in crates.collection_ids():
		total += int(crates.collection_progress(str(cid)).total)
	assert_string_contains(_text(scr), "0/%d" % total, "progresso x/N di tutte le collezioni")
	# una tessera per collezione (raggruppate in In corso / Finite / Non iniziate)
	var tiles := 0
	for c in _all_nodes(scr.find_child("CollectionTiles", true, false)):
		if str(c.name).begins_with("Collection_"):
			tiles += 1
	assert_eq(tiles, crates.collection_ids().size())
	# Album bianco: nulla è in corso, quindi le collezioni da cominciare sono visibili (non un elenco vuoto)
	assert_true((scr.find_child("GroupUnstarted", true, false) as Control).visible)


func _all_nodes(node: Node, acc: Array = []) -> Array:
	acc.append(node)
	for ch in node.get_children():
		_all_nodes(ch, acc)
	return acc


func test_guardaroba_vuoto_mostra_slot_grigi_e_dove_ottenere_i_pezzi() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var scr := _screen("WardrobeScreen")
	await wait_process_frames(2)
	var crates := Game.system("crates") as CrateSystem
	for s in crates.wardrobe_slots():
		assert_not_null(scr.find_child("Slot_" + str(s.slot), true, false), "slot " + str(s.slot))
	for t in ["worn", "bonus", "reliq"]:
		assert_not_null(scr.find_child("Tab_" + t, true, false), "scheda " + t)
	assert_null(scr.find_child("Tab_album", true, false), "niente schede della Sala qui")
	# nessuno slot scelto: una riga, non una carta di spiegazione (la guida è nel tooltip dello slot vuoto)
	assert_not_null(scr.find_child("PickHint", true, false))
	var tip := (scr.find_child("Slot_weapon", true, false) as Control).tooltip_text
	assert_string_contains(tip, str(TranslationServer.translate("UI_VUX_HOW_TO_FILL")), "«Come si riempie» nel tooltip dello slot vuoto")
	# gli slot sono su 4 colonne
	assert_eq((scr.find_child("Slot_weapon", true, false).get_parent() as GridContainer).columns, 4)
	# scelgo uno slot: compaiono le casse da cui escono le finiture che mancano, con Vai
	scr._selected_slot = "weapon"
	scr._rebuild(true)
	var t := _text(scr)
	assert_string_contains(t, str(TranslationServer.translate("UI_VUX_WD_TO_FIND")))
	assert_string_contains(t, CrateUi.def_name(CRATE), "la cassa che contiene finiture per quello slot")
	assert_string_contains(t, str(TranslationServer.translate("UI_VUX_WD_NONE_OWNED")))


func test_guardaroba_equipaggia_e_tutto_resta_funzionante() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var crates := Game.system("crates") as CrateSystem
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	var def_id := str(crates.contents(CRATE)["rare"][0])
	var slot := str(DataRegistry.item(def_id).skin.slot)
	var uid := bank.add_instance({"def_id": def_id, "kind": "skin", "rarity": "rare", "crate": CRATE,
		"condition": crates.condition_for_float(0.5), "float": 0.5, "annalist": false, "seed": 3, "phase": "", "polish": 0, "locked": false})
	var scr := _screen("WardrobeScreen")
	scr._selected_slot = slot
	scr._rebuild(true)
	await wait_process_frames(1)
	var equip_btn: Button = null
	for b in _buttons(scr):
		if (b as Button).text == str(TranslationServer.translate("UI_VUX_WD_EQUIP")):
			equip_btn = b
	assert_not_null(equip_btn, "pulsante Indossa")
	equip_btn.pressed.emit()
	assert_eq(crates.equipped(slot), uid, "indossata")
	assert_string_contains(_text(scr), str(TranslationServer.translate("UI_VUX_WD_WORN")))


func test_bottega_schede_chiuse_o_vuote_hanno_carta_con_vai() -> void:
	_start(["feature:crates"])
	for tab in ["contracts", "refine", "challenge"]:
		var scr := _screen("VaultWorkshopScreen", {"tab": tab})
		await wait_process_frames(1)
		assert_not_null(scr.find_child("EmptyCard", true, false), tab + ": carta di spiegazione")
		scr.queue_free()
	# sbloccate ma senza pezzi
	var u := Game.system("unlock") as UnlockSystem
	for t in ["feature:tradeup", "feature:refinery"]:
		u.grant(t)
	for tab in ["contracts", "refine", "bank"]:
		var scr2 := _screen("VaultWorkshopScreen", {"tab": tab})
		await wait_process_frames(1)
		var card := scr2.find_child("EmptyCard", true, false)
		assert_not_null(card, tab + ": senza pezzi spiega cosa fare")
		scr2.queue_free()


# ------------------------------------------------------------------ Sala: pulsanti e probabilità

func test_sala_con_casse_ha_un_solo_primario_e_probabilita_visibili() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 3)
	bank.add("key_t1", 3)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(2)
	assert_null(scr.find_child("EmptyCard", true, false))
	var primary := 0
	for b in _buttons(scr._detail):
		if (b as Button).theme_type_variation == &"AccentButton":
			primary += 1
	assert_eq(primary, 1, "un solo pulsante primario nel dettaglio: Apri")
	assert_not_null(scr.find_child("OddsBar", true, false), "barra delle probabilità")
	assert_not_null(scr.find_child("OddsBox", true, false).find_child("OddsBar", true, false), "dentro il blocco probabilità, mai in un Disclosure")
	var crates := Game.system("crates") as CrateSystem
	for r in crates.odds(CRATE):
		assert_string_contains(_text(scr._detail), CrateUi.pct(float(r.pct)), "probabilità visibile: " + str(r.rarity))
	assert_not_null(scr.find_child("CrateCard_" + CRATE, true, false), "carta della cassa")
	# apri: estratto prima dell'animazione (comportamento invariato)
	scr._do_open(1)
	assert_eq(crates.state.opened, 1)
	scr._on_close_panel()


func test_sala_senza_chiave_dice_cosa_manca_e_dove_trovarla() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 2)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(2)
	var why := scr.find_child("WhyDisabled", true, false)
	assert_not_null(why, "pulsante Apri spento: c'è il motivo")
	assert_string_contains(_text(why), CrateUi.def_name("key_t1"))
	var open_btn := scr.find_child("OpenButton", true, false) as Button
	assert_true(open_btn.disabled)
	assert_gt(_buttons(why).size(), 0, "almeno un Vai")


func test_elenco_casse_si_aggiorna_con_le_chiavi() -> void:
	# il riepilogo risorse separato non c'è più (un posto solo, D18): casse e chiavi stanno nell'elenco e nel dettaglio
	_start(["feature:crates"])
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 1)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(1)
	assert_null(scr.find_child("ResourceBar", true, false))
	var before := _text(scr.find_child("CrateInfo", true, false))
	bank.add("key_t1", 5)
	scr.refresh()
	await wait_process_frames(1)
	assert_ne(_text(scr.find_child("CrateInfo", true, false)), before, "chiavi nuove nel dettaglio")


# ------------------------------------------------------------------ icone a scala intera, testi bilingui

func test_icone_a_scala_intera() -> void:
	for tex in [IconLib.icon("crates", CRATE), IconLib.ui("ui_lock"), IconLib.icon("items", "vault_shard")]:
		for sc in [1, 2, 3]:
			var r := VaultKit.pix(tex, sc)
			assert_eq(r.custom_minimum_size, tex.get_size() * float(sc), "scala intera")
			assert_eq(r.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
			r.free()


func test_stringhe_nuove_bilingui_e_senza_genere() -> void:
	var f := FileAccess.open("res://../localization/parts/vault_ux.csv", FileAccess.READ)
	assert_not_null(f, "localization/parts/vault_ux.csv raggiungibile dal progetto (i test girano dal repository)")
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
		assert_ne(row[1], row[2], row[0] + ": IT e EN identici?")
	assert_gt(n, 50)


func test_mercato_emporio_commesse_si_aprono_con_intestazione_e_oro() -> void:
	_start(["feature:crates", "feature:market"])
	for path in ["MarketScreen", "ShopScreen", "OrdersScreen"]:
		var scr := _screen(path)
		await wait_process_frames(2)
		scr.refresh()
		assert_not_null(scr.find_child("IntroToggle", true, false), path + ": spiegazione richiudibile")
		assert_not_null(scr.find_child("GoldChip", true, false), path + ": oro in evidenza")
		scr.queue_free()


func test_mercato_senza_merci_spiega_e_non_resta_vuoto() -> void:
	_start(["feature:crates", "feature:market"])
	(Game.system("bank") as BankSystem).state.stacks.clear()
	var scr := _screen("MarketScreen")
	await wait_process_frames(2)
	scr.refresh()
	assert_not_null(scr.find_child("EmptyCard", true, false), "Deposito senza merci vendibili: carta esplicativa")


# ------------------------------------------------------------------ F11: Album e Guardaroba riordinati

func test_album_con_pezzi_ha_gruppi_chiusi_e_dettagli_nel_tooltip() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var crates := Game.system("crates") as CrateSystem
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	bank.add(CRATE, 3)
	bank.add("key_t1", 3)
	crates.open(CRATE, 3, false)
	var scr := _screen("AlbumScreen")
	await wait_process_frames(2)
	assert_not_null(scr.find_child("GroupActive", true, false), "In corso")
	assert_true((scr.find_child("GroupActive", true, false) as Control).visible)
	var unstarted := scr.find_child("GroupUnstarted", true, false) as Control
	assert_not_null(unstarted)
	assert_false(unstarted.visible, "«Non iniziate» chiuse quando c'è qualcosa in corso")
	var toggle := scr.find_child("ToggleUnstarted", true, false) as Button
	toggle.pressed.emit()
	assert_true(unstarted.visible, "un clic le apre")
	# nessuna carta ripete «Patina migliore · Analisti»: sta nel tooltip
	var best := str(TranslationServer.translate("UI_CRATES_ALBUM_BEST")).split("{")[0].strip_edges()
	assert_false(_text(scr.find_child("SlotGrid", true, false)).contains(best), "patina migliore non ripetuta sulle carte")
	var any_tip := false
	for c in scr.find_child("SlotGrid", true, false).get_children():
		if (c as Control).tooltip_text.contains(best):
			any_tip = true
	assert_true(any_tip, "patina migliore e Analisti nel tooltip dei pezzi trovati")
	# «Reliquie 0/N» non compare finché non ce n'è una
	assert_false(_text(scr.find_child("SlotGrid", true, false).get_parent()).contains("0/4"), "niente «Reliquie 0/N» senza Reliquie")


func test_guardaroba_ha_tre_schede_e_il_resto_si_ricorda() -> void:
	_start(["feature:crates", "feature:wardrobe"])
	var scr := _screen("WardrobeScreen")
	await wait_process_frames(2)
	assert_true((scr.find_child("PageWorn", true, false) as Control).visible)
	assert_false((scr.find_child("PageBonus", true, false) as Control).visible)
	(scr.find_child("Tab_bonus", true, false) as Button).pressed.emit()
	assert_true((scr.find_child("PageBonus", true, false) as Control).visible)
	assert_not_null(scr.find_child("TotalsCard", true, false), "Bonus attivi")
	(scr.find_child("Tab_reliq", true, false) as Button).pressed.emit()
	assert_true((scr.find_child("PageReliq", true, false) as Control).visible)
	assert_not_null(scr.find_child("ReliquarySlots", true, false), "Reliquiari")


func test_introduzione_solo_alla_prima_visita_poi_si_richiude_in_un_punto_interrogativo() -> void:
	var old: Array = (Settings.get_value("seen_intro") as Array).duplicate()
	Settings.set_value("seen_intro", [])
	VaultHead._intro_open.clear()
	_start(["feature:crates", "feature:wardrobe"])
	var first := _screen("WardrobeScreen")
	await wait_process_frames(1)
	assert_true((first.find_child("IntroText", true, false) as Control).visible, "prima visita: la frase è aperta")
	assert_true((Settings.get_value("seen_intro") as Array).has("wardrobe"), "segnata come vista")
	first.queue_free()
	await wait_process_frames(1)
	VaultHead._intro_open.clear()                       # nuova sessione di gioco: la frase NON torna aperta
	var second := _screen("WardrobeScreen")
	await wait_process_frames(1)
	assert_false((second.find_child("IntroText", true, false) as Control).visible, "dalla seconda visita è chiusa")
	(second.find_child("IntroToggle", true, false) as Button).pressed.emit()
	assert_true((second.find_child("IntroText", true, false) as Control).visible, "il «?» la riapre")
	Settings.set_value("seen_intro", old)
	VaultHead._intro_open.clear()
