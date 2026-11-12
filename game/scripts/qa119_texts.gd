extends SceneTree
## QA119: elenco dei testi «A cosa serve» / «Come si usa» per ogni sottocategoria (una riga distinta per tipo), per rilettura.
##   <godot> --headless --path game -s res://scripts/qa119_texts.gd -- [it|en]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	root.get_node("Settings").call("set_value", "locale", args[0] if args.size() > 0 else "it")
	var data: Object = root.get_node("DataRegistry")
	var IU: GDScript = load("res://src/ui/ItemUse.gd")
	var seen := {}
	print("Q119T start")
	var ids: Array = data.all_items().keys()
	ids.sort()
	var empty := 0
	for iid in ids:
		var it: Dictionary = data.item(str(iid))
		var p: String = IU.call("purpose", str(iid))
		var h: String = IU.call("howto", str(iid))
		if p.strip_edges() == "":
			empty += 1
			print("Q119T VUOTO ", iid)
		if p.contains("nessuna mansione") or p.contains("no skill uses"):
			print("Q119T NESSUNUSO ", iid)
		var key := "%s/%s|%s|%s" % [it.get("category", ""), it.get("subcategory", ""), p.left(60), h.left(40)]
		if seen.has(key):
			continue
		seen[key] = true
		print("Q119T [%s/%s] %s :: SERVE: %s || USO: %s" % [it.get("category", ""), it.get("subcategory", ""), iid, p, h])
	print("Q119T vuoti: ", empty)
	quit(0)
