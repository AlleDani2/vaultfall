extends GutTest
## Ottimizzazioni del Deposito (resoconto docs/audit_2026-10-22/122): le versioni veloci devono dare gli stessi risultati di
## quelle lente: insieme «in uso» = is_in_use(), mappa degli slot = worn_slot(), ordinamento nativo = confronto classico,
## anteprime di vendita in memoria che si rinnovano quando il Deposito cambia.

const BANK_SCREEN := "res://src/ui/screens/BankScreen.tscn"

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_bank_perf_cache_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	assert_true(Game.new_game(1, "normal", 12201))


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _bank() -> BankSystem:
	return Game.system("bank") as BankSystem


## Deposito con equipaggiamento in doppio, un pezzo indossato e uno bloccato.
func _stock() -> void:
	var b := _bank()
	b.state.slots_bought = int(b.state.slots_bought) + 500
	var n := 0
	for d in DataRegistry.items_by_category("equipment"):
		b.add(str(d.id), 2, "test")
		n += 1
		if n >= 25:
			break
	b.add("log_pine", 7, "test")
	var cb := Game.system("combat") as CombatSystem
	for inst in b.state.instances:
		if cb.equip(str(inst.uid)):
			break
	if b.state.instances.size() > 3:
		b.state.instances[3].locked = true


func test_insieme_in_uso_e_mappa_degli_slot_coincidono_con_le_funzioni_per_pezzo() -> void:
	_stock()
	var b := _bank()
	var cb := Game.system("combat") as CombatSystem
	var set := b.in_use_set()
	var map := cb.worn_slot_map()
	assert_gt(b.state.instances.size(), 10)
	assert_gt(set.size(), 0, "almeno un pezzo e' indossato")
	for inst in b.state.instances:
		var uid := str(inst.uid)
		assert_eq(set.has(uid), b.is_in_use(uid), "in uso: " + uid)
		assert_eq(str(map.get(uid, "")), cb.worn_slot(uid), "slot: " + uid)
	for u in b.duplicate_uids():
		assert_false(b.is_in_use(str(u)), "un doppione non e' mai in uso")


func test_ordinamento_nativo_uguale_al_confronto_classico() -> void:
	_stock()
	var scr = (load(BANK_SCREEN) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	scr._on_group("gear")                    # F15: l'equipaggiamento sta nell'Armeria, non in «Tutto»
	assert_gt(scr._entries.size(), 30)
	for f in ["recent", "name", "value", "tier", "worn"]:
		for d in [true, false]:
			scr._sort = f
			scr._descending = d
			scr._rebuild_entries()
			var got: Array = scr._entries.map(func(e: Dictionary) -> Variant: return e.key)
			var ref: Array = scr._entries.duplicate()
			ref.shuffle()
			ref.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var va: Variant = a.sort_name if f == "name" else (a.worn_n if f == "worn" else a[f])
				var vb: Variant = b.sort_name if f == "name" else (b.worn_n if f == "worn" else b[f])
				if va == vb:
					return a.sort_name < b.sort_name if a.sort_name != b.sort_name else a.key < b.key
				return va > vb if d else va < vb)
			assert_eq(got, ref.map(func(e: Dictionary) -> Variant: return e.key), "ordine %s %s" % [f, d])


func test_anteprima_dei_doppioni_in_memoria_si_rinnova_quando_il_deposito_cambia() -> void:
	_stock()
	var b := _bank()
	var mk := Game.system("market") as MarketSystem
	var p1 := PlanMemo.dupes(b, mk, true)
	var p2 := PlanMemo.dupes(b, mk, true)
	assert_true(is_same(p1, p2), "stesso Deposito: stesso piano, nessun ricalcolo")
	assert_false(is_same(p1, PlanMemo.dupes(b, mk, true, true)), "fresh: ricalcolato sempre")
	var first_def := str(b.state.instances[0].def)
	var before := int(PlanMemo.dupes(b, mk, true).pieces)
	b.add(first_def, 3, "test")
	var after := int(PlanMemo.dupes(b, mk, true).pieces)
	assert_gt(after, before, "tre pezzi in piu' dello stesso oggetto: l'anteprima li conta")
	assert_eq(after, int(SellRules.collect_dupes(b, mk, true).pieces), "uguale al calcolo diretto")


func test_il_pannello_del_carro_nasce_solo_quando_serve() -> void:
	var b := _bank()
	var scr = (load(BANK_SCREEN) as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({})
	assert_null(scr._carro, "Deposito non pieno e Carro vuoto: nessun pannello costruito")
	var n := b.free_slots()
	var ids: Array = []
	for d in DataRegistry.items_by_category("material"):
		ids.append(str(d.id))
	var i := 0
	while b.free_slots() > 0 and i < ids.size():
		b.add(ids[i], 1, "test")
		i += 1
	assert_gt(n, 0)
	scr.refresh()
	if b.is_full():
		assert_not_null(scr._carro, "Deposito pieno: il pannello compare")
		assert_true(scr._carro.visible)
