extends SceneTree
## QA119: un Apprendista assegnato a una costruzione singola (single_craft) ne produce più di una?
##   <godot> --headless --path game -s res://scripts/qa119_appr_single.gd -- <cartella_checkpoint> [azione]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ss := root.get_node("SaveService")
	var save_dir := "user://q119s_saves"
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir + "/" + f)
	for f in DirAccess.get_files_at(args[0]):
		DirAccess.copy_absolute(args[0] + "/" + f, save_dir + "/" + f)
	ss.set("save_dir", save_dir)
	ss.set("autosave_enabled", false)
	var G: Node = root.get_node("Game")
	G.call("load_game", 1)
	var aid := args[1] if args.size() > 1 else "smith_sword_copper"
	var ap: Object = G.call("system", "apprentices")
	var bank: Object = G.call("system", "bank")
	var data: Object = root.get_node("DataRegistry")
	var a: Dictionary = data.call("action", aid)
	var out_item := str(a.outputs[0].item)
	for i in a.inputs:
		bank.call("add", str(i.item), int(i.qty) * 2000, "qa119")
	print("Q119S slot=", ap.slots_total(), " can_assign=", ap.can_assign(aid))
	var before: int = bank.count(out_item) + bank.instance_count()
	print("Q119S assegna=", ap.assign(0, aid))
	var rep: Dictionary = ap.simulate_offline(3600.0)
	var after: int = bank.count(out_item) + bank.instance_count()
	print("Q119S dopo 1 h offline: istanze+pile %d -> %d  report=%s" % [before, after, JSON.stringify(rep).left(300)])
	for i in 600:
		G.call("_on_step", 0.1)
	print("Q119S dopo altri 60 s online: istanze=%d" % bank.instance_count())
	quit(0)
