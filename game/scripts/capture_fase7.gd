extends SceneTree
## Catture e misure della fase F7 del progetto di interfaccia (docs/ui_redesign/07, F7): mansioni e Coltivazione.
## Per Taglialegna, Forgiatura, Sartoria, Gioielleria e Coltivazione: pagine di scorrimento (altezza del contenuto / altezza
## visibile) a livello 1 e a livello 40, e una cattura della schermata a livello 20. Funziona anche sul progetto PRIMA della
## fase (stesse chiamate pubbliche), per il confronto.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase7.gd -- <cartella> [it|en] [prefisso]
## Partita nuova con seme 4242, tutto sbloccato, tutorial spenti. Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const SKILLS := {"woodcutting": "taglialegna", "smithing": "forgiatura", "tailoring": "sartoria", "jewelcrafting": "gioielleria",
	"farming": "coltivazione"}

var _out := "user://capture_fase7"
var _prefix := ""
var _main: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase7_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 2:
		_prefix = args[2]
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm(main: Node) -> void:
	for k in 60:
		if main.find_child("TutorialOk", true, false) == null and main.find_child("WelcomeGo", true, false) == null:
			break
		var b := main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _shot(name: String) -> void:
	await _frames(12)
	await _calm(_main)
	var path := "%s/%s.png" % [_out, name]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


## Altezza del contenuto che scorre / altezza visibile del primo ScrollContainer della schermata.
func _pages(screen: Node) -> float:
	for sc in screen.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if s.size.y < 50.0 or s.get_child_count() == 0:
			continue
		var content := s.get_child(0) as Control
		return snappedf(content.get_combined_minimum_size().y / s.size.y, 0.01)
	return 0.0


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	_main = main
	await _frames(30)
	await _calm(main)
	main.call("build_menu")
	var sk: Object = game.call("system", "skills")
	print("AREA_LOGICA ", root.get_visible_rect().size)
	for sid in SKILLS:
		for lv in [1, 40]:
			sk.get("state")[sid]["level"] = lv
			root.get_node("Settings").call("set_value", "seen_intro", [])      # prima visita: nessun filtro acceso di partenza
			main.call("show_screen", "skill:" + sid)
			await _frames(20)
			await _calm(main)
			var scr: Node = main.get("_current")
			print("PAGINE ", sid, " Lv", lv, " ", _pages(scr))
	for sid in SKILLS:           # seconda visita: «Solo ciò che posso fare» parte acceso (solo dopo F7)
		sk.get("state")[sid]["level"] = 40
		root.get_node("Settings").call("set_value", "seen_intro", ["skills_list:" + sid])
		main.call("show_screen", "skill:" + sid)
		await _frames(20)
		await _calm(main)
		print("PAGINE_SECONDA_VISITA ", sid, " Lv40 ", _pages(main.get("_current")))
	sk.call("start", "wc_pine")
	for i in 5:
		game.call("_on_step", 0.1)
	for sid in SKILLS:
		sk.get("state")[sid]["level"] = 20
		root.get_node("Settings").call("set_value", "seen_intro", [])
		main.call("show_screen", "skill:" + sid)
		await _shot(_prefix + SKILLS[sid])
	quit()
