extends GutTest
## SeasonalEventSystem (T-11.3, docs/27): calendario (date simulate, fuso, orologio indietro), cadute di valuta, missioni, recupero
## (Eco e Negozio), disattivazione, salvataggio, bonus temporaneo ed etica della Cassa evento (probabilità mostrate = usate).

const UNLOCK := "feature:crates"
const SOURCE := "event:lantern_night"


class FakeCompendium extends GameSystem:
	var pets: Array = []
	var titles: Array = []
	func _init() -> void:
		id = "compendium"
	func has_pet(pet_id: String) -> bool:
		return pets.has(pet_id)
	func grant_title(title_id: String) -> bool:
		if titles.has(title_id):
			return false
		titles.append(title_id)
		return true


var sim: Simulation
var sys: SeasonalEventSystem
var bank: TestFakeBank
var comp: FakeCompendium
var crates: CrateSystem
var state: Dictionary
var mods: ModifierStack
var wall: int = 0
var tz: int = 0
var _pets_seen: Array = []


func _u(y: int, m: int, d: int, h: int = 12, mi: int = 0) -> int:
	return SeasonalEventSystem.unix_of(y, m, d, h, mi)


## Sistema in una partita finta: Deposito finto, Cassa vera, Compendio finto. `unix` = ora dell'orologio.
func _make(unix: int, tz_min: int = 0, activity: bool = true, seed_value: int = 11) -> void:
	state = {"unlocks": [UNLOCK], "activity": ({"type": "skill", "action": "x", "progress_s": 0.0} if activity else {})}
	mods = ModifierStack.new()
	mods.set_catalog(DataRegistry.table("modifier_catalog"))
	var ctx := SystemContext.make(DataRegistry, state, mods, RngStreams.new(seed_value), EventBus)
	sim = Simulation.new()
	bank = TestFakeBank.new()
	comp = FakeCompendium.new()
	crates = CrateSystem.new()
	sys = SeasonalEventSystem.new()
	wall = unix
	tz = tz_min
	sys.set_wall(wall, tz)
	sim.setup(ctx, [bank, crates, comp, sys])
	sim.bind_state(state)


func _set_wall(unix: int, tz_min: int = 0) -> void:
	wall = unix
	tz = tz_min
	sys.set_wall(wall, tz)


