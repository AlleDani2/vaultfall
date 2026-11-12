extends GutTest
## T-1.4: determinismo e salvataggio dei flussi RNG (seed/state uint64 come stringhe, R-SAV-7).


func _seq(r: RngStreams, stream_name: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(r.stream(stream_name).randi())
	return out


func test_stesso_seed_stesse_sequenze() -> void:
	var a := RngStreams.new(123456789)
	var b := RngStreams.new(123456789)
	for s in RngStreams.STREAMS:
		assert_eq(_seq(a, s, 50), _seq(b, s, 50), "flusso " + s)


func test_seed_diversi_e_flussi_indipendenti() -> void:
	var a := RngStreams.new(1)
	var b := RngStreams.new(2)
	assert_ne(_seq(a, "loot", 10), _seq(b, "loot", 10), "seed diversi -> sequenze diverse")
	var c := RngStreams.new(7)
	assert_ne(_seq(c, "loot", 10), _seq(c, "crates", 10), "flussi diversi -> sequenze diverse")
	# consumare "crates" non cambia "loot"
	var x := RngStreams.new(99)
	var y := RngStreams.new(99)
	_seq(x, "crates", 1000)
	assert_eq(_seq(x, "loot", 20), _seq(y, "loot", 20), "loot indipendente da crates")


func test_stato_salvato_come_stringhe_e_ripreso() -> void:
	var a := RngStreams.new(-5)             # seed con il bit alto acceso
	_seq(a, "combat", 37)
	var st := a.to_state()
	for s in RngStreams.STREAMS:
		assert_true(st[s].seed is String and st[s].state is String, "stringhe per " + s)
		assert_true(RngStreams.is_u64_string(st[s].state), "uint64 valido")
	# passa per JSON come farebbe il salvataggio
	var back: Dictionary = JSON.parse_string(JSON.stringify(st))
	var b := RngStreams.new(0)
	assert_true(b.from_state(back))
	for s in RngStreams.STREAMS:
		assert_eq(_seq(b, s, 25), _seq(a, s, 25), "continua identico: " + s)
	assert_eq(b.master_seed, a.master_seed)


func test_from_state_rifiuta_dati_non_validi() -> void:
	var a := RngStreams.new(42)
	var before := a.to_state()
	var bad := before.duplicate(true)
	bad["loot"]["state"] = 12345.0          # numero invece di stringa
	assert_false(a.from_state(bad))
	bad = before.duplicate(true)
	bad["world"]["seed"] = "18446744073709551616"   # 2^64: fuori intervallo
	assert_false(a.from_state(bad))
	assert_false(a.from_state({}))
	assert_eq(a.to_state(), before, "flussi invariati dopo un rifiuto")


func test_u64_limiti() -> void:
	for s in ["0", "1", "9223372036854775807", "9223372036854775808", "12345678901234567890", RngStreams.U64_MAX_STR]:
		assert_eq(RngStreams.u64_to_string(RngStreams.parse_u64(s)), s, s)
	assert_eq(RngStreams.parse_u64(RngStreams.U64_MAX_STR), -1)
	assert_false(RngStreams.is_u64_string("-1"))
	assert_false(RngStreams.is_u64_string("1e5"))
	assert_false(RngStreams.is_u64_string(""))


func test_weighted_index_e_chance() -> void:
	var r := RngStreams.new(2026)
	var counts := [0, 0, 0]
	for i in 10000:
		counts[r.weighted_index("loot", [70, 25, 5])] += 1
	assert_almost_eq(counts[0] / 10000.0, 0.70, 0.03)
	assert_almost_eq(counts[2] / 10000.0, 0.05, 0.015)
	assert_eq(r.weighted_index("loot", [0, 0]), -1)
	assert_eq(r.weighted_index("loot", [0, 3, 0]), 1)
	assert_false(r.chance("loot", 0.0))
	assert_true(r.chance("loot", 1.0))
	var r2 := RngStreams.new(2026)
	var r3 := RngStreams.new(2026)
	for i in 100:
		assert_eq(r2.weighted_index("crates", [1, 2, 3]), r3.weighted_index("crates", [1, 2, 3]))
