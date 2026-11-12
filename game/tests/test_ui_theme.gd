extends GutTest
## Tema UI (resoconto 62): i temi generati da scripts/build_theme.gd esistono e hanno le variazioni usate dalle schermate,
## i telai di assets/ui/frames/ coincidono col manifest (dimensioni, margini coerenti, pixel senza antialiasing),
## gli accenti di sezione sono ridefinizioni delle variazioni, le cornici di rarità e gli stati vuoti si costruiscono.

const THEME := "res://src/ui/theme/main_theme.tres"
const VARIATIONS: PackedStringArray = ["TitleLabel", "BrandLabel", "SectionLabel", "MutedLabel", "MonoLabel", "NumberLabel",
	"WindowTitle", "SidebarButton", "AccentButton", "TopBarPanel", "ContentPanel", "LogPanel", "SidebarPanel", "CardPanel",
	"RaisedPanel", "InsetPanel", "BackdropPanel", "SearchField", "CardCommon", "CardRelic", "SlotCommon", "SlotRelic"]


func _theme() -> Theme:
	return load(THEME) as Theme


func test_main_theme_has_all_variations() -> void:
	var t := _theme()
	assert_not_null(t)
	for v in VARIATIONS:
		assert_true(t.get_type_list().has(v), "variazione mancante: " + v)


func test_project_uses_main_theme() -> void:
	assert_eq(str(ProjectSettings.get_setting("gui/theme/custom")), THEME)


func test_panels_are_textured_nine_slices() -> void:
	var t := _theme()
	for type in ["PanelContainer", "ContentPanel", "CardPanel", "TopBarPanel", "LogPanel", "SidebarPanel"]:
		assert_true(t.get_stylebox("panel", type) is StyleBoxTexture, type + " deve usare un telaio 9-slice")
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		assert_true(t.get_stylebox(st, "Button") is StyleBoxTexture, "Button/" + st)
	assert_true(t.get_stylebox("fill", "ProgressBar") is StyleBoxTexture)


func test_focus_is_visible_on_every_button_kind() -> void:
	var t := _theme()
	for type in ["Button", "AccentButton", "SidebarButton", "OptionButton", "CheckBox", "CheckButton"]:
		var sb := t.get_stylebox("focus", type) as StyleBoxTexture
		assert_not_null(sb, "focus senza telaio: " + type)


func test_frames_match_manifest() -> void:
	var man: Dictionary = UiKit.manifest()
	assert_gt(man.size(), 80, "il manifest dei telai è vuoto: python tools/make_ui_frames.py")
	for frame_id in man:
		var d: Dictionary = man[frame_id]
		var tex := UiKit.texture(frame_id)
		assert_not_null(tex, "PNG mancante: " + frame_id)
		if tex == null:
			continue
		assert_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(int(d.size[0]), int(d.size[1])), "dimensioni: " + frame_id)
		if d.has("margin"):
			var m: Array = d.margin
			assert_lte(int(m[0]) + int(m[2]), tex.get_width(), "margini orizzontali oltre la larghezza: " + frame_id)
			assert_lte(int(m[1]) + int(m[3]), tex.get_height(), "margini verticali oltre l'altezza: " + frame_id)


func test_frames_are_pixel_exact() -> void:
	# nessun antialiasing: ogni pixel è del tutto trasparente o del tutto opaco (controllo a campione su ogni telaio)
	for frame_id in UiKit.manifest():
		var img := UiKit.texture(frame_id).get_image()
		var bad := 0
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				if a > 0.01 and a < 0.99:
					bad += 1
		assert_eq(bad, 0, "pixel semitrasparenti (antialiasing) in " + frame_id)


func test_accent_themes_override_section_variations() -> void:
	for sec in ["skills", "adventure", "progress"]:
		var a := UiKit.accent_theme(sec)
		assert_not_null(a, sec)
		for v in ["ContentPanel", "TitleLabel", "SectionLabel", "CardPanel", "TopBarPanel"]:
			assert_true(a.get_type_list().has(v), "%s: manca %s" % [sec, v])
	assert_null(UiKit.accent_theme("city"), "la Città usa l'ottone del tema principale")
	assert_null(UiKit.accent_theme(""))
	var olive := (UiKit.accent_theme("skills").get_stylebox("fill", "ProgressBar") as StyleBoxTexture).texture
	var rust := (UiKit.accent_theme("adventure").get_stylebox("fill", "ProgressBar") as StyleBoxTexture).texture
	assert_ne(olive, rust, "le barre cambiano colore con la sezione")


func test_rarity_variations_exist_for_every_known_rarity() -> void:
	var t := _theme()
	for r in ["common", "rare", "epic", "legendary", "mythic", "relic"]:
		assert_true(t.get_type_list().has(String(UiKit.rarity_variation(r, true))), r)
		assert_true(t.get_type_list().has(String(UiKit.rarity_variation(r, false))), r)
	assert_eq(UiKit.rarity_variation("sconosciuta"), &"SlotCommon")
	assert_eq(UiKit.rarity_variation("epic", true), &"CardEpic")


func test_every_crate_rarity_has_a_frame() -> void:
	for r in DataRegistry.rules("crate_rules").get("rarities", []):
		assert_true(UiKit.RARITY_KEYS.has(str(r.id)), "rarità senza cornice: " + str(r.id))


func test_tinted_fill_keeps_color() -> void:
	var sb := UiKit.tinted_fill(Color("#d05050"))
	assert_eq(sb.modulate_color, Color("#d05050"))
	assert_not_null(sb.texture)


func test_empty_state_builds_picture_and_text() -> void:
	var c := UiKit.empty_state("chest", "UI_CRATES_EMPTY")
	autofree(c)
	assert_eq(c.get_child_count(), 2)
	assert_true(c.get_child(0) is TextureRect)
	assert_not_null((c.get_child(0) as TextureRect).texture)
	assert_true(c.get_child(1) is Label)


func test_main_screen_sets_accent_per_section() -> void:
	# la sezione Mansioni usa l'oliva, Avventura la ruggine, Progresso il viola; Città e Riepilogo l'ottone (nessun tema locale)
	assert_not_null(UiKit.accent_theme("skills"))
	assert_not_null(UiKit.accent_theme("adventure"))
	assert_not_null(UiKit.accent_theme("progress"))
	assert_null(UiKit.accent_theme("city"))
	assert_null(UiKit.accent_theme("summary"))


func test_text_colors_have_enough_contrast() -> void:
	# testi principali ≥ 4,5:1 sul fondo dei pannelli (docs/16): colore del testo, testo smorzato e titoli
	var t := _theme()
	var panel := Color("#1b1e26")
	assert_gte(_contrast(t.get_color("font_color", "Label"), panel), 4.5)
	assert_gte(_contrast(t.get_color("font_color", "MutedLabel"), panel), 4.5)
	assert_gte(_contrast(t.get_color("font_color", "TitleLabel"), panel), 4.5)
	for sec in ["skills", "adventure", "progress"]:
		var c := UiKit.accent_theme(sec).get_color("font_color", "SectionLabel")
		assert_gte(_contrast(c, panel), 4.5, "SectionLabel " + sec)


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
