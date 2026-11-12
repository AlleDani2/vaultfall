extends GutTest
## Correzioni del rapporto di revisione grafica 08 (punti 4, 10, 11, 12): menù laterale con righe uniformi e un solo tipo di segnale,
## attività in corso distinguibile dalla voce selezionata; barra alta con gruppi e icone omogenee; binario destro con didascalie;
## Deposito con i comandi in due righe. Test sulla struttura (misure, stili, nodi), non sui pixel.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"

var _old_dir: String
var _old: Dictionary = {}
var _old_size: Vector2i


func before_each() -> void:
	_old_size = get_tree().root.size
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_grafica_menu_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["tutorials", "reduce_motion", "locale", "sidebar_groups_closed", "ui_layout_rev", "right_col_visible"]:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", true)
	Settings.set_value("locale", "it")
	Settings.set_value("sidebar_groups_closed", ["*"])
	Settings.set_value("ui_layout_rev", 2)
	Settings.set_value("right_col_visible", false)
	assert_true(Game.new_game(1, "normal", 4242))


func after_each() -> void:
	DisplayServer.window_set_size(_old_size)
	get_tree().root.size = _old_size
	if Clock.paused:
		Clock.set_paused(false)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	for k in _old:
		Settings.set_value(k, _old[k])


func _unlock_all() -> void:
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)


func _main(sz: Vector2 = Vector2(1280, 720)) -> Control:
	_unlock_all()
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = sz
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	await wait_process_frames(2)
	return main


func _first_wood() -> String:
	return str(DataRegistry.actions_for_skill("woodcutting")[0].id)


# ------------------------------------------------------------------ menù laterale (punto 4)

func test_tutte_le_voci_hanno_la_stessa_altezza_e_lo_spazio_dell_icona() -> void:
	var main := await _main()
	var buttons: Dictionary = main.get("_buttons")
	assert_gt(buttons.size(), 30)
	for id in buttons:
		var b: Button = buttons[id]
		assert_almost_eq(b.custom_minimum_size.y, SidebarMenu.ROW_H, 0.01, "altezza uniforme: " + str(id))
		assert_not_null(b.icon, "ogni voce ha l'icona (o il suo spazio): " + str(id))
		assert_almost_eq(b.icon.get_size().x, MenuIcons.SIZE, 0.01, "stesso spazio per il testo: " + str(id))


func test_le_icone_riusate_esistono_a_dimensione_nativa() -> void:
	for id in MenuIcons.PATHS:
		var p := MenuIcons.path_of(str(id))
		assert_true(ResourceLoader.exists(p), "%s: %s" % [id, p])
		var t := MenuIcons.texture(str(id))
		assert_not_null(t)
		assert_eq(Vector2(t.get_size()), Vector2(MenuIcons.SIZE, MenuIcons.SIZE), "%s non va ridimensionata (D-6)" % id)


func test_i_gruppi_sono_separati_da_uno_spazio_e_da_un_filetto() -> void:
	var main := await _main()
	var list := main.find_child("List", true, false) as VBoxContainer
	var seen := 0
	for gid in (main.get("_sidebar") as SidebarMenu).group_ids():
		var h := (main.get("_sidebar") as SidebarMenu).header_button(gid)
		assert_not_null(h)
		var prev := list.get_child(h.get_index() - 1) as Control
		assert_eq(str(prev.get_meta("gap_of", "")), str(gid))
		assert_almost_eq(prev.custom_minimum_size.y, SidebarMenu.GROUP_GAP, 0.01)
		assert_almost_eq(h.custom_minimum_size.y, SidebarMenu.HEADER_H, 0.01)
		var sb := h.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(sb.border_width_top, 1, "filetto sopra l'intestazione")
		seen += 1
	assert_gt(seen, 3)


