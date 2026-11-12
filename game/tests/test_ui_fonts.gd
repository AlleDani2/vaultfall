extends GutTest
## Tipografia (resoconto 81): i font OFL inclusi si caricano, il Theme li usa (non più SystemFont come font principale),
## le licenze sono accanto ai file, ogni carattere dei testi (CSV IT/EN) è coperto dalla catena dei font inclusi
## (l'unica eccezione nota, ⚔ nel codice di RaidPanel, è lasciata al font di sistema) e il pixel font si usa solo a multipli di 11 px.

const DIR := "res://assets/fonts/"
const FILES: PackedStringArray = ["AtkinsonHyperlegibleNext-Regular.ttf", "AtkinsonHyperlegibleNext-Medium.ttf",
	"AtkinsonHyperlegibleNext-Bold.ttf", "AtkinsonHyperlegibleNext-Italic.ttf", "AtkinsonHyperlegibleNext-BoldItalic.ttf",
	"DepartureMono-Regular.otf", "VaultfallSymbols-Regular.ttf"]
const LICENSES: PackedStringArray = ["OFL-AtkinsonHyperlegibleNext.txt", "OFL-DepartureMono.txt", "OFL-VaultfallSymbols.txt"]
const THEME := "res://src/ui/theme/main_theme.tres"


func _theme() -> Theme:
	return load(THEME) as Theme


func test_font_files_load_and_licenses_present() -> void:
	for f in FILES:
		var font := load(DIR + f) as FontFile
		assert_not_null(font, "font non caricabile: " + f)
	for l in LICENSES:
		assert_true(FileAccess.file_exists(DIR + l), "licenza mancante: " + l)
		var txt := FileAccess.get_file_as_string(DIR + l)
		assert_true(txt.contains("SIL OPEN FONT LICENSE"), "non è la OFL: " + l)


func test_theme_uses_bundled_fonts() -> void:
	var t := _theme()
	assert_true(t.default_font is FontVariation, "il font di testo deve essere una FontVariation sui file inclusi")
	var base := (t.default_font as FontVariation).base_font
	assert_true(base is FontFile and base.resource_path.contains("AtkinsonHyperlegibleNext"), "testo = Atkinson")
	var title := t.get_font("font", "TitleLabel") as FontVariation
	assert_true(title.base_font.resource_path.contains("DepartureMono"), "titoli = Departure Mono")
	for v in ["BrandLabel", "WindowTitle"]:
		assert_true((t.get_font("font", v) as FontVariation).base_font.resource_path.contains("DepartureMono"), v)
	for v in ["MonoLabel", "NumberLabel"]:
		assert_true((t.get_font("font", v) as FontVariation).base_font.resource_path.contains("Atkinson"), v + " = dati leggibili")
	assert_true(t.has_font("bold_font", "RichTextLabel"))
	assert_true(t.has_font("bold_italics_font", "RichTextLabel"))


func test_pixel_font_sizes_are_multiples_of_11() -> void:
	var t := _theme()
	for v in ["TitleLabel", "BrandLabel", "WindowTitle"]:
		assert_eq(t.get_font_size("font_size", v) % 11, 0, "%s: il pixel font va a multipli di 11 px" % v)
	assert_eq(t.get_font_size("title_font_size", "Window") % 11, 0)


func test_tabular_digits_enabled() -> void:
	var t := _theme()
	var f := t.default_font as FontVariation
	assert_eq(int(f.opentype_features.get("tnum", 0)), 1)
	var w1 := f.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var w0 := f.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	assert_almost_eq(w1, w0, 0.5, "le cifre devono avere la stessa larghezza")


func test_line_height_not_inflated_by_fallbacks() -> void:
	var f := _theme().default_font
	assert_lte(f.get_height(16), 21.0, "l'interlinea a 16 px non deve gonfiarsi per i ripieghi")


func _chars_of_csv(path: String, out: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var row := f.get_csv_line()
		for i in range(1, row.size()):
			for ch in row[i]:
				out[ch] = true


func test_all_text_characters_covered() -> void:
	var chars := {}
	_chars_of_csv("res://localization/ui_strings.csv", chars)
	var d := DirAccess.open("res://localization/parts")
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".csv"):
				_chars_of_csv("res://localization/parts/" + fn, chars)
	var text_font := load(DIR + "AtkinsonHyperlegibleNext-Regular.ttf") as Font
	var pixel := load(DIR + "DepartureMono-Regular.otf") as Font
	var sym := load(DIR + "VaultfallSymbols-Regular.ttf") as Font
	var missing := PackedStringArray()
	for ch in chars:
		var cp := (ch as String).unicode_at(0)
		if cp < 32:
			continue
		if not (text_font.has_char(cp) or sym.has_char(cp) or pixel.has_char(cp)):
			missing.append("U+%04X %s" % [cp, ch])
	assert_eq(missing.size(), 0, "caratteri non coperti dai font inclusi: " + ", ".join(missing))
	for ch in "àèéìòùÀÈÉÌÒÙ’«»€★▸▾×":
		var cp := ch.unicode_at(0)
		assert_true(text_font.has_char(cp) or sym.has_char(cp) or pixel.has_char(cp), "manca " + ch)
