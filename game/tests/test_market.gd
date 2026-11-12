extends GutTest
## MarketSystem: prezzi vs formule di riferimento (docs/10 §3), saturazione e recupero, limite di rendimento
## economico (docs/19, R-EC-3), Commesse, Emporio, fazioni, offline. Usa un finto bank con le firme del contratto.


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var gold_n: int = 0
	var cap_full: bool = false
	func _init() -> void:
		id = "bank"
	func add(def_id: String, qty: int, _source: String = "") -> int:
		if cap_full:
			return 0
		stacks[def_id] = int(stacks.get(def_id, 0)) + qty
		return qty
	func remove(def_id: String, qty: int) -> bool:
		if int(stacks.get(def_id, 0)) < qty:
			return false
		stacks[def_id] = int(stacks[def_id]) - qty
		return true
	func count(def_id: String) -> int:
		return int(stacks.get(def_id, 0))
	func has(def_id: String, qty: int = 1) -> bool:
		return count(def_id) >= qty
	func gold() -> int:
		return gold_n
	func add_gold(n: int) -> void:
		gold_n += n
	func spend_gold(n: int) -> bool:
		if gold_n < n:
			return false
		gold_n -= n
		return true


var _state: Dictionary
var _sim: Simulation
var _mk: MarketSystem
var _bank: FakeBank
var _ctx: SystemContext


func _make(seed_value: int = 7, unlocked: bool = true) -> void:
	_state = {"unlocks": ["feature:market"] if unlocked else [], "skills": {}, "bank": {"stacks": {}}}
	_ctx = SystemContext.make(DataRegistry, _state, ModifierStack.new(), RngStreams.new(seed_value), EventBus)
	_ctx.modifiers.set_catalog(DataRegistry.table("modifier_catalog"))
	_bank = FakeBank.new()
	_mk = MarketSystem.new()
	_sim = Simulation.new()
	_sim.setup(_ctx, [_bank, _mk])
	_sim.bind_state(_state)


func after_each() -> void:
	if _mk != null:
		_mk.teardown()


func _rules() -> Dictionary:
	return DataRegistry.rules("market_rules")


# ------------------------------------------------------------------ prezzi

func test_prezzo_senza_vendite_e_valore_per_tendenza_per_tassa() -> void:
	_make()
	var v := float(DataRegistry.item("log_pine").value)
	assert_almost_eq(_mk.price_sell("log_pine"), v * 1.0 * (1.0 - float(_rules().sell_tax)), 1e-9)
	_state.market.trend["log"] = 1.2
	assert_almost_eq(_mk.price_sell("log_pine"), v * 1.2 * 0.95, 1e-9)


func test_oggetti_da_cassa_tassa_maggiore_e_chiavi_non_vendibili() -> void:
	_make()
	var skin: Dictionary = DataRegistry.items_by_category("skin")[0]
	assert_almost_eq(_mk.tax_rate(skin.id), float(DataRegistry.constants.market.skin_sell_tax), 1e-9)
	assert_eq(_mk.price_sell("key_t1"), 0.0, "le chiavi non si vendono (R-EC-6)")
	_bank.stacks["key_t1"] = 3
	assert_eq(_mk.sell("key_t1", 3), 0)
	assert_eq(_bank.count("key_t1"), 3)


func test_tassa_ridotta_da_modificatori_con_cap_80() -> void:
	_make()
	_ctx.modifiers.set_source("t", [{"key": "market_tax_reduction_pct", "value": 20, "mode": "add"}])
	assert_almost_eq(_mk.tax_rate("log_pine"), 0.05 * 0.8, 1e-9)
	_ctx.modifiers.set_source("t", [{"key": "market_tax_reduction_pct", "value": 500, "mode": "add"}])
	assert_almost_eq(_mk.tax_rate("log_pine"), 0.05 * 0.2, 1e-9, "cap 80%")