func test_un_solo_stile_di_segnale_tondo_per_numero_novita_e_pericolo() -> void:
	var main := await _main()
	var sb: SidebarMenu = main.get("_sidebar")
	for kind in [SidebarBadges.KIND_COUNT, SidebarBadges.KIND_DANGER, SidebarBadges.KIND_DOT]:
		for text in ["3", "9+", "!", ""]:
			var p := sb._new_pill()
			sb._style_pill(p, kind, text)
			var st := p.get_theme_stylebox("panel") as StyleBoxFlat
			assert_eq(st.corner_radius_top_left, int(minf(p.custom_minimum_size.x, p.custom_minimum_size.y) * 0.5), "tondo: %s «%s»" % [kind, text])
			assert_eq(st.corner_radius_top_left, st.corner_radius_bottom_right)
			assert_true(p.custom_minimum_size.y <= SidebarMenu.PILL, "mai più alto della pillola")
			p.free()
	# numero e pericolo hanno la stessa misura; la novità senza numero è lo stesso cerchio, più piccolo
	var a := sb._new_pill()
	var d := sb._new_pill()
	sb._style_pill(a, SidebarBadges.KIND_COUNT, "2")
	sb._style_pill(d, SidebarBadges.KIND_DANGER, "!")
	assert_eq(a.custom_minimum_size, d.custom_minimum_size)
	a.free()
	d.free()


func test_il_punteggio_dei_talenti_non_e_piu_testo_accanto_al_nome() -> void:
	var main := await _main()
	var sb: SidebarMenu = main.get("_sidebar")
	var b: Button = main.get("_buttons")["talents"]
	var base := b.text
	sb._set_badge("talents", 8, "UI_BADGE_TALENTS")
	assert_eq(b.text, base, "il testo della voce non cambia: niente «●8» accanto al nome")
	var badge: PanelContainer = main.get("_badges")["talents"]
	assert_true(badge.visible)
	assert_eq((badge.get_node("N") as Label).text, "8", "il numero sta dentro la pillola, come gli altri segnali")
	sb._set_badge("talents", 0, "UI_BADGE_TALENTS")
	assert_false(badge.visible)


func test_attivita_in_corso_non_e_la_voce_selezionata() -> void:
	var main := await _main()
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start(_first_wood()))
	main.call("refresh_activity_marks")
	await wait_process_frames(2)
	var buttons: Dictionary = main.get("_buttons")
	var wood: Button = buttons["skill:woodcutting"]
	var summary: Button = buttons["summary"]
	assert_true(summary.button_pressed, "il Riepilogo è la voce selezionata")
	assert_false(wood.button_pressed, "la mansione in corso NON risulta selezionata")
	# la selezione è un riempimento pieno con barra dorata; l'attività è solo un punto verde (nessun riempimento)
	var sel := summary.get_theme_stylebox("pressed") as StyleBoxFlat
	assert_eq(sel.border_width_left, 4)
	assert_eq(sel.bg_color, SidebarMenu.SEL_BG)
	assert_ne(MenuMark.LIVE, SidebarMenu.SEL_BAR, "colori diversi: verde = in corso, oro = selezionata")
	assert_ne(MenuMark.LIVE.h, SidebarMenu.SEL_BAR.h)
	var mark := wood.get_node_or_null("ActivityMark") as MenuMark
	assert_not_null(mark)
	assert_eq(mark.role, MenuActivity.ROLE_MAIN)
	assert_false(wood.get_theme_stylebox("normal") is StyleBoxTexture, "nessuna riga colorata sulla voce in corso")
	assert_eq((wood.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a, 0.0, "sfondo della voce in corso: trasparente")
	# selezionando la mansione: testo semigrassetto e barretta di sezione nascosta; la deselezione ripristina
	wood.button_pressed = true
	await wait_process_frames(1)
	assert_true(wood.has_theme_font_override("font"), "semigrassetto sulla voce selezionata")
	var bar := wood.get_node_or_null("SectionBar") as CanvasItem
	if bar != null:
		assert_false(bar.visible)
	summary.button_pressed = true
	await wait_process_frames(1)
	assert_false(wood.has_theme_font_override("font"))


# ------------------------------------------------------------------ barra alta (punto 11)

func test_barra_alta_icone_omogenee_gruppi_e_aiuto_disegnato() -> void:
	var main := await _main()
	var hb := main.get_node("Root/TopBar/HBox")
	var help := hb.get_node("HelpButton") as TopIcon
	assert_eq(help.kind, TopIcon.Kind.HELP, "il «?» ha la sua icona (prima: pausa + testo sovrapposti)")
	for n in ["PauseButton", "SaveButton", "SettingsButton", "HelpButton"]:
		assert_eq((hb.get_node(n) as Control).custom_minimum_size, TopIcon.SIZE, n)
	assert_not_null(hb.get_node_or_null("Sep"))
	assert_not_null(hb.get_node_or_null("Sep2"), "filetto anche prima dei comandi")
	assert_eq(hb.get_theme_constant("separation"), TopBar.GROUP_IN)
	for n in ["GoldChip", "BankChip", "ActivityChip"]:
		assert_almost_eq((hb.get_node(n) as Control).custom_minimum_size.y, float(TopBar.CHIP_H), 0.01, n)
	for c in hb.get_children():
		if c is Control and (c as Control).visible and not (c is VSeparator) and c.name != "Title":
			var r := (c as Control).get_global_rect()
			assert_almost_eq(r.get_center().y, hb.get_global_rect().get_center().y, 3.0, "centrato in verticale: " + str(c.name))


func test_attivita_in_barra_e_il_dato_principale() -> void:
	var main := await _main()
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start(_first_wood()))
	await wait_process_frames(4)
	var chip := main.get_node("Root/TopBar/HBox/ActivityChip") as ActivityChip
	var name_l := main.get_node("%Activity") as Label
	assert_eq(name_l.theme_type_variation, &"MonoLabel", "nome nel colore del testo, non più grigio spento")
	var bar := main.get_node("%ActivityBar") as Control
	assert_true(bar.visible)
	assert_gt(bar.custom_minimum_size.x, 100.0, "barra ben visibile")
	chip.set_compact(true)
	assert_lt(bar.custom_minimum_size.x, 100.0, "in banda stretta la barra si accorcia per prima")
	chip.set_compact(false)
	# nome, barra e tempo restano vicini: ActSpacer assorbe lo spazio
	var sp := chip.find_child("ActSpacer", true, false) as Control
	assert_not_null(sp)
	assert_true(sp.visible)
	await wait_process_frames(3)
	var eta := main.get_node("%LevelEta") as Control
	assert_lt(eta.get_global_rect().position.x - name_l.get_global_rect().end.x, 260.0, "tempo al livello vicino al nome")


