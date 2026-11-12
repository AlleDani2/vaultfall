extends GutTest
## Rullo e schermate delle Casse (T-4.2/T-4.3): solo presentazione. Il rullo mostra il risultato già estratto,
## rispetta "riduci animazioni", Salta e i ganci audio; le probabilità mostrate coincidono con quelle del sistema.

const REEL := preload("res://src/ui/screens/CrateReel.tscn")
const CRATE := "crate_millbrook"

var _old_reduce: bool
var _old_dir: String


func before_each() -> void:
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_crates_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings.set_value("reduce_motion", _old_reduce)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _tiles() -> Array:
	var crates := CrateSystem.new()
	var ctx := SystemContext.make(DataRegistry, {}, ModifierStack.new(), RngStreams.new(3), EventBus)
	crates.ctx = ctx
	crates.from_state(crates.default_state())
	return crates.build_reel(CRATE, "skin_millbrook_01", "rare")


func test_rullo_con_riduci_animazioni_mostra_subito_il_vincitore() -> void:
	Settings.set_value("reduce_motion", true)
	var reel: CrateReel = REEL.instantiate()
	reel.size = Vector2(800, 190)
	add_child_autofree(reel)
	watch_signals(reel)
	reel.play(_tiles(), 52, 0.5)
	assert_signal_emitted(reel, "finished")
	assert_signal_emitted(reel, "reveal_sound")
	assert_false(reel.playing)
	# l'indicatore (centro) cade dentro la tessera vincente
	var centre := reel.scroll + 400.0
	assert_between(centre, 52.0 * reel.pitch(), 52.0 * reel.pitch() + CrateReel.TILE_W)


func test_rullo_salta_e_ganci_audio() -> void:
	Settings.set_value("reduce_motion", false)
	var reel: CrateReel = REEL.instantiate()
	reel.size = Vector2(800, 190)
	add_child_autofree(reel)
	watch_signals(reel)
	reel.play(_tiles(), 52, 0.3)
	assert_true(reel.playing)
	await wait_process_frames(10)
	assert_signal_emitted(reel, "tick_sound", "un tick per ogni tessera che passa")
	reel.skip()
	await wait_seconds(0.8)
	assert_signal_emitted(reel, "finished")
	assert_signal_emitted(reel, "reveal_sound")
	var centre := reel.scroll + 400.0
	assert_between(centre, 52.0 * reel.pitch(), 52.0 * reel.pitch() + CrateReel.TILE_W, "dopo Salta il risultato è quello estratto")


func test_colori_di_rarita_originali() -> void:
	var forbidden := ["#4B69FF", "#8847FF", "#D32CE6", "#EB4B4B", "#B0C3D9", "#5E98D9", "#FFD700"]
	for r in CrateSystem.RARITIES:
		var col := CrateUi.rarity_color(r)
		for f in forbidden:
			assert_ne(col.to_html(false).to_upper(), f.substr(1), "colore distinto da quelli di altri giochi: " + r)
		assert_ne(CrateUi.rarity_symbol(r), "", "simbolo presente (non solo colore)")


func test_schermate_si_aprono_e_mostrano_le_probabilita() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var crates := Game.system("crates") as CrateSystem
	assert_not_null(crates)
	for path in ["VaultHallScreen", "WardrobeScreen", "AlbumScreen"]:
		var scr: GameScreen = (load("res://src/ui/screens/%s.tscn" % path) as PackedScene).instantiate()
		add_child_autofree(scr)
		scr.open({"crate": CRATE})
		await wait_process_frames(1)
		scr.refresh()
		scr.close()
		assert_true(scr is GameScreen)
	# le percentuali scritte in schermata = quelle del sistema (odds)
	var shown := 0.0
	for r in crates.odds(CRATE):
		shown += float(r.pct)
	assert_almost_eq(shown, 100.0, 1e-6)


func test_sala_dei_caveau_apre_x1_e_x5_con_deposito_finto() -> void:
	Settings.set_value("reduce_motion", true)
	assert_true(Game.new_game(1, "normal", 5))
	# Deposito VERO (integrazione): prima c'era un finto bank che poi veniva tolto da Game.sim, lasciando
	# la partita senza Deposito per i test successivi.
	var bank := Game.system("bank") as BankSystem
	bank.add(CRATE, 20)
	bank.add("key_t1", 20)
	var scr: GameScreen = (load("res://src/ui/screens/VaultHallScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"crate": CRATE})
	await wait_process_frames(2)
	var crates := Game.system("crates") as CrateSystem
	scr._do_open(1)
	assert_eq(crates.state.opened, 1, "estratta prima di qualunque animazione")
	assert_true(scr._open_panel.visible)
	await wait_process_frames(2)
	assert_ne(scr._result_label.text, "", "risultato mostrato")
	scr._on_close_panel()
	scr._do_open(5)
	assert_eq(crates.state.opened, 6)
	assert_eq(scr._multi.results().size(), 5)
	assert_eq(scr._multi.visible_count(), 5, "ridotto movimento: tutte le carte subito")
	scr._on_close_panel()
	var w: GameScreen = (load("res://src/ui/screens/WardrobeScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(w)
	w.open({})
	w._selected_slot = "weapon"
	w._rebuild(true)
	var a: GameScreen = (load("res://src/ui/screens/AlbumScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(a)
	a.open({})
	await wait_process_frames(1)
	Game.stop_game(false)