func test_volume_elastico_dalle_azioni() -> void:
	_make()
	# wc_pine: 1 tronco ogni 3 s = 1200/h -> 8 ore (elasticità dei dati) = 9600
	assert_almost_eq(_mk.volume("log_pine"), float(DataRegistry.rules("market_rules").demand.elasticity_hours_of_production) * 3600.0 / 3.0, 1e-6)
	assert_gt(_mk.volume("sword_copper"), 20.0, "anche l'equipaggiamento ha volume elastico (audit 53)")
	assert_gte(_mk.volume("bar_copper"), 20.0)


func test_vendita_riduce_il_prezzo_come_da_formula() -> void:
	_make()
	var v := _mk.volume("log_pine")
	var unit := _mk.base_price("log_pine")
	_bank.stacks["log_pine"] = 100000
	var q := 1000
	var expected := roundi(unit * v * log((v + q) / v))
	assert_eq(_mk.quote_sell("log_pine", q), expected, "anteprima = integrale della curva")
	var gold := _mk.sell("log_pine", q)
	assert_eq(gold, expected)
	assert_eq(_bank.gold(), expected)
	assert_eq(_bank.count("log_pine"), 100000 - q)
	assert_almost_eq(_mk.demand("log_pine"), 1.0 / (1.0 + q / v), 1e-9)
	assert_lt(_mk.price_sell("log_pine"), unit, "il prezzo cala dopo aver venduto")
	assert_lt(float(gold) / q, unit, "prezzo medio sotto il prezzo iniziale")
	assert_gt(float(gold) / q, _mk.price_sell("log_pine"), "e sopra il prezzo marginale finale")


func test_saturazione_a_meta_volume_dimezza_la_domanda() -> void:
	_make()
	var v := _mk.volume("log_pine")
	_bank.stacks["log_pine"] = int(v) + 10
	_mk.sell("log_pine", int(v))
	assert_almost_eq(_mk.demand("log_pine"), 0.5, 1e-3, "venduto = volume elastico -> domanda 1/2")


func test_recupero_con_emivita_6_ore_di_gioco() -> void:
	_make()
	var v := _mk.volume("log_pine")
	_bank.stacks["log_pine"] = int(v)
	_mk.sell("log_pine", int(v))
	var x0 := _mk.recent_sold("log_pine")
	_mk.simulate_offline(6.0 * 3600.0)
	assert_almost_eq(_mk.recent_sold("log_pine"), x0 * 0.5, x0 * 1e-6, "dimezza ogni 6 h")
	assert_gt(_mk.demand("log_pine"), 0.5)
	assert_gt(_mk.hours_to_recover("log_pine", 0.9), 0.0)
	_mk.simulate_offline(24.0 * 3600.0 * 3.0)
	assert_gt(_mk.demand("log_pine"), 0.99, "dopo giorni la domanda è piena")
	assert_eq(_mk.hours_to_recover("log_pine", 0.9), 0.0)


func test_recupero_dipende_dal_tempo_di_gioco_non_dai_tick() -> void:
	_make()
	_bank.stacks["log_pine"] = 5000
	_mk.sell("log_pine", 5000)
	var a := _mk.recent_sold("log_pine")
	for i in 600:
		_sim.tick(0.1)         # 60 s
	assert_almost_eq(_mk.game_time(), 60.0, 1e-6)
	assert_almost_eq(_mk.recent_sold("log_pine"), a * pow(0.5, 60.0 / 21600.0), a * 1e-9)


func test_vendita_parziale_e_oggetti_mancanti() -> void:
	_make()
	_bank.stacks["log_pine"] = 5
	var g := _mk.sell("log_pine", 50)
	assert_gt(g, 0)
	assert_eq(_bank.count("log_pine"), 0, "vende al massimo quanto possiede")
	assert_eq(_mk.sell("log_pine", 1), 0)
	assert_eq(_mk.sell("log_pine", 0), 0)


