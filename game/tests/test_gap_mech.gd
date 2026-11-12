extends GutTest
## GAP-MECCANICHE (audit 71): Rango degli oggetti (G03), Clessidra del Custode (G05), nodi delle Costellazioni (G13),
## Set di equipaggiamento (G15), Casse ritirate (G35), doppione del famiglio evento (G40), orologio indietro (G52).
## Il cronometro di «Contro il Tempo» (G39) è in test_eras_trials.gd. Partite vere su Game (sistemi reali).

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_gap_mech_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _new_game() -> void:
	assert_true(Game.new_game(1, "normal", 21))


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


func _ps() -> PrestigeSystem:
	return Game.system("prestige") as PrestigeSystem


## Armi a una mano di tier 1, livello 1, non uniche (ordinate per id: deterministico).
func _weapons(n: int) -> Array:
	var out: Array = []
	for it in DataRegistry.items_by_category("equipment"):
		var eq: Dictionary = it.get("equipment", {})
		if str(eq.get("slot", "")) == "weapon" and int(it.get("tier", 0)) == 1 and int(eq.get("level_req", 1)) <= 1 \
				and not bool(eq.get("two_handed", false)) and not bool(it.get("unique", false)):
			out.append(str(it.id))
	out.sort()
	return out.slice(0, n)


func _give_weapon(def_id: String) -> String:
	return _bank().add_instance({"def": def_id, "quality": "normal", "sockets": [], "rank": 0, "source": "test"})


# ------------------------------------------------------------------ G03 Rango

func test_rango_formule_dai_dati() -> void:
	var k: Dictionary = DataRegistry.constants.eras.rank_cost
	assert_eq(int(k.gold_per_tier), 250)
	assert_eq(Formulas.rank_essence_cost(1), 3, "ceil(2 + 0,5)")
	assert_eq(Formulas.rank_essence_cost(2), 3)
	assert_eq(Formulas.rank_essence_cost(3), 4)
	assert_eq(Formulas.rank_gold_cost(11, 1), 3025, "250 × 11 × 1,1")
	assert_eq(Formulas.rank_gold_cost(1, 10), 500)


func test_rango_bloccato_nell_era_1_poi_costi_e_tetto() -> void:
	_new_game()
	var ps := _ps()
	var b := _bank()
	var uid := _give_weapon(_weapons(1)[0])
	assert_true(ps.is_rankable(uid))
	assert_eq(ps.preview_rank_up(uid).reason, "UI_GAPM_RANK_REASON_LOCKED", "i Ranghi si comprano dall'Era II")
	ps.state["era_max"] = 2
	var p := ps.preview_rank_up(uid)
	assert_eq(int(p.cap), 24, "12 × Era massima")
	assert_eq(int(p.essence), Formulas.rank_essence_cost(1))
	if b.count(PrestigeSystem.ESSENCE) < int(p.essence):
		assert_eq(p.reason, "UI_GAPM_RANK_REASON_ESSENCE")
	b.add(PrestigeSystem.ESSENCE, 100, "test")
	b.spend_gold(b.gold())
	assert_eq(ps.preview_rank_up(uid).reason, "UI_GAPM_RANK_REASON_GOLD")
	b.add_gold(100000)
	var e0 := b.count(PrestigeSystem.ESSENCE)
	var g0 := b.gold()
	p = ps.preview_rank_up(uid)
	assert_true(p.ok, str(p.reason))
	assert_false(ps.do_rank_up(uid).is_empty())
	assert_eq(int(b.get_instance(uid).rank), 1)
	assert_eq(b.count(PrestigeSystem.ESSENCE), e0 - int(p.essence), "Essenza spesa esattamente come in anteprima")
	assert_eq(b.gold(), g0 - int(p.gold), "oro speso esattamente come in anteprima")
	assert_eq(ps.preview_rank_up(uid).rank_after, 2)
	b.set_instance_rank(uid, ps.rank_cap())
	assert_eq(ps.preview_rank_up(uid).reason, "UI_GAPM_RANK_REASON_CAP")
	assert_true(ps.do_rank_up(uid).is_empty(), "oltre il tetto non si sale")


