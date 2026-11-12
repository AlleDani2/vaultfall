extends GutTest
## CrateSystem (T-4.1): distribuzioni, pity, determinismo, estrazione prima dell'animazione, probabilità
## mostrate = usate. Usa un finto Deposito con le stesse firme del contratto "bank".

const CRATE := "crate_millbrook"
const SAMPLE := 100000


class FakeBank extends GameSystem:
	var stacks: Dictionary = {}
	var inst: Dictionary = {}
	var n: int = 0
	func _init() -> void:
		id = "bank"
	func free_slots() -> int:
		return 1 << 40
	func add(def_id: String, qty: int, _source: String = "") -> int:
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
	func add_instance(i: Dictionary) -> String:
		n += 1
		var uid := "i_%06d" % n
		i["uid"] = uid
		inst[uid] = i
		return uid
	func get_instance(uid: String) -> Dictionary:
		return inst.get(uid, {})
	func remove_instance(uid: String) -> bool:
		return inst.erase(uid)
	func list_instances() -> Array:
		return inst.values()


var sim: Simulation
var crates: CrateSystem
var bank: FakeBank
var state: Dictionary
var mods: ModifierStack


func _make(seed_value: int = 7) -> void:
	state = {}
	mods = ModifierStack.new()
	mods.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, mods, RngStreams.new(seed_value), EventBus)
	sim = Simulation.new()
	bank = FakeBank.new()
	crates = CrateSystem.new()
	sim.setup(ctx, [bank, crates])
	sim.bind_state(state)


func _fill(crate_id: String, qty: int) -> void:
	bank.stacks[crate_id] = qty
	var key: Variant = DataRegistry.item(crate_id).crate.get("key")
	if key != null:
		bank.stacks[str(key)] = qty


func test_probabilita_sommano_100_e_coincidono_con_i_dati() -> void:
	_make()
	for c in DataRegistry.items_by_category("crate"):
		var tot := 0.0
		var cur := 0.0
		for r in crates.odds(c.id):
			tot += r.pct
			cur += r.current_pct
			var item_sum := 0.0
			for it in r.items:
				item_sum += it.pct
			assert_almost_eq(item_sum, r.pct, 1e-6, "%s %s: somma oggetti = rarità" % [c.id, r.rarity])
		assert_almost_eq(tot, 100.0, 1e-6, c.id)
		assert_almost_eq(cur, 100.0, 1e-6, c.id + " (correnti)")
	var rows := crates.odds(CRATE)
	assert_eq(rows.size(), 5)
	assert_almost_eq(rows[0].pct, 79.2, 1e-9)
	assert_almost_eq(rows[0].items[0].pct, 13.2, 1e-9, "13,2% ciascuna")
	assert_almost_eq(rows[4].effective_pct, 0.571, 0.005, "★ effettiva con la pity")


func test_pity_coincide_con_formulas() -> void:
	_make()
	var st := CrateSystem.pity_stats(0.003, int(Formulas.k().crates.pity.soft_start))
	var ref := Formulas.relic_pity_stats()
	assert_almost_eq(float(st[0]), float(ref[0]), 1e-9)
	assert_almost_eq(float(st[1]), float(ref[1]), 1e-12)
	var info := crates.pity_info(CRATE)
	assert_almost_eq(info.mean_openings, 175.0, 0.1)


func test_distribuzione_su_100000_aperture() -> void:
	_make(12345)
	_fill(CRATE, SAMPLE)
	var counts := {}
	for r in CrateSystem.RARITIES:
		counts[r] = 0
	var res := crates.open(CRATE, SAMPLE, false)
	assert_eq(res.size(), SAMPLE)
	for r in res:
		counts[r.rarity] += 1
	var eff := Formulas.effective_rarity_pct()
	for r in CrateSystem.RARITIES:
		var p: float = float(eff[r]) / 100.0
		var sigma := sqrt(p * (1.0 - p) / SAMPLE)
		assert_almost_eq(float(counts[r]) / SAMPLE, p, 5.0 * sigma + 1e-4, "frequenza di " + r)
	assert_eq(int(state.crates.opened), SAMPLE)


