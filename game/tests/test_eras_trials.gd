extends GutTest
## Ere del Mondo e Prove del Custode (docs/13 §4 e §6, audit 43): PrestigeSystem.
## Mondo di prova: Deposito, Mansioni, Sblocchi e Prestigio VERI con un EventBus PRIVATO (nessuna interferenza con i
## sistemi dell'autoload Game). Il combattimento è simulato emettendo gli stessi segnali che emette quello vero.

const _GS := preload("res://src/autoload/GameState.gd")
const FOOD := "food_bleak"
const BOSS_Z2 := "captain_saltgrin"          # boss della zona 2 (Costa del Sale): bersaglio del grado I di quasi tutte le Prove


class Rec extends RefCounted:
	var important: Array = []
	var objectives: Array = []
	var notices: Array = []
	func on_important(r: String) -> void:
		important.append(r)
	func on_objective(k: String, p: Dictionary) -> void:
		objectives.append([k, p])
	func on_notice(kind: String, _t: String, _d: Dictionary) -> void:
		notices.append(kind)


func _world() -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var bus: Node = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	autofree(bus)
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(5), bus)
	var sim := Simulation.new()
	var ps := PrestigeSystem.new()
	sim.setup(ctx, [BankSystem.new(), SkillSystem.new(), UnlockSystem.new(), ps])
	sim.bind_state(state)
	var rec := Rec.new()
	bus.important_event.connect(rec.on_important)
	bus.objective_event.connect(rec.on_objective)
	bus.notice.connect(rec.on_notice)
	return {"sim": sim, "ctx": ctx, "state": state, "ps": ps, "stack": stack, "bus": bus, "rec": rec, "bank": sim.get_system("bank")}


## Apre le Prove (Capitolo 5 completato) e tiene fuori i Grandi Obiettivi dalla Polvere.
func _open_trials(w: Dictionary) -> void:
	w.state.quests.done.append("main_c5_q5")
	for g in DataRegistry.constants.prestige.goals:
		w.state.prestige.goals[str(g.id)] = true


func _kill(w: Dictionary, monster_id: String) -> void:
	w.bus.monster_killed.emit(monster_id, [])


## G39: il bersaglio della Prova in corso compare in campo (il cronometro di «Contro il Tempo» parte da qui).
func _engage(w: Dictionary) -> void:
	var ta: Dictionary = w.ps.trial_active()
	var tgt: Dictionary = w.ps.trial_target(str(ta.id), int(ta.tier))
	w.state["activity"] = {"type": "combat", "mode": "zone", "enemy": {"id": str(tgt.id)}}


# ------------------------------------------------------------------ ERE: formule e anteprima

func test_formule_dell_era_dai_dati() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_almost_eq(ps.era_monster_mult(3), pow(1.35, 2), 1e-9)
	assert_almost_eq(ps.era_reward_mult(3), 1.6, 1e-9)
	assert_almost_eq(ps.era_crate_mult(3), 1.5, 1e-9, "Cassa dell'Era: 1 + 0,25 (N-1) dalla formula dei dati")
	assert_eq(ps.era_essence_qty(4), 4, "Essenza d'Era per drop = N")
	assert_eq(ps.ranks_for_era(1), 0)
	assert_eq(ps.ranks_for_era(3), int(ceil(2.0 * log(1.35) / log(1.04) - 1e-9)), "circa 7,65 ranghi per Era")
	assert_eq(ps.warden_dust_base(4), 20, "5 x era")


