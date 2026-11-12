extends GutTest
## Menù laterale a gruppi e segnali a tre tipi (progetto di interfaccia, docs/ui_redesign/06 D14, D15, D29; fase F4).
## Segnali (numero ambra / puntino / rosso) con fixture dei sistemi, tetti (9+, ≤ 5 numeri e puntini), priorità, Recenti,
## gruppi che si chiudono e si ricordano, somma e segno sull'intestazione, bersaglio del tutorial, tasti 1-9, larghezza 200 px.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _old_dir: String
var _old: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_sidebar_groups_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["tutorials", "reduce_motion", "locale", "sidebar_groups_closed"]:
		_old[k] = Settings.get_value(k)
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", true)
	Settings.set_value("locale", "it")
	Settings.set_value("sidebar_groups_closed", ["*"])           # di partenza: tutto aperto (il predefinito dipende dall'altezza)
	assert_true(Game.new_game(1, "normal", 4242))


func after_each() -> void:
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


func _main(all_unlocked: bool = true, h: float = 1000.0) -> Control:
	if all_unlocked:
		_unlock_all()
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, h)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	await wait_process_frames(2)
	return main


func _sb(main: Control) -> SidebarMenu:
	return main.get("_sidebar") as SidebarMenu


func _slow(main: Control) -> void:
	main.call("_update_slow")


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _crates(n: int) -> void:
	var cs := Game.system("crates") as CrateSystem
	_bank().add("crate_millbrook", n, "test")
	var key: Variant = cs.crate_def("crate_millbrook").get("key")
	if key != null:
		_bank().add(str(key), n, "test")


func _fill_bank() -> void:
	var i := 0
	while not _bank().is_full():
		_bank().state.stacks["zz_fill_%d" % i] = 1
		i += 1


func _quest_ready() -> void:
	var q := Game.system("quests") as QuestSystem
	var qid := q.current_main()
	var pr: Array = []
	for o in q.quest_def(qid).objectives:
		pr.append(QuestSystem.target_of(o))
	q.state.progress[qid] = pr


# ------------------------------------------------------------------ segnali: i tre tipi

func test_numero_ambra_per_azioni_possibili_adesso() -> void:
	_crates(2)
	_quest_ready()
	var s := SidebarBadges.signals()
	assert_eq(s["vault_hall"].kind, SidebarBadges.KIND_COUNT)
	assert_gt(int(s["vault_hall"].n), 0)
	assert_eq(s["quests"].kind, SidebarBadges.KIND_COUNT, "missione da riscattare = numero")
	assert_eq(int(s["quests"].n), (Game.system("quests") as QuestSystem).ready_count(), "solo i riscatti, non i passi di scoperta")
	assert_eq(s["vault_hall"].causes[0][0], "UI_UIB_BADGE_CRATES", "una riga di tooltip per causa")


func test_puntino_per_novita_non_urgenti() -> void:
	var q := Game.system("quests") as QuestSystem
	assert_gt(QuestGuide.discoveries(q).size(), 0, "a inizio partita ci sono passi di scoperta")
	var s := SidebarBadges.signals()
	assert_eq(s["quests"].kind, SidebarBadges.KIND_DOT, "i passi di scoperta sono un puntino, non un numero")
	assert_eq(int(s["quests"].n), 0)


