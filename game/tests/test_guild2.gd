extends GutTest
## GUILD-2: Imprese/Titoli/Famigli (CompendiumSystem), Luoghi Segreti (SecretSystem), incarichi di fazione e ricompense
## delle missioni (reputazione, titolo, cornice), Scarta del Deposito, Rune 1-4 non vendibili.


func _fx(seed_value: int = 7) -> Guild2Fixtures:
	var f := Guild2Fixtures.make(seed_value)
	autofree(f.events)
	f.sim.tick(0.1)
	return f


func _social() -> Dictionary:
	return DataRegistry.rules("social_rules")


# ------------------------------------------------------------------ famigli

func test_famiglio_nuovo_registra_bonus_e_compagno() -> void:
	var f := _fx()
	f.events.pet_found.emit("pet_skill_woodcutting")
	assert_true(f.comp.has_pet("pet_skill_woodcutting"))
	assert_eq(f.comp.companion(), "pet_skill_woodcutting", "il primo famiglio diventa il compagno visibile")
	# bonus passivo: skill_double_pct:woodcutting +3
	assert_almost_eq(f.mods.apply(100.0, "skill_double_pct", ["woodcutting"]), 103.0, 1e-6)
	assert_eq((f.state.pets as Array).size(), 1)


func test_doppione_di_famiglio_diventa_polvere() -> void:
	var f := _fx()
	f.events.pet_found.emit("pet_crate_waspling")
	var dust0: int = f.bank.currency("stardust")
	f.events.pet_found.emit("pet_crate_waspling")
	f.events.pet_found.emit("pet_crate_waspling")
	assert_eq((f.state.pets as Array).size(), 1, "nessun duplicato nell'elenco")
	assert_eq(f.comp.pet_dupes("pet_crate_waspling"), 2)
	assert_eq(f.bank.currency("stardust") - dust0, 2 * int(_social().pets.crate_duplicate_stardust))
	# bonus non raddoppiato
	assert_almost_eq(f.mods.apply(100.0, "skill_xp_pct", ["gathering"]), 102.0, 1e-6)


func test_famiglio_sconosciuto_ignorato() -> void:
	var f := _fx()
	assert_eq(f.comp.found_pet("pet_inesistente"), "unknown")
	assert_eq((f.state.pets as Array).size(), 0)


func test_compagno_solo_se_posseduto() -> void:
	var f := _fx()
	assert_false(f.comp.set_companion("pet_skill_mining"))
	f.events.pet_found.emit("pet_skill_mining")
	f.events.pet_found.emit("pet_skill_fishing")
	assert_true(f.comp.set_companion("pet_skill_fishing"))
	assert_eq(f.comp.companion(), "pet_skill_fishing")


# ------------------------------------------------------------------ titoli e cornici

func test_titoli_si_scelgono_solo_se_posseduti() -> void:
	var f := _fx()
	assert_false(f.comp.set_title("title_vaultbreaker"))
	assert_true(f.comp.grant_title("title_vaultbreaker"))
	assert_false(f.comp.grant_title("title_vaultbreaker"), "idempotente")
	assert_eq(f.comp.selected_title(), "title_vaultbreaker", "il primo titolo si indossa da solo")
	assert_true(f.comp.grant_title("title_firmament"))
	assert_true(f.comp.set_title("title_firmament"))
	assert_true(f.comp.set_title(""), "si può anche togliere")
	assert_eq(f.comp.title_line(), "")
	assert_false(f.comp.grant_title("title_che_non_esiste"))


func test_cornice_da_missione_e_selezione() -> void:
	var f := _fx()
	assert_true(f.comp.grant_cosmetic("cosmetic_frame_woodcutting_bronze"))
	assert_false(f.comp.grant_cosmetic("cosmetic_frame_woodcutting_bronze"))
	assert_true(f.comp.has_frame("cosmetic_frame_woodcutting_bronze"))
	assert_false(f.comp.set_frame("star_frame_gold_mining"), "non posseduta")
	assert_true(f.comp.set_frame("cosmetic_frame_woodcutting_bronze"))


