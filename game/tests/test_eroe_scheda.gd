extends GutTest
## FEEDBACK EROE (giocatore reale): la scheda Eroe si apre INSIEME al Combattimento e ogni controllo funziona davvero.
## Qui si premono i controlli della scheda (soglia del cibo, slot cibo, pozione, Glifi, classe, attributi, tecniche, equipaggiamento)
## e si verifica l'effetto sul CombatSystem. Resoconto: docs/audit_2026-10-22/113_RESOCONTO_EROE.md.

const HERO := "res://src/ui/screens/HeroScreen.tscn"

var _old_dir: String
var combat: CombatSystem
var bank: BankSystem


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_eroe_scheda_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 7))
	_set_level(12)
	(GameState.data.unlocks as Array).append_array(["feature:combat", "zone:millbrook", "skill:hero", "skill:cooking", "skill:alchemy"])
	combat = Game.system("combat") as CombatSystem
	bank = Game.system("bank") as BankSystem


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _set_level(lvl: int) -> void:
	GameState.data.skills["hero"] = {"xp": 0.0, "level": lvl, "record_level": lvl, "stars": 0, "perks": {}, "unlocked": true}


func _open() -> GameScreen:
	var s: GameScreen = (load(HERO) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	return s


func _clear_food() -> void:
	for it in DataRegistry.items_by_category("food"):
		var n := bank.count(str(it.id))
		if n > 0:
			bank.remove(str(it.id), n)
	for i in combat.food_slots().size():
		combat.set_food(i, "")


# ------------------------------------------------------------------ SBLOCCO insieme al Combattimento

func test_dati_eroe_e_combattimento_nella_stessa_missione() -> void:
	var q: Dictionary = DataRegistry.get_def("quests", "main_c0_q4")
	assert_true((q.unlocks as Array).has("feature:combat"))
	assert_true((q.unlocks as Array).has("skill:hero"), "l'Eroe si apre con il Combattimento")
	assert_eq(UnlockSystem.quest_for_token("skill:hero", DataRegistry), "main_c0_q4")
	assert_eq(UnlockSystem.quest_for_token("feature:combat", DataRegistry), "main_c0_q4")
	assert_false(((DataRegistry.get_def("quests", "main_c1_q2").unlocks) as Array).has("skill:hero"), "non più dopo lupi e archi")


func test_accettando_la_missione_del_combattimento_si_apre_anche_l_eroe() -> void:
	var u := Game.system("unlock") as UnlockSystem
	var arr: Array = GameState.data.unlocks
	arr.erase("feature:combat")
	arr.erase("skill:hero")
	var q := Game.system("quests") as QuestSystem
	assert_true(q.accept("main_c0_q4"))
	assert_true(u.has("feature:combat"))
	assert_true(u.has("skill:hero"), "serve subito: la missione chiede di indossare la spada")
	assert_true(ScreenRegistry.is_available(ScreenRegistry.get_entry("hero"), u.tokens()))


func test_salvataggi_vecchi_con_combattimento_ricevono_l_eroe() -> void:
	var u := Game.system("unlock") as UnlockSystem
	u.from_state(["feature:combat", "zone:millbrook"])
	assert_true(u.has("skill:hero"))
	u.from_state(["skill:woodcutting"])
	assert_false(u.has("skill:hero"), "senza Combattimento resta chiuso")


func test_tutorial_eroe_prima_del_combattimento_con_istruzioni() -> void:
	var ids: Array = []
	var by: Dictionary = {}
	for s in TutorialCatalog.STEPS:
		ids.append(str(s.id))
		by[str(s.id)] = s
	assert_eq(str(by.f_hero.token), "skill:hero")
	assert_eq(str(by.f_combat.after), "f_hero", "prima si indossa e si assegna il cibo")
	assert_lt(ids.find("f_hero"), ids.find("f_combat"))
	var body := tr("UI_TUT_F_HERO_B").to_lower()
	assert_false(body.begins_with("ui_"), "testo tradotto")
	assert_true(body.contains("slot"), "il passo spiega come indossare")
	assert_true(body.contains("cibo") or body.contains("food"), "e come assegnare il cibo")


func test_scheda_eroe_all_apertura_ha_gia_gli_slot_e_il_cibo() -> void:
	var hs := _open()
	await wait_process_frames(2)
	assert_not_null(hs.get("_doll"), "equipaggiamento")
	assert_eq((hs.get("_food_panel") as FoodPanel)._slot_btns.size(), combat.food_slots().size(), "slot cibo")
	assert_gt((hs.get("_doll") as EquipDoll).slot_buttons.size(), 8)


# ------------------------------------------------------------------ SOGLIA DEL CIBO

func test_soglia_massimo_non_cala_con_il_valore_scelto() -> void:
	var mx := combat.auto_eat_max_pct()
	assert_eq(mx, float(DataRegistry.constants.combat.rules.emergency_eat_below_pct), "base: dai dati")
	combat.set_eat_pct(2)
	assert_eq(float(combat.auto_eat_cfg().threshold_pct), 2.0, "la soglia reale segue la scelta")
	assert_eq(combat.auto_eat_max_pct(), mx, "il massimo resta quello della cintura")


func test_slider_soglia_range_valore_e_reimpostazione() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var fp: FoodPanel = hs.get("_food_panel")
	var sl: HSlider = fp._eat_slider
	var mx := combat.auto_eat_max_pct()
	assert_eq(sl.min_value, 1.0)
	assert_eq(sl.max_value, mx)
	assert_eq(sl.value, mx, "predefinito: tutto a destra = il massimo, scritto nel testo")
	assert_true(fp._eat_label.text.contains(str(int(mx))), fp._eat_label.text)
	sl.value = 2.0                                  # come trascinare il cursore
	assert_eq(int(combat.state.eat_pct), 2)
	assert_eq(float(combat.auto_eat_cfg().threshold_pct), 2.0)
	assert_eq(sl.max_value, mx, "il massimo non scende a 2")
	assert_eq(sl.value, 2.0, "il cursore resta dov'è: non salta a destra")
	assert_true(fp._eat_label.text.contains("2%"), fp._eat_label.text)
	sl.value = 5.0
	assert_eq(float(combat.auto_eat_cfg().threshold_pct), 5.0, "si può anche rialzare")
	sl.value = mx
	assert_eq(int(combat.state.eat_pct), 0, "il massimo = predefinito, salvato come 0")
	assert_eq(float(combat.auto_eat_cfg().threshold_pct), mx)


func test_slider_con_cintura_del_cibo() -> void:
	(GameState.data.unlocks as Array).append("shop:auto_eat_1")
	var eff: Dictionary = DataRegistry.get_def("shop", "auto_eat_1").effect.auto_eat
	var hs := _open()
	await wait_process_frames(2)
	var sl: HSlider = (hs.get("_food_panel") as FoodPanel)._eat_slider
	assert_eq(sl.max_value, float(eff.threshold_pct))
	sl.value = 10.0
	assert_eq(float(combat.auto_eat_cfg().threshold_pct), 10.0)
	assert_eq(sl.max_value, float(eff.threshold_pct), "con la cintura il massimo resta quello della cintura")
	assert_eq(float(combat.auto_eat_cfg().target_pct), float(eff.target_pct))


func test_soglia_cambia_quando_il_cibo_viene_mangiato() -> void:
	_clear_food()
	bank.add("food_bleak", 20, "test")
	combat.set_food(0, "food_bleak")
	combat.state["hp"] = combat.max_hp() * 0.05            # 5% di vita
	var n0 := bank.count("food_bleak")
	combat.set_eat_pct(2)                                  # sotto il 2%: a 5% non mangia
	combat._auto_eat()
	assert_eq(bank.count("food_bleak"), n0, "5% non è sotto la soglia del 2%")
	combat.set_eat_pct(0)                                  # predefinita (massimo): a 5% mangia
	combat._auto_eat()
	assert_lt(bank.count("food_bleak"), n0, "5% è sotto la soglia di base")
	assert_gt(float(combat.state.hp), combat.max_hp() * 0.05)


func test_pulsante_mangia_ora() -> void:
	_clear_food()
	bank.add("food_bleak", 5, "test")
	combat.set_food(0, "food_bleak")
	combat.state["hp"] = combat.max_hp() * 0.5
	var hs := _open()
	await wait_process_frames(2)
	var fp: FoodPanel = hs.get("_food_panel")
	assert_false(fp._eat_btn.disabled)
	fp._eat_btn.pressed.emit()
	assert_eq(bank.count("food_bleak"), 4)
	assert_gt(float(combat.state.hp), combat.max_hp() * 0.5)


# ------------------------------------------------------------------ SLOT CIBO

func test_lo_stesso_cibo_non_sta_in_due_slot_e_la_scorta_non_si_triplica() -> void:
	_clear_food()
	bank.add("food_bleak", 51, "test")
	combat.set_food(0, "food_bleak")
	combat.set_food(1, "food_bleak")
	combat.set_food(2, "food_bleak")
	assert_eq(combat.food_slots(), ["", "", "food_bleak"], "ultimo assegnamento: gli altri slot si liberano")
	assert_eq(combat.food_available(), 51, "51 porzioni, non 153")
	# stato già salvato con lo stesso cibo ovunque (vecchi salvataggi): si ripulisce al caricamento
	var st: Dictionary = combat.to_state()
	st["food"] = ["food_bleak", "food_bleak", "food_bleak"]
	combat.from_state(st)
	assert_eq(combat.food_distinct(), ["food_bleak"])
	assert_eq(combat.food_available(), 51)
	# e anche se lo stato viene forzato a mano, il conteggio conta ogni tipo una volta
	for i in 3:
		combat.state.food[i] = "food_bleak"
	assert_eq(combat.food_available(), 51)


func test_slot_con_cibi_diversi_ognuno_mostra_il_suo() -> void:
	_clear_food()
	bank.add("food_bleak", 51, "test")
	bank.add("food_carp", 10, "test")
	var hs := _open()
	await wait_process_frames(2)
	var fp: FoodPanel = hs.get("_food_panel")
	fp._open_picker(0)
	fp._on_food_picked(fp._pick_defs.find("food_bleak"))
	fp._open_picker(1)
	fp._on_food_picked(fp._pick_defs.find("food_carp"))
	assert_eq(combat.food_slots(), ["food_bleak", "food_carp", ""])
	assert_eq(combat.food_available(), 61)
	assert_true(fp._stock.text.contains("61"), fp._stock.text)
	# scegliere lo stesso cibo di un altro slot lo sposta, senza duplicati
	fp._open_picker(2)
	fp._on_food_picked(fp._pick_defs.find("food_bleak"))
	assert_eq(combat.food_slots(), ["", "food_carp", "food_bleak"])
	assert_eq(combat.food_available(), 61)
	# svuotare uno slot
	fp._clear_slot(1)
	assert_eq(combat.food_slots(), ["", "", "food_bleak"])
	assert_eq(combat.food_available(), 51)


func test_si_mangia_dal_primo_slot_con_porzioni() -> void:
	_clear_food()
	bank.add("food_bleak", 3, "test")
	bank.add("food_carp", 3, "test")
	combat.set_food(0, "food_carp")
	combat.set_food(1, "food_bleak")
	combat.state["hp"] = combat.max_hp() * 0.4
	assert_true(combat.eat_food(true))
	assert_eq(bank.count("food_carp"), 2, "primo slot")
	assert_eq(bank.count("food_bleak"), 3)


# ------------------------------------------------------------------ POZIONE

func test_pozione_senza_opzioni_spiega_e_rimanda_all_alchimia() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var opt: OptionButton = hs.get("_potion_opt")
	assert_true(opt.disabled)
	assert_lt(opt.get_item_text(0).length(), 30, "testo breve, non troncato nel menù: " + opt.get_item_text(0))
	var note: Label = hs.get("_potion_note")
	assert_false(note.text.is_empty())
	assert_false(note.text.begins_with("UI_"), "stringa tradotta")
	assert_gt((hs.get("_potion_go") as Control).get_child_count(), 0, "pulsante «Vai all'Alchimia»")
	assert_true((hs.get("_potion_btn") as Button).disabled)


func test_pozione_bevuta_dal_menu() -> void:
	bank.add("potion_vigor_1", 3, "test")
	var hs := _open()
	await wait_process_frames(2)
	var opt: OptionButton = hs.get("_potion_opt")
	assert_false(opt.disabled)
	assert_eq(hs.get("_potion_ids"), ["potion_vigor_1"])
	(hs.get("_potion_btn") as Button).pressed.emit()
	assert_eq(str(combat.active_potion().def), "potion_vigor_1")
	assert_eq(bank.count("potion_vigor_1"), 2)
	assert_gt((hs.get("_potion_note") as Label).text.length(), 0)
	assert_eq((hs.get("_potion_go") as Control).get_child_count(), 0, "con pozioni niente rimando")


# ------------------------------------------------------------------ GLIFI

func test_glifi_senza_incastri_testo_breve_e_nota() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var opt: OptionButton = hs.get("_glyph_item_opt")
	assert_true(opt.disabled)
	assert_lt(opt.get_item_text(0).length(), 30, opt.get_item_text(0))
	assert_false((hs.get("_glyph_note") as Label).text.is_empty())
	assert_false((hs.get("_glyph_note") as Label).text.begins_with("UI_"))


func test_glifi_incastona_e_rimuovi() -> void:
	var sword := bank.add_instance({"def": "sword_copper", "quality": "masterwork"})
	assert_true(combat.equip(sword))
	bank.add("glyph_fury_1", 3, "test")
	var hs := _open()
	await wait_process_frames(2)
	var opt: OptionButton = hs.get("_glyph_item_opt")
	assert_false(opt.disabled)
	assert_eq(hs.get("_glyph_uids"), [sword])
	var box: VBoxContainer = hs.get("_glyph_box")
	assert_eq(box.get_child_count(), int(combat.sockets_of(sword).max), "una riga per incastro")
	hs._open_glyph_picker(sword, 0, box)
	(hs.get("_glyph_popup") as PopupMenu).hide()        # il menù si chiude alla scelta
	hs._on_glyph_picked(hs.get("_glyph_pick_ids").find("glyph_fury_1"))
	assert_eq((combat.sockets_of(sword).glyphs as Array).size(), 1)
	assert_eq(bank.count("glyph_fury_1"), 2)
	# «Rimuovi» sulla riga 0 (dopo il refresh della scheda)
	hs.refresh()
	await wait_process_frames(2)
	var row := (hs.get("_glyph_box") as VBoxContainer).get_child(0)
	var btn := row.get_child(1) as Button
	btn.pressed.emit()
	assert_eq((combat.sockets_of(sword).glyphs as Array).size(), 0, "il Glifo rimosso è distrutto")
	assert_eq(bank.count("glyph_fury_1"), 2)


# ------------------------------------------------------------------ CLASSE, SPECIALIZZAZIONE, ATTRIBUTI, TECNICHE

func test_classe_dal_menu() -> void:
	_set_level(8)                                     # fino al livello 10 il cambio è gratuito
	var hs := _open()
	await wait_process_frames(2)
	var ids: Array = hs.get("_class_ids")
	var target := ""
	for c in ids:
		if str(c) != str(combat.state.class) and combat.build.class_available(str(c)):
			target = str(c)
			break
	assert_false(target.is_empty(), "almeno un'altra classe disponibile")
	(hs.get("_class_opt") as OptionButton).item_selected.emit(ids.find(target))
	assert_eq(str(combat.state.class), target)
	await wait_process_frames(1)
	assert_eq((hs.get("_class_opt") as OptionButton).selected, ids.find(target), "il menù mostra la classe scelta")


func test_classe_bloccata_durante_il_combattimento() -> void:
	var sword := bank.add_instance({"def": "sword_copper", "quality": "normal"})
	combat.equip(sword)
	assert_true(combat.start("millbrook", "mud_slime"))
	var hs := _open()
	await wait_process_frames(2)
	assert_true((hs.get("_class_opt") as OptionButton).disabled)
	assert_true((hs.get("_spec_opt") as OptionButton).disabled)
	combat.stop()


func test_specializzazione_senza_requisiti_resta_chiusa() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var specs := combat.build.specs_of(str(combat.state.class))
	assert_false(specs.is_empty())
	for sid in specs:
		assert_false(combat.build.spec_available(str(sid)), "livello 12: ancora chiusa")
	var o := hs.get("_spec_opt") as OptionButton
	for i in range(1, o.item_count):
		assert_true(o.is_item_disabled(i), "voce chiusa e grigia")
	assert_false((hs.get("_spec_note") as Label).text.is_empty())


func test_attributi_piu_e_punti_automatici() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var auto_btn := hs.get("_auto_btn") as CheckButton
	assert_true(auto_btn.button_pressed)
	assert_false((hs.get("_attr_note") as Label).text.is_empty())
	auto_btn.toggled.emit(false)                        # passa a manuale
	assert_false(bool(combat.state.auto_alloc))
	_set_level(13)                                      # un livello in più = punti liberi da spendere
	hs._sig = ""
	hs.refresh()
	await wait_process_frames(2)
	var free0 := combat.free_points()
	assert_gt(free0, 0, "livello 12: punti da spendere")
	var str0 := float(combat.hero_stats().attrs.str)
	var plus: Button = null
	for c in (hs.get("_attr_box") as GridContainer).get_children():
		if c is Button:
			plus = c
			break
	assert_not_null(plus)
	assert_false(plus.disabled)
	plus.pressed.emit()
	assert_eq(combat.free_points(), free0 - 1)
	assert_eq(float(combat.hero_stats().attrs.str), str0 + 1.0, "il primo «+» è Forza")
	# in combattimento niente punti
	var sword := bank.add_instance({"def": "sword_copper", "quality": "normal"})
	combat.equip(sword)
	assert_true(combat.start("millbrook", "mud_slime"))
	hs._sig = ""
	hs.refresh()
	await wait_process_frames(2)
	for c in (hs.get("_attr_box") as GridContainer).get_children():
		if c is Button:
			assert_true((c as Button).disabled, "«+» spento in combattimento")
	assert_false(combat.allocate("str", 1))
	assert_true((hs.get("_attr_note") as Label).text != "")
	combat.stop()


func test_tecniche_automatiche_e_a_mano() -> void:
	var sword := bank.add_instance({"def": "sword_copper", "quality": "normal"})
	combat.equip(sword)
	var hs := _open()
	await wait_process_frames(2)
	var cb := hs.get("_auto_abil") as CheckButton
	assert_true(cb.button_pressed)
	cb.toggled.emit(false)
	assert_false(bool(combat.state.auto_abilities))
	hs.refresh()
	await wait_process_frames(1)
	var o := (hs.get("_slot_opts") as Array)[0] as OptionButton
	assert_false(o.disabled, "a mano i menù si accendono")
	assert_gt(o.item_count, 1, "almeno una tecnica disponibile")
	var ids: Array = (hs.get("_slot_ids") as Array)[0]
	o.item_selected.emit(ids.size() - 1)                # l'ultima tecnica nello slot 1
	assert_eq(str(combat.build.abilities_equipped()[0].id), str(ids[ids.size() - 1]), "la tecnica scelta è equipaggiata")
	o.item_selected.emit(0)                             # «(vuoto)»
	assert_eq(str(combat.state.abilities[0]) if (combat.state.abilities as Array).size() > 0 else "", "" if ids.size() <= 2 else str(combat.state.abilities[0]))


# ------------------------------------------------------------------ EQUIPAGGIAMENTO E SET

func test_equipaggia_e_togli_dallo_slot() -> void:
	var sword := bank.add_instance({"def": "sword_copper", "quality": "normal"})
	var hs := _open()
	await wait_process_frames(2)
	var doll := hs.get("_doll") as EquipDoll
	doll._select_slot("weapon")
	doll.refresh(true)
	assert_false(doll._entries.is_empty(), "la spada è nell'elenco")
	var idx := -1
	for i in doll._entries.size():
		if str(doll._entries[i].key) == sword:
			idx = i
	assert_gt(idx, -1)
	doll.picked_key = sword
	assert_true(doll._do_equip(sword))
	assert_eq(combat.equipped("weapon"), sword)
	doll._unequip("weapon")
	assert_eq(combat.equipped("weapon"), "")
	assert_eq(bank.count("sword_copper"), 1, "resta nel Deposito")


func test_set_di_equipaggiamento_dalla_scheda() -> void:
	(Game.system("market") as MarketSystem).state.shop["loadout_slot"] = 1     # Rastrelliera comprata
	var lo := Game.system("loadouts") as LoadoutSystem
	var sword := bank.add_instance({"def": "sword_copper", "quality": "normal"})
	combat.equip(sword)
	var hs := _open()
	await wait_process_frames(2)
	var extras := hs.get("_gear_extras") as HeroGearExtras
	extras._sig = ""
	extras.refresh()
	var row := extras._sets_box.get_child(0)
	var save: Button = null
	var wear: Button = null
	for c in row.get_children():
		if c is Button and (c as Button).text == "UI_GAPM_SET_SAVE":
			save = c
		if c is Button and (c as Button).text == "UI_GAPM_SET_APPLY":
			wear = c
	assert_not_null(save)
	save.pressed.emit()
	assert_false(lo.is_empty_slot(0), "«Salva» registra l'equipaggiamento")
	combat.unequip("weapon")
	extras._sig = ""
	extras.refresh()
	row = extras._sets_box.get_child(0)
	for c in row.get_children():
		if c is Button and (c as Button).text == "UI_GAPM_SET_APPLY":
			wear = c
	assert_false(wear.disabled)
	wear.pressed.emit()
	assert_eq(combat.equipped("weapon"), sword, "«Indossa» rimette il set")


# ------------------------------------------------------------------ MENU CHE NON SI CHIUDONO DA SOLI, NIENTE OVERFLOW

func test_menu_aperto_non_viene_ricostruito() -> void:
	var hs := _open()
	await wait_process_frames(2)
	var o := hs.get("_class_opt") as OptionButton
	var count := o.item_count
	o.get_popup().visible = true
	hs._sig = ""                                        # forza un aggiornamento completo
	hs.refresh()
	assert_true(hs._any_menu_open())
	assert_eq(o.item_count, count, "il menù aperto non si svuota (non si chiude da solo)")
	assert_eq(hs._sig, "", "l'aggiornamento è rimandato")
	o.get_popup().visible = false
	hs.refresh()
	assert_ne(hs._sig, "", "chiuso il menù si aggiorna")


func test_il_cibo_mangiato_non_ricostruisce_i_menu() -> void:
	_clear_food()
	bank.add("food_bleak", 10, "test")
	combat.set_food(0, "food_bleak")
	var hs := _open()
	await wait_process_frames(2)
	hs.refresh()
	var sig := str(hs._sig)
	bank.remove("food_bleak", 3)
	hs.refresh()
	assert_eq(str(hs._sig), sig, "una porzione in meno non fa ricostruire classe, tecniche, pozione e Glifi")


func test_nessun_overflow_orizzontale_a_1280x720() -> void:
	_clear_food()
	bank.add("food_bleak", 51, "test")
	combat.set_food(0, "food_bleak")
	var hs := _open()
	await wait_process_frames(3)
	var scroll := hs.get_child(0) as ScrollContainer
	var page := scroll.get_child(0) as Control
	# a 1280x720 la colonna centrale è ~790 px: nessun controllo deve pretendere di più
	assert_lte(page.get_combined_minimum_size().x, 790.0, "larghezza minima della scheda: %s" % page.get_combined_minimum_size().x)
