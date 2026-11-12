extends GutTest
## Resoconto 117 (docs/audit_2026-10-22/117_RESOCONTO_DEPOSITO_PIENO.md): il Deposito pieno NON blocca la progressione.
## Il Carro di Ritiro vale per tutte le fonti (aperture di Casse, acquisti, ricompense, produzione), con tetto di istanze
## dai dati e vendita oltre il tetto; le unita' impilabili del Carro si possono usare (chiavi, ingredienti). Sistemi VERI.

const CRATE := "crate_millbrook"
const KEY := "key_t1"

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_carro_totale_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Modifiers.set_source("constellation", [])
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _open_game(seed_value: int) -> void:
	assert_true(Game.new_game(1, "normal", seed_value))
	for t in ["feature:market", "feature:crates", "feature:combat"]:
		if not (GameState.data.unlocks as Array).has(t):
			GameState.data.unlocks.append(t)


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _crates() -> CrateSystem:
	return Game.system("crates") as CrateSystem


func _gear() -> String:
	for it in DataRegistry.items_by_category("equipment"):
		return str(it.id)
	return ""


## Riempie lo Spazio con PILE di materiali (F15: l'equipaggiamento non occupa Spazio, quindi non riempie il Deposito).
## Ritorna gli id usati, per liberare posti dopo.
func _fill(b: BankSystem) -> Array:
	var used: Array = []
	var mats: Array = DataRegistry.items_by_category("material")
	var i := 0
	while not b.is_full() and i < mats.size():
		var id := str(mats[i].id)
		if id != "log_pine" and not b.state.stacks.has(id):       # log_pine: le prove ne aggiungono unità nuove al Carro
			b.add(id, 1, "test")
			used.append(id)
		i += 1
	assert_true(b.is_full())
	return used


func _skin() -> String:
	for it in DataRegistry.items_by_category("skin"):
		return str(it.id)
	return ""


func _relic() -> String:
	for it in DataRegistry.items_by_category("relic"):
		return str(it.id)
	return ""


func _sig(res: Array) -> Array:
	var out: Array = []
	for r in res:
		var inst: Dictionary = r.instance
		out.append([str(r.def_id), str(r.rarity), str(inst.get("condition", "")), snappedf(float(inst.get("float", 0.0)), 0.000001),
			int(inst.get("seed", 0)), bool(inst.get("annalist", false))])
	return out


# ------------------------------------------------------------------ apertura a Deposito pieno

func test_apertura_a_deposito_pieno_non_perde_e_non_cambia_l_esito() -> void:
	# stesso seme: l'esito della N-esima apertura NON dipende da quanto e' pieno il Deposito (RNG indicizzato invariato)
	_open_game(11701)
	var a := _bank()
	a.add(KEY, 30, "test")
	a.add(CRATE, 30, "test")
	var free_res := _crates().open(CRATE, 12, false)
	var sig_free := _sig(free_res)
	Game.stop_game(false)
	_open_game(11701)
	var b := _bank()
	b.add(KEY, 30, "test")
	b.add(CRATE, 30, "test")
	_fill(b)
	var full_res := _crates().open(CRATE, 12, false)
	assert_eq(full_res.size(), 12, "il Deposito pieno non ferma l'apertura")
	assert_eq(_sig(full_res), sig_free, "stesso esito con il Deposito pieno o vuoto")
	var pieces := 0
	for r in full_res:
		if str(r.kind) == "skin" or str(r.kind) == "relic":
			pieces += 1
			assert_true(bool(r.carro))
	assert_gt(pieces, 0)
	assert_eq(b.overflow_instance_count(), pieces, "nessuna Finitura persa")
	assert_eq(b.count(CRATE), 18)
	assert_eq(b.count(KEY), 18)


func test_il_carro_si_scarica_da_solo_quando_si_libera_posto() -> void:
	_open_game(11702)
	var b := _bank()
	b.add(KEY, 10, "test")
	b.add(CRATE, 10, "test")
	var fillers := _fill(b)
	var res := _crates().open(CRATE, 6, false)
	var kept := 0
	for r in res:
		if str(r.kind) != "pet":
			kept += 1
	assert_eq(b.overflow_instance_count(), kept)
	var victims: Array = []
	for id in fillers.slice(0, 4):
		victims.append(str(id))
	for u in victims:
		b.remove(u, b.count(u))
	b.tick(0.1)
	assert_eq(b.overflow_instance_count(), maxi(0, kept - 4), "il Carro si svuota nei posti liberati, in ordine di arrivo")
	assert_eq(b.free_slots(), maxi(0, 4 - kept))


