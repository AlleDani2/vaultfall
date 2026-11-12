extends SceneTree
## Catture della fase F11 del progetto di interfaccia (docs/ui_redesign/07, F11): Sala dei Caveau, Album, Guardaroba.
##   xvfb-run -a -s "-screen 0 2200x1300x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_fase11.gd -- <cartella> <suffisso> [it|en]
## Seme 4242, tutto sbloccato, tutorial spenti, animazioni ridotte. Qualche cassa aperta per riempire Album e Guardaroba.
## Non tocca i salvataggi veri.

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_fase11"
var _suffix := ""
var _main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_suffix = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_fase11_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	root.get_node("Settings").call("set_value", "seen_intro", [])
	if args.size() > 2:
		root.get_node("Settings").call("set_value", "locale", args[2])
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _calm() -> void:
	for k in 60:
		if _main.find_child("TutorialOk", true, false) == null and _main.find_child("WelcomeGo", true, false) == null:
			break
		var b := _main.find_child("WelcomeGo", true, false) as Button
		if b != null:
			b.pressed.emit()
		var t := _main.find_child("TutorialOk", true, false) as Button
		if t != null:
			t.pressed.emit()
		await _frames(2)
	var toasts: Node = _main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _shot(name: String) -> void:
	_main.call("_on_ui_tick")
	await _frames(12)
	await _calm()
	var path := "%s/%s_%s.png" % [_out, name, _suffix]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	root.get_texture().get_image().save_png(abs_path)
	print("CATTURA ", name)


func _host_screen() -> Node:
	var host: Control = _main.get("_host")
	return host.get_child(host.get_child_count() - 1)


func _run() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 4242)
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	var bank: Object = game.call("system", "bank")
	bank.get("state")["slots_bought"] = 5000
	var crates: Object = game.call("system", "crates")
	var dr: Node = root.get_node("DataRegistry")
	var ids: Array = []
	for it in dr.call("items_by_category", "crate"):
		ids.append(str(it.id))
	# riempie un po' l'Album: apre alcune casse con chiavi date apposta; restano casse con e senza chiave
	for k in ids.size():
		var cid: String = ids[k]
		bank.call("add", cid, 4 + k)
		var cdef: Dictionary = crates.call("crate_def", cid)
		if cdef.get("key") != null and k < 6:
			bank.call("add", str(cdef.key), 10)
			crates.call("open", cid, 3, false)
	var worn := 0
	for inst in bank.call("list_instances"):
		if str(inst.get("kind", "")) == "skin" and worn < 8:
			if bool(crates.call("equip", str(inst.uid))):
				worn += 1
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(30)
	await _calm()
	_main.call("build_menu")
	await get_root().get_tree().create_timer(7.0).timeout       # lascia sparire il riquadro «Impresa sbloccata» delle casse aperte
	await _calm()
	var first: String = ids[0]
	var nokey := ""
	for cid in ids:
		if int(crates.call("openable_now", cid)) < 1 and int(bank.call("count", cid)) > 0:
			nokey = cid
			break
	_main.call("show_screen", "vault_hall", {"crate": first})
	await _shot("1_sala_cassa_selezionata")
	if nokey != "":
		_main.call("show_screen", "vault_hall", {"crate": nokey})
		await _shot("2_sala_cassa_senza_chiave")
	_main.call("show_screen", "album")
	await _shot("3_album")
	_main.call("show_screen", "wardrobe")
	var wd := _host_screen()
	await _shot("4_guardaroba")
	wd.set("_selected_slot", "weapon")
	wd.call("_rebuild", true)
	await _shot("5_guardaroba_slot_scelto")
	wd.call("_set_tab", "bonus")
	await _shot("6_guardaroba_bonus_attivi")
	quit()
