extends SceneTree
## QA119: cosa succede a chi parte con una costruzione singola (single_craft) e resta via 8 h: quanto tempo si perde?
##   <godot> --headless --path game -s res://scripts/qa119_offline_single.gd -- <cartella_checkpoint> [azione] [ore]

var _rep: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ss := root.get_node("SaveService")
	var save_dir := "user://q119o_saves"
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir + "/" + f)
	for f in DirAccess.get_files_at(args[0]):
		DirAccess.copy_absolute(args[0] + "/" + f, save_dir + "/" + f)
	ss.set("save_dir", save_dir)
	ss.set("autosave_enabled", false)
	var G: Node = root.get_node("Game")
	G.call("load_game", 1)
	root.get_node("EventBus").connect("offline_progress", func(sec: float, rep: Dictionary) -> void: _rep = rep; print("Q119O evento offline sec=", sec))
	var aid := args[1] if args.size() > 1 else "smith_sickle_copper"
	var hours := float(args[2]) if args.size() > 2 else 8.0
	var sk: Object = G.call("system", "skills")
	var bank: Object = G.call("system", "bank")
	var a: Dictionary = root.get_node("DataRegistry").call("action", aid)
	for i in a.inputs:
		bank.call("add", str(i.item), int(i.qty) * 50, "qa119")
	print("Q119O can_start=", sk.can_start(aid), " start=", sk.start(aid))
	var xp0: float = sk.xp(str(a.skill))
	G.call("_on_long_gap", hours * 3600.0)
	print("Q119O dopo %.1f h: azione attiva='%s' XP %s: %.0f -> %.0f" % [hours, sk.current_action(), a.skill, xp0, sk.xp(str(a.skill))])
	print("Q119O report: ", JSON.stringify(_rep).left(1800))
	quit(0)