func test_anteprima_era() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.preview_era(2).reason, "UI_ERA_REASON_LOCKED")
	assert_eq(ps.preview_era(1).reason, "UI_ERA_REASON_SAME")
	assert_eq(ps.preview_era(0).reason, "UI_ERA_REASON_INVALID")
	ps.state["era_max"] = 3
	var up := ps.preview_era(3)
	assert_true(up.ok)
	assert_eq(up.lose.size(), 1, "salire costa mostri più duri")
	assert_eq(up.lose[0].key, "UI_ERA_LOSE_HARDER")
	assert_eq(up.gain.size(), 2, "ricompense + Essenza")
	assert_eq(up.keep[0].key, "UI_ERA_KEEP_ALL", "non si perde niente")
	assert_almost_eq(float(up.reward_mult), 1.6, 1e-9)
	assert_eq(int(up.essence_qty), 3)
	ps.set_era(3)
	var down := ps.preview_era(1)
	assert_true(down.ok)
	assert_eq(down.lose[0].key, "UI_ERA_LOSE_REWARDS")
	assert_eq(down.gain[0].key, "UI_ERA_GAIN_EASIER")


func test_cambio_era_applica_l_anteprima() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	ps.state["era_max"] = 4
	assert_eq(ps.do_select_era(9), {}, "Era bloccata: rifiutata")
	assert_eq(ps.do_select_era(1), {}, "Era già attiva: niente da fare")
	var p := ps.do_select_era(3)
	assert_false(p.is_empty())
	assert_eq(ps.era_current(), 3)
	assert_true(w.rec.important.has("era_select"))
	assert_eq(ps.era_max(), 4, "il massimo non cambia")


# ------------------------------------------------------------------ ERE: il Custode

func test_custode_sblocca_la_catena_di_ere() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.on_warden_defeated(1), 5)
	assert_eq(ps.era_max(), 2)
	assert_eq(w.bank.currency("stardust"), 5)
	assert_eq(ps.on_warden_defeated(2), 10)
	assert_eq(ps.era_max(), 3)
	assert_eq(w.bank.currency("stardust"), 15)
	assert_eq(ps.on_warden_defeated(3), 15)
	assert_eq(ps.era_max(), 4)
	assert_eq(ps.warden_kills(2), 1)


func test_custode_eventi_per_imprese_e_autosave() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	ps.on_warden_defeated(1)
	assert_true(w.rec.important.has("era"), "important_event per l'autosave")
	var found := false
	for o in w.rec.objectives:
		if o[0] == "era" and int(o[1].era) == 2:
			found = true
	assert_true(found, "objective_event('era', {era: 2}) per ach_era_2")
	assert_true(w.rec.notices.has("success"))


func test_custode_ripetuto_non_e_una_fonte_di_polvere() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	ps.on_warden_defeated(1)
	var total := 0
	for i in 200:
		total += ps.on_warden_defeated(1)
	assert_eq(total, 0, "regola 9: niente anello Polvere -> danno -> Custodi")
	assert_eq(w.bank.currency("stardust"), 5)
	assert_eq(ps.warden_kills(1), 201, "le uccisioni si contano comunque")
	assert_eq(ps.era_max(), 2, "e non sbloccano altro")
	assert_eq(ps.warden_info(1).dust_now, 0)


func test_custode_ignora_ere_non_sbloccate_e_invalide() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.on_warden_defeated(5), 0, "Era non sbloccata")
	assert_eq(ps.on_warden_defeated(0), 0)
	assert_eq(ps.on_warden_defeated(-3), 0)
	assert_eq(ps.era_max(), 1)
	assert_eq(w.bank.currency("stardust"), 0)


func test_custode_polvere_aumentata_da_stardust_gain_pct() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	w.stack.set_source("t", [{"key": "stardust_gain_pct", "value": 100, "mode": "add"}])
	assert_eq(ps.on_warden_defeated(1), 10)
	assert_eq(ps.warden_dust_now(2), 20, "anteprima = quello che pagherà")


func test_custode_non_conta_durante_una_prova() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	assert_false(ps.start_trial("trial_fasting", 1).is_empty())
	assert_eq(ps.on_warden_defeated(1), 0)
	assert_eq(ps.era_max(), 1)
	assert_false(ps.set_era(1), "durante la Prova l'Era non si cambia")


