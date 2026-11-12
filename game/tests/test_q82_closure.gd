extends GutTest
## QA82 - chiusura dei problemi aperti Q82-1..4 e della vendita automatica del cibo.
##  Q82-1  Casse: estrazione INDICIZZATA (seme del salvataggio, id cassa, contatore): ricaricare dopo l'apertura da' lo
##         stesso esito, nessuna deviazione a costo zero (altre casse, rullo si/no) lo cambia, pity e distribuzione restano
##         quelle dei dati. Migrazione di schema 2 -> 3.
##  Q82-2  Frecce: tetto COMBINATO ai dati (ammo_recovery_max_pct), resta un consumo residuo.
##  Q82-3  thievery_stun_reduction_pct col tetto del catalogo.
##  Q82-4  Game._on_long_gap rispetta il limite offline del caricamento.
##  B10    La vendita automatica «Cibo» non vende il cibo degli slot dell'eroe.

const CRATE := "crate_millbrook"
const OTHER := "crate_saltreach"
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
var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_q82c_saves"
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in [1, 2, 3]:
		SaveService.delete_slot(s)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


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
	bank.stacks[crate_id] = int(bank.stacks.get(crate_id, 0)) + qty
	var key: Variant = DataRegistry.item(crate_id).crate.get("key")
	if key != null:
		bank.stacks[str(key)] = int(bank.stacks.get(str(key), 0)) + qty


## Impronta di un esito, senza uid (cambia da una partita all'altra) e senza rullo.
static func _sig(r: Dictionary) -> Array:
	var i: Dictionary = (r.instance as Dictionary).duplicate()
	i.erase("uid")
	return [r.def_id, r.rarity, i, r.stop_frac]


func _sigs(results: Array) -> Array:
	var out: Array = []
	for r in results:
		out.append(_sig(r))
	return out


# ------------------------------------------------------------------ Q82-1

func test_deviazione_a_costo_zero_non_cambia_l_esito_della_n_esima_apertura() -> void:
	_make(555)
	_fill(CRATE, 12)
	var a := _sigs(crates.open(CRATE, 12, true))
	# B: prima apre altre casse (senza rullo), poi CRATE
	_make(555)
	_fill(CRATE, 12)
	_fill(OTHER, 9)
	crates.open(OTHER, 9, false)
	var b := _sigs(crates.open(CRATE, 12, false))
	assert_eq(a, b, "stesse 12 aperture, comunque si sia deviato prima")
	# C: una alla volta, alternando casse e rullo si/no
	_make(555)
	_fill(CRATE, 12)
	_fill(OTHER, 9)
	var c: Array = []
	for i in 12:
		if i % 3 == 0:
			crates.open(OTHER, 1, i % 2 == 0)
		c.append_array(_sigs(crates.open(CRATE, 1, i % 2 == 1)))
	assert_eq(a, c, "alternanza di casse e di rullo non cambia nulla")


func test_seme_diverso_da_esiti_diversi() -> void:
	_make(1)
	_fill(CRATE, 40)
	var a := _sigs(crates.open(CRATE, 40, false))
	_make(2)
	_fill(CRATE, 40)
	var b := _sigs(crates.open(CRATE, 40, false))
	assert_ne(a, b, "un altro salvataggio ha altri esiti")


func test_contatore_persistito_e_ripristinato_con_lo_stato() -> void:
	_make(77)
	_fill(CRATE, 30)
	crates.open(CRATE, 10, false)
	assert_eq(crates.draw_count(CRATE), 10)
	var snap: Dictionary = crates.to_state().duplicate(true)
	var tail_a := _sigs(crates.open(CRATE, 5, false))
	# "ricarica" dallo stato salvato dopo 10 aperture: le 5 successive sono le stesse
	crates.from_state(snap)
	assert_eq(crates.draw_count(CRATE), 10)
	bank.stacks.clear()
	_fill(CRATE, 5)
	var tail_b := _sigs(crates.open(CRATE, 5, false))
	assert_eq(tail_a, tail_b, "stesso stato salvato, stesso esito")


func test_ricarica_del_salvataggio_stesso_esito() -> void:
	assert_true(Game.new_game(1, "normal", 9091))
	var b := Game.system("bank") as BankSystem
	var cr := Game.system("crates") as CrateSystem
	b.add(CRATE, 30, "test")
	b.add("key_t1", 30, "test")
	assert_true(SaveService.save_now())
	var first := _sigs(cr.open(CRATE, 8, false))
	# ricarica e riprova, con il rullo (azione a costo zero in piu')
	var res: Dictionary = Game.load_game(1)
	assert_true(bool(res.ok))
	cr = Game.system("crates") as CrateSystem
	b = Game.system("bank") as BankSystem
	assert_eq(cr.draw_count(CRATE), 0, "il contatore e' tornato indietro insieme a chiavi e casse")
	assert_eq(b.count(CRATE), 30)
	var second := _sigs(cr.open(CRATE, 8, true))
	assert_eq(first, second, "ricaricare riporta lo stesso esito")
	# salvataggio DOPO l'apertura: ricaricando le successive restano fisse
	assert_true(SaveService.save_now())
	var next_a := _sigs(cr.open(CRATE, 4, false))
	Game.load_game(1)
	cr = Game.system("crates") as CrateSystem
	assert_eq(cr.draw_count(CRATE), 8)
	var next_b := _sigs(cr.open(CRATE, 4, false))
	assert_eq(next_a, next_b)
	Game.stop_game(false)