func test_condizioni_e_float_rispettano_le_probabilita_della_finitura() -> void:
	_make(99)
	_fill(CRATE, 20000)
	var by_def := {}
	for r in crates.open(CRATE, 20000, false):
		if r.kind != "skin":
			continue
		var i: Dictionary = r.instance
		var d := DataRegistry.item(r.def_id)
		var sk: Dictionary = d.skin
		assert_true(float(i.float) >= float(sk.float_min) - 1e-9 and float(i.float) <= float(sk.float_max) + 1e-9,
			"float dentro l'intervallo della finitura")
		var cond := crates.condition_info(i.condition)
		assert_true(float(i.float) >= float(cond.float_min) - 1e-9 and float(i.float) <= float(cond.float_max) + 1e-9,
			"float dentro la fascia della condizione")
		assert_true(sk.condition_odds.has(i.condition), "condizione impossibile estratta")
		var e: Dictionary = by_def.get(r.def_id, {"n": 0})
		e.n += 1
		e[i.condition] = int(e.get(i.condition, 0)) + 1
		by_def[r.def_id] = e
	var checked := 0
	for did in by_def:
		var e: Dictionary = by_def[did]
		if e.n < 1000:
			continue
		checked += 1
		var co: Dictionary = DataRegistry.item(did).skin.condition_odds
		for c in co:
			var p: float = float(co[c]) / 100.0
			var sigma := sqrt(p * (1.0 - p) / e.n)
			assert_almost_eq(float(e.get(c, 0)) / e.n, p, 5.0 * sigma, "%s %s" % [did, c])
	assert_gt(checked, 0)


func test_pity_garantisce_la_stella_e_si_azzera() -> void:
	_make(5)
	_fill(CRATE, 600)
	var hard := int(Formulas.k().crates.pity.hard)
	state.crates.pity[CRATE] = hard - 1
	var r: Dictionary = crates.open(CRATE, 1)[0]
	assert_eq(r.rarity, "relic", "alla %dª è garantita" % hard)
	assert_eq(r.relic_p, 1.0)
	assert_eq(int(state.crates.pity[CRATE]), 0)
	var r2: Dictionary = crates.open(CRATE, 1)[0]
	assert_eq(int(state.crates.pity[CRATE]), 0 if r2.rarity == "relic" else 1)
	assert_false(state.crates.pity.has("crate_saltreach"), "un contatore per famiglia")


func test_pity_morbida_aumenta_la_probabilita_e_il_nodo_la_anticipa() -> void:
	_make()
	var base: float = crates.rarity_weights(CRATE, 0).relic
	var soft := crates.soft_start()
	var later: float = crates.rarity_weights(CRATE, soft + 10).relic
	assert_almost_eq(later, base + float(Formulas.k().crates.pity.soft_step) * 11, 1e-9)
	assert_almost_eq(float(crates.rarity_weights(CRATE, soft - 1).relic), base, 1e-12)
	mods.set_source("test", [{"key": "pity_soft_start_reduction", "value": 100, "mode": "add"}])
	assert_eq(crates.soft_start(), soft - 100)
	assert_gt(float(crates.rarity_weights(CRATE, soft - 50).relic), base, "la soglia anticipata vale subito")
	var sum := 0.0
	for v in crates.rarity_weights(CRATE, 300).values():
		sum += v
	assert_almost_eq(sum, 1.0, 1e-9)


func test_determinismo_del_seed() -> void:
	var a := _run_sequence(4242)
	var b := _run_sequence(4242)
	var c := _run_sequence(4243)
	assert_eq(a, b, "stesso seed, stesse aperture")
	assert_ne(a, c, "seed diverso, aperture diverse")


func _run_sequence(seed_value: int) -> Array:
	_make(seed_value)
	_fill(CRATE, 60)
	var out: Array = []
	for r in crates.open(CRATE, 60):
		var i: Dictionary = r.instance.duplicate()
		i.erase("uid")
		out.append([r.def_id, r.rarity, i, r.stop_frac, r.reel])
	return out


func test_estrazione_prima_dell_animazione() -> void:
	_make()
	_fill(CRATE, 3)
	var before: int = bank.count(CRATE)
	var r: Dictionary = crates.open(CRATE, 1)[0]
	# quando open() ritorna è già tutto applicato: Deposito, pity, contatori, album
	assert_eq(bank.count(CRATE), before - 1)
	assert_eq(bank.count("key_t1"), before - 1, "chiave consumata")
	assert_eq(int(state.crates.opened), 1)
	if r.kind != "pet":
		assert_true(bank.inst.has(r.uid), "istanza già nel Deposito")
	assert_eq(r.reel.size(), 60)
	assert_eq(r.reel[52].d, r.def_id, "il vincitore del rullo è il risultato già estratto")
	assert_eq(r.reel[52].r, r.rarity)