func test_rosso_solo_per_pericolo_in_corso() -> void:
	var s0 := SidebarBadges.signals()
	for id in s0:
		assert_ne(s0[id].kind, SidebarBadges.KIND_DANGER, "nessun rosso senza pericoli: " + id)
	# 1) Deposito pieno
	_fill_bank()
	var s1 := SidebarBadges.signals()
	assert_eq(s1["bank"].kind, SidebarBadges.KIND_DANGER)
	assert_eq(s1["bank"].causes[0][0], SidebarBadges.CAUSE_DANGER_BANK)
	for id in s1:
		if id != "bank":
			assert_ne(s1[id].kind, SidebarBadges.KIND_DANGER, "solo il Deposito è rosso: " + id)
	# 2) Dispensa vuota della Tenuta (con coloni)
	_bank().state.stacks.erase("zz_fill_0")
	(GameState.data.unlocks as Array).append("feature:estate")
	var es := Game.system("estate") as EstateSystem
	es.state["settlers"] = 2
	es.state["pantry"] = 0.0
	var s2 := SidebarBadges.signals()
	assert_eq(s2["estate"].kind, SidebarBadges.KIND_DANGER)
	assert_eq(s2["estate"].causes[0][0], SidebarBadges.CAUSE_DANGER_PANTRY)
	es.state["pantry"] = 50.0
	assert_false(SidebarBadges.signals().has("estate") and SidebarBadges.signals()["estate"].kind == SidebarBadges.KIND_DANGER, "con la Dispensa piena niente rosso")


func test_rosso_cibo_finito_con_combattimento_a_rischio() -> void:
	var cb := Game.system("combat") as CombatSystem
	assert_eq(cb.food_available(), 0)
	var found := ""
	for z in cb.zones():
		var zid := str(z.id)
		if cb.start(zid):
			if str(CloseGuard.combat_status().get("level", "")) == "red":
				found = zid
				break
			cb.stop()
	assert_false(found.is_empty(), "esiste una zona 'rossa' per un eroe di livello 1 senza cibo")
	if found.is_empty():
		return
	var s := SidebarBadges.signals()
	assert_eq(s["combat"].kind, SidebarBadges.KIND_DANGER)
	assert_eq(s["combat"].causes[0][0], SidebarBadges.CAUSE_DANGER_FOOD)


func test_nessun_rosso_se_c_e_cibo_anche_con_il_combattimento_a_rischio() -> void:
	var cb := Game.system("combat") as CombatSystem
	var started := false
	for z in cb.zones():
		if cb.start(str(z.id)) and str(CloseGuard.combat_status().get("level", "")) == "red":
			started = true
			break
	assert_true(started, "esiste una zona 'rossa' per un eroe di livello 1")
	if not started:
		return
	var food := str(DataRegistry.items_by_category("food")[0].id)
	_bank().add(food, 20, "test")
	assert_true(cb.set_food(0, food))
	assert_gt(cb.food_available(), 0)
	var s := SidebarBadges.signals()
	assert_false(s.has("combat") and s["combat"].kind == SidebarBadges.KIND_DANGER, "con il cibo niente rosso")


# ------------------------------------------------------------------ tetti e priorità

func test_tetto_9_piu() -> void:
	assert_eq(SidebarBadges.label(9), "9")
	assert_eq(SidebarBadges.label(10), "9+")
	assert_eq(SidebarBadges.label(250), "9+")
	assert_eq(SidebarBadges.MAX_SHOWN, 9)


func test_pillola_con_nove_piu_disegnata_nel_menu() -> void:
	_crates(12)
	var main := await _main()
	_slow(main)
	var n := int(SidebarBadges.signals()["vault_hall"].n)
	assert_gt(n, 9, "più di nove casse apribili")
	var badge := main._badges["vault_hall"] as PanelContainer
	assert_true(badge.visible)
	assert_eq((badge.get_node("N") as Label).text, "9+")