func test_stelle_danno_cornici_e_titolo() -> void:
	var f := _fx()
	f.state.skills["mining"] = {"xp": 0.0, "level": 1, "stars": 25}
	f.comp.evaluate()
	assert_true(f.comp.has_frame("star_frame_silver_mining"))
	assert_true(f.comp.has_frame("star_frame_gold_mining"))
	assert_true(f.comp.has_frame("star_frame_platinum_mining"))
	assert_false(f.comp.has_frame("star_frame_diamond_mining"))
	assert_true(f.comp.has_title("title_star_mining"))


# ------------------------------------------------------------------ imprese

func test_impresa_livello_sblocca_paga_polvere_e_segnala() -> void:
	var f := _fx()
	f.state.skills["woodcutting"] = {"xp": 0.0, "level": 50}
	var got: Array = []
	f.events.achievement_unlocked.connect(func(i: String) -> void: got.append(i))
	var dust0: int = f.bank.currency("stardust")
	assert_gt(f.comp.evaluate(), 0)
	assert_true(f.comp.is_unlocked("ach_woodcutting_50"))
	assert_true(got.has("ach_woodcutting_50"))
	assert_eq(f.bank.currency("stardust") - dust0, int(DataRegistry.get_def("achievements", "ach_woodcutting_50").reward.stardust) + _extra_dust(f, got))
	assert_eq(f.comp.evaluate(), 0, "non si sblocca due volte")


func _extra_dust(_f: Guild2Fixtures, got: Array) -> int:
	var extra := 0
	for g in got:
		if g != "ach_woodcutting_50":
			extra += int(DataRegistry.get_def("achievements", g).reward.get("stardust", 0))
	return extra


func test_impresa_con_titolo() -> void:
	var f := _fx()
	var ach := ""
	for a in DataRegistry.table("achievements"):
		if a.reward.has("title") and a.condition.type == "skill_level":
			ach = str(a.id)
			f.state.skills[str(a.condition.skill)] = {"xp": 0.0, "level": int(a.condition.level)}
			break
	assert_ne(ach, "", "esiste un'impresa di livello con titolo")
	f.comp.evaluate()
	assert_true(f.comp.is_unlocked(ach))
	assert_true(f.comp.has_title(str(DataRegistry.get_def("achievements", ach).reward.title)))


func test_impresa_progresso_e_contatori_da_segnali() -> void:
	var f := _fx()
	f.events.objective_event.emit("recruit", {"qty": 1, "rarity": "legendary"})
	f.events.objective_event.emit("expedition", {"qty": 3})
	assert_eq(f.comp.counter("recruit:legendary"), 1)
	f.comp.evaluate()
	assert_true(f.comp.is_unlocked("ach_merc_legendary"))
	var p: Dictionary = f.comp.ach_progress("ach_exp_100")
	assert_eq(int(p.cur), 3)
	assert_eq(int(p.target), 100)


func test_famiglio_trovato_aggiorna_impresa_famigli() -> void:
	var f := _fx()
	f.events.pet_found.emit("pet_skill_woodcutting")
	f.comp.evaluate()
	assert_true(f.comp.is_unlocked("ach_pets_1"))


func test_stato_compendio_round_trip_json() -> void:
	var f := _fx()
	f.events.pet_found.emit("pet_skill_woodcutting")
	f.comp.grant_title("title_firmament")
	f.events.objective_event.emit("tradeup", {"qty": 2})
	var back: Variant = JSON.parse_string(JSON.stringify(f.comp.to_state()))
	assert_true(back is Dictionary)
	assert_eq(int(back.counters.tradeup), 2)
	assert_eq(str(back.title), "title_firmament")


# ------------------------------------------------------------------ incarichi di fazione e ricompense

func test_ricompense_missione_reputazione() -> void:
	var f := _fx()
	var qid := "side_merchant_league_1"
	assert_eq(f.quests.faction_quest_status(qid), "available")
	assert_true(f.quests.accept_faction_quest(qid))
	assert_eq(f.quests.faction_quest_status(qid), "active")
	f.events.objective_event.emit("sell_market", {"gold": 10000})
	f.sim.tick(0.1)
	assert_eq(f.quests.faction_quest_status(qid), "ready")
	var gold0: int = f.bank.gold()
	assert_true(f.quests.claim(qid))
	assert_eq(f.market.reputation("merchant_league"), 250)
	assert_eq(f.bank.gold() - gold0, 2000)
	assert_eq(f.quests.faction_quest_status(qid), "done")
	assert_eq(f.quests.faction_quest_status("side_merchant_league_2"), "available", "si sblocca il successivo")


