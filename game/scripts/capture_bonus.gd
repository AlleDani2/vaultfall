extends SceneTree
## Catture del pannello «Bonus attivi» (rapporto 112). Scenario con fonti vere (evento, famigli, talenti, equipaggiamento...).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_bonus.gd -- <cartella> [it|en]
## Non tocca i salvataggi veri (cartella temporanea in user://).

const MAIN := "res://src/ui/main/MainScreen.tscn"

var _out := "user://capture_bonus"
var _n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_bonus_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "tutorials", false)
	if args.size() > 1:
		root.get_node("Settings").call("set_value", "locale", args[1])
	_tour.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name]
	root.get_texture().get_image().save_png(path)
	print("CATTURA ", path)


func _press(main: Node, node_name: String) -> void:
	var b := main.find_child(node_name, true, false) as Button
	if b != null:
		b.pressed.emit()


func _calm(main: Node) -> void:
	await _frames(20)
	for k in 60:
		if main.find_child("TutorialOk", true, false) == null and main.find_child("WelcomeGo", true, false) == null:
			break
		_press(main, "WelcomeGo")
		_press(main, "TutorialOk")
		await _frames(2)
	var toasts: Node = main.get("_toasts")
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	await _frames(2)


func _scenario(mods: Object) -> void:
	mods.call("set_source", "event:lantern_night", [{"key": "crate_find_pct:all", "value": 10}])
	mods.call("set_source", "perk:cooking", [{"key": "craft_quality_pct:cooking", "value": 8}])
	mods.call("set_source", "pet:pet_skill_mining", [{"key": "skill_double_pct:mining", "value": 3}])
	mods.call("set_source", "pet:pet_skill_fishing", [{"key": "skill_double_pct:fishing", "value": 3}])
	mods.call("set_source", "star:mining", [{"key": "skill_xp_pct:mining", "value": 12, "mode": "more"}])
	mods.call("set_source", "constellation", [{"key": "skill_xp_pct:all", "value": 28, "mode": "more"}, {"key": "skill_haste_pct:all", "value": 6}])
	mods.call("set_source", "talents", [{"key": "combat_dmg_pct", "value": 12}, {"key": "combat_crit_chance_pct", "value": 8}, {"key": "combat_hp_pct", "value": 10}])
	mods.call("set_source", "equip:weapon", [{"key": "combat_dmg_pct", "value": 20}, {"key": "combat_acc_pct", "value": 5}])
	mods.call("set_source", "equip:head", [{"key": "combat_arm_pct", "value": 6}])
	mods.call("set_source", "collection:collection_saltreach", [{"key": "crate_find_pct:all", "value": 140}, {"key": "skill_double_pct:fishing", "value": 3}])
	mods.call("set_source", "collection:collection_millbrook", [{"key": "crate_find_pct", "value": 110}])
	mods.call("set_source", "buff:feast", [{"key": "skill_xp_pct:all", "value": 10}])
	mods.call("set_source", "mode:cozy", [{"key": "skill_xp_pct:all", "value": 5}])
	mods.call("set_source", "shop:bank_slot", [{"key": "bank_slots", "value": 5}])
	mods.call("set_source", "guild:banner_scholars", [{"key": "skill_xp_pct:all", "value": 2.5}])
	mods.call("set_source", "prestige:partners", [{"key": "estate_prod_pct", "value": 12}])
	mods.call("set_source", "skilltool:woodcutting", [{"key": "skill_haste_pct:woodcutting", "value": 10}])
	mods.call("set_source", "run:perks", [{"key": "combat_dmg_pct", "value": 4}])
	mods.call("set_source", "perk:thievery", [{"key": "gold_gain_pct:thievery", "value": 10}, {"key": "offline_cap_hours", "value": 4}])


func _tour() -> void:
	var game: Node = root.get_node("Game")
	for s in [1, 2, 3]:
		root.get_node("SaveService").call("delete_slot", s)
	game.call("new_game", 1, "normal", 5)
	var data: Dictionary = root.get_node("GameState").get("data")
	if data.has("tutorial"):
		data.tutorial["off"] = true
	for t in ["feature:combat", "feature:market", "skill:cooking"]:
		(data.unlocks as Array).append(t)
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _calm(main)
	_scenario(root.get_node("Modifiers"))
	EventBus_changed()
	EventBus_screen("summary")
	await _frames(10)
	await _shot("riepilogo")
	var opener: Button = null
	for b in main.find_children("*", "Button", true, false):
		if str((b as Button).text) == "UI_UIA_BONUS_BTN" or str((b as Button).text).begins_with("Bonus attivi") or str((b as Button).text).begins_with("Active bonuses"):
			opener = b
	opener.pressed.emit()
	var dlg: Window = null
	for w in main.find_children("*", "AcceptDialog", true, false):
		if w.get_script() != null and str(w.get_script().resource_path).ends_with("BonusDialog.gd"):
			dlg = w
	await _frames(10)
	await _shot("dialogo")
	# apre tutti gli elenchi di fonti
	for b in dlg.find_children("*", "Button", true, false):
		if (b as Button).flat and str((b as Button).text).begins_with("▸"):
			(b as Button).pressed.emit()
	await _frames(4)
	await _shot("dialogo_fonti_aperte")
	var sc := dlg.find_child("Scroll", true, false) as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 700
		await _shot("dialogo_scorrimento")
	var se := dlg.find_children("*", "LineEdit", true, false)
	if se.size() > 0:
		(se[0] as LineEdit).text = "casse" if args_it() else "crate"
		(se[0] as LineEdit).text_changed.emit((se[0] as LineEdit).text)
		await _shot("dialogo_ricerca")
	quit()


func args_it() -> bool:
	var a := OS.get_cmdline_user_args()
	return not (a.size() > 1 and a[1] == "en")


func EventBus_changed() -> void:
	root.get_node("EventBus").emit_signal("modifiers_changed")


func EventBus_screen(id: String) -> void:
	root.get_node("EventBus").emit_signal("screen_requested", id, {})
