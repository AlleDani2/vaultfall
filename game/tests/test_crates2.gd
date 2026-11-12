extends GutTest
## CRATES-2: Fondi / Vendi / Blocca, Contratti (Scambio e Aureo), Affinatura, Banco dei Caveau, Sfida dei Collezionisti.
## Regola 5 (docs/24): probabilità mostrate = usate, esito estratto prima di mostrare, determinismo, nessuna posta.
## Usa il Deposito VERO (BankSystem) con il CrateSystem vero.

const MIL := "crate_millbrook"
const SAL := "crate_saltreach"
const TOKENS: Array = ["feature:tradeup", "feature:golden_contract", "feature:refinery", "feature:collectors_challenge"]

var sim: Simulation
var crates: CrateSystem
var bank: BankSystem
var state: Dictionary
var mods: ModifierStack


func _make(seed_value: int = 7, unlocks: Array = TOKENS) -> void:
	state = {"unlocks": unlocks.duplicate(), "stats": {"playtime_s": 0.0}}
	mods = ModifierStack.new()
	mods.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, mods, RngStreams.new(seed_value), EventBus)
	sim = Simulation.new()
	bank = BankSystem.new()
	crates = CrateSystem.new()
	sim.setup(ctx, [bank, crates])
	sim.bind_state(state)
	bank.state.slots_bought = 5000


func _skin(crate_id: String, rarity: String, k: int = 0) -> String:
	return str(crates.contents(crate_id)[rarity][k])


## Aggiunge al Deposito una finitura con float noto (default: a metà del suo intervallo).
func _give(def_id: String, f: float = -1.0, annalist: bool = false) -> String:
	var d := DataRegistry.item(def_id)
	var sk: Dictionary = d.skin
	if f < 0.0:
		f = (float(sk.float_min) + float(sk.float_max)) * 0.5
	var inst := {"def_id": def_id, "kind": "skin", "rarity": d.rarity, "crate": "crate_" + str(d.crate), "condition": crates.condition_for_float(f),
		"float": f, "annalist": annalist, "seed": 1, "phase": "", "polish": 0, "locked": false}
	return bank.add_instance(inst)


func _give_many(crate_id: String, rarity: String, n: int, annalist: bool = false) -> Array:
	var out: Array = []
	var size: int = crates.contents(crate_id)[rarity].size()
	for i in n:
		out.append(_give(_skin(crate_id, rarity, i % size), -1.0, annalist))
	return out


# ------------------------------------------------------------------ Fondi / Vendi / Blocca

func test_fondi_da_schegge_per_rarita_e_bonus() -> void:
	_make()
	var shards_by_rarity := {"rare": 1, "epic": 5, "legendary": 25, "mythic": 125}
	for r in shards_by_rarity:
		var u := _give(_skin(MIL, r))
		assert_eq(crates.fuse_value(u), shards_by_rarity[r], r)
	var u2 := _give(_skin(MIL, "epic"))
	assert_eq(crates.fuse(u2), 5)
	assert_eq(crates.shards(), 5)
	assert_true(crates.instance(u2).is_empty(), "fuso = sparito")
	mods.set_source("t", [{"key": "shards_pct", "value": 50, "mode": "add"}])
	var u3 := _give(_skin(MIL, "legendary"))
	assert_eq(crates.fuse(u3), roundi(25 * 1.5), "shards_pct si applica")


func test_fondi_vendi_rifiutano_bloccati_e_in_uso() -> void:
	_make()
	var def_id := _skin(MIL, "rare")
	var u := _give(def_id)
	assert_true(crates.set_locked(u, true))
	assert_true(crates.is_locked(u))
	assert_eq(crates.consume_block(u), "locked")
	assert_eq(crates.fuse(u), 0)
	assert_eq(crates.sell(u), 0)
	assert_false(crates.instance(u).is_empty(), "l'oggetto bloccato è ancora lì")
	assert_true(crates.set_locked(u, false))
	assert_true(crates.equip(u))
	assert_eq(crates.consume_block(u), "in_use")
	assert_eq(crates.fuse(u), 0)
	assert_eq(crates.sell_price(u), 0)
	crates.unequip(str(DataRegistry.item(def_id).skin.slot))
	assert_eq(crates.consume_block(u), "")
	assert_gt(crates.fuse(u), 0)


