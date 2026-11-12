extends GutTest
## Modalità di gioco (docs/05 §7): regole (ModeRules, dati), Autarchica (blocchi di Mercato/Emporio e Commesse),
## Estrema (morte permanente, ritiro offline), titoli e cornici, salvataggio, menù iniziale.
## I sistemi veri girano dentro Game.new_game; l'offline usa l'ambiente a sistemi finti di COMBAT-2.

const Env := preload("res://tests/helpers/combat2_env.gd")
const START := "res://src/ui/start/StartScreen.tscn"

var _old_dir: String
var _keys: Dictionary = {}


func before_all() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			_keys[row[0]] = [row[1], row[2]]


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_modes_saves_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _ticks(seconds: float) -> void:
	for i in int(round(seconds / 0.1)):
		Game._on_step(0.1)


func _grant(tokens: Array) -> void:
	for t in tokens:
		(Game.system("unlock") as UnlockSystem).grant(str(t))


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


# ------------------------------------------------------------------ regole (ModeRules)

func test_regole_normale_senza_restrizioni() -> void:
	var r := ModeRules.make(DataRegistry, "normal")
	assert_true(r.is_normal())
	assert_false(r.market_buy_restricted())
	assert_true(r.market_buy_allowed("axe_copper"))
	assert_true(r.orders_enabled())
	assert_false(r.has_permadeath())
	assert_false(r.offline_stops_before_death())
	assert_eq(r.title_id(), "")
	assert_eq(r.frame_id(), "")


func test_regole_autarchica() -> void:
	var r := ModeRules.make(DataRegistry, "autarchic")
	assert_true(r.market_buy_restricted())
	assert_false(r.orders_enabled(), "Commesse disattivate")
	assert_false(r.has_permadeath(), "la morte resta quella normale")
	for ok in ["vial", "seed_potato", "seed_wheat", "seed_onion"]:
		assert_true(r.market_buy_allowed(ok), "consentito: " + ok)
	for no in ["axe_copper", "pickaxe_copper", "key_t1", "capsule_banners", "log_pine"]:
		assert_false(r.market_buy_allowed(no), "vietato: " + no)


func test_regole_estrema() -> void:
	var r := ModeRules.make(DataRegistry, "extreme")
	assert_true(r.has_permadeath())
	assert_eq(r.permadeath().reset_skills, ["hero"], "le mansioni restano: solo l'Eroe")
	assert_true(r.offline_stops_before_death())
	assert_true(r.orders_enabled(), "il Mercato resta normale")
	assert_false(r.market_buy_restricted())


func test_modalita_sconosciuta_e_normale() -> void:
	var r := ModeRules.make(DataRegistry, "hardcore")
	assert_true(r.is_normal())
	assert_true(r.market_buy_allowed("axe_copper"))
	assert_false(r.has_permadeath())
	assert_eq(ModeRules.all_ids(DataRegistry), PackedStringArray(["normal", "autarchic", "extreme"]))


func test_titoli_cornici_e_testi_esistono() -> void:
	for m in ["autarchic", "extreme"]:
		var r := ModeRules.make(DataRegistry, m)
		assert_false(DataRegistry.get_def("titles", r.title_id()).is_empty(), "titolo " + m)
		assert_false(DataRegistry.get_def("titles", r.star_title_id()).is_empty(), "secondo titolo " + m)
		assert_false(DataRegistry.get_def("frames", r.frame_id()).is_empty(), "cornice " + m)
		for k in ["UI_MODES_DESC_", "UI_MODES_CONFIRM_", "UI_MODES_WARN_"]:
			assert_true(_keys.has(k + m.to_upper()), k + m)
	assert_true(_keys.has("UI_MODES_DESC_NORMAL"))


func test_i_sistemi_non_confrontano_la_modalita() -> void:
	# "un solo punto": nessun sistema confronta mode == ... (solo GameState/ModeRules/UI possono leggere l'id)
	var re := RegEx.create_from_string("mode\\(\\)\\s*==|\"mode\"\\s*\\]?\\s*==|== \"(autarchic|extreme)\"")
	var bad: Array = []
	var d := DirAccess.open("res://src/systems")
	for f in d.get_files():
		if f.get_extension() == "gd" and re.search(FileAccess.get_file_as_string("res://src/systems/" + f)) != null:
			bad.append(f)
	assert_eq(bad, [], "usare ctx.mode_rules()")


