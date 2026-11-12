extends GutTest
## SnapshotCache (resoconto 50, E47-6): lo snapshot incrementale delle liste grandi è identico alla copia profonda,
## riusa i pezzi invariati, vede ogni modifica (campo, aggiunta, rimozione) e non condivide memoria con lo stato vivo.

const N := 6000


func _data(n: int = N) -> Dictionary:
	var inst: Array = []
	for i in n:
		inst.append({"uid": "i_%06d" % i, "def": "skin_%d" % (i % 40), "float": float(i % 997) / 997.0, "locked": i % 7 == 0,
			"sockets": [i % 3], "seed": i % 1000})
	return {"bank": {"stacks": {"log_pine": 5, "gold": 100.0}, "instances": inst, "slots_bought": 3},
		"stats": {"playtime_s": 12.5}, "schema_version": 1, "rng": {"seed": "123"}, "tags": [1, 2, 3]}


func test_identico_alla_copia_profonda() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	var s := sc.snapshot(d)
	assert_eq(s, d.duplicate(true), "stesso contenuto della copia profonda")
	assert_eq(sc.reused, 0, "al primo snapshot niente da riusare")
	assert_gt(sc.rebuilt, 0)
	assert_false(is_same(s.bank.instances, d.bank.instances), "copia, non riferimento")
	assert_false(is_same(s.bank.instances[0], d.bank.instances[0]), "anche le istanze sono copie")


func test_senza_modifiche_riusa_tutti_i_pezzi() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	var s1 := sc.snapshot(d)
	var s2 := sc.snapshot(d)
	assert_eq(sc.rebuilt, 0, "nessun pezzo rifatto")
	assert_gt(sc.reused, 0)
	assert_eq(s2, s1)
	assert_true(is_same(s1.bank.instances[10], s2.bank.instances[10]), "le copie invariate sono condivise (sola lettura)")


func test_modifica_di_un_campo_in_un_solo_pezzo() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	var s1 := sc.snapshot(d)
	d.bank.instances[3000]["locked"] = true
	d.bank.instances[3000]["sockets"].append(9)
	var s2 := sc.snapshot(d)
	assert_eq(sc.rebuilt, 1, "solo il pezzo toccato")
	assert_eq(s2, d.duplicate(true))
	assert_ne(s1.bank.instances[3000], s2.bank.instances[3000], "lo snapshot precedente non cambia")
	assert_eq(s1.bank.instances[3000].sockets.size(), 1, "i vecchi snapshot sono intatti")


func test_aggiunta_e_rimozione() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	sc.snapshot(d)
	d.bank.instances.append({"uid": "i_new", "def": "x", "float": 0.5, "locked": false, "sockets": [], "seed": 1})
	assert_eq(sc.snapshot(d), d.duplicate(true), "aggiunta in coda")
	assert_eq(sc.rebuilt, 1, "solo l'ultimo pezzo")
	d.bank.instances.remove_at(100)       # sposta tutti gli elementi seguenti: deve restare corretto
	var s := sc.snapshot(d)
	assert_eq(s, d.duplicate(true), "rimozione in mezzo")
	assert_eq(s.bank.instances.size(), N)
	d.bank.instances.clear()
	assert_eq(sc.snapshot(d).bank.instances.size(), 0, "lista svuotata")


func test_stato_vivo_modificato_dopo_lo_snapshot_non_lo_cambia() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	var s := sc.snapshot(d)
	var before: Dictionary = (s.bank.instances[5] as Dictionary).duplicate(true)
	d.bank.instances[5]["float"] = 0.99
	d.bank.stacks["log_pine"] = 77
	assert_eq(s.bank.instances[5], before)
	assert_eq(int(s.bank.stacks.log_pine), 5)


func test_full_rifa_tutto_e_reset() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	sc.snapshot(d)
	sc.snapshot(d, true)
	assert_eq(sc.reused, 0, "full = tutto da zero")
	sc.reset()
	sc.snapshot(d)
	assert_eq(sc.reused, 0, "dopo reset niente da riusare")


func test_completo_ogni_full_every() -> void:
	var d := _data()
	var sc := SnapshotCache.new()
	for i in SnapshotCache.FULL_EVERY - 1:
		sc.snapshot(d)
	sc.snapshot(d)
	assert_eq(sc.reused, 0, "ogni %d snapshot uno completo" % SnapshotCache.FULL_EVERY)


func test_liste_piccole_e_scalari_passano_invariati() -> void:
	var d := _data(100)
	var sc := SnapshotCache.new()
	var s := sc.snapshot(d)
	assert_eq(s, d)
	assert_eq(sc.rebuilt + sc.reused, 0, "sotto la soglia nessun pezzo")
	assert_eq(int(s.schema_version), 1)


func test_perf_costo_incrementale_minore_della_copia_profonda() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var d := _data(20000)
	var sc := SnapshotCache.new()
	var full: Dictionary = {}
	var s: Dictionary = {}
	var t_full := INF
	var t_inc := INF
	sc.snapshot(d)
	for k in 3:          # migliore di 3 per entrambe: il rapporto resta confrontabile e il rumore si cancella
		var t0 := PerfGate.clock_usec()
		full = d.duplicate(true)
		t_full = minf(t_full, float(PerfGate.clock_usec() - t0) / 1000.0)
		t0 = PerfGate.clock_usec()
		s = sc.snapshot(d)
		t_inc = minf(t_inc, float(PerfGate.clock_usec() - t0) / 1000.0)
	gut.p("20.000 istanze: copia profonda %.1f ms, snapshot incrementale %.1f ms" % [t_full, t_inc])
	assert_eq(s.bank.instances.size(), full.bank.instances.size())
	assert_lt(t_inc, t_full * 0.6, "l'incrementale costa molto meno")