func test_catena_incarichi_blocca_il_successivo() -> void:
	var f := _fx()
	assert_eq(f.quests.faction_quest_status("side_merchant_league_3"), "locked")
	f.state.unlocks.erase("feature:factions")
	assert_eq(f.quests.faction_quest_status("side_merchant_league_1"), "locked", "serve il token feature:factions")


func test_incarichi_con_fonte_si_accettano() -> void:
	# integrazione finale: Contratti/Affinatura (CrateSystem) e Incursioni (EndgameCombat) emettono gli eventi
	var f := _fx()
	f.quests.state.done.append("side_grey_hand_2")
	assert_eq(f.quests.faction_quest_status("side_grey_hand_3"), "available")
	assert_true(f.quests.accept_faction_quest("side_grey_hand_3"))


func test_incarico_finale_da_titolo() -> void:
	var f := _fx()
	f.quests.state.done.append("side_merchant_league_5")
	assert_true(f.quests.accept_faction_quest("side_merchant_league_6"))
	f.events.objective_event.emit("estate_prestige", {"qty": 1})
	f.sim.tick(0.1)
	assert_true(f.quests.claim("side_merchant_league_6"))
	assert_true(f.comp.has_title("title_merchant_league_champion"))
	assert_eq(f.market.reputation("merchant_league"), 1500)


func test_grado_di_fazione_sale_e_da_il_titolo_esaltato() -> void:
	var f := _fx()
	f.market.add_reputation("merchant_league", 40000)
	assert_eq(f.market.rank_id("merchant_league"), "exalted")
	f.comp.evaluate()
	assert_true(f.comp.has_title("title_merchant_league_exalted"))


func test_salto_di_grado_avvisa() -> void:
	var f := _fx()
	f.notices.clear()
	f.market.add_reputation("order_of_wardens", 1000)
	var found := false
	for n in f.notices:
		if str(n.text).contains("Ordine") or str(n.text).contains("Order"):
			found = true
	assert_true(found, "avviso del nuovo grado")


func test_ricompensa_cosmetico_da_percorso_mansione() -> void:
	var f := _fx()
	var qid := ""
	for q in DataRegistry.table("quests"):
		if q.rewards.has("cosmetic"):
			qid = str(q.id)
			break
	assert_ne(qid, "")
	f.quests.accept(qid)
	for i in (f.quests.state.progress[qid] as Array).size():
		f.quests.state.progress[qid][i] = QuestSystem.target_of(f.quests.quest_def(qid).objectives[i])
	assert_true(f.quests.claim(qid))
	assert_true(f.comp.has_frame(str(f.quests.quest_def(qid).rewards.cosmetic)))


func test_anteprima_ricompense_include_reputazione_titolo_cornice() -> void:
	var f := _fx()
	var pv: Array = f.quests.reward_preview("side_merchant_league_6")
	var kinds: Array = pv.map(func(r: Dictionary) -> String: return str(r.kind))
	assert_true(kinds.has("reputation"))
	assert_true(kinds.has("title"))
	var lines := QuestText.reward_lines(pv, DataRegistry)
	assert_eq(lines.size(), pv.size())


func test_evento_ordini_e_mercenari_alimentano_gli_incarichi() -> void:
	var f := _fx()
	f.quests.state.done.append("side_rangers_company_3")
	assert_true(f.quests.accept("side_rangers_company_4"))
	f.events.objective_event.emit("recruit", {"qty": 1, "rarity": "common"})
	f.sim.tick(0.1)
	assert_eq(int(f.quests.progress_of("side_rangers_company_4")[0]), 0, "serve un mercenario Raro")
	f.events.objective_event.emit("recruit", {"qty": 1, "rarity": "rare"})
	f.sim.tick(0.1)
	assert_true(f.quests.is_ready("side_rangers_company_4"))


# ------------------------------------------------------------------ Luoghi Segreti

func _frag(f: Guild2Fixtures, n: int) -> void:
	f.bank.add("map_fragment", n, "test")