func test_set_era_bloccato_durante_la_prova() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.state["era_max"] = 3
	ps.set_era(3)
	assert_false(ps.start_trial("trial_fasting", 1).is_empty())
	assert_false(ps.set_era(2), "durante la Prova l'Era non si cambia")
	assert_eq(ps.preview_era(2).reason, "UI_ERA_REASON_TRIAL")
	ps.abandon_trial()
	assert_eq(ps.era_current(), 3, "l'Era torna com'era")
	assert_true(ps.set_era(2))


# ------------------------------------------------------------------ PROVE: sblocco, regole, anteprima

func test_prove_si_aprono_dopo_il_capitolo_5() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_false(ps.trials_unlocked())
	assert_eq(ps.can_start_trial("trial_fasting", 1), "UI_TRIALS_REASON_LOCKED")
	w.state.quests.done.append("main_c5_q5")
	assert_true(ps.trials_unlocked())
	assert_eq(ps.can_start_trial("trial_fasting", 1), "")
	# lo strato compare nella schermata solo con feature:prestige; il token delle Prove lo concede la manutenzione
	w.state.unlocks.append("feature:prestige")
	ps.simulate_offline(2.0)
	assert_true(w.state.unlocks.has("feature:trials"))
	assert_true(ps.layer_visible("trials"))


func test_prove_motivi_di_rifiuto() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.can_start_trial("trial_inesistente", 1), "UI_TRIALS_REASON_INVALID")
	assert_eq(ps.can_start_trial("trial_fasting", 0), "UI_TRIALS_REASON_INVALID")
	assert_eq(ps.can_start_trial("trial_fasting", 6), "UI_TRIALS_REASON_INVALID")
	assert_eq(ps.can_start_trial("trial_fasting", 2), "UI_TRIALS_REASON_ORDER", "i gradi si fanno in ordine")
	ps.state.trials["trial_fasting"] = 1
	assert_eq(ps.can_start_trial("trial_fasting", 1), "UI_TRIALS_REASON_DONE")
	assert_eq(ps.can_start_trial("trial_fasting", 2), "")
	assert_false(ps.start_trial("trial_fasting", 2).is_empty())
	assert_eq(ps.can_start_trial("trial_glass", 1), "UI_TRIALS_REASON_ACTIVE")


func test_prove_regole_risolte() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.trial_rules("trial_blunt", 1).max_gear_tier, 1, "zona 2: tier 2 - 1")
	assert_eq(ps.trial_rules("trial_blunt", 5).max_gear_tier, 9, "zona 10: tier 10 - 1")
	assert_true(ps.trial_rules("trial_fasting", 1).no_food)
	assert_eq(ps.trial_target("trial_fasting", 1), {"kind": "boss", "id": BOSS_Z2, "zone": "saltreach"})
	assert_eq(ps.trial_target("trial_marathon", 1).kind, "dungeon")
	assert_eq(ps.trial_target("trial_marathon", 1).id, "wreck_of_fortune")
	assert_eq(ps.trial_target("trial_fasting", 9), {})
	# ogni grado di ogni Prova ha un bersaglio nei dati
	for tid in ps.trial_ids():
		for t in range(1, ps.trial_tier_count(tid) + 1):
			assert_false(ps.trial_target(tid, t).is_empty(), "bersaglio di %s grado %d" % [tid, t])


func test_prove_anteprima_obbligatoria() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.state["era_max"] = 3
	ps.set_era(3)
	var p := ps.preview_trial("trial_race", 1)
	assert_true(p.ok)
	assert_eq(p.rules[0].key, "UI_TRIALS_RULE_TIME_LIMIT_S")
	assert_eq(int(p.rules[0].params.n), 60)
	assert_eq(p.lose[0].key, "UI_TRIALS_LOSE_ERA", "si lascia l'Era per la Prova: lo dice")
	assert_eq(p.keep[0].key, "UI_TRIALS_KEEP_ALL")
	assert_eq(int(p.reward_dust), 3)
	assert_eq(p.reward_modifiers[0].key, "combat_haste_pct")
	assert_eq(p.target.id, BOSS_Z2)
	assert_eq(ps.era_current(), 3, "l'anteprima non cambia nulla")
	assert_false(ps.is_trial_active())
	# anteprima = ciò che applica start_trial
	var s := ps.start_trial("trial_race", 1)
	assert_eq(s.target, p.target)
	assert_eq(s.reward_dust, p.reward_dust)


