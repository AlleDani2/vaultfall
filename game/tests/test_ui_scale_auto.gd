extends GutTest
## F5 (docs/ui_redesign/06 §3.17): scala automatica dell'area logica, vincolo 1024×576, conversione dei vecchi valori.

var _old_path: String
var _old_values: Dictionary
var _old_csf: float


func before_each() -> void:
	_old_path = Settings.path
	_old_values = Settings._values.duplicate(true)
	_old_csf = get_tree().root.content_scale_factor
	Settings.path = "user://test_ui_scale_%d.cfg" % Time.get_ticks_usec()


func after_each() -> void:
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _old_values
	Settings.apply_all()
	get_tree().root.content_scale_factor = _old_csf


func _logical(w: int, h: int, user: float, auto_on: bool) -> Vector2:
	var win := Vector2i(w, h)
	return UiScale.logical_size(win, UiScale.content_scale_factor(win, user, auto_on))


func test_tabella_di_progetto_con_dimensione_100() -> void:
	var table := [
		[1280, 720, 1280.0, 720.0], [1280, 800, 1280.0, 800.0], [1366, 768, 1366.0, 768.0],
		[1600, 900, 1600.0, 900.0], [1920, 1080, 1280.0, 720.0], [2560, 1440, 1280.0, 720.0], [3840, 2160, 1280.0, 720.0],
	]
	for r in table:
		var l := _logical(r[0], r[1], 1.0, true)
		assert_almost_eq(l.x, float(r[2]), 0.5, "%dx%d larghezza logica" % [r[0], r[1]])
		assert_almost_eq(l.y, float(r[3]), 0.5, "%dx%d altezza logica" % [r[0], r[1]])


func test_dimensioni_relative() -> void:
	var big := _logical(1280, 720, 1.25, true)
	assert_almost_eq(big.x, 1024.0, 0.5)
	assert_almost_eq(big.y, 576.0, 0.5)
	var small := _logical(1280, 720, 0.8, true)
	assert_almost_eq(small.x, 1600.0, 0.5)
	assert_almost_eq(small.y, 900.0, 0.5)
	var s1080 := _logical(1920, 1080, 0.8, true)
	assert_almost_eq(s1080.x, 1600.0, 0.5, "80% a 1080p: 1,5 × 0,8 = 1,2 fisico → 1600×900 logici")


func test_vincolo_1024x576_mai_violato() -> void:
	for w in [960, 1024, 1280, 1366, 1600, 1920, 2560, 3840]:
		for h in [540, 576, 720, 768, 800, 900, 1080, 1440, 2160]:
			for u in [0.8, 0.9, 1.0, 1.1, 1.25]:
				for auto_on in [true, false]:
					var win := Vector2i(w, h)
					if float(w) / 1024.0 < 1.0 and float(h) / 576.0 < 1.0:
						continue         # finestre sotto 1024×576 fisici: il vincolo non può essere rispettato (minimo finestra 960×540)
					var l := UiScale.logical_size(win, UiScale.content_scale_factor(win, u, auto_on))
					# espansione: la dimensione che eccede l'aspetto 16:9 cresce, quindi basta la dimensione più stretta
					var ratio_ok: bool = l.x >= 1024.0 - 0.5 or l.y >= 576.0 - 0.5
					assert_true(ratio_ok, "%dx%d u=%s auto=%s → %s" % [w, h, u, auto_on, str(l)])
					assert_true(l.x >= 1024.0 - 0.5 and l.y >= 576.0 - 0.5, "area logica %s sotto 1024×576 (%dx%d u=%s auto=%s)" % [str(l), w, h, u, auto_on])


func test_finestra_minima_960x540_raggiunge_1024x576() -> void:
	var l := _logical(960, 540, 1.0, true)
	assert_almost_eq(l.x, 1024.0, 0.5)
	assert_almost_eq(l.y, 576.0, 0.5)


func test_auto_spento_e_il_comportamento_di_oggi() -> void:
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 800)]:
		assert_almost_eq(UiScale.content_scale_factor(sz, 1.0, false), 1.0, 0.0001, "csf 1,0 a %s" % str(sz))
		assert_almost_eq(UiScale.content_scale_factor(sz, 1.25, false), 1.25, 0.0001)
	var l := _logical(1920, 1080, 1.0, false)
	assert_almost_eq(l.x, 1280.0, 0.5, "a 1080p senza automatica l'area resta 1280×720 ingrandita")
	assert_almost_eq(l.y, 720.0, 0.5)


func test_conversione_dei_vecchi_valori() -> void:
	assert_almost_eq(UiScale.migrate_old_scale(1.0), 1.0, 0.0001)
	assert_almost_eq(UiScale.migrate_old_scale(1.25), 1.25, 0.0001)
	assert_almost_eq(UiScale.migrate_old_scale(0.75), 0.8, 0.0001)


func test_migrazione_in_settings_una_sola_volta() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.SECTION, "ui_scale", 0.75)
	cfg.set_value(Settings.SECTION, "volume_master", 0.5)
	assert_eq(cfg.save(Settings.path), OK)
	Settings.load_settings()
	assert_almost_eq(float(Settings.get_value("ui_scale")), 0.8, 0.0001)
	assert_true(Settings.get_value("ui_scale_auto"))
	assert_eq(Settings.get_value("ui_scale_rev"), 2)
	assert_true(Settings._scale_notice_pending, "chi aveva già impostazioni vede l'avviso")
	Settings.set_value("ui_scale", 0.9)
	Settings.load_settings()                       # seconda lettura: nessuna nuova conversione
	assert_almost_eq(float(Settings.get_value("ui_scale")), 0.9, 0.0001)
	assert_false(Settings._scale_notice_pending)
	# 1,0 e 1,25 restano come sono
	var cfg2 := ConfigFile.new()
	cfg2.set_value(Settings.SECTION, "ui_scale", 1.25)
	cfg2.save(Settings.path)
	Settings.load_settings()
	assert_almost_eq(float(Settings.get_value("ui_scale")), 1.25, 0.0001)


