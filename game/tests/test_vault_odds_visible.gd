extends GutTest
## F11 (docs/ui_redesign/06 §3.13, brief F11): REGOLA 5 di CLAUDE.md e docs/24. Le probabilità della cassa selezionata sono
## visibili SENZA alcun clic, in ogni stato della Sala dei Caveau (pronta, senza chiave, con la sequenza di apertura finita),
## a 1280×720 e a 1024×576; il contenuto completo con le probabilità per finitura è a UN clic; il riordino non cambia
## l'estrazione (stessi oggetti, stesso seme) e non nasconde nulla dietro un Disclosure.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1024, 576)]

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_auto: bool
var _old_reduce: bool
var _old_fps: int


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	_old_auto = bool(Settings.get_value("ui_scale_auto"))
	_old_reduce = bool(Settings.get_value("reduce_motion"))
	Settings._values["ui_scale_auto"] = false
	Settings.set_value("reduce_motion", true)
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_vault_odds_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings._values["ui_scale_auto"] = _old_auto
	Settings.set_value("reduce_motion", _old_reduce)
	_set_window(_old_size)
	get_tree().root.content_scale_factor = _old_scale
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _set_window(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	get_tree().root.size = sz


func _main_with_crates(with_keys: bool, max_kinds: int = 0) -> Control:
	Game.new_game(1, "normal", 4242)
	var un := Game.system("unlock") as UnlockSystem
	for t in ["feature:crates", "feature:wardrobe", "feature:tradeup", "feature:refinery", "feature:collectors_challenge"]:
		un.grant(t)
	Settings.set_value("tutorials", false)
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	var kinds := 0
	for it in DataRegistry.items_by_category("crate"):
		if max_kinds > 0 and kinds >= max_kinds:
			break
		bank.add(str(it.id), 2)
		kinds += 1
	if with_keys:
		for it in DataRegistry.items_by_category("key"):
			bank.add(str(it.id), 20)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	return main


func _scroll_of(n: Control) -> ScrollContainer:
	var p := n.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	return p as ScrollContainer


## Vero se il rettangolo globale di `n` sta dentro l'area visibile dello scorrimento che lo contiene E dentro la finestra.
func _inside_visible_area(n: Control, view: Rect2) -> bool:
	if not n.is_visible_in_tree():
		return false
	var sc := _scroll_of(n)
	var r := n.get_global_rect()
	if sc != null:
		if sc.scroll_vertical != 0:
			return false
		if not sc.get_global_rect().grow(1.0).encloses(r):
			return false
	return view.grow(1.0).encloses(r)


func _check_odds_visible(main: Control, label: String) -> void:
	var host := main.get("_host") as Control
	var scr := host.get_child(host.get_child_count() - 1) as Control
	var view := get_tree().root.get_visible_rect()
	var crates := Game.system("crates") as CrateSystem
	var cid: String = str(scr.get("_selected"))
	var box := scr.find_child("OddsBox", true, false) as Control
	assert_not_null(box, "%s: blocco probabilità presente" % label)
	if box == null:
		return
	assert_true(_inside_visible_area(box.find_child("OddsBar", true, false) as Control, view), "%s: barra delle probabilità visibile senza clic" % label)
	var legend := box.find_child("OddsLegend", true, false) as Control
	assert_true(_inside_visible_area(legend, view), "%s: legenda delle probabilità visibile senza clic" % label)
	var text := ""
	for l in legend.get_children():
		text += (l as Label).text + "\n"
		assert_true(_inside_visible_area(l as Control, view), "%s: ogni voce della legenda visibile" % label)
	for r in crates.odds(cid):
		assert_string_contains(text, CrateUi.pct(float(r.pct)), "%s: %s mostra %s" % [label, cid, str(r.rarity)])
	# non sta dentro nessun Disclosure chiuso: nessun antenato nascosto o ContentsBox
	var p: Node = box
	while p != null and p != scr:
		assert_ne(str(p.name), "ContentsBox", "le probabilità non stanno nel contenuto a scomparsa")
		p = p.get_parent()


func test_probabilita_visibili_senza_clic_per_ogni_cassa_a_due_risoluzioni() -> void:
	for with_keys in [false, true]:                       # senza chiave (Apri spento) e con chiavi (pronta)
		var main: Control = await _main_with_crates(with_keys)
		get_tree().root.content_scale_factor = 1.0
		var crates := Game.system("crates") as CrateSystem
		var checked := 0
		for sz in SIZES:
			_set_window(sz)
			await wait_process_frames(3)
			var seen_here := 0
			for it in DataRegistry.items_by_category("crate"):
				if crates.crate_def(str(it.id)).is_empty():
					continue
				seen_here += 1
				if not with_keys and seen_here > 5:
					continue                   # senza chiavi (Apri spento, riquadro del motivo) bastano 5 casse: il resto è identico
				assert_true(main.call("show_screen", "vault_hall", {"crate": str(it.id)}))
				await wait_process_frames(3)
				_check_odds_visible(main, "%dx%d %s %s" % [sz.x, sz.y, "chiavi" if with_keys else "senza chiavi", str(it.id)])
				checked += 1
		assert_gt(checked, 8, "controllate le casse possedute, due risoluzioni")
		Game.stop_game(false)
		await wait_process_frames(2)


func test_contenuto_completo_a_un_clic_e_le_probabilita_restano_visibili() -> void:
	var main: Control = await _main_with_crates(true)
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	var cid := str((DataRegistry.items_by_category("crate")[0] as Dictionary).id)
	assert_true(main.call("show_screen", "vault_hall", {"crate": cid}))
	await wait_process_frames(3)
	var host := main.get("_host") as Control
	var scr := host.get_child(host.get_child_count() - 1) as Control
	var toggle := scr.find_child("ContentsToggle", true, false) as Button
	var content := scr.find_child("ContentsBox", true, false) as Control
	assert_not_null(toggle)
	assert_not_null(content)
	if not content.visible:
		toggle.pressed.emit()                                  # UN clic
	assert_true(content.visible, "il contenuto completo si apre con un clic")
	assert_gt(content.find_children("*", "PanelContainer", true, false).size(), 0, "celle con probabilità per finitura")
	toggle.pressed.emit()                                      # richiuso: le probabilità per rarità NON spariscono
	assert_false(content.visible)
	_check_odds_visible(main, "contenuto chiuso")
	# avviso legale: una riga, sempre visibile, con il testo completo nel tooltip
	var legal := scr.find_child("LegalLine", true, false) as Label
	assert_not_null(legal)
	assert_true(legal.is_visible_in_tree())
	assert_eq(legal.tooltip_text, TranslationServer.translate("UI_CRATES_LEGAL"))


func test_ogni_stato_dopo_apertura_mantiene_le_probabilita() -> void:
	var main: Control = await _main_with_crates(true)
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	var cid := str((DataRegistry.items_by_category("crate")[0] as Dictionary).id)
	assert_true(main.call("show_screen", "vault_hall", {"crate": cid}))
	await wait_process_frames(3)
	var host := main.get("_host") as Control
	var scr := host.get_child(host.get_child_count() - 1)
	scr.call("_do_open", 1)
	await wait_process_frames(3)
	scr.call("_on_close_panel")
	await wait_process_frames(3)
	_check_odds_visible(main, "dopo apertura")


func _item_ids(results: Array) -> Array:
	var out: Array = []
	for r in results:
		out.append("%s|%s|%s" % [str(r.def_id), str(r.rarity), str(r.get("instance", {}).get("float", ""))])
	return out


## Stesso seme, stessa sequenza di aperture: la schermata riordinata dà gli stessi oggetti dell'estrazione diretta.
func test_stessa_sequenza_di_aperture_stessi_oggetti_con_stesso_seme() -> void:
	var cid := str((DataRegistry.items_by_category("crate")[0] as Dictionary).id)
	var seq := [1, 5, 1, 10]
	var via_ui: Array = []
	Game.new_game(1, "normal", 777)
	(Game.system("unlock") as UnlockSystem).grant("feature:crates")
	var bank := Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	bank.add(cid, 40)
	var key = (Game.system("crates") as CrateSystem).crate_def(cid).get("key")
	if key != null:
		bank.add(str(key), 40)
	var scr: GameScreen = (load("res://src/ui/screens/VaultHallScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	scr.open({"crate": cid})
	await wait_process_frames(2)
	for n in seq:
		scr.call("_do_open", n)
		via_ui.append_array(_item_ids(scr.get("_results") as Array))
		scr.call("_on_close_panel")
	Game.stop_game(false)
	await wait_process_frames(2)
	Game.new_game(1, "normal", 777)
	(Game.system("unlock") as UnlockSystem).grant("feature:crates")
	bank = Game.system("bank") as BankSystem
	bank.state.slots_bought = 5000
	bank.add(cid, 40)
	if key != null:
		bank.add(str(key), 40)
	var direct: Array = []
	for n in seq:
		direct.append_array(_item_ids((Game.system("crates") as CrateSystem).open(cid, n)))
	assert_gt(direct.size(), 10, "aperture riuscite")
	assert_eq(via_ui, direct, "stessi oggetti, nello stesso ordine, con lo stesso seme")


## Accettazione F11: Sala ≤ 2 pagine di scorrimento (misura come l'audit: altezza scorribile / altezza visibile), a 1280×720,
## con il contenuto completo richiuso (l'apertura alla prima visita è temporanea).
func test_sala_con_casse_al_massimo_due_pagine() -> void:
	var main: Control = await _main_with_crates(true, 14)         # 14 tipi di cassa: più di quanti ne possiede un giocatore reale a 60 h
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	var bank := Game.system("bank") as BankSystem
	for it in DataRegistry.items_by_category("crate"):
		var cid := str(it.id)
		if bank.count(cid) <= 0:
			continue
		assert_true(main.call("show_screen", "vault_hall", {"crate": cid}))
		await wait_process_frames(3)
		var host := main.get("_host") as Control
		var scr := host.get_child(host.get_child_count() - 1)
		var content := scr.find_child("ContentsBox", true, false) as Control
		if content != null and content.visible:
			(scr.find_child("ContentsToggle", true, false) as Button).pressed.emit()
			await wait_process_frames(3)
		var pages := 1.0
		for sc in scr.find_children("*", "ScrollContainer", true, false):
			var c := sc as ScrollContainer
			if c.is_visible_in_tree() and c.get_v_scroll_bar().page > 0.0:
				pages = maxf(pages, c.get_v_scroll_bar().max_value / c.get_v_scroll_bar().page)
		assert_lte(pages, 2.0, "%s: Sala a %.2f pagine" % [cid, pages])