## Gioca `seconds` secondi: l'orologio avanza insieme al tempo di gioco, a passi da 60 s.
func _play(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(60.0, left)
		wall += int(round(dt))
		sys.set_wall(wall, tz)
		sim.tick(dt)
		left -= dt


func _pet_found(pet_id: String) -> void:
	_pets_seen.append(pet_id)


# ------------------------------------------------------------------ aritmetica delle date

func test_date_civili_come_il_motore() -> void:
	assert_eq(SeasonalEventSystem.days_from_civil(1970, 1, 1), 0)
	for unix in [0, 86400 * 59, 951782400, 1709164800, 1767225600, 1798761599, 4102444800]:
		var z := floori(float(unix) / 86400.0)
		var c := SeasonalEventSystem.civil_from_days(z)
		var dt := Time.get_datetime_dict_from_unix_time(unix)
		assert_eq([c.x, c.y, c.z], [dt.year, dt.month, dt.day], "data di %d" % unix)
		assert_eq(SeasonalEventSystem.days_from_civil(c.x, c.y, c.z), z)
	assert_eq(SeasonalEventSystem.unix_of(2026, 1, 1), 1767225600)


# ------------------------------------------------------------------ calendario

func test_quattro_eventi_all_anno_senza_sovrapposizioni() -> void:
	_make(_u(2027, 1, 1))
	var seen := {}
	var last := ""
	var starts := 0
	for day in 365:
		_set_wall(_u(2027, 1, 1) + day * 86400)
		var st := sys.status()
		assert_true(bool(st.trusted), "un orologio che avanza è fidato")
		var e := str(st.event) if st.mode == "event" else ""
		seen[e] = true
		if e != "" and e != last:
			starts += 1
		last = e
	seen.erase("")
	assert_eq(seen.size(), 4, "4 eventi all'anno")
	assert_eq(starts, 5, "Festa del Gelo compare due volte (a cavallo d'anno: gennaio e dicembre)")
	assert_true(seen.has("lantern_night") and seen.has("frost_feast") and seen.has("blossom") and seen.has("sun_regatta"))


func test_confini_delle_date_e_a_cavallo_d_anno() -> void:
	_make(_u(2026, 10, 19, 12))
	var st := sys.status()
	assert_eq(st.mode, "echo", "fuori dalle date c'è l'Eco dell'ultimo evento concluso")
	assert_eq(st.echo_event, "sun_regatta")
	assert_eq(st.next_event, "lantern_night")
	assert_eq(int(st.next_in_s), 12 * 3600, "mezzogiorno del 19 → mezzanotte del 20")
	_set_wall(_u(2026, 10, 20, 0, 0))
	st = sys.status()
	assert_eq([st.mode, st.event, st.occ], ["event", "lantern_night", "lantern_night:2026"])
	assert_eq(int(st.ends_in_s), 17 * 86400, "dal 20/10 alle 00:00 al 6/11 alle 00:00")
	_set_wall(_u(2026, 11, 5, 23, 59))
	assert_eq(sys.status().mode, "event", "il 5/11 è ancora evento")
	_set_wall(_u(2026, 11, 6, 0, 0))
	assert_eq(sys.status().mode, "echo", "dal 6/11 finito")
	_set_wall(_u(2026, 12, 31, 12))
	st = sys.status()
	assert_eq([st.event, st.occ], ["frost_feast", "frost_feast:2026"])
	_set_wall(_u(2027, 1, 6, 23, 30))
	st = sys.status()
	assert_eq([st.mode, st.occ], ["event", "frost_feast:2026"], "a cavallo d'anno l'edizione resta quella di inizio")
	_set_wall(_u(2027, 1, 7, 0, 0))
	assert_eq(sys.status().mode, "echo")
	_set_wall(_u(2027, 3, 20, 8))
	assert_eq(sys.status().event, "blossom")
	_set_wall(_u(2027, 8, 15, 23, 59))
	assert_eq(sys.status().event, "sun_regatta")
	_set_wall(_u(2027, 8, 16, 0, 0))
	assert_eq(sys.status().mode, "echo")


func test_fuso_orario_sposta_il_giorno_locale() -> void:
	_make(_u(2026, 10, 19, 23, 30), 120)           # UTC+2: per l'utente è già il 20/10, 01:30
	assert_eq(sys.status().event, "lantern_night", "con il fuso +2 l'evento è già iniziato")
	assert_eq(int(sys.status().ends_in_s), 17 * 86400 - 5400)
	_set_wall(_u(2026, 10, 19, 23, 30), 0)
	assert_eq(sys.status().mode, "echo", "stesso istante con fuso 0: non ancora")
	_set_wall(_u(2026, 11, 6, 2, 0), -300)          # UTC-5: per l'utente è ancora il 5/11, 21:00
	assert_eq(sys.status().event, "lantern_night")
	_set_wall(_u(2026, 11, 6, 6, 0), -300)
	assert_eq(sys.status().mode, "echo")


func test_orologio_indietro_non_fidato_il_calendario_segue_il_gioco() -> void:
	_make(_u(2026, 11, 5, 22, 0))                   # 2 h prima della fine di Lanterne
	_play(600.0)
	assert_true(bool(sys.status().trusted))
	# l'utente rimette l'orologio indietro di 10 giorni: non è più fidato, la data virtuale prosegue
	_set_wall(wall - 10 * 86400)
	var st := sys.status()
	assert_false(bool(st.trusted))
	assert_eq(st.mode, "event", "la data virtuale è ancora dentro l'evento")
	var before := bank.count("event_wax")
	_play(3600.0)                                   # 1 h di gioco: dalle 22:10 alle 23:10 virtuali
	assert_eq(bank.count("event_wax") - before, 12, "1 ora = 12 unità, come con l'orologio giusto")
	assert_eq(sys.status().mode, "event")
	_play(3600.0)                                   # la data virtuale supera la mezzanotte del 6/11: evento finito
	st = sys.status()
	assert_false(bool(st.trusted))
	assert_eq(st.mode, "echo", "il tempo di gioco ha portato la data oltre la fine dell'evento")
	# orologio ripristinato (il vero tempo trascorso): fidato di nuovo
	_set_wall(_u(2026, 11, 6, 3, 0))
	assert_true(bool(sys.status().trusted))


func test_data_non_valida_e_nessun_calendario_all_avvio() -> void:
	_make(0)
	sys.set_wall(0, 0, false)
	var st := sys.status()
	assert_false(bool(st.ok))
	assert_eq(st.mode, "none")
	_play(3000.0)
	assert_eq(bank.count("event_wax"), 0, "senza una data valida non si inventa nulla")
	_set_wall(_u(2025, 3, 3))                       # prima di min_valid_unix: orologio non affidabile
	assert_false(bool(sys.status().ok))
	_set_wall(_u(2026, 10, 25))
	assert_eq(sys.status().event, "lantern_night")


func test_giocare_con_l_orologio_manomesso_non_da_premi_extra() -> void:
	_make(_u(2026, 10, 25, 12))
	var dates: Array = [_u(2026, 10, 25), _u(2026, 2, 1), _u(2026, 12, 20), _u(2026, 7, 20), _u(2027, 3, 25), _u(2025, 5, 5)]
	var total_s := 0.0
	var chunk := 0
	while total_s < 7200.0:
		_set_wall(int(dates[chunk % dates.size()]) + int(total_s))     # salta avanti e indietro tra edizioni diverse
		sim.tick(60.0)
		total_s += 60.0
		chunk += 1
	var got := 0
	for c in ["event_wax", "event_snowflake", "event_petal", "event_shell"]:
		got += bank.count(c)
	assert_lte(got, 24, "2 ore di gioco: al massimo 12 unità/ora (nessun guadagno dal gioco con la data)")


# ------------------------------------------------------------------ cadute di valuta

func test_cadute_ogni_300_secondi_solo_con_un_attivita() -> void:
	_make(_u(2026, 10, 25))
	_play(3000.0)
	assert_eq(bank.count("event_wax"), 10, "1 ogni 300 s")
	state.activity = {}
	_play(3000.0)
	assert_eq(bank.count("event_wax"), 10, "senza attività non cade nulla")
	state.activity = {"type": "combat"}
	_play(600.0)
	assert_eq(bank.count("event_wax"), 12, "anche il combattimento è un'attività")


func test_cadute_dopo_la_prima_cassa_e_con_tetto() -> void:
	_make(_u(2026, 10, 25))
	state.unlocks = []
	_play(1200.0)
	assert_eq(bank.count("event_wax"), 0, "prima della prima Cassa gli eventi non partono")
	state.unlocks = [UNLOCK]
	_play(300.0 * 400.0 + 6000.0)
	assert_eq(bank.count("event_wax"), 400, "tetto per edizione")
	assert_eq(int(state.seasonal.earned["lantern_night:2026"]), 400)
	_play(6000.0)
	assert_eq(bank.count("event_wax"), 400, "oltre il tetto non cade altro")


func test_offline_a_cavallo_dell_inizio_evento() -> void:
	_make(_u(2026, 10, 19, 21, 0))                  # ultimo punto fidato salvato: 21:00 del 19/10
	_set_wall(_u(2026, 10, 20, 3, 0))               # riapro alle 03:00 del 20/10, dopo 6 h
	# le prime 3 h erano nell'Eco, le ultime 3 nell'evento
	var sim_report := sys.simulate_offline(6 * 3600.0)
	assert_eq(bank.count("event_wax"), 36, "3 h di evento → 36 unità")
	assert_eq(bank.count("event_shell"), 18, "3 h di Eco → 1 ogni 600 s")
	assert_eq(int(sim_report.total), 54)


func test_offline_tetto_e_orologio_non_fidato() -> void:
	_make(_u(2026, 10, 25, 12))
	sys.simulate_offline(48 * 3600.0)
	assert_eq(bank.count("event_wax"), 400, "48 h offline: tetto per edizione")
	# orologio rimesso indietro durante l'assenza: la data virtuale avanza con il tempo di gioco, nessun extra
	var anchor_unix := int(state.seasonal.anchor_unix)
	_set_wall(anchor_unix - 30 * 86400)
	var wax := bank.count("event_wax")
	sys.simulate_offline(3600.0)
	assert_eq(bank.count("event_wax"), wax, "il tetto vale anche così")
	assert_false(bool(sys.status().trusted))


# ------------------------------------------------------------------ missioni

func _action_of(skill: String) -> String:
	return str(DataRegistry.actions_for_skill(skill)[0].id)


func _mission(event_id: String, kind: String) -> Dictionary:
	for m in sys.missions(event_id):
		if m.kind == kind:
			return m
	return {}


func test_missioni_avanzano_e_si_riscuotono() -> void:
	_make(_u(2026, 10, 25))
	var wc := _action_of("woodworking")
	var other := _action_of("mining")
	for i in 50:
		EventBus.action_completed.emit(other, [])
	assert_eq(int(_mission("lantern_night", "actions").prog), 0, "la mansione tematica è Carpenteria: le altre non contano")
	for i in 150:
		EventBus.action_completed.emit(wc, [])
	EventBus.action_batch_completed.emit(wc, 500, [])
	var m := _mission("lantern_night", "actions")
	assert_eq(int(m.prog), int(m.qty), "il progresso si ferma alla quantità")
	assert_true(bool(m.done))
	assert_true(sys.claim(str(m.id)))
	assert_eq(bank.count("event_wax"), int(m.reward))
	assert_false(sys.claim(str(m.id)), "una sola riscossione")
	EventBus.monster_killed.emit("mud_slime", [])
	EventBus.monsters_killed_batch.emit("mud_slime", 99, [])
	var k := _mission("lantern_night", "kills")
	assert_eq(int(k.prog), 100)
	EventBus.crate_opened.emit({"crate_id": "crate_millbrook", "kind": "skin", "def_id": "x"})
	assert_eq(int(_mission("lantern_night", "crates").prog), 1, "qualsiasi Cassa conta")


func test_missione_valuta_e_titolo_con_tutte_e_quattro() -> void:
	_make(_u(2026, 10, 25))
	var wc := _action_of("woodworking")
	EventBus.action_batch_completed.emit(wc, 200, [])
	EventBus.monsters_killed_batch.emit("mud_slime", 100, [])
	for i in 3:
		EventBus.crate_opened.emit({"crate_id": "crate_millbrook", "kind": "skin", "def_id": "x"})
	_play(300.0 * 20.0)                              # 20 unità raccolte dalle cadute
	var cur := _mission("lantern_night", "currency")
	assert_true(bool(cur.done))
	assert_eq(sys.claimable().size(), 4)
	for m in sys.missions("lantern_night"):
		assert_true(sys.claim(str(m.id)))
	assert_eq(comp.titles, ["title_lantern_keeper"], "con tutte e 4 le missioni arriva il titolo")
	assert_eq(bank.count("event_wax"), 20 + 50, "20 dalle cadute + 10+10+15+15 dalle missioni")


func test_missioni_di_un_evento_concluso_restano_riscuotibili() -> void:
	_make(_u(2026, 11, 5, 12))
	EventBus.monsters_killed_batch.emit("mud_slime", 100, [])
	_set_wall(_u(2026, 11, 20))                      # evento finito
	assert_eq(sys.status().mode, "echo")
	assert_eq(sys.claimable().size(), 1, "il progresso non si perde quando l'evento finisce")
	assert_true(sys.claim(sys.claimable()[0].id))


# ------------------------------------------------------------------ recupero: Eco e Negozio

func test_eco_rigioca_un_evento_passato_a_meta_ritmo() -> void:
	_make(_u(2026, 9, 1))
	var st := sys.status()
	assert_eq([st.mode, st.event], ["echo", "sun_regatta"], "di base l'ultimo concluso")
	_play(3600.0)
	assert_eq(bank.count("event_shell"), 6, "1 ogni 600 s")
	assert_true(sys.set_echo_event("blossom"))
	assert_false(sys.set_echo_event("inesistente"))
	_play(3600.0)
	assert_eq(bank.count("event_petal"), 6)
	assert_eq(mods.total_add("skill_double_pct", ["farming"]), 0.0, "l'Eco non dà bonus temporanei")
	# missioni dell'Eco → titolo
	EventBus.action_batch_completed.emit(_action_of("foraging"), 200, [])
	EventBus.monsters_killed_batch.emit("mud_slime", 100, [])
	for i in 3:
		EventBus.crate_opened.emit({"crate_id": "crate_millbrook", "kind": "skin", "def_id": "x"})
	_play(600.0 * 20.0)
	for m in sys.missions("blossom"):
		assert_true(sys.claim(str(m.id)), "missione dell'Eco " + str(m.id))
	assert_eq(comp.titles, ["title_gardener"], "il titolo si recupera anche con l'Eco")
	assert_eq(int(state.seasonal.earned["blossom:echo"]), 6 + 20)
	sys.set_echo_event("")
	assert_eq(sys.echo_event(), "sun_regatta")


func test_negozio_prezzo_fisso_recupera_ogni_ricompensa() -> void:
	_make(_u(2026, 9, 1))
	for ev in DataRegistry.table("events"):
		var shop := sys.shop(str(ev.id))
		var ids: Array = []
		for s in shop:
			ids.append(str(s.id))
		for r in ev.rewards:
			assert_true(str(r).begins_with("title_") or ids.has(str(r)), "%s è acquistabile nel Negozio di %s" % [r, ev.id])
	var cosm := "cosmetic_event_blossom_1"
	assert_eq(sys.buy_check("blossom", cosm), "funds")
	bank.stacks["event_petal"] = 100
	assert_eq(sys.buy_check("blossom", cosm), "")
	assert_true(sys.buy("blossom", cosm))
	assert_eq(bank.count("event_petal"), 100 - 25)
	assert_eq(bank.inst.size(), 1)
	assert_eq(bank.inst.values()[0].def_id, cosm)
	assert_eq(sys.buy_check("blossom", cosm), "owned")
	assert_false(sys.buy("blossom", cosm), "non si ricompra")
	assert_eq(bank.count("event_petal"), 75)
	# famiglio: arriva il segnale pet_found, nessun bonus (compagno)
	bank.stacks["event_petal"] = 500
	EventBus.pet_found.connect(_pet_found)
	_pets_seen.clear()
	assert_true(sys.buy("blossom", "pet_event_bee"))
	EventBus.pet_found.disconnect(_pet_found)
	assert_eq(_pets_seen, ["pet_event_bee"])
	comp.pets.append("pet_event_bee")
	assert_eq(sys.buy_check("blossom", "pet_event_bee"), "owned")
	assert_true(DataRegistry.get_def("pets", "pet_event_bee").modifiers.is_empty(), "i famigli evento non danno potere")


func test_negozio_resta_aperto_fuori_dalle_date() -> void:
	_make(_u(2027, 5, 5))                            # nessun evento in corso
	assert_ne(sys.status().mode, "event")
	bank.stacks["event_wax"] = 300
	assert_true(sys.buy("lantern_night", "cosmetic_banner_lantern_night"), "la valuta avanzata non va sprecata")


func test_cassa_evento_si_apre_con_la_valuta_e_si_registra_il_possesso() -> void:
	_make(_u(2026, 10, 25))
	bank.stacks["crate_event_lantern_night"] = 200
	bank.stacks["event_wax"] = 25 * 200
	var owned := {}
	for r in crates.open("crate_event_lantern_night", 200, false):
		if r.kind == "cosmetic":
			owned[r.def_id] = true
	assert_gt(owned.size(), 0)
	for d in owned:
		assert_eq(sys.shop("lantern_night").filter(func(s: Dictionary) -> bool: return s.id == d)[0].owned, true, "possesso registrato: " + d)


# ------------------------------------------------------------------ disattivazione

func test_disattivare_gli_eventi() -> void:
	_make(_u(2026, 10, 25))
	_play(900.0)
	assert_eq(bank.count("event_wax"), 3)
	assert_true(mods.has_source(SOURCE))
	EventBus.monsters_killed_batch.emit("mud_slime", 40, [])
	sys.set_events_enabled(false)
	assert_eq(sys.status().mode, "off")
	assert_false(sys.events_enabled())
	assert_false(mods.has_source(SOURCE), "niente bonus temporaneo")
	_play(1500.0)
	assert_eq(bank.count("event_wax"), 3, "niente cadute")
	EventBus.monsters_killed_batch.emit("mud_slime", 60, [])
	assert_eq(int(_mission("lantern_night", "kills").prog), 40, "niente progressi di missione")
	assert_eq(sys.simulate_offline(36000.0), {}, "né offline")
	assert_false(sys.buy("lantern_night", "cosmetic_event_lantern_night_1"))
	sys.set_events_enabled(true)
	assert_true(mods.has_source(SOURCE))
	assert_eq(int(_mission("lantern_night", "kills").prog), 40, "i progressi restano")
	_play(300.0)
	assert_eq(bank.count("event_wax"), 4)


# ------------------------------------------------------------------ bonus temporaneo

func test_bonus_temporaneo_solo_durante_le_date() -> void:
	_make(_u(2026, 10, 25))
	assert_eq(mods.total_add("crate_find_pct", ["all"]), 10.0)
	_set_wall(_u(2026, 11, 7))
	sim.tick(1.0)
	assert_false(mods.has_source(SOURCE), "evento finito: bonus tolto")
	assert_eq(mods.total_add("crate_find_pct", ["all"]), 0.0)
	_set_wall(_u(2026, 12, 20))
	sim.tick(1.0)
	assert_eq(mods.total_add("skill_xp_pct", ["all"]), 10.0)
	assert_eq(mods.total_add("crate_find_pct", ["all"]), 0.0)


func test_nessun_malus_per_l_assenza() -> void:
	_make(_u(2026, 10, 25))
	_play(600.0)
	var wax := bank.count("event_wax")
	_set_wall(_u(2027, 6, 1))                         # un'assenza di 7 mesi
	var st := sys.status()
	assert_eq(bank.count("event_wax"), wax, "la valuta resta")
	assert_true(bool(st.trusted))
	assert_eq(sys.shop("lantern_night").size(), 5)
	assert_eq(sys.claimable().size(), 0)


# ------------------------------------------------------------------ salvataggio

func test_salvataggio_e_caricamento() -> void:
	_make(_u(2026, 10, 25))
	_play(1800.0)
	EventBus.monsters_killed_batch.emit("mud_slime", 70, [])
	EventBus.crate_opened.emit({"crate_id": "crate_event_lantern_night", "kind": "cosmetic", "def_id": "cosmetic_event_lantern_night_2"})
	sys.set_echo_event("blossom")
	var text := JSON.stringify(sim.ctx.state.get("seasonal", sys.to_state()))
	var parsed: Variant = JSON.parse_string(text)
	var wrapped := {"seasonal": parsed}
	assert_eq(SaveCodec.normalize(wrapped, PackedStringArray(Array(sys.int_paths()).map(func(p: String) -> String: return "seasonal." + p))).size(), 0)
	var drops := bank.count("event_wax")
	_make(_u(2026, 10, 26))                           # "nuovo avvio" un giorno dopo
	state["seasonal"] = wrapped.seasonal
	sim.bind_state(state)
	assert_eq(int(_mission("lantern_night", "kills").prog), 70, "progressi missione salvati")
	assert_true(sys.is_owned("item", "cosmetic_event_lantern_night_2"))
	assert_eq(sys.echo_event(), "blossom")
	assert_eq(int(state.seasonal.earned["lantern_night:2026"]), drops)
	assert_true(bool(sys.status().trusted))
	assert_true(mods.has_source(SOURCE), "i modificatori si riapplicano al caricamento")
	# un salvataggio senza la sezione (versione precedente) riceve lo stato iniziale
	_make(_u(2026, 10, 26))
	assert_false(state.seasonal.opt_out)
	assert_eq(sys.status().mode, "event")


func test_salvataggio_vecchio_con_orologio_indietro() -> void:
	_make(_u(2026, 10, 25))
	_play(600.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.seasonal))
	_make(_u(2020, 1, 1))                             # PC con la data sbagliata (anteriore alla validità)
	state["seasonal"] = saved
	sim.bind_state(state)
	var st := sys.status()
	assert_false(bool(st.trusted))
	assert_eq(st.mode, "event", "si riparte dalla data virtuale salvata")