func test_massimo_cinque_numeri_con_la_priorita_giusta() -> void:
	assert_eq(Array(SidebarBadges.NUMBER_ORDER), ["quests", "vault_hall", "skill:farming", "orders", "events"], "Missioni > Casse > raccolti > Commesse > Eventi")
	var order: Array = ["quests", "vault_hall", "skill:farming", "orders", "events", "extra_a", "extra_b"]
	var raw := {"quests": 1, "vault_hall": 2, "skill:farming": 3, "orders": 4, "events": 5, "extra_a": 6, "extra_b": 7}
	var p := SidebarBadges.pick_numbers(raw, order, SidebarBadges.MAX_NUMBERS)
	assert_eq(p.numbers.size(), 5, "al massimo cinque voci con il numero")
	assert_eq(p.numbers.keys(), ["quests", "vault_hall", "skill:farming", "orders", "events"])
	assert_eq(p.overflow.keys(), ["extra_a", "extra_b"], "le altre passano a puntino")
	# se i candidati sono più dei posti, restano quelli a priorità più alta
	var p2 := SidebarBadges.pick_numbers({"quests": 1, "orders": 2, "events": 3}, order, 2)
	assert_eq(p2.numbers.keys(), ["quests", "orders"])
	assert_eq(p2.overflow.keys(), ["events"])
	assert_eq(SidebarBadges.MAX_NUMBERS, 5)


func test_massimo_cinque_puntini() -> void:
	var out: Dictionary = {}
	var dots := 0
	for i in 8:
		dots = SidebarBadges._add_dot(out, "voce_%d" % i, ["X", 1], dots)
	assert_eq(out.size(), 5)
	assert_eq(dots, 5)
	dots = SidebarBadges._add_dot(out, "voce_0", ["Y", 2], dots)
	assert_eq((out["voce_0"].causes as Array).size(), 2, "una voce che ha già il puntino accumula le cause")
	assert_eq(dots, 5)


func test_conteggio_a_60_ore_resta_entro_cinque_numeri() -> void:
	_crates(3)
	_quest_ready()
	var s := SidebarBadges.signals()
	var numbers := 0
	for id in s:
		if s[id].kind == SidebarBadges.KIND_COUNT:
			numbers += 1
	assert_lte(numbers, SidebarBadges.MAX_NUMBERS)


# ------------------------------------------------------------------ Recenti e talenti

func _perk_ready(skill: String) -> void:
	var sk := Game.system("skills") as SkillSystem
	(GameState.data.unlocks as Array).append("skill:" + skill)
	sk.state[skill]["level"] = 30
	assert_gt(sk.pending_perk_tiers(skill).size(), 0)


func test_puntino_dei_talenti_solo_per_le_recenti() -> void:
	_perk_ready("woodcutting")
	_perk_ready("mining")
	var both := SidebarBadges.perk_counts()
	assert_true(both.has("skill:woodcutting") and both.has("skill:mining"))
	var s := SidebarBadges.signals({"recent": ["skill:woodcutting"]})
	assert_true(s.has("skill:woodcutting"))
	assert_eq(s["skill:woodcutting"].kind, SidebarBadges.KIND_DOT)
	assert_false(s.has("skill:mining"), "mansione fuori dalle Recenti: nessun puntino")
	assert_eq(SidebarBadges.counts()["skill:mining"], both["skill:mining"], "counts() resta compatibile")


func test_recenti_ultime_cinque_e_a_inizio_partita_si_vedono_tutte() -> void:
	var main := await _main(false)
	var sb := _sb(main)
	var avail := 0
	for id in sb._skill_ids:
		if sb._avail_ids.has(id):
			avail += 1
	assert_lt(avail, SidebarMenu.RECENT_MAX, "a inizio partita le mansioni sbloccate sono poche")
	for id in sb._skill_ids:
		if sb._avail_ids.has(id):
			assert_true((main._buttons[id] as Button).visible, "si vede " + str(id))
		else:
			assert_false((main._buttons[id] as Button).visible, "le bloccate stanno sotto «Tutte»: " + str(id))


