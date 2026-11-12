extends SceneTree
## Catture del tutorial guidato (controllo a occhio): benvenuto -> barra laterale -> Pino -> Missioni -> Rame -> come
## muoversi -> Livello e Maestria, poi alcuni passi agganciati agli sblocchi (Coda, Pozioni, Combattimento, Casse, Tenuta,
## Prestigio). Serve un display (anche virtuale):
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##       -s res://scripts/capture_tutorial.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const START := "res://src/ui/start/StartScreen.tscn"
const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_tutorial"
var _n := 0
var _main: Control
var _dir: Object


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_tutorial_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	root.get_node("Settings").call("set_value", "tutorials", true)
	root.get_node("Settings").call("set_value", "reduce_motion", false)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	_n += 1
	var img := root.get_texture().get_image()
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	img.save_png(path)
	print("CATTURA ", path, " ", img.get_size(), " passo=", _dir.call("current_step_id") if _dir != null else "", " chiave=", _dir.call("highlighted_key") if _dir != null else "")


## Fa partire subito il prossimo passo (senza i tempi reali di attesa) e lo fotografa.
func _step(name: String, expect: String) -> void:
	for r in 3:
		_dir.set("_gap", 0.0)
		_dir.set("_poll", 0.0)
		await _frames(4)
		if _dir.call("current_step_id") == expect:
			break
	if _dir.call("current_step_id") != expect:
		print("ATTENZIONE: atteso ", expect, " trovato '", _dir.call("current_step_id"), "'")
	await _shot(name)


func _run() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _frames(3)
	start.call("start_new", 1)
	await _frames(2)
	start.queue_free()
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	_dir = _main.call("tutorial")
	await _shot("benvenuto")
	_press("WelcomeGo")
	await _frames(3)
	await _step("sidebar", "g_sidebar")
	_dir.call("press_next")
	await _step("apri_taglialegna", "g_open_pine")
	_main.call("show_screen", "skill:woodcutting")
	await _frames(3)
	await _step("inizia_col_pino", "g_pine")
	var pine: Button = TutorialTargets.find(self, "action:wc_pine")
	if pine != null:
		pine.pressed.emit()
	await _frames(3)
	await _step("missioni", "g_quests")
	_dir.call("press_next")
	# fine della prima missione
	var qs: Object = game.call("system", "quests")
	var need: int = int(qs.call("quest_def", "main_c0_q1").objectives[0].qty)
	root.get_node("EventBus").emit_signal("action_completed", "wc_pine", [{"item": "log_pine", "qty": need}])
	game.get("sim").call("tick", 0.1)
	qs.call("claim", "main_c0_q1")
	await _frames(3)
	await _step("apri_miniera", "g_open_copper")
	_main.call("show_screen", "skill:mining")
	await _frames(3)
	await _step("rame", "g_copper")
	var cu: Button = TutorialTargets.find(self, "action:mine_copper")
	if cu != null:
		cu.pressed.emit()
	await _frames(3)
	await _step("come_muoversi", "g_move")
	_dir.call("press_next")
	await _step("in_alto", "g_move2")
	_dir.call("press_next")
	await _step("livello", "b_level")
	_dir.call("press_next")
	await _step("maestria", "b_mastery")
	_dir.call("press_next")
	await _step("livello_vs_maestria", "b_compare")
	_dir.call("press_next")
	# sblocchi reali: i passi successivi
	var unlocks: Array = root.get_node("GameState").data.unlocks
	for t in ["feature:perks", "feature:combat", "skill:hero", "feature:crates", "feature:estate", "feature:prestige", "skill:alchemy", "skill:cooking"]:
		if not unlocks.has(t):
			unlocks.append(t)
	var sk: Object = game.call("system", "skills")
	_main.call("build_menu")
	await _frames(3)
	_main.call("show_screen", "skill:woodcutting")
	await _frames(3)
	await _step("talenti_di_mansione", "f_perks")
	_dir.call("press_next")
	_main.call("show_screen", "skill:alchemy")
	await _frames(3)
	await _step("pozioni", "f_potions")
	_dir.call("press_next")
	await _step("cibo_menu", "f_feast")
	_main.call("show_screen", "skill:cooking")
	await _frames(3)
	await _step("cibo_banchetti", "f_feast")
	_dir.call("press_next")
	await _step("combattimento_menu", "f_combat")
	_main.call("show_screen", "combat")
	await _frames(3)
	await _step("combattimento", "f_combat")
	_dir.call("press_later")
	_main.call("show_screen", "guide")
	await _frames(3)
	await _shot("guida")
	quit(0)


func _press(node_name: String) -> void:
	var b := _main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()