# ------------------------------------------------------------------ Autarchica

func test_autarchica_emporio_blocca_attrezzi_chiavi_capsule() -> void:
	assert_true(Game.new_game(1, "autarchic", 11))
	_grant(["feature:market"])
	var mk := Game.system("market") as MarketSystem
	_bank().add_gold(10000000)
	for blocked in ["buy_axe_copper", "buy_pickaxe_copper", "buy_key_t1", "buy_capsule_banners", "buy_lockpick_copper"]:
		assert_eq(str(mk.shop_status(blocked).reason), "mode", blocked)
		assert_false(mk.buy(blocked, 1), "acquisto rifiutato: " + blocked)
	for ok in ["buy_vial", "buy_seed_potato", "buy_seed_wheat", "buy_seed_onion"]:
		assert_ne(str(mk.shop_status(ok).reason), "mode", ok)
	var vials := _bank().count("vial")
	assert_true(mk.buy("buy_vial", 5), "le fiale si comprano")
	assert_eq(_bank().count("vial"), vials + 5)
	assert_true(mk.buy("buy_seed_potato", 2), "i semi base si comprano")
	assert_true(mk.buy("auto_eat_1", 1), "i potenziamenti permanenti restano in vendita (OPEN_QUESTIONS M-1)")


func test_autarchica_scorte_dei_png_chiuse() -> void:
	assert_true(Game.new_game(1, "autarchic", 12))
	_grant(["feature:market"])
	var mk := Game.system("market") as MarketSystem
	assert_eq(mk.buy_price_npc("log_pine"), 0, "niente scorte PNG di materiali")
	assert_false(mk.buy_npc("log_pine", 1))
	Game.stop_game(false)
	assert_true(Game.new_game(1, "normal", 12))
	_grant(["feature:market"])
	mk = Game.system("market") as MarketSystem
	assert_gt(mk.buy_price_npc("log_pine"), 0, "in Normale le scorte ci sono")


func test_normale_emporio_non_bloccato() -> void:
	assert_true(Game.new_game(1, "normal", 13))
	_grant(["feature:market"])
	var mk := Game.system("market") as MarketSystem
	for id in ["buy_axe_copper", "buy_key_t1", "buy_capsule_banners"]:
		assert_ne(str(mk.shop_status(id).reason), "mode", id)


func test_autarchica_senza_commesse() -> void:
	assert_true(Game.new_game(1, "autarchic", 14))
	_grant(["feature:market"])
	_ticks(60.0)
	var mk := Game.system("market") as MarketSystem
	assert_false(mk.orders_enabled())
	assert_eq(mk.order_slots(), 0)
	assert_eq(mk.orders().size(), 0, "bacheca vuota")
	assert_false(mk.complete_order("o_1"))
	Game.stop_game(false)
	assert_true(Game.new_game(1, "normal", 14))
	_grant(["feature:market"])
	_ticks(60.0)
	mk = Game.system("market") as MarketSystem
	assert_gt(mk.orders().size(), 0, "in Normale la bacheca si riempie")


func test_autarchica_la_morte_resta_lieve() -> void:
	assert_true(Game.new_game(1, "autarchic", 15))
	var sk := Game.system("skills") as SkillSystem
	sk.add_xp("hero", 20000.0)
	var lv := sk.level("hero")
	assert_gt(lv, 3)
	EventBus.player_died.emit("test")
	assert_eq(sk.level("hero"), lv, "nessuna perdita")


# ------------------------------------------------------------------ Estrema

func _extreme_with_gear() -> Dictionary:
	assert_true(Game.new_game(1, "extreme", 21))
	var sk := Game.system("skills") as SkillSystem
	var cb := Game.system("combat") as CombatSystem
	sk.add_xp("hero", 30000.0)
	sk.add_xp("woodcutting", 6000.0)
	var sword := _bank().add_instance({"def": "sword_copper"})
	assert_true(cb.equip(sword))
	var axe := _bank().add_instance({"def": "axe_bronze"})
	assert_true(cb.equip(axe), "attrezzo di mansione")
	return {"sk": sk, "cb": cb, "sword": sword, "axe": axe}