func test_equipaggiamento_dai_png_usa_il_ricarico_dedicato() -> void:
	_make()
	var rules := DataRegistry.rules("market_rules")
	var mult := float(rules.get("buy_markup_equipment", 0.0))
	assert_gt(mult, float(rules.buy_markup) * 2.0, "l'equipaggiamento costa molto più degli altri oggetti (E47-8)")
	_state.market.trend["equipment"] = 1.0
	var def_id := "plate_body_iron"
	assert_eq(_mk.category_of(def_id), "equipment")
	assert_eq(_mk.buy_price_npc(def_id), ceili(float(DataRegistry.item(def_id).value) * mult))
	assert_eq(_mk.buy_price_npc("log_pine"), ceili(float(DataRegistry.item("log_pine").value) * float(rules.buy_markup) * _mk.trend("log")),
		"gli altri oggetti restano ×buy_markup")
	assert_gt(float(_mk.buy_price_npc(def_id)), _mk.price_sell(def_id) * 5.0, "niente arbitraggio sull'equipaggiamento")


func test_acquisto_dai_png_costa_piu_della_vendita() -> void:
	_make()
	for it_id in ["log_pine", "bar_copper", "ore_copper", "food_bleak"]:
		if _mk.category_of(it_id) == "":
			continue
		assert_gt(float(_mk.buy_price_npc(it_id)), _mk.price_sell(it_id) * 1.5, "niente arbitraggio: " + it_id)
	_state.market.trend["log"] = 0.7
	assert_eq(_mk.buy_price_npc("log_pine"), ceili(float(DataRegistry.item("log_pine").value) * 1.8 * 0.7))
	_bank.gold_n = 1000000
	var cap := _mk.npc_stock("log_pine")
	assert_gt(cap, 0)
	assert_true(_mk.buy_npc("log_pine", cap))
	assert_eq(_mk.npc_stock("log_pine"), 0, "scorte esaurite")
	assert_false(_mk.buy_npc("log_pine", 1))
	_mk.simulate_offline(3600.0)
	assert_eq(_mk.npc_stock("log_pine"), cap, "rifornite ogni 60 minuti di gioco")


# ------------------------------------------------------------------ tendenze e Gazzetta

func test_tendenza_ornstein_uhlenbeck_giornaliera() -> void:
	_make(11)
	var ref := RngStreams.new(11)
	var rng := ref.stream("market")
	var rules: Dictionary = _rules().trend
	var cats: Array = _rules().categories
	var x := {}
	for c in cats:
		x[c] = 1.0
	_mk.simulate_offline(86400.0)
	for c in cats:
		x[c] = clampf(x[c] + rules.theta * (1.0 - x[c]) + rules.sigma * rng.randfn(), rules.min, rules.max)
	# nel giorno possono essere estratti anche eventi della Gazzetta (stesso flusso): confrontiamo solo senza sblocco
	_make(11, false)
	_mk.simulate_offline(86400.0)
	for c in cats:
		assert_almost_eq(_mk.trend(c), x[c], 1e-12, "tendenza " + c)
	assert_eq((_mk.trend_history(cats[0]) as Array).size(), 2)


func test_tendenza_sempre_nei_limiti_e_storico_30_giorni() -> void:
	_make(3, false)
	_mk.simulate_offline(86400.0 * 120.0)
	for c in _mk.categories():
		assert_between(_mk.trend(c), 0.7, 1.4)
		assert_lte((_mk.trend_history(c) as Array).size(), 30)


func test_gazzetta_cambia_il_prezzo_della_categoria() -> void:
	_make(5)
	var before := _mk.price_sell("bar_copper")
	_state.market.gazette.active.append({"id": "smiths_strike", "category": "bar", "mult": 1.35, "ends_t": 3600.0})
	assert_almost_eq(_mk.price_sell("bar_copper"), before * 1.35, 1e-9)
	_mk.simulate_offline(3601.0)
	assert_almost_eq(_mk.gazette_mult("bar"), 1.0, 1e-9, "scaduto dopo la durata")


func test_gazzetta_ogni_3_ore_se_sbloccato() -> void:
	_make(9)
	var rep := _mk.simulate_offline(3.0 * 3600.0 * 4 + 1.0)
	assert_eq((_state.market.gazette.log as Array).size(), 4)
	assert_true(rep is Dictionary)
	_make(9, false)
	_mk.simulate_offline(3.0 * 3600.0 * 4 + 1.0)
	assert_eq((_state.market.gazette.log as Array).size(), 0, "senza feature:market non c'è Gazzetta")