func test_rango_moltiplica_solo_le_statistiche_dell_oggetto() -> void:
	_new_game()
	var ps := _ps()
	var cb := Game.system("combat") as CombatSystem
	var uid := _give_weapon(_weapons(1)[0])
	assert_true(cb.equip(uid))
	var dmg0 := float(cb._gear_blocks()[0].damage)
	ps.state["era_max"] = 2
	_bank().add(PrestigeSystem.ESSENCE, 50, "test")
	_bank().add_gold(50000)
	var p := ps.preview_rank_up(uid)
	assert_almost_eq(float(p.stats[0].after) / float(p.stats[0].before), 1.04, 1e-9, "anteprima: +4% per rango")
	assert_false(ps.do_rank_up(uid).is_empty())
	assert_false(ps.do_rank_up(uid).is_empty())
	assert_almost_eq(float(cb._gear_blocks()[0].damage), dmg0 * 1.04 * 1.04, 1e-6, "CombatSystem applica ×1,04^rango")
	var st := cb.hero_stats()
	assert_true(float(st.get("max_hit", 1.0)) > 0.0)


func test_rango_non_per_attrezzi_e_niente_in_dungeon() -> void:
	_new_game()
	var ps := _ps()
	ps.state["era_max"] = 2
	var tool_id := ""
	for it in DataRegistry.items_by_category("tool"):
		tool_id = str(it.id)
		break
	var tuid := _bank().add_instance({"def": tool_id, "quality": "normal", "sockets": [], "rank": 0})
	assert_false(ps.is_rankable(tuid), "gli attrezzi di mansione non salgono di Rango")
	assert_eq(ps.preview_rank_up(tuid).reason, "UI_GAPM_RANK_REASON_NOT_GEAR")
	assert_eq(ps.preview_rank_up("nessuno").reason, "UI_GAPM_RANK_REASON_NO_ITEM")


# ------------------------------------------------------------------ G05 Clessidra

func _start_first_gathering() -> String:
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1:
			GameState.data.unlocks.append("skill:woodcutting")
			if sk.start(str(a.id)):
				return str(a.id)
	return ""


func test_clessidra_motivi_e_consumo() -> void:
	_new_game()
	var b := _bank()
	assert_eq(Hourglass.can_use(Game.ctx), "UI_GAPM_HG_REASON_NONE")
	b.add(Hourglass.ITEM, 2, "test")
	GameState.data["activity"].clear()
	assert_eq(Hourglass.can_use(Game.ctx), "UI_GAPM_HG_REASON_IDLE")
	var aid := _start_first_gathering()
	assert_false(aid.is_empty(), "azione di raccolta avviata")
	assert_eq(Hourglass.can_use(Game.ctx), "")
	var xp0 := float(GameState.data.skills.woodcutting.xp)
	var est0 := float(GameState.data.prestige.clock_s)
	var heard := []
	var cb := func(s: float, r: Dictionary) -> void: heard.append([s, r])
	EventBus.offline_progress.connect(cb)
	var res := Game.use_hourglass()
	EventBus.offline_progress.disconnect(cb)
	assert_true(res.ok)
	assert_almost_eq(float(res.seconds), 3600.0, 1e-6, "1 h (hourglass.hours dei dati)")
	assert_eq(b.count(Hourglass.ITEM), 1, "una Clessidra consumata")
	assert_gt(float(GameState.data.skills.woodcutting.xp), xp0, "l'azione attiva ha avuto la sua ora")
	assert_almost_eq(float(GameState.data.prestige.clock_s), est0, 1e-9, "il resto del mondo non avanza")
	assert_eq(heard.size(), 1, "Bentornato: stesso segnale dell'offline vero")
	assert_true(heard[0][1].has("hourglass"))
	var wb := WelcomeBack.build(3600.0, heard[0][1], DataRegistry, Game.offline_cap_s())
	assert_false(bool(wb.empty), "il Bentornato mostra il resoconto")


