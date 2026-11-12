extends GutTest
## M7 (COMBAT-2): talenti (punti, requisiti, ramo di specializzazione, modificatori, azzeramento), classi base e ibride,
## specializzazioni, cambio classe, pozioni di combattimento, oli, incastri di Glifi.

const Env := preload("res://tests/helpers/combat2_env.gd")


func _hero(cls: String = "warrior", lvl: int = 30, tier: int = 3) -> Object:
	var env: Object = Env.make(4, lvl, cls)
	env.gear(cls, tier)
	return env


# ------------------------------------------------------------------ punti e requisiti

func test_punti_talento_per_livello_e_stelle() -> void:
	var env: Object = _hero("warrior", 10, 1)
	var r: Dictionary = Formulas.k().combat.rules.talents
	assert_eq(env.combat.build.points_total(), int(10.0 / float(r.hero_levels_per_point)), "1 punto ogni 2 livelli Eroe")
	env.skills.levels["hero"] = 100
	assert_eq(env.combat.build.points_total(), int(r.max_level_points), "max 50 dai livelli")
	env.state.skills["hero"] = {"stars": 3}
	assert_eq(env.combat.build.points_total(), int(r.max_level_points) + 3, "+1 per Stella dell'Eroe")
	env.state.skills["hero"] = {"stars": 99}
	assert_eq(env.combat.build.points_total(), int(r.max_level_points) + int(r.max_star_points), "max +25 dalle Stelle")


func test_requisiti_dei_nodi_e_rami() -> void:
	var env: Object = _hero()
	var b: HeroBuild = env.combat.build
	var nodes := b.talent_nodes()
	assert_eq(nodes.size(), 18, "6 generali + 2 rami da 6 per la classe base")
	assert_eq(b.why_not("warrior_toughness"), "")
	assert_eq(b.why_not("warrior_precision_t"), "branch", "il nodo 1 richiede punti nel ramo")
	assert_eq(b.why_not("ranger_toughness"), "class", "albero di un'altra classe")
	assert_eq(b.why_not("pal_bulwark"), "spec", "ramo della specializzazione non sbloccata")
	for i in 2:
		assert_true(b.rank_up("warrior_toughness"))
	assert_eq(b.rank("warrior_toughness"), 2)
	assert_eq(b.why_not("warrior_precision_t"), "", "dopo 2 punti nel ramo")
	assert_eq(b.points_free(), b.points_total() - 2)
	# massimo dei ranghi
	for i in 3:
		b.rank_up("warrior_toughness")
	assert_eq(b.why_not("warrior_toughness"), "max")
	# finiscono i punti
	env.skills.levels["hero"] = 4
	assert_eq(b.points_total(), 2)
	assert_eq(b.why_not("warrior_precision_t"), "points")


func test_ramo_di_specializzazione() -> void:
	var env: Object = _hero()
	var b: HeroBuild = env.combat.build
	assert_false(b.set_spec("paladin"), "serve la missione di classe")
	env.quests.done["class_paladin"] = true
	assert_true(b.set_spec("paladin"))
	assert_eq(env.combat.state.spec, "paladin")
	assert_eq(b.why_not("pal_bulwark"), "")
	assert_true(b.rank_up("pal_bulwark"))
	assert_false(b.set_spec("sharpshooter"), "specializzazione di un'altra classe")
	assert_true(b.set_spec(""), "si può tornare senza specializzazione")
	env.skills.levels["hero"] = 20
	assert_false(b.set_spec("paladin"), "livello Eroe 30 richiesto")


func test_modificatori_dei_talenti_nelle_statistiche() -> void:
	var env: Object = _hero()
	var hp0: float = env.combat.hero_stats().hp
	var add0: float = env.mods.total_add("combat_hp_pct")
	for i in 3:
		env.combat.build.rank_up("warrior_toughness")
	assert_true(env.mods.has_source("talents"))
	var hp1: float = env.combat.hero_stats().hp
	var per: float = float(DataRegistry.get_def("talents", "warrior_toughness").modifiers_per_rank[0].value)
	assert_almost_eq(hp1 / hp0, (1.0 + (add0 + 3.0 * per) / 100.0) / (1.0 + add0 / 100.0), 1e-9)


func test_azzeramento_gratis_e_a_pagamento() -> void:
	var env: Object = _hero("warrior", 18, 2)
	env.combat.build.rank_up("warrior_toughness")
	assert_eq(env.combat.build.respec_cost(), 0, "gratis fino a Eroe 20")
	assert_true(env.combat.build.respec())
	assert_true(env.combat.state.talents.is_empty())
	assert_false(env.mods.has_source("talents"), "modificatori rimossi")
	env.skills.levels["hero"] = 30
	env.combat.build.rank_up("warrior_toughness")
	var r: Dictionary = Formulas.k().combat.rules.talents
	assert_eq(env.combat.build.respec_cost(), int(r.respec_gold_per_level) * 30)
	assert_false(env.combat.build.respec(), "senza oro non si azzera")
	env.bank.gold_n = 30000
	assert_true(env.combat.build.respec())
	assert_eq(env.bank.gold_n, 0)
	# non durante il combattimento
	env.combat.build.rank_up("warrior_toughness")
	env.unlock_zone("millbrook")
	env.combat.start("millbrook", "mud_slime")
	env.bank.gold_n = 99999
	assert_false(env.combat.build.respec())


