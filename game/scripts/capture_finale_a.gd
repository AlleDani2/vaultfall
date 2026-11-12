extends Node
## Catture della revisione finale A (docs/review_1_0/34): avvisi in alto, Riepilogo con «Livello totale», benvenuto e pausa.
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path game --rendering-driver opengl3 --resolution 1600x900 \
##     res://scripts/capture_finale_a.tscn -- <cartella>

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://finale_a"
var _main: Control
var root: Window


func _ready() -> void:
	root = get_tree().root
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	SaveService.save_dir = "user://finale_a_saves"
	SaveService.autosave_enabled = false
	Settings.set_value("locale", "it")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await _frames(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, tag])
	print("CATTURA ", tag)


func _run() -> void:
	Game.new_game(1, "normal", 20261029)
	Settings.set_value("tutorials", false)
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(6)
	await _snap("benvenuto")
	Feedback.toggle_pause_menu(true)
	await _frames(4)
	await _snap("pausa_con_benvenuto")
	Feedback.close_pause_menu()
	await _frames(4)
	_main.get("_overlay").call("dismiss_active")
	await _frames(4)
	_main.call("show_screen", "summary")
	await _frames(6)
	await _snap("riepilogo_inizio")
	_main.call("show_screen", "market")
	await _frames(6)
	for t in ["Equipaggiato: Spada di Rame", "Venduto: Tronco di Pino ×20", "Venduto: Tronco di Pino ×20", "Hai raccolto 3 Patate",
			"Nuovo traguardo: Primo Taglio", "Livello 2: Taglialegna"]:
		_main.call("toast", t)
	await _frames(8)
	await _snap("avvisi_in_alto")
	get_tree().quit(0)