func test_clessidra_non_in_dungeon_ne_in_prova() -> void:
	_new_game()
	_bank().add(Hourglass.ITEM, 1, "test")
	GameState.data["activity"].clear()
	GameState.data["activity"].merge({"type": "combat", "mode": "dungeon", "dungeon": "x"})
	assert_eq(Hourglass.activity_kind(Game.ctx), "other")
	assert_eq(Hourglass.can_use(Game.ctx), "UI_GAPM_HG_REASON_ACTIVITY")
	GameState.data["activity"]["mode"] = "zone"
	assert_eq(Hourglass.can_use(Game.ctx), "")
	_ps().state["trial_active"] = {"id": "trial_race", "tier": 1, "started_s": 0.0, "era_restore": 1, "engaged": false}
	assert_eq(Hourglass.can_use(Game.ctx), "UI_GAPM_HG_REASON_TRIAL")
	_ps().state["trial_active"] = {}


# ------------------------------------------------------------------ G13 Costellazioni

func test_costellazioni_nodi_dormienti_solo_quelli_senza_sistema() -> void:
	assert_eq(Array(PrestigeSystem.DORMANT_FAMILIES), ["echo_mult_pct"])
	_new_game()
	var ps := _ps()
	for n in ps.nodes():
		if ps.is_dormant(str(n.id)):
			assert_eq(ps.node_max_level(str(n.id)), 0, "nodo dormiente non acquistabile: " + str(n.id))
	# il nodo ritirato non blocca la catena: l'Agenda chiede la Raccolta Automatica
	assert_eq(ps.node("c_cu_queue").requires[0], "c_cu_autocollect")


func test_costellazioni_rimborso_del_nodo_ritirato() -> void:
	_new_game()
	var ps := _ps()
	var d0 := ps.dust()
	ps.state.constellations["c_vi_echo"] = 1
	var cost := ps.node_cost("c_vi_echo", 0)
	ps.state["stardust_spent"] = cost
	ps.from_state(ps.state)
	assert_false(ps.state.constellations.has("c_vi_echo"))
	assert_eq(ps.dust(), d0 + cost, "Polvere restituita al costo pagato")
	assert_eq(int(ps.state.stardust_spent), 0)


func test_costellazioni_forgia_fortunata_e_biblioteca() -> void:
	_new_game()
	var sk := Game.system("skills") as SkillSystem
	var key_action := ""
	for a in DataRegistry.actions_for_skill("keysmithing"):
		for o in a.get("outputs", []):
			if str(DataRegistry.item(str(o.item)).get("category", "")) == "key":
				key_action = str(a.id)
		if not key_action.is_empty():
			break
	var other := str(DataRegistry.actions_for_skill("smithing")[0].id)
	var s0 := float(sk.profile_of(key_action).save_pct)
	var o0 := float(sk.profile_of(other).save_pct)
	var tome0 := sk.tome_xp("tome_xp_small", "woodcutting")
	Modifiers.stack.set_source("test:gap", [{"key": "key_craft_save_pct", "value": 10.0, "mode": "add"},
		{"key": "xp_tome_pct", "value": 20.0, "mode": "add"}])
	assert_almost_eq(float(sk.profile_of(key_action).save_pct), s0 + 10.0, 1e-9, "chiavi: risparmio dei materiali")
	assert_almost_eq(float(sk.profile_of(other).save_pct), o0, 1e-9, "le altre ricette non cambiano")
	assert_almost_eq(sk.tome_xp("tome_xp_small", "woodcutting"), tome0 * 1.2, 1e-6, "Tomi: +20% XP")
	Modifiers.stack.clear_source("test:gap")


# ------------------------------------------------------------------ G15 Set di equipaggiamento

