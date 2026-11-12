extends GutTest
## «Espandi Deposito» (feedback giocatore 23/10/2026, resoconto 114): capacità da dati, acquisto +1/+5/+10 senza passare
## dall'Emporio, motivo se non si può comprare, fonti permanenti (missioni, Costellazione, reliquie) nel riepilogo, vecchi
## salvataggi che non perdono nulla, pulsante e finestra nel Deposito, passo del tutorial e riga del Manuale.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"

var _old_dir: String
var _old_locale: Variant
var _old_motion: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_locale = Settings.get_value("locale")
	_old_motion = Settings.get_value("reduce_motion")
	SaveService.save_dir = "user://test_bank_expand_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Settings.set_value("reduce_motion", true)
	assert_true(Game.new_game(1, "normal", 4321))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("locale", _old_locale)
	Settings.set_value("reduce_motion", _old_motion)


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _mk() -> MarketSystem:
	return Game.system("market") as MarketSystem


func _qs() -> QuestSystem:
	return Game.system("quests") as QuestSystem


func _shop() -> Dictionary:
	return DataRegistry.get_def("shop", "bank_slot")


func _fill(n: int) -> void:
	var ids: Array = []
	for d in DataRegistry.items_by_category("material"):
		ids.append(str(d.id))
		if ids.size() >= n:
			break
	for id in ids:
		_bank().add(id, 1)


# ------------------------------------------------------------------ capacità e prezzi dai dati

func test_la_capacita_di_partenza_e_la_base_dei_dati() -> void:
	assert_eq(_bank().capacity(), int(_shop().base_slots))
	assert_gte(int(_shop().base_slots), 100, "base alzata: 60 non bastava per le prime ore (resoconto 114)")
	var bd := _bank().capacity_breakdown()
	assert_eq(int(bd.base), int(_shop().base_slots))
	assert_eq(int(bd.total), _bank().capacity())


func test_il_prezzo_cresce_piano_e_ha_un_tetto() -> void:
	var e := _mk().shop_entry("bank_slot")
	var p0 := _mk().shop_unit_price(e, 0)
	var p40 := _mk().shop_unit_price(e, 40)
	assert_lt(p0, 1000, "i primi spazi costano poco")
	assert_lt(p40, p0 * 5, "la crescita è graduale (vecchio prezzo: x15 in 40 acquisti)")
	assert_lte(_mk().shop_unit_price(e, int(_shop().max_purchases)), 5000000)


func test_anteprima_costo_spazi_dopo_e_motivo_senza_oro() -> void:
	var e := _mk().shop_entry("bank_slot")
	var cap := _bank().capacity()
	var q5 := _mk().bank_expansion(5)
	var want := 0
	for i in 5:
		want += _mk().shop_unit_price(e, i)
	assert_eq(int(q5.cost), want, "costo = somma dei prezzi dei 5 spazi")
	assert_eq(int(q5.added), 5)
	assert_eq(int(q5.cap_now), cap)
	assert_eq(int(q5.cap_after), cap + 5)
	var gold := _bank().gold()
	assert_eq(int(q5.missing), maxi(0, want - gold))
	_bank().spend_gold(gold)
	var poor := _mk().bank_expansion(5)
	assert_false(bool(poor.ok))
	assert_eq(str(poor.reason), "gold")
	assert_eq(int(poor.missing), want)
	assert_false(_mk().buy_bank_slots(5), "senza oro non compra e non cambia nulla")
	assert_eq(_bank().capacity(), cap)


func test_acquisto_multiplo_senza_emporio() -> void:
	var cap := _bank().capacity()
	var q := _mk().bank_expansion(10)
	_bank().add_gold(int(q.cost) + 7)
	var before := _bank().gold()
	assert_true(_mk().buy_bank_slots(10))
	assert_eq(_bank().capacity(), cap + 10)
	assert_eq(_bank().gold(), before - int(q.cost))
	assert_eq(_mk().owned("bank_slot"), 10)
	assert_eq(int(_bank().capacity_breakdown().bought), 10)
	assert_eq(int(_bank().capacity_breakdown().total), cap + 10)
	assert_gt(int(_mk().bank_expansion(1).next_price), int(_mk().shop_unit_price(_mk().shop_entry("bank_slot"), 0)), "il prossimo costa di più")


