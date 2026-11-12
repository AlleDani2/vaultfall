extends GutTest
## Rapporto 36 BASSA B1: gli avvisi in alto non coprono la striscia dell'Obiettivo e non si accavallano con lo striscione
## («Impresa sbloccata»): stanno sotto l'una e sotto l'altro. I clic restano liberi.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const MS := preload("res://src/ui/main/MainScreen.gd")

var _old_dir: String
var _saved: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_toast_layout_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_saved = Settings._values.duplicate(true)
	Settings.set_value("tutorials", false)


func after_each() -> void:
	Fx.reset()
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings._values = _saved
	Settings.apply_all()


func _main(sz: Vector2) -> Control:
	assert_true(Game.new_game(1, "normal", 7))
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = sz
	await wait_process_frames(3)
	assert_true(main.show_screen("bank"))
	main.call("_on_ui_tick")
	await wait_process_frames(3)
	return main


func test_gli_avvisi_stanno_sotto_la_striscia_dell_obiettivo() -> void:
	for sz in [Vector2(1280, 720), Vector2(1024, 576)]:
		var main := await _main(sz)
		var strip := main.find_child("GoalStrip", true, false) as Control
		assert_not_null(strip)
		assert_true(strip.is_visible_in_tree(), "premessa: all'inizio c'e' un obiettivo da mostrare in questa schermata")
		var toasts := main.find_child("Toasts", true, false) as Control
		main.toast("Prova avviso")
		await wait_seconds(0.4)
		assert_gte(toasts.get_global_rect().position.y, strip.get_global_rect().end.y - 0.5, "sotto la striscia (%s)" % str(sz))
		assert_eq(toasts.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		main.queue_free()
		await wait_process_frames(2)
		Game.stop_game(false)


func test_gli_avvisi_non_si_accavallano_con_lo_striscione() -> void:
	var main := await _main(Vector2(1280, 720))
	var toasts := main.find_child("Toasts", true, false) as Control
	main.toast("Prima dello striscione")
	await wait_seconds(0.3)
	assert_true(Fx.banner("Impresa sbloccata", "Prova"))
	await wait_seconds(0.4)
	assert_true(Fx.banner_active())
	assert_gte(toasts.get_global_rect().position.y, FxBanner.Y_REST + FxBanner.H, "sotto lo striscione")
	main.toast("Durante lo striscione")
	await wait_process_frames(4)
	assert_gte(toasts.get_global_rect().position.y, FxBanner.Y_REST + FxBanner.H, "anche i nuovi avvisi")