func test_estrema_la_morte_toglie_livello_ed_equipaggiamento() -> void:
	var e := _extreme_with_gear()
	var sk: SkillSystem = e.sk
	var cb: CombatSystem = e.cb
	var lv_hero := sk.level("hero")
	var lv_wc := sk.level("woodcutting")
	assert_gt(lv_hero, 3)
	assert_gt(lv_wc, 3)
	sk.state.hero["stars"] = 2
	sk.state.hero["record_level"] = lv_hero
	cb.state["attrs"] = {"str": 3}
	cb.state["talents"] = {"x": 1}
	_bank().add("arrow_pine", 10, "test")
	EventBus.player_died.emit("test")
	assert_eq(sk.level("hero"), 1, "livello Eroe perso")
	assert_eq(float(sk.state.hero.xp), 0.0)
	assert_eq(sk.level("woodcutting"), lv_wc, "le mansioni restano")
	assert_eq(int(sk.state.hero.stars), 2, "le Stelle restano")
	assert_eq(int(sk.state.hero.record_level), lv_hero, "il record resta (Eco)")
	assert_eq(cb.equipped("weapon"), "", "arma persa")
	assert_true(_bank().get_instance(str(e.sword)).is_empty(), "l'istanza è distrutta")
	assert_true(cb.is_equipped(str(e.axe)), "gli attrezzi di mansione restano")
	assert_false(_bank().get_instance(str(e.axe)).is_empty())
	assert_eq(cb.state.talents, {}, "talenti azzerati con il livello")
	assert_eq(cb.state.attrs, {})
	var md: Dictionary = GameState.data.modes
	assert_eq(int(md.deaths_lost), 1)
	assert_eq(int(md.levels_lost), lv_hero - 1)
	assert_eq(int(md.items_lost), 1)
	assert_eq(int(md.last.items), 1)


func test_normale_la_morte_non_toglie_nulla() -> void:
	assert_true(Game.new_game(1, "normal", 22))
	var sk := Game.system("skills") as SkillSystem
	var cb := Game.system("combat") as CombatSystem
	sk.add_xp("hero", 30000.0)
	var lv := sk.level("hero")
	var sword := _bank().add_instance({"def": "sword_copper"})
	assert_true(cb.equip(sword))
	EventBus.player_died.emit("test")
	assert_eq(sk.level("hero"), lv)
	assert_true(cb.is_equipped(sword))
	assert_eq(int(GameState.data.modes.deaths_lost), 0)


func test_estrema_morte_reale_in_combattimento() -> void:
	assert_true(Game.new_game(1, "extreme", 23))
	_grant(["feature:combat", "zone:millbrook"])
	var cb := Game.system("combat") as CombatSystem
	var sword := _bank().add_instance({"def": "sword_copper"})
	assert_true(cb.equip(sword))
	assert_true(cb.start("millbrook", "hornet_queen"))
	var guard := 0
	while int(cb.state.deaths) == 0 and guard < 6000:
		Game._on_step(0.1)
		guard += 1
	assert_gt(int(cb.state.deaths), 0, "il livello 1 contro la Regina Vespa muore")
	assert_eq(cb.equipped("weapon"), "", "la spada è andata")
	assert_eq(int(GameState.data.modes.deaths_lost), 1)
	assert_eq(int(GameState.data.modes.items_lost), 1)
	_ticks(15.0)
	assert_gt(cb.hp(), 0.0, "l'Eroe si rialza (senza spada)")


func test_estrema_nessuna_perdita_senza_equipaggiamento() -> void:
	assert_true(Game.new_game(1, "extreme", 24))
	var sk := Game.system("skills") as SkillSystem
	EventBus.player_died.emit("test")
	assert_eq(sk.level("hero"), 1)
	assert_eq(int(GameState.data.modes.items_lost), 0)
	assert_eq(int(GameState.data.modes.deaths_lost), 1, "conta comunque la vita")