func test_oltre_il_massimo_non_si_compra() -> void:
	var mx := int(_shop().max_purchases)
	_mk().state.shop["bank_slot"] = mx - 2
	_bank().add_gold(1000000000)
	var q := _mk().bank_expansion(5)
	assert_false(bool(q.ok))
	assert_eq(str(q.reason), "max")
	assert_eq(int(q.left), 2)
	var gold := _bank().gold()
	assert_false(_mk().buy_bank_slots(5))
	assert_eq(_bank().gold(), gold, "nessun addebito")
	assert_true(_mk().buy_bank_slots(2))
	assert_eq(int(_mk().bank_expansion(1).left), 0)


# ------------------------------------------------------------------ fonti permanenti e vecchi salvataggi

func test_le_missioni_con_spazi_sono_finite_e_pagano_dopo_il_riscatto() -> void:
	var rewards := _qs().bank_slot_rewards()
	assert_gt(rewards.size(), 0)
	var total := 0
	for r in rewards:
		total += int(r.slots)
		assert_false(bool(r.done))
	assert_eq(_qs().bank_slots_earned(), 0)
	var first: Dictionary = rewards[0]
	var cap := _bank().capacity()
	_qs().state.done.append(str(first.quest))
	_qs().from_state(_qs().state)
	assert_eq(_qs().bank_slots_earned(), int(first.slots))
	assert_eq(_bank().capacity(), cap + int(first.slots))
	assert_eq(int(_bank().capacity_breakdown().quests), int(first.slots))
	var ps := _bank().permanent_sources()
	assert_eq(int(ps.quest_total), total)
	assert_eq(int(ps.quest_earned), int(first.slots))
	assert_eq(int(ps.quest_left), rewards.size() - 1)


func test_riscatto_vero_aggiunge_spazi_e_avvisa() -> void:
	var qid := str(_qs().bank_slot_rewards()[0].quest)
	var cap := _bank().capacity()
	# porta la missione allo stato «pronta» senza giocare: attiva e con tutti i contatori pieni
	var d := _qs().quest_def(qid)
	_qs().state.active = [qid]
	var prog: Array = []
	for o in d.objectives:
		prog.append(QuestSystem.target_of(o))
	_qs().state.progress[qid] = prog
	watch_signals(EventBus)
	assert_true(_qs().is_ready(qid), "con tutti i contatori pieni la missione e' pronta (SHARK 1.0 #11: niente piu' pending)")
	if _qs().is_ready(qid):
		assert_true(_qs().claim(qid))
		assert_eq(_bank().capacity(), cap + int(d.rewards.bank_slots))


func test_anteprima_ricompensa_e_riga_di_testo() -> void:
	var qid := str(_qs().bank_slot_rewards()[0].quest)
	var found := false
	for rp in _qs().reward_preview(qid):
		if str(rp.kind) == "bank_slots":
			found = true
			var lines := QuestText.reward_lines([rp], DataRegistry)
			assert_true(lines[0].contains(str(int(rp.qty))))
	assert_true(found, "la scheda della missione mostra gli spazi in premio")