# ------------------------------------------------------------------ PROVE: ciclo di vita

func test_prova_vinta_con_l_uccisione_del_boss() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.state["era_max"] = 2
	ps.set_era(2)
	assert_false(ps.start_trial("trial_fasting", 1).is_empty())
	assert_eq(ps.era_current(), 1, "si combatte nell'Era I")
	assert_true(ps.is_trial_active())
	assert_true(w.rec.important.has("trial_start"))
	_kill(w, "armored_crab")
	assert_true(ps.is_trial_active(), "un altro mostro non conta")
	_kill(w, BOSS_Z2)
	assert_false(ps.is_trial_active())
	assert_eq(ps.era_current(), 2, "l'Era scelta torna")
	assert_eq(ps.trial_tiers_done("trial_fasting"), 1)
	assert_eq(w.bank.currency("stardust"), 3)
	assert_almost_eq(w.stack.total_add("food_heal_pct", []), 1.0, 1e-9, "bonus permanente via Modifiers")
	assert_true(w.rec.important.has("trial"))
	var ch := false
	for o in w.rec.objectives:
		if o[0] == "challenge":
			ch = true
	assert_true(ch, "objective_event('challenge')")


func test_prova_gradi_successivi_sommano_bonus_e_polvere_una_volta() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_silence", 1)
	_kill(w, BOSS_Z2)
	var t2 := ps.trial_target("trial_silence", 2)
	ps.start_trial("trial_silence", 2)
	_kill(w, str(t2.id))
	assert_eq(ps.trial_tiers_done("trial_silence"), 2)
	assert_eq(w.bank.currency("stardust"), 3 + 6)
	assert_almost_eq(w.stack.total_add("combat_dmg_pct", []), 2.0, 1e-9)
	# rifarlo non è possibile: nessuna Polvere ripetibile
	assert_eq(ps.can_start_trial("trial_silence", 1), "UI_TRIALS_REASON_DONE")
	_kill(w, BOSS_Z2)
	assert_eq(w.bank.currency("stardust"), 9, "l'uccisione fuori da una Prova non paga")


func test_prova_morte_la_boccia_senza_perdere_niente() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.state["era_max"] = 2
	ps.set_era(2)
	ps.start_trial("trial_glass", 1)
	assert_almost_eq(w.stack.total_add("combat_hp_pct", []), -75.0, 1e-9, "Vetro: -75% vita (modificatore temporaneo)")
	w.bus.player_died.emit(BOSS_Z2)
	assert_false(ps.is_trial_active())
	assert_eq(ps.era_current(), 2)
	assert_eq(ps.trial_tiers_done("trial_glass"), 0)
	assert_eq(w.bank.currency("stardust"), 0)
	assert_almost_eq(w.stack.total_add("combat_hp_pct", []), 0.0, 1e-9, "il modificatore temporaneo sparisce")
	assert_true(w.rec.important.has("trial_fail"))
	_kill(w, BOSS_Z2)
	assert_eq(ps.trial_tiers_done("trial_glass"), 0, "dopo il fallimento l'uccisione non conta")


func test_prova_vetro_vinta_toglie_il_malus_e_da_il_bonus() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_glass", 1)
	_kill(w, BOSS_Z2)
	assert_almost_eq(w.stack.total_add("combat_hp_pct", []), 1.0, 1e-9, "+1% vita permanente, niente più -75%")