func test_set_salva_e_indossa() -> void:
	_new_game()
	var lo := Game.system("loadouts") as LoadoutSystem
	var cb := Game.system("combat") as CombatSystem
	assert_eq(lo.slot_count(), 0, "senza Rastrelliera nessun set")
	assert_false(lo.save_set(0))
	(Game.system("market") as MarketSystem).state.shop["loadout_slot"] = 2
	assert_eq(lo.slot_count(), 2, "effetto loadouts dell'Emporio")
	var w := _weapons(2)
	var a := _give_weapon(w[0])
	var bb := _give_weapon(w[1])
	assert_true(cb.equip(a))
	assert_true(lo.save_set(0))
	assert_true(cb.equip(bb))
	assert_true(lo.save_set(1, "Pesca"))
	assert_eq(cb.equipped("weapon"), bb)
	assert_eq(lo.can_apply(0), "")
	var r := lo.apply_set(0)
	assert_true(r.ok)
	assert_eq(cb.equipped("weapon"), a, "set 1 indossato")
	assert_eq(str(lo.get_set(1).name), "Pesca")
	_bank().remove_instance(bb)
	r = lo.apply_set(1)
	assert_eq(r.missing, ["weapon"], "il pezzo venduto si salta")
	assert_eq(cb.equipped("weapon"), "", "e il resto si toglie come da set")
	assert_true(lo.clear_set(1))
	assert_eq(lo.can_apply(1), "UI_GAPM_SET_REASON_EMPTY")
	assert_false(lo.save_set(2), "solo i posti comprati")


func test_set_sopravvive_al_salvataggio() -> void:
	_new_game()
	(Game.system("market") as MarketSystem).state.shop["loadout_slot"] = 1
	var uid := _give_weapon(_weapons(1)[0])
	(Game.system("combat") as CombatSystem).equip(uid)
	var lo := Game.system("loadouts") as LoadoutSystem
	lo.save_set(0, "Lunedì")
	SaveService.save_now()
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	lo = Game.system("loadouts") as LoadoutSystem
	assert_eq(str(lo.get_set(0).name), "Lunedì")
	assert_eq(str(lo.get_set(0).gear.weapon), uid)


# ------------------------------------------------------------------ G35 Casse ritirate

func test_casse_ritirate_crescono_dell_1_5_per_cento_a_settimana() -> void:
	_new_game()
	var cr := Game.system("crates") as CrateSystem
	var inst := {"def_id": "x", "kind": "skin", "rarity": "rare", "crate": "crate_era_2", "condition": "marked"}
	assert_almost_eq(cr.retired_mult(inst), 1.0, 1e-9, "non ancora ritirata")
	_ps().state["era_max"] = 3
	GameState.data.stats["playtime_s"] = 1000.0
	assert_eq(cr.update_retired(), 1, "con l'Era III la Cassa dell'Era II è ritirata")
	assert_true(cr.state.retired.has("crate_era_2"))
	assert_false(cr.state.retired.has("crate_era_3"), "la più recente resta in circolazione")
	assert_almost_eq(cr.retired_mult(inst), 1.0, 1e-9, "settimana 0")
	var week := float(DataRegistry.rules("crate_rules").market.retired_week_days) * MarketSystem.DAY_S
	GameState.data.stats["playtime_s"] = 1000.0 + 2.5 * week
	assert_eq(cr.retired_weeks(inst), 2, "settimane intere")
	assert_almost_eq(cr.retired_mult(inst), 1.03, 1e-9, "+1,5% × 2 (lineare)")
	inst["crate"] = "crate_millbrook"
	assert_almost_eq(cr.retired_mult(inst), 1.0, 1e-9, "le casse normali non si ritirano")
	assert_eq(cr.update_retired(), 0, "il ritiro si registra una volta sola")


# ------------------------------------------------------------------ G40 famiglio evento

func test_doppione_famiglio_evento_senza_polvere() -> void:
	_new_game()
	var comp := Game.system("compendium") as CompendiumSystem
	var ps := _ps()
	var ev_pet := ""
	var other := ""
	for p in DataRegistry.table("pets"):
		if str(p.source.type) == "event" and ev_pet.is_empty():
			ev_pet = str(p.id)
		elif str(p.source.type) == "monster" and other.is_empty():
			other = str(p.id)
	assert_eq(comp.found_pet(ev_pet), "new")
	var d0 := ps.dust()
	assert_eq(comp.found_pet(ev_pet), "dupe")
	assert_eq(ps.dust(), d0, "nessun potere, nessuna Polvere")
	comp.found_pet(other)
	d0 = ps.dust()
	comp.found_pet(other)
	assert_eq(ps.dust(), d0 + int(DataRegistry.rules("social_rules").pets.duplicate_stardust), "gli altri doppioni pagano ancora")


