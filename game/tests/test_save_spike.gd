extends GutTest
## Regressione dello spike S2 (docs/17 §10 R-SAV-7/8): nessuna perdita nel round-trip del salvataggio.

const Spike := preload("res://scripts/save_spike.gd")


func test_u64_stringhe_round_trip() -> void:
	for s in [Spike.MAX_U64_STR, "0", "1", "9223372036854775807", "9223372036854775808", "12345678901234567890"]:
		assert_eq(Spike.u64_to_string(Spike.parse_u64(s)), s, "u64 " + s)
	assert_eq(Spike.parse_u64(Spike.MAX_U64_STR), -1, "2^64-1 = tutti i bit accesi")


func test_round_trip_20000_istanze_senza_perdite() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var original := Spike.build_state(rng)
	var t := {}
	assert_true(Spike.save_atomic(original, t), "scrittura atomica")
	var loaded = Spike.load_slot(t)
	assert_true(loaded is Dictionary, "rilettura")
	assert_true(Spike.normalize(loaded), "normalizzazione tipi")
	var expect := original.duplicate(true)
	expect["stats"]["gold_earned"] = int(loaded["stats"]["gold_earned"])   # numero > 2^53: perdita nota, per questo si usano stringhe
	var out := []
	Spike.diff(expect, loaded, "", out)
	assert_eq(out, [], "nessuna differenza")
	assert_eq(loaded["estate"]["coins"], Spike.BIG_GOLD_STR, "intero oltre int64 come stringa")
	assert_ne(loaded["stats"]["gold_earned"], Spike.TWO53_PLUS_1, "un intero > 2^53 salvato come numero PERDE precisione")
	DirAccess.remove_absolute(Spike.SLOT)
	DirAccess.remove_absolute(Spike.SLOT + ".bak1")
