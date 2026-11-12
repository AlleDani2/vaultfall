extends SceneTree
## QA119: prova MECCANICA di tutte le azioni di costruzione/lavorazione. Per ogni azione con ingredienti: dà i materiali
## al Deposito, porta la mansione al livello richiesto, avvia, fa scorrere il tempo e controlla che (a) parta, (b) produca
## l'uscita nel Deposito, (c) le azioni `single_craft` si fermino dopo UNA costruzione. Stampa «Q119C ...» per ogni anomalia.
##   <godot> --headless --path game -s res://scripts/qa119_craftall.gd
## Nessun salvataggio vero toccato (cartella temporanea).

var G: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	G = root.get_node("Game")
	var ss := root.get_node("SaveService")
	ss.set("save_dir", "user://q119c_saves")
	ss.set("autosave_enabled", false)
	DirAccess.make_dir_recursive_absolute("user://q119c_saves")
	G.call("new_game", 1, "normal", 20261119)
	var data: Object = root.get_node("DataRegistry")
	var sk: Object = G.call("system", "skills")
	var bank: Object = G.call("system", "bank")
	var un: Object = G.call("system", "unlock")
	var n_ok := 0
	var n_bad := 0
	var by_skill := {}
	for aid in data.all_actions():
		var a: Dictionary = data.action(str(aid))
		var skill := str(a.get("skill", ""))
		if (a.get("inputs", []) as Array).is_empty() or (a.get("outputs", []) as Array).is_empty():
			continue
		if skill == "farming":
			continue
		un.call("grant", "skill:" + skill)
		var lvl := int(a.get("level_req", 1))
		var guard := 0
		while sk.level(skill) < lvl and guard < 300:
			guard += 1
			var p: Array = sk.xp_progress(skill)
			sk.add_xp(skill, maxf(1.0, float(p[1]) - float(p[0]) + 1.0))
		for i in a.inputs:
			var item := str(i.get("item", "")) if i is Dictionary else str(i[0])
			var q := int(i.get("qty", 1)) if i is Dictionary else int(i[1])
			bank.add(item, q * 5 + 5, "qa119")
		var reason: String = sk.can_start(str(aid))
		if reason != "":
			print("Q119C NON PARTE %s (%s lv%d): %s" % [aid, skill, lvl, reason])
			n_bad += 1
			by_skill[skill] = int(by_skill.get(skill, 0)) + 1
			continue
		var main_out := str(a.outputs[0].get("item", ""))
		var before: int = bank.count(main_out)
		if not sk.start(str(aid)):
			print("Q119C START FALLITO ", aid)
			n_bad += 1
			continue
		var t := 0.0
		var dur := float(a.get("time_s", 3.0)) * 3.0 + 5.0
		while t < dur:
			G.call("_on_step", 0.1)
			t += 0.1
		var after: int = bank.count(main_out)
		var running: bool = sk.current_action() == str(aid)
		var single := bool(a.get("single_craft", false))
		if after <= before and not bool(a.get("quality", false)):
			print("Q119C NESSUN OUTPUT %s -> %s (before %d after %d) running=%s" % [aid, main_out, before, after, running])
			n_bad += 1
		elif single and (after - before) > 1 and not (a.outputs[0].get("qty", 1) is Array):
			print("Q119C SINGLE_CRAFT RIPETUTO %s: %d copie" % [aid, after - before])
			n_bad += 1
		elif single and running:
			print("Q119C SINGLE_CRAFT NON SI FERMA ", aid)
			n_bad += 1
		else:
			n_ok += 1
		sk.stop()
	print("Q119C fine ok=%d anomalie=%d per mansione=%s" % [n_ok, n_bad, str(by_skill)])
	quit(0)
