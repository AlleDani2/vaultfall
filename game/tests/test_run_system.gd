extends GutTest
## CORSA (resoconto 91): Corsa a scelte del combattimento in zona (RunSystem + agganci in CombatSystem), tetto della velocità
## d'attacco, rami di talento esclusivi, talenti ritarati.

const Env := preload("res://tests/helpers/combat2_env.gd")


func _env(lvl: int = 30, seed_v: int = 21, zone: String = "millbrook", tier: int = 3) -> Object:
	var run := RunSystem.new()
	var env: Object = Env.make(seed_v, lvl, "warrior", false, [run])
	env.gear("warrior", tier)
	env.food()
	env.unlock_zone(zone)
	env.set_meta("run", run)
	autofree(env.bus)
	return env


func _run(env: Object) -> RunSystem:
	return env.get_meta("run") as RunSystem


func _rules() -> Dictionary:
	return DataRegistry.rules("run_rules")


## Avvia lo scontro e accende la Corsa (un tick del solo RunSystem).
func _start(env: Object, zone: String = "millbrook", mon: String = "mud_slime") -> RunSystem:
	env.combat.start(zone, mon)
	var r := _run(env)
	r.tick(0.1)
	return r


func _kills(r: RunSystem, n: int) -> void:
	for i in n:
		r.on_kill()


func test_dati_ogni_voce_ha_vantaggio_e_compromesso() -> void:
	var r := RunSystem.new()
	var env: Object = Env.make(1, 20, "warrior", false, [r])
	autofree(env.bus)
	var perks: Array = DataRegistry.table("run_perks")
	assert_gte(perks.size(), 24)
	for p in perks:
		var gains := 0
		var costs := 0
		for m in p.modifiers:
			if r.is_gain(m):
				gains += 1
			else:
				costs += 1
		assert_true(gains > 0 and costs > 0, "voce %s con compromesso" % p.id)


func test_offerta_dopo_n_uccisioni_e_scelta_passa_dai_modificatori() -> void:
	var env := _env()
	var r := _start(env)
	assert_true(r.is_active(), "Corsa attiva in zona dal livello di sblocco")
	r.set_mode("ask")
	var kpc := int(_rules().kills_per_choice)
	_kills(r, kpc - 1)
	assert_true(r.offer().is_empty())
	_kills(r, 1)
	assert_eq(r.offer().size(), int(_rules().offers), "offerta di 3 voci")
	var pid := str(r.offer()[0])
	assert_true(r.choose(0))
	assert_eq(r.picks(), [pid])
	assert_true(env.mods.has_source(str(_rules().modifier_source)), "fonte run:perks applicata")
	var key := str(r.perk(pid).modifiers[0].key)
	assert_almost_eq(env.mods.total_add(key), float(r.perk(pid).modifiers[0].value), 1e-6, "valore della voce in Modifiers")


func test_pausa_fuori_dalla_zona_e_ripresa() -> void:
	var env := _env()
	var r := _start(env)
	_kills(r, int(_rules().kills_per_choice))
	r.choose(0)
	env.combat.stop()
	r.tick(0.1)
	assert_false(r.is_active())
	assert_false(env.mods.has_source(str(_rules().modifier_source)), "in pausa la fonte si toglie")
	assert_eq(r.picks().size(), 1, "le voci restano")
	_kills(r, 50)
	assert_true(r.offer().is_empty(), "in pausa le uccisioni non contano")
	env.combat.start("millbrook", "grey_wolf")       # stesso posto, altro mostro: riprende
	r.tick(0.1)
	assert_true(r.is_active())
	assert_eq(r.picks().size(), 1)


func test_cambiare_zona_chiude_la_corsa() -> void:
	var env := _env()
	env.unlock_zone("saltreach")
	var r := _start(env)
	_kills(r, int(_rules().kills_per_choice))
	r.choose(0)
	env.combat.start("saltreach", "")
	r.tick(0.1)
	assert_eq(r.picks().size(), 0, "zona nuova = Corsa nuova")
	assert_eq(str(r.state.zone), "saltreach")
	assert_eq(str((r.state.history as Array)[0].end), "zone")


func test_chiedi_sceglie_da_solo_dopo_l_attesa_e_scegli_per_me_subito() -> void:
	var env := _env()
	var r := _start(env)
	r.set_mode("ask")
	_kills(r, int(_rules().kills_per_choice))
	var expect := str(r.offer()[r.auto_index()])
	var steps := int(ceil(float(_rules().ask_timeout_s) / 0.1)) + 2
	for i in steps:
		r.tick(0.1)
	assert_true(r.offer().is_empty(), "dopo l'attesa la scelta si fa da sola")
	assert_eq(str(r.picks()[0]), expect, "con la priorità")
	r.set_mode("auto")
	_kills(r, int(_rules().kills_per_choice))
	r.tick(0.1)
	assert_eq(r.picks().size(), 2, "Scegli per me: subito")