func test_recenti_si_aggiornano_con_le_mansioni_aperte() -> void:
	var main := await _main()
	var sb := _sb(main)
	var ids: Array = sb._skill_ids.duplicate()
	assert_gt(ids.size(), 8)
	for i in 7:
		assert_true(main.show_screen(str(ids[i]), ScreenRegistry.get_entry(str(ids[i])).get("params", {})))
	var rec := sb.recent_skills()
	assert_eq(rec.size(), SidebarMenu.RECENT_MAX)
	assert_eq(rec[0], ids[6], "la più recente per prima")
	assert_false(rec.has(ids[0]), "le più vecchie escono")
	assert_eq((GameState.data["ui"] as Dictionary)["recent_skills"], rec, "salvato in GameState.data.ui")
	await wait_process_frames(1)
	var visible_skills := 0
	for id in ids:
		if (main._buttons[id] as Button).visible:
			visible_skills += 1
	assert_eq(visible_skills, SidebarMenu.RECENT_MAX, "a «Tutte» chiusa si vedono le Recenti")
	assert_true(sb.all_row().visible)
	assert_true(sb.all_row().text.contains("(%d)" % ids.size()), sb.all_row().text)
	assert_true(sb.all_row().text.ends_with("▸"))
	sb.all_row().pressed.emit()
	await wait_process_frames(1)
	for id in ids:
		assert_true((main._buttons[id] as Button).visible, "«Tutte» aperta: " + str(id))
	assert_true(sb.all_row().text.ends_with("▾"))
	assert_true(bool((GameState.data["ui"] as Dictionary)["all_skills_open"]), "ricordato")


func test_campo_ui_mancante_vale_vuoto_e_sopravvive_al_salvataggio() -> void:
	var main := await _main()
	var sb := _sb(main)
	GameState.data.erase("ui")
	assert_eq(sb.recent_skills(), [])
	assert_false(sb.all_skills_open())
	assert_false(sb.coop_used())
	main.show_screen("skill:mining", {"skill": "mining"})
	var copy: Variant = JSON.parse_string(JSON.stringify(GameState.data["ui"]))
	assert_true(copy is Dictionary)
	assert_eq((copy as Dictionary)["recent_skills"], ["skill:mining"])


# ------------------------------------------------------------------ gruppi richiudibili

func test_gruppi_si_chiudono_si_ricordano_e_riaprono() -> void:
	var main := await _main()
	var sb := _sb(main)
	assert_eq(sb.group_ids(), ["skills", "adventure", "city", "vault", "progress"])
	for gid in sb.group_ids():
		assert_true(sb.is_group_open(gid))
	var hdr := sb.header_button("city")
	assert_true(hdr.text.begins_with("▾ "), hdr.text)
	assert_true(main._buttons["bank"].visible)
	hdr.pressed.emit()
	await wait_process_frames(1)
	assert_false(sb.is_group_open("city"))
	assert_true(hdr.text.begins_with("▸ "), hdr.text)
	assert_false(main._buttons["bank"].visible, "voce nascosta a gruppo chiuso")
	assert_true((Settings.get_value("sidebar_groups_closed") as Array).has("city"), "ricordato in Settings")
	main.call("build_menu")                    # ricostruzione del menù: la scelta resta
	await wait_process_frames(2)
	assert_false(sb.is_group_open("city"))
	assert_false(main._buttons["bank"].visible)
	sb.header_button("city").pressed.emit()
	await wait_process_frames(1)
	assert_true(sb.is_group_open("city"))
	assert_true(main._buttons["bank"].visible)
	assert_false((Settings.get_value("sidebar_groups_closed") as Array).has("city"))


func test_intestazione_si_attiva_da_tastiera() -> void:
	var main := await _main()
	var sb := _sb(main)
	var hdr := sb.header_button("adventure")
	assert_eq(hdr.focus_mode, Control.FOCUS_ALL, "raggiungibile con la tastiera e col controller")
	hdr.grab_focus()
	await wait_process_frames(1)
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await wait_process_frames(1)
	await wait_process_frames(1)
	assert_false(sb.is_group_open("adventure"))


func test_predefinito_nelle_finestre_basse_chiude_citta_caveau_progresso() -> void:
	Settings.set_value("sidebar_groups_closed", [])             # nessuna scelta del giocatore
	var main := await _main()
	var sb := _sb(main)
	var h := main.get_viewport().get_visible_rect().size.y
	if h < SidebarMenu.SHORT_WINDOW_H:
		assert_eq(sb.closed_groups(), ["city", "vault", "progress"])
		assert_true(sb.is_group_open("adventure"))
	else:
		assert_eq(sb.closed_groups(), [])


