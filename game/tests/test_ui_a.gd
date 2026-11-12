extends GutTest
## UI-A (audit G14-G21, G25, G32): vendita multipla e automatica, Compendio completo, Bonus attivi, tooltip di calcolo,
## notifiche per categoria, conferma di chiusura, filtri del registro, menù contestuale, Stendardi ed Emblemi.

var _old_dir: String
var _old_settings: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ui_a_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	for k in ["notify_loot", "notify_progress", "notify_achievements", "notify_levels", "notify_events", "notify_boss",
			"notify_info", "combat_log", "combat_log_filter", "confirm_quit"]:
		_old_settings[k] = Settings.get_value(k)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	for k in _old_settings:
		Settings.set_value(k, _old_settings[k])


func _new() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	(GameState.data.unlocks as Array).append("feature:market")


func _open(path: String) -> Control:
	var scr: Control = (load(path) as PackedScene).instantiate()
	add_child_autofree(scr)
	await wait_process_frames(1)
	scr.open({})
	scr.refresh()
	return scr


func _texts(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is Label or c is Button:
			out += str(c.text) + "\n"
		if c is RichTextLabel:
			out += str(c.text) + "\n"
		out += _texts(c)
	return out


# ------------------------------------------------------------------ G14 vendita multipla e regole

func test_vendita_multipla_non_tocca_bloccati_e_indossati() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var market := Game.system("market") as MarketSystem
	var combat := Game.system("combat") as CombatSystem
	var free_uid := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	var locked_uid := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	var worn_uid := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	var fine_uid := bank.add_instance({"def": "plate_helm_copper", "quality": "fine"})
	bank.set_instance_locked(locked_uid, true)
	assert_true(combat.equip(worn_uid), "indossato")
	var f := SellRules.new_filter("equipment")
	f.max_quality = "normal"
	var plan := SellRules.collect(bank, market, f)
	assert_eq(plan.uids, [free_uid], "solo l'istanza libera e di qualità normale")
	assert_eq(int(plan.locked), 1)
	assert_eq(int(plan.in_use), 1)
	assert_gt(int(plan.gold), 0, "anteprima con oro")
	var gold_before := bank.gold()
	var got := SellRules.execute(market, plan)
	assert_eq(got, int(plan.gold), "l'oro incassato coincide con l'anteprima")
	assert_eq(bank.gold(), gold_before + got)
	assert_true(bank.get_instance(free_uid).is_empty(), "venduta")
	assert_false(bank.get_instance(locked_uid).is_empty(), "il bloccato resta")
	assert_false(bank.get_instance(worn_uid).is_empty(), "l'indossato resta")
	assert_false(bank.get_instance(fine_uid).is_empty(), "la qualità Fine resta (limite: Normale)")


func test_vendita_multipla_pile_e_tier() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var market := Game.system("market") as MarketSystem
	bank.add("log_pine", 40)
	bank.add("ore_copper", 10)
	bank.set_def_locked("ore_copper", true)
	var plan := SellRules.collect(bank, market, SellRules.new_filter("material"))
	var ids: Array = []
	for g in plan.groups:
		ids.append(g.id)
	assert_true(ids.has("log_pine"))
	assert_false(ids.has("ore_copper"), "pila bloccata esclusa")
	assert_eq(int(plan.locked), 10)
	var t1 := SellRules.new_filter("material")
	t1.max_tier = 1
	for g in SellRules.collect(bank, market, t1).groups:
		assert_lte(int(DataRegistry.item(str(g.id)).get("tier", 0)), 1)
	# categoria non ammessa -> filtro ripulito su equipaggiamento
	assert_eq(SellRules.clean({"cat": "crate"}).cat, "equipment")


func test_regole_automatiche_sbloccate_dalla_costellazione() -> void:
	_new()
	var assist := Game.system("assist") as AssistSystem
	var bank := Game.system("bank") as BankSystem
	assert_false(assist.auto_sell_unlocked())
	assert_false(assist.add_rule(SellRules.new_filter("material")), "bloccata senza il nodo")
	Modifiers.set_source("constellation", [{"key": "auto_sell_unlock", "value": 1}])
	assert_true(assist.auto_sell_unlocked())
	var f := SellRules.new_filter("material")
	f.max_tier = 1
	assert_true(assist.add_rule(f))
	assert_false(assist.add_rule(f), "regola uguale rifiutata")
	bank.add("log_pine", 25)
	var gold0 := bank.gold()
	assist.tick(AssistSystem.SCAN_S + 0.1)
	assert_gt(bank.gold(), gold0, "la regola ha venduto")
	assert_eq(bank.count("log_pine"), 0)
	# interruttore generale e regola spenta
	bank.add("log_pine", 5)
	assist.set_auto_on(false)
	assert_eq(assist.run_auto_sell(), 0)
	assist.set_auto_on(true)
	assist.set_rule_on(0, false)
	assert_eq(assist.run_auto_sell(), 0)
	assist.remove_rule(0)
	assert_eq((assist.rules() as Array).size(), 0)
	Modifiers.clear_source("constellation")


func test_avviso_boss_mondiale_una_volta_per_finestra() -> void:
	_new()
	var assist := Game.system("assist") as AssistSystem
	var combat := Game.system("combat") as CombatSystem
	(GameState.data.unlocks as Array).append("feature:world_bosses")
	assert_false(assist.check_world_boss_soon(), "lontano: nessun avviso")
	var spawn := float(DataRegistry.table("world_bosses")[0].spawn_every_h) * 3600.0
	combat.state.wb["t"] = spawn - 200.0
	watch_signals(EventBus)
	assert_true(assist.check_world_boss_soon(), "a 200 s dall'apertura avvisa")
	assert_signal_emitted(EventBus, "notice")
	assert_false(assist.check_world_boss_soon(), "una sola volta per finestra")


# ------------------------------------------------------------------ G19 notifiche

func test_notifiche_per_categoria() -> void:
	assert_eq(NoticeFilter.category_of("warning", {}), "", "gli avvisi non si spengono")
	assert_eq(NoticeFilter.category_of("success", {"digest": "ach"}), "achievements")
	assert_eq(NoticeFilter.category_of("info", {"category": "boss"}), "boss")
	assert_eq(NoticeFilter.category_of("info", {"reason": "bank_full"}), "")
	assert_true(NoticeFilter.allows("info", {}, {"notify_info": true}))
	assert_false(NoticeFilter.allows("info", {}, {"notify_info": false}))
	assert_true(NoticeFilter.allows("warning", {}, {"notify_info": false}))
	Settings.set_value("notify_achievements", false)
	var dg := LogDigest.new()
	assert_true(dg.absorb("success", "x", {"digest": "ach"}), "spenta: assorbita")
	assert_true(dg.flush().is_empty(), "e non produce righe")
	Settings.set_value("notify_achievements", true)
	assert_true(dg.absorb("success", "x", {"digest": "ach"}))
	assert_eq(dg.flush().size(), 1)
	Settings.set_value("notify_levels", false)
	dg.add_level("Mining", 3)
	assert_true(dg.flush().is_empty(), "livelli spenti")


# ------------------------------------------------------------------ G16 / G32 Compendio

func test_registro_oggetti_mostri_e_contatori() -> void:
	_new()
	var codex := Game.system("codex") as CodexSystem
	var bank := Game.system("bank") as BankSystem
	assert_false(codex.item_seen("log_oak") and not DataRegistry.has_item("log_oak"))
	var before := codex.item_progress()
	bank.add("log_pine", 3, "test")
	assert_true(codex.item_seen("log_pine"))
	assert_eq(codex.item_count_seen("log_pine"), 3)
	assert_eq(int(codex.item_progress().have), int(before.have) + 1)
	bank.remove("log_pine", 3)
	assert_true(codex.item_seen("log_pine"), "resta ottenuto anche se consumato")
	# drop dei mostri
	var mid := "mud_slime"
	var slots := codex.drop_slots(mid)
	assert_gt(slots.size(), 0)
	assert_eq(int(codex.monster_drop_progress(mid).have), 0)
	EventBus.monster_killed.emit(mid, [{"id": slots[0], "qty": 2}])
	assert_eq(codex.drop_got(mid, str(slots[0])), 2)
	assert_eq(int(codex.monster_drop_progress(mid).have), 1)
	EventBus.monsters_killed_batch.emit(mid, 5, [{"id": slots[0], "qty": 4}])
	assert_eq(codex.drop_got(mid, str(slots[0])), 6)
	# completamento
	var c := codex.completion()
	assert_between(int(c.pct), 0, 100)
	assert_eq(CodexSystem.pct(0, 0), 0)
	assert_eq(CodexSystem.pct(999, 1000), 99, "mai 100% finché manca qualcosa")
	assert_eq(CodexSystem.pct(5, 5), 100)
	# contatori a vita
	GameState.data.stats["kills"] = 1234
	GameState.data.stats["gold_earned"] = 5678
	EventBus.offline_progress.emit(3600.0, {})
	var life := codex.lifetime()
	assert_eq(int(life.kills), 1234)
	assert_eq(int(life.gold), 5678)
	assert_almost_eq(float(life.offline_s), 3600.0, 0.1)
	# unici
	assert_eq(codex.unique_ids().size(), 55)


func test_registro_si_salva_e_riparte_dal_deposito() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	bank.add("log_pine", 2, "test")
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var res := Game.load_game(1)
	assert_true(bool(res.get("ok", true)))
	var codex := Game.system("codex") as CodexSystem
	assert_true(codex.item_seen("log_pine"), "il registro sopravvive al salvataggio")
	# vecchio salvataggio: sezione assente -> backfill dal Deposito
	var cx := Game.system("codex") as CodexSystem
	cx.state.seen.erase("log_pine")
	cx.from_state(cx.state)
	assert_true(cx.item_seen("log_pine"), "backfill dal Deposito")


func test_stendardi_ed_emblemi() -> void:
	_new()
	var codex := Game.system("codex") as CodexSystem
	var bank := Game.system("bank") as BankSystem
	var banners := codex.all_cosmetics("banner")
	var emblems := codex.all_cosmetics("emblem")
	assert_gt(banners.size(), 0)
	assert_gt(emblems.size(), 0)
	assert_false(codex.select("banner", str(banners[0])), "non ottenuto: rifiutato")
	assert_ne(banners[0], emblems[0])
	bank.add_instance({"def_id": str(banners[0]), "kind": "cosmetic", "source": "test"})
	bank.add_instance({"def_id": str(emblems[0]), "kind": "cosmetic", "source": "test"})
	assert_true(codex.select("banner", str(banners[0])))
	assert_true(codex.select("emblem", str(emblems[0])))
	assert_false(codex.select("emblem", str(banners[0])), "un emblema non è uno stendardo")
	assert_eq(codex.selected("banner"), str(banners[0]))
	assert_true(codex.select("banner", ""))
	assert_eq(codex.selected("banner"), "")


func test_compendio_nuove_schede_si_aprono() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var codex := Game.system("codex") as CodexSystem
	var banner := str(codex.all_cosmetics("banner")[0])
	bank.add_instance({"def_id": banner, "kind": "cosmetic", "source": "test"})
	codex.select("banner", banner)
	var scr: Control = await _open("res://src/ui/screens/CompendiumScreen.tscn")
	assert_eq(scr._tabs.get_tab_count(), 8)
	for tab in 8:
		scr._tabs.current_tab = tab
		scr.refresh()
		await wait_process_frames(1)
	var totals := _texts(scr._tabs.get_child(7))
	assert_true(totals.contains("%"), "percentuale di completamento")
	scr._tabs.current_tab = 1
	scr.refresh()
	assert_true(_texts(scr._bodies[1]).length() > 0)
	# la scelta dello stendardo dalla UI
	scr._on_cosmetic("banner", "")
	assert_eq(codex.selected("banner"), "")


func test_riepilogo_scheda_profilo_e_bonus_attivi() -> void:
	_new()
	var scr: Control = await _open("res://src/ui/screens/SummaryScreen.tscn")
	assert_not_null(scr._profile)
	scr.refresh()
	Modifiers.set_source("test:ui_a", [{"key": "skill_haste_pct:mining", "value": 5}])
	var dlg: BonusDialog = scr.open_bonus_panel()
	await wait_process_frames(2)
	assert_false(_texts(dlg).contains("skill_haste_pct:mining"), "la chiave tecnica non compare più nel pannello")
	dlg.queue_free()
	Modifiers.clear_source("test:ui_a")


# ------------------------------------------------------------------ G17 Bonus attivi

func test_bonus_attivi_totali_fonti_e_limite() -> void:
	var st := ModifierStack.new()
	st.set_catalog(DataRegistry.table("modifier_catalog"))
	st.set_source("pet:pet_skill_mining", [{"key": "crate_find_pct", "value": 150}])
	st.set_source("star:mining", [{"key": "crate_find_pct", "value": 100}, {"key": "skill_double_pct:mining", "value": 10}])
	st.set_source("equip:weapon", [{"key": "skill_double_pct:mining", "value": 20, "mode": "more"}])
	var rows := BonusSummary.rows(st)
	var by: Dictionary = {}
	for r in rows:
		by[r.key] = r
	assert_true(by.has("crate_find_pct:all"))
	assert_true(bool(by["crate_find_pct:all"].capped), "250% > tetto 200%: limite raggiunto")
	assert_eq((by["crate_find_pct:all"].sources as Array).size(), 2, "due fonti elencate")
	assert_false(bool(by["skill_double_pct:mining"].capped))
	assert_string_contains(str(by["skill_double_pct:mining"].total), "×1", "il more appare come moltiplicatore")
	assert_eq(BonusSummary.rows(st, str(by["skill_double_pct:mining"].name).substr(0, 6)).size(), 1, "filtro per testo")
	assert_string_contains(BonusSummary.source_label("pet:pet_skill_mining"), ":")
	assert_eq(BonusSummary.rows(ModifierStack.new()).size(), 0)


# ------------------------------------------------------------------ G18 tooltip di calcolo

func test_scomposizione_statistiche_torna_al_totale() -> void:
	_new()
	var combat := Game.system("combat") as CombatSystem
	var st := combat.hero_stats()
	for stat in ["hp", "ap", "acc", "eva", "arm", "ward", "max_hit", "crit", "critd", "interval", "regen_pct"]:
		var e := StatBreakdown.explain(combat, stat)
		assert_false(e.is_empty(), stat)
		if not (e.parts as Array).is_empty():
			assert_string_contains(str(e.formula), "=", stat)
	var acc := StatBreakdown.explain(combat, "acc")
	assert_almost_eq(float(acc.total), float(st.acc), 0.01)
	assert_string_contains(str(acc.formula), "×", "coefficiente × livello")
	# la somma delle parti (con i fattori) ricostruisce il totale
	var sum := 0.0
	for p in acc.parts:
		sum += _parse(str(p.text))
	var mult := 1.0
	for f in acc.factors:
		mult *= float(str(f.text).trim_prefix("×").replace(",", "."))
	assert_almost_eq(sum * mult, float(st.acc), maxf(2.0, float(st.acc) * 0.02))
	assert_true(StatBreakdown.explain(combat, "nonesiste").is_empty())


func _parse(txt: String) -> float:
	if txt.contains("×"):
		var a := txt.split("×")
		return float(str(a[0]).replace(",", ".")) * float(str(a[1]).replace(",", "."))
	return float(txt.replace(",", ".").replace(".", "") if txt.count(".") > 1 else txt.replace(",", "."))


func test_riordino_abilita_per_trascinamento() -> void:
	assert_eq(AbilityDragRow.reorder_ids(["a", "b", "c"], 0, 2), ["b", "c", "a"])
	assert_eq(AbilityDragRow.reorder_ids(["a", "b", "c"], 2, 0), ["c", "a", "b"])
	assert_eq(AbilityDragRow.reorder_ids(["a", "b", "c"], 1, 1), ["a", "b", "c"])
	assert_eq(AbilityDragRow.reorder_ids(["a", "b"], 5, 0), ["a", "b"], "indici fuori campo ignorati")
	var row := AbilityDragRow.new(2)
	add_child_autofree(row)
	assert_true(row._can_drop_data(Vector2.ZERO, {AbilityDragRow.DRAG_KEY: 0}))
	assert_false(row._can_drop_data(Vector2.ZERO, {AbilityDragRow.DRAG_KEY: 2}), "non su se stessa")
	watch_signals(row)
	row._drop_data(Vector2.ZERO, {AbilityDragRow.DRAG_KEY: 0})
	assert_signal_emitted_with_parameters(row, "moved", [0, 2])


func test_eroe_tooltip_finitura_e_menu() -> void:
	_new()
	var combat := Game.system("combat") as CombatSystem
	var bank := Game.system("bank") as BankSystem
	var uid := bank.add_instance({"def": "plate_helm_copper"})
	combat.equip(uid)
	var scr: Control = await _open("res://src/ui/screens/HeroScreen.tscn")
	scr.refresh()
	await wait_process_frames(2)
	var tips := 0
	for c in scr._stats_box.get_children():
		if (c as Control).tooltip_text.contains("="):
			tips += 1
	assert_gt(tips, 4, "le statistiche hanno il tooltip di calcolo")
	var btn: ItemTipButton = scr._slot_rows["helm"].btn
	assert_eq(btn.def_id, "plate_helm_copper")
	# finitura sull'arma: appare nome e colore
	var crates := Game.system("crates") as CrateSystem
	var sk := bank.add_instance({"def_id": "skin_millbrook_01", "kind": "skin", "rarity": "rare", "condition": "marked", "crate": "millbrook"})
	assert_true(crates.equip(sk))
	scr._sig = ""
	scr.refresh()
	var fin: Label = scr._finish_labels["weapon"]
	assert_true(fin.visible)
	assert_string_contains(fin.text, "Spiga Dorata" if Loc.locale() == "it" else "Golden Ear")
	# tasto destro: le voci disponibili per un pezzo indossato
	var ids: Array = []
	for a in ItemActions.available("plate_helm_copper", uid):
		ids.append(a.id)
	assert_true(ids.has("unequip"))
	assert_false(ids.has("equip"))


# ------------------------------------------------------------------ G25 tooltip e menù contestuale

func test_tooltip_oggetto_confronto_con_indossato() -> void:
	_new()
	var combat := Game.system("combat") as CombatSystem
	var bank := Game.system("bank") as BankSystem
	var worn := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	combat.equip(worn)
	var better := bank.add_instance({"def": "plate_helm_copper", "quality": "masterwork"})
	var c := ItemTooltip.build("plate_helm_copper", bank.get_instance(better))
	assert_true(bool(c.has_compare))
	assert_gt((c.compare as Array).size(), 0, "il capolavoro è meglio")
	var armor_up := false
	for r in c.compare:
		if r.key == "armor":
			armor_up = float(r.diff) > 0.0
	assert_true(armor_up, "più armatura del pezzo normale")
	var bb := ItemTooltip.to_bbcode(c)
	assert_string_contains(bb, "7fcf8a")
	# già indossato: nessun confronto con se stesso
	var c2 := ItemTooltip.build("plate_helm_copper", bank.get_instance(worn))
	assert_false(bool(c2.has_compare))
	# stesso pezzo normale vs indossato normale = differenza nulla
	var same := bank.add_instance({"def": "plate_helm_copper", "quality": "normal"})
	assert_eq((ItemTooltip.build("plate_helm_copper", bank.get_instance(same)).compare as Array).size(), 0)
	# statistiche effettive con qualità
	var eff := ItemTooltip.effective_stats(DataRegistry.item("plate_helm_copper"), {"quality": "masterwork"})
	assert_almost_eq(float(eff.armor), 7.0 * 1.28, 0.01)
	var tip := ItemTooltip.make_control("plate_helm_copper", {})
	assert_not_null(tip)
	tip.free()
	assert_null(ItemTooltip.make_control("non_esiste", {}))


func test_menu_contestuale_azioni() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var uid := bank.add_instance({"def": "plate_helm_copper"})
	var ids: Array = []
	for a in ItemActions.available("plate_helm_copper", uid):
		ids.append(a.id)
	for need in ["equip", "lock", "sell"]:
		assert_true(ids.has(need), need)
	assert_true(ItemActions.perform("lock", "plate_helm_copper", uid))
	assert_true(bank.is_instance_locked(uid))
	var sell_en := true
	for a in ItemActions.available("plate_helm_copper", uid):
		if a.id == "sell":
			sell_en = bool(a.enabled)
	assert_false(sell_en, "bloccato: non vendibile")
	assert_true(ItemActions.perform("unlock", "plate_helm_copper", uid))
	assert_true(ItemActions.perform("sell", "plate_helm_copper", uid))
	assert_true(bank.get_instance(uid).is_empty())
	# pila
	bank.add("log_pine", 4)
	assert_true(ItemActions.perform("lock", "log_pine", ""))
	assert_true(bank.is_def_locked("log_pine"))
	assert_false(ItemActions.perform("sell", "log_pine", "") and bank.count("log_pine") == 0, "bloccata: resta")


func test_deposito_dialoghi_e_menu() -> void:
	_new()
	var bank := Game.system("bank") as BankSystem
	var uid := bank.add_instance({"def": "plate_helm_copper"})
	bank.add("log_pine", 10)
	var scr: Control = await _open("res://src/ui/screens/BankScreen.tscn")
	await wait_process_frames(2)
	var row := scr._grid._pool[0] as ItemCell
	assert_not_null(row, "celle con tooltip")
	assert_ne(row.def_id, "")
	scr._on_cell_pressed(row)
	assert_gt(scr._detail_box.get_child_count(), 2)
	# vendita multipla
	scr.open_multi_sell()
	await wait_process_frames(2)
	var dlg: SellDialog
	for c in scr.get_children():
		if c is SellDialog:
			dlg = c
	assert_not_null(dlg)
	dlg.editor.set_filter({"cat": "equipment", "max_tier": 0, "max_quality": "", "max_rarity": ""})
	assert_eq(int(dlg.plan.pieces), 1)
	assert_string_contains(dlg.preview.text, "1")
	dlg._do_sell()
	assert_true(bank.get_instance(uid).is_empty(), "venduta")
	dlg.queue_free()
	await wait_process_frames(2)
	# regole automatiche: bloccate senza il nodo
	scr.open_auto_sell()
	await wait_process_frames(2)
	var adlg: AutoSellDialog
	for c in scr.get_children():
		if c is AutoSellDialog:
			adlg = c
	assert_not_null(adlg)
	assert_true(adlg._locked_note.visible)
	adlg.queue_free()


# ------------------------------------------------------------------ G20 conferma di chiusura

func test_conferma_di_chiusura_solo_in_combattimento() -> void:
	_new()
	var combat := Game.system("combat") as CombatSystem
	Settings.set_value("confirm_quit", true)
	assert_true(CloseGuard.combat_status().is_empty(), "nessun combattimento: chiude subito")
	assert_false(CloseGuard.needs_confirmation())
	var zone := str(DataRegistry.table("zones")[0].id)
	assert_true(combat.start(zone))
	var st := CloseGuard.combat_status()
	assert_false(st.is_empty())
	assert_true(CloseGuard.needs_confirmation())
	assert_true(["green", "yellow", "red", ""].has(str(st.level)))
	var msg := CloseGuard.message(st)
	assert_gt(msg.length(), 20)
	Settings.set_value("confirm_quit", false)
	assert_false(CloseGuard.needs_confirmation(), "opzione spenta")
	Settings.set_value("confirm_quit", true)
	var fired := [false]
	var dlg := CloseGuard.build_dialog({"level": "green", "food_hours": -1.0}, func() -> void: fired[0] = true)
	add_child_autofree(dlg)
	dlg.confirmed.emit()
	assert_true(fired[0])
	assert_string_contains(CloseGuard.message({"level": "red", "food_hours": 2.0}), "2")


# ------------------------------------------------------------------ G21 registro di combattimento

func test_filtri_del_registro() -> void:
	var lines := PackedStringArray(["colpo", "drop raro", "boss urla", "altro colpo"])
	var cats := PackedStringArray(["", "rare", "boss", ""])
	assert_eq(CombatUi.filter_lines(lines, cats, "all"), lines)
	assert_eq(CombatUi.filter_lines(lines, cats, "rare"), PackedStringArray(["drop raro"]))
	assert_eq(CombatUi.filter_lines(lines, cats, "boss"), PackedStringArray(["boss urla"]))
	assert_false(Settings.set_value("combat_log_filter", "inesistente"), "valore non ammesso")
	assert_true(Settings.set_value("combat_log_filter", "rare"))


func test_scheda_combattimento_registro_attivabile() -> void:
	_new()
	var scr: Control = await _open("res://src/ui/screens/CombatScreen.tscn")
	assert_not_null(scr._log_filter)
	scr._add_line("a", "rare")
	scr._add_line("b")
	assert_eq(scr._log_lines.size(), 2)
	Settings.set_value("combat_log", false)
	scr._add_line("c")
	assert_eq(scr._log_lines.size(), 2, "registro spento: nessuna nuova riga")
	Settings.set_value("combat_log", true)


func test_impostazioni_notifiche() -> void:
	var scr: Control = await _open("res://src/ui/screens/SettingsScreen.tscn")
	var t := _texts(scr)
	assert_string_contains(t, "UI_UIA_SET_NOTIFY")
	assert_string_contains(t, "UI_UIA_NOTIFY_BOSS")
	var checks := 0
	for cat in NoticeFilter.CATEGORIES:
		assert_true(Settings.get_value(NoticeFilter.key_of(cat)) is bool)
		checks += 1
	assert_eq(checks, 7)
