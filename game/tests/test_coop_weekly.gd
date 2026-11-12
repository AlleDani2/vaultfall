extends GutTest
## COOP-1: seme settimanale condiviso (settimana ISO in UTC), Breccia della settimana identica per tutti, punteggio
## confrontabile, codice-risultato e classifica LOCALE degli amici.

const Env := preload("res://tests/helpers/coop_env.gd")
const NOW := 1760000000          # 2025-10-09, giovedì (UTC)


func _unix(y: int, mo: int, d: int, h: int = 0, mi: int = 0, s: int = 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": s}))


func _env(lvl: int, tier: int, cls: String, created: int) -> Object:
	var env: Object = Env.make(13, lvl, cls, tier, created)
	env.state.unlocks.append("feature:rift")
	return env


func after_each() -> void:
	Env.free_all()


func test_settimana_iso_in_utc() -> void:
	var cases := [
		[_unix(2026, 10, 23, 12), "2026-W43"],
		[_unix(2026, 10, 19, 0, 0, 0), "2026-W43"],
		[_unix(2026, 10, 18, 23, 59, 59), "2026-W42"],
		[_unix(2021, 1, 3), "2020-W53"],
		[_unix(2024, 12, 30), "2025-W01"],
		[_unix(2026, 1, 1), "2026-W01"],
		[_unix(2016, 1, 1), "2015-W53"],
		[_unix(2025, 12, 28, 23, 59, 59), "2025-W52"],
		[_unix(2025, 12, 29), "2026-W01"],
	]
	for c in cases:
		assert_eq(CoopWeekly.week_of(int(c[0])).id, c[1], "unix %d" % int(c[0]))
	var w := CoopWeekly.week_of(_unix(2026, 10, 23, 12))
	assert_eq(int(w.start), _unix(2026, 10, 19))
	assert_eq(int(w.end), _unix(2026, 10, 26))


func test_due_istanze_con_orologi_locali_diversi_hanno_la_stessa_breccia() -> void:
	var rift: Dictionary = DataRegistry.table("rift")[0]
	# lo STESSO istante UTC visto da due PC: Tokyo (UTC+9) e Los Angeles (UTC-8)
	var instant := _unix(2026, 10, 19, 1, 30)            # lunedì 01:30 UTC
	var tokyo_local := instant + 9 * 3600
	var la_local := instant - 8 * 3600
	var tz_tokyo := 9 * 3600
	var tz_la := -8 * 3600
	# ogni PC deve riportare il suo orologio locale a UTC: l'ingresso del seme è sempre UTC
	var a := CoopWeekly.week_of(tokyo_local - tz_tokyo)
	var b := CoopWeekly.week_of(la_local - tz_la)
	assert_eq(a.id, b.id)
	var da := CoopWeekly.rift_def_for(str(a.id), rift, DataRegistry)
	var db := CoopWeekly.rift_def_for(str(b.id), rift, DataRegistry)
	assert_eq(JSON.stringify(da, "", true, true), JSON.stringify(db, "", true, true), "stessa Breccia, bit per bit")
	# il confine: un secondo prima del lunedì UTC è la settimana scorsa per tutti, anche se a Tokyo è già lunedì mattina
	var before := _unix(2026, 10, 18, 23, 59, 59)
	assert_eq(CoopWeekly.week_of(before).id, "2026-W42")
	assert_eq(CoopWeekly.week_of(before + 1).id, "2026-W43")
	assert_ne(CoopWeekly.seed_of("2026-W42"), CoopWeekly.seed_of("2026-W43"))


func test_la_breccia_della_settimana_e_deterministica_e_varia() -> void:
	var rift: Dictionary = DataRegistry.table("rift")[0]
	var wk: Dictionary = DataRegistry.rules("coop_rules").weekly
	var seen: Dictionary = {}
	for w in range(1, 40):
		var id := "2026-W%02d" % w
		var d1 := CoopWeekly.rift_def_for(id, rift, DataRegistry)
		var d2 := CoopWeekly.rift_def_for(id, rift, DataRegistry)
		assert_eq(JSON.stringify(d1, "", true, true), JSON.stringify(d2, "", true, true), "stesso seme, stessa Breccia")
		seen[JSON.stringify([d1.affixes, d1.styles_cycle, d1.guardian_mechanics])] = true
		var n: int = (d1.affixes as Array).size()
		assert_between(n, int(wk.affix_count[0]), mini(int(wk.affix_count[1]), (rift.affixes as Array).size()))
		for af in d1.affixes:
			assert_between(int(af.from_floor), int(wk.affix_from_floor[0]), int(wk.affix_from_floor[1]))
		for m in d1.guardian_mechanics:
			assert_false(DataRegistry.get_def("boss_mechanics", str(m)).is_empty(), "meccanica esistente")
		assert_almost_eq(float(d1.stat_mult_per_floor), float(rift.stat_mult_per_floor), float(wk.mult_per_floor_jitter) + 1e-9)
		assert_eq((d1.styles_cycle as Array).size(), (rift.styles_cycle as Array).size())
		assert_eq(d1.weekly_id, id)
		assert_false((d1.weekly_name as Dictionary).is_empty())
	assert_gt(seen.size(), 20, "settimane diverse, Breccie diverse")
	assert_eq(DataRegistry.table("rift")[0].affixes.size(), 5, "la Breccia dei dati non viene toccata")


func test_prova_della_settimana_riproducibile_e_senza_compagni() -> void:
	var env: Object = _env(60, 6, "warrior", 1700000001)
	var r1: Dictionary = env.coop.weekly_run(NOW)
	var r2: Dictionary = env.coop.weekly_run(NOW)
	assert_false(r1.is_empty())
	assert_eq(r1.floor, r2.floor)
	assert_eq(r1.t, r2.t)
	assert_eq(r1.dmg, r2.dmg)
	assert_eq(r1.week, CoopWeekly.week_of(NOW).id)
	assert_gte(int(r1.floor), 1)
	assert_true(env.combat.eg.rift_override.is_empty(), "la Breccia dei dati torna com'era")
	assert_false(env.coop.suspended)
	assert_eq(env.combat.eg.rift_def().id, "the_rift")
	# con un compagno attivo il punteggio della prova non cambia (solo l'Eroe conta)
	var friend: Object = _env(100, 9, "warrior", 1700000002)
	assert_true(friend.share_to(env, NOW).ok)
	var r3: Dictionary = env.coop.weekly_run(NOW)
	assert_eq(r3.floor, r1.floor)
	assert_eq(r3.t, r1.t)
	# un Eroe più forte arriva più in alto (o uguale) nella stessa Breccia
	var strong: Object = _env(100, 10, "warrior", 1700000003)
	var rs: Dictionary = strong.coop.weekly_run(NOW)
	print("COOP_PROVA debole piano %d, forte piano %d" % [int(r1.floor), int(rs.floor)])
	assert_gte(int(rs.floor), int(r1.floor))
	assert_true(strong.coop.my_result(str(r1.week)).floor == rs.floor)


func test_codice_risultato_e_classifica_locale() -> void:
	var a: Object = _env(60, 6, "warrior", 1700000011)
	var b: Object = _env(100, 10, "warrior", 1700000012)
	var c: Object = _env(40, 3, "ranger", 1700000013)
	var ra: Dictionary = a.coop.weekly_run(NOW)
	var rb: Dictionary = b.coop.weekly_run(NOW)
	var rc: Dictionary = c.coop.weekly_run(NOW)
	var wk := str(ra.week)
	var code_b: String = b.coop.export_result_code(wk)
	var code_c: String = c.coop.export_result_code(wk)
	assert_true(code_b.begins_with("VFR1."))
	assert_eq(a.coop.import_code(code_b, NOW).status, "result_added")
	assert_eq(a.coop.import_code(code_c, NOW).status, "result_added")
	assert_eq(a.coop.import_code(code_c, NOW).status, "result_same", "doppio incolla: nessun doppione")
	var board: Array = a.coop.leaderboard(wk)
	assert_eq(board.size(), 3)
	for i in range(board.size() - 1):
		assert_false(CoopSystem.better(board[i + 1], board[i]), "ordinata")
		assert_gte(int(board[i].floor), int(board[i + 1].floor), "più piani prima")
	assert_eq(int(board[0].rank), 1)
	var mine := 0
	for r in board:
		mine += 1 if r.me else 0
	assert_eq(mine, 1, "una sola riga è la tua")
	# stesso ordine su un altro PC che incolla gli stessi tre risultati
	var d: Object = _env(50, 5, "arcanist", 1700000014)
	d.coop.import_code(a.coop.export_result_code(wk), NOW)
	d.coop.import_code(code_b, NOW)
	d.coop.import_code(code_c, NOW)
	var names_a: Array = []
	var names_d: Array = []
	for r in a.coop.leaderboard(wk):
		names_a.append(r.uid)
	for r in d.coop.leaderboard(wk):
		names_d.append(r.uid)
	assert_eq(names_a, names_d, "stessa classifica ovunque")
	# il proprio codice non si re-importa; un risultato migliore sostituisce, uno peggiore no
	assert_eq(a.coop.import_code(a.coop.export_result_code(wk), NOW).error, "self")
	var better_b: Dictionary = a.coop.sanitize_result(a.coop.state.results[wk][str(b.coop.my_uid())], NOW).result
	better_b["floor"] = int(better_b.floor) + 3
	assert_eq(a.coop.import_code(CoopCodec.pack("R", 1, better_b), NOW).status, "result_updated")
	var worse_b := better_b.duplicate()
	worse_b["floor"] = 1
	assert_eq(a.coop.import_code(CoopCodec.pack("R", 1, worse_b), NOW).status, "result_older")
	assert_true(ra.floor >= 1 and rb.floor >= 1 and rc.floor >= 1)


func test_risultati_manomessi_si_riportano_ai_limiti_o_si_rifiutano() -> void:
	var a: Object = _env(60, 6, "warrior", 1700000021)
	var wk := str(CoopWeekly.week_of(NOW).id)
	var base := {"uid": "0123456789abcdef", "name": "Furbo", "class": "warrior", "spec": "", "level": 9999, "week": wk,
		"floor": 99999999, "t": -50.0, "dmg": 1.0e99, "issued": NOW}
	var r: Dictionary = a.coop.import_code(CoopCodec.pack("R", 1, base), NOW)
	assert_true(r.ok, str(r))
	assert_gt(int(r.clamped), 0)
	var e: Dictionary = a.coop.state.results[wk]["0123456789abcdef"]
	var cap := int(DataRegistry.rules("coop_rules").weekly.max_floors)
	assert_lte(int(e.floor), cap + 1)
	assert_gte(float(e.t), 0.0)
	assert_lte(float(e.dmg), 1.0e30)
	assert_lte(int(e.level), int(DataRegistry.constants.level_cap))
	var bad := base.duplicate()
	bad["week"] = "2026-W99"
	assert_false(a.coop.import_code(CoopCodec.pack("R", 1, bad), NOW).ok, "settimana inesistente")
	bad["week"] = "settimana"
	assert_false(a.coop.import_code(CoopCodec.pack("R", 1, bad), NOW).ok)
	bad["week"] = "2099-W01"
	assert_eq(a.coop.import_code(CoopCodec.pack("R", 1, bad), NOW).error, "future")
	var evil := base.duplicate()
	evil["items"] = {"sword": 1}
	assert_eq(a.coop.import_code(CoopCodec.pack("R", 1, evil), NOW).error, "forbidden")
	var nouid := base.duplicate()
	nouid.erase("uid")
	assert_false(a.coop.import_code(CoopCodec.pack("R", 1, nouid), NOW).ok)
	# un codice-eroe non è un risultato e viceversa: incollati nel posto giusto funzionano entrambi
	var hero_code: String = a.coop.export_hero_code(NOW)
	assert_eq(a.coop.import_code(hero_code, NOW).error, "self")


func test_storico_limitato_e_gli_amici_per_settimana() -> void:
	var a: Object = _env(60, 6, "warrior", 1700000031)
	var hist := int(DataRegistry.rules("coop_rules").weekly.history_weeks)
	for w in range(1, hist + 6):
		var week := "2026-W%02d" % w
		var entry := {"uid": "00000000000000%02d" % w, "name": "Amico %d" % w, "class": "warrior", "spec": "", "level": 50,
			"week": week, "floor": w, "t": 100.0, "dmg": 1000.0, "issued": _unix(2026, 6, 1)}
		a.coop._store_result(entry, false)
	assert_eq(a.coop.state.results.size(), hist, "solo le ultime settimane")
	assert_false(a.coop.state.results.has("2026-W01"), "la più vecchia è caduta")
	var maxn := int(DataRegistry.rules("coop_rules").weekly.max_entries_per_week)
	for i in maxn + 20:
		var entry := {"uid": "%016x" % (i + 1), "name": "Folla", "class": "warrior", "spec": "", "level": 50,
			"week": "2026-W50", "floor": 1 + i % 7, "t": 10.0 + i, "dmg": 1.0, "issued": _unix(2026, 6, 1)}
		a.coop._store_result(entry, false)
	assert_lte((a.coop.state.results["2026-W50"] as Dictionary).size(), maxn, "tetto di righe per settimana")


func test_partita_cozy_marca_scheda_risultato_e_classifica() -> void:
	var a: Object = _env(60, 6, "warrior", 1700000021)
	var b: Object = _env(60, 6, "warrior", 1700000022)
	assert_false(a.coop.is_cozy(), "partita normale: nessuna marcatura")
	assert_false(bool(a.coop.weekly_run(NOW).cozy))
	# b gioca in Cozy (come fa Game via ModeSystem.set_cozy), poi spegne la Cozy: la marcatura resta
	b.modes.set_cozy(true)
	b.modes.set_cozy(false)
	assert_true(b.modes.run_tags().has("cozy"))
	assert_true(b.coop.is_cozy(), "legge ModeSystem.run_tags(), non una chiave inesistente")
	var rb: Dictionary = b.coop.weekly_run(NOW)
	assert_true(bool(rb.cozy), "il risultato porta la marcatura")
	var sheet: Dictionary = b.coop.build_sheet(NOW)
	assert_true(bool(sheet.cozy), "la scheda porta la marcatura")
	# dall'altra parte: scheda e risultato importati restano marcati, la classifica li mostra
	var wk := str(rb.week)
	a.coop.weekly_run(NOW)
	assert_eq(a.coop.import_code(b.coop.export_result_code(wk), NOW).status, "result_added")
	var cozy_rows := 0
	for r in a.coop.leaderboard(wk):
		if bool(r.get("cozy", false)):
			cozy_rows += 1
			assert_false(bool(r.me))
	assert_eq(cozy_rows, 1, "solo la riga dell'amico Cozy e' marcata")
	assert_eq(a.coop.import_code(b.coop.export_hero_code(NOW), NOW).kind, "H")
	var comps: Array = a.coop.companions()
	assert_eq(comps.size(), 1)
	assert_true(bool(comps[0].sheet.cozy), "la scheda del Compagno importata resta marcata")
