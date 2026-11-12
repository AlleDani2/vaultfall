extends GutTest
## Marchio 1.0 (tools/make_logo.py): i file generati ci sono e hanno le misure giuste, l'icona .ico ha tutti i frame, la
## schermata del titolo non ha testo tagliato né fuori schermo a 1280×720, 1600×900, 1080p e 4K, e non mostra chiavi nude (IT/EN).
## Il contenuto dei pixel (palette, tratto, parola ≥ 60% dell'altezza, monocromo) lo verifica tests/test_logo.py.

const START := "res://src/ui/start/StartScreen.tscn"
const StartScript := preload("res://src/ui/start/StartScreen.gd")
const BRAND := "res://assets/brand/"
const ICON_SIZES: Array[int] = [16, 32, 48, 64, 128, 256]

var _old_dir: String
var _old_locale: String


func before_each() -> void:
	_old_dir = SaveService.save_dir
	_old_locale = Loc.locale()
	SaveService.save_dir = "user://test_logo_1_0_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	DirAccess.make_dir_recursive_absolute(SaveService.save_dir)
	SlotSummary.invalidate()
	Settings.set_value("last_slot", 0)


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	SlotSummary.invalidate()
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	Settings.set_value("locale", _old_locale)


func _start() -> Control:
	var s: Control = (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	return s


func _img(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func test_file_del_marchio_esistono_con_le_misure_attese() -> void:
	var word := _img(BRAND + "logo_wordmark.png")
	assert_not_null(word)
	assert_eq(word.get_size(), Vector2i(104, 17), "parola grande: griglia 1:1")
	for n in ["logo_wordmark_white", "logo_wordmark_dark"]:
		assert_eq(_img(BRAND + n + ".png").get_size(), word.get_size(), n)
	var lock := _img(BRAND + "logo_lockup.png")
	assert_eq(lock.get_size(), Vector2i(118, 16), "lockup compatto")
	for n in ["logo_lockup_white", "logo_lockup_dark"]:
		assert_eq(_img(BRAND + n + ".png").get_size(), lock.get_size(), n)
	for n in ["emblem", "emblem_white", "emblem_dark"]:
		assert_eq(_img(BRAND + n + ".png").get_size(), Vector2i(32, 32), n)
	assert_eq(Vector2i(StartScript.LOGO_SIZE), word.get_size(), "StartScreen.LOGO_SIZE = misura reale del logo")


func test_icona_png_256_e_ico_con_tutti_i_frame() -> void:
	assert_eq(_img("res://icon.png").get_size(), Vector2i(256, 256))
	var f := FileAccess.open("res://icon.ico", FileAccess.READ)
	assert_not_null(f)
	var data := f.get_buffer(f.get_length())
	assert_eq(data.decode_u16(0), 0, "reserved")
	assert_eq(data.decode_u16(2), 1, "tipo ICO")
	var n := data.decode_u16(4)
	assert_eq(n, ICON_SIZES.size())
	var found: Array[int] = []
	for i in n:
		var w := data[6 + i * 16]
		found.append(256 if w == 0 else int(w))
	found.sort()
	assert_eq(found, ICON_SIZES)


func test_export_presets_usa_l_icona_giusta() -> void:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_string_contains(cfg, 'application/icon="res://icon.ico"')
	assert_eq(str(ProjectSettings.get_setting("application/config/icon")), "res://icon.png")


func _texts(root_node: Node) -> Array:
	var out: Array = []
	for n in root_node.find_children("*", "", true, false):
		if (n is Button or n is Label) and (n as Control).is_visible_in_tree():
			out.append(n)
	return out


func test_titolo_senza_testo_tagliato_alle_risoluzioni() -> void:
	_make_slot()
	var s := await _start()
	for v in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(3840, 2160)]:
		s.set_anchors_preset(Control.PRESET_TOP_LEFT)
		s.size = v
		s.call("_apply_layout")
		await wait_process_frames(3)
		var bad := LayoutChecker.scan(s, Rect2(Vector2.ZERO, v))
		assert_eq(bad.size(), 0, "%s: controlli fuori schermo %s" % [str(v), str(bad)])
		for c in _texts(s):
			var ctl := c as Control
			var txt := tr(str(ctl.get("text")))
			var font := ctl.get_theme_font("font")
			var fs := ctl.get_theme_font_size("font_size")
			var need := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if ctl is Label and (ctl as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
				assert_gte(ctl.size.y, font.get_height(fs) - 1.0, "%s a %s: riga senza altezza" % [txt, str(v)])
				continue
			assert_lte(need, ctl.size.x + 1.0, "%s a %s: testo tagliato" % [txt, str(v)])
		var title := s.get_node("Margin/Stage/Menu/TitleBox/Title") as Control
		var logo_w := title.offset_right - title.offset_left
		assert_eq(int(logo_w) % 104, 0, "il logo è a scala INTERA della griglia (%s)" % str(v))


func test_titolo_senza_chiavi_nude_it_en() -> void:
	_make_slot()
	var bare := RegEx.create_from_string("^UI_[A-Z0-9_]+$")
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		var s := await _start()
		for c in _texts(s):
			var txt := tr(str((c as Control).get("text")))
			if txt.strip_edges().is_empty():
				continue
			assert_null(bare.search(txt), "%s: chiave nuda «%s» nel titolo" % [lang, txt])
		s.queue_free()
		await wait_process_frames(1)


func test_barra_alta_e_crediti_usano_il_lockup() -> void:
	var holder := Control.new()
	add_child_autofree(holder)
	var b := TopCurrency.as_brand(holder, "VAULTFALL")
	assert_eq(b.get_minimum_size(), Vector2(236, 32), "lockup 118×16 a scala 2")
	var t := CreditsView.make_lockup()
	add_child_autofree(t)
	assert_eq(t.custom_minimum_size, Vector2(236, 32))
	assert_eq(t.texture.get_size(), Vector2(118, 16))


func _make_slot() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	assert_true(SaveService.save_now())
	Game.stop_game(false)
	SlotSummary.invalidate()