# ------------------------------------------------------------------ etica della Cassa evento

func test_cassa_evento_probabilita_mostrate_uguali_a_quelle_usate() -> void:
	_make(_u(2026, 10, 25), 0, true, 4242)
	for ev in DataRegistry.table("events"):
		var cid := str(ev.crate)
		var rows := sys.crate_odds(str(ev.id))
		var tot := 0.0
		for r in rows:
			tot += float(r.pct)
			assert_almost_eq(float(r.pct), float(r.current_pct), 1e-9, "mostrata = usata alla prossima apertura")
			assert_almost_eq(float(r.pct), float(r.effective_pct), 1e-9, "senza pity: nominale = effettiva")
		assert_almost_eq(tot, 100.0, 1e-6)
		assert_eq(crates.pity_family(cid), "", "nessuna pity nascosta")
		var cr := crates.crate_def(cid)
		assert_true(cr.get("key") == null, "nessuna chiave, nessun acquisto")
		assert_eq(str(cr.open_cost.item), str(ev.currency), "si apre solo con la valuta evento")
		for sid in cr.skins:
			assert_eq(str(DataRegistry.item(sid).category), "cosmetic", "solo cosmetici")
		for pid in cr.relic_pool:
			assert_true(DataRegistry.get_def("pets", str(pid)).modifiers.is_empty(), "nessun potere")
		assert_false(bool(DataRegistry.item(cid).tradeable))
		assert_false(bool(DataRegistry.item(str(ev.currency)).tradeable), "la valuta non si scambia")