# ------------------------------------------------------------------ limite di rendimento economico (docs/19)

func test_rendimento_vendendo_la_produzione_resta_sotto_gph() -> void:
	# Vendo ogni ora tutta la produzione di una mansione di raccolta; tendenza al massimo (1,4): peggior caso.
	_make(1, false)
	for tier_item in [["log_pine", 1], ["log_birch", 2], ["log_cedar", 4]]:
		var item_id: String = tier_item[0]
		if not DataRegistry.has_item(item_id):
			continue
		_make(1, false)
		for cat in _mk.categories():
			_state.market.trend[cat] = 1.4
		var rate_per_h := _mk.volume(item_id) / 4.0
		var hours := 72
		var earned := 0
		for h in hours:
			_bank.stacks[item_id] = int(rate_per_h)
			earned += _mk.sell(item_id, int(rate_per_h))
			_mk.simulate_offline(3600.0)
			for cat in _mk.categories():
				_state.market.trend[cat] = 1.4
		var tier := int(DataRegistry.item(item_id).tier)
		var gph := Formulas.gph(tier)
		var per_hour := float(earned) / hours
		assert_lt(per_hour, 1.5 * gph, "R-EC-3: %s rende %.0f/h contro tetto %.0f" % [item_id, per_hour, 1.5 * gph])


func test_ricavo_totale_limitato_da_logaritmo() -> void:
	_make()
	_bank.stacks["log_pine"] = 10000000
	var v := _mk.volume("log_pine")
	var g := _mk.sell("log_pine", 10000000)
	var naive := _mk.base_price("log_pine") * 10000000.0
	assert_lt(float(g), naive * 0.01, "vendere 10 milioni di fila non vale nemmeno l'1% del valore nominale")
	assert_almost_eq(float(g), _mk.base_price("log_pine") * v * log(1.0 + 10000000.0 / v), 1.0)


# ------------------------------------------------------------------ Commesse

func _seed_seen() -> void:
	for i in ["log_pine", "ore_copper", "bar_copper", "food_bleak", "hide_rabbit"]:
		if DataRegistry.has_item(i):
			_state.market.seen[i] = true


func test_commesse_generate_solo_con_sblocco_e_oggetti_visti() -> void:
	_make(2, false)
	_seed_seen()
	_sim.tick(0.1)
	assert_eq(_mk.orders().size(), 0, "senza feature:market niente bacheca")
	_make(2, true)
	_sim.tick(0.1)
	assert_eq(_mk.orders().size(), 0, "nessun oggetto ancora visto")
	_seed_seen()
	_mk.simulate_offline(4.0 * 3600.0 + 1.0)
	assert_eq(_mk.orders().size(), _mk.order_slots())
	assert_eq(_mk.order_slots(), int(DataRegistry.rules("orders_rules").board_slots))


func test_commessa_forma_ricompensa_e_reputazione() -> void:
	_make(4)
	_seed_seen()
	_sim.tick(0.1)
	var rules := DataRegistry.rules("orders_rules")
	assert_gt(_mk.orders().size(), 0)
	for o in _mk.orders():
		var it: Dictionary = DataRegistry.item(o.item)
		var ratio := float(o.gold) / (float(o.qty) * float(it.value))
		var rr: Array = rules.reward_mult_range
		assert_between(ratio, float(rr[0]) - 0.05, float(rr[1]) + 0.05, "ricompensa = qty × valore × reward_mult_range (R-EC-3: max 1,5)")
		assert_lte(float(rr[1]), 1.5, "R-EC-3: una Commessa non supera 1,5 volte il valore")
		assert_false(["skin", "relic"].has(str(it.category)), "niente Finiture/Reliquie tra le Commesse")
		assert_false(bool(it.get("unique", false)), "niente armi uniche da drop tra le Commesse")
		assert_eq(int(o.rep), 10 + 5 * int(it.tier))
		assert_eq(o.faction, rules.faction_by_category.get(_mk.category_of(o.item), "merchant_league"))
		var qr: Array = rules.qty_range
		assert_lte(int(o.qty), int(ceil(_mk.volume(o.item) * float(qr[1]))) + 1)
		assert_gte(int(o.qty), 1)
		assert_gt(float(o.expires_t), float(o.created_t))