func test_prova_abbandono() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	assert_false(ps.abandon_trial(), "niente da abbandonare")
	ps.start_trial("trial_fasting", 1)
	assert_true(ps.abandon_trial())
	assert_false(ps.is_trial_active())
	assert_eq(w.bank.currency("stardust"), 0)
	assert_eq(ps.trial_tiers_done("trial_fasting"), 0)


func test_prova_digiuno_mangiare_fa_fallire() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_fasting", 1)
	w.bus.item_removed.emit("log_pine", 3)           # vendere/consumare altro non conta
	assert_true(ps.is_trial_active())
	w.bus.item_removed.emit(FOOD, 1)                 # il Deposito emette item_removed quando si mangia
	assert_false(ps.is_trial_active(), "mangiare = fallire")
	# un'altra Prova non è toccata dal cibo
	ps.start_trial("trial_silence", 1)
	w.bus.item_removed.emit(FOOD, 1)
	assert_true(ps.is_trial_active())


func test_prova_a_tempo() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_race", 1)
	_engage(w)
	for i in 590:
		ps.tick(0.1)                                  # 59 s
	assert_true(ps.is_trial_active())
	for i in 20:
		ps.tick(0.1)                                  # 61 s
	assert_false(ps.is_trial_active(), "tempo scaduto")
	assert_eq(ps.era_current(), 1)
	# l'offline fa scadere la Prova a tempo, ma non le altre
	ps.start_trial("trial_race", 1)
	ps.simulate_offline(3600.0)
	assert_false(ps.is_trial_active())
	ps.start_trial("trial_silence", 1)
	ps.simulate_offline(3600.0)
	assert_true(ps.is_trial_active())


func test_prova_a_tempo_parte_dal_boss_in_campo() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_race", 1)
	assert_false(ps.trial_engaged(), "il boss non è ancora comparso")
	w.state["activity"] = {"type": "combat", "mode": "zone", "enemy": {"id": "un_altro_mostro"}}
	for i in 1200:
		ps.tick(0.1)                                  # 120 s di cammino e mostri qualunque: il tempo non scorre
	assert_true(ps.is_trial_active(), "il cronometro non è ancora partito")
	_engage(w)
	ps.tick(0.1)
	assert_true(ps.trial_engaged(), "boss in campo: si parte")
	for i in 580:
		ps.tick(0.1)
	assert_true(ps.is_trial_active(), "58 s dal boss: ancora in tempo")
	for i in 40:
		ps.tick(0.1)
	assert_false(ps.is_trial_active(), "oltre 60 s dal comparire del boss: scaduta")


func test_prova_regole_per_grado() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	assert_eq(ps.trial_rules("trial_race", 1).time_limit_s, 60)
	assert_eq(ps.trial_rules("trial_race", 3).time_limit_s, 90, "il tempo cresce con i gradi alti (balance_sim §11)")
	assert_true(ps.trial_rules("trial_fasting", 3).no_food)
	assert_false(ps.trial_rules("trial_fasting", 4).no_food)
	assert_eq(ps.trial_rules("trial_fasting", 4).max_food, 3)
	assert_eq(ps.trial_rules("trial_fasting", 5).max_food, 6)
	# 90 s per il grado III: a 70 s la Prova è ancora in corso
	w.state.prestige.trials["trial_race"] = 2
	ps.start_trial("trial_race", 3)
	_engage(w)
	for i in 700:
		ps.tick(0.1)
	assert_true(ps.is_trial_active())
	for i in 250:
		ps.tick(0.1)
	assert_false(ps.is_trial_active())


