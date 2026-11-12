extends "res://scripts/novice_base.gd"
## Sonda (resoconto 121): il primo combattimento del novizio. Con la spada di rame indossata e senza armatura né cibo, il clic su
## «Inizia a combattere» deve fare QUALCOSA di visibile (partire, o chiedere conferma).
##   xvfb-run <godot> --path game --rendering-driver opengl3 --resolution 1280x720 -s res://scripts/probe_combat_click.gd -- <cartella>

const MAIN := "res://src/ui/main/MainScreen.tscn"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "/tmp/probe_combat"
	loc = a[1] if a.size() > 1 else "it"
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveService").set("save_dir", "user://probe_combat_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "locale", loc)
	root.get_node("Settings").call("set_value", "tutorials", false)
	_run.call_deferred()


func _run() -> void:
	var game: Node = root.get_node("Game")
	game.call("new_game", 1, "normal", 11)
	system("quests").call("mark_intro_seen")
	var un := uns()
	for t in ["feature:combat", "skill:hero", "zone:millbrook"]:
		if not un.has(t):
			un.append(t)
	var bank: Object = system("bank")
	bank.call("add", "sword_copper", 1, "probe")
	_main = (load(MAIN) as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await frames(10)
	_main.call("show_screen", "combat")
	await frames(10)
	var sb := TutorialTargets.find(self, "combat_start") as Button
	say("pulsante: %s disabilitato=%s" % [shown(sb), str(sb.disabled)])
	await shot("prima")
	await click(sb, "Inizia a combattere")
	await frames(20)
	say("in combattimento: %s" % str(system("combat").call("in_combat")))
	var dlg: Window = null
	for w in root.find_children("*", "AcceptDialog", true, false):
		if (w as Window).visible:
			dlg = w
	say("dialogo aperto: %s" % ("sì: " + str(dlg.dialog_text if dlg != null else "") if dlg != null else "no"))
	await shot("dopo")
	save_diary()
	quit(0)