func test_le_unita_del_carro_contano_e_si_consumano() -> void:
	_open_game(11703)
	var b := _bank()
	_fill(b)
	b.add("log_pine", 10, "test")
	assert_eq(b.overflow_count(), 10)
	assert_eq(b.count("log_pine"), 10, "le unita' nel Carro contano")
	assert_true(b.remove("log_pine", 4))
	assert_eq(b.count("log_pine"), 6)
	assert_eq(b.overflow_count(), 6)
	assert_true(b.remove("log_pine", 6))
	assert_eq(b.overflow_count(), 0)
	assert_false(b.remove("log_pine", 1))


func test_le_chiavi_si_comprano_e_si_usano_a_deposito_pieno() -> void:
	_open_game(11704)
	var b := _bank()
	var mk := Game.system("market") as MarketSystem
	b.add_gold(100000)
	b.add(CRATE, 5, "test")
	_fill(b)
	assert_eq(b.free_slots(), 0)
	var st := mk.shop_status("buy_key_t1", 3)
	assert_true(bool(st.ok), "l'Emporio non chiede un posto libero per la chiave: " + str(st.reason))
	assert_true(mk.buy("buy_key_t1", 3))
	assert_eq(b.count(KEY), 3)
	assert_eq(b.overflow_count(), 3, "le chiavi aspettano nel Carro")
	var res := _crates().open(CRATE, 3, false)
	assert_eq(res.size(), 3, "con le chiavi nel Carro la Cassa si apre")
	assert_eq(b.count(KEY), 0)


func test_il_riepilogo_online_dice_cosa_e_entrato_nel_carro() -> void:
	_open_game(11705)
	var b := _bank()
	_fill(b)
	var notices: Array = []
	var conn := func(kind: String, _t: String, data: Dictionary) -> void: notices.append([kind, str(data.get("reason", ""))])
	EventBus.notice.connect(conn)
	b.add("log_pine", 3, "test")
	b.tick(1000.0)
	EventBus.notice.disconnect(conn)
	assert_true(notices.has(["warning", "carro_stash"]), "il Registro riassume cosa e' entrato nel Carro")


# ------------------------------------------------------------------ tetto e vendita oltre il tetto

func test_oltre_il_tetto_si_vendono_solo_le_finiture_comuni_mai_reliquie_o_annaliste() -> void:
	_open_game(11706)
	var b := _bank()
	var k: Dictionary = Formulas.k().offline
	var old_cap: Variant = k.overflow_max_instances
	k["overflow_max_instances"] = 2
	_fill(b)
	var skin := _skin()
	var gold0 := b.gold()
	for i in 5:
		b.add_instance({"def_id": skin, "kind": "skin", "rarity": "common", "annalist": false})
	assert_eq(b.overflow_instance_count(), 2, "il Carro tiene fino al tetto dei dati")
	assert_gt(b.gold(), gold0, "oltre il tetto la Finitura comune si vende al Mercato")
	var sold_gold := b.gold()
	# Annalista, Reliquia: restano nel Carro anche oltre il tetto (mai vendute)
	b.add_instance({"def_id": skin, "kind": "skin", "rarity": "common", "annalist": true})
	b.add_instance({"def_id": _relic(), "kind": "relic", "rarity": "relic"})
	k["overflow_max_instances"] = old_cap
	assert_eq(b.overflow_instance_count(), 4, "Annalista e Reliquia non si vendono mai")
	assert_eq(b.gold(), sold_gold)


# ------------------------------------------------------------------ vendita automatica consigliata