func test_vendi_prezzo_con_moltiplicatori_e_oro_di_gioco() -> void:
	_make()
	var def_id := _skin(MIL, "epic")
	var d := DataRegistry.item(def_id)
	var plain := _give(def_id, 0.30)
	var ann := _give(def_id, 0.30, true)
	var tax := float(DataRegistry.constants.market.skin_sell_tax)
	var cond_mult := float(crates.condition_info(crates.condition_for_float(0.30)).value_mult)
	var expect_plain := maxi(1, roundi(float(d.value) * (1.0 - tax) * cond_mult))
	assert_eq(crates.sell_price(plain), expect_plain)
	assert_eq(crates.sell_price(ann), maxi(1, roundi(float(d.value) * (1.0 - tax) * cond_mult * 2.2)), "Annalista ×2,2")
	var gold0 := bank.gold()
	var got := crates.sell(plain)
	assert_eq(got, expect_plain)
	assert_eq(bank.gold(), gold0 + got)
	assert_true(crates.instance(plain).is_empty())


# ------------------------------------------------------------------ Contratti

func test_contratto_anteprima_mostra_ogni_esito_con_probabilita() -> void:
	_make()
	var ins: Array = _give_many(MIL, "rare", 6) + _give_many(SAL, "rare", 4)
	var pv := crates.contract_preview(ins)
	assert_true(pv.ok, str(pv.reason))
	assert_eq(pv.rarity_in, "rare")
	assert_eq(pv.rarity_out, "epic")
	var total := 0.0
	var by_crate := {}
	for o in pv.outcomes:
		total += float(o.pct)
		by_crate[o.crate] = float(by_crate.get(o.crate, 0.0)) + float(o.pct)
		var sk: Dictionary = DataRegistry.item(o.def_id).skin
		assert_eq(DataRegistry.item(o.def_id).rarity, "epic", "solo la rarità successiva")
		assert_gte(float(o.float), float(sk.float_min) - 1e-9)
		assert_lte(float(o.float), float(sk.float_max) + 1e-9)
		assert_eq(str(o.condition), crates.condition_for_float(float(o.float)), "condizione prevista coerente")
	assert_almost_eq(total, 100.0, 1e-9)
	assert_almost_eq(float(by_crate[MIL]), 60.0, 1e-9, "collezione in proporzione agli ingressi")
	assert_almost_eq(float(by_crate[SAL]), 40.0, 1e-9)
	assert_eq(pv.outcomes.size(), 8, "4 epiche per cassa")


func test_contratto_float_in_uscita_segue_la_formula() -> void:
	_make()
	var ins := _give_many(MIL, "rare", 10)
	var norm_sum := 0.0
	for u in ins:
		var inst := crates.instance(u)
		var sk: Dictionary = DataRegistry.item(inst.def_id).skin
		norm_sum += (float(inst.float) - float(sk.float_min)) / (float(sk.float_max) - float(sk.float_min))
	var avg := norm_sum / 10.0
	var pv := crates.contract_preview(ins)
	assert_almost_eq(float(pv.avg_norm), avg, 1e-9)
	var res := crates.contract_sign(ins)
	assert_false(res.is_empty())
	var out := crates.instance(res.uid)
	var sk2: Dictionary = DataRegistry.item(res.def_id).skin
	assert_almost_eq(float(out.float), float(sk2.float_min) + (float(sk2.float_max) - float(sk2.float_min)) * avg, 1e-9, "formula docs/09 §9.4")
	assert_eq(out.rarity, "epic")
	assert_eq(out.condition, crates.condition_for_float(float(out.float)))
	for u in ins:
		assert_true(crates.instance(u).is_empty(), "ingressi consumati")
	assert_eq(crates.state.stats.contracts, 1)


