extends GutTest
## QA-UX gruppo B (resoconto 41): regressioni dei difetti visivi corretti.
##  - rullo: il vincitore resta sotto l'indicatore anche se il pannello viene dimensionato DOPO l'avvio;
##  - nessuna schermata del gruppo B è più larga dello spazio utile a 1280x720 (altrimenti spinge fuori la barra laterale).

const REEL := preload("res://src/ui/screens/CrateReel.tscn")
const CRATE := "crate_millbrook"

var _old_reduce: bool
var _old_dir: String


func before_each() -> void:
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ux_b_%d" % Time.get_ticks_usec()
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


func test_rullo_ridimensionato_dopo_l_avvio_resta_allineato() -> void:
	Settings.set_value("reduce_motion", true)
	var reel: CrateReel = REEL.instantiate()
	reel.size = Vector2(480, 190)          # larghezza minima: il pannello non è ancora stato disposto
	add_child_autofree(reel)
	reel.play(_tiles(), 52, 0.5)
	reel.size = Vector2(780, 190)          # layout definitivo
	var centre := reel.scroll + 390.0
	assert_between(centre, 52.0 * reel.pitch(), 52.0 * reel.pitch() + CrateReel.TILE_W,
		"l'indicatore cade sulla tessera vincente anche dopo il ridimensionamento")


func test_rullo_in_corso_usa_la_larghezza_attuale() -> void:
	Settings.set_value("reduce_motion", false)
	var reel: CrateReel = REEL.instantiate()
	reel.size = Vector2(480, 190)
	add_child_autofree(reel)
	reel.play(_tiles(), 52, 0.5)
	reel.size = Vector2(780, 190)
	reel.skip()
	var centre := reel.scroll + 390.0
	assert_between(centre, 52.0 * reel.pitch(), 52.0 * reel.pitch() + CrateReel.TILE_W)


func test_schermate_gruppo_b_entrano_in_1280() -> void:
	Game.new_game(1, "normal", 4242)
	var un: Object = Game.system("unlock")
	for t in ["combat", "crates", "wardrobe", "market", "estate", "mercenaries", "orders", "prestige", "constellations", "skill_prestige", "talents"]:
		un.grant("feature:" + t)
	un.grant("skill:hero")
	un.grant("dungeon:cursed_granary")
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := main.get("_host") as Control
	for sid in ["combat", "hero", "talents", "dungeon", "vault_hall", "wardrobe", "album", "market", "shop", "orders", "estate", "guild", "prestige"]:
		main.call("show_screen", sid)
		await get_tree().process_frame
		await get_tree().process_frame
		var sc := host.get_child(host.get_child_count() - 1) as Control
		var wide := 0.0
		for c in sc.get_children():
			if c is Container:
				wide = maxf(wide, (c as Control).get_combined_minimum_size().x)
		assert_lt(wide, 790.0, "%s: larghezza minima %d oltre lo spazio utile" % [sid, int(wide)])
	Game.stop_game(false)
