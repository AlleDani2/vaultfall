extends GutTest
## CRATES-2, presentazione: Bottega dei Caveau (Contratti, Affinatura, Banco, Sfida), azioni dopo l'apertura,
## rullo ×5/×10 (CrateMultiReveal). Le schermate mostrano soltanto ciò che il sistema ha già deciso.

const CRATE := "crate_millbrook"
const TOKENS: Array = ["feature:tradeup", "feature:golden_contract", "feature:refinery", "feature:collectors_challenge"]

var _old_reduce: bool
var _old_dir: String


func before_each() -> void:
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_crates2_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _start(unlock: bool = true) -> CrateSystem:
	assert_true(Game.new_game(1, "normal", 5))
	if unlock:
		var u := Game.system("unlock") as UnlockSystem
		for t in TOKENS:
			u.grant(t)
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	return Game.system("crates") as CrateSystem


func _skin(crates: CrateSystem, rarity: String, k: int = 0) -> String:
	return str(crates.contents(CRATE)[rarity][k])


func _give(crates: CrateSystem, rarity: String, k: int, f: float = 0.5) -> String:
	var bank := Game.system("bank") as BankSystem
	var def_id := _skin(crates, rarity, k)
	return bank.add_instance({"def_id": def_id, "kind": "skin", "rarity": rarity, "crate": CRATE,
		"condition": crates.condition_for_float(f), "float": f, "annalist": false, "seed": 3, "phase": "", "polish": 0, "locked": false})