func test_rullo_riempitivi_con_probabilita_reali() -> void:
	_make(31)
	_fill(CRATE, 3000)
	var counts := {}
	var tot := 0
	for r in crates.open(CRATE, 3000):
		for i in r.reel.size():
			if i == 52:
				continue
			counts[r.reel[i].r] = int(counts.get(r.reel[i].r, 0)) + 1
			tot += 1
			var pool: Array = crates.contents(CRATE)[r.reel[i].r]
			assert_true(pool.has(r.reel[i].d), "tessera coerente con la sua rarità")
	for row in crates.odds(CRATE):
		var p: float = row.effective_pct / 100.0       # i riempitivi usano le probabilità EFFETTIVE (pity inclusa), audit 53
		var sigma := sqrt(p * (1.0 - p) / tot)
		assert_almost_eq(float(counts.get(row.rarity, 0)) / tot, p, 5.0 * sigma + 1e-4, "riempitivi " + row.rarity)


func test_senza_chiave_o_cassa_non_si_apre() -> void:
	_make()
	bank.stacks[CRATE] = 2
	assert_eq(crates.open(CRATE, 1).size(), 0, "manca la chiave")
	bank.stacks["key_t1"] = 1
	assert_eq(crates.open(CRATE, 5).size(), 1, "si ferma quando finisce la chiave")
	assert_eq(bank.count(CRATE), 1)


func test_crate_found_aggiunge_la_cassa() -> void:
	_make()
	EventBus.crate_found.emit(CRATE, "test")
	assert_eq(bank.count(CRATE), 1)
	crates.grant_crate(CRATE, 4)
	assert_eq(bank.count(CRATE), 5)


func test_capsule_ed_eventi_senza_pity() -> void:
	_make()
	bank.stacks["capsule_banners"] = 50
	var res := crates.open("capsule_banners", 50, false)
	assert_eq(res.size(), 50)
	assert_true(state.crates.pity.is_empty(), "le capsule non hanno pity")
	for r in res:
		assert_eq(r.kind, "cosmetic")
	bank.stacks["crate_event_blossom"] = 1
	assert_eq(crates.open("crate_event_blossom").size(), 0, "serve il costo in valuta evento")
	bank.stacks["event_petal"] = 25
	assert_eq(crates.open("crate_event_blossom").size(), 1)
	assert_eq(bank.count("event_petal"), 0)


func test_guardaroba_bonus_e_annalista() -> void:
	_make()
	var skin_id := "skin_millbrook_01"
	var d := DataRegistry.item(skin_id)
	var uid := bank.add_instance({"def_id": skin_id, "kind": "skin", "condition": "pristine", "float": 0.05, "annalist": true})
	assert_true(crates.equip(uid))
	assert_eq(crates.equipped(d.skin.slot), uid)
	var key: String = d.skin.modifier.key
	var expect: float = float(d.skin.modifier.value) * 1.2
	assert_almost_eq(mods.total_add(key), expect, 1e-9, "bonus x condizione (Intatto x1,2)")
	for i in 100:
		EventBus.action_completed.emit("x", [])
		EventBus.monster_killed.emit("m", [])
	assert_eq(int(state.crates.ann.get(uid, 0)), 100, "100 conteggiate (uccisioni o azioni secondo lo slot)")
	assert_almost_eq(mods.total_add(key), expect + 0.2, 1e-9, "traguardo 100: +0,2 punti")
	crates.unequip(d.skin.slot)
	assert_almost_eq(mods.total_add(key), 0.0, 1e-9)


func test_collezione_completa_da_bonus() -> void:
	_make()
	var cdef := DataRegistry.get_def("collections", "collection_millbrook")
	var cr: Dictionary = DataRegistry.item("crate_millbrook").crate
	var m: Dictionary = cdef.complete_bonus.modifiers[0]
	for sid in cr.skins:
		_fake_found(sid)
	assert_true(crates.collection_progress("collection_millbrook").complete)
	assert_almost_eq(mods.total_add(m.key, ["gathering"]), float(m.value), 1e-9)
	assert_false(crates.collection_progress("collection_millbrook").golden)
	for rid in cr.relic_pool:
		_fake_found(rid)
	assert_true(crates.collection_progress("collection_millbrook").golden)
	assert_almost_eq(mods.total_add(m.key, ["gathering"]), 2.0 * float(m.value), 1e-9, "Aurea: raddoppiato")


func _fake_found(def_id: String) -> void:
	crates._record_find("crate_millbrook", def_id, {"float": 0.5})


func test_salvataggio_ricostruisce_i_modificatori() -> void:
	_make()
	var skin_id := "skin_millbrook_02"
	var uid := bank.add_instance({"def_id": skin_id, "kind": "skin", "condition": "marked", "float": 0.3, "annalist": false})
	crates.equip(uid)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.crates))
	var key: String = DataRegistry.item(skin_id).skin.modifier.key
	mods.clear_all()
	crates.from_state(saved)
	assert_gt(mods.total_add(key), 0.0)