func test_vendita_automatica_a_un_clic_rispetta_blocchi_e_reliquie() -> void:
	_open_game(11707)
	var b := _bank()
	var assist := Game.system("assist") as AssistSystem
	assert_false(assist.enable_recommended(), "senza il nodo di Costellazione non si puo'")
	Modifiers.set_source("constellation", [{"key": "auto_sell_unlock", "value": 1}])
	var skin := _skin()
	var u_common := b.add_instance({"def_id": skin, "kind": "skin", "rarity": "common", "annalist": false})
	var u_locked := b.add_instance({"def_id": skin, "kind": "skin", "rarity": "common", "locked": true})
	var u_ann := b.add_instance({"def_id": skin, "kind": "skin", "rarity": "common", "annalist": true})
	var u_epic := b.add_instance({"def_id": skin, "kind": "skin", "rarity": "epic"})
	var u_relic := b.add_instance({"def_id": _relic(), "kind": "relic", "rarity": "relic"})
	assert_false(assist.recommended_active())
	var gold0 := b.gold()
	assert_true(assist.enable_recommended())
	assert_true(assist.recommended_active())
	assert_true(assist.is_auto_dupes())
	assert_gt(b.gold(), gold0, "la regola ha venduto")
	assert_true(b.get_instance(u_common).is_empty(), "la Finitura comune e' venduta")
	for u in [u_locked, u_ann, u_epic, u_relic]:
		assert_false(b.get_instance(u).is_empty(), "bloccata, Annalista, Epica e Reliquia restano")
	assert_true(assist.enable_recommended(), "idempotente")
	assert_eq(assist.rules().size(), 1)


func test_il_pannello_vendi_finiture_usa_il_filtro_dei_dati() -> void:
	_open_game(11708)
	var b := _bank()
	var f := b.recommended_sell_rule()
	assert_eq(str(f.get("cat", "")), "skin")
	assert_eq(str(f.get("max_rarity", "")), "rare")
	assert_true(bool(f.get("keep_special", false)))
	var skin := _skin()
	b.add_instance({"def_id": skin, "kind": "skin", "rarity": "rare"})
	b.add_instance({"def_id": skin, "kind": "skin", "rarity": "legendary"})
	var plan := SellRules.collect(b, Game.system("market") as MarketSystem, f)
	assert_eq(int(plan.pieces), 1, "solo comuni e rare")


# ------------------------------------------------------------------ missioni e salvataggi

func test_il_salvataggio_conserva_il_carro_e_i_vecchi_salvataggi_si_aprono() -> void:
	_open_game(11709)
	var b := _bank()
	_fill(b)
	b.add("log_pine", 7, "test")
	b.add_instance({"def_id": _skin(), "kind": "skin", "rarity": "rare"})
	assert_eq(b.overflow_count(), 8)
	var snap := Game.snapshot(true).duplicate(true)
	var back: Dictionary = JSON.parse_string(JSON.stringify(snap))
	GameState.replace(back)
	Game.sim.bind_state(GameState.data)
	var b2 := Game.system("bank") as BankSystem
	assert_eq(b2.overflow_count(), 8, "il Carro sopravvive al salvataggio")
	assert_eq(b2.count("log_pine"), 7)
	(back.bank as Dictionary).erase("overflow_stacks")           # salvataggio precedente al Carro
	(back.bank as Dictionary).erase("overflow_instances")
	GameState.replace(back)
	Game.sim.bind_state(GameState.data)
	assert_eq((Game.system("bank") as BankSystem).overflow_count(), 0)


func test_offline_con_deposito_pieno_non_perde_e_le_casse_nel_carro_si_aprono() -> void:
	_open_game(11710)
	var b := _bank()
	_fill(b)
	b.add(CRATE, 3, "test")       # nuova pila di Casse nel Carro
	b.add(KEY, 3, "test")
	assert_eq(b.overflow_stacks_count(), 2)
	var res := _crates().open(CRATE, 3, false)
	assert_eq(res.size(), 3, "le Casse e le chiavi nel Carro si aprono")


# ------------------------------------------------------------------ Dispensa e cibo (punti c, d)

func test_la_dispensa_prende_l_eccedenza_del_cibo_negli_slot_dell_eroe() -> void:
	_open_game(11711)
	var b := _bank()
	var es := Game.system("estate") as EstateSystem
	var cb := Game.system("combat") as CombatSystem
	var reserve := int(EstateSystem.tuning().pantry_slot_reserve)
	assert_gt(reserve, 0, "la riserva dello slot viene dai dati")
	es.state.settlers = 20
	es.state.pantry = 0.0
	assert_true(cb.set_food(0, "food_bleak"))
	assert_true(es._auto_foods.any(func(fd: Dictionary) -> bool: return str(fd.id) == "food_bleak"), "food_bleak e' ammesso alla Dispensa")
	b.remove("food_bleak", b.count("food_bleak"))        # niente regalo di nuova partita
	b.add("food_bleak", reserve - 1, "test")
	assert_eq(es._auto_stock(), 0.0, "sotto la riserva lo slot dell'Eroe tiene tutto")
	b.add("food_bleak", 100, "test")
	es.state.pantry = 0.0
	var taken := es._auto_stock()
	assert_gt(taken, 0.0, "l'eccedenza oltre la riserva e' usabile (prima l'intera pila era esclusa)")
	assert_gte(b.count("food_bleak"), reserve, "all'Eroe resta sempre la riserva")