func test_somma_e_puntino_sull_intestazione_chiusa() -> void:
	_crates(3)
	var main := await _main()
	var sb := _sb(main)
	_slow(main)
	var open_state := sb.header_state("vault")
	assert_true(open_state.open)
	assert_false(open_state.sum_visible, "a gruppo aperto i numeri stanno sulle voci")
	var n := int(SidebarBadges.signals()["vault_hall"].n)
	sb.set_group_closed("vault", true)
	var st := sb.header_state("vault")
	assert_false(st.open)
	assert_true(st.sum_visible)
	assert_eq(st.sum_text, SidebarBadges.label(n), "somma dei numeri del gruppo")
	assert_true(st.text.begins_with("▸ "))
	# progresso: il puntino di una voce appena sbloccata (mai aperta) compare sull'intestazione chiusa
	(GameState.data.unlocks as Array).append("feature:coop")
	main.call("build_menu")
	await wait_process_frames(2)
	_slow(main)
	var prog := sb.header_state("progress")
	assert_true(prog.open)
	sb.set_group_closed("progress", true)
	assert_false(sb.header_state("progress").sum_visible)


func test_rosso_sull_intestazione_chiusa() -> void:
	var main := await _main()
	var sb := _sb(main)
	_fill_bank()
	_slow(main)
	assert_eq(main._badges["bank"].visible, true)
	assert_eq(sb.badge_kind("bank"), SidebarBadges.KIND_DANGER)
	assert_eq((main._badges["bank"].get_node("N") as Label).text, "!")
	sb.set_group_closed("city", true)
	var st := sb.header_state("city")
	assert_true(st.sum_visible)
	assert_true(st.sum_danger)
	assert_eq(st.sum_text, "!")


func test_voce_in_corso_resta_visibile_e_l_intestazione_chiusa_ha_il_segno() -> void:
	var main := await _main()
	var sb := _sb(main)
	var sk := Game.system("skills") as SkillSystem
	assert_true(sk.start(str(DataRegistry.actions_for_skill("woodcutting")[0].id)))
	main.refresh_activity_marks()
	assert_eq(main.main_mark_id(), "skill:woodcutting")
	sb.set_group_closed("skills", true)
	await wait_process_frames(2)
	assert_true((main._buttons["skill:woodcutting"] as Button).visible, "l'attività in corso resta come riga fissa")
	assert_false((main._buttons["skill:mining"] as Button).visible, "le altre mansioni si nascondono")
	assert_true(sb.header_state("skills").mark, "segno dell'attività sull'intestazione chiusa")
	sb.set_group_closed("skills", false)
	assert_false(sb.header_state("skills").mark, "a gruppo aperto il segno è sulla voce")
	assert_false(main.edge_hints().up or main.edge_hints().down)


func test_gruppo_della_voce_selezionata_si_apre_da_solo() -> void:
	var main := await _main()
	var sb := _sb(main)
	sb.set_group_closed("city", true)
	assert_false(main._buttons["bank"].visible)
	assert_true(main.show_screen("bank"))
	await wait_process_frames(1)
	assert_true(sb.is_group_open("city"), "contiene la voce selezionata")
	assert_true(main._buttons["bank"].visible)
	assert_true((main._buttons["bank"] as Button).button_pressed)
	assert_true((Settings.get_value("sidebar_groups_closed") as Array).has("city"), "la scelta dell'utente non cambia")
	# se il giocatore lo richiude a mano, resta chiuso (finché non cambia voce)
	sb.header_button("city").pressed.emit()
	assert_false(sb.is_group_open("city"))
	main.show_screen("summary")
	assert_false(sb.is_group_open("city"))


