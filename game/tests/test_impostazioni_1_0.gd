extends GutTest
## Impostazioni 1.0: schede, schermo (modalità, risoluzione, VSync, FPS, monitor, F11), migrazione e validazione delle chiavi nuove.

const SETTINGS := "res://src/ui/screens/SettingsScreen.tscn"

var _saved: Dictionary = {}
var _old_path: String
var _old_dir: String


func before_each() -> void:
	_saved = Settings._values.duplicate(true)
	_old_path = Settings.path
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_impostazioni_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings.path = _old_path
	Settings._values = _saved
	Settings.apply_all()
	if GameState.active:
		Game.stop_game(false)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(in_menu: bool = false) -> Control:
	var s: Control = (load(SETTINGS) as PackedScene).instantiate()
	s.in_menu = in_menu
	add_child_autofree(s)
	s.open({"in_menu": in_menu})
	await wait_process_frames(2)
	return s


# ------------------------------------------------------------------ schede

func test_sei_schede_in_ordine() -> void:
	var s := await _open()
	var tabs: TabContainer = s.tabs
	assert_eq(tabs.get_tab_count(), 6)
	var expect := ["Gioco", "Schermo", "Audio", "Accessibilità", "Comandi", "Salvataggi e dati"]
	var old_loc := str(Settings.get_value("locale"))
	Settings.set_value("locale", "it")
	s = await _open()
	tabs = s.tabs
	for i in 6:
		assert_eq(tabs.get_tab_title(i), expect[i], "scheda %d" % i)
	Settings.set_value("locale", old_loc)


func test_ogni_scheda_ha_la_sua_pagina_scorrevole_e_non_ce_una_pagina_alta() -> void:
	var s := await _open()
	for i in s.tabs.get_tab_count():
		var page: Control = s.tabs.get_tab_control(i)
		assert_true(page is ScrollContainer, "pagina %d scorrevole" % i)
		assert_true((page as ScrollContainer).follow_focus, "il fuoco fa scorrere la pagina %d" % i)
	assert_not_null(s.display_panel)
	assert_not_null(s.controls_panel)
	assert_not_null(s.accessibility_panel)


func test_le_sezioni_vecchie_ci_sono_ancora() -> void:
	var s := await _open()
	var texts := PackedStringArray()
	for l in s.find_children("*", "Label", true, false):
		texts.append(str((l as Label).text))
	for k in ["UI_PUSH_SAND", "UI_UIA_SET_NOTIFY", "UI_SETTINGS_AUDIO", "UI_FB_SECTION", "UI_UIB_SET_COZY_TITLE"]:
		assert_true(texts.has(k), "sezione " + k)
	assert_not_null(s.find_child("SettingsExtras", true, false))


func test_lb_rb_cambiano_scheda_e_si_ricorda_l_ultima() -> void:
	var s := await _open()
	s.tabs.current_tab = 0
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	ev.pressed = true
	s._unhandled_input(ev)
	assert_eq(s.tabs.current_tab, 1)
	ev.button_index = JOY_BUTTON_LEFT_SHOULDER
	s._unhandled_input(ev)
	s._unhandled_input(ev)
	assert_eq(s.tabs.current_tab, 5, "dalla prima si torna all'ultima")
	s.switch_tab(1)
	assert_eq(s.tabs.current_tab, 0)
	s.tabs.current_tab = 3
	var s2 := await _open()
	assert_eq(s2.tabs.current_tab, 3, "la scheda aperta resta (anche dopo il cambio lingua)")
	s2.tabs.current_tab = 0
	s.last_tab = 0


func test_menu_iniziale_ha_il_pulsante_indietro() -> void:
	var s := await _open(true)
	assert_not_null(s.find_child("BackButton", true, false))
	var s2 := await _open(false)
	assert_null(s2.find_child("BackButton", true, false))


func test_in_partita_la_scheda_dati_ha_esporta_importa_e_uscita() -> void:
	assert_true(Game.new_game(1, "normal", 5))
	var s := await _open()
	var data: Control = s.tabs.get_tab_control(5)
	var texts := PackedStringArray()
	for b in data.find_children("*", "Button", true, false):
		texts.append(str((b as Button).text))
	for k in ["UI_EXPORT_SAVE", "UI_IMPORT_SAVE", "UI_MAIN_MENU", "UI_QUIT"]:
		assert_true(texts.has(k), k)


# ------------------------------------------------------------------ chiavi nuove, validazione, migrazione