## Q119-2: una Commessa non chiede centinaia di pezzi non impilabili (si costruiscono UNO per volta con «Costruisci»):
## prima c'erano 1.912 Spade di Rame (15.862 oro) impossibili da consegnare.
func test_q119_commesse_pezzi_singoli_in_quantita_piccola() -> void:
	var cap := int(DataRegistry.rules("orders_rules")["unique_qty_max"])
	assert_gt(cap, 0, "orders_rules.unique_qty_max esiste (dai dati)")
	var visti := 0
	for seed_v in range(1, 25):
		_make(seed_v)
		for t in DataRegistry.items_by_category("equipment"):
			if bool(t.get("tradeable", true)) and not bool(t.get("unique", false)) and not bool(t.get("stackable", true)):
				_state.market.seen[str(t.id)] = true
		_mk.simulate_offline(30.0 * 3600.0)
		assert_gt(_mk.orders().size(), 0, "bacheca vuota seed %d candidati %d" % [seed_v, _mk.order_candidates().size()])
		for o in _mk.orders():
			var it: Dictionary = DataRegistry.item(o.item)
			if not bool(it.get("stackable", true)):
				visti += 1
				assert_lte(int(o.qty), cap, "Commessa di un pezzo singolo con quantita' enorme: " + str(o.item) + " x" + str(o.qty))
	assert_gt(visti, 0, "il test ha visto almeno una Commessa di equipaggiamento")


## Q119-2b: una Commessa vecchia (salvataggio precedente) di 1.912 Spade di Rame si riduce al tetto, con ricompensa in proporzione.
func test_q119_commessa_vecchia_ridotta_al_caricamento() -> void:
	_make(3)
	var cap := int(DataRegistry.rules("orders_rules").unique_qty_max)
	_state["orders"] = [{"id": "o_old", "item": "sword_copper", "qty": 1912, "gold": 15862, "rep": 15, "faction": "order_of_wardens",
		"npc": "ilde", "crate": "", "created_t": 0.0, "expires_t": 1e9}]
	_mk.from_state(_state.get("market"))
	var o: Dictionary = _mk.get_order("o_old")
	assert_eq(int(o.qty), cap)
	assert_eq(int(o.gold), roundi(15862.0 * float(cap) / 1912.0))


func test_consegna_commessa_paga_e_da_reputazione() -> void:
	_make(4)
	_seed_seen()
	_sim.tick(0.1)
	var o: Dictionary = _mk.orders()[0]
	assert_false(_mk.complete_order(o.id), "senza gli oggetti non si consegna")
	_bank.stacks[o.item] = int(o.qty)
	var rep_before := _mk.reputation(o.faction)
	assert_true(_mk.complete_order(o.id))
	assert_eq(_bank.count(o.item), 0)
	assert_eq(_bank.gold(), int(o.gold))
	assert_eq(_mk.reputation(o.faction), rep_before + int(o.rep))
	assert_eq(_mk.get_order(o.id), {})
	assert_eq(int(_state.market.orders_done), 1)


func test_rifiuto_sostituisce_dopo_30_minuti_e_senza_penalita() -> void:
	_make(4)
	_seed_seen()
	_sim.tick(0.1)
	var n := _mk.orders().size()
	_mk.reject_order(_mk.orders()[0].id)
	assert_eq(_mk.orders().size(), n - 1)
	_mk.simulate_offline(29.0 * 60.0)
	assert_eq(_mk.orders().size(), n - 1, "ancora vuoto prima dei 30 minuti")
	_mk.simulate_offline(2.0 * 60.0)
	assert_eq(_mk.orders().size(), n, "sostituita dopo 30 minuti di gioco")
	assert_eq(_mk.reputation("merchant_league"), 0, "nessuna penalità")