func test_estrema_offline_si_ritira_invece_di_morire() -> void:
	var env: Object = Env.make(5, 3, "warrior")
	autofree(env.bus)
	env.state["mode"] = "extreme"
	env.unlock_zone("millbrook")
	env.combat.start("millbrook", "hornet_queen")
	var rep: Dictionary = env.combat.simulate_offline(3600.0)
	assert_false(bool(rep.get("died", false)), "offline non si muore")
	assert_eq(str(rep.get("stopped", "")), "death_risk")
	assert_eq(int(env.combat.state.deaths), 0)
	assert_false(env.combat.in_combat(), "l'attività si ferma")
	# stessa situazione in Normale: la morte c'è (comportamento invariato)
	var env2: Object = Env.make(5, 3, "warrior")
	autofree(env2.bus)
	env2.unlock_zone("millbrook")
	env2.combat.start("millbrook", "hornet_queen")
	var rep2: Dictionary = env2.combat.simulate_offline(3600.0)
	assert_true(bool(rep2.get("died", false)))
	assert_eq(int(env2.combat.state.deaths), 1)


# ------------------------------------------------------------------ titoli e cornici

func test_titolo_e_cornice_alla_creazione() -> void:
	for m in ["autarchic", "extreme"]:
		assert_true(Game.new_game(1, m, 31))
		_ticks(0.5)
		var comp := Game.system("compendium") as CompendiumSystem
		var r := ModeRules.make(DataRegistry, m)
		assert_true(comp.has_title(r.title_id()), "titolo " + m)
		assert_true(comp.has_frame(r.frame_id()), "cornice " + m)
		assert_true(bool(GameState.data.modes.badge))
		Game.stop_game(false)
	assert_true(Game.new_game(1, "normal", 31))
	_ticks(0.5)
	assert_eq((Game.system("compendium") as CompendiumSystem).owned_titles(), [], "nessun titolo in Normale")


func test_secondo_titolo_alla_prima_stella() -> void:
	assert_true(Game.new_game(1, "extreme", 32))
	_ticks(0.5)
	var comp := Game.system("compendium") as CompendiumSystem
	assert_false(comp.has_title("title_mode_extreme_star"))
	EventBus.star_gained.emit("woodcutting")
	assert_true(comp.has_title("title_mode_extreme_star"))
	EventBus.star_gained.emit("mining")
	assert_eq(comp.owned_titles().count("title_mode_extreme_star"), 1, "una volta sola")


# ------------------------------------------------------------------ prestigio

func test_estrema_le_stelle_e_la_polvere_restano() -> void:
	assert_true(Game.new_game(1, "extreme", 41))
	var pr := Game.system("prestige") as PrestigeSystem
	pr.state["stardust"] = 123
	pr.state["era_max"] = 3
	var sk := Game.system("skills") as SkillSystem
	sk.state.woodcutting["stars"] = 4
	EventBus.player_died.emit("test")
	assert_eq(int(pr.state.stardust), 123)
	assert_eq(int(pr.state.era_max), 3)
	assert_eq(int(sk.state.woodcutting.stars), 4)


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_estremo_round_trip() -> void:
	assert_true(Game.new_game(2, "extreme", 51))
	_ticks(0.5)
	EventBus.player_died.emit("test")
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var info := SaveService.slot_info(2)
	assert_true(info.ok)
	assert_eq(str(info.mode), "extreme")
	var res := Game.load_game(2)
	assert_true(res.ok)
	assert_eq(GameState.mode(), "extreme")
	assert_true(GameState.mode_rules().has_permadeath(), "le regole tornano dopo il caricamento")
	assert_eq(int(GameState.data.modes.deaths_lost), 1)
	assert_true(bool(GameState.data.modes.badge))
	# la modalità non cambia più: nessuna funzione pubblica la modifica e il load la conserva
	EventBus.player_died.emit("test")
	assert_eq(int(GameState.data.modes.deaths_lost), 2)


func test_salvataggio_vecchio_senza_sezione_modes() -> void:
	assert_true(Game.new_game(3, "normal", 52))
	GameState.data.erase("modes")
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(3).ok)
	assert_eq(GameState.mode(), "normal")
	assert_true(GameState.data.has("modes"), "sezione creata dal default")
	assert_eq(int(GameState.data.modes.deaths_lost), 0)