func test_chiavi_nuove_hanno_predefiniti_e_validazione() -> void:
	assert_eq(Settings.DEFAULTS.window_mode, "windowed")
	assert_true(Settings.set_value("window_mode", "borderless"))
	assert_false(Settings.set_value("window_mode", "iconic"))
	assert_false(Settings.set_value("window_mode", 3))
	assert_true(Settings.set_value("vsync", "adaptive"))
	assert_false(Settings.set_value("vsync", "triple"))
	assert_true(Settings.set_value("window_size", Vector2i(1920, 1080)))
	assert_false(Settings.set_value("window_size", Vector2i(100, 100)), "sotto il minimo")
	assert_false(Settings.set_value("window_size", Vector2i(99999, 9999)))
	assert_false(Settings.set_value("window_size", "1920x1080"))
	assert_true(Settings.set_value("monitor", 2))
	assert_false(Settings.set_value("monitor", "2"))
	assert_true(Settings.set_value("colorblind", "tritanopia"))
	assert_false(Settings.set_value("colorblind", "rosso"))
	assert_true(Settings.set_value("text_scale", 1.25))
	assert_false(Settings.set_value("text_scale", 1.3))
	assert_true(Settings.set_value("pad_glyphs", "playstation"))
	assert_false(Settings.set_value("pad_glyphs", "nintendo"))
	assert_true(Settings.set_value("pad_hints", "always"))
	assert_false(Settings.set_value("pad_hints", "sempre"))
	assert_false(Settings.set_value("keybinds", "no"))
	assert_false(Settings.set_value("keybinds", {"x": "non un array"}))
	assert_true(Settings.set_value("keybinds", {}))


func test_fps_ammessi_e_senza_limite() -> void:
	for v in [30, 60, 120, 144, 0]:
		assert_true(Settings.set_value("fps_cap", v), str(v))
	assert_false(Settings.set_value("fps_cap", 45))
	Settings.set_value("fps_cap", 0)
	assert_eq(Clock.focus_fps, 0, "0 = senza limite")
	assert_eq(Engine.max_fps, 0)
	Settings.set_value("fps_cap", 120)
	assert_eq(Clock.focus_fps, 120)
	Settings.set_value("fps_cap", 60)


func test_migrazione_da_un_file_della_valfa() -> void:
	var p := "user://test_settings_vecchio_%d.cfg" % Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "locale", "en")
	cfg.set_value("settings", "volume_music", 0.3)
	cfg.set_value("settings", "fps_cap", 30)
	cfg.set_value("settings", "reduce_motion", true)
	cfg.set_value("settings", "ui_scale_rev", 2)
	cfg.set_value("settings", "ui_scale", 1.1)
	cfg.save(p)
	Settings.path = p
	Settings.load_settings()
	assert_eq(Settings.get_value("settings_rev"), Settings.SETTINGS_REV, "revisione portata alla corrente")
	assert_eq(Settings.get_value("locale"), "en", "valori vecchi intatti")
	assert_almost_eq(float(Settings.get_value("volume_music")), 0.3, 0.001)
	assert_eq(Settings.get_value("fps_cap"), 30)
	assert_true(bool(Settings.get_value("reduce_motion")))
	assert_almost_eq(float(Settings.get_value("ui_scale")), 1.1, 0.001)
	assert_eq(Settings.get_value("window_mode"), "windowed", "chiavi nuove: predefiniti")
	assert_eq(Settings.get_value("window_size"), Vector2i(1600, 900))
	assert_eq(Settings.get_value("colorblind"), "off")
	assert_eq(Settings.get_value("keybinds"), {})
	var again := ConfigFile.new()
	assert_eq(again.load(p), OK)
	assert_eq(int(again.get_value("settings", "settings_rev")), Settings.SETTINGS_REV, "il file è stato aggiornato")
	assert_eq(again.get_value("settings", "volume_music"), 0.3)
	DirAccess.remove_absolute(p)


func test_file_di_una_revisione_futura_non_si_abbassa() -> void:
	var p := "user://test_settings_futuro_%d.cfg" % Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "settings_rev", 9)
	cfg.set_value("settings", "window_mode", "fullscreen")
	cfg.save(p)
	Settings.path = p
	Settings.load_settings()
	assert_eq(Settings.get_value("settings_rev"), 9)
	assert_eq(Settings.get_value("window_mode"), "fullscreen")
	DirAccess.remove_absolute(p)


