extends GutTest
## Ritmo della Tenuta (criterio M6: «prima Rifondazione ~11 h a ×1» di docs/11 §4 e balance_report §7).
## Un giocatore "avido" riproduce il simulatore di bilanciamento col sistema VERO: ricompra sempre il miglior rapporto
## produzione/costo, Dispensa e materiali sempre pieni, Bottega attiva, tier prodotto che sale di 1 ogni 12 h.
## Il test dichiara i numeri (informativo) e vincola solo una forchetta larga; la differenza con il simulatore
## (che ignora l'arrivo dei coloni, 1 ogni 6 minuti) è documentata in docs/audit_2026-10-22/30_RESOCONTO_ESTATE.md.

const STEP := 60.0


func _topup(f: EstateFixtures) -> void:
	for it in ["plank_pine", "plank_birch", "plank_chestnut", "plank_cedar", "plank_ebony", "bar_copper", "bar_bronze", "bar_iron", "bar_steel",
			"bar_cobalt", "granite", "padlock_bronze", "padlock_steel"]:
		if f.bank.count(it) < 1000000:
			f.bank.add(it, 1000000)
	f.estate.state.pantry = 1.0e9


func _greedy(f: EstateFixtures, instant_settlers: bool) -> float:
	var e: EstateSystem = f.estate
	var producers := ["sawmill", "mine_shaft", "fishery", "fields", "ranch"]
	f.bank.add_gold(500)
	f.mods.set_source("pacing", [{"key": "estate_auto_collect", "value": 1, "mode": "add"}])    # niente tetto del Magazzino
	var t := 0.0
	var first := -1.0
	while t < 40.0 * 3600.0:
		_topup(f)
		var units := e.total_units_per_hour()
		e._advance(STEP)
		e._finish_advance()
		t += STEP
		# la Bottega del simulatore: vende tutto all'80% del valore dei tronchi del tier, con tetto 0,8 × gph(tier)
		var tier := mini(10, 1 + int(t / 3600.0 / 12.0))
		var log_value := float(DataRegistry.item(["log_pine", "log_birch", "log_chestnut", "log_cedar", "log_ebony", "log_ironwood",
			"log_raventhorn", "log_silverbark", "log_vesperwood", "log_starwood"][tier - 1]).value)
		f.bank.add_gold(int(min(units * log_value * 0.8, float(DataRegistry.constants.estate.shop_income_cap_gph) * Formulas.gph(tier)) * STEP / 3600.0 + 0.5))
		if instant_settlers:
			e.state.settlers = e.settler_cap()
		var bought := true
		var guard := 0
		while bought and guard < 200:
			bought = false
			guard += 1
			if e.level_of("cottage") == 0:
				bought = e.upgrade("cottage")
				if instant_settlers:
					e.state.settlers = e.settler_cap()
				continue
			if e.settlers_free() < 1 and e.level_of("cottage") > 0 and e.settlers() >= e.settler_cap():
				if e.upgrade("cottage"):
					bought = true
				continue
			if e.settlers_free() < 1:
				break
			var best := ""
			var best_r := -1.0
			for p in producers:
				if not e.is_unlocked(p):
					continue
				var l: int = e.level_of(p)
				var gain: float = Formulas.estate_units_per_hour(l + 1) - Formulas.estate_units_per_hour(l)
				var c: int = int(e.cost_of(p).gold)
				var r := gain / float(maxi(1, c))
				if r > best_r:
					best_r = r
					best = p
			if best != "" and e.upgrade(best):
				bought = true
		if first < 0.0 and e.state.prosperity >= float(e.prestige_min_units()):
			first = t / 3600.0
			break
		# il tier del giocatore sale di 1 ogni 12 h (come nel simulatore)
	return first


func test_prima_rifondazione_ritmo() -> void:
	var f := EstateFixtures.make(3)
	autofree(f.events)
	f.skills.state["woodcutting"]["level"] = 1
	var instant := _greedy(f, true)
	var f2 := EstateFixtures.make(3)
	autofree(f2.events)
	var real := _greedy(f2, false)
	gut.p("Prima Rifondazione: coloni istantanei (come nel simulatore) %.1f h · arrivo reale (arrival_min dei dati) %.1f h" % [instant, real])
	assert_gt(instant, 0.0, "raggiunta")
	assert_between(instant, 4.0, 30.0, "forchetta larga attorno alle ~11-14 h del simulatore")
	assert_gt(real, 0.0, "raggiunta anche con l'arrivo reale dei coloni")
	assert_lte(real, 15.0, "audit 42: la prima Rifondazione col sistema vero resta entro il tetto di 15 h (docs/11 §4)")