func test_prova_digiuno_porzioni_concesse_ai_gradi_alti() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	w.state.prestige.trials["trial_fasting"] = 3
	var p := ps.start_trial("trial_fasting", 4)
	assert_false(p.is_empty())
	assert_eq(p.rules[0].key, "UI_TRIALS_RULE_MAX_FOOD")
	assert_eq(int(p.rules[0].params.n), 3)
	for i in 3:
		w.bus.item_removed.emit(FOOD, 1)
	assert_true(ps.is_trial_active(), "tre porzioni sono concesse")
	assert_eq(int(ps.trial_active().food_eaten), 3)
	w.bus.item_removed.emit(FOOD, 1)
	assert_false(ps.is_trial_active(), "la quarta no")


func test_prova_vinta_in_tempo() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_race", 1)
	for i in 300:
		ps.tick(0.1)
	_kill(w, BOSS_Z2)
	assert_eq(ps.trial_tiers_done("trial_race"), 1)


func test_prova_regole_note_al_combattimento_in_on_trial_won() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_silence", 1)
	var r := ps.on_trial_won({"used_abilities": true})
	assert_false(r.ok)
	assert_eq(r.reason, "UI_TRIALS_FAIL_ABILITIES")
	assert_false(ps.is_trial_active())
	ps.start_trial("trial_fasting", 1)
	assert_eq(ps.on_trial_won({"ate_food": true}).reason, "UI_TRIALS_FAIL_FOOD")
	ps.start_trial("trial_race", 1)
	assert_eq(ps.on_trial_won({"elapsed_s": 61.0}).reason, "UI_TRIALS_FAIL_TIME")
	ps.start_trial("trial_marathon", 1)
	assert_eq(ps.on_trial_won({"retreated": true}).reason, "UI_TRIALS_FAIL_RETREAT")
	assert_eq(ps.on_trial_won({}).reason, "UI_TRIALS_REASON_NONE", "nessuna Prova in corso")
	ps.start_trial("trial_fasting", 1)
	var ok := ps.on_trial_won({})
	assert_true(ok.ok)
	assert_eq(int(ok.dust), 3)
	assert_false(ps.on_trial_won({}).ok, "una seconda chiamata non paga due volte")
	assert_eq(w.bank.currency("stardust"), 3)


func test_prova_maratona_si_vince_col_dungeon() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	ps.start_trial("trial_marathon", 1)
	_kill(w, BOSS_Z2)
	assert_true(ps.is_trial_active(), "il boss di zona non basta")
	w.bus.objective_event.emit("complete_dungeon", {"dungeon": "cursed_granary", "qty": 1})
	assert_true(ps.is_trial_active(), "un altro dungeon non conta")
	w.bus.objective_event.emit("complete_dungeon", {"dungeon": "wreck_of_fortune", "qty": 1})
	assert_eq(ps.trial_tiers_done("trial_marathon"), 1)
	assert_almost_eq(w.stack.total_add("dungeon_loot_pct", ["all"]), 1.0, 1e-9)


func test_prova_equipaggiamento() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	# Lama Spuntata grado I: solo tier 1
	w.state.equipment["weapon"] = {"def": "sword_cobalt"}
	var rp := {}
	assert_eq(ps.can_start_trial("trial_blunt", 1, rp), "UI_TRIALS_REASON_GEAR_TIER")
	assert_eq(int(rp.tier), 1)
	w.state.equipment["weapon"] = {"def": "sword_copper"}
	assert_eq(ps.can_start_trial("trial_blunt", 1), "")
	# durante la Prova cambiare equipaggiamento fa fallire alla vittoria
	ps.start_trial("trial_blunt", 1)
	w.state.equipment["weapon"] = {"def": "sword_cobalt"}
	_kill(w, BOSS_Z2)
	assert_eq(ps.trial_tiers_done("trial_blunt"), 0, "equipaggiamento troppo buono")
	assert_false(ps.is_trial_active())
	# Senza Armatura: pezzi d'armatura vietati, arma e accessori no
	w.state.equipment = {"weapon": {"def": "sword_cobalt"}}
	assert_eq(ps.can_start_trial("trial_naked", 1), "")
	w.state.equipment["helm"] = {"def": "plate_helm_copper"}
	assert_eq(ps.can_start_trial("trial_naked", 1), "UI_TRIALS_REASON_GEAR_ARMOR")


