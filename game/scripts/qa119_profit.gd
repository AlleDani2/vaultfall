extends SceneTree
## QA119: profitto orario netto delle azioni (vendita al Mercato dei prodotti meno costo degli ingredienti al prezzo di
## vendita) su un checkpoint, confrontato con gph(tier). Segnala profitti > 1,5 x gph (R-EC-3) e azioni in perdita.
##   <godot> --headless --path game -s res://scripts/qa119_profit.gd -- <cartella_checkpoint>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ss := root.get_node("SaveService")
	var save_dir := "user://q119p_saves"
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir + "/" + f)
	for f in DirAccess.get_files_at(args[0]):
		DirAccess.copy_absolute(args[0] + "/" + f, save_dir + "/" + f)
	ss.set("save_dir", save_dir)
	ss.set("autosave_enabled", false)
	var G: Node = root.get_node("Game")
	G.call("load_game", 1)
	var data: Object = root.get_node("DataRegistry")
	var sk: Object = G.call("system", "skills")
	var mk: Object = G.call("system", "market")
	var rows: Array = []
	for aid in data.all_actions():
		var a: Dictionary = data.action(str(aid))
		var skill := str(a.get("skill", ""))
		if skill == "farming" or sk.level(skill) < int(a.get("level_req", 1)):
			continue
		var hr: Dictionary = sk.hourly(str(aid))
		if hr.is_empty():
			continue
		var gain := float(hr.get("gold", 0.0))
		for k in hr.items:
			gain += float(mk.quote_sell(str(k), maxi(1, roundi(float(hr.items[k]) * 10.0)))) / 10.0     # 10 h di produzione in un colpo (saturazione)
		var cost := 0.0
		var cyc := float(hr.cycles)
		for i in a.get("inputs", []):
			var item := str(i.get("item", "")) if i is Dictionary else str(i[0])
			var q := float(i.get("qty", 1)) if i is Dictionary else float(i[1])
			cost += q * cyc * float(mk.price_sell(item)) * 0.0 + float(mk.quote_sell(item, maxi(1, roundi(q * cyc * 10.0)))) / 10.0
		var tier := int(a.get("tier", 1))
		var gph := float(Formulas.gph(tier))
		rows.append([str(aid), skill, int(a.get("level_req", 1)), tier, gain - cost, gph, bool(a.get("single_craft", false)), cyc])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return float(x[4]) / maxf(1.0, float(x[5])) > float(y[4]) / maxf(1.0, float(y[5])))
	print("Q119P azioni valutate: ", rows.size())
	for r in rows.slice(0, 25):
		print("Q119P TOP %s %s lv%d t%d net %.0f/h gph %.0f ratio %.2f single=%s cicli/h %.0f" % [r[0], r[1], r[2], r[3], r[4], r[5], float(r[4]) / maxf(1.0, float(r[5])), r[6], r[7]])
	var neg := 0
	for r in rows:
		if float(r[4]) < 0.0 and not r[6]:
			neg += 1
	print("Q119P in perdita (ripetibili): ", neg)
	for r in rows.slice(rows.size() - 12, rows.size()):
		print("Q119P BOTTOM %s %s lv%d t%d net %.0f/h gph %.0f ratio %.2f" % [r[0], r[1], r[2], r[3], r[4], r[5], float(r[4]) / maxf(1.0, float(r[5]))])
	quit(0)