func test_contratto_probabilita_mostrate_uguali_a_quelle_usate() -> void:
	_make(31)
	var ins := _give_many(MIL, "rare", 7) + _give_many(SAL, "rare", 3)
	var pv := crates.contract_preview(ins)
	var want := {}
	for o in pv.outcomes:
		want[o.def_id] = float(o.pct) / 100.0
	var counts := {}
	var n := 3000
	for i in n:
		var cur: Array = _give_many(MIL, "rare", 7) + _give_many(SAL, "rare", 3)
		var res := crates.contract_sign(cur)
		counts[res.def_id] = int(counts.get(res.def_id, 0)) + 1
		crates.fuse(res.uid)
	for did in want:
		var p: float = want[did]
		var sigma := sqrt(p * (1.0 - p) / n)
		assert_almost_eq(float(counts.get(did, 0)) / n, p, 5.0 * sigma, "frequenza di " + did)
	for did in counts:
		assert_true(want.has(did), "mai un esito non annunciato: " + did)


func test_contratto_determinismo_e_estrazione_prima_di_mostrare() -> void:
	var a := _sign_with_seed(555)
	var b := _sign_with_seed(555)
	var c := _sign_with_seed(556)
	assert_eq(a, b, "stesso seed, stesso esito")
	assert_ne(a, c, "seed diverso")
	_make(9)
	var ins := _give_many(MIL, "epic", 10)
	var got: Array = []
	var cb := func(kind: String, _p: Dictionary) -> void: got.append(kind)
	EventBus.objective_event.connect(cb)
	var res := crates.contract_sign(ins)
	EventBus.objective_event.disconnect(cb)
	assert_false(res.is_empty())
	assert_eq(got, ["tradeup"], "evento per le missioni")
	assert_false(crates.instance(res.uid).is_empty(), "l'esito è già nel Deposito quando la funzione ritorna")


func _sign_with_seed(seed_value: int) -> Array:
	_make(seed_value)
	var res := crates.contract_sign(_give_many(MIL, "rare", 10))
	var inst: Dictionary = res.instance.duplicate()
	inst.erase("uid")
	return [res.def_id, inst]


func test_contratto_rifiuta_ingressi_non_validi() -> void:
	_make()
	var ten := _give_many(MIL, "rare", 10)
	assert_true(crates.contract_check(ten).ok)
	assert_eq(crates.contract_check(ten.slice(0, 9)).reason, "count")
	var mixed := ten.slice(0, 9) + [_give(_skin(MIL, "epic"))]
	assert_eq(crates.contract_check(mixed).reason, "rarity")
	var var_mix := ten.slice(0, 9) + [_give(_skin(MIL, "rare"), -1.0, true)]
	assert_eq(crates.contract_check(var_mix).reason, "variant")
	crates.set_locked(ten[0], true)
	assert_eq(crates.contract_check(ten).reason, "locked")
	crates.set_locked(ten[0], false)
	var dup := ten.slice(0, 9) + [ten[0]]
	assert_eq(crates.contract_check(dup).reason, "dup")
	assert_eq(crates.contract_check(_give_many(MIL, "mythic", 10)).reason, "rarity", "le Mitiche vanno nel Contratto Aureo")
	assert_eq(crates.contract_sign(mixed), {}, "firma rifiutata, nulla consumato")
	assert_false(crates.instance(ten[1]).is_empty())
	# funzione non sbloccata
	_make(7, [])
	var t2 := _give_many(MIL, "rare", 10)
	assert_eq(crates.contract_check(t2).reason, "locked_feature")


func test_contratto_aureo_5_mitiche_in_una_reliquia() -> void:
	_make(77)
	var ins := _give_many(MIL, "mythic", 2) + _give_many(SAL, "mythic", 2) + _give_many(MIL, "mythic", 1)
	var pv := crates.contract_preview(ins, true)
	assert_true(pv.ok, str(pv.reason))
	assert_eq(pv.rarity_out, "relic")
	var total := 0.0
	var pool := {}
	for cid in [MIL, SAL]:
		for did in crates.contents(cid).relic:
			pool[did] = true
	for o in pv.outcomes:
		total += float(o.pct)
		assert_true(pool.has(o.def_id), "solo la riserva ★ delle collezioni in ingresso")
	assert_almost_eq(total, 100.0, 1e-9)
	var ph := 0.0
	for p in pv.phases:
		ph += float(p.pct)
	assert_almost_eq(ph, 100.0, 1e-9, "anche le fasce colore sono dichiarate")
	var res := crates.contract_sign(ins, true)
	assert_false(res.is_empty())
	assert_eq(res.rarity, "relic")
	if res.kind == "relic":
		assert_ne(str(res.instance.phase), "")
		assert_false(crates.instance(res.uid).is_empty())
	assert_eq(crates.state.stats.golden, 1)
	assert_eq(crates.contract_check(_give_many(MIL, "mythic", 4), true).reason, "count")


