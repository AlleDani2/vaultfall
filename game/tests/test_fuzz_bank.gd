extends GutTest
## QA 72 - proprieta' del Deposito con operazioni casuali (seme fisso): conservazione di oggetti e valute, nessuna scorta
## negativa, capacita' rispettata, uid unici. I difetti noti (F5: overflow di add()/add_currency()) sono corretti: controlli veri.

var _r := RandomNumberGenerator.new()


func before_each() -> void:
	Game.new_game(1, "normal", 31337)
	_r.seed = 72


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func test_operazioni_casuali_conservano_oggetti_e_valute() -> void:
	var bank := Game.system("bank") as BankSystem
	var stackable: Array = []
	var singles: Array = []
	for id in DataRegistry.all_items():
		var d: Dictionary = DataRegistry.all_items()[id]
		if str(d.get("category", "")) == "currency" or id == "gold":
			continue
		if bool(d.get("stackable", false)):
			stackable.append(id)
		elif str(d.get("category", "")) in ["equipment", "tool", "skin", "relic", "cosmetic"]:      # istanze: Armeria e Spazio (F15)
			singles.append(id)
	var shadow := {}
	var gold := bank.gold()
	for i in 3000:
		var op := _r.randi() % 6
		var qty: int = [0, 1, 2, 5, 50, -1, -100, 1000][_r.randi() % 8]
		if op <= 1:
			var id: String = stackable[_r.randi() % stackable.size()]
			var added := bank.add(id, qty, "fuzz")
			assert_between(added, 0, maxi(qty, 0), "add restituisce 0..qty")
			shadow[id] = int(shadow.get(id, 0)) + added
		elif op == 2:
			var id2: String = stackable[_r.randi() % stackable.size()]
			var have := int(shadow.get(id2, 0))
			var ok := bank.remove(id2, qty)
			if qty > have or qty < 0:
				assert_false(ok, "remove oltre la scorta/negativo rifiutato")
			elif ok:
				shadow[id2] = have - qty
		elif op == 3:
			var id3: String = singles[_r.randi() % singles.size()]
			var added2 := bank.add(id3, mini(qty, 3), "fuzz")
			assert_gte(added2, 0)
		elif op == 4:
			var n := absi(qty) % 500
			var before := bank.gold()
			var ok2 := bank.spend_gold(n)
			assert_eq(ok2, before >= n)
			gold = bank.gold()
			assert_eq(gold, before - (n if ok2 else 0))
			bank.add_gold(_r.randi_range(0, 100))
		else:
			bank.discard(stackable[_r.randi() % stackable.size()], qty)
			shadow.clear()           # discard cambia le scorte: si riparte dal Deposito
			for k in bank.owned_stack_ids():                # Carro di Ritiro compreso
				shadow[k] = bank.count(str(k))
		if i % 100 == 0:
			assert_eq(FuzzLib.invariants(), [], "invarianti al passo %d" % i)
			assert_lte(bank.used_slots(), bank.capacity(), "capacita'")
			# F15, R-SP-7: nessun oggetto perso fra le due classi; free_slots mai negativo; l'Armeria rispetta il tetto
			assert_eq(bank.used_slots() + bank.gear_used(), bank.state.stacks.size() + bank.instance_count(), "Spazio + Armeria = pile + istanze")
			assert_gte(bank.free_slots(), 0)
			assert_gte(bank.gear_free(), 0)
			assert_lte(bank.gear_used(), bank.gear_cap(), "tetto dell'Armeria")
			var gear_counted := 0
			for inst in bank.state.instances:
				if bank.is_gear_def(str(inst.def)):
					gear_counted += 1
			assert_eq(gear_counted, bank.gear_used(), "contatore dell'Armeria = istanze di categoria libera")
	for id4 in shadow:
		if int(shadow[id4]) > 0:
			assert_eq(bank.count(id4), int(shadow[id4]), "conservazione di " + id4)
	var uids := {}
	for inst in bank.list_instances():
		assert_false(uids.has(inst.uid), "uid unico")
		uids[inst.uid] = true


func test_overflow_di_quantita_F5() -> void:
	var bank := Game.system("bank") as BankSystem
	var id := ""
	for k in DataRegistry.all_items():
		if bool(DataRegistry.all_items()[k].get("stackable", false)) and str(DataRegistry.all_items()[k].get("category", "")) != "currency":
			id = k
			break
	bank.add(id, 9223372036854775807, "fuzz")
	bank.add(id, 5, "fuzz")
	bank.add_gold(9223372036854775807)
	bank.add_gold(10)
	assert_gt(bank.count(id), 0, "scorta positiva")
	assert_gt(bank.gold(), 0, "oro positivo")
	assert_eq(bank.count(id), BankSystem.QTY_CAP, "saturazione")
	assert_eq(bank.gold(), BankSystem.QTY_CAP, "saturazione")
	assert_eq(BankSystem.sat_add(5, 6), 11)