func test_cassa_evento_frequenze_estratte_coincidono_con_le_mostrate() -> void:
	_make(_u(2026, 10, 25), 0, true, 9001)
	var cid := "crate_event_frost_feast"
	var n := 12000
	bank.stacks[cid] = n
	bank.stacks["event_snowflake"] = 25 * n
	var counts := {}
	for r in crates.open(cid, n, false):
		counts[r.rarity] = int(counts.get(r.rarity, 0)) + 1
	assert_eq(counts.values().reduce(func(a: int, b: int) -> int: return a + b), n)
	for row in sys.crate_odds("frost_feast"):
		var p := float(row.pct) / 100.0
		var got := float(counts.get(row.rarity, 0)) / float(n)
		var sigma := sqrt(p * (1.0 - p) / float(n))
		assert_almost_eq(got, p, 5.0 * sigma + 1e-9, "rarità %s: mostrata %.4f, estratta %.4f" % [row.rarity, p, got])


func test_cassa_evento_rullo_con_probabilita_reali_e_risultato_prima() -> void:
	_make(_u(2026, 10, 25), 0, true, 77)
	var cid := "crate_event_blossom"
	bank.stacks[cid] = 1
	bank.stacks["event_petal"] = 25
	var res := crates.open(cid, 1, true)
	assert_eq(res.size(), 1)
	var r: Dictionary = res[0]
	assert_eq(str(r.reel[int(r.reel_index)].d), str(r.def_id), "il vincitore è già nel rullo (risultato estratto prima)")
	assert_eq(bank.count(cid), 0, "risultato già applicato")
	# i riempitivi usano le probabilità nominali mostrate
	var cnt := {}
	var tiles := 0
	for i in 400:
		for t in crates.build_reel(cid, str(r.def_id), str(r.rarity)):
			cnt[t.r] = int(cnt.get(t.r, 0)) + 1
			tiles += 1
	for row in sys.crate_odds("blossom"):
		var p := float(row.pct) / 100.0
		var got := float(cnt.get(row.rarity, 0)) / float(tiles)
		assert_almost_eq(got, p, 5.0 * sqrt(p * (1.0 - p) / float(tiles)) + 0.002, "rullo: " + str(row.rarity))


