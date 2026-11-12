extends GutTest
## Revisione grafica 1.0 (problemi 2, 3, 31 e 25): gerarchia tipografica unica, contrasto dei testi spenti, corpo minimo leggibile.
## Le misure vivono in UiType; qui si controlla che tema e schermate le rispettino.

const THEME := "res://src/ui/theme/main_theme.tres"
const ACCENTS := ["skills", "adventure", "progress"]

var _old_dir: String
var _old_auto: bool


func _theme() -> Theme:
	return load(THEME) as Theme


func test_gerarchia_titolo_sezione_corpo_nota() -> void:
	var t := _theme()
	assert_eq(t.default_font_size, UiType.BODY, "il corpo del tema è UiType.BODY")
	assert_eq(t.get_font_size("font_size", "TitleLabel"), UiType.PAGE)
	assert_eq(t.get_font_size("font_size", "MutedLabel"), UiType.NOTE)
	assert_eq(t.get_font_size("font_size", "IntroHint"), UiType.NOTE)
	assert_gt(UiType.PAGE, UiType.SECTION, "titolo di pagina > sezione")
	assert_gt(UiType.SECTION, UiType.BODY, "sezione > corpo")
	assert_gt(UiType.BODY, UiType.NOTE, "corpo > nota")
	assert_gte(UiType.NOTE, UiType.MIN)
	for s in [UiType.PAGE, UiType.SECTION, UiType.BODY, UiType.NOTE]:
		assert_eq(s % 2, 0, "corpo %d: pari, così a 1,5× resta un numero intero di px" % s)
	var accent_themes: Array[Theme] = [t]
	for sec in ACCENTS:
		accent_themes.append(UiKit.accent_theme(sec))
	for th in accent_themes:
		assert_eq(th.get_font_size("font_size", "SectionLabel"), UiType.SECTION, "i titoli di sezione non sono più piccoli del corpo")
		assert_gte(th.get_font_size("font_size", "SectionLabel"), t.default_font_size)
		var f := th.get_font("font", "SectionLabel") as FontVariation
		assert_true(f != null and f.base_font.resource_path.contains("Bold"), "titolo di sezione in grassetto")


func test_font_nitidi_hinting_e_posizione_intera() -> void:
	for f in ["AtkinsonHyperlegibleNext-Regular.ttf", "AtkinsonHyperlegibleNext-Medium.ttf", "AtkinsonHyperlegibleNext-Bold.ttf",
			"AtkinsonHyperlegibleNext-Italic.ttf", "AtkinsonHyperlegibleNext-BoldItalic.ttf", "VaultfallSymbols-Regular.ttf", "DepartureMono-Regular.otf"]:
		var font := load("res://assets/fonts/" + f) as FontFile
		assert_not_null(font, f)
		assert_ne(font.hinting, TextServer.HINTING_NONE, "%s: con hinting spento i glifi cadono a metà pixel" % f)
		assert_eq(font.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED, "%s: posizione dei glifi a pixel interi" % f)


func _contrast_min_on_frame(text: Color, frame: String) -> float:
	var img := (load("res://assets/ui/frames/%s.png" % frame) as Texture2D).get_image()
	var worst := 99.0
	for y in [6, 12, 18]:                       # il fondo interno del telaio (colonna centrale)
		worst = minf(worst, _contrast(text, img.get_pixel(12, y)))
	return worst


func test_testo_disabilitato_almeno_4_5_a_1() -> void:
	var t := _theme()
	for typ in ["Button", "OptionButton", "AccentButton"]:
		var kind := "accent" if typ == "AccentButton" else "std"
		var c := t.get_color("font_disabled_color", typ)
		assert_gte(_contrast_min_on_frame(c, "button_%s_disabled" % kind), 4.5, "%s disabilitato" % typ)
	assert_gte(_contrast_min_on_frame(t.get_color("font_disabled_color", "TabContainer"), "tab_disabled"), 4.5, "scheda disabilitata")
	assert_gte(_contrast(t.get_color("font_disabled_color", "CheckBox"), Color("#1b1e26")), 4.5, "casella disabilitata sul pannello")


func test_sintesi_dello_slot_sul_titolo_ha_il_velo() -> void:
	# la sintesi dell'ultima partita sta su un'illustrazione luminosa: il velo scuro deve dare ≥ 4,5:1 anche sul bianco pieno
	var glass: Color = load("res://src/ui/start/StartScreen.gd").BAND_COLOR
	var on_white := Color(1, 1, 1).lerp(Color(glass.r, glass.g, glass.b), glass.a)
	assert_gte(_contrast(Color(0.90, 0.87, 0.78), on_white), 4.5, "testo chiaro sul velo, nel caso peggiore")


## Ogni schermata registrata: titolo di pagina a larghezza naturale (mai a barra), titoli di sezione ≥ corpo, nessun testo sotto
## UiType.MIN (si guarda solo l'area del contenuto: menù laterale, barra alta e binario destro sono di altra competenza).
func test_schermate_rispettano_la_gerarchia() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = bool(Settings.get_value("ui_scale_auto"))
	SaveService.save_dir = "user://test_tipo_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	Game.new_game(1, "normal", 4242)
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)
	Settings.set_value("tutorials", false)
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	var bad := PackedStringArray()
	var titles := 0
	for e in ScreenRegistry.entries():
		if str(e.get("scene", "")) == "":
			continue
		if not main.show_screen(str(e.id), e.get("params", {})):
			continue
		await wait_process_frames(3)
		var first_title := true
		for n in _visible_controls(main.get_node("Root/Body/Content")):
			if n is Label and (n as Label).theme_type_variation == &"TitleLabel" and first_title:
				first_title = false
				titles += 1
				var l := n as Label
				if l.size_flags_horizontal & Control.SIZE_EXPAND != 0:
					bad.append("%s: titolo di pagina «%s» a barra (SIZE_EXPAND)" % [e.id, l.text.left(24)])
			if n is Label and (n as Label).theme_type_variation == &"SectionLabel":
				if (n as Label).get_theme_font_size("font_size") < _theme().default_font_size:
					bad.append("%s: sezione «%s» più piccola del corpo" % [e.id, (n as Label).text.left(24)])
			if n.name == &"Tag":
				continue                    # sigla di 2 lettere nel segnalino colorato del Registro: ridondante col nome accanto
			var sz := _text_size(n)
			if sz > 0 and sz < UiType.MIN:
				bad.append("%s: %s «%s» a %d px (< %d)" % [e.id, n.get_class(), str(n.get("text")).left(24), sz, UiType.MIN])
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings._values["ui_scale_auto"] = _old_auto
	Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	if not bad.is_empty():
		gut.p("\n".join(bad.slice(0, 40)))
	assert_gt(titles, 10, "il giro ha visto i titoli di pagina")
	assert_eq(bad.size(), 0, "violazioni (elenco sopra)")


func _text_size(n: Node) -> int:
	if n is Label or n is Button or n is LineEdit:
		if str(n.get("text")).strip_edges() == "":
			return 0
		return (n as Control).get_theme_font_size("font_size")
	if n is RichTextLabel:
		if (n as RichTextLabel).get_parsed_text().strip_edges() == "":
			return 0
		return (n as Control).get_theme_font_size("normal_font_size")
	return 0


func _visible_controls(root_node: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect(root_node, out)
	return out


func _collect(n: Node, out: Array[Node]) -> void:
	var c := n as Control
	if c != null:
		if not c.visible:
			return
		out.append(n)
	for k in n.get_children():
		_collect(k, out)


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