func test_anti_fomo_le_commesse_restano_7_giorni() -> void:
	_make(4)
	_seed_seen()
	_sim.tick(0.1)
	var ids: Array = _mk.orders().map(func(o: Dictionary) -> String: return o.id)
	_mk.simulate_offline(6.0 * 86400.0)
	var still: Array = _mk.orders().map(func(o: Dictionary) -> String: return o.id)
	for i in ids:
		assert_true(still.has(i), "dopo 6 giorni di assenza la commessa c'è ancora: " + str(i))
	_mk.simulate_offline(2.0 * 86400.0)
	for i in ids:
		assert_false((_mk.orders().map(func(o: Dictionary) -> String: return o.id)).has(i), "scaduta dopo 7 giorni")


func test_limite_economico_commesse() -> void:
	# docs/19 / R-EC-3: ogni commessa paga al massimo 2,4× il valore e chiede al massimo 0,6 volumi elastici
	# (= 2,4 ore di produzione): il flusso massimo è limitato da posti/rinnovo.
	_make(4)
	_seed_seen()
	_sim.tick(0.1)
	var rules := DataRegistry.rules("orders_rules")
	var max_per_hour := 0.0
	for o in _mk.orders():
		var it: Dictionary = DataRegistry.item(o.item)
		var rate := _mk.volume(o.item) / 4.0
		max_per_hour = maxf(max_per_hour, float(o.gold) / maxf(1.0, float(o.qty) / rate))
		assert_lte(float(o.gold), float(o.qty) * float(it.value) * 2.4 + 1.0)
	var board_hours := float(rules.refresh_h)
	assert_gt(board_hours, 0.0)
	assert_lte(float(_mk.order_slots()) / board_hours, 1.0, "al massimo 1 commessa nuova all'ora")


func test_slot_extra_dai_modificatori_e_commessa_con_cassa() -> void:
	_make(4)
	_seed_seen()
	_ctx.modifiers.set_source("t", [{"key": "orders_slots", "value": 2, "mode": "add"}])
	assert_eq(_mk.order_slots(), 6)


# ------------------------------------------------------------------ fazioni

func test_gradi_di_fazione_e_bonus() -> void:
	_make()
	assert_eq(_mk.rank_id("merchant_league"), "neutral")
	_mk.add_reputation("merchant_league", 999)
	assert_eq(_mk.rank_id("merchant_league"), "neutral")
	_mk.add_reputation("merchant_league", 1)
	assert_eq(_mk.rank_id("merchant_league"), "friendly")
	assert_almost_eq(_ctx.modifiers.total_add("market_tax_reduction_pct"), 10.0, 1e-9)
	assert_almost_eq(_mk.tax_rate("log_pine"), 0.05 * 0.9, 1e-9)
	_mk.add_reputation("merchant_league", 4000)
	assert_eq(_mk.rank_id("merchant_league"), "honored")
	assert_eq(_mk.order_slots(), 5, "Onorato: +1 commessa")
	assert_almost_eq(_ctx.modifiers.total_add("market_tax_reduction_pct"), 10.0, 1e-9, "i bonus dei gradi si sommano senza raddoppiare")
	assert_eq(_mk.add_reputation("nessuna", 5), 0)


func test_reputazione_moltiplicata_da_faction_rep_pct() -> void:
	_make()
	_ctx.modifiers.set_source("t", [{"key": "faction_rep_pct", "value": 50, "mode": "add"}])
	assert_eq(_mk.add_reputation("grey_hand", 100), 150)


# ------------------------------------------------------------------ Emporio

func test_emporio_oggetti_e_oro() -> void:
	_make()
	assert_false(_mk.buy("buy_vial", 1), "senza oro")
	_bank.gold_n = 100
	assert_true(_mk.buy("buy_vial", 5))
	assert_eq(_bank.count("vial"), 5)
	assert_eq(_bank.gold(), 100 - 5 * int(_mk.shop_entry("buy_vial").price))
	assert_false(_mk.buy("inesistente"))
	_bank.cap_full = true
	var g := _bank.gold()
	assert_false(_mk.buy("buy_vial", 1), "deposito pieno: nessun addebito")
	assert_eq(_bank.gold(), g)