func test_luogo_segreto_sblocco_con_frammenti() -> void:
	var f := _fx()
	assert_false(f.unlock.has("feature:secrets"))
	_frag(f, 3)
	assert_true(f.unlock.has("feature:secrets"), "il menù compare col primo frammento")
	assert_eq(f.secrets.can_reveal("hidden_grove"), "level")
	f.state.skills["woodcutting"] = {"xp": 0.0, "level": 60}
	assert_eq(f.secrets.can_reveal("hidden_grove"), "fragments")
	_frag(f, 7)
	assert_eq(f.secrets.can_reveal("hidden_grove"), "")
	assert_true(f.secrets.reveal("hidden_grove"))
	assert_eq(f.bank.count("map_fragment"), 0)
	assert_true(f.secrets.is_revealed("hidden_grove"))
	assert_eq(f.secrets.can_reveal("hidden_grove"), "revealed")
	assert_almost_eq(f.secrets.time_left("hidden_grove"), 24.0 * 3600.0, 1.0)
	assert_eq(f.secrets.runs_left("hidden_grove"), int(_social().secrets.runs_per_reveal))


func test_luogo_segreto_esplorazione_dà_xp_e_oggetti() -> void:
	var f := _fx(3)
	f.state.skills["woodcutting"] = {"xp": 0.0, "level": 60}
	_frag(f, 10)
	assert_true(f.secrets.reveal("hidden_grove"))
	var pv: Dictionary = f.secrets.preview("hidden_grove")
	assert_gt(float(pv.xp), 0.0)
	assert_true(f.secrets.explore("hidden_grove"))
	assert_eq(f.secrets.can_explore("hidden_grove"), "busy", "una alla volta")
	assert_eq(f.secrets.runs_left("hidden_grove"), int(_social().secrets.runs_per_reveal) - 1)
	var xp0: float = f.skills.xp("woodcutting")
	f.run(float(_social().secrets.explore_minutes) * 60.0 + 1.0, 1.0)
	assert_true((f.secrets.state.active as Dictionary).is_empty())
	assert_almost_eq(f.skills.xp("woodcutting") - xp0, float(pv.xp), maxf(1.0, float(pv.xp) * 0.02))
	assert_eq(int(f.secrets.state.done_runs), 1)
	assert_gte(f.bank.count("log_vaultroot"), int(floor(float(pv.bonus_expected))))


func test_prima_scoperta_paga_polvere_ed_evento() -> void:
	var f := _fx()
	f.state.skills["mining"] = {"xp": 0.0, "level": 60}
	var kinds: Array = []
	f.events.objective_event.connect(func(k: String, _p: Dictionary) -> void: kinds.append(k))
	_frag(f, 20)
	var dust0: int = f.bank.currency("stardust")
	assert_true(f.secrets.reveal("hollow_vein"))
	assert_eq(f.bank.currency("stardust") - dust0, int(_social().secrets.discovery_stardust))
	assert_true(kinds.has("secret_spot"))
	assert_true(kinds.has("secret_spot_all"))
	# una seconda rivelazione dello stesso luogo non paga di nuovo
	f.secrets.state.spots.clear()
	var dust1: int = f.bank.currency("stardust")
	assert_true(f.secrets.reveal("hollow_vein"))
	assert_eq(f.bank.currency("stardust"), dust1)


func test_finestra_scade_dopo_24_ore() -> void:
	var f := _fx()
	f.state.skills["fishing"] = {"xp": 0.0, "level": 60}
	_frag(f, 10)
	f.secrets.reveal("moonlit_pool")
	f.secrets.simulate_offline(25.0 * 3600.0)
	assert_false(f.secrets.is_revealed("moonlit_pool"))
	assert_true(f.secrets.is_discovered("moonlit_pool"), "la scoperta resta")
	assert_eq(f.secrets.can_explore("moonlit_pool"), "hidden")


func test_esplorazione_offline_coincide_con_i_tick() -> void:
	var a := _fx(5)
	var b := _fx(5)
	for f in [a, b]:
		f.state.skills["woodcutting"] = {"xp": 0.0, "level": 60}
		_frag(f, 10)
		f.secrets.reveal("hidden_grove")
		f.secrets.explore("hidden_grove")
	a.run(3600.0, 1.0)
	var rep: Dictionary = b.secrets.simulate_offline(3600.0)
	assert_eq(int(a.secrets.state.done_runs), int(b.secrets.state.done_runs))
	assert_true(rep.has("rows"), "riga per il Bentornato")