func test_contratto_auto_pick_sceglie_i_peggiori_consumabili() -> void:
	_make()
	var ins := _give_many(MIL, "rare", 12)
	crates.set_locked(ins[0], true)
	var pick := crates.auto_pick("rare", false)
	assert_eq(pick.size(), 10)
	assert_false(pick.has(ins[0]), "i bloccati non si propongono")
	assert_true(crates.contract_check(pick).ok)


# ------------------------------------------------------------------ Affinatura

func test_lucidatura_formula_costo_e_massimo() -> void:
	_make()
	bank.add_currency("vault_shard", 100000)
	var def_id := _skin(MIL, "epic")
	var sk: Dictionary = DataRegistry.item(def_id).skin
	var u := _give(def_id, 0.60)
	var f := 0.60
	for n in 10:
		var info := crates.polish_info(u)
		assert_true(info.ok, "lucidatura %d" % n)
		assert_eq(int(info.cost), int(ceil(5 * 0.5 * (1 + n))), "costo = ceil(schegge × 0,5 × (1 + fatte))")
		var expect := f - 0.10 * (f - float(sk.float_min))
		assert_almost_eq(float(info.new_float), expect, 1e-12)
		var before := crates.shards()
		assert_true(crates.polish(u))
		assert_eq(before - crates.shards(), int(info.cost))
		f = expect
		assert_almost_eq(float(crates.instance(u).float), f, 1e-12)
		assert_eq(crates.instance(u).condition, crates.condition_for_float(f))
	assert_eq(crates.polish_info(u).reason, "max")
	assert_false(crates.polish(u))
	assert_eq(int(crates.instance(u).polish), 10)


func test_lucidatura_senza_schegge_o_al_minimo_non_fa_nulla() -> void:
	_make()
	var u := _give(_skin(MIL, "rare"), 0.5)
	assert_eq(crates.polish_info(u).reason, "shards")
	assert_false(crates.polish(u))
	assert_almost_eq(float(crates.instance(u).float), 0.5, 1e-12, "niente è stato toccato")
	bank.add_currency("vault_shard", 50)
	var sk: Dictionary = DataRegistry.item(_skin(MIL, "rare")).skin
	var m := _give(_skin(MIL, "rare"), float(sk.float_min))
	assert_eq(crates.polish_info(m).reason, "at_min")
	_make(7, [])
	var z := _give(_skin(MIL, "rare"), 0.5)
	assert_eq(crates.polish_info(z).reason, "locked_feature")


func test_lucidatura_aggiorna_bonus_equipaggiato() -> void:
	_make()
	bank.add_currency("vault_shard", 1000)
	var def_id := _skin(MIL, "rare")
	var u := _give(def_id, 0.74)        # Sfregiato
	crates.equip(u)
	var key := str(DataRegistry.item(def_id).skin.modifier.key)
	var v0 := mods.total_add(key)
	for i in 6:
		crates.polish(u)
	assert_ne(crates.instance(u).condition, "scarred")
	assert_gt(mods.total_add(key), v0, "il bonus del Guardaroba sale con la condizione")