func test_valori_validi_si_salvano_e_si_rileggono() -> void:
	var p := "user://test_settings_giro_%d.cfg" % Time.get_ticks_usec()
	Settings.path = p
	Settings.set_value("window_mode", "borderless")
	Settings.set_value("window_size", Vector2i(1366, 768))
	Settings.set_value("vsync", "off")
	Settings.set_value("monitor", 1)
	Settings.set_value("text_scale", 1.5)
	Settings.set_value("high_contrast", true)
	Settings._values = Settings.DEFAULTS.duplicate(true)
	Settings.load_settings()
	assert_eq(Settings.get_value("window_mode"), "borderless")
	assert_eq(Settings.get_value("window_size"), Vector2i(1366, 768))
	assert_eq(Settings.get_value("vsync"), "off")
	assert_eq(Settings.get_value("monitor"), 1)
	assert_almost_eq(float(Settings.get_value("text_scale")), 1.5, 0.001)
	assert_true(bool(Settings.get_value("high_contrast")))
	DirAccess.remove_absolute(p)


func test_valore_rovinato_nel_file_torna_al_predefinito() -> void:
	var p := "user://test_settings_rotto_%d.cfg" % Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "window_mode", "chissà")
	cfg.set_value("settings", "window_size", Vector2i(5, 5))
	cfg.set_value("settings", "colorblind", 7)
	cfg.set_value("settings", "keybinds", [1, 2])
	cfg.save(p)
	Settings.path = p
	Settings.load_settings()
	assert_eq(Settings.get_value("window_mode"), "windowed")
	assert_eq(Settings.get_value("window_size"), Vector2i(1600, 900))
	assert_eq(Settings.get_value("colorblind"), "off")
	assert_eq(Settings.get_value("keybinds"), {})
	DirAccess.remove_absolute(p)


func test_ripristina_predefiniti_include_le_chiavi_nuove() -> void:
	Settings.set_value("vsync", "off")
	Settings.set_value("colorblind", "protanopia")
	Settings.set_value("keybinds", {"bank": [{"t": "key", "c": KEY_J, "ctrl": false, "alt": false, "shift": false}]})
	Settings.reset_to_defaults()
	assert_eq(Settings.get_value("vsync"), "on")
	assert_eq(Settings.get_value("colorblind"), "off")
	assert_true(InputBindings.is_default("bank"))


# ------------------------------------------------------------------ schermo: calcoli puri

func test_risoluzioni_offerte_entrano_nel_monitor() -> void:
	var out := DisplayOptions.resolution_choices(Vector2i(1920, 1080), Vector2i(1600, 900))
	assert_true(out.has(Vector2i(1920, 1080)) == false, "1920×1080 non entra in un monitor 1920×1080 con la barra del titolo")
	assert_true(out.has(Vector2i(1600, 900)))
	assert_true(out.has(Vector2i(1280, 720)))
	assert_false(out.has(Vector2i(2560, 1440)))
	var big := DisplayOptions.resolution_choices(Vector2i(3840, 2160), Vector2i(1600, 900))
	assert_true(big.has(Vector2i(3840, 2160)) == false and big.has(Vector2i(2560, 1440)))
	var custom := DisplayOptions.resolution_choices(Vector2i(2560, 1440), Vector2i(1500, 850))
	assert_true(custom.has(Vector2i(1500, 850)), "la dimensione scelta a mano compare")
	for i in range(1, custom.size()):
		assert_true(custom[i].x >= custom[i - 1].x, "ordinate")
	var tiny := DisplayOptions.resolution_choices(Vector2i(800, 600), Vector2i(1600, 900))
	assert_false(tiny.is_empty(), "mai un elenco vuoto")


func test_piano_della_finestra_per_ogni_modalita() -> void:
	var screen := Rect2i(Vector2i(0, 0), Vector2i(2560, 1440))
	var usable := Rect2i(Vector2i(0, 0), Vector2i(2560, 1400))
	var f := DisplayOptions.plan("fullscreen", Vector2i(1600, 900), screen, usable)
	assert_eq(f.mode, Window.MODE_FULLSCREEN)
	assert_false(f.borderless)
	var b := DisplayOptions.plan("borderless", Vector2i(1600, 900), screen, usable)
	assert_eq(b.mode, Window.MODE_WINDOWED)
	assert_true(b.borderless)
	assert_eq(b.size, Vector2i(2560, 1440), "senza bordi = tutto il monitor")
	assert_eq(b.position, Vector2i(0, 0))
	var w := DisplayOptions.plan("windowed", Vector2i(1600, 900), screen, usable)
	assert_eq(w.mode, Window.MODE_WINDOWED)
	assert_false(w.borderless)
	assert_eq(w.size, Vector2i(1600, 900))
	assert_true(Rect2i(usable).encloses(Rect2i(w.position, w.size)), "centrata nell'area utile")
	var small := DisplayOptions.plan("windowed", Vector2i(3000, 2000), screen, Rect2i(Vector2i(0, 0), Vector2i(1366, 728)))
	assert_lte(small.size.x, 1366, "una finestra troppo grande si riduce")
	assert_lte(small.size.y, 728)
	var second := DisplayOptions.plan("borderless", Vector2i(1600, 900), Rect2i(Vector2i(1920, 0), Vector2i(1920, 1080)), usable)
	assert_eq(second.position, Vector2i(1920, 0), "sul secondo monitor")


