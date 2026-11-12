extends SceneTree
## QA119: arbitraggio. Per ogni oggetto che si compra (Mercato/Emporio) confronta il prezzo di acquisto con il ricavo di
## vendita (stato di mercato iniziale e con tendenza/Gazzetta al massimo). Stampa chi rende più di quanto costa.
##   <godot> --headless --path game -s res://scripts/qa119_arb.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ss := root.get_node("SaveService")
	ss.set("save_dir", "user://q119a_saves")
	ss.set("autosave_enabled", false)
	DirAccess.make_dir_recursive_absolute("user://q119a_saves")
	var G: Node = root.get_node("Game")
	G.call("new_game", 1, "normal", 20261119)
	var mk: Object = G.call("system", "market")
	var data: Object = root.get_node("DataRegistry")
	var n := 0
	var bad := 0
	for iid in data.all_items():
		var id := str(iid)
		if not mk.is_tradeable(id) or mk.category_of(id) == "":
			continue
		var buy: float = float(mk.buy_price_npc(id))
		var sell: float = float(mk.price_sell(id))
		if buy <= 0.0 or sell <= 0.0:
			continue
		n += 1
		var ratio := sell / buy
		if ratio > 0.7:
			bad += 1
			print("Q119A %s compra %.1f vende %.1f rapporto %.2f" % [id, buy, sell, ratio])
	print("Q119A confrontati ", n, " con rapporto vendita/acquisto > 0,7: ", bad)
	# Emporio: merci a prezzo fisso
	var shop: Array = data.table("shop")
	var g := 0
	for e in shop:
		if str(e.get("section", "")) == "goods" and e.get("item", "") != "":
			var it: String = str(e.item)
			var price := float(e.get("price", 0))
			var sell2: float = float(mk.price_sell(it)) if mk.is_tradeable(it) else 0.0
			g += 1
			if sell2 > price * 0.5:
				print("Q119A EMPORIO %s costa %.1f, si rivende a %.1f" % [it, price, sell2])
	print("Q119A merci Emporio: ", g)
	quit(0)