func test_vecchio_salvataggio_non_perde_gli_spazi_comprati() -> void:
	# Un salvataggio precedente: 37 cassetti comprati all'Emporio, 3 nel vecchio contatore del Deposito, capitoli già finiti.
	_mk().state.shop["bank_slot"] = 37
	_bank().state.slots_bought = 3
	var first_two: Array = _qs().bank_slot_rewards().slice(0, 2)
	var got := 0
	for r in first_two:
		_qs().state.done.append(str(r.quest))
		got += int(r.slots)
	assert_true(SaveService.save_now())
	assert_true(Game.load_game(1).ok)
	var base := int(_shop().base_slots)
	assert_eq(_mk().owned("bank_slot"), 37, "i posti già acquistati non cambiano")
	assert_eq(int(_bank().state.slots_bought), 3)
	assert_eq(_bank().capacity(), base + 37 + 3 + got, "base nuova + comprati + missioni già fatte (retroattive)")
	var bd := _bank().capacity_breakdown()
	assert_eq(int(bd.bought), 40)
	assert_eq(int(bd.quests), got)
	assert_eq(int(bd.total), _bank().capacity())


func test_riepilogo_elenca_costellazione_e_reliquia_dai_dati() -> void:
	var ps := _bank().permanent_sources()
	assert_false((ps.node as Dictionary).is_empty(), "il nodo di Costellazione degli spazi esiste")
	assert_gt(int(ps.node.max), 0, "finito: regola 9 (nessun bonus infinito)")
	assert_false((ps.relic as Dictionary).is_empty(), "la reliquia degli spazi esiste")
	# con il nodo comprato e la reliquia nel Reliquiario il riepilogo li separa
	Game.ctx.modifiers.set_source(PrestigeSystem.SRC_CONSTELLATION, [{"key": "bank_slots", "value": 20.0, "mode": "add"}])
	Game.ctx.modifiers.set_source(CrateSystem.RELIC_PREFIX + "i_999", [{"key": "bank_slots", "value": 40.0, "mode": "add"}])
	var bd := _bank().capacity_breakdown()
	assert_eq(int(bd.constellations), 20)
	assert_eq(int(bd.relics), 40)
	assert_eq(int(bd.total), int(bd.base) + 60)


# ------------------------------------------------------------------ interfaccia

