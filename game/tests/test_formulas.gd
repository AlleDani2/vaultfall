extends GutTest
## T-1.2: Formulas.gd contro TUTTI i casi di tests/reference_values.json (generato da tools/export_reference_values.py).
## Il numero di casi può crescere senza toccare questo file; una funzione nuova nel file di riferimento
## fa fallire test_ogni_funzione_e_coperta finché non viene portata.

const REF_PATH := "res://tests/reference_values.json"
const SimFx := preload("res://tests/helpers/sim_fixtures.gd")

var _cases: Array = []


func before_all() -> void:
	assert_true(DataRegistry.is_loaded(), "DataRegistry carico (python tools/sync_data.py)")
	Formulas.configure(DataRegistry.constants, DataRegistry._formula_extras())
	var text := FileAccess.get_file_as_string(REF_PATH)
	assert_false(text.is_empty(), "manca %s (python tools/export_reference_values.py)" % REF_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_cases = parsed.cases


func _call(fn: String, a: Array) -> Variant:
	match fn:
		"xp_to_next": return Formulas.xp_to_next(int(a[0]))
		"xp_total_for_level": return Formulas.xp_total_for_level(int(a[0]))
		"tier_of_level": return Formulas.tier_of_level(int(a[0]))
		"xph": return Formulas.xph(int(a[0]))
		"gph": return Formulas.gph(int(a[0]))
		"food_heal": return Formulas.food_heal(int(a[0]))
		"weapon_damage": return Formulas.weapon_damage(int(a[0]), float(a[1]))
		"mastery_to_next": return Formulas.mastery_to_next(int(a[0]))
		"hit_chance": return Formulas.hit_chance(float(a[0]), float(a[1]))
		"damage_reduction": return Formulas.damage_reduction(float(a[0]), float(a[1]))
		"triangle_mult": return Formulas.triangle_mult(a[0], a[1])
		"monster_stats": return Formulas.monster_stats(int(a[0]), a[1])
		"echo_multiplier": return Formulas.echo_multiplier(int(a[0]), int(a[1]))
		"star_haste_pct": return Formulas.star_haste_pct(int(a[0]))
		"star_xp_pct": return Formulas.star_xp_pct(int(a[0]))
		"star_curve": return Formulas.star_curve(float(a[0]), float(a[1]), int(a[2]))
		"stardust_for_star": return Formulas.stardust_for_star(int(a[0]))
		"soci_total": return Formulas.soci_total(float(a[0]))
		"estate_units_per_hour": return Formulas.estate_units_per_hour(int(a[0]))
		"estate_cost_gold": return Formulas.estate_cost_gold(int(a[0]), int(a[1]))
		"estate_milestone_mult": return Formulas.estate_milestone_mult(int(a[0]))
		"quality_chances": return Formulas.quality_chances(int(a[0]), int(a[1]))
		"key_shop_price": return Formulas.key_shop_price(int(a[0]))
		"skin_value": return Formulas.skin_value(int(a[0]), a[1])
		"era_monster_mult": return Formulas.era_monster_mult(int(a[0]))
		"era_reward_mult": return Formulas.era_reward_mult(int(a[0]))
		"rank_essence_cost": return Formulas.rank_essence_cost(int(a[0]))
		"rank_gold_cost": return Formulas.rank_gold_cost(int(a[0]), int(a[1]))
		"push_regen": return Formulas.push_regen(float(a[0]), float(a[1]))
		"push_spend": return Formulas.push_spend(float(a[0]), float(a[1]))
		"round_nice": return Formulas.round_nice(float(a[0]))
		"rhalf": return Formulas.rhalf(float(a[0]))
		"condition_odds": return Formulas.condition_odds(float(a[0]), float(a[1]))
		"relic_pity_mean_openings": return Formulas.relic_pity_mean_openings()
		"relic_pity_effective_rate": return Formulas.relic_pity_effective_rate()
		"effective_rarity_pct": return Formulas.effective_rarity_pct()
		"raw_value": return Formulas.raw_value(int(a[0]), float(a[1]))
		"set_value": return Formulas.set_value(float(a[0]), int(a[1]))
		"dr_k": return Formulas.dr_k(float(a[0]))
		"hero_hp": return Formulas.hero_hp(float(a[0]), int(a[1]), float(a[2]), float(a[3]))
		"hero_ap": return Formulas.hero_ap(float(a[0]), float(a[1]))
		"hero_acc": return Formulas.hero_acc(int(a[0]), float(a[1]), float(a[2]))
		"hero_eva": return Formulas.hero_eva(int(a[0]), float(a[1]), float(a[2]))
		"max_hit": return Formulas.max_hit(float(a[0]), float(a[1]), float(a[2]))
		"overlevel_xp_mult": return Formulas.overlevel_xp_mult(int(a[0]), int(a[1]))
		"effective_haste_pct": return Formulas.effective_haste_pct(float(a[0]))
		"hero_stats": return SimFx.hero(DataRegistry, a[0], int(a[1]), int(a[2]))
		"fight":
			var h := SimFx.hero(DataRegistry, a[0], int(a[1]), int(a[2]))
			return Formulas.fight_estimate(h, DataRegistry.get_def("monsters", a[3]), float(a[4]))
	return null


## Confronto ricorsivo: numeri con tolleranza assoluta (tol) o relativa (tol_rel), "inf" come stringa.
func _match(got: Variant, expv: Variant, tol: float, tol_rel: float, path: String, out: Array) -> void:
	if expv is Dictionary:
		if not (got is Dictionary):
			out.append("%s: atteso dizionario, ottenuto %s" % [path, str(got)])
			return
		for k in expv:
			if not got.has(k):
				out.append("%s.%s: manca" % [path, k])
			else:
				_match(got[k], expv[k], tol, tol_rel, path + "." + str(k), out)
		if got.size() != expv.size():
			out.append("%s: %d chiavi invece di %d" % [path, got.size(), expv.size()])
	elif expv is Array:
		if not (got is Array) or got.size() != expv.size():
			out.append("%s: atteso array di %d" % [path, expv.size()])
			return
		for i in expv.size():
			_match(got[i], expv[i], tol, tol_rel, "%s[%d]" % [path, i], out)
	elif expv is String:
		if expv == "inf":
			if not (got is float and is_inf(got) and got > 0):
				out.append("%s: atteso inf, ottenuto %s" % [path, str(got)])
		elif str(got) != expv:
			out.append("%s: atteso %s, ottenuto %s" % [path, expv, str(got)])
	elif expv is float or expv is int:
		if not (got is float or got is int):
			out.append("%s: atteso numero, ottenuto %s" % [path, str(got)])
			return
		var e := float(expv)
		var g := float(got)
		var allowed := maxf(tol, tol_rel * absf(e)) + 1e-12 * maxf(1.0, absf(e))
		if absf(g - e) > allowed:
			out.append("%s: atteso %s, ottenuto %s (tolleranza %s)" % [path, str(expv), str(got), str(allowed)])
	elif expv is bool or expv == null:
		if got != expv:
			out.append("%s: atteso %s, ottenuto %s" % [path, str(expv), str(got)])


func test_forma_del_file() -> void:
	assert_gt(_cases.size(), 208, "i casi devono essere più dei 208 originali (T-P2)")
	for c in _cases:
		assert_true(c.has("fn") and c.has("args") and c.has("expected") and c.has("tol"), "caso malformato")


func test_ogni_funzione_e_coperta() -> void:
	var missing := {}
	for c in _cases:
		if _call(c.fn, c.args) == null:
			missing[c.fn] = true
	assert_eq(missing.keys(), [], "funzioni del riferimento non portate in Formulas.gd")


func test_tutti_i_casi_di_riferimento() -> void:
	var fails: Array = []
	var by_fn := {}
	for c in _cases:
		var got: Variant = _call(c.fn, c.args)
		var out: Array = []
		_match(got, c.expected, float(c.tol), float(c.get("tol_rel", 0.0)), "%s%s" % [c.fn, str(c.args)], out)
		by_fn[c.fn] = int(by_fn.get(c.fn, 0)) + 1
		if not out.is_empty():
			fails.append_array(out)
	assert_eq(fails.size(), 0, "casi diversi da Python: %d\n%s" % [fails.size(), "\n".join(PackedStringArray(fails.slice(0, 30)))])
	assert_eq(by_fn.size(), 48, "funzioni distinte nel riferimento (aggiornare se ne aggiungete)")
	gut.p("Casi di riferimento verificati: %d (%d funzioni)" % [_cases.size(), by_fn.size()])


func test_valori_enormi_hanno_tolleranza_relativa() -> void:
	var n := 0
	for c in _cases:
		if c.get("oltre_2_alla_53", false):
			n += 1
			assert_true(c.has("tol_rel"), "un valore oltre 2^53 deve avere tol_rel")
	assert_gt(n, 0, "ci devono essere casi oltre 2^53")


func test_rhalf_metà_per_eccesso() -> void:
	assert_eq(Formulas.rhalf(2.5), 3)
	assert_eq(Formulas.rhalf(-2.5), -3)
	assert_eq(Formulas.rhalf(0.49), 0)
	assert_almost_eq(Formulas.rdec(0.12345, 4), 0.1235, 1e-12)


## FIX-COMBATTIMENTO (QA4 #12): NaN, infiniti e interi enormi non producono più numeri negativi o NaN silenziosi.
func test_casi_limite_nan_inf_overflow() -> void:
	var c: Dictionary = Formulas.k().combat
	assert_eq(Formulas.rhalf(NAN), 0, "NaN -> 0")
	assert_eq(Formulas.rhalf(INF), Formulas.INT_LIMIT)
	assert_eq(Formulas.rhalf(-INF), -Formulas.INT_LIMIT)
	assert_eq(Formulas.rhalf(1e19), Formulas.INT_LIMIT, "oltre 2^62 satura, mai negativo")
	assert_eq(Formulas.round_nice(NAN), 1)
	assert_eq(Formulas.round_nice(1e25), Formulas.INT_LIMIT)
	assert_gt(Formulas.xp_to_next(1000), 0)
	assert_gt(int(Formulas.monster_stats(100000).hp), 0)
	assert_gt(Formulas.food_heal(1000), 0)
	assert_almost_eq(Formulas.hit_chance(NAN, 10.0), float(c.hit_min), 1e-12)
	assert_almost_eq(Formulas.hit_chance(10.0, NAN), float(c.hit_min), 1e-12)
	assert_almost_eq(Formulas.hit_chance(INF, INF), float(c.hit_min), 1e-12)
	assert_almost_eq(Formulas.hit_chance(-10.0, 10.0), float(c.hit_min), 1e-12)
	assert_almost_eq(Formulas.damage_reduction(NAN, 100.0), 0.0, 1e-12)
	assert_almost_eq(Formulas.damage_reduction(INF, 100.0), float(c.dr_cap), 1e-12)
	assert_almost_eq(Formulas.damage_reduction(100.0, 1e6), 0.0, 1e-12, "divisione per un K infinito")
	assert_almost_eq(Formulas.triangle_mult("", ""), 1.0, 1e-12, "stile vuoto: nessun vantaggio")
	assert_almost_eq(Formulas.triangle_mult("melee", ""), 1.0, 1e-12)
	assert_true(is_inf(Formulas.era_monster_mult(2400)))


func test_costanti_dai_dati_hanno_precedenza() -> void:
	# un valore in constants.json deve vincere su PENDING_CONSTANTS
	var k := DataRegistry.constants.duplicate(true)
	k["stars"]["stardust_base"] = 99
	Formulas.configure(k)
	assert_eq(Formulas.stardust_for_star(1), 99)
	Formulas.configure(DataRegistry.constants, DataRegistry._formula_extras())
	assert_eq(Formulas.stardust_for_star(1), 10)
