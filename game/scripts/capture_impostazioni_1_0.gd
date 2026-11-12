extends SceneTree
## Catture delle Impostazioni 1.0 a schede: ogni scheda, conferma «Mantieni?», Comandi con conflitto e in attesa di un tasto,
## Accessibilità con daltonismo, alto contrasto e testo grande, barra dei suggerimenti del controller, tastiera a schermo.
##   xvfb-run -a -s "-screen 0 3840x2160x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_impostazioni_1_0.gd -- <cartella> <it|en> <larghezza> <altezza>
## Non tocca i salvataggi veri (cartella temporanea in user://) e riporta le impostazioni com'erano.
const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://capture_impostazioni_1_0"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_impostazioni_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").set("path", "user://capture_impostazioni_settings.cfg")
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	if args.size() > 3:
		DisplayServer.window_set_size(Vector2i(int(args[2]), int(args[3])))
		root.size = Vector2i(int(args[2]), int(args[3]))
	root.get_node("Settings").call("set_value", "reduce_motion", true)
	root.get_node("Settings").call("set_value", "tutorials", false)
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(25)
	_n += 1
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [_out, _n, shot_name])
	print("CATTURA ", shot_name, " ", img.get_size())


func _tour() -> void:
	var game: Node = root.get_node("Game")
	var st: Node = root.get_node("Settings")
	game.call("new_game", 1, "normal")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	var ov: Variant = main.get("_overlay")
	for i in 6:
		if ov != null and ov.call("is_busy"):
			ov.call("dismiss_active")
			await _frames(3)
	main.call("show_screen", "settings")
	await _frames(5)
	var scr: Control = main.call("current_screen")
	var tabs: TabContainer = scr.get("tabs")
	var names := ["gioco", "schermo", "audio", "accessibilita", "comandi", "dati"]
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await _shot("scheda_" + names[i])
	# Schermo: conferma «Mantieni?»
	tabs.current_tab = 1
	var panel: Node = scr.get("display_panel")
	panel.call("ask_keep", {})
	await _shot("mantieni")
	for d in root.find_children("*", "KeepDisplayDialog", true, false):
		d.call("keep")
	# Comandi: conflitto
	tabs.current_tab = 4
	var ctl: Node = scr.get("controls_panel")
	ctl.set("capturing", "bank")
	var ev := InputEventKey.new()
	ev.keycode = KEY_C
	ctl.call("capture_event", ev)
	await _shot("comandi_conflitto")
	ctl.call("_clear_message")
	(tabs.get_tab_control(4) as ScrollContainer).scroll_vertical = 100000
	await _shot("comandi_controller")
	(tabs.get_tab_control(4) as ScrollContainer).scroll_vertical = 0
	ctl.call("begin_capture", "hero")
	await _shot("comandi_attesa")
	ctl.call("cancel_capture")
	# Accessibilità
	tabs.current_tab = 3
	st.call("set_value", "colorblind", "deuteranopia")
	await _shot("daltonico_deuteranopia")
	st.call("set_value", "colorblind", "off")
	st.call("set_value", "high_contrast", true)
	await _shot("alto_contrasto")
	st.call("set_value", "high_contrast", false)
	st.call("set_value", "text_scale", 1.5)
	await _shot("testo_grande")
	st.call("set_value", "text_scale", 1.0)
	# controller: barra dei suggerimenti sul Riepilogo + tastiera a schermo
	main.call("show_screen", "summary")
	st.call("set_value", "pad_hints", "always")
	await _shot("suggerimenti_controller")
	st.call("set_value", "pad_glyphs", "playstation")
	await _shot("suggerimenti_playstation")
	st.call("set_value", "pad_glyphs", "xbox")
	st.call("set_value", "pad_hints", "auto")
	var le := LineEdit.new()
	le.custom_minimum_size = Vector2(300, 32)
	le.position = Vector2(300, 100)
	main.add_child(le)
	await _frames(2)
	var kb: Variant = OnScreenKeyboard.open_for(le)
	await _shot("tastiera_a_schermo")
	if kb != null:
		kb.call("close")
	game.call("stop_game", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_impostazioni_settings.cfg"))
	quit()