func test_f11_alterna_schermo_intero_e_torna_alla_modalita_di_prima() -> void:
	assert_eq(DisplayOptions.toggled_mode("windowed", "windowed"), "fullscreen")
	assert_eq(DisplayOptions.toggled_mode("borderless", "windowed"), "fullscreen")
	assert_eq(DisplayOptions.toggled_mode("fullscreen", "borderless"), "borderless")
	assert_eq(DisplayOptions.toggled_mode("fullscreen", "fullscreen"), "windowed", "mai di nuovo a schermo intero")


func test_f11_cambia_la_modalita_salvata() -> void:
	Settings.set_value("window_mode", "windowed")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F11
	ev.pressed = true
	assert_true(UiRuntime._is_fullscreen_toggle(ev), "F11")
	var alt := InputEventKey.new()
	alt.keycode = KEY_ENTER
	alt.alt_pressed = true
	alt.pressed = true
	assert_true(UiRuntime._is_fullscreen_toggle(alt), "Alt+Invio")
	var plain := InputEventKey.new()
	plain.keycode = KEY_ENTER
	plain.pressed = true
	assert_false(UiRuntime._is_fullscreen_toggle(plain))
	Settings.runtime.toggle_fullscreen()
	assert_eq(Settings.get_value("window_mode"), "fullscreen")
	Settings.runtime.toggle_fullscreen()
	assert_eq(Settings.get_value("window_mode"), "windowed")


func test_f11_si_puo_rimappare() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F10
	ev.pressed = true
	assert_false(UiRuntime._is_fullscreen_toggle(ev))
	assert_true(bool(InputBindings.assign("fullscreen", InputBindings.key_event(KEY_F10)).ok))
	assert_true(UiRuntime._is_fullscreen_toggle(ev))
	InputBindings.reset_all()


# ------------------------------------------------------------------ pannello schermo

func test_pannello_schermo_scrive_in_settings() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	p.mode_opt.select(2)
	p.mode_opt.item_selected.emit(2)
	assert_eq(Settings.get_value("window_mode"), "fullscreen")
	assert_true(p.res_opt.disabled, "risoluzione grigia fuori dalla modalità finestra")
	p.mode_opt.select(0)
	p.mode_opt.item_selected.emit(0)
	assert_false(p.res_opt.disabled)
	p.vsync_opt.select(0)
	p.vsync_opt.item_selected.emit(0)
	assert_eq(Settings.get_value("vsync"), "off")
	var idx := Array(DisplayOptions.FPS_CAPS).find(0)
	p.fps_opt.select(idx)
	p.fps_opt.item_selected.emit(idx)
	assert_eq(Settings.get_value("fps_cap"), 0)
	p.res_opt.select(0)
	p.res_opt.item_selected.emit(0)
	assert_eq(Settings.get_value("window_size"), p._res_values[0])


func test_pannello_schermo_segue_f11() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	Settings.set_value("window_mode", "fullscreen")
	assert_eq(p.mode_opt.selected, 2)
	assert_true(p.res_opt.disabled)
	Settings.set_value("window_mode", "windowed")
	assert_eq(p.mode_opt.selected, 0)


func test_scala_interfaccia_resta_con_il_tetto_125() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var top := 0.0
	for c in UiScale.SIZE_CHOICES:
		top = maxf(top, float(c[1]))
	assert_almost_eq(top, 1.25, 0.0001)
	assert_eq(p.size_opt.item_count, UiScale.SIZE_CHOICES.size())
	p.size_opt.select(5)
	p.size_opt.item_selected.emit(5)
	assert_almost_eq(float(Settings.get_value("ui_scale")), 1.25, 0.0001)
	assert_false(Settings.set_value("ui_scale", 2.0) and float(Settings.get_value("ui_scale")) > 1.25, "mai oltre il 125%")