# ------------------------------------------------------------------ binario destro (punto 12)

func test_binario_con_didascalie_che_stanno_nella_colonna() -> void:
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		TranslationServer.set_locale(loc)
		var main := await _main()
		var rail := main.find_child("RightRail", true, false) as Control
		var cap := rail.find_child("RailLogCap", true, false) as Label
		assert_not_null(cap)
		assert_false(cap.tr(cap.text).begins_with("UI_"), cap.text)
		assert_eq(cap.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
		var limit := RightRail.RAIL_W - 2.0 * (RightRail.RAIL_W - PushButton.SIDE) * 0.5
		assert_lte(cap.get_combined_minimum_size().x, limit, "[%s] didascalia del Registro troppo larga: %s" % [loc, cap.text])
		var pcap := rail.find_child("PushCaption", true, false) as Label
		assert_not_null(pcap, "didascalia della Sabbia")
		assert_false(pcap.tr(pcap.text).begins_with("UI_"), pcap.text)
		assert_lte(pcap.get_combined_minimum_size().x, limit, "[%s] didascalia della Sabbia: %s" % [loc, pcap.text])
		main.queue_free()
		await wait_process_frames(2)
		Game.stop_game(false)
		assert_true(Game.new_game(1, "normal", 4242))


# ------------------------------------------------------------------ Deposito (punto 10)

func _bank_screen() -> Control:
	var b := Game.system("bank") as BankSystem
	b.state.slots_bought = int(b.state.slots_bought) + 200
	var n := 0
	for d in DataRegistry.items_by_category("equipment"):
		b.add(str(d.id), 2, "test")
		n += 1
		if n >= 12:
			break
	b.add("log_pine", 40, "test")
	var scr: Control = (load(BANK_SCREEN) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scr.size = Vector2(1000, 600)             # contenuto a 1280x720 (meno menù e binario)
	scr.open({})
	return scr


func test_deposito_comandi_in_due_righe_prima_del_primo_oggetto() -> void:
	var scr := _bank_screen()
	await wait_process_frames(4)
	var tabs := scr.find_child("TabsBar", true, false) as Control
	var tools := scr.find_child("ToolsFlow", true, false) as Control
	var grid := scr.find_child("Grid", true, false) as Control
	assert_not_null(tabs)
	assert_not_null(tools)
	assert_lt(tabs.size.y, 44.0, "schede: una riga")
	assert_lt(tools.size.y, 44.0, "barra compatta: UNA riga a 1000 px di larghezza")
	var ys := {}
	for c in tools.get_children():
		if c is Control and (c as Control).visible:
			ys[int((c as Control).position.y)] = true
	assert_eq(ys.size(), 1, "tutti i comandi della barra sulla stessa riga: " + str(ys.keys()))
	assert_null(scr.find_child("GroupFlow", true, false), "le categorie non sono una terza riga")
	# fra la riga delle schede e la griglia non c'è altro che la barra compatta (e nessun avviso lungo)
	assert_lt(grid.global_position.y - tabs.global_position.y, 44.0 + 8.0 + 44.0 + 16.0, "il primo oggetto parte subito dopo le due righe")
	var welcome := scr.find_child("TabsWelcome", true, false) as Control
	if welcome != null and welcome.visible:
		assert_lt(welcome.size.y, 60.0, "avviso di benvenuto: una riga")


func test_deposito_nessuna_funzione_persa_nei_menu() -> void:
	var scr := _bank_screen()
	await wait_process_frames(3)
	# categorie
	var cm := scr.find_child("CategoryMenu", true, false) as MenuButton
	assert_not_null(cm)
	var cpop := cm.get_popup()
	assert_eq(cpop.item_count, scr.GROUPS.size() - 1, "tutte le categorie tranne l'Armeria (è una scheda)")
	var mats: int = scr._group_menu_id("materials")
	cpop.id_pressed.emit(mats)
	assert_eq(scr.get("_group"), "materials")
	assert_true(cm.text.contains(tr("UI_BANK_GROUP_MATERIALS")), cm.text)
	cpop.id_pressed.emit(scr._group_menu_id("all"))
	assert_eq(scr.get("_group"), "all")
	assert_eq(cm.text, tr("UI_GM_CAT_MENU"))
	# azioni: selezione e modalità vendita dal menù
	var sm := scr.find_child("SellMenu", true, false) as MenuButton
	assert_eq(sm.text, tr("UI_GM_ACTIONS"))
	sm.get_popup().id_pressed.emit(scr.SELL_SELECT)
	assert_eq(scr.mode(), "select")
	var si := sm.get_popup().get_item_index(scr.SELL_SELECT)
	assert_true(sm.get_popup().is_item_checked(si), "spunta sulla modalità attiva")
	sm.get_popup().id_pressed.emit(scr.SELL_SELECT)
	assert_eq(scr.mode(), "")
	# vista: griglia, lista e densità sono un solo gruppo segmentato
	var vt := scr.find_child("ViewToggle", true, false) as Control
	assert_not_null(vt.get_node_or_null("View_grid"))
	assert_not_null(vt.get_node_or_null("View_list"))
	assert_not_null(vt.get_node_or_null("DensityButton"))
	# ricerca e ordine restano nella barra
	assert_not_null(scr.get("_search"))
	assert_not_null(scr.get("_sort_opt"))
	assert_ne(str((scr.get("_sort_opt") as OptionButton).tooltip_text), "", "«Ordina per» vive nel tooltip")
	assert_not_null(scr.find_child("FiltersMenu", true, false))


func test_testi_nuovi_bilingui_senza_chiavi_nude() -> void:
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		TranslationServer.set_locale(loc)
		for k in ["UI_GM_RAIL_LOG", "UI_GM_RAIL_SAND", "UI_GM_CAT_MENU", "UI_GM_CAT_TIP", "UI_GM_ACTIONS", "UI_GM_ACTIONS_TIP", "UI_GM_BANK_NOTICE"]:
			assert_ne(tr(k), k, "%s tradotta (%s)" % [k, loc])
	TranslationServer.set_locale("it")
	assert_eq(Loc.tf("UI_GM_CAT_MENU_ON", {"name": "Materiali"}), "Materiali ▾")