func test_salvataggio_modalita_manomessa_torna_normale() -> void:
	assert_true(Game.new_game(1, "normal", 53))
	GameState.data["mode"] = "godmode"
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	assert_eq(GameState.mode(), "normal")


func test_salvataggio_dorato_resta_normale() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/golden/save_v0_1_fine_cap1.sav")
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	assert_eq(SaveService.write_atomic(1, bytes), OK)
	assert_true(Game.load_game(1).ok)
	assert_eq(GameState.mode(), "normal")
	assert_false(GameState.mode_rules().has_permadeath())
	assert_true(GameState.data.has("modes"))


func test_nuova_partita_modalita_sconosciuta_rifiutata() -> void:
	assert_false(Game.new_game(1, "hardcore"))
	assert_false(GameState.active)
	for m in ["normal", "autarchic", "extreme"]:
		assert_true(Game.new_game(1, m, 61), m)
		assert_eq(GameState.mode(), m)
		Game.stop_game(false)


# ------------------------------------------------------------------ menù iniziale e interfaccia

func test_menu_tutte_le_modalita_selezionabili_con_descrizione() -> void:
	var start: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(2)
	start.show_slots()
	await wait_process_frames(1)
	var opt: OptionButton = start._mode_option
	assert_eq(opt.item_count, 3)
	for i in 3:
		assert_false(opt.is_item_disabled(i), "modalità %d selezionabile" % i)
	var texts := {}
	for m in ModeRules.all_ids(DataRegistry):
		var t: String = start.mode_text(m)
		assert_false(t.is_empty() or t.begins_with("UI_"), "testo tradotto per " + m)
		texts[t] = true
	assert_eq(texts.size(), 3, "tre descrizioni diverse")
	assert_true(start.mode_text("extreme").contains(tr("UI_MODES_PERMANENT")), "avviso: non si cambia dopo")
	assert_false(start.mode_text("normal").contains(tr("UI_MODES_PERMANENT")))
	opt.select(2)
	opt.item_selected.emit(2)
	assert_eq(start.selected_mode(), "extreme")
	assert_eq(start._mode_desc.text, start.mode_text("extreme"))


func test_menu_crea_partita_estrema() -> void:
	var start: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(2)
	start.show_slots()
	await wait_process_frames(1)
	start._mode_option.select(1)
	watch_signals(start)
	start.start_new(1)
	assert_true(GameState.active)
	assert_eq(GameState.mode(), "autarchic")
	assert_eq(GameState.mode_rules().mode_id, "autarchic")


func test_menu_conferma_per_le_modalita_estreme() -> void:
	var start: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(start)
	await wait_process_frames(2)
	start.show_slots()
	await wait_process_frames(1)
	start._mode_option.select(2)
	start._on_new_in_slot(1, false)
	await wait_process_frames(1)
	assert_false(GameState.active, "serve la conferma")
	assert_true(start._confirm.dialog_text.contains(tr("UI_MODES_CONFIRM_EXTREME")))
	start._confirm.hide()
	start._pending = Callable()
	start._mode_option.select(0)
	start._on_new_in_slot(1, false)
	assert_true(GameState.active, "in Normale si parte subito")


func test_indicatore_modalita_nella_barra_e_nel_riepilogo() -> void:
	assert_true(Game.new_game(1, "extreme", 71))
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	var badge := main.get_node_or_null("Root/TopBar/HBox/ModeBadge") as Label
	assert_not_null(badge, "indicatore nella barra")
	assert_true(badge.text.contains(tr("UI_MODE_EXTREME")))
	assert_eq(badge.tooltip_text, tr("UI_MODES_DESC_EXTREME"))
	var summary: Control = main.current_screen()
	summary.refresh()
	assert_eq((summary.get_node("%ModeValue") as Label).text, tr("UI_MODE_EXTREME"))
	EventBus.player_died.emit("test")
	summary.refresh()
	assert_true((summary.get_node("%ModeValue") as Label).text.contains(Loc.tf("UI_MODES_SUMMARY_LOST", {"n": 1})))
	Game.stop_game(false)
	assert_true(Game.new_game(1, "normal", 72))
	var main2: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main2)
	await wait_process_frames(2)
	assert_null(main2.get_node_or_null("Root/TopBar/HBox/ModeBadge"), "nessun indicatore in Normale")
