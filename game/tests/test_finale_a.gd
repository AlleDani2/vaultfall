extends GutTest
## Revisione SHARK finale 1.0, rapporti 31 e 32 (docs/review_1_0/34): avvisi in alto e in coda, Sala dei Caveau compatta,
## un solo overlay alla volta, «Livello totale» a inizio partita, «Ripristina» dei comandi senza doppioni (fuzz da 3.000
## operazioni), impostazioni con tipi sbagliati riparate, import con slot inesistente.

const MAIN := "res://src/ui/main/MainScreen.tscn"
const MS := preload("res://src/ui/main/MainScreen.gd")
const HALL := "res://src/ui/screens/VaultHallScreen.tscn"

var _old_dir: String
var _old_path: String
var _saved: Dictionary = {}


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_finale_a_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_saved = Settings._values.duplicate(true)
	_old_path = Settings.path
	Settings.path = "user://test_finale_a_%d.cfg" % Time.get_ticks_usec()
	Settings.set_value("tutorials", false)
	Settings.set_value("reduce_motion", true)


func after_each() -> void:
	if Feedback.is_pause_menu_open():
		Feedback.close_pause_menu()
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _saved
	Settings.apply_all()
	InputBindings.install()


func _main(sz: Vector2 = Vector2(1280, 720)) -> Control:
	assert_true(Game.new_game(1, "normal", 7))
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = sz
	await wait_process_frames(3)
	return main


## Svuota gli avvisi che la schermata ha già in corso (per esempio quello della migrazione del layout).
func _clear_toasts(main: Control) -> Control:
	var toasts := main.find_child("Toasts", true, false) as Control
	for c in toasts.get_children():
		c.free()
	(main.get("_toast_queue") as Array).clear()
	return toasts


# ------------------------------------------------------------------ 1. avvisi

func _visible_texts(toasts: Control) -> Array:
	var out: Array = []
	for p in toasts.get_children():
		out.append(str(((p as Node).get_child(0) as Label).text))
	return out


