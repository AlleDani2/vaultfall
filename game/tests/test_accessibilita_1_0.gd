extends GutTest
## Accessibilità 1.0: filtro colore per daltonici (solo colore, D-6), alto contrasto, testo grande, percentuali sulle barre.

var _saved: Dictionary = {}
var _old_path: String


func before_each() -> void:
	_saved = Settings._values.duplicate(true)
	_old_path = Settings.path
	Settings.path = "user://test_a11y_%d.cfg" % Time.get_ticks_usec()


func after_each() -> void:
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _saved
	Settings.apply_all()


func test_modalita_e_parametri_del_filtro() -> void:
	var off := Accessibility.filter_params("off", false)
	assert_false(off.active)
	assert_eq(off.mode, 0)
	assert_eq(Accessibility.filter_params("protanopia", false).mode, 1)
	assert_eq(Accessibility.filter_params("deuteranopia", false).mode, 2)
	assert_eq(Accessibility.filter_params("tritanopia", false).mode, 3)
	assert_true(Accessibility.filter_params("deuteranopia", false).active)
	var hc := Accessibility.filter_params("off", true)
	assert_true(hc.active)
	assert_gt(float(hc.contrast), 1.0)
	assert_gt(float(hc.saturation), 1.0)
	assert_eq(Accessibility.COLORBLIND_MODES.size(), 4)


func test_il_filtro_e_un_nodo_nascosto_se_spento_e_visibile_se_acceso() -> void:
	var rt := Settings.runtime
	assert_not_null(rt)
	Settings.set_value("colorblind", "off")
	Settings.set_value("high_contrast", false)
	assert_false(rt.vision_layer.visible, "spento: nessun costo")
	Settings.set_value("colorblind", "protanopia")
	assert_true(rt.vision_layer.visible)
	var mat := (rt.vision_layer.get_node("Rect") as ColorRect).material as ShaderMaterial
	assert_eq(mat.get_shader_parameter("mode"), 1)
	Settings.set_value("colorblind", "off")
	Settings.set_value("high_contrast", true)
	assert_true(rt.vision_layer.visible)
	assert_almost_eq(float(mat.get_shader_parameter("contrast")), Accessibility.HIGH_CONTRAST, 0.0001)
	Settings.set_value("high_contrast", false)
	assert_false(rt.vision_layer.visible)
	assert_eq(rt.vision_layer.layer, UiRuntime.FILTER_LAYER)


func test_il_filtro_non_ruba_i_clic() -> void:
	var rect := Settings.runtime.vision_layer.get_node("Rect") as ColorRect
	assert_eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_solo_colore_nessuna_geometria_ne_png() -> void:
	# D-6: lo shader legge solo lo schermo e scrive solo COLOR; niente UV/VERTEX/texture esterne
	var src := FileAccess.get_file_as_string("res://src/ui/settings/vision_filter.gdshader")
	assert_false(src.contains("VERTEX"), "nessuna geometria")
	assert_false(src.contains("UV =") or src.contains("UV="), "nessuna modifica delle UV")
	assert_true(src.contains("COLOR ="))
	assert_false(src.contains("sampler2D") and src.contains("source_color"), "nessuna texture esterna")
	var code := FileAccess.get_file_as_string("res://src/ui/settings/Accessibility.gd")
	assert_false(code.contains("Image.") or code.contains("load(\"res://assets"), "nessuna lettura o scrittura di PNG")


func test_il_filtro_distingue_rosso_e_verde_per_chi_non_li_vede() -> void:
	var red := Color("#e5484d")
	var green := Color("#4caf50")
	for mode in ["protanopia", "deuteranopia"]:
		var sim_red := Accessibility._simulate(red, mode)
		var sim_green := Accessibility._simulate(green, mode)
		var fix_red := Accessibility._simulate(Accessibility.daltonize(red, mode), mode)
		var fix_green := Accessibility._simulate(Accessibility.daltonize(green, mode), mode)
		assert_gt(Accessibility.color_gap(fix_red, fix_green), Accessibility.color_gap(sim_red, sim_green),
			"%s: visti con la visione ridotta, rosso e verde si distinguono di più con il filtro" % mode)


func test_il_filtro_distingue_blu_e_giallo_per_chi_non_li_vede() -> void:
	var blue := Color("#4f8fe8")
	var yellow := Color("#e8b84f")
	var sim_b := Accessibility._simulate(blue, "tritanopia")
	var sim_y := Accessibility._simulate(yellow, "tritanopia")
	var fix_b := Accessibility._simulate(Accessibility.daltonize(blue, "tritanopia"), "tritanopia")
	var fix_y := Accessibility._simulate(Accessibility.daltonize(yellow, "tritanopia"), "tritanopia")
	assert_gt(Accessibility.color_gap(fix_b, fix_y), Accessibility.color_gap(sim_b, sim_y))


func test_daltonize_lascia_neutri_i_grigi_e_non_esce_dal_range() -> void:
	for mode in ["protanopia", "deuteranopia", "tritanopia"]:
		var g := Accessibility.daltonize(Color(0.5, 0.5, 0.5), mode)
		assert_almost_eq(g.r, 0.5, 0.06, "grigio resta grigio: " + mode)
		assert_almost_eq(g.g, 0.5, 0.06)
		assert_almost_eq(g.b, 0.5, 0.06)
		for c in [Color.RED, Color.GREEN, Color.BLUE, Color.WHITE, Color.BLACK, Color("#ff00ff")]:
			var o := Accessibility.daltonize(c, mode)
			assert_between(o.r, 0.0, 1.0)
			assert_between(o.g, 0.0, 1.0)
			assert_between(o.b, 0.0, 1.0)
	assert_eq(Accessibility.daltonize(Color("#336699"), "off"), Color("#336699"), "spento: nessun cambio")