func test_prove_completare_tutto_da_l_impresa() -> void:
	var w := _world()
	_open_trials(w)
	var ps: PrestigeSystem = w.ps
	for tid in ps.trial_ids():
		w.state.prestige.trials[tid] = ps.trial_tier_count(tid)
	w.state.prestige.trials["trial_fasting"] = ps.trial_tier_count("trial_fasting") - 1
	var t := ps.trial_target("trial_fasting", 5)
	assert_false(ps.start_trial("trial_fasting", 5).is_empty())
	_kill(w, str(t.id))
	var all_max := false
	for o in w.rec.objectives:
		if o[0] == "challenge_all_max":
			all_max = true
	assert_true(all_max, "challenge_all_max quando tutte le Prove sono al grado V")


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_senza_campi_nuovi_e_round_trip() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var old := {"stardust": 0, "constellations": {}, "era_max": 3, "era_current": 2, "trials": {}}
	ps.from_state(old)
	assert_eq(old.era_kills, {})
	assert_eq(old.trial_active, {})
	# round-trip JSON (come il salvataggio vero) con Prova in corso
	_open_trials(w)
	var w2 := _world()
	w2.ps.on_warden_defeated(1)
	w2.ps.on_warden_defeated(2)
	w2.ps.on_warden_defeated(2)
	w2.state.quests.done.append("main_c5_q5")
	w2.ps.set_era(3)
	w2.ps.state.trials["trial_fasting"] = 1
	assert_false(w2.ps.start_trial("trial_fasting", 2).is_empty())
	var json := JSON.stringify(w2.ps.to_state())
	var data: Variant = JSON.parse_string(json)
	assert_eq(SaveCodec.normalize({"prestige": data}, PackedStringArray(["prestige.era_kills.*", "prestige.trials.*", "prestige.trial_active.tier", "prestige.trial_active.era_restore", "prestige.era_max"])).size(), 0)
	var w3 := _world()
	w3.ps.from_state(data)
	assert_eq(w3.ps.era_max(), 3)
	assert_eq(w3.ps.warden_kills(2), 2)
	assert_eq(w3.ps.trial_tiers_done("trial_fasting"), 1)
	assert_true(w3.ps.is_trial_active())
	assert_eq(w3.ps.trial_active().id, "trial_fasting")
	assert_eq(w3.ps.trial_active().tier, 2)
	assert_eq(w3.ps.era_current(), 1, "Era I durante la Prova")
	assert_true(w3.ps.abandon_trial())
	assert_eq(w3.ps.era_current(), 3, "l'Era salvata torna dopo il caricamento")
	assert_almost_eq(w3.stack.total_add("food_heal_pct", []), 1.0, 1e-9, "bonus delle Prove ricostruiti dal caricamento")


func test_salvataggio_prova_incoerente_viene_chiusa_con_l_era_restituita() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var bad: Dictionary = ps.default_state()
	bad["era_max"] = 4
	bad["era_current"] = 1
	bad["trial_active"] = {"id": "trial_che_non_esiste", "tier": 1, "started_s": 0.0, "era_restore": 3}
	ps.from_state(bad)
	assert_false(ps.is_trial_active())
	assert_eq(ps.era_current(), 3)
	var bad2: Dictionary = ps.default_state()
	bad2["era_max"] = 2
	bad2["trial_active"] = {"id": "trial_fasting", "tier": 4, "started_s": 0.0, "era_restore": 2}     # grado non in ordine
	bad2["trials"] = {"trial_fasting": 1, "trial_fantasma": 3}
	ps.from_state(bad2)
	assert_false(ps.is_trial_active())
	assert_eq(ps.era_current(), 2)
	assert_false(bad2.trials.has("trial_fantasma"), "Prova rimossa dai dati: ignorata")