func test_cento_mila_aperture_distribuzione_e_pity_invariate() -> void:
	_make(2026)
	_fill(CRATE, SAMPLE)
	var counts := {}
	for r in CrateSystem.RARITIES:
		counts[r] = 0
	var res := crates.open(CRATE, SAMPLE, false)
	assert_eq(res.size(), SAMPLE)
	var gap := 0
	var max_gap := 0
	var stars := 0
	for r in res:
		counts[r.rarity] += 1
		if r.rarity == "relic":
			stars += 1
			max_gap = maxi(max_gap, gap)
			gap = 0
		else:
			gap += 1
	var hard := int(Formulas.k().crates.pity.hard)
	assert_lte(max_gap, hard - 1, "pity dura: mai piu' di %d aperture senza stella" % hard)
	var eff := Formulas.effective_rarity_pct()
	for r in CrateSystem.RARITIES:
		var p: float = float(eff[r]) / 100.0
		var sigma := sqrt(p * (1.0 - p) / SAMPLE)
		assert_almost_eq(float(counts[r]) / SAMPLE, p, 5.0 * sigma + 1e-4, "frequenza di " + r)
	var info := crates.pity_info(CRATE)
	assert_almost_eq(float(SAMPLE) / float(stars), float(info.mean_openings), float(info.mean_openings) * 0.06, "media tra due stelle")
	assert_eq(crates.draw_count(CRATE), SAMPLE)


func test_il_rullo_non_cambia_l_esito() -> void:
	_make(31)
	_fill(CRATE, 3)
	var r: Dictionary = crates.open(CRATE, 1, true)[0]
	assert_eq(r.reel.size(), 60)
	assert_eq(r.reel[52].d, r.def_id)
	_make(31)
	_fill(CRATE, 3)
	var r2: Dictionary = crates.open(CRATE, 1, false)[0]
	assert_eq(_sig(r), _sig(r2), "con o senza rullo l'esito e' lo stesso")


func test_contatore_dei_contratti_a_parte() -> void:
	_make(404)
	_fill(CRATE, 20)
	var a := crates.draw_count(CrateSystem.CONTRACT_DRAW_KEY)
	crates.open(CRATE, 5, false)
	assert_eq(crates.draw_count(CrateSystem.CONTRACT_DRAW_KEY), a, "le casse non toccano il contatore dei contratti")
	var r1 := crates._draw_rng(CrateSystem.CONTRACT_DRAW_KEY).randi()
	_make(404)
	var r2 := crates._draw_rng(CrateSystem.CONTRACT_DRAW_KEY).randi()
	assert_eq(r1, r2, "stesso seme e stesso contatore, stessa estrazione")


func test_migrazione_v2_a_v3_aggiunge_il_seme_senza_toccare_il_progresso() -> void:
	assert_gte(SaveCodec.SCHEMA_VERSION, 3)
	var old := {"schema_version": 2, "rng": {"master": "123456789012345678"},
		"crates": {"pity": {"crate_millbrook": 17}, "opened": 40, "found": {"rare": 30}}}
	var res := SaveCodec.migrate(old)
	assert_eq(res.error, "")
	assert_eq(int(res.data.schema_version), SaveCodec.SCHEMA_VERSION)
	var c: Dictionary = res.data.crates
	assert_true(RngStreams.is_u64_string(str(c.draw_seed)) and str(c.draw_seed) != "0")
	assert_eq(c.draw_n, {})
	assert_eq(int(c.pity.crate_millbrook), 17)
	assert_eq(int(c.opened), 40)
	var again := SaveCodec.migrate_v2_to_v3(res.data)
	assert_eq(str(again.crates.draw_seed), str(c.draw_seed), "idempotente")
	var expected := RngStreams.u64_to_string(RngStreams.derive_seed(RngStreams.parse_u64("123456789012345678"), "crate-draw-seed", 0))
	assert_eq(str(c.draw_seed), expected, "uguale alla derivazione lazy di CrateSystem")
	assert_eq(SaveCodec.migrate({"schema_version": 2}).error, "", "senza sezione Casse non si rompe")


func test_salvataggio_v2_si_carica() -> void:
	assert_true(Game.new_game(1, "normal", 321))
	var snap := Game.snapshot(true).duplicate(true)
	snap["schema_version"] = 2
	(snap.crates as Dictionary).erase("draw_seed")
	(snap.crates as Dictionary).erase("draw_n")
	var loaded := SaveCodec.load_bytes(SaveCodec.encode(snap), Game.sim.int_paths())
	assert_true(bool(loaded.ok), str(loaded.get("error", "")))
	assert_eq(int(loaded.data.schema_version), SaveCodec.SCHEMA_VERSION)
	assert_true((loaded.data.crates as Dictionary).has("draw_seed"))
	Game.stop_game(false)