func test_nuova_installazione_senza_avviso() -> void:
	Settings.load_settings()                       # nessun file
	assert_eq(Settings.get_value("ui_scale_rev"), 2)
	assert_true(Settings.get_value("ui_scale_auto"))
	assert_false(Settings._scale_notice_pending)


func test_finestra_applica_il_fattore() -> void:
	var win := get_tree().root
	var old_size := win.size
	Settings.set_value("ui_scale_auto", true)
	Settings.set_value("ui_scale", 1.0)
	win.size = Vector2i(1920, 1080)
	await wait_process_frames(2)
	assert_almost_eq(win.content_scale_factor, 1.0, 0.01, "1080p automatica: 1,5 fisico (gradino) / 1,5 di Godot")
	Settings.set_value("ui_scale_auto", false)
	assert_almost_eq(win.content_scale_factor, 1.0, 0.0001, "auto spento: csf = dimensione")
	win.size = old_size


func test_voce_del_menu_dimensione_interfaccia() -> void:
	assert_eq(UiScale.size_index(true, 1.0), 0)
	assert_eq(UiScale.size_index(false, 1.0), 3)
	assert_eq(UiScale.size_index(true, 0.8), 1)
	assert_eq(UiScale.size_index(true, 1.25), 5)


func test_bande() -> void:
	assert_eq(UiBands.band(_logical(1600, 900, 1.0, true).x), UiBands.BAND_WIDE, "1600 logici = larga")
	assert_eq(UiBands.band(_logical(1920, 1080, 1.0, true).x), UiBands.BAND_NORMAL, "1280 logici = normale")
	assert_eq(UiBands.band(_logical(1280, 720, 1.0, true).x), UiBands.BAND_NORMAL)
	assert_eq(UiBands.band(_logical(1280, 720, 1.25, true).x), UiBands.BAND_NARROW)


func test_finestra_sotto_il_minimo_resta_classica() -> void:
	assert_almost_eq(UiScale.content_scale_factor(Vector2i(64, 64), 1.0, true), 1.0, 0.0001, "finestra di prova 64×64")
	assert_almost_eq(UiScale.content_scale_factor(Vector2i(800, 450), 1.25, true), 1.25, 0.0001)


## Revisione grafica 1.0, problema 1: con la scala automatica la scala fisica sta SEMPRE su un gradino pulito (mai 1,04 o 1,25).
func test_scala_fisica_a_gradini_puliti() -> void:
	var table := [
		[Vector2i(1280, 720), 1.0], [Vector2i(1280, 800), 1.0], [Vector2i(1366, 768), 1.0], [Vector2i(1600, 900), 1.0],
		[Vector2i(1920, 1080), 1.5], [Vector2i(1900, 1060), 1.5], [Vector2i(2560, 1440), 2.0], [Vector2i(3440, 1440), 2.0],
		[Vector2i(3840, 2160), 3.0], [Vector2i(5120, 2880), 4.0], [Vector2i(7680, 4320), 4.0],
	]
	for r in table:
		var win: Vector2i = r[0]
		var phys := UiScale.physical_scale(win, 1.0, true)
		assert_almost_eq(phys, float(r[1]), 0.0001, "%s: scala fisica" % str(win))
		assert_true(UiBands.SCALE_STEPS.has(phys), "%s: %s non è un gradino" % [str(win), phys])
		var csf := UiScale.content_scale_factor(win, 1.0, true)
		assert_almost_eq(UiScale.base_scale(win) * csf, phys, 0.0001, "csf coerente con la scala fisica")


func test_gradini_non_scendono_mai_sotto_uno_ne_superano_la_finestra() -> void:
	for w in range(960, 4000, 37):
		for h in [540, 600, 720, 800, 900, 1080, 1200, 1440, 2160]:
			var win := Vector2i(w, h)
			var phys := UiScale.physical_scale(win, 1.0, true)
			var cap := minf(float(w) / UiBands.MIN_LOGICAL.x, float(h) / UiBands.MIN_LOGICAL.y)
			assert_true(phys <= cap + 0.0001, "%s: scala %s oltre il tetto %s" % [str(win), phys, cap])
			assert_true(phys >= minf(1.0, cap) - 0.0001, "%s: scala %s sotto 1,0" % [str(win), phys])
			# nitidezza: ogni valore ≥ 1 è un gradino (oppure il tetto della finestra minima)
			assert_true(UiBands.SCALE_STEPS.has(phys) or absf(phys - cap) < 0.0001, "%s: %s non nitido" % [str(win), phys])


## Il tetto del 125% sulla dimensione scelta dal giocatore resta: la scala fisica non supera mai gradino × 1,25.
func test_tetto_125_per_cento_resta() -> void:
	for win in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		var step := UiScale.step_for(UiScale.base_scale(win))
		var phys := UiScale.physical_scale(win, 5.0, true)       # un valore fuori limite viene riportato a 1,25
		assert_true(phys <= step * 1.25 + 0.0001, "%s: %s oltre il 125%%" % [str(win), phys])