func _screen(path: String, params: Dictionary = {}) -> GameScreen:
	var scr: GameScreen = (load("res://src/ui/screens/%s.tscn" % path) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open(params)
	return scr


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	if n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out


# ------------------------------------------------------------------ chiavi di testo

func test_motivi_di_rifiuto_tutti_tradotti() -> void:
	for r in ["locked_feature", "count", "missing", "locked", "in_use", "kind", "rarity", "variant", "dup", "no_output",
			"max", "at_min", "shards", "already", "gold", "space", "none", "unknown", "unsellable"]:
		var key: String = "UI_CRATES2_WHY_" + r.to_upper()
		assert_ne(str(TranslationServer.translate(key)), key, "motivo senza testo: " + r)
		assert_ne(CrateUi.why(r), "")


# ------------------------------------------------------------------ Bottega: ogni scheda si apre

func test_bottega_apre_tutte_le_schede() -> void:
	var crates := _start()
	for tab in ["contracts", "refine", "bank", "challenge"]:
		var scr := _screen("VaultWorkshopScreen", {"tab": tab})
		await wait_process_frames(1)
		scr.refresh()
		assert_not_null(scr.current_view(), tab)
		assert_gt(scr.current_view().get_child_count(), 0, "la scheda %s mostra qualcosa" % tab)
		scr.close()
	assert_not_null(crates)


func test_bottega_funzioni_bloccate_mostrano_il_come_sbloccarle() -> void:
	_start(false)
	var scr := _screen("VaultWorkshopScreen", {"tab": "contracts"})
	var text := _all_text(scr.current_view())
	assert_true(text.contains(CrateUi.why("locked_feature")) or text.contains(TranslationServer.translate("UI_QUESTS_UNLOCK_HINT").substr(0, 8)),
		"scheda bloccata con spiegazione")
	var tabs := CrateUi.build_tabs(scr, "contracts")
	assert_true((tabs.get_node("Tab_refine") as Button).disabled)
	assert_true((tabs.get_node("Tab_bank") as Button).disabled == false)
	tabs.queue_free()


# ------------------------------------------------------------------ Contratti: tutti gli esiti con la probabilità, prima di firmare

func test_contratti_mostra_ogni_esito_con_la_sua_probabilita_e_firma() -> void:
	Settings.set_value("reduce_motion", true)
	var crates := _start()
	var ins: Array = []
	for i in 10:
		ins.append(_give(crates, "rare", i % 6))
	var scr := _screen("VaultWorkshopScreen", {"tab": "contracts", "add": ins[0]})
	var view := scr.current_view() as ContractsView
	assert_eq(view.selection, [ins[0]], "il pezzo del pulsante Contratto è già scelto")
	view.auto_pick()
	assert_eq(view.selection.size(), 10)
	var text := _all_text(view)
	var pv := crates.contract_preview(view.selection)
	assert_true(pv.ok)
	for o in pv.outcomes:
		assert_true(text.contains(CrateUi.def_name(str(o.def_id)) + "  " + CrateUi.pct(float(o.pct))), "esito mostrato con la sua probabilità: " + str(o.def_id))
	var opened := int(crates.state.opened)
	view.sign_now()
	assert_false(view.last_result.is_empty())
	assert_eq(view.selection.size(), 0)
	assert_eq(int(crates.state.stats.contracts), 1)
	assert_false(crates.instance(str(view.last_result.uid)).is_empty())
	assert_eq(int(crates.state.opened), opened, "un contratto non è un'apertura di cassa")
	assert_true(_all_text(view).contains(CrateUi.def_name(str(view.last_result.def_id))))


# ------------------------------------------------------------------ Affinatura e Banco dalla UI

func test_affinatura_e_banco_dalla_schermata() -> void:
	var crates := _start()
	var bank := Game.system("bank") as BankSystem
	bank.add_currency("vault_shard", 500)
	var u := _give(crates, "epic", 0, 0.6)
	var scr := _screen("VaultWorkshopScreen", {"tab": "refine", "add": u})
	var rv := scr.current_view() as RefineryView
	assert_eq(rv.selected_uid, u)
	var before := float(crates.instance(u).float)
	rv.do_polish()
	assert_lt(float(crates.instance(u).float), before)
	rv.do_engrave()
	assert_true(bool(crates.instance(u).annalist))
	rv.tag_text = "Briciola"
	bank.add_gold(20000)
	rv.do_rename()
	assert_eq(crates.instance(u).tag, "Briciola")
	assert_true(_all_text(rv).contains("Briciola"))
	var b2 := _screen("VaultWorkshopScreen", {"tab": "bank"})
	var vb := b2.current_view() as VaultBankView
	var k0 := bank.count("key_t1")
	vb.buy("key_t1")
	assert_eq(bank.count("key_t1"), k0 + 1)
	var rares: Array = []
	for i in 3:
		rares.append(_give(crates, "rare", i))
	vb.fuse_rarity = "rare"
	var s0 := crates.shards()
	vb.fuse_all()
	assert_gt(crates.shards(), s0)
	for r in rares:
		assert_true(crates.instance(str(r)).is_empty())


func test_sfida_scheda_mostra_classifica_e_punti_dai_dati() -> void:
	var crates := _start()
	var scr := _screen("VaultWorkshopScreen", {"tab": "challenge"})
	var text := _all_text(scr.current_view())
	for r in crates.challenge_board():
		if not bool(r.player):
			assert_true(text.contains(Loc.t(r.name)), "rivale in classifica")
	for rar in CrateSystem.RARITIES:
		assert_true(text.contains("%s %d" % [CrateUi.rarity_symbol(rar), crates.challenge_points(rar)]), "punti per rarità visibili")


# ------------------------------------------------------------------ azioni dopo l'apertura

func test_pulsanti_dopo_l_apertura() -> void:
	var crates := _start()
	var u := _give(crates, "rare", 0)
	var act := CrateActions.new()
	add_child_autofree(act)
	act.setup(crates, u)
	assert_not_null(act.equip_btn)
	assert_not_null(act.lock_btn)
	assert_not_null(act.fuse_btn)
	assert_not_null(act.sell_btn)
	assert_not_null(act.contract_btn)
	assert_false(act.contract_btn.disabled, "Rara con Contratti sbloccati")
	assert_true(act.fuse_btn.text.contains(str(crates.fuse_value(u))), "il pulsante dice quante Schegge")
	act.lock_btn.pressed.emit()
	assert_true(crates.is_locked(u))
	assert_true(act.fuse_btn.disabled and act.sell_btn.disabled, "bloccato: niente Fondi né Vendi")
	act.lock_btn.pressed.emit()
	assert_false(crates.is_locked(u))
	watch_signals(EventBus)
	act.contract_btn.pressed.emit()
	assert_signal_emitted_with_parameters(EventBus, "screen_requested", ["vault_workshop", {"tab": "contracts", "add": u, "golden": false}])
	act.do_sell()
	assert_true(crates.instance(u).is_empty())
	var u2 := _give(crates, "rare", 1)
	act.setup(crates, u2)
	act.do_fuse()
	assert_true(crates.instance(u2).is_empty())
	assert_eq(int(crates.state.stats.fused), 1)
	# Epica e oltre chiedono conferma
	var u3 := _give(crates, "legendary", 0)
	act.setup(crates, u3)
	assert_true(act.needs_confirm())
	var u4 := _give(crates, "rare", 2)
	act.setup(crates, u4)
	assert_false(act.needs_confirm())


func test_contratto_disabilitato_senza_sblocco_o_per_reliquie() -> void:
	var crates := _start(false)
	var u := _give(crates, "rare", 0)
	var act := CrateActions.new()
	add_child_autofree(act)
	act.setup(crates, u)
	assert_true(act.contract_btn.disabled)
	assert_ne(act.contract_btn.tooltip_text, "", "spiega perché")


# ------------------------------------------------------------------ rullo ×5/×10

func _results(crates: CrateSystem, n: int) -> Array:
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, n)
	bank.add("key_t1", n)
	return crates.open(CRATE, n)


