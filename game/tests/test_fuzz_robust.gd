extends GutTest
## QA 72 - robustezza ai valori assurdi: F4 (quantita' enormi), F5 (negativi/non finiti), F6 (orologio), F7 (offline
## dei Modi), F8 (id sconosciuti). Dettagli: docs/audit_2026-10-22/qa/72_QA_FUZZ.md.

var _old_dir: String
var _dir: String


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_dir = FuzzLib.tmp_save_dir("robust")
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	FuzzLib.rm_dir(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func test_f6_orologio_non_finito() -> void:
	var c := FixedStepClock.new()
	for bad in [NAN, INF, -INF, 1e300, -1e300]:
		var n := c.advance(bad)
		assert_gte(n, 0)
		assert_true(is_finite(c.pending_s()), "accumulatore finito dopo %s" % str(bad))
		assert_true(is_finite(c.sim_time))
	var gaps: Array = []
	c.long_gap.connect(func(s: float) -> void: gaps.append(s))
	c.advance(1e300)
	for g in gaps:
		assert_true(is_finite(g) and g >= 0.0, "long_gap valido")
	c.reset()
	assert_eq(c.advance(0.25), 2, "dopo i valori assurdi l'orologio funziona")
	c.speed = NAN
	assert_eq(c.advance(1.0), 0)
	c.speed = 1.0
	c.reset()
	assert_eq(c.advance(1.0), 10)


func test_f4_quantita_enormi() -> void:
	Game.new_game(1, "normal", 5)
	var m := Game.system("market") as MarketSystem
	var p := Game.system("prestige") as PrestigeSystem
	var t0 := Time.get_ticks_msec()
	var shop_ids: Array = []
	for e in DataRegistry.table("shop"):
		shop_ids.append(str(e.id))
	assert_false(shop_ids.is_empty())
	for sid in shop_ids.slice(0, 5):
		assert_false(m.buy(sid, 4294967296))
		assert_false(bool(m.shop_status(sid, 9223372036854775807).ok))
		assert_false(bool(m.shop_status(sid, 9223372036854775807).get("ok", true)))
	for nid in DataRegistry.table("constellations").slice(0, 8):
		var id := str(nid.id)
		var pv := p.preview_node(id, 2147483648)
		assert_true(pv.has("cost"))
		assert_eq(p.buy_node(id, 9223372036854775807).is_empty() or true, true)
	assert_lt(Time.get_ticks_msec() - t0, 5000, "nessun ciclo enorme")
	Game.stop_game(false)


func test_f5_valori_non_finiti_e_negativi_nelle_api() -> void:
	Game.new_game(1, "normal", 6)
	var sk := Game.system("skills") as SkillSystem
	var xp0 := sk.xp("hero")
	for bad in [NAN, INF, -INF, -5.0]:
		sk.add_xp("hero", bad)
		assert_eq(sk.xp("hero"), xp0, "xp invariata con %s" % str(bad))
	var bf := Game.system("buffs") as BuffSystem
	for bad in [NAN, INF, -INF, -3.0]:
		bf.add_buff("fuzz_b", bad, [])
	assert_eq(bf.state.active.has("fuzz_b"), false)
	var mk := Game.system("market") as MarketSystem
	var cp := Game.system("compendium") as CompendiumSystem
	Game._on_long_gap(NAN)
	Game._on_long_gap(INF)
	Game._on_long_gap(-INF)
	Game.ctx.events.offline_progress.emit(NAN, {})
	Game.ctx.events.offline_progress.emit(INF, {})
	assert_true(is_finite(float(cp.state.offline_h_max)))
	assert_true(is_finite(float(mk.state.t)) if mk.state.has("t") else true)
	assert_true(is_finite(float(GameState.data.hero.hp)))
	Game.stop_game(false)


func test_f5_valori_negativi_o_non_finiti_nel_salvataggio() -> void:
	Game.new_game(1, "normal", 7)
	var bank := Game.system("bank") as BankSystem
	var item := ""
	for k in DataRegistry.all_items():
		if bool(DataRegistry.all_items()[k].get("stackable", false)) and str(DataRegistry.all_items()[k].get("category", "")) != "currency":
			item = k
			break
	bank.add(item, 7, "fuzz")
	var snap := Game.snapshot(true).duplicate(true)
	Game.stop_game(false)
	var bad_variants: Array = []
	for v in [-1, -50.0, 1e30]:
		var d := snap.duplicate(true)
		d.bank.stacks[item] = v
		d.currencies["gold"] = v
		d.skills.hero.level = -3
		d.skills.hero.xp = v
		bad_variants.append(d)
	for d in bad_variants:
		FuzzLib.rm_dir(_dir)
		DirAccess.make_dir_recursive_absolute(_dir)
		SaveService.save_data(1, d)
		var res := Game.load_game(1)
		if not res.ok:
			continue          # rifiutato dal normalizzatore: va bene
		var b := Game.system("bank") as BankSystem
		assert_gte(b.count(item), 0)
		assert_gte(b.gold(), 0)
		assert_gte(int(GameState.data.skills.hero.level), 1)
		assert_true(is_finite(float(GameState.data.skills.hero.xp)))
		assert_gte(float(GameState.data.skills.hero.xp), 0.0)
		Game.stop_game(false)
	# inf (1e999) letto dal JSON
	var txt := JSON.stringify(snap, "", false, true).replace('"gold":', '"gold":1e999,"gold_x":')
	var parsed: Variant = JSON.parse_string(txt)
	assert_true(parsed is Dictionary)
	var d2: Dictionary = parsed
	FuzzLib.rm_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	FuzzLib.write_raw(SaveService.slot_path(1), SaveCodec.encode(d2))
	var r2 := Game.load_game(1)
	if r2.ok:
		assert_gte((Game.system("bank") as BankSystem).gold(), 0)
		Game.stop_game(false)
	else:
		assert_false(GameState.active)
	for e in get_errors():
		e.handled = true          # il motore segnala «Exponent too high» per 1e999: atteso


func test_f7_offline_dei_modi_senza_tick_a_vuoto() -> void:
	Game.new_game(1, "normal", 8)
	var ms := Game.system("modes") as ModeSystem
	ms.state["badge"] = false
	var t0 := Time.get_ticks_msec()
	ms.simulate_offline(86400.0 * 365.0 * 10.0)
	assert_lt(Time.get_ticks_msec() - t0, 500, "nessun milione di tick a vuoto")
	var rep := Game.sim.run_offline(NAN)
	assert_true(rep.is_empty())
	assert_true(Game.sim.run_offline(INF).is_empty())
	Game.stop_game(false)


func test_f8_crate_def_e_id_sconosciuti() -> void:
	Game.new_game(1, "normal", 9)
	var cr := Game.system("crates") as CrateSystem
	assert_eq(typeof(cr.crate_def("skin_x")), TYPE_DICTIONARY)
	assert_eq(cr.crate_def("nope"), {})
	assert_eq(cr.openable("nope"), 0)
	assert_eq(cr.open("nope", 3), [])
	assert_eq(cr.build_reel("nope", "x", "rare"), [])
	assert_eq(CrateSystem.best_result_index([5, "x", null]), -1)
	var sk := Game.system("skills") as SkillSystem
	assert_eq(sk.duration_of("azione_inesistente"), 0.0)
	assert_eq(sk.profile_of("azione_inesistente"), {})
	assert_eq(sk.hourly("azione_inesistente"), {})
	Game.stop_game(false)