func test_gruppo_con_il_bersaglio_del_tutorial_si_apre_da_solo() -> void:
	Settings.set_value("tutorials", true)
	var main := await _main()
	var sb := _sb(main)
	sb.set_group_closed("city", true)
	assert_null(TutorialTargets.find(get_tree(), "menu:bank"), "chiuso: il controllo non si trova")
	var td: TutorialDirector = main.tutorial()
	(Game.system("unlock") as Object).grant("chapter:1")
	assert_true(td.show_step("f_bank"), "passo del Deposito disponibile")
	main.call("_tick_marks")
	await wait_process_frames(2)
	assert_true(sb.is_group_open("city"), "il passo punta al Deposito: il gruppo si apre da solo")
	assert_not_null(TutorialTargets.find(get_tree(), "menu:bank"))
	td.dismiss()
	main.call("_tick_marks")
	assert_false(sb.is_group_open("city"), "finito il passo torna come lo ha scelto il giocatore")


# ------------------------------------------------------------------ tasti 1-9 e voci del menù

func test_tasti_uno_nove_sulle_prime_nove_voci_visibili() -> void:
	var main := await _main()
	var sb := _sb(main)
	var ids: Array = sb.menu_ids
	assert_gte(ids.size(), 9)
	var vis: Array = []
	for e in ScreenRegistry.entries():
		var b: Button = main._buttons.get(str(e.id))
		if b != null and b.visible and not b.disabled and not b.has_meta("req_target"):
			vis.append(str(e.id))
	assert_eq(ids, vis, "menu_ids = voci visibili e aprirbili, in ordine")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_3
	assert_eq(ShortcutMap.resolve(ev, ids), {"type": "screen", "id": ids[2]})
	assert_true((main._buttons[ids[2]] as Button).tooltip_text.contains(Loc.tf("UI_UIB_KEY_HINT", {"key": ShortcutMap.key_label_for(str(ids[2]), ids)})), "il tooltip mostra il tasto")
	# chiudo un gruppo: le cifre scorrono sulle voci che restano visibili
	sb.set_group_closed("adventure", true)
	var ids2: Array = sb.menu_ids
	assert_false(ids2.has("combat"))
	assert_ne(ids2.slice(0, 9), ids.slice(0, 9))
	for i in mini(9, ids2.size()):
		var key := ShortcutMap.key_label_for(str(ids2[i]), ids2)     # le voci con tasto proprio (B, M…) mostrano quello
		assert_false(key.is_empty())
		assert_true((main._buttons[ids2[i]] as Button).tooltip_text.contains(Loc.tf("UI_UIB_KEY_HINT", {"key": key})), "%s ← %s" % [key, ids2[i]])
	assert_true(ids2.size() < ids.size(), "meno voci visibili con un gruppo chiuso")


func test_impostazioni_fuori_dal_menu_ma_raggiungibili() -> void:
	var main := await _main()
	assert_false(main._buttons.has("settings"), "Impostazioni non è una voce del menù")
	assert_false(_sb(main).menu_ids.has("settings"))
	assert_false(ScreenRegistry.get_entry("settings").is_empty(), "la schermata esiste ancora")
	var btn := main.get("_settings_btn") as Button
	assert_not_null(btn, "⚙ resta nella barra alta")
	btn.pressed.emit()
	await wait_process_frames(2)
	assert_eq(main.current_id, "settings")
	for id in main._buttons:
		assert_false((main._buttons[id] as Button).button_pressed, "nessuna voce evidenziata in Impostazioni: " + str(id))


func test_lobby_e_gilda_solo_dopo_il_primo_uso_del_coop() -> void:
	var main := await _main()
	assert_true(main._buttons.has("coop"), "Coop sempre (se sbloccato)")
	assert_false(main._buttons.has("coop_lobby"))
	assert_false(main._buttons.has("coop_guild"))
	assert_true(main.show_screen("coop"))
	await wait_process_frames(3)
	assert_true(main._buttons.has("coop_lobby"), "dopo il primo uso compare la Lobby")
	assert_true(main._buttons.has("coop_guild"))
	assert_true(_sb(main).coop_used())