func test_priorita_famiglie() -> void:
	var env := _env()
	var r := _start(env)
	r.state["order"] = ["defense", "offense", "loot", "technique"]
	r.state["offer"] = ["off_edge", "loot_lesson", "def_guard"]
	assert_eq(r.auto_index(), 2, "la Difesa in testa alla priorità")
	r.move_family("loot", -1)
	r.move_family("loot", -1)
	assert_eq(r.state.order[0], "loot")
	assert_eq(r.auto_index(), 1)


func test_rilancia_ed_escludi_una_volta() -> void:
	var env := _env()
	var r := _start(env)
	r.set_mode("ask")
	_kills(r, int(_rules().kills_per_choice))
	var before: Array = r.offer().duplicate()
	assert_true(r.reroll())
	for pid in r.offer():
		assert_false(before.has(pid), "voci nuove")
	assert_false(r.reroll(), "una volta per Corsa")
	var gone := str(r.offer()[1])
	assert_true(r.banish(1))
	assert_false(r.offer().has(gone))
	assert_true((r.state.banned as Array).has(gone))
	assert_false(r.banish(0), "una volta per Corsa")


func test_determinismo_delle_offerte() -> void:
	var a := _env(30, 77)
	var b := _env(30, 77)
	var ra := _start(a)
	var rb := _start(b)
	for k in 5:
		_kills(ra, int(_rules().kills_per_choice))
		_kills(rb, int(_rules().kills_per_choice))
		assert_eq(ra.offer(), rb.offer(), "stesso seme, stesse offerte (giro %d)" % k)
		ra.choose(0)
		rb.choose(0)


func test_tetto_scelte_campione_e_chiusura() -> void:
	var env := _env(30, 5)
	var r := _start(env)
	r.set_mode("auto")
	var mx := int(_rules().max_choices)
	for i in mx:
		_kills(r, int(_rules().kills_per_choice))
		r.tick(0.1)
	assert_eq(r.picks().size(), mx)
	assert_true(r.champion_due(), "dopo l'ultima scelta tocca al Campione")
	_kills(r, 100)
	assert_eq(r.picks().size(), mx, "nessuna scelta oltre il tetto")
	# il Campione compare davvero alla prossima comparsa e, battuto, chiude la Corsa
	var xp0 := float(env.skills.xp.get("hero", 0.0))
	var seen := false
	for i in 4000:
		env.tick(1)
		var en: Dictionary = env.state.activity.get("enemy", {})
		if bool(en.get("champion", false)):
			seen = true
		if seen and int(r.state.champions) > 0:
			break
	assert_true(seen, "Campione in campo")
	assert_eq(int(r.state.champions), 1, "Campione battuto")
	assert_eq(r.picks().size(), 0, "Corsa nuova vuota")
	assert_eq(str((r.state.history as Array)[0].end), "champion")
	assert_false(env.mods.has_source(str(_rules().modifier_source)), "voci della Corsa finita tolte")
	assert_gt(float(env.skills.xp.get("hero", 0.0)) - xp0, 0.0)


func test_campione_non_uccide_e_si_arrende_dopo_i_tentativi() -> void:
	var env := _env(30, 9)
	var r := _start(env)
	var ch: Dictionary = _rules().champion
	var saved := ch.duplicate()
	ch["dmg_mult"] = 5000.0                 # ogni colpo sarebbe letale
	ch["hp_mult"] = 5000.0
	r.state["picks"] = ["off_edge"]
	r.state["champion"] = "due"
	for i in 6000:
		env.tick(1)
		if (r.state.history as Array).size() > 0:
			break
	_rules()["champion"] = saved
	assert_eq(int(env.combat.state.deaths), 0, "il Campione si ritira invece di uccidere")
	assert_eq(str((r.state.history as Array)[0].end), "champion_fled", "dopo %d tentativi la Corsa si chiude" % int(saved.max_attempts))
	assert_eq(int(r.state.champions), 0)


func test_offline_la_corsa_e_in_pausa() -> void:
	var env := _env()
	var r := _start(env)
	r.set_mode("ask")
	_kills(r, int(_rules().kills_per_choice))
	r.choose(0)
	_kills(r, 3)
	var k0 := int(r.state.kills)
	var rep: Dictionary = env.combat.simulate_offline(2.0 * 3600.0)
	assert_gt(int(rep.get("kills", 0)), 100, "l'offline del combattimento gira")
	assert_eq(int(r.state.kills), k0, "il contatore della Corsa non avanza offline")
	assert_false(env.mods.has_source(str(_rules().modifier_source)), "statistiche offline senza le voci della Corsa")
	r.tick(0.1)
	assert_true(env.mods.has_source(str(_rules().modifier_source)), "al ritorno la Corsa riprende")


