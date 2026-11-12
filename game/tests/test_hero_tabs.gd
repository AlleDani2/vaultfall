extends GutTest
## F10 (docs/ui_redesign/06 §3.12, §3.14, §3.15): Eroe a schede, Talenti con un solo riquadro di dettaglio e ramo non attivo a icone,
## Prestigio con Consigliere e Grande Obiettivo uno alla volta. Solo presentazione: le regole restano nei sistemi.

const HERO := "res://src/ui/screens/HeroScreen.tscn"
const TALENTS := "res://src/ui/screens/TalentScreen.tscn"
const PRESTIGE := "res://src/ui/screens/PrestigeScreen.tscn"
const HeroScript := preload("res://src/ui/screens/HeroScreen.gd")
const PrestigeScript := preload("res://src/ui/screens/PrestigeScreen.gd")

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_seen: Variant


func before_all() -> void:
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_hero_tabs_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_seen = Settings.get_value("seen_intro")
	Settings.set_value("seen_intro", [])
	HeroScript._last_tab = "equip"
	assert_true(Game.new_game(1, "normal", 11))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 40, "record_level": 40, "stars": 0, "perks": {}, "unlocked": true}
	(GameState.data.unlocks as Array).append_array(["feature:combat", "zone:millbrook", "skill:hero", "feature:talents", "feature:prestige"])


func after_each() -> void:
	Settings.set_value("seen_intro", _old_seen)
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	get_tree().root.content_scale_factor = _old_scale
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	return s


func _visible_pages(hs: Control) -> Array:
	var out: Array = []
	for k in hs.get("_pages"):
		if (hs.get("_pages")[k] as Control).visible:
			out.append(k)
	return out


# ------------------------------------------------------------------ Eroe

func test_eroe_ha_cinque_schede_e_non_ripete_talenti_e_guardaroba() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	assert_eq(HeroScript.TAB_IDS, PackedStringArray(["equip", "abilities", "stats", "food", "glyphs"]))
	var btns: Dictionary = hs.get("_tab_btns")
	assert_eq(btns.size(), 5, "cinque schede")
	for id in btns:
		assert_false(["talents", "wardrobe"].has(str(id)), "Talenti e Guardaroba hanno la loro voce di menù")
	for b in btns.values():
		var t := str((b as Button).text).to_lower()
		assert_false(t.contains("talent") or t.contains("guardaroba") or t.contains("wardrobe"), "scheda: " + t)
	assert_eq(_visible_pages(hs), ["equip"], "una sola pagina alla volta, all'inizio l'equipaggiamento")


func test_eroe_cambia_scheda_e_mostra_una_pagina_sola() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	for id in HeroScript.TAB_IDS:
		(hs.get("_tab_btns")[id] as Button).pressed.emit()
		assert_eq(hs.call("current_tab"), id)
		assert_eq(_visible_pages(hs), [id])
		assert_true((hs.get("_tab_btns")[id] as Button).button_pressed, "la scheda attiva è premuta")
	# i controlli di ogni pagina continuano a funzionare anche da nascosti
	assert_not_null(hs.get("_class_opt"))
	assert_not_null(hs.get("_potion_opt"))
	assert_not_null(hs.get("_glyph_item_opt"))


func test_eroe_testata_in_una_riga_con_classe_e_tre_statistiche() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	var combat := Game.system("combat") as CombatSystem
	var head: Label = hs.get("_head_class")
	assert_string_contains(head.text, "40")
	assert_string_contains(head.text, Loc.t(combat.class_def().get("name", {})))
	var chips: Dictionary = hs.get("_head_chips")
	assert_eq(chips.size(), 3, "PV, Precisione, Armatura")
	for k in chips:
		var l := chips[k] as Label
		assert_false(l.text.is_empty())
		assert_false(l.tooltip_text.is_empty(), "tooltip di calcolo (StatBreakdown) su " + str(k))


func test_eroe_ricorda_l_ultima_scheda() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	(hs.get("_tab_btns")["food"] as Button).pressed.emit()
	var hs2 := _open(HERO)
	await wait_process_frames(2)
	assert_eq(hs2.call("current_tab"), "food")


func test_eroe_riga_unica_senza_pezzi_adatti_con_vai() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll := hs.get("_doll") as EquipDoll
	doll._select_slot("cape")
	doll.refresh(true)
	assert_true(doll._entries.is_empty(), "nessun mantello nel Deposito")
	assert_string_contains(doll._list_head.text, "0")
	assert_false(doll._empty_box.visible, "niente blocco di testo separato")
	assert_eq(doll._list_head.get_parent(), doll._go_row.get_parent(), "«adatti: 0» e i «Vai» stanno nella stessa riga")


func test_eroe_utensili_solo_per_mansioni_sbloccate() -> void:
	var hs := _open(HERO)
	await wait_process_frames(2)
	var doll := hs.get("_doll") as EquipDoll
	var sk := Game.system("skills") as SkillSystem
	for slot in doll.slot_buttons:
		if str(slot).begins_with("tool:"):
			assert_eq((doll.slot_buttons[slot] as Control).visible, sk.is_unlocked(str(slot).substr(5)), str(slot))