func test_salvataggio_gradi_oltre_il_massimo_vengono_limitati() -> void:
	var w := _world()
	var ps: PrestigeSystem = w.ps
	var s: Dictionary = ps.default_state()
	s["trials"] = {"trial_fasting": 99}
	ps.from_state(s)
	assert_eq(ps.trial_tiers_done("trial_fasting"), 5)


# ------------------------------------------------------------------ dati

func test_dati_delle_prove_coerenti() -> void:
	assert_eq(DataRegistry.table("trials").size(), 8)
	var rules: Dictionary = DataRegistry.rules("era_rules")
	assert_true(rules.has("stardust_repeat_pct"), "la ripetizione del Custode è un dato, non un numero nel codice")
	assert_eq(float(rules.stardust_repeat_pct), 0.0)
	assert_eq(DataRegistry.constants.prestige.trials.era, 1)
	assert_true(DataRegistry.constants.prestige.trials.armor_slots.has("helm"))
	for t in DataRegistry.table("trials"):
		assert_eq((t.tiers as Array).size(), 5)
		var n := 0
		for tier in t.tiers:
			n += int(tier.reward.stardust)
			for m in tier.reward.modifiers:
				assert_true(DataRegistry.table("modifier_catalog").any(func(e: Dictionary) -> bool: return e.family == str(m.key).split(":")[0]), "modificatore noto: " + str(m.key))
		assert_eq(n, 45, "3+6+9+12+15 Polvere per Prova")


# ------------------------------------------------------------------ schermata

func test_schermata_ere_e_prove() -> void:
	var old_dir := SaveService.save_dir
	SaveService.save_dir = "user://test_eras_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 9))
	var ps := Game.system("prestige") as PrestigeSystem
	GameState.data.unlocks.append("feature:prestige")
	GameState.data.quests.done.append("main_c5_q5")
	GameState.data.unlocks.append("zone:saltreach")
	GameState.data.skills.hero.level = 30
	var e := ScreenRegistry.get_entry("prestige")
	var scr: GameScreen = (load(e.scene) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	await wait_process_frames(1)
	scr.refresh()
	assert_true(scr._tab_ids.has("trials"), "le Prove compaiono dopo il Capitolo 5")
	assert_false(scr._tab_ids.has("era"), "l'Era compare solo dopo il primo Custode")
	ps.on_warden_defeated(1)
	await wait_process_frames(1)
	scr.refresh()
	assert_true(scr._tab_ids.has("era"))
	# Ere: anteprima + cambio
	scr._on_era_spin(2.0)
	scr.refresh()
	assert_true(scr._era_btn.visible, "Era II sbloccata: si può passare")
	scr._on_era_switch()
	assert_eq(ps.era_current(), 2)
	# Prove: scelta, anteprima, conferma a due passaggi
	scr._select_trial("trial_silence")
	scr.refresh()
	assert_true(scr._trial_start.visible)
	assert_eq(Game.system("combat").in_combat(), false)
	scr._on_trial_start()
	assert_false(ps.is_trial_active(), "primo clic: arma soltanto")
	assert_true(scr.is_armed("trial_start"))
	var nav: Array = []
	var on_nav := func(id: String, _p: Dictionary) -> void: nav.append(id)
	EventBus.screen_requested.connect(on_nav)
	scr._on_trial_start()
	EventBus.screen_requested.disconnect(on_nav)
	assert_true(ps.is_trial_active(), "secondo clic: la Prova parte")
	assert_eq(ps.era_current(), 1)
	assert_true(Game.system("combat").in_combat(), "e parte anche lo scontro col boss")
	assert_eq(nav, ["combat"], "dopo l'avvio si va alla schermata Combattimento")
	scr.refresh()
	assert_true(scr._trial_abandon.visible)
	scr._on_trial_abandon()
	assert_false(ps.is_trial_active())
	assert_eq(ps.era_current(), 2)
	Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = old_dir
	SaveService.autosave_enabled = true
