extends SceneTree
## Sonda (QA overflow 107): i dialoghi e i popup degli OptionButton stanno dentro la finestra?
##   xvfb-run -a <godot> --path game --rendering-driver opengl3 -s res://scripts/popup_probe.gd -- <WxH> <scala>

func _initialize() -> void:
	Engine.max_fps = 0
	var a := OS.get_cmdline_user_args()
	root.get_node("SaveService").set("save_dir", "user://qa_b_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	_run.call_deferred(a[0], float(a[1]))


func _f(n: int) -> void:
	for i in n:
		await process_frame


func _run(wh: String, scale: float) -> void:
	root.get_node("Game").call("load_game", 1)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _f(4)
	root.content_scale_factor = scale
	var p := wh.split("x")
	DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	root.size = Vector2i(int(p[0]), int(p[1]))
	await _f(4)
	var view := root.get_visible_rect()
	print("area ", view.size)
	# 1. dialoghi grandi
	for sz in [Vector2i(700, 560), Vector2i(620, 460), Vector2i(1000, 700)]:
		var d := ConfirmationDialog.new()
		d.dialog_text = "prova"
		main.add_child(d)
		d.popup_centered(sz)
		await _f(3)
		var r := Rect2(Vector2(d.position), Vector2(d.size))
		print("dialogo ", sz, " -> ", r, " dentro=", view.encloses(r))
		d.queue_free()
		await _f(2)
	# 2. OptionButton in basso a destra
	main.call("show_screen", "combat")
	await _f(6)
	var found := 0
	for ob in main.find_children("*", "OptionButton", true, false):
		var o := ob as OptionButton
		if not o.is_visible_in_tree() or o.item_count == 0:
			continue
		found += 1
		o.show_popup()
		await _f(3)
		var pm := o.get_popup()
		var r2 := Rect2(Vector2(pm.position), Vector2(pm.size))
		print("optionbutton ", o.get_global_rect(), " popup ", r2, " dentro=", view.encloses(r2))
		pm.hide()
		await _f(2)
	print("optionbutton provati ", found)
	quit(0)