func test_caveau_e_un_gruppo_a_parte() -> void:
	var main := await _main()
	var sb := _sb(main)
	for id in ["vault_hall", "album", "wardrobe", "vault_workshop"]:
		assert_eq(ScreenRegistry.get_entry(id).section, "vault", id)
		assert_eq(sb._entry_group[id], "vault")
	assert_eq(sb._entry_group["bank"], "city")
	assert_eq(sb._entry_group["quests"], "summary")
	assert_null(sb._headers.get("summary"), "Riepilogo e Missioni in cima, senza titolo")


func test_voce_sbloccata_e_mai_aperta_e_un_puntino() -> void:
	var main := await _main(false)
	var sb := _sb(main)
	_slow(main)
	assert_eq(sb.signal_of("market"), {}, "non sbloccata")
	(Game.system("unlock") as Object).grant("feature:market")
	main.call("build_menu")
	await wait_process_frames(2)
	_slow(main)
	assert_eq(sb.signal_of("market").kind, SidebarBadges.KIND_DOT, "sbloccata e mai aperta")
	assert_eq(sb.signal_of("market").causes[0][0], SidebarBadges.CAUSE_NEW_ENTRY)
	assert_eq(sb.signal_of("bank"), {}, "le voci già presenti all'inizio non segnalano")
	main.show_screen("market")
	_slow(main)
	assert_eq(sb.signal_of("market"), {}, "aperta: il puntino si spegne")


# ------------------------------------------------------------------ larghezza e testi

func test_larghezza_200_e_nessun_nome_tagliato_in_italiano_e_inglese() -> void:
	assert_eq(UiBands.SIDEBAR_W, 200.0)
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		var main := await _main()
		var sb := _sb(main)
		for gid in sb.group_ids():
			sb.set_group_closed(gid, false)
		sb.set_all_skills_open(true)
		_crates(12)
		_slow(main)
		await wait_process_frames(3)
		var side := main.get_node("Root/Body/Sidebar") as Control
		assert_almost_eq(side.size.x, 200.0, 0.5, "[%s] larghezza del menù" % loc)
		var scroll_w := (main.get_node("Root/Body/Sidebar/Scroll") as ScrollContainer).get_v_scroll_bar().get_combined_minimum_size().x
		var limit := side.size.x - scroll_w
		var wide := PackedStringArray()
		var checked := 0
		var rows: Array = []
		rows.append_array(main._buttons.values())
		rows.append(sb.all_row())
		for gid in sb.group_ids():
			rows.append(sb.header_button(gid))
		for b: Button in rows:
			if not b.visible:
				continue
			checked += 1
			var w := b.get_combined_minimum_size().x
			if w > limit:
				wide.append("%s (%s): %d > %d" % [b.text, loc, int(w), int(limit)])
		assert_gt(checked, 30)
		assert_eq(wide.size(), 0, "nomi tagliati/che allargano il menù: " + ", ".join(wide))
		main.queue_free()
		await wait_process_frames(2)
		Game.stop_game(false)
		assert_true(Game.new_game(1, "normal", 4242))


func test_testi_nuovi_bilingui_senza_chiavi_nude() -> void:
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		for k in ["UI_SIDE_GROUP_VAULT", "UI_SIDE_ALL_SKILLS", "UI_SIDE_ALL_TIP", "UI_SIDE_HEADER_TIP", "UI_SIDE_DISCOVERY", "UI_SIDE_NEW_ENTRY",
				"UI_SIDE_DANGER_BANK", "UI_SIDE_DANGER_PANTRY", "UI_SIDE_DANGER_FOOD"]:
			assert_ne(tr(k), k, "%s tradotta (%s)" % [k, loc])
	Settings.set_value("locale", "it")
	assert_eq(Loc.tf("UI_SIDE_ALL_SKILLS", {"n": 17}), "Tutte (17)")