func test_il_collezionista_si_supera_con_il_koi_e_la_guida_lo_dice() -> void:
	_open_game(11712)
	var b := _bank()
	var cb := Game.system("combat") as CombatSystem
	var koi: Dictionary = DataRegistry.item("food_vaultkoi").food
	var lynx: Dictionary = DataRegistry.item("food_lynx").food
	assert_gt(float(koi.heal), float(lynx.heal))
	b.add("food_lynx", 25, "test")
	b.add("food_vaultkoi", 24, "test")        # il regalo di main_c10_q4
	assert_true(cb.set_food(0, "food_lynx"))
	# 113 porzioni di food_lynx a uccisione (misura del report 111): quante di Koi?
	var bf: Dictionary = QuestGuide._best_food_for(cb, 113)
	assert_eq(str(bf.get("id", "")), "food_vaultkoi", "la guida indica il cibo migliore in borsa")
	assert_lte(int(bf.need), 24, "le 24 porzioni di Koi regalate da main_c10_q4 bastano per una uccisione")
	# il bot sceglie il Koi da solo (anche se fosse nel Carro)
	var bot := BotPlayer.new(Game.sim, func(dt: float) -> void: Game._on_step(dt))
	assert_eq(bot._food_id(), "food_vaultkoi")
	_fill(b)
	b.add("food_vaultkoi", 5, "test")
	assert_eq(bot._food_id(), "food_vaultkoi")


func test_la_guida_della_fiala_manda_all_emporio() -> void:
	_open_game(11713)
	GameState.data.unlocks.append("feature:market")
	var w: Dictionary = QuestGuide.where_item("vial")
	assert_true(str(w.text).to_lower().contains("emporio") or str(w.text).to_lower().contains("emporium"), "la Fiala Vuota si compra all'Emporio: " + str(w.text))
	assert_eq(str(w.target.get("screen", "")), "shop")


# ------------------------------------------------------------------ interfaccia

func test_il_pannello_del_carro_compare_solo_quando_serve_e_ha_i_quattro_rimedi() -> void:
	_open_game(11714)
	var b := _bank()
	var panel := CarroPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(2)
	assert_false(panel.visible, "con il Deposito non pieno e il Carro vuoto non c'e'")
	_fill(b)
	panel.refresh(true)
	assert_true(panel.visible, "a Deposito pieno compare")
	for n in ["CarroDupesButton", "CarroSkinsButton", "CarroAutoButton", "CarroExpandButton"]:
		assert_not_null(panel.find_child(n, true, false), n)
	b.add("log_pine", 4, "test")
	panel.refresh(true)
	assert_true((panel.find_child("CarroTitle", true, false) as Label).text.contains("4"), "dice quanti pezzi aspettano nel Carro")
	# senza il nodo di Costellazione il pulsante «Vendita automatica» resta attivo e spiega come ottenerla
	var auto := panel.find_child("CarroAutoButton", true, false) as Button
	assert_false(auto.disabled)
	assert_true(auto.tooltip_text.length() > 0)


func test_la_sala_dei_caveau_mostra_il_carro_e_la_riga_del_premio() -> void:
	_open_game(11715)
	var b := _bank()
	b.add(KEY, 5, "test")
	b.add(CRATE, 5, "test")
	_fill(b)
	var scr: GameScreen = (load("res://src/ui/screens/VaultHallScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(3)
	var panel := scr.find_child("CarroPanel", true, false) as CarroPanel
	assert_not_null(panel, "indicatore del Carro nella Sala dei Caveau")
	assert_true(panel.visible)
	var line: String = scr._carro_line()
	assert_true(line.contains(str(b.overflow_count())), "«Deposito pieno: il premio e' nel Carro di Ritiro (N pezzi)»: " + line)