func test_eroe_nome_del_cibo_intero_nello_slot() -> void:
	var b := EquipSlotButton.new("food:0", true)
	add_child_autofree(b)
	b.show_item(null, "Pesce del Pontile Affumicato")
	var l: Label = b._item_l
	assert_false(l.clip_text, "il nome non è tagliato")
	assert_ne(l.autowrap_mode, TextServer.AUTOWRAP_OFF, "va a capo")
	assert_gt(b.custom_minimum_size.y, EquipSlotButton.SIZE_SMALL.y, "lo slot del cibo è più alto per le righe in più")


func test_eroe_larghezza_minima_di_ogni_scheda_sta_nell_area_stretta() -> void:
	# 125% di scala a 1280x720 = area logica 1024x576: nessuna scheda deve pretendere più larghezza del contenuto disponibile
	var hs := _open(HERO)
	await wait_process_frames(3)
	var scroll := hs.get_child(0) as ScrollContainer
	var page := scroll.get_child(0) as Control
	for id in HeroScript.TAB_IDS:
		(hs.get("_tab_btns")[id] as Button).pressed.emit()
		await wait_process_frames(1)
		assert_lte(page.get_combined_minimum_size().x, 760.0, "scheda %s: larghezza minima %s" % [id, page.get_combined_minimum_size().x])


# ------------------------------------------------------------------ Talenti

func test_talenti_un_solo_riquadro_di_dettaglio_e_rango_dentro_il_nodo() -> void:
	var ts := _open(TALENTS)
	await wait_process_frames(2)
	var combat := Game.system("combat") as CombatSystem
	var rows := ts.find_children("*", "PanelContainer", true, false).filter(func(n: Node) -> bool: return n is ScreenKit.PickRow)
	assert_gt(rows.size(), 4, "nodi del ramo attivo")
	for r in rows:
		var pr := r as ScreenKit.PickRow
		assert_null(pr.pill, "il rango non è una pillola a parte")
		assert_null(pr.sub_l, "l'effetto non è una riga per nodo")
		assert_true(pr.title_l.text.contains("/"), "il rango n/N sta nel nodo: " + pr.title_l.text)
		assert_eq(pr.btn.tooltip_text, "", "il testo si legge nel riquadro di dettaglio, non in un tooltip per nodo")
	# il riquadro è uno solo e segue il nodo scelto
	var id := "warrior_toughness"
	ts.call("_show_detail", id)
	var t := combat.build.talent_def(id)
	assert_eq((ts.get("_d_name") as Label).text, Loc.t(t.name))
	assert_string_contains((ts.get("_d_meta") as Label).text, str(int(t.max_rank)))
	ts.call("_show_detail", "warrior_cleave" if not combat.build.talent_def("warrior_cleave").is_empty() else str(combat.build.talent_nodes()[1].id))
	assert_ne((ts.get("_d_name") as Label).text, Loc.t(t.name), "il riquadro cambia nodo")


func test_talenti_ramo_non_attivo_ridotto_a_icone() -> void:
	var ts := _open(TALENTS)
	await wait_process_frames(2)
	var combat := Game.system("combat") as CombatSystem
	var icons := 0
	var cards := 0
	for t in combat.build.talent_nodes():
		var entry: Dictionary = ts.get("_nodes")[str(t.id)]
		if combat.build.branch_active(str(t.branch)):
			assert_false(bool(entry.icon), str(t.id))
			cards += 1
		else:
			assert_true(bool(entry.icon), str(t.id) + ": ramo non attivo a icona")
			assert_true(entry.button is Button and not (entry.button is ScreenKit.PickRow))
			icons += 1
	assert_gt(icons, 0, "c'è almeno un ramo non attivo")
	assert_gt(cards, 4)


func test_talenti_clic_sul_nodo_compra_un_rango() -> void:
	var ts := _open(TALENTS)
	await wait_process_frames(2)
	var combat := Game.system("combat") as CombatSystem
	var free0 := combat.build.points_free()
	assert_gt(free0, 0)
	ts.call("_on_node", "warrior_toughness")
	assert_eq(combat.build.rank("warrior_toughness"), 1)
	assert_eq(combat.build.points_free(), free0 - 1)
	var pr: ScreenKit.PickRow = ts.get("_nodes")["warrior_toughness"].button
	assert_string_contains(pr.title_l.text, "1/")


func test_talenti_banner_punti_spesi_solo_la_prima_volta() -> void:
	var combat := Game.system("combat") as CombatSystem
	var guard := 0
	while combat.build.points_free() > 0 and guard < 200:
		guard += 1
		for t in combat.build.talent_nodes():
			if combat.build.rank_up(str(t.id)):
				break
	assert_eq(combat.build.points_free(), 0, "tutti i punti spesi")
	var ts := _open(TALENTS)
	await wait_process_frames(2)
	assert_true((ts.get("_hint_bar") as Control).visible, "prima volta: il banner c'è")
	assert_true(HeroKit.seen("talents_spent"))
	var ts2 := _open(TALENTS)
	await wait_process_frames(2)
	assert_false((ts2.get("_hint_bar") as Control).visible, "dalla volta dopo non più")