func _screen() -> GameScreen:
	var scr: GameScreen = (load(BANK_SCREEN) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	return scr


func test_il_pulsante_e_nell_intestazione_col_prezzo() -> void:
	var scr := _screen()
	var b := scr.find_child("ExpandButton", true, false) as Button
	assert_not_null(b)
	assert_true(b.visible)
	var price := NumberFormat.fmt(float(_mk().bank_expansion(1).next_price))
	assert_true(b.text.contains(price), "il testo mostra il prezzo del prossimo spazio: " + b.text)
	assert_not_null(TutorialTargets.find(get_tree(), "bank_expand_btn"), "marcato per l'evidenziazione del tutorial")
	var row := scr.find_child("ExpandBannerButton", true, false) as Button
	assert_false(row.is_visible_in_tree(), "con il Deposito vuoto l'avviso non c'è")


func test_avviso_quasi_pieno_ha_il_suo_pulsante() -> void:
	_fill(int(_bank().capacity() * 0.95))
	assert_true(_bank().nearly_full())
	var scr := _screen()
	var b := scr.find_child("ExpandBannerButton", true, false) as Button
	assert_true(b.is_visible_in_tree())
	assert_true(b.text.contains(NumberFormat.fmt(float(_mk().bank_expansion(1).next_price))))


func test_la_finestra_compra_e_spiega_il_motivo() -> void:
	var scr := _screen()
	var gold := _bank().gold()
	_bank().spend_gold(gold)
	var dlg := BankExpandDialog.new()
	add_child_autofree(dlg)
	await wait_process_frames(2)
	for n in [1, 5, 10]:
		var bt := dlg.find_child("Buy%d" % n, true, false) as Button
		assert_not_null(bt, "pacchetto +%d" % n)
		assert_true(bt.disabled, "senza oro tutto spento")
	var why := dlg.find_child("Why", true, false) as Label
	assert_true(why.visible)
	assert_true(why.text.length() > 5, "dice perché: " + why.text)
	# con l'oro: compra +5 con un clic, la finestra si aggiorna e il Deposito cresce
	var q := _mk().bank_expansion(5)
	_bank().add_gold(int(q.cost) + 1)
	var cap := _bank().capacity()
	dlg.rebuild()
	await wait_process_frames(2)
	var b5 := dlg.find_child("Buy5", true, false) as Button
	assert_false(b5.disabled)
	b5.pressed.emit()
	await wait_process_frames(2)
	assert_eq(_bank().capacity(), cap + 5)
	var tot := dlg.find_child("Total", true, false) as Label
	assert_true(tot.text.contains(NumberFormat.fmt(_bank().capacity())), "il totale del riepilogo segue")
	scr.refresh()


func test_testi_bilingui_e_senza_chiavi_scoperte() -> void:
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		TranslationServer.set_locale(loc)
		for k in ["UI_BANKX_TITLE", "UI_BANKX_BTN", "UI_BANKX_BTN_PRICE", "UI_BANKX_OPT_1", "UI_BANKX_OPT_N", "UI_BANKX_WHY_GOLD",
				"UI_BANKX_SRC_TITLE", "UI_BANKX_SRC_QUESTS_HINT", "UI_BANKX_SRC_CONST_HINT", "UI_BANKX_RW", "UI_BANKX_BOUGHT",
				"UI_TUT_F_BANK_EXPAND_T", "UI_TUT_F_BANK_EXPAND_B", "UI_MAN2_BANK_HOW_5", "UI_MAN2_BANK_F_3", "UI_MAN2_BANK_HOW_6", "UI_MAN2_BANK_F_4"]:
			assert_ne(tr(k), k, "%s tradotta (%s)" % [k, loc])
	Settings.set_value("locale", "it")
	TranslationServer.set_locale("it")
	assert_true(tr("UI_BANKX_BTN").contains("Espandi"))
	TranslationServer.set_locale("en")
	assert_true(tr("UI_BANKX_BTN").contains("Expand"))
	TranslationServer.set_locale("it")


# ------------------------------------------------------------------ tutorial e Manuale

func test_il_passo_del_tutorial_compare_solo_quando_il_deposito_si_riempie() -> void:
	var ts := Game.system("tutorial") as TutorialSystem
	var step := TutorialCatalog.get_step("f_bank_expand")
	assert_false(step.is_empty())
	assert_false(ts.cond_ok(step.cond), "Deposito vuoto: nessun passo")
	_fill(int(_bank().capacity() * 0.95))
	assert_true(ts.cond_ok(step.cond), "oltre la soglia del dati: il passo si propone")
	assert_true(TutorialCatalog.targets_of(step).has("bank_expand_btn"), "evidenzia il pulsante")
	var p := TutorialSystem.text_params("f_bank_expand", DataRegistry)
	assert_eq(int(p.warn), int(DataRegistry.constants.bank.warn_pct))
	assert_true(p.has("quests") and p.has("vname") and p.has("rname"))
	Settings.set_value("locale", "it")
	TranslationServer.set_locale("it")
	assert_true(tr("UI_TUT_F_BANK_EXPAND_B").contains("Armeria"), "il tutorial dice che l'equipaggiamento non occupa Spazio")


func test_il_manuale_spiega_come_espandere_con_numeri_dai_dati() -> void:
	Settings.set_value("locale", "it")
	TranslationServer.set_locale("it")
	var page := ManualPages.build("bank", DataRegistry, [])
	assert_true(page.contains("Espandi Deposito"))
	assert_true(page.contains(str(int(_shop().base_slots))), "la base viene dai dati")
	# F15: la pagina dice che l'equipaggiamento ha la sua Armeria, con il tetto dai dati
	assert_true(page.contains("Armeria"), "la pagina Deposito parla dell'Armeria")
	assert_true(page.contains(str(int(DataRegistry.constants.bank.space.gear_cap))), "il tetto dell'Armeria viene dai dati")