func test_avvisi_in_alto_sotto_la_barra_e_senza_catturare_il_mouse() -> void:
	var main := await _main()
	var toasts := main.find_child("Toasts", true, false) as Control
	var top := main.find_child("TopBar", true, false) as Control
	main.toast("uno")
	await wait_process_frames(2)
	assert_eq(toasts.mouse_filter, Control.MOUSE_FILTER_IGNORE, "i clic passano sotto gli avvisi")
	for p in toasts.get_children():
		assert_eq((p as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gte(toasts.get_global_rect().position.y, top.get_global_rect().end.y - 0.5, "sotto la barra alta")
	assert_lt(toasts.get_global_rect().end.y, main.size.y * 0.5, "nella metà alta: mai sui pulsanti d'uso in basso")


func test_massimo_tre_avvisi_visibili_gli_altri_in_coda() -> void:
	var main := await _main()
	var toasts := _clear_toasts(main)
	for i in 7:
		main.toast("avviso %d" % i)
	assert_eq(toasts.get_child_count(), MS.TOAST_MAX, "al massimo TOAST_MAX insieme")
	assert_eq(MS.TOAST_MAX, 3)
	assert_eq((main.get("_toast_queue") as Array).size(), 4, "gli altri aspettano")
	# quando c'è posto entrano in ordine
	toasts.get_child(0).free()
	main.call("_pump_toasts")
	assert_eq(toasts.get_child_count(), MS.TOAST_MAX)
	assert_eq(_visible_texts(toasts)[2], "avviso 3", "il primo in coda entra per primo")


func test_stesso_avviso_di_seguito_diventa_un_contatore() -> void:
	var main := await _main()
	var toasts := _clear_toasts(main)
	for i in 5:
		main.toast("Equipaggiato")
	assert_eq(toasts.get_child_count(), 1, "un solo avviso, non cinque")
	assert_true(_visible_texts(toasts)[0].contains("×5"), "con il contatore")
	main.toast("Altro")
	assert_eq(toasts.get_child_count(), 2)


func test_coda_limitata_e_durata_piu_breve_nel_tutorial() -> void:
	var main := await _main()
	_clear_toasts(main)
	for i in 60:
		main.toast("n %d" % i)
	assert_lte((main.get("_toast_queue") as Array).size(), MS.TOAST_QUEUE_MAX, "la coda non cresce senza fine")
	assert_lt(MS.TOAST_SECONDS_TUTORIAL, MS.TOAST_SECONDS)


# ------------------------------------------------------------------ 2. Sala dei Caveau compatta

func _hall_in(sz: Vector2i) -> Array:
	assert_true(Game.new_game(1, "normal", 5))
	(Game.system("unlock") as UnlockSystem).grant("feature:crates")
	var bank: Object = Game.system("bank")
	bank.call("add", "crate_millbrook", 4, "qa")
	bank.call("add", "key_t1", 4, "qa")
	var sv := SubViewport.new()
	sv.size = sz
	add_child_autofree(sv)
	var scr := (load(HALL) as PackedScene).instantiate() as GameScreen
	sv.add_child(scr)
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.open({"crate": "crate_millbrook"})
	await wait_process_frames(6)
	return [scr, sv]


func test_sala_1024x576_apri_raggiungibile_senza_scorrere() -> void:
	for sz in [Vector2i(1024, 576), Vector2i(1280, 720)]:
		var r := await _hall_in(sz)
		var scr: Control = r[0]
		var btn := scr.find_child("OpenButton", true, false) as Button
		assert_not_null(btn, "pulsante Apri")
		var sc: Control = btn.get_parent()
		while sc != null and not (sc is ScrollContainer):
			sc = sc.get_parent()
		assert_not_null(sc)
		assert_lte(btn.get_global_rect().end.y, sc.get_global_rect().end.y + 0.5, "Apri dentro l'area visibile a %s" % str(sz))
		assert_gte(btn.get_global_rect().position.y, sc.get_global_rect().position.y - 0.5)
		assert_not_null(scr.find_child("OddsBar", true, false), "probabilità sempre presenti")
		assert_true(scr.find_child("OddsBox", true, false).is_visible_in_tree(), "e visibili a %s" % str(sz))
		(r[1] as Node).queue_free()
		await wait_process_frames(2)


func test_sala_compatta_solo_sotto_la_soglia() -> void:
	var r := await _hall_in(Vector2i(1024, 576))
	assert_true((r[0] as Object).call("is_compact"))
	(r[1] as Node).queue_free()
	await wait_process_frames(2)
	var r2 := await _hall_in(Vector2i(1600, 900))
	assert_false((r2[0] as Object).call("is_compact"))


# ------------------------------------------------------------------ 3. un solo overlay alla volta

func test_benvenuto_aspetta_se_il_menu_di_pausa_e_aperto() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	assert_true(Feedback.toggle_pause_menu(true), "pausa aperta prima del benvenuto")
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(4)
	var ov := main.get("_overlay") as OverlayHost
	assert_true(Feedback.is_pause_menu_open())
	assert_null(ov.find_child("WelcomeGo", true, false), "il benvenuto non compare sotto la pausa")
	Feedback.close_pause_menu()
	await wait_process_frames(4)
	assert_not_null(ov.find_child("WelcomeGo", true, false), "compare quando la pausa si chiude")


func test_pausa_nasconde_il_benvenuto_gia_aperto() -> void:
	var main := await _main()
	var ov := main.get("_overlay") as OverlayHost
	await wait_process_frames(3)
	var go := ov.find_child("WelcomeGo", true, false)
	assert_not_null(go, "benvenuto aperto")
	Feedback.toggle_pause_menu(true)
	await wait_process_frames(3)
	assert_false(go.is_visible_in_tree(), "con la pausa il benvenuto non si vede")
	Feedback.close_pause_menu()
	await wait_process_frames(3)
	assert_true(go.is_visible_in_tree(), "e torna dopo")


# ------------------------------------------------------------------ 4. Livello totale e titolo del benvenuto

func test_livello_totale_a_inizio_partita_mostra_il_minimo() -> void:
	var b := TotalLevelText.base()
	assert_gt(b, 0)
	assert_true(TotalLevelText.text(b).contains(NumberFormat.fmt(b) + " "), "17 (minimo 17)")
	assert_ne(TotalLevelText.text(b), NumberFormat.fmt(b))
	assert_eq(TotalLevelText.text(b * 2), NumberFormat.fmt(b * 2), "più avanti solo il numero")
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		assert_false(TotalLevelText.text(b).contains("UI_"), "nessuna chiave nuda in " + loc)


func test_titolo_del_benvenuto_senza_battuta_tra_parentesi() -> void:
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		var t := tr("UI_QUESTS_WELCOME_TITLE")
		assert_ne(t, "UI_QUESTS_WELCOME_TITLE")
		assert_false(t.contains("(") or t.contains(")"), "titolo pulito: " + t)
		assert_lt(t.length(), 40, "corto")


# ------------------------------------------------------------------ 5. Ripristina dei comandi

func _key(code: int, shift: bool = false) -> InputEventKey:
	var k := InputBindings.key_event(code, false, false, shift)
	k.pressed = true
	return k


func _invariant(ctx: String) -> bool:
	for kind in [InputBindings.KIND_KEY, InputBindings.KIND_PAD]:
		var seen := {}
		for id in InputBindings.ids_of_kind(kind):
			var evs := InputBindings.events_of(id)
			if evs.is_empty():
				fail_test("comando senza tasti: %s (%s)" % [id, ctx])
				return false
			for ev in evs:
				var k := JSON.stringify(InputBindings.serialize(ev))
				if seen.has(k) and seen[k] != id:
					fail_test("doppione %s tra %s e %s (%s)" % [k, seen[k], id, ctx])
					return false
				seen[k] = id
	return true


func test_reset_one_riprova_il_caso_del_rapporto() -> void:
	InputBindings.reset_all()
	var res := InputBindings.assign("hero", _key(KEY_B), false)
	var bank_before := InputBindings.label_for("bank")
	assert_true(bool(res.ok) or res.reason == "conflict")
	var cl := InputBindings.conflicts("hero", _key(KEY_C))
	if not cl.is_empty():
		InputBindings.assign("hero", _key(KEY_C), true)       # scambio: Eroe prende C, l'altro prende B
	var out := InputBindings.reset_one("hero")
	assert_true(_invariant("dopo reset_one"))
	assert_true(out.has("swapped"))
	assert_true(InputBindings.is_default("hero"), "Eroe torna ai predefiniti")
	assert_ne(bank_before, "x")


func test_fuzz_comandi_3000_operazioni_senza_doppioni_ne_comandi_vuoti() -> void:
	InputBindings.reset_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool := [KEY_B, KEY_C, KEY_E, KEY_H, KEY_I, KEY_K, KEY_M, KEY_Q, KEY_T, KEY_U, KEY_X, KEY_Y, KEY_F2, KEY_F3, KEY_1, KEY_2]
	var key_ids := InputBindings.ids_of_kind(InputBindings.KIND_KEY).filter(func(i: String) -> bool: return not bool(InputBindings.entry(i).get("fixed", false)))
	var pad_ids := InputBindings.ids_of_kind(InputBindings.KIND_PAD)
	var swaps := 0
	for step in 3000:
		var roll := rng.randi() % 100
		if roll < 55:
			var id: String = key_ids[rng.randi() % key_ids.size()]
			var ev := _key(pool[rng.randi() % pool.size()], rng.randi() % 5 == 0)
			var r := InputBindings.assign(id, ev, false)
			if not bool(r.ok) and str(r.reason) == "conflict":
				InputBindings.assign(id, ev, rng.randi() % 3 != 0)
		elif roll < 90:
			var id2: String = key_ids[rng.randi() % key_ids.size()]
			swaps += int(InputBindings.reset_one(id2).swapped.size())
		elif roll < 96:
			var pid: String = pad_ids[rng.randi() % pad_ids.size()]
			var pr := InputBindings.assign(pid, InputBindings.pad_event(rng.randi() % 10), false)
			if not bool(pr.ok) and str(pr.reason) == "conflict":
				InputBindings.assign(pid, InputBindings.pad_event(rng.randi() % 10), true)
		elif roll < 98:
			InputBindings.reset_one(pad_ids[rng.randi() % pad_ids.size()])
		else:
			InputBindings.reset_all()
		if not _invariant("passo %d" % step):
			return
	assert_gt(swaps, 0, "il fuzz ha davvero provato scambi automatici")
	# persistenza: ricaricando dal disco lo stato è lo stesso e resta senza doppioni
	var before: Dictionary = (Settings.get_value("keybinds") as Dictionary).duplicate(true)
	Settings.save_settings()
	Settings.load_settings()
	assert_eq(Settings.get_value("keybinds"), before)
	assert_true(_invariant("dopo ricarica"))


# ------------------------------------------------------------------ 6. file con tipi sbagliati

func test_deserialize_ostile_senza_errori() -> void:
	var bad: Array = [
		{"t": "key", "c": [1, 2]}, {"t": "key", "c": "65"}, 		{"t": "key", "c": NAN}, {"t": "key", "c": INF}, {"t": ["key"], "c": 65}, {"t": "pad", "b": {}},
		{"t": "pad", "b": -3}, {"t": "pad", "b": 9999}, {}, [], "x", 5, null, {"t": "key", "c": {"a": 1}}]
	for d in bad:
		assert_null(InputBindings.deserialize(d), "scartato: " + str(d))
	var ok := InputBindings.deserialize({"t": "key", "c": 65, "ctrl": "yes"})
	assert_not_null(ok, "il tasto resta valido")
	assert_false((ok as InputEventKey).ctrl_pressed, "una stringa non vale come vero")
	assert_eq(InputBindings.deserialize({"t": "key", "c": 65.0}).keycode, KEY_A as Key, "un float intero va bene")


func test_settings_con_comandi_ostili_si_ripara_e_il_file_si_riscrive_pulito() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.SECTION, "keybinds", {"bank": [{"t": "key", "c": [1, 2]}], "menu_1": [{"t": "key", "c": 65, "ctrl": "yes"}],
		"zzz": [1], "hero": "no", "quests": [5, {"t": "pad", "b": 3}]})
	cfg.save(Settings.path)
	Settings.load_settings()
	var kb: Dictionary = Settings.get_value("keybinds")
	assert_false(kb.has("bank"), "voce illeggibile scartata")
	assert_false(kb.has("zzz"), "azione sconosciuta scartata")
	assert_false(kb.has("hero"))
	assert_false(kb.has("quests"), "un pulsante non vale per un comando da tastiera")
	assert_true(kb.has("menu_1"), "la voce con il tasto valido resta")
	assert_false(bool(kb.menu_1[0].ctrl), "ma il flag sbagliato non vale")
	assert_true(_invariant("dopo il caricamento ostile"))
	var again := ConfigFile.new()
	assert_eq(again.load(Settings.path), OK)
	var on_disk: Variant = again.get_value(Settings.SECTION, "keybinds")
	assert_eq(on_disk, kb, "file riparato sul disco")


# ------------------------------------------------------------------ 7. import su slot inesistente

func test_import_slot_inesistente_ha_un_codice() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var s := SaveCodec.to_base64(GameState.data)
	assert_eq(SaveService.import_string(s, 99, true).error, "bad_slot")
	assert_true(SaveService.import_string(s, 0).ok, "slot 0 = solo controllo")
	assert_false(SaveService.import_error_text("bad_slot").begins_with("UI_"), "messaggio tradotto")


# ------------------------------------------------------------------ 8. rullo: nomi delle tessere

func test_rullo_nomi_sempre_interi_in_due_righe_con_corpo_leggibile() -> void:
	assert_true(Game.new_game(1, "normal", 3))
	var worst := 0
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		var reel := CrateReel.new()
		add_child_autofree(reel)
		var ids: Array = DataRegistry.all_items().keys()
		var names: Array = []
		for id in ids:
			names.append(CrateUi.def_name(str(id)))
		reel._names = names
		var cut := 0
		for i in names.size():
			var f := reel.name_fit(i)
			assert_gte(int(f.font_size), CrateReel.NAME_MIN_FONT, "corpo leggibile: " + str(names[i]))
			assert_lte(int(f.lines), CrateReel.NAME_LINES_MAX)
			if str(f.text) != str(names[i]):
				cut += 1
		worst = maxi(worst, cut)
		assert_eq(cut, 0, "nessun nome accorciato in " + loc)