func test_conferma_mantieni_annulla_ripristina() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var before := DisplayOptions.snapshot()
	Settings.set_value("window_mode", "borderless")
	Settings.set_value("window_size", Vector2i(1366, 768))
	p.ask_keep(before)
	var d := p.keep_dialog
	assert_not_null(d)
	assert_eq(d.seconds_left, DisplayOptions.KEEP_SECONDS)
	d._tick()
	assert_eq(d.seconds_left, DisplayOptions.KEEP_SECONDS - 1)
	d.revert()
	assert_eq(Settings.get_value("window_mode"), before.window_mode)
	assert_eq(Settings.get_value("window_size"), before.window_size)


func test_conferma_mantieni_scaduto_il_tempo_torna_indietro() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var before := DisplayOptions.snapshot()
	Settings.set_value("vsync", "off")
	Settings.set_value("window_mode", "fullscreen")
	p.ask_keep(before)
	var d := p.keep_dialog
	d.seconds_left = 1
	d._tick()
	assert_eq(Settings.get_value("window_mode"), "windowed", "scaduti i 10 s: indietro")
	assert_eq(Settings.get_value("vsync"), "on")


func test_conferma_mantieni_conferma_lascia_le_impostazioni() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var before := DisplayOptions.snapshot()
	Settings.set_value("window_mode", "borderless")
	p.ask_keep(before)
	var watch := []
	p.keep_dialog.resolved.connect(func(kept: bool) -> void: watch.append(kept))
	p.keep_dialog.keep()
	assert_eq(watch, [true])
	assert_eq(Settings.get_value("window_mode"), "borderless")
	p.keep_dialog.revert()          # dopo la conferma non fa più nulla (già risolto)
	assert_eq(Settings.get_value("window_mode"), "borderless")


func test_un_secondo_cambio_non_perde_le_impostazioni_di_prima() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var before := DisplayOptions.snapshot()
	p.ask_keep(before)
	var first := p.keep_dialog
	first.seconds_left = 4
	Settings.set_value("window_mode", "fullscreen")
	p.ask_keep(DisplayOptions.snapshot())
	assert_eq(p.keep_dialog, first, "un solo avviso")
	assert_eq(first.seconds_left, DisplayOptions.KEEP_SECONDS, "si riparte da 10")
	first.revert()
	assert_eq(Settings.get_value("window_mode"), before.window_mode, "torna alla prima, non alla seconda")


func test_ripristina_predefiniti_dello_schermo() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	Settings.set_value("vsync", "adaptive")
	Settings.set_value("fps_cap", 144)
	Settings.set_value("ui_scale", 1.25)
	p.reset_defaults()
	assert_eq(Settings.get_value("vsync"), "on")
	assert_eq(Settings.get_value("fps_cap"), 60)
	assert_almost_eq(float(Settings.get_value("ui_scale")), 1.0, 0.0001)
	assert_true(bool(Settings.get_value("ui_scale_auto")))


func test_in_headless_la_finestra_non_si_tocca() -> void:
	assert_false(DisplayOptions.managed(), "headless: nessuna modifica alla finestra")
	assert_false(DisplayOptions.apply_window(get_window()))


func test_se_il_gioco_si_chiude_durante_la_conferma_al_riavvio_si_torna_a_prima() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	var before := DisplayOptions.snapshot()
	Settings.set_value("window_mode", "fullscreen")
	Settings.set_value("window_size", Vector2i(1280, 720))
	p.ask_keep(before)
	assert_false((Settings.get_value("display_revert") as Dictionary).is_empty(), "il «prima» è salvato mentre si aspetta")
	# chiusura brusca: si ricarica il file così com'è
	Settings._values = Settings.DEFAULTS.duplicate(true)
	Settings.load_settings()
	assert_eq(Settings.get_value("window_mode"), before.window_mode, "al riavvio torna la modalità di prima")
	assert_eq(Settings.get_value("window_size"), before.window_size)
	assert_true((Settings.get_value("display_revert") as Dictionary).is_empty(), "e il «prima» è consumato")


func test_confermando_o_annullando_il_prima_si_cancella() -> void:
	var s := await _open()
	var p: DisplayPanel = s.display_panel
	p.ask_keep(DisplayOptions.snapshot())
	p.keep_dialog.keep()
	assert_true((Settings.get_value("display_revert") as Dictionary).is_empty())
	Settings.set_value("window_mode", "borderless")
	p.ask_keep(DisplayOptions.snapshot())
	p.keep_dialog.revert()
	assert_true((Settings.get_value("display_revert") as Dictionary).is_empty())
	assert_false(Settings.set_value("display_revert", "no"))