func test_salvataggio_vecchio_e_voci_sconosciute() -> void:
	var r := RunSystem.new()
	var env: Object = Env.make(3, 20, "warrior", false, [r])
	autofree(env.bus)
	r.from_state({"picks": ["off_edge", "voce_che_non_esiste"], "mode": "boh", "order": ["loot"], "kills": "x"})
	assert_eq(r.picks(), ["off_edge"])
	assert_eq(str(r.state.mode), str(_rules().default_mode))
	assert_eq((r.state.order as Array).size(), (_rules().families as Array).size())
	assert_eq(str(r.state.order[0]), "loot")
	assert_eq(int(r.state.kills), 0)


func test_sotto_il_livello_di_sblocco_niente_corsa() -> void:
	var env := _env(int(_rules().unlock_hero_level) - 1)
	var r := _start(env)
	assert_false(r.is_active())
	assert_eq(str(r.status().phase), "locked")


func test_tetto_velocita_d_attacco() -> void:
	var env := _env()
	var c: CombatSystem = env.combat
	var a0: float = env.mods.total_add("combat_haste_pct")
	var weapon_iv := float(c.hero_stats().interval) * (1.0 + Formulas.effective_haste_pct(a0) / 100.0)
	env.mods.set_source("test:haste", [{"key": "combat_haste_pct", "value": 1000.0}])
	var hc: Dictionary = Formulas.k().combat.rules.haste_cap
	assert_almost_eq(float(c.hero_stats().interval), weapon_iv / (1.0 + float(hc.hard_pct) / 100.0), 1e-6, "mai oltre il tetto duro")
	env.mods.set_source("test:haste", [{"key": "combat_haste_pct", "value": 10.0}])
	assert_almost_eq(float(c.hero_stats().interval), weapon_iv / (1.0 + (a0 + 10.0) / 100.0), 1e-6, "sotto il tetto morbido invariato")
	assert_almost_eq(Formulas.effective_haste_pct(80.0), 70.0, 1e-9)


func test_rami_di_talento_esclusivi() -> void:
	var env := _env(40)
	var c: CombatSystem = env.combat
	env.quests.done["class_paladin"] = true
	env.quests.done["class_berserker"] = true
	c.build.set_spec("paladin")
	c.state.talents["ber_fury"] = 5
	c.on_build_changed()
	assert_almost_eq(_talent_add(env, "combat_dmg_pct"), 0.0, 1e-9, "ramo Berserker inattivo con il Paladino")
	assert_eq(c.build.why_not("ber_leech"), "inactive")
	c.build.set_spec("berserker")
	assert_almost_eq(_talent_add(env, "combat_dmg_pct"), 10.0, 1e-9, "torna a valere cambiando specializzazione")


func _talent_add(env: Object, key: String) -> float:
	var n := 0.0
	for m in env.mods.get_source("talents"):
		if str(m.key) == key:
			n += float(m.value)
	return n


func test_talenti_ritarati() -> void:
	var v: Dictionary = DataRegistry.get_def("talents", "warrior_vigor_t")
	assert_almost_eq(float(v.modifiers_per_rank[0].value) * int(v.max_rank), 0.15, 1e-9, "Vigore: +0,15%/s con 3 punti")
	var bc: Dictionary = DataRegistry.get_def("talents", "ber_crit")
	assert_eq(int(bc.modifiers_per_rank[0].value), 25)
	var ph: Dictionary = DataRegistry.get_def("talents", "pal_heal")
	assert_eq(str(ph.modifiers_per_rank[0].key), "food_heal_pct")
	var pr: Dictionary = DataRegistry.get_def("talents", "pal_resolve")
	assert_eq((pr.modifiers_per_rank as Array).size(), 2, "Risolutezza: resistenza + vita")


# ---------------------------------------------------------------------- Preparazione dei boss (risposte alle meccaniche)

func _mech_sim() -> CombatSim:
	var sim := CombatSim.new()
	sim.mech = {}
	for m in DataRegistry.table("boss_mechanics"):
		sim.mech[str(m.id)] = m
	return sim


func test_risposte_nei_dati() -> void:
	var sim := _mech_sim()
	for mid in ["heavy_blow", "shield_phase", "poison_cloud", "stun", "summon_adds"]:
		assert_false((sim.mech[mid].get("answer", {}) as Dictionary).is_empty(), "risposta per %s" % mid)