func test_emporio_potenziamenti_catena_e_modificatori() -> void:
	_make()
	_bank.gold_n = 10000000
	assert_eq(_mk.shop_status("auto_eat_2").reason, "requires_item")
	assert_true(_mk.buy("auto_eat_1"))
	assert_eq(int(_mk.auto_eat().threshold_pct), 25)
	assert_false(_mk.buy("auto_eat_1"), "acquisto unico")
	assert_true(_mk.buy("auto_eat_2"))
	assert_eq(int(_mk.auto_eat().threshold_pct), 35)
	assert_true(_mk.buy("action_queue_1"))
	assert_gt(_ctx.modifiers.total_add("action_queue_slots"), 0.0)
	assert_eq(_mk.shop_status("market_license_1").reason, "requires_faction")
	_mk.add_reputation("merchant_league", 1000)
	assert_true(_mk.buy("market_license_1"))
	assert_almost_eq(_ctx.modifiers.total_add("market_tax_reduction_pct"), 10.0 + 20.0, 1e-9)


func test_emporio_prezzi_da_formula_dei_dati() -> void:
	_make()
	var lo := _mk.shop_entry("loadout_slot")
	assert_eq(_mk.shop_unit_price(lo, 0), 50000)
	assert_eq(_mk.shop_unit_price(lo, 2), 450000)
	var bs := _mk.shop_entry("bank_slot")
	assert_eq(_mk.shop_unit_price(bs, 0), 200, "resoconto 114: 200 * 1,03^n")
	assert_eq(_mk.shop_unit_price(bs, 1), roundi(200 * 1.03))
	assert_eq(_mk.shop_unit_price(bs, 500), 5000000, "tetto 5.000.000")
	_bank.gold_n = 100000000
	assert_true(_mk.buy("bank_slot", 3))
	assert_eq(_mk.owned("bank_slot"), 3)
	assert_almost_eq(_ctx.modifiers.total_add("bank_slots"), 3.0, 1e-9)
	assert_eq(_mk.shop_status("bank_slot", 1).max, 340)


func test_emporio_chiavi_limite_giornaliero_e_livello() -> void:
	_make()
	_bank.gold_n = 1000000
	assert_true(_mk.buy("buy_key_t1", 5))
	assert_eq(_mk.shop_status("buy_key_t1").reason, "limit")
	assert_false(_mk.buy("buy_key_t1"))
	_mk.simulate_offline(86400.0)
	assert_true(_mk.buy("buy_key_t1", 2), "il limite si rinnova col giorno di gioco")
	assert_eq(_mk.shop_status("buy_key_t2").reason, "requires_level")
	_state.skills["hero"] = {"level": 20}
	assert_true(_mk.buy("buy_key_t2"))


# ------------------------------------------------------------------ salvataggio e offline

func test_salvataggio_roundtrip_e_offline_coincide_con_i_tick() -> void:
	_make(21)
	_seed_seen()
	_bank.stacks["log_pine"] = 3000
	_mk.sell("log_pine", 3000)
	_sim.tick(0.1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_state))
	var a_state := saved.duplicate(true)
	var b_state := saved.duplicate(true)
	var sims: Array = []
	for s in [a_state, b_state]:
		var c := SystemContext.make(DataRegistry, s, ModifierStack.new(), RngStreams.new(21), EventBus)
		c.modifiers.set_catalog(DataRegistry.table("modifier_catalog"))
		var sim := Simulation.new()
		var mk := MarketSystem.new()
		sim.setup(c, [FakeBank.new(), mk])
		sim.bind_state(s)
		sims.append([sim, mk])
	sims[0][0].run_offline(3.0 * 3600.0)
	for i in 108000:
		sims[1][0].tick(0.1)
	assert_almost_eq(float(a_state.market.t), float(b_state.market.t), 1e-3)
	assert_eq(a_state.orders.size(), b_state.orders.size())
	assert_eq(a_state.market.gazette.log.size(), b_state.market.gazette.log.size())
	assert_almost_eq(sims[0][1].recent_sold("log_pine"), sims[1][1].recent_sold("log_pine"), 1e-3)
	for p in sims:
		p[1].teardown()