# ------------------------------------------------------------------ classi

func test_cambio_classe_gratis_poi_a_pagamento_con_ricarica() -> void:
	var env: Object = _hero("warrior", 8, 1)
	assert_true(env.combat.set_class("ranger"), "gratis fino a Eroe 10")
	assert_eq(env.combat.state.class, "ranger")
	assert_eq(env.combat.class_change_cost(), 0)
	env.skills.levels["hero"] = 30
	var cc: Dictionary = Formulas.k().combat.rules.class_change
	assert_eq(env.combat.class_change_cost(), int(cc.gold_per_level) * 30)
	assert_false(env.combat.set_class("arcanist"), "senza oro")
	env.bank.gold_n = 400000
	env.combat.build.rank_up("ranger_toughness")
	assert_true(env.combat.set_class("arcanist"))
	assert_eq(env.bank.gold_n, 400000 - int(cc.gold_per_level) * 30)
	assert_true(env.combat.state.talents.is_empty(), "i talenti della vecchia classe si azzerano")
	assert_eq(env.combat.state.spec, "")
	assert_false(env.combat.set_class("warrior"), "ricarica di 1 ora")
	env.tick(int(float(cc.cooldown_s) / FixedStepClock.STEP) + 2)
	assert_true(env.combat.set_class("warrior"))
	assert_false(env.combat.set_class("paladin"), "una specializzazione non è una classe")


func test_cambio_classe_dopo_il_livello_libero_costo_basso_e_ritorno_di_prova_gratis() -> void:
	# MURI (BOT-05): chi prova una classe a Eroe 25 non resta bloccato: costo basso e ritorno gratuito entro la finestra di prova
	var env: Object = _hero("warrior", 25, 1)
	var cc: Dictionary = Formulas.k().combat.rules.class_change
	assert_gte(int(cc.free_until_level), 20, "finestra gratuita almeno fino a Eroe 20")
	assert_lt(int(cc.gold_per_level) * 25, 20000, "a Eroe 25 provare una classe costa poco")
	assert_eq(env.combat.class_change_cost(), int(cc.gold_per_level) * 25 if 25 > int(cc.free_until_level) else 0)
	env.skills.levels["hero"] = int(cc.free_until_level) + 5
	var lvl: int = int(cc.free_until_level) + 5
	env.bank.gold_n = int(cc.gold_per_level) * lvl + 10
	assert_true(env.combat.set_class("ranger"), "primo cambio a pagamento")
	assert_eq(env.bank.gold_n, 10)
	assert_true(env.combat.class_change_is_trial_return("warrior"))
	assert_eq(env.combat.class_change_cost("warrior"), 0, "il ritorno alla classe lasciata e' gratis")
	assert_gt(env.combat.class_change_cost("arcanist"), 0)
	assert_false(env.combat.set_class("arcanist"), "senza oro e con la ricarica")
	assert_true(env.combat.set_class("warrior"), "ritorno di prova: gratis e senza attesa")
	assert_eq(env.bank.gold_n, 10)
	assert_eq(float(env.combat.state.class_cd_s), 0.0)
	assert_false(env.combat.class_change_is_trial_return("ranger"), "il ritorno gratuito non si concatena")
	# la finestra scade con il tempo di gioco
	env.bank.gold_n = int(cc.gold_per_level) * lvl * 2
	assert_true(env.combat.set_class("ranger"))
	env.combat._dec_class_timers(float(cc.trial_return_s) + 1.0)      # scorre il tempo di gioco
	assert_false(env.combat.class_change_is_trial_return("warrior"), "finestra di prova scaduta")
	assert_gt(env.combat.class_change_cost("warrior"), 0)


func test_classi_ibride_sbloccate_da_stella_e_missione() -> void:
	var env: Object = _hero("warrior", 40, 3)
	assert_false(env.combat.build.class_available("spellblade"))
	env.state.skills["hero"] = {"stars": 1}
	assert_false(env.combat.build.class_available("spellblade"), "serve anche la missione di classe")
	env.quests.done["class_spellblade"] = true
	assert_true(env.combat.build.class_available("spellblade"))
	env.bank.gold_n = 999999
	assert_true(env.combat.set_class("spellblade"))
	assert_eq(env.combat.build.talent_nodes().size(), 8, "ramo unico da 8 nodi")


