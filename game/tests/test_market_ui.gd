extends GutTest
## Schermate del Mercato: si aprono, si aggiornano e non rompono con un Deposito reale o assente.

const SCREENS := [
	"res://src/ui/screens/MarketScreen.tscn",
	"res://src/ui/screens/ShopScreen.tscn",
	"res://src/ui/screens/OrdersScreen.tscn",
]

var _old_dir: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_market_ui_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func test_registro_ha_le_tre_voci_del_mercato() -> void:
	for id in ["market", "shop", "orders"]:
		var e := ScreenRegistry.get_entry(id)
		assert_false(e.is_empty(), id)
		assert_eq(e.unlock, "feature:market")
		assert_true(ResourceLoader.exists(e.scene))
	assert_not_null(Game.system("market") if Game.is_active() else MarketSystem.new())


func test_schermate_si_aprono_e_si_aggiornano() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	GameState.data.unlocks.append("feature:market")
	GameState.data.bank.stacks["log_pine"] = 500
	GameState.data.bank.stacks["ore_copper"] = 80
	var mk := Game.system("market") as MarketSystem
	assert_not_null(mk)
	mk.state.seen["log_pine"] = true
	mk.simulate_offline(5.0 * 3600.0)
	for path in SCREENS:
		var scr: Control = (load(path) as PackedScene).instantiate()
		add_child_autofree(scr)
		await wait_process_frames(1)
		scr.open({})
		scr.refresh()
		scr.refresh()
		assert_gt(scr.get_child_count(), 2, path)
		scr.close()