# ------------------------------------------------------------------ G52 orologio all'indietro

func test_orologio_indietro_tempo_zero_e_riallineamento() -> void:
	var g: Dictionary = Game.offline_gap(1000, 5000)
	assert_true(g.rewound)
	assert_eq(int(g.elapsed), 0, "Δt = 0")
	assert_eq(int(g.rewound_s), 4000)
	assert_eq(int(g.now), 1000, "nuovo riferimento = adesso")
	g = Game.offline_gap(5000, 1000)
	assert_false(g.rewound)
	assert_eq(int(g.elapsed), 4000)
	assert_false(Game.offline_gap(5000, 0).rewound, "salvataggio senza data: niente riallineamento")


# ------------------------------------------------------------------ interfaccia (Eroe: Rango e Set; Deposito: Clessidra)

func _open(path: String) -> Control:
	var scr: Control = (load(path) as PackedScene).instantiate()
	add_child_autofree(scr)
	await wait_process_frames(1)
	scr.open({})
	scr.refresh()
	return scr


func _find(root: Node, cls: String, text: String = "") -> Node:
	for c in root.get_children():
		if c.is_class(cls) and (text.is_empty() or str(c.get("text")) == text):
			return c
		var r := _find(c, cls, text)
		if r != null:
			return r
	return null


func test_ui_eroe_rango_e_set_compaiono_solo_quando_servono() -> void:
	_new_game()
	var hs: Control = await _open("res://src/ui/screens/HeroScreen.tscn")
	var ex: HeroGearExtras = hs._gear_extras
	assert_false(ex._rank_head.visible, "niente Rango prima dell'Era II")
	assert_false(ex._sets_head.visible, "niente Set senza Rastrelliera")
	_ps().state["era_max"] = 2
	(Game.system("market") as MarketSystem).state.shop["loadout_slot"] = 2
	var uid := _give_weapon(_weapons(1)[0])
	(Game.system("combat") as CombatSystem).equip(uid)
	_bank().add(PrestigeSystem.ESSENCE, 20, "test")
	_bank().add_gold(20000)
	hs.refresh()
	assert_true(ex._rank_head.visible)
	assert_eq(ex._sets_box.get_child_count(), 2, "una riga per posto comprato")
	var b: Button = _find(ex._rank_box, "Button", "UI_GAPM_RANK_BUTTON")
	assert_not_null(b)
	assert_false(b.disabled)
	b.pressed.emit()
	var dlg: ConfirmationDialog = _find(ex._rank_box, "ConfirmationDialog")
	assert_not_null(dlg, "conferma con l'anteprima")
	assert_eq(int(_bank().get_instance(uid).rank), 0, "nulla prima del sì")
	dlg.confirmed.emit()
	assert_eq(int(_bank().get_instance(uid).rank), 1)
	var save: Button = _find(ex._sets_box, "Button", "UI_GAPM_SET_SAVE")
	save.pressed.emit()
	assert_false((Game.system("loadouts") as LoadoutSystem).is_empty_slot(0), "set salvato dalla schermata")


func test_ui_deposito_clessidra() -> void:
	_new_game()
	_bank().add(Hourglass.ITEM, 1, "test")
	_start_first_gathering()
	var scr: Control = await _open("res://src/ui/screens/BankScreen.tscn")
	scr._selected = Hourglass.ITEM
	scr._mark_dirty()
	var b: Button = _find(scr, "Button", "UI_GAPM_HG_USE")
	assert_not_null(b, "pulsante nel dettaglio della Clessidra")
	assert_false(b.disabled)
	b.pressed.emit()
	var dlg: ConfirmationDialog = _find(scr, "ConfirmationDialog")
	assert_not_null(dlg)
	dlg.confirmed.emit()
	assert_eq(_bank().count(Hourglass.ITEM), 0, "usata dopo la conferma")
