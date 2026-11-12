extends Node
## Catture della Sala dei Caveau e delle schede del gruppo (Album, Guardaroba, Bottega, Mercato, Emporio, Commesse).
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/capture_caveau.tscn -- <cartella> <stato: locked|empty|rich> [it|en]
## Prova anche i CLIC: ogni scheda viene premuta come farebbe il giocatore e si stampa la schermata che compare.

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://caveau"
var _state := "empty"
var _main: Control
var root: Window


func _ready() -> void:
	root = get_tree().root
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_state = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	SaveService.save_dir = "user://caveau_saves"
	SaveService.autosave_enabled = false
	Settings.set_value("locale", args[2] if args.size() > 2 else "it")
	Settings.set_value("tutorials", false)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await _frames(3)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, _state, tag]
	img.save_png(path)
	print("CATTURA ", path)


func _grant(tokens: Array) -> void:
	var un: Object = Game.system("unlock")
	for t in tokens:
		un.call("grant", str(t))


func _setup() -> void:
	var crates: Object = Game.system("crates")
	var bank: Object = Game.system("bank")
	_grant(["feature:crates"])
	if _state == "locked":
		return
	_grant(["feature:wardrobe", "feature:market", "feature:tradeup", "feature:refinery", "feature:collectors_challenge",
		"feature:golden_contract", "feature:bounties", "feature:estate"])
	if _state == "empty":
		return
	bank.call("add", "gold", 5000000, "qa")
	for k in ["key_t1", "key_t2", "key_t3"]:
		bank.call("add", k, 7, "qa")
	var n := 0
	for it in DataRegistry.items_by_category("crate"):
		n += 1
		bank.call("add", str(it.id), 2 + n * 3, "qa")
		if n >= 8:
			break
	for i in 6:
		(crates as CrateSystem).open("crate_millbrook", 1)


func _press(name: String) -> bool:
	var b: Node = _main.find_child(name, true, false)
	if b is BaseButton and b.is_visible_in_tree() and not (b as BaseButton).disabled:
		(b as BaseButton).pressed.emit()
		return true
	return false


func _which() -> String:
	var s: Node = _main.call("current_screen")
	return str(s.scene_file_path.get_file()) if s != null else "?"


func _run() -> void:
	Game.new_game(1, "normal", 20261023)
	_setup()
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(4)
	for k in 6:
		_press("WelcomeGo")
		_press("TutorialOk")
		await _frames(1)
	Settings.set_value("tutorials", false)
	_main.call("build_menu")
	_main.call("show_screen", "vault_hall")
	await _frames(8)
	await _snap("hall")
	# CLIC reali sulle schede: ogni clic deve cambiare schermata (o spiegare perché no)
	var seq := ["album", "wardrobe", "contracts", "refine", "bank", "challenge", "hall"]
	for t in seq:
		_main.call("show_screen", "vault_hall")
		await _frames(4)
		var before := _which()
		var ok := _press("Tab_" + t)
		await _frames(6)
		print("CLIC ", t, " premuto=", ok, " prima=", before, " dopo=", _which())
		await _snap("tab_" + t)
	if _state == "rich":
		# apertura vera: il risultato è già estratto prima del rullo; si guarda il pannello a rullo e il risultato
		_main.call("show_screen", "vault_hall")
		await _frames(6)
		print("APRI premuto=", _press("OpenButton"))
		await get_tree().create_timer(0.9).timeout
		await _snap("open_reel")
		await get_tree().create_timer(5.5).timeout
		await _snap("open_result")
	for sid in ["market", "shop", "orders", "bounty"]:
		var ok := bool(_main.call("show_screen", sid))
		await _frames(8)
		print("SCHERMATA ", sid, " ok=", ok)
		await _snap("scr_" + sid)
	print("CAVEAU_OK")
	get_tree().quit(0)