# ------------------------------------------------------------------ Q82-2

func test_frecce_tetto_combinato_e_costo_residuo() -> void:
	assert_eq(int(Formulas.k().combat.rules.ammo_recovery_max_pct), 90)
	assert_true(Game.new_game(1, "normal", 5150))
	var cb := Game.system("combat") as CombatSystem
	var arrow := ""
	for id in DataRegistry.items_by_category("ammo"):
		var d: Dictionary = id if id is Dictionary else DataRegistry.item(str(id))
		if str(d.get("subcategory", "")) == "arrow":
			arrow = str(d.id)
			break
	assert_ne(arrow, "", "esiste almeno una freccia nei dati")
	Modifiers.set_source("test:ammo", [{"key": "ammo_save_pct", "value": 500.0, "mode": "add"}])
	assert_almost_eq(cb._ammo_recovery_pct(arrow), 0.90, 1e-9, "base 20 + bonus (tetto di catalogo 80) = al massimo 90")
	Modifiers.set_source("test:ammo", [{"key": "ammo_save_pct", "value": 60.0, "mode": "add"}])
	assert_almost_eq(cb._ammo_recovery_pct(arrow), 0.80, 1e-9, "sotto il tetto: 20 + 60")
	Modifiers.clear_source("test:ammo")
	assert_almost_eq(cb._ammo_recovery_pct(arrow), 0.20, 1e-9)
	# consumo reale: con il massimo dei bonus ~10% delle frecce parte comunque
	Modifiers.set_source("test:ammo", [{"key": "ammo_save_pct", "value": 500.0, "mode": "add"}])
	var rng := Rng.stream("combat")
	rng.seed = 99
	var used := 0
	for i in 20000:
		if not rng.randf() < cb._ammo_recovery_pct(arrow):
			used += 1
	assert_almost_eq(float(used) / 20000.0, 0.10, 0.012, "resta un consumo residuo")
	Modifiers.clear_source("test:ammo")
	Game.stop_game(false)


# ------------------------------------------------------------------ Q82-3

func test_stordimento_borseggio_col_tetto_del_catalogo() -> void:
	assert_true(Game.new_game(1, "normal", 5151))
	var sk := Game.system("skills") as SkillSystem
	var act := ""
	for a in DataRegistry.actions_for_skill("thievery"):
		if (a as Dictionary).has("success") and float((a as Dictionary).get("stun_s", 0.0)) > 0.0:
			act = str((a as Dictionary).id)
			break
	assert_ne(act, "", "un'azione di Borseggio con stordimento")
	Modifiers.set_source("test:stun", [{"key": "thievery_stun_reduction_pct", "value": 400.0, "mode": "add"}])
	var cap: float = Modifiers.stack.cap_of("thievery_stun_reduction_pct")
	assert_almost_eq(cap, 75.0, 1e-9)
	var p: Dictionary = sk._profile(act)
	assert_almost_eq(float(p.stun_s), float(DataRegistry.action(act).stun_s) * 0.25, 1e-6, "lo stordimento non sparisce")
	assert_gt(float(p.stun_s), 0.0)
	Modifiers.clear_source("test:stun")
	Game.stop_game(false)


# ------------------------------------------------------------------ Q82-4

func test_lungo_stallo_rispetta_il_limite_offline() -> void:
	assert_true(Game.new_game(1, "normal", 5152))
	var got: Array = []
	var cb := func(sec: float, _rep: Dictionary) -> void: got.append(sec)
	EventBus.offline_progress.connect(cb)
	var cap: float = Game.offline_cap_s()
	Game._on_long_gap(cap * 3.0)
	EventBus.offline_progress.disconnect(cb)
	assert_eq(got.size(), 1)
	assert_almost_eq(float(got[0]), cap, 1.0, "mai oltre il tetto del caricamento")
	Game.stop_game(false)


# ------------------------------------------------------------------ B10

func test_vendita_automatica_cibo_salva_gli_slot_dell_eroe() -> void:
	assert_true(Game.new_game(1, "normal", 5153))
	var b := Game.system("bank") as BankSystem
	var cb := Game.system("combat") as CombatSystem
	var mk := Game.system("market") as MarketSystem
	b.add("food_bleak", 50, "test")
	b.add("food_carp", 30, "test")
	var bleak := b.count("food_bleak")
	var carp := b.count("food_carp")
	assert_true(cb.set_food(0, "food_bleak"))
	var plan := SellRules.collect(b, mk, SellRules.new_filter("food"))
	var ids: Array = []
	for g in plan.groups:
		ids.append(str(g.id))
	assert_false(ids.has("food_bleak"), "il cibo dello slot non si vende")
	assert_true(ids.has("food_carp"), "gli altri cibi si vendono")
	assert_gte(int(plan.in_use), bleak)
	SellRules.execute(mk, plan)
	assert_eq(b.count("food_bleak"), bleak)
	assert_eq(b.count("food_carp"), 0)
	assert_gt(carp, 0)
	Game.stop_game(false)
