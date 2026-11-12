extends GutTest
## QA 72 - Casse: probabilita' che sommano a 1, nessuna apertura senza chiave, ripetibilita' col seme (anche dopo
## salvataggio/caricamento), Deposito pieno (F3: perdita del premio -> pending finche' non corretto).

var _old_dir: String
var _dir: String


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_dir = FuzzLib.tmp_save_dir("gutc")
	SaveService.save_dir = _dir
	SaveService.autosave_enabled = false


func after_all() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, 4):
		SaveService.delete_slot(s)
	FuzzLib.rm_dir(_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func _crates() -> Array:
	var out: Array = []
	var cr := Game.system("crates") as CrateSystem
	for k in DataRegistry.all_items():
		if str(DataRegistry.all_items()[k].get("category", "")) == "crate" and cr.is_crate(k):
			out.append(k)
	return out


func _kit(cid: String, n: int) -> void:
	var cr := Game.system("crates") as CrateSystem
	var bank := Game.system("bank") as BankSystem
	var def := cr.crate_def(cid)
	bank.add(cid, n, "fuzz")
	if def.get("key") != null:
		bank.add(str(def.key), n, "fuzz")
	if def.has("open_cost"):
		bank.add(str(def.open_cost.item), n * int(def.open_cost.qty), "fuzz")


func _digest(res: Array) -> String:
	var parts := PackedStringArray()
	for x in res:
		parts.append("%s|%s|%s|%s" % [x.def_id, x.rarity, str(x.instance.get("float", "")), str(x.stop_frac)])
	return "\n".join(parts).sha256_text()


func test_probabilita_sommano_a_uno() -> void:
	Game.new_game(1, "normal", 1)
	var cr := Game.system("crates") as CrateSystem
	for cid in _crates():
		var s := 0.0
		for v in cr.nominal_fractions(cid).values():
			s += float(v)
		assert_almost_eq(s, 1.0, 1e-9, "nominali " + cid)
		for since in 160:
			var sw := 0.0
			for v in cr.rarity_weights(cid, since).values():
				assert_false(is_nan(float(v)))
				assert_between(float(v), -1e-12, 1.0 + 1e-9)
				sw += float(v)
			assert_almost_eq(sw, 1.0, 1e-6, "%s since=%d" % [cid, since])


func test_nessuna_apertura_senza_chiave() -> void:
	Game.new_game(1, "normal", 2)
	var cr := Game.system("crates") as CrateSystem
	var bank := Game.system("bank") as BankSystem
	for cid in _crates():
		var def := cr.crate_def(cid)
		if def.get("key") == null and not def.has("open_cost"):
			continue
		bank.add(cid, 1000, "fuzz")
		var t0 := Time.get_ticks_msec()
		assert_eq(cr.open(cid, 100000, false), [], "senza chiave non si apre " + cid)
		assert_lt(Time.get_ticks_msec() - t0, 2000)
		assert_eq(bank.count(cid), 1000)
		bank.remove(cid, 1000)
	assert_eq(cr.open("crate_inesistente", 5, false), [])
	assert_eq(cr.open(_crates()[0], 0, false), [])
	assert_eq(cr.open(_crates()[0], -5, false), [])


func test_ripetibilita_col_seme_e_dopo_salvataggio() -> void:
	var cid: String = _crates()[0]
	var digs: Array = []
	for rep in 2:
		Game.new_game(1, "normal", 2468)
		Game.ctx.modifiers.set_source("fuzz:cap", [{"key": "bank_slots", "value": 5000}])
		_kit(cid, 300)
		digs.append(_digest((Game.system("crates") as CrateSystem).open(cid, 200, true)))
	assert_eq(digs[0], digs[1], "stesso seme, stesse aperture")
	Game.new_game(1, "normal", 2468)
	Game.ctx.modifiers.set_source("fuzz:cap", [{"key": "bank_slots", "value": 5000}])
	_kit(cid, 300)
	var cr := Game.system("crates") as CrateSystem
	cr.open(cid, 100, true)
	SaveService.save_now()
	var cont := _digest(cr.open(cid, 100, true))
	assert_true(Game.load_game(1).ok)
	Game.ctx.modifiers.set_source("fuzz:cap", [{"key": "bank_slots", "value": 5000}])
	var after := _digest((Game.system("crates") as CrateSystem).open(cid, 100, true))
	assert_eq(after, cont, "dopo il caricamento le aperture proseguono identiche")


func test_deposito_pieno_non_perde_il_premio_F3() -> void:
	Game.new_game(1, "normal", 99)
	var cid: String = _crates()[0]
	var cr := Game.system("crates") as CrateSystem
	var bank := Game.system("bank") as BankSystem
	_kit(cid, 10)
	var junk := ""
	for k in DataRegistry.all_items():
		var d: Dictionary = DataRegistry.all_items()[k]
		if not bool(d.get("stackable", false)) and str(d.get("category", "")) == "skin":      # F15: un collezionabile occupa Spazio (l'equipaggiamento no)
			junk = k
			break
	while bank.free_slots() > 0 and bank.add(junk, 1, "fuzz") > 0:
		pass
	var crates_before := bank.count(cid)
	var keys_before := bank.count(str(cr.crate_def(cid).key))
	var opened_before := int(cr.state.opened)
	# Deposito pieno (resoconto 117): si apre lo stesso, ogni premio non-famiglio finisce nel Carro di Ritiro, nulla si perde
	assert_false(cr.blocked_by_space(cid))
	assert_eq(cr.openable_now(cid), 10)
	var res := cr.open(cid, 10, false)
	assert_eq(res.size(), 10)
	var kept := 0
	var in_bank := 0
	for x in res:
		if x.kind != "pet":
			kept += 1
			if bool(x.carro):
				assert_eq(str(x.uid), "")
			else:
				assert_ne(str(x.uid), "", "o nel Carro o nel Deposito (l'ultima Cassa o chiave libera un posto)")
				in_bank += 1
	assert_eq(bank.count(cid), crates_before - 10)
	assert_eq(bank.count(str(cr.crate_def(cid).key)), keys_before - 10)
	assert_eq(int(cr.state.opened), opened_before + 10)
	assert_eq(bank.overflow_instance_count() + in_bank, kept, "nessun premio perso")
	# liberando 3 posti il Carro si scarica da solo (in ordine di arrivo)
	var before := bank.overflow_instance_count()
	var free0 := bank.free_slots()            # i posti liberati dalle pile di Casse e chiavi finite
	var drops: Array = []
	for u in bank.state.instances.slice(0, 3):
		drops.append(str(u.uid))
	for u in drops:
		bank.remove_instance(u)
	bank.tick(0.1)
	assert_eq(bank.free_slots(), maxi(0, free0 + 3 - before))
	assert_eq(bank.overflow_instance_count(), maxi(0, before - free0 - 3))