func test_colpo_devastante_risposto_da_scudo_o_difesa() -> void:
	var sim := _mech_sim()
	var rt := CombatSim.new_rt()
	assert_false(sim._guard_answered(rt))
	rt.buffs["battle_cry"] = {"left": 5.0, "mods": [{"key": "combat_dmg_pct", "value": 20}]}
	assert_false(sim._guard_answered(rt), "un potenziamento offensivo non è una risposta")
	rt.buffs["shield_wall"] = {"left": 5.0, "mods": [{"key": "combat_dmg_taken_pct", "value": -30}]}
	assert_true(sim._guard_answered(rt))
	var rt2 := CombatSim.new_rt()
	rt2["shield"] = 10.0
	assert_true(sim._guard_answered(rt2), "scudo assorbente")


func test_barriera_risposta_da_penetrazione_o_dot() -> void:
	var sim := _mech_sim()
	sim.st = {"armor_pen": 0.0}
	var e := {"dots": {}}
	assert_false(sim._pierce_answered(e))
	e.dots["bleed"] = {"left": 3.0}
	assert_true(sim._pierce_answered(e), "danno nel tempo sul boss")
	sim.st = {"armor_pen": 0.25}
	assert_true(sim._pierce_answered({"dots": {}}), "penetrazione oltre la soglia")


func test_preparazione_si_legge_prima_dello_scontro() -> void:
	var env := _env(30)
	var c: CombatSystem = env.combat
	var queen: Dictionary = DataRegistry.get_def("monsters", "hornet_queen")
	c.build.set_auto_abilities(false)
	c.state["abilities"] = ["cleave"]
	c.on_build_changed()
	var a0: Array = c.boss_answers(queen)
	assert_eq(a0.size(), 1)
	assert_false(bool(a0[0].ready), "senza potenziamento difensivo: manca")
	c.build.set_slot(1, "shield_wall")
	var a1: Array = c.boss_answers(queen)
	assert_true(bool(a1[0].ready), "con Muro di Scudi: pronto")


func test_risposta_riduce_il_danno_del_boss_nel_motore() -> void:
	# stesso Eroe con Muro di Scudi contro la Regina Calabrone: con la risposta il danno subito per uccisione cala
	var env := _env(14, 31, "millbrook", 1)
	var c: CombatSystem = env.combat
	c.build.set_slot(0, "shield_wall")
	var queen: Dictionary = DataRegistry.get_def("monsters", "hornet_queen")
	var ans: Dictionary = c.mechanics()["heavy_blow"].answer
	var saved := float(ans.hit_mult)
	var loss := []
	for hm in [1.0, saved]:
		ans["hit_mult"] = hm
		c._est_cache.clear()
		var est: Dictionary = c.estimate_mon(queen, c._scaled(queen, 1), {"precise": false})
		loss.append(float(est.loss_per_kill))
	ans["hit_mult"] = saved
	assert_lt(loss[1], loss[0], "danno per uccisione con la risposta %.1f < senza %.1f" % [loss[1], loss[0]])


# ---- regola 2: nessun numero di ripiego nel codice, le regole vengono dai dati

func _without(d: Dictionary, path: String) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	var parts := path.split(".")
	var cur: Dictionary = c
	for i in parts.size() - 1:
		cur = cur[parts[i]]
	cur.erase(parts[parts.size() - 1])
	return c


func test_regole_obbligatorie_presenti_nei_dati() -> void:
	assert_eq(RunSystem.missing_rule_keys(_rules()), PackedStringArray(), "run_rules.json completo")


func test_se_manca_una_regola_il_controllo_fallisce() -> void:
	for path in RunSystem.REQUIRED_RULES:
		var missing := RunSystem.missing_rule_keys(_without(_rules(), path))
		assert_true(missing.has(path), "togliendo %s deve essere segnalata" % path)


func test_il_codice_legge_solo_regole_dichiarate_e_senza_ripiego() -> void:
	var used: Dictionary = {}
	for f in ["res://src/systems/RunSystem.gd", "res://src/systems/CombatSystem.gd", "res://src/ui/screens/RunPanel.gd"]:
		var txt := FileAccess.get_file_as_string(f)
		var rx := RegEx.create_from_string("\\brule\\(\"([a-z_.]+)\"\\)")
		for m in rx.search_all(txt):
			used[m.get_string(1)] = true
		var rx2 := RegEx.create_from_string("(?:(?<![a-z_])rules\\(\\)|champion_rules\\(\\))\\.get\\(\"[a-z_]+\", *[^)]")
		assert_null(rx2.search(txt), "%s: lettura con valore di ripiego" % f)
	assert_gt(used.size(), 10)
	for k in used:
		assert_true(RunSystem.REQUIRED_RULES.has(k) or k == "champion", "regola %s letta ma non dichiarata" % k)