func test_incisione_annalista_e_targhetta() -> void:
	_make()
	var u := _give(_skin(MIL, "legendary"))
	assert_eq(crates.engrave_info(u).cost, 25 * 8)
	assert_eq(crates.engrave_info(u).reason, "shards")
	assert_false(crates.engrave(u))
	bank.add_currency("vault_shard", 200)
	assert_true(crates.engrave(u))
	assert_true(bool(crates.instance(u).annalist))
	assert_eq(bank.currency("vault_shard"), 0)
	assert_eq(crates.engrave_info(u).reason, "already")
	# targhetta
	assert_eq(crates.rename_info(u, "Pippo").reason, "gold")
	var g_before := bank.gold()
	bank.add_gold(10000)
	assert_true(crates.rename(u, "  Pippo\u0007  "))
	assert_eq(crates.instance(u).tag, "Pippo", "ripulita")
	assert_eq(bank.gold(), g_before)
	assert_true(CrateUi.tagged_name(crates.instance(u)).contains("Pippo"))
	assert_eq(crates.clean_tag("x".repeat(60)).length(), 24)
	assert_true(crates.rename(u, ""), "togliere la targhetta è gratis")
	assert_false(crates.instance(u).has("tag"))


# ------------------------------------------------------------------ Banco dei Caveau

func test_banco_compra_con_le_schegge() -> void:
	_make()
	assert_gt(crates.vault_stock().size(), 5)
	assert_eq(crates.vault_buy_check("key_t1"), "shards")
	assert_false(crates.vault_buy("key_t1"))
	bank.add_currency("vault_shard", 100)
	assert_eq(crates.vault_buy_check("key_t1"), "")
	assert_true(crates.vault_buy("key_t1", 2))
	assert_eq(bank.count("key_t1"), 2)
	assert_eq(bank.currency("vault_shard"), 100 - 60)
	assert_eq(crates.vault_buy_check("sword"), "unknown", "solo ciò che è in listino")
	assert_eq(crates.vault_buy_check("key_t6"), "shards")


# ------------------------------------------------------------------ Sfida dei Collezionisti

func test_sfida_non_conta_se_non_sbloccata() -> void:
	_make(7, [])
	bank.add(MIL, 3)
	bank.add("key_t1", 3)
	crates.open(MIL, 3, false)
	assert_eq(crates.challenge_info().score, 0)


func test_sfida_punti_rarita_dai_dati_e_rivali_deterministici() -> void:
	_make(11)
	assert_eq(crates.challenge_points("rare"), 1)
	assert_eq(crates.challenge_points("relic"), 250)   # audit 84: era 1000 (la ★ decideva la Sfida)
	bank.add(MIL, 40)
	bank.add("key_t1", 40)
	var expect := 0
	for r in crates.open(MIL, 40, false):
		expect += crates.challenge_points(str(r.rarity))
	var info := crates.challenge_info()
	assert_eq(info.score, expect, "punteggio = somma dei punti rarità degli oggetti trovati")
	var board := crates.challenge_board()
	assert_eq(board.size(), 4)
	assert_true(board.any(func(e: Dictionary) -> bool: return e.player))
	var rivals1: Dictionary = crates.state.challenge.rivals.duplicate()
	assert_eq(rivals1.keys().size(), 3)
	_make(11)
	crates.challenge_sync()
	assert_eq(crates.state.challenge.rivals, rivals1, "stesso seed, stessi rivali")
	_make(12)
	crates.challenge_sync()
	assert_ne(crates.state.challenge.rivals, rivals1, "seed diverso, rivali diversi")


func test_sfida_fine_settimana_assegna_piazzamento_e_premio_ritirabile() -> void:
	_make(21)
	crates.challenge_sync()
	var week := int(crates.challenge_info().week)
	assert_gte(week, 0)
	state.stats.playtime_s = 8.0 * 86400.0          # più di una settimana di gioco
	var pend := crates.challenge_pending()
	assert_false(pend.is_empty(), "la settimana è chiusa: premio in attesa")
	assert_eq(pend.week, week)
	assert_between(int(pend.place), 1, 4)
	var rewards: Array = pend.rewards
	var shards0 := crates.shards()
	assert_eq(crates.challenge_claim_check(), "")
	assert_true(crates.challenge_claim())
	assert_true(crates.challenge_pending().is_empty(), "ritirato una volta sola")
	assert_false(crates.challenge_claim())
	var got := 0
	for e in rewards:
		if e.item == "vault_shard":
			got += int(e.qty)
	assert_eq(crates.shards(), shards0 + got)
	assert_eq(int(crates.challenge_info().week), 1, "nuova settimana aperta")