func test_alto_contrasto_allarga_la_distanza_tra_scuri_e_chiari() -> void:
	var dark := Color(0.3, 0.3, 0.35)
	var light := Color(0.7, 0.7, 0.75)
	var base := Accessibility.color_gap(dark, light)
	var hc := Accessibility.color_gap(Accessibility.daltonize(dark, "off", Accessibility.HIGH_CONTRAST, Accessibility.HIGH_SATURATION),
		Accessibility.daltonize(light, "off", Accessibility.HIGH_CONTRAST, Accessibility.HIGH_SATURATION))
	assert_gt(hc, base * 1.2)
	var mid := Accessibility.daltonize(Color(0.5, 0.5, 0.5), "off", Accessibility.HIGH_CONTRAST, Accessibility.HIGH_SATURATION)
	assert_almost_eq(mid.r, 0.5, 0.001, "il grigio medio non si sposta")


func test_testo_grande_scala_i_corpi_e_si_ripristina() -> void:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_font_size("font_size", "TitleLabel", 22)
	th.set_font_size("font_size", "MutedLabel", 14)
	Accessibility.apply_text_scale(th, 1.5)
	assert_eq(th.default_font_size, 24)
	assert_eq(th.get_font_size("font_size", "TitleLabel"), 33)
	assert_eq(th.get_font_size("font_size", "MutedLabel"), 21)
	Accessibility.apply_text_scale(th, 1.25)
	assert_eq(th.default_font_size, 20, "si riparte dagli originali, non si compone")
	assert_eq(th.get_font_size("font_size", "TitleLabel"), 28)
	Accessibility.apply_text_scale(th, 1.0)
	assert_eq(th.default_font_size, 16)
	assert_eq(th.get_font_size("font_size", "TitleLabel"), 22)
	assert_eq(th.get_font_size("font_size", "MutedLabel"), 14)


func test_testo_grande_cambia_il_tema_del_progetto() -> void:
	var th := Accessibility.project_theme()
	assert_not_null(th)
	var before := th.default_font_size
	Settings.set_value("text_scale", 1.5)
	assert_gt(th.default_font_size, before)
	assert_eq(th.default_font_size, int(round(float(before) * 1.5)))
	Settings.set_value("text_scale", 1.0)
	assert_eq(th.default_font_size, before)


func test_testo_grande_nelle_etichette_vere() -> void:
	var l := Label.new()
	add_child_autofree(l)
	await wait_process_frames(1)
	var base := l.get_theme_font_size("font_size")
	Settings.set_value("text_scale", 1.25)
	await wait_process_frames(1)
	assert_gt(l.get_theme_font_size("font_size"), base)
	Settings.set_value("text_scale", 1.0)


func test_percentuale_sulle_barre() -> void:
	var b := ProgressBar.new()
	b.show_percentage = false
	add_child_autofree(b)
	Settings.set_value("bar_percent", true)
	assert_true(b.show_percentage, "le barre già aperte")
	var b2 := SmoothBar.new()
	add_child_autofree(b2)
	await wait_process_frames(2)
	assert_true(b2.show_percentage, "le barre nuove")
	Settings.set_value("bar_percent", false)
	assert_false(b.show_percentage)
	assert_false(b2.show_percentage)


func test_pannello_accessibilita_scrive_in_settings() -> void:
	var p := AccessibilityPanel.new()
	add_child_autofree(p)
	await wait_process_frames(1)
	p.text_opt.select(2)
	p.text_opt.item_selected.emit(2)
	assert_almost_eq(float(Settings.get_value("text_scale")), 1.5, 0.0001)
	p.colorblind_opt.select(2)
	p.colorblind_opt.item_selected.emit(2)
	assert_eq(Settings.get_value("colorblind"), "deuteranopia")
	p.contrast_check.button_pressed = true
	assert_true(bool(Settings.get_value("high_contrast")))
	p.percent_check.button_pressed = true
	assert_true(bool(Settings.get_value("bar_percent")))
	p.contrast_check.button_pressed = false
	p.percent_check.button_pressed = false


func test_anteprima_ha_il_nome_accanto_al_colore() -> void:
	var p := AccessibilityPanel.new()
	add_child_autofree(p)
	await wait_process_frames(1)
	var prev := p.find_child("Preview", true, false)
	assert_eq(prev.get_child_count(), AccessibilityPanel.PREVIEW.size())
	for box in prev.get_children():
		var t := (box.get_child(0) as Label).text
		assert_gt(t.length(), 3, "segno + nome, non solo colore: " + t)


func test_riduci_animazioni_e_effetti_nella_scheda() -> void:
	var p := AccessibilityPanel.new()
	add_child_autofree(p)
	await wait_process_frames(1)
	var keys := PackedStringArray()
	for l in p.find_children("*", "Label", true, false):
		keys.append(str((l as Label).text))
	assert_true(keys.has("UI_REDUCE_MOTION"))
	assert_true(keys.has("UI_FX_MODE"))
	assert_true(keys.has("UI_I10_A11Y_MOTION_NOTE"), "è descritto cosa cambia")
	assert_true(keys.has("UI_I10_A11Y_FX_NOTE"))


func test_categorie_del_registro_hanno_sigla_e_nome_oltre_al_colore() -> void:
	for cat in LogCategory.ORDER:
		assert_ne(LogCategory.tag(cat), "UI_LOGCAT_%s_TAG" % str(cat).to_upper(), "sigla tradotta " + str(cat))
		assert_ne(LogCategory.label(cat), "UI_LOGCAT_" + str(cat).to_upper(), "nome tradotto " + str(cat))