func test_rullo_multiplo_ordine_migliore_per_ultima_e_filtro() -> void:
	Settings.set_value("reduce_motion", true)
	var crates := _start()
	var res := _results(crates, 10)
	var mr := CrateMultiReveal.new()
	add_child_autofree(mr)
	watch_signals(mr)
	mr.play(res)
	assert_signal_emitted(mr, "finished")
	assert_eq(mr.visible_count(), 10, "riduci animazioni: tutto subito")
	var order := CrateMultiReveal.reveal_order(res)
	assert_eq(order.size(), 10)
	assert_eq(order[order.size() - 1], CrateSystem.best_result_index(res), "la migliore per ultima")
	var last_rar := -1
	for k in order.size() - 1:
		var ri := CrateSystem.RARITIES.find(str(res[order[k]].rarity))
		assert_gte(ri, last_rar, "rarità crescente")
		last_rar = ri
	assert_true(mr.best_index() >= 0)
	# filtro
	var rar := str(res[mr.best_index()].rarity)
	mr.set_filter(rar)
	var want := 0
	for r in res:
		if r.rarity == rar:
			want += 1
	assert_eq(mr.visible_count(), want)
	mr.set_filter("")
	assert_eq(mr.visible_count(), 10)


func test_rullo_multiplo_salta_scopre_tutto_con_animazioni() -> void:
	Settings.set_value("reduce_motion", false)
	var crates := _start()
	var res := _results(crates, 10)
	var mr := CrateMultiReveal.new()
	add_child_autofree(mr)
	watch_signals(mr)
	mr.play(res)
	assert_true(mr.playing, "la sequenza è in corso")
	await wait_process_frames(2)
	assert_lt(mr.visible_count(), 10, "non è tutto subito")
	mr.skip()
	assert_false(mr.playing)
	assert_eq(mr.visible_count(), 10)
	assert_signal_emitted(mr, "finished")
	assert_signal_emitted(mr, "tick_sound")


func test_rullo_multiplo_rapido_finisce_in_meno_di_un_secondo() -> void:
	Settings.set_value("reduce_motion", false)
	var crates := _start()
	var res := _results(crates, 5)
	var mr := CrateMultiReveal.new()
	add_child_autofree(mr)
	watch_signals(mr)
	mr.play(res, true)
	await wait_seconds(1.2)
	assert_signal_emitted(mr, "finished")
	assert_eq(mr.visible_count(), 5)


func test_sala_x10_estrae_prima_e_mostra_azioni_per_la_migliore() -> void:
	Settings.set_value("reduce_motion", true)
	var crates := _start()
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 10)
	bank.add("key_t1", 10)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(2)
	scr._do_open(10)
	assert_eq(int(crates.state.opened), 10, "tutte e 10 estratte prima di qualunque animazione")
	assert_true(scr._multi.visible)
	assert_eq(scr._multi.visible_count(), 10)
	await wait_process_frames(2)
	assert_true(scr._actions.visible, "Equipaggia · Blocca · Fondi · Vendi · Contratto per la migliore")
	var best: Dictionary = scr._results[scr._multi.best_index()]
	assert_eq(scr._actions.current_uid(), str(best.uid))
	# scegliere un altro pezzo cambia le azioni
	scr._on_multi_selected(0)
	assert_eq(scr._actions.current_uid(), str(scr._results[0].uid))
	scr._on_close_panel()


func test_sala_x1_mostra_i_pulsanti_dopo_il_rullo() -> void:
	Settings.set_value("reduce_motion", true)
	var crates := _start()
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 3)
	bank.add("key_t1", 3)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(2)
	scr._do_open(1)
	await wait_process_frames(2)
	var r: Dictionary = scr._results[0]
	assert_eq(scr._actions.visible, r.kind == "skin" or r.kind == "relic" or r.kind == "cosmetic")
	if scr._actions.visible:
		assert_eq(scr._actions.current_uid(), str(r.uid))
	assert_not_null(crates)
	scr._on_close_panel()


func test_sala_bulk_fondi_le_rare_del_lotto() -> void:
	Settings.set_value("reduce_motion", true)
	var crates := _start()
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 10)
	bank.add("key_t1", 10)
	var scr := _screen("VaultHallScreen", {"crate": CRATE})
	await wait_process_frames(2)
	scr._do_open(10)
	await wait_process_frames(2)
	var uids: Array = scr._bulk_uids()
	assert_gt(uids.size(), 0, "con il 79% di Rare ce ne sono sempre")
	var res := crates.fuse_many(uids)
	assert_eq(res.n, uids.size())
	assert_eq(scr._bulk_uids().size(), 0)
	scr._on_close_panel()