func test_sfida_pari_merito_vince_il_giocatore() -> void:
	_make()
	assert_eq(crates._place_of(100, {"a": 100, "b": 100, "c": 100}), 1)
	assert_eq(crates._place_of(99, {"a": 100, "b": 100, "c": 100}), 4)
	assert_eq(crates._place_of(100, {"a": 101, "b": 50, "c": 100}), 2)


func test_sfida_premi_solo_valuta_di_gioco() -> void:
	var rw: Dictionary = DataRegistry.rules("crate_rules").collectors_challenge.rewards_by_place
	for place in rw:
		for e in rw[place]:
			var it := DataRegistry.item(str(e.item))
			assert_true(str(it.category) in ["currency", "key"], "premio solo Schegge o chiavi (nessun oggetto in palio): " + str(e.item))


# ------------------------------------------------------------------ la migliore dell'apertura multipla

func test_migliore_del_lotto() -> void:
	var rs: Array = [
		{"rarity": "rare", "instance": {"float": 0.01}},
		{"rarity": "legendary", "instance": {"float": 0.9}},
		{"rarity": "legendary", "instance": {"float": 0.2}},
		{"rarity": "epic", "instance": {"float": 0.0}},
	]
	assert_eq(CrateSystem.best_result_index(rs), 2, "rarità più alta, poi float più basso")
	rs.append({"rarity": "relic", "instance": {"float": 1.0}})
	assert_eq(CrateSystem.best_result_index(rs), 4)
	assert_eq(CrateSystem.best_result_index([]), -1)


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_conserva_sfida_statistiche_e_istanze() -> void:
	_make(5)
	bank.add(MIL, 5)
	bank.add("key_t1", 5)
	crates.open(MIL, 5, false)
	var u := _give(_skin(MIL, "epic"))
	bank.add_currency("vault_shard", 30)
	bank.add_gold(10000)
	crates.rename(u, "Salvami")
	crates.fuse(_give(_skin(MIL, "rare")))
	var score := int(crates.challenge_info().score)
	var snap := {"bank": bank.to_state(), "crates": crates.to_state(), "currencies": state.currencies}
	var back: Dictionary = JSON.parse_string(JSON.stringify(snap))
	var paths := PackedStringArray()
	for p in crates.int_paths():
		paths.append("crates." + p)
	var errs := SaveCodec.normalize(back, paths)
	assert_eq(errs.size(), 0, str(errs))
	_make(5)
	state["currencies"] = back.currencies
	bank.from_state(back.bank)
	crates.from_state(back.crates)
	assert_eq(int(crates.state.challenge.score), score)
	assert_typeof(crates.state.challenge.score, TYPE_INT)
	assert_typeof(crates.state.challenge.week, TYPE_INT)
	assert_eq(int(crates.state.stats.fused), 1)
	assert_eq(crates.instance(u).tag, "Salvami")
	assert_eq(bank.currency("vault_shard"), 31)
	# salvataggio vecchio senza le sezioni nuove: si completa senza rompersi
	var old: Dictionary = back.crates.duplicate(true)
	old.erase("stats")
	old.erase("challenge")
	crates.from_state(old)
	assert_eq(crates.state.stats, {})
	crates.challenge_sync()
	assert_gte(int(crates.challenge_info().week), 0)


func test_apertura_normale_invariata_con_le_nuove_sezioni() -> void:
	# l'ordine dei numeri casuali dell'apertura non cambia (stessa sequenza con e senza Sfida sbloccata)
	var a := _open_seq(TOKENS)
	var b := _open_seq([])
	assert_eq(a, b)


func _open_seq(unlocks: Array) -> Array:
	_make(2024, unlocks)
	bank.add(MIL, 30)
	bank.add("key_t1", 30)
	var out: Array = []
	for r in crates.open(MIL, 30):
		out.append([r.def_id, r.rarity, r.stop_frac, r.instance.get("float", 0.0)])
	return out
