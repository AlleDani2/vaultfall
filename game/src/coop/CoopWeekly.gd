class_name CoopWeekly
extends RefCounted
## Seme settimanale condiviso (COOP-1): la settimana ISO in UTC decide, in modo deterministico, la «Breccia della
## settimana» (affissi, stile dei piani, meccaniche del Guardiano, nome). Stessa settimana = stessa Breccia su ogni PC,
## qualunque sia il fuso o l'orologio locale: l'unico ingresso è l'istante UNIX (UTC), mai la data locale.
## Nessuna rete, nessuna telemetria. Funzioni pure, testabili senza partita.

const DAY_S := 86400
const WEEK_S := 7 * 86400


## Giorni interi dall'epoca UNIX (UTC), anche per istanti negativi.
static func day_of(unix: int) -> int:
	return int(floor(float(unix) / float(DAY_S)))


## Settimana ISO 8601 dell'istante UNIX in UTC: {"year","week","id": "2026-W43","start": unix del lunedì 00:00 UTC, "end"}.
static func week_of(unix: int) -> Dictionary:
	var d := day_of(unix)
	var wd := posmod(d + 3, 7)                 # 0 = lunedì (il 1970-01-01 era un giovedì)
	var thursday := d - wd + 3                 # il giovedì decide l'anno ISO
	var tdt := Time.get_datetime_dict_from_unix_time(thursday * DAY_S)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": int(tdt.year), "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var yday := thursday - day_of(jan1)
	var wk := int(floor(float(yday) / 7.0)) + 1
	var start := (d - wd) * DAY_S
	return {"year": int(tdt.year), "week": wk, "id": "%04d-W%02d" % [int(tdt.year), wk], "start": start, "end": start + WEEK_S}


## Seme intero a 32 bit della settimana (FNV-1a sull'id): uguale su ogni piattaforma.
static func seed_of(week_id: String) -> int:
	return CoopCodec.checksum("vaultfall-week|" + week_id).hex_to_int()


## Definizione della Breccia della settimana: copia di `base_rift` (data/rift.json) con affissi, ritmo e Guardiano decisi
## dal seme. I numeri (intervalli, liste) vengono da coop_rules.weekly. Stessi argomenti = stesso risultato, sempre.
static func rift_def_for(week_id: String, base_rift: Dictionary, data: Object) -> Dictionary:
	var wk: Dictionary = data.rules("coop_rules").weekly
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of(week_id)
	var d: Dictionary = base_rift.duplicate(true)
	# affissi: un sottoinsieme (mischiato) di quelli della Breccia, ognuno con un piano d'inizio deciso dal seme
	var pool: Array = (base_rift.get("affixes", []) as Array).duplicate(true)
	_shuffle(pool, rng)
	var n := clampi(rng.randi_range(int(wk.affix_count[0]), int(wk.affix_count[1])), 1, pool.size())
	var affixes: Array = []
	for i in n:
		var af: Dictionary = pool[i]
		af["from_floor"] = rng.randi_range(int(wk.affix_from_floor[0]), int(wk.affix_from_floor[1]))
		affixes.append(af)
	affixes.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x.from_floor) < int(y.from_floor) or (int(x.from_floor) == int(y.from_floor) and str(x.id) < str(y.id)))
	d["affixes"] = affixes
	# ritmo di crescita dei piani e stili a rotazione
	var jit := float(wk.mult_per_floor_jitter)
	d["stat_mult_per_floor"] = float(base_rift.stat_mult_per_floor) + rng.randf_range(-jit, jit)
	var styles: Array = (base_rift.styles_cycle as Array).duplicate()
	_shuffle(styles, rng)
	d["styles_cycle"] = styles
	# Guardiano: le sue meccaniche di base più qualche extra dalla lista dei dati (solo id esistenti)
	var mechs: Array = (base_rift.guardian_mechanics as Array).duplicate()
	var extra_pool: Array = []
	for m in wk.guardian_pool:
		if data.get_def("boss_mechanics", str(m)).is_empty() or mechs.has(m):
			continue
		extra_pool.append(str(m))
	_shuffle(extra_pool, rng)
	var ne := mini(rng.randi_range(int(wk.guardian_extra[0]), int(wk.guardian_extra[1])), extra_pool.size())
	for i in ne:
		mechs.append(extra_pool[i])
	d["guardian_mechanics"] = mechs
	var names: Array = wk.name_pool
	d["weekly_name"] = names[rng.randi_range(0, names.size() - 1)] if not names.is_empty() else {}
	d["weekly_id"] = week_id
	return d


## Mescolamento di Fisher-Yates con il generatore dato (dipende solo dal seme).
static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