# ------------------------------------------------------------------ dati

func test_dati_degli_eventi() -> void:
	var evs := DataRegistry.table("events")
	assert_eq(evs.size(), 4)
	var rules: Dictionary = DataRegistry.rules("event_rules").seasonal
	for ev in evs:
		assert_eq(ev.missions.size(), 4)
		assert_true(DataRegistry.has_def("npcs", str(ev.host)), "presentatore esistente")
		assert_false(Loc.t(ev.intro).is_empty())
		for m in ev.missions:
			assert_true(str(m.desc.it).contains(str(int(m.qty))) and str(m.desc.en).contains(str(int(m.qty))), "la descrizione dice la quantità")
			assert_true(ctx_text_ok(m.name) and ctx_text_ok(m.desc))
		var sum := 0
		for s in ev.shop:
			sum += int(s.price)
		assert_lte(sum, int(rules.max_drops_per_occurrence) + _mission_sum(ev), "il Negozio si completa in una edizione")
		assert_true(rules.cosmetic_only)
		assert_eq(float(ev.currency_drop_every_s), 300.0)
	assert_gte(float(rules.echo_every_s), 300.0)


func ctx_text_ok(t: Dictionary) -> bool:
	return not str(t.get("it", "")).is_empty() and not str(t.get("en", "")).is_empty()