func test_incarichi_ranger_con_luoghi_segreti() -> void:
	var f := _fx()
	f.quests.state.done.append("side_rangers_company_2")
	f.quests.state.done.append("side_rangers_company_5")
	assert_true(f.quests.accept("side_rangers_company_3"))
	f.state.skills["woodcutting"] = {"xp": 0.0, "level": 60}
	_frag(f, 10)
	f.secrets.reveal("hidden_grove")
	f.sim.tick(0.1)
	assert_true(f.quests.is_ready("side_rangers_company_3"))


# ------------------------------------------------------------------ Deposito: Scarta

func test_scarta_pila_rispetta_blocchi() -> void:
	var f := _fx()
	f.bank.add("log_pine", 10, "test")
	assert_eq(f.bank.discardable_count("log_pine"), 10)
	assert_eq(f.bank.discard("log_pine", 4), 4)
	assert_eq(f.bank.count("log_pine"), 6)
	f.bank.set_def_locked("log_pine", true)
	assert_eq(f.bank.discard("log_pine", 6), 0, "pila bloccata")
	f.bank.set_def_locked("log_pine", false)
	assert_eq(f.bank.discard("log_pine", 99), 6, "al massimo quanto posseduto")
	assert_eq(f.bank.count("log_pine"), 0)


func test_scarta_istanze_non_bloccate_e_non_usate() -> void:
	var f := _fx()
	var u1: String = f.bank.add_instance({"def": "sword_copper"})
	var u2: String = f.bank.add_instance({"def": "sword_copper"})
	f.bank.set_instance_locked(u1, true)
	assert_false(f.bank.discard_instance(u1), "bloccata")
	assert_eq(f.bank.discardable_count("sword_copper"), 1)
	assert_eq(f.bank.discard("sword_copper", 5), 1)
	assert_true(f.bank.get_instance(u2).is_empty(), "u2 scartata")
	assert_false(f.bank.get_instance(u1).is_empty(), "u1 resta")


func test_scarta_non_tocca_valute_e_oggetti_missione() -> void:
	var f := _fx()
	f.bank.add_gold(50)
	assert_eq(f.bank.discard("gold", 50), 0)
	assert_eq(f.bank.gold(), 50)


func test_scarta_libera_spazio() -> void:
	var f := _fx()
	var cap: int = f.bank.capacity()
	for i in cap:
		f.bank.add_instance({"def": "skin_millbrook_01"})
	assert_true(f.bank.is_full())
	f.bank.add("log_pine", 1, "test")
	assert_eq(f.bank.overflow_count(), 1, "a Deposito pieno il pezzo aspetta nel Carro (resoconto 117)")
	assert_eq(f.bank.discard("skin_millbrook_01", 3), 3)
	f.bank.tick(0.1)
	assert_eq(f.bank.overflow_count(), 0, "scartando si libera posto e il Carro si scarica")
	assert_eq(f.bank.count("log_pine"), 1)


func test_notice_deposito_pieno_ha_motivo() -> void:
	# resoconto 117: niente piu' «non ha trovato posto»; il Registro riassume cio' che e' entrato nel Carro (motivo carro_stash)
	var f := _fx()
	for i in f.bank.capacity():
		f.bank.add_instance({"def": "skin_millbrook_01"})
	f.notices.clear()
	f.bank.add("log_pine", 1, "test")
	f.bank.tick(1000.0)
	assert_gt(f.notices.size(), 0)
	assert_eq(str(f.notices[0].data.get("reason", "")), "carro_stash")


# ------------------------------------------------------------------ Rune 1-4

func test_rune_basse_non_vendibili_e_alte_si() -> void:
	var f := _fx()
	for t in [1, 2, 3, 4]:
		assert_false(f.market.is_tradeable("rune_t%d" % t), "rune_t%d" % t)
	assert_true(f.market.is_tradeable("rune_t5"))
	for t in [1, 2, 3]:
		assert_false(f.market.is_tradeable("tome_t%d" % t))
	assert_true(f.market.is_tradeable("tome_t4"))
	f.bank.add("rune_t1", 25, "test")
	assert_eq(f.market.sell("rune_t1", 25), 0)
	assert_eq(f.bank.count("rune_t1"), 25)
	assert_eq(f.bank.discard("rune_t1", 25), 25, "ma si possono scartare")