func test_ibrida_sceglie_la_postura_in_vantaggio() -> void:
	var env: Object = _hero("warrior", 40, 3)
	env.state.skills["hero"] = {"stars": 1}
	env.quests.done["class_spellblade"] = true
	env.bank.gold_n = 999999
	env.combat.set_class("spellblade")      # Mischia + Arcano
	var vs_melee := {"style": "melee"}
	var vs_ranged := {"style": "ranged"}
	assert_eq(env.combat.stance_for(vs_melee), "arcane", "l'Arcano batte la Mischia")
	assert_eq(env.combat.stance_for(vs_ranged), "melee", "la Mischia batte la Distanza")
	var s_arc: Dictionary = env.combat._stats_for("arcane")
	var s_mel: Dictionary = env.combat._stats_for("melee")
	assert_eq(s_arc.style, "arcane")
	assert_eq(s_mel.style, "melee")
	assert_eq(s_arc.primary, "int")
	assert_eq(s_mel.primary, "str")
	var pm: float = float(env.combat.class_def().passive.stat_mult)
	assert_almost_eq(pm, 1.2, 1e-9, "Postura automatica: statistiche ×1,2 (Q97: stile sbagliato meno punitivo, ibride a 0,95-1,01 delle classi base)")


# ------------------------------------------------------------------ pozioni, oli, Glifi

func test_pozione_di_combattimento_a_cariche() -> void:
	var env: Object = _hero("warrior", 20, 2)
	env.food()
	env.unlock_zone("millbrook")
	assert_false(env.combat.use_potion("potion_fury_1"), "non ce l'ha")
	env.bank.add("potion_fury_1", 2, "test")
	var d: Dictionary = DataRegistry.item("potion_fury_1")
	var add0: float = env.mods.total_add(str(d.potion.modifiers[0].key))
	assert_true(env.combat.use_potion("potion_fury_1"))
	assert_eq(env.bank.count("potion_fury_1"), 1)
	assert_true(env.mods.has_source(CombatSystem.POTION_SOURCE))
	assert_gt(env.mods.total_add(str(d.potion.modifiers[0].key)), add0)
	var charges0: int = int(env.combat.state.potion.charges)
	assert_eq(charges0, int(d.potion.charges))
	env.combat.start("millbrook", "mud_slime")
	env.tick(200)
	assert_lt(int(env.combat.state.potion.get("charges", 0)), charges0, "una carica per attacco")
	env.combat.state.potion["charges"] = 1
	env.tick(100)
	assert_true(env.combat.state.potion.is_empty(), "esaurita")
	assert_false(env.mods.has_source(CombatSystem.POTION_SOURCE))


func test_olio_da_lama_aggiunge_danno_e_si_consuma_ai_colpi() -> void:
	var env: Object = _hero("warrior", 20, 2)
	env.food()
	env.unlock_zone("millbrook")
	var hit0: float = env.combat.hero_stats().max_hit
	env.bank.add("oil_t1", 50, "test")
	assert_true(env.combat.equip_ammo("oil_t1"))
	assert_gt(float(env.combat.hero_stats().max_hit), hit0, "l'olio aggiunge danno alla lama")
	assert_true(env.combat.start("millbrook", "mud_slime"), "per la Mischia l'olio è facoltativo")
	env.tick(300)
	assert_lt(env.combat.ammo_qty(), 50, "un olio per colpo andato a segno")


func test_incastri_di_glifi() -> void:
	var env: Object = _hero("warrior", 20, 2)
	var plain: String = env.give("sword_copper", "normal")
	assert_eq(env.combat.sockets_of(plain).max, 0, "qualità Normale: nessun incastro")
	var fine: String = env.give("sword_copper", "masterwork")
	var info: Dictionary = env.combat.sockets_of(fine)
	assert_eq(info.max, 3)
	env.combat.equip(fine)
	var hit0: float = env.combat.hero_stats().max_hit
	env.bank.add("glyph_fury_1", 5, "test")
	watch_signals(env.bus)
	assert_true(env.combat.socket_glyph(fine, "glyph_fury_1"))
	assert_eq(env.bank.count("glyph_fury_1"), 4)
	assert_signal_emitted_with_parameters(env.bus, "objective_event", ["socket_glyph", {"qty": 1}])
	env.combat._sync_equipment()
	assert_gt(float(env.combat.hero_stats().max_hit), hit0, "il Glifo aggiunge i suoi modificatori")
	assert_true(env.combat.socket_glyph(fine, "glyph_fury_1"))
	assert_true(env.combat.socket_glyph(fine, "glyph_fury_1"))
	assert_false(env.combat.socket_glyph(fine, "glyph_fury_1"), "incastri finiti")
	assert_false(env.combat.socket_glyph(plain, "glyph_fury_1"))
	assert_true(env.combat.unsocket_glyph(fine, 0), "rimuovere distrugge il Glifo")
	assert_eq(env.combat.sockets_of(fine).glyphs.size(), 2)
	assert_eq(env.bank.count("glyph_fury_1"), 2, "non torna indietro")