func _mission_sum(ev: Dictionary) -> int:
	var s := 0
	for m in ev.missions:
		s += int(m.reward)
	return s


# ------------------------------------------------------------------ partita vera

func test_partita_vera_cadute_bonus_e_registro() -> void:
	var old_dir := SaveService.save_dir
	SaveService.save_dir = "user://test_seasonal_saves"
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 31337))
	var s := Game.system("seasonal") as SeasonalEventSystem
	assert_not_null(s, "registrato in SystemRegistry")
	s.set_wall(_u(2026, 10, 25), 0)
	(Game.system("unlock") as UnlockSystem).grant(UNLOCK)
	assert_true((Game.system("skills") as SkillSystem).start("wc_pine"))
	for i in 600:
		Game._on_step(0.1)
	s.set_wall(_u(2026, 10, 25) + 60, 0)
	for i in 3000:                                     # 5 minuti di gioco
		Game._on_step(0.1)
	assert_gte((Game.system("bank") as BankSystem).count("event_wax"), 1, "la valuta cade nella partita vera")
	assert_eq(Modifiers.total_add("crate_find_pct", ["all"]), 10.0, "bonus temporaneo nello stack vero")
	# salvataggio e ricarica
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_eq(Modifiers.total_add("crate_find_pct", ["all"]), 0.0)
	var s2 := Game.system("seasonal") as SeasonalEventSystem
	s2.set_wall(_u(2026, 10, 25) + 3600, 0)
	var res := Game.load_game(1)
	assert_true(bool(res.ok))
	s2.set_wall(_u(2026, 10, 25) + 3700, 0)
	assert_true(s2.status().mode == "event")
	Game.stop_game(false)
	s2.wall_source = SeasonalEventSystem.system_wall
	for sl in [1, 2, 3]:
		SaveService.delete_slot(sl)
	SaveService.save_dir = old_dir
	SaveService.autosave_enabled = true