func test_talenti_prosa_alla_prima_visita_poi_nel_punto_interrogativo() -> void:
	var ts := _open(TALENTS)
	await wait_process_frames(2)
	assert_true((ts.get("_purpose") as Control).visible, "prima visita: la frase è aperta")
	var ts2 := _open(TALENTS)
	await wait_process_frames(2)
	assert_false((ts2.get("_purpose") as Control).visible, "poi si richiude nel «?»")


# ------------------------------------------------------------------ Prestigio

func test_prestigio_consigliere_e_obiettivo_sono_schede_a_se() -> void:
	var ps := Game.system("prestige") as PrestigeSystem
	GameState.data.skills.woodcutting.level = 100
	GameState.data.skills.woodcutting.record_level = 100
	var pr := _open(PRESTIGE)
	await wait_process_frames(2)
	pr.refresh()
	var tabs := pr.get("_tabs") as TabContainer
	assert_eq(tabs.get_tab_title(PrestigeScript.TAB_ADVISOR), tr("UI_SCR_HERO_PR_TAB_ADVISOR"))
	assert_eq(tabs.get_tab_title(PrestigeScript.TAB_GOAL), tr("UI_SCR_HERO_PR_TAB_GOAL"))
	assert_eq((pr.get("_tab_ids") as Array)[0], "star", "gli strati restano a parte, senza Consigliere/Obiettivo")
	# una scheda alla volta: il Consigliere e l'Obiettivo non sono più impilati sopra le schede
	assert_eq(tabs.current_tab, PrestigeScript.TAB_ADVISOR)
	var adv := pr.get("_adv_page") as Control
	var goal := pr.get("_goal_page") as Control
	assert_true(adv.visible)
	assert_false(goal.visible)
	assert_not_null(ps)


func test_prestigio_rifondazione_solo_se_disponibile() -> void:
	var ps := Game.system("prestige") as PrestigeSystem
	(GameState.data.unlocks as Array).append("feature:estate")
	GameState.data.skills.woodcutting.level = 100
	GameState.data.skills.woodcutting.record_level = 100
	var pr := _open(PRESTIGE)
	await wait_process_frames(2)
	pr.refresh()
	assert_true(ps.layer_visible("refound"), "lo strato esiste")
	assert_false(ps.can_refound().is_empty(), "ma non si può ancora fare")
	assert_false((pr.get("_tab_ids") as Array).has("refound"), "la scheda Rifondazione non c'è finché non è disponibile")
	ps.state["partners"] = 2
	pr.refresh()
	assert_true((pr.get("_tab_ids") as Array).has("refound"), "con dei Soci già ottenuti la scheda resta")


# ------------------------------------------------------------------ area stretta (125% di scala a 1280x720 = 1024x576)

func _main() -> Control:
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)
	Settings.set_value("tutorials", false)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	return main


func test_a_scala_125_nessun_controllo_esce_dall_area_in_eroe_talenti_prestigio() -> void:
	var old_auto: bool = bool(Settings.get_value("ui_scale_auto"))
	Settings._values["ui_scale_auto"] = false              # il fattore si fissa a mano (come in test_layout_resolutions)
	var bank := Game.system("bank") as BankSystem
	var combat := Game.system("combat") as CombatSystem
	bank.add("food_bleak", 51, "test")
	combat.set_food(0, "food_bleak")
	var main: Control = await _main()
	get_tree().root.content_scale_factor = 1.25
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_tree().root.size = Vector2i(1280, 720)
	await wait_process_frames(3)
	var view := get_tree().root.get_visible_rect()
	assert_almost_eq(view.size.x, 1024.0, 1.0, "area logica 1024 di larghezza")
	var report := PackedStringArray()
	assert_true(main.show_screen("hero"))
	await wait_process_frames(3)
	var host := main.get("_host") as Control
	for id in HeroScript.TAB_IDS:
		var hs := host.get_child(host.get_child_count() - 1)
		hs.call("_set_tab", id)
		await wait_process_frames(3)
		var bad := LayoutChecker.scan(main, view)
		if not bad.is_empty():
			report.append("Eroe/%s: %d fuori" % [id, bad.size()])
			report.append_array(LayoutChecker.worst(bad, 4))
	for sid in ["talents", "prestige"]:
		assert_true(main.show_screen(sid))
		await wait_process_frames(3)
		var bad2 := LayoutChecker.scan(main, view)
		if not bad2.is_empty():
			report.append("%s: %d fuori" % [sid, bad2.size()])
			report.append_array(LayoutChecker.worst(bad2, 4))
	Settings._values["ui_scale_auto"] = old_auto
	if not report.is_empty():
		gut.p("\n".join(report))
	assert_eq(report.size(), 0, "controlli fuori dall'area a 125% (elenco sopra)")
