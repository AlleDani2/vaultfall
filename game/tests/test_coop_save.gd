extends GutTest
## COOP-1: lo stato coop sta nel salvataggio personale come sezione ADDITIVA (nessun bump di schema), sopravvive a
## salvataggio e ricarica, i salvataggi vecchi lo ricevono vuoto, e nulla fuori dallo stato influenza i risultati.

const Env := preload("res://tests/helpers/coop_env.gd")
const GOLDEN := "res://tests/golden/save_v0_1_fine_cap1.sav"
const NOW := 1760000000

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_coop_save_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Env.free_all()
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _friend_code(created: int = 1700555555) -> String:
	var f: Object = Env.make(9, 55, "warrior", 6, created)
	return f.coop.export_hero_code(NOW)


func test_schema_invariato_e_sezione_additiva() -> void:
	assert_false(FileAccess.get_file_as_string("res://src/core/SaveCodec.gd").to_lower().contains("coop"), "nessuna migrazione per il coop")
	assert_false(GameState.default_state().has("coop"), "la sezione la crea il sistema, il resto dello stato è invariato")
	assert_true(Game.new_game(1, "normal", 3))
	assert_true(GameState.data.has("coop"))
	assert_eq(int(GameState.data.schema_version), SaveCodec.SCHEMA_VERSION)
	var co := Game.system("coop") as CoopSystem
	assert_not_null(co)
	assert_eq(co.companions().size(), 0)
	assert_eq(co.state.v, 1)


func test_salvataggio_vecchio_riceve_lo_stato_coop_vuoto() -> void:
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	assert_eq(SaveService.write_atomic(2, FileAccess.get_file_as_bytes(GOLDEN)), OK)
	var lr := Game.load_game(2)
	assert_true(lr.ok)
	var co := Game.system("coop") as CoopSystem
	assert_true(GameState.data.has("coop"))
	assert_eq(co.companions().size(), 0)
	assert_eq(int(GameState.data.schema_version), SaveCodec.SCHEMA_VERSION)


func test_compagni_e_risultati_sopravvivono_a_salva_e_ricarica() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var co := Game.system("coop") as CoopSystem
	co.set_my_name("Developer")
	var r := co.import_code(_friend_code(), NOW)
	assert_true(r.ok, str(r))
	var cid: String = str(co.companions()[0].id)
	co.set_enabled(cid, false)
	var week := str(CoopWeekly.week_of(NOW).id)
	var res := {"uid": "00000000000000ab", "name": "Giulia", "class": "ranger", "spec": "", "level": 70, "week": week, "floor": 12,
		"t": 345.5, "dmg": 123456789.123456, "issued": NOW}
	assert_true(co.import_code(CoopCodec.pack("R", 1, res), NOW).ok)
	var before := JSON.stringify(GameState.data.coop, "", true, true)
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	var lr := Game.load_game(1)
	assert_true(lr.ok, str(lr))
	var co2 := Game.system("coop") as CoopSystem
	assert_eq(JSON.stringify(GameState.data.coop, "", true, true), before, "lo stato coop è identico dopo il ricarico")
	assert_eq(co2.companions().size(), 1)
	assert_false(co2.companions()[0].enabled, "l'interruttore si ricorda")
	assert_eq(co2.my_name(), "Developer")
	var lb := co2.leaderboard(week)
	assert_eq(lb.size(), 1)
	assert_almost_eq(float(lb[0].dmg), 123456789.123456, 1e-6, "piena precisione")
	assert_eq(co2.my_uid(), co.my_uid(), "l'identità della partita non cambia")


func test_scheda_salvata_manomessa_si_ripulisce_al_carico() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var co := Game.system("coop") as CoopSystem
	assert_true(co.import_code(_friend_code(), NOW).ok)
	var c: Dictionary = GameState.data.coop.companions[0]
	c.sheet.st.hp = 1.0e30
	c.sheet.level = 50000
	c.sheet["items"] = {"sword": 1}
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	var co2 := Game.system("coop") as CoopSystem
	assert_eq(co2.companions().size(), 0, "con una chiave vietata la scheda cade")
	# senza la chiave vietata: i numeri tornano ai limiti
	assert_true(co2.import_code(_friend_code(1700666666), NOW).ok)
	var c2: Dictionary = GameState.data.coop.companions[0]
	c2.sheet.st.hp = 1.0e30
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	assert_true(Game.load_game(1).ok)
	var lim := CoopSheet.limits_for(DataRegistry, int((Game.system("coop") as CoopSystem).companions()[0].sheet.level))
	assert_lte(float((Game.system("coop") as CoopSystem).companions()[0].sheet.st.hp), float(lim.hp))


func test_nulla_fuori_dallo_stato_influenza_il_risultato() -> void:
	# due sistemi con lo STESSO stato (uno con cache calde, uno freddo) danno gli stessi numeri
	var a: Object = Env.make(5, 55, "warrior", 6, 1700000000)
	a.unlock_raid("collectors_den")
	var f: Object = Env.make(9, 55, "ranger", 6, 1700777777)
	assert_true(f.share_to(a, NOW).ok)
	var fx1: Dictionary = a.combat.eg.raid_fx("collectors_den", a.coop.party_with_companions("collectors_den", []))
	var copy: Dictionary = JSON.parse_string(JSON.stringify(a.state.coop, "", true, true))
	var b: Object = Env.make(5, 55, "warrior", 6, 1700000000)
	b.unlock_raid("collectors_den")
	b.coop.from_state(copy)
	b.state["coop"] = b.coop.state
	var fx2: Dictionary = b.combat.eg.raid_fx("collectors_den", b.coop.party_with_companions("collectors_den", []))
	assert_eq(JSON.stringify(fx1, "", true, true), JSON.stringify(fx2, "", true, true), "stesso stato, stessi effetti")
	# il codice si può ricostruire dalla copia dello stato (solo lo stato conta)
	assert_eq(a.coop.my_uid(), b.coop.my_uid())
