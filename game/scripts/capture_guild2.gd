extends SceneTree
## Giro fotografico GUILD-2: Compendio (4 schede), Fazioni, Luoghi Segreti, Deposito con la finestra «Scarta», registro riassunto.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_guild2.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_guild2"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_guild2_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	root.get_node("Settings").call("set_value", "tutorials", false)
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name, " codice ", code)


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var state: Node = root.get_node("GameState")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 11)
	var d: Dictionary = state.get("data")
	for t in ["feature:combat", "feature:crates", "feature:market", "feature:factions", "feature:estate", "feature:mercenaries",
			"skill:woodcutting", "skill:mining", "skill:fishing", "skill:foraging", "skill:trapping"]:
		(d.unlocks as Array).append(t)
	var skills: Dictionary = d.skills
	for sk in ["woodcutting", "mining", "fishing"]:
		skills[sk] = {"xp": 0.0, "level": 62}
	var comp: Object = game.call("system", "compendium")
	for p in ["pet_skill_woodcutting", "pet_skill_mining", "pet_crate_waspling", "pet_crate_waspling"]:
		comp.call("found_pet", p)
	for t in ["title_firmament", "title_vaultbreaker", "title_master_mining"]:
		comp.call("grant_title", t)
	comp.call("grant_cosmetic", "cosmetic_frame_woodcutting_bronze")
	var bank: Object = game.call("system", "bank")
	bank.call("add", "map_fragment", 14, "prova")
	bank.call("add", "log_pine", 40, "prova")
	bank.call("add", "rune_t1", 120, "prova")
	var mk: Object = game.call("system", "market")
	mk.call("add_reputation", "merchant_league", 1300)
	var qs: Object = game.call("system", "quests")
	qs.call("accept", "side_merchant_league_1")
	qs.call("accept", "side_order_of_wardens_1")
	root.get_node("EventBus").emit_signal("objective_event", "sell_market", {"gold": 10000})
	game.get("sim").call("tick", 0.1)
	game.get("sim").call("tick", 2.5)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	var wb := main.find_child("WelcomeGo", true, false) as Button
	if wb != null:
		wb.pressed.emit()
		await _frames(2)
	var tut := main.find_child("TutorialOk", true, false) as Button
	if tut != null:
		tut.pressed.emit()
		await _frames(2)
	main.call("show_screen", "compendium")
	await _shot("compendio_imprese")
	for tab in [1, 2, 3]:
		var scr: Control = main.call("current_screen")
		scr.get("_tabs").set("current_tab", tab)
		scr.call("refresh")
		await _shot("compendio_scheda_%d" % tab)
	main.call("show_screen", "factions")
	await _shot("fazioni")
	main.call("show_screen", "secrets")
	await _shot("luoghi_segreti")
	var sec: Control = main.call("current_screen")
	sec.call("_on_reveal", "hidden_grove")
	sec.call("_on_explore", "hidden_grove")
	await _frames(2)
	sec.call("refresh")
	await _shot("luoghi_segreti_esplorazione")
	main.call("show_screen", "bank")
	var bscr: Control = main.call("current_screen")
	bscr.set("_selected", "log_pine")
	bscr.call("_mark_dirty")
	await _frames(3)
	bscr.call("_on_discard")
	await _shot("deposito_scarta")
	for lv in range(2, 13):
		root.get_node("EventBus").emit_signal("level_up", "woodcutting", lv)
	for i in 14:
		root.get_node("EventBus").emit_signal("notice", "warning", "x", {"reason": "bank_full", "item": "Cassa della Valle"})
	main.call("_flush_digest")
	main.call("show_screen", "hero")
	await _shot("registro_riassunto_eroe")
	quit(0)
