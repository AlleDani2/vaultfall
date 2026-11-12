class_name BankStress
extends RefCounted
## Stato di stress del Deposito per le prove di layout (resoconto 123): 5+ valute, Deposito al 90% (avviso «quasi pieno»),
## Carro con pezzi (pannello dei rimedi), pezzi indossati («E»), nomi lunghi. Usato da `scripts/bank_stress.gd` (catture e giro
## a più risoluzioni) e da `tests/test_bank_layout.gd`. Non è codice di gioco: lavora solo sui sistemi pubblici.

const CURRENCIES := ["raid_seal", "rift_shard", "bounty_mark", "vault_shard", "commission_token", "stardust"]


## `mode`: "nearly" = 90% pieno (avviso «quasi pieno»), "full" = pieno con pezzi nel Carro (il Carro si svuota da solo appena
## si libera un posto, quindi non coesiste con il 90%), "both" = come "full" e la prova forza anche l'avviso (caso peggiore:
## avviso e pannello insieme), "empty" = Deposito quasi vuoto con il solo oro (caso normale).
static func prepare(game: Node, mode: String = "both", n_currencies: int = 5) -> void:
	var un: Object = game.call("system", "unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.call("grant", tok)
	for t in ["feature:market", "feature:combat", "skill:hero"]:
		un.call("grant", t)
	var tree_root: Node = (Engine.get_main_loop() as SceneTree).root       # autoload per nome: questo file compila anche da uno script -s
	var data: Dictionary = tree_root.get_node("GameState").get("data")
	var reg: Node = tree_root.get_node("DataRegistry")
	var loc: Node = tree_root.get_node("Loc")
	data.skills["hero"] = {"xp": 0.0, "level": 25, "record_level": 25, "stars": 0, "perks": {}, "unlocked": true}
	var bank := game.call("system", "bank") as BankSystem
	var combat := game.call("system", "combat") as CombatSystem
	bank.add_gold(1234567890)
	if mode == "empty":
		return
	for i in clampi(n_currencies - 1, 0, CURRENCIES.size()):
		bank.add_currency(CURRENCIES[i], 98765 + i * 1000)
	# pezzi di equipaggiamento: alcuni indossati, alcuni doppioni
	var worn: Array[String] = []
	for d in ["plate_gloves_copper", "plate_helm_copper", "sword_copper", "plate_body_copper", "plate_legs_copper"]:
		if reg.call("has_item", d):
			worn.append(bank.add_instance({"def": d, "quality": "fine"}))
			bank.add_instance({"def": d, "quality": "normal"})
	for u in worn:
		combat.equip(u)
	# pile con i nomi più lunghi, fino al 90% (o al 100% per "full")
	var names: Array = []
	var all_items: Dictionary = reg.call("all_items")
	for id in all_items:
		var def: Dictionary = all_items[id]
		var cat := str(def.get("category", ""))
		if cat in ["material", "food", "potion", "consumable", "seed", "ammo"] and not bank.is_currency(str(id)):
			names.append([loc.call("t", def.get("name", {})).length(), str(id)])
	names.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var cap := bank.capacity()
	var target := cap if (mode == "full" or mode == "both") else int(ceil(cap * 0.9))
	for pair in names:
		if bank.used_slots() >= target:
			break
		bank.add(str(pair[1]), 123456, "stress")
	var stash := "plate_boots_copper" if reg.call("has_item", "plate_boots_copper") else "sword_copper"
	if mode == "full" or mode == "both":
		bank.add_instance({"def": stash, "quality": "normal"})            # oltre il tetto: finisce nel Carro
		bank.add(str(names[names.size() - 1][1]), 5, "stress")
