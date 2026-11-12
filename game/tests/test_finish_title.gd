extends GutTest
## Finitura: Crediti bilingui, schermata iniziale (pulsanti, sfondo animato che rispetta «Riduci animazioni»),
## icone UI derivate dal colore, icona delle Casse dell'Era nei dati, nessun glifo fuori dai font inclusi in RaidPanel.

const START := "res://src/ui/start/StartScreen.tscn"
var _old_motion: bool
var _old_dir: String


func before_each() -> void:
	_old_motion = bool(Settings.get_value("reduce_motion"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_finish_title_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)
	Settings.set_value("reduce_motion", _old_motion)
	Settings.set_value("locale", "it")
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _credit_keys() -> PackedStringArray:
	var keys := PackedStringArray(["UI_CRED_TITLE", "UI_CRED_BUTTON", "UI_CRED_INTRO", "UI_CRED_THANKS", "UI_CRED_ORIGINAL"])
	for sec in CreditsView.SECTIONS:
		if str(sec[0]) != "":
			keys.append(str(sec[0]))
		for k in sec[1]:
			keys.append(str(k))
	return keys


func test_credits_texts_exist_in_both_languages() -> void:
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		for k in _credit_keys():
			assert_ne(tr(k), k, "%s manca in %s" % [k, lang])
	Settings.set_value("locale", "en")
	assert_string_contains(tr("UI_CRED_ENGINE"), "MIT")
	assert_string_contains(tr("UI_CRED_FONT_ATKINSON"), "Atkinson Hyperlegible Next")
	assert_string_contains(tr("UI_CRED_FONT_DEPARTURE"), "Departure Mono")
	assert_string_contains(tr("UI_CRED_FONT_SYMBOLS"), "Noto")


func test_credits_show_release_from_version_json() -> void:
	var v := CreditsView.new()
	add_child_autofree(v)
	var lab := v.get_node("VersionLabel") as Label
	assert_string_contains(lab.text, AppInfo.release_label())
	assert_eq(AppInfo.release_label(), "1.0")


func test_credits_has_no_personal_dedication() -> void:
	for lang in ["it", "en"]:
		Settings.set_value("locale", lang)
		for k in _credit_keys():
			assert_false(tr(k).to_lower().contains("dafne"), k)


func test_start_screen_has_all_buttons_and_credits_panel() -> void:
	var s := (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_frames(2)
	for n in ["ContinueButton", "NewGameButton", "SettingsButton", "QuitButton", "CreditsButton"]:
		assert_not_null(s.find_child(n, true, false), n)
	s.show_credits()
	await wait_frames(2)
	assert_true(s.get("_panel").visible)
	assert_not_null(s.get("_credits_view"))
	s.get("_credits_view").closed.emit()
	await wait_frames(2)
	assert_false(s.get("_panel").visible)


func test_backdrop_runs_only_without_reduce_motion() -> void:
	Settings.set_value("reduce_motion", false)
	var s := (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_frames(2)
	var b := s.get("_backdrop") as StartBackdrop
	assert_true(b.is_running(), "con le animazioni attive lo sfondo si muove")
	Settings.set_value("reduce_motion", true)
	assert_false(b.is_running(), "con Riduci animazioni lo sfondo si ferma subito")
	for m in b.get_children():
		assert_eq((m as CanvasItem).modulate.a, 0.0)
	Settings.set_value("reduce_motion", false)
	assert_true(b.is_running())


func test_backdrop_starts_still_with_reduce_motion() -> void:
	Settings.set_value("reduce_motion", true)
	var s := (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_frames(2)
	assert_false((s.get("_backdrop") as StartBackdrop).is_running())


func test_overwrite_confirm_on_full_slot() -> void:
	Game.new_game(1, "normal")
	Game.stop_game(true)
	var s := (load(START) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_frames(2)
	s.show_slots()
	s._on_new_in_slot(1, true)
	var c := s.get_node("Confirm") as ConfirmationDialog
	assert_true(c.visible)
	assert_eq(c.get_ok_button().text, tr("UI_START_OVERWRITE"))
	assert_ne(c.title, "Please Confirm...")
	c.hide()
	SaveService.delete_slot(1)


func test_derived_ui_icons_are_16px_with_color_changes_only() -> void:
	var pairs := {"ui_stat_speed": "ui_stat_evasion", "ui_stat_focus": "ui_stat_accuracy",
		"ui_stat_fury": "ui_elem_fire", "ui_currency_commission_token": "ui_currency_gold"}
	for dst in pairs:
		var a := (load("res://assets/ui/%s.png" % dst) as Texture2D).get_image()
		var b := (load("res://assets/ui/%s.png" % pairs[dst]) as Texture2D).get_image()
		assert_eq(a.get_size(), Vector2i(16, 16), dst)
		assert_eq(a.get_size(), b.get_size())
		var changed := 0
		for y in 16:
			for x in 16:
				assert_eq(a.get_pixel(x, y).a > 0.0, b.get_pixel(x, y).a > 0.0, "%s: la forma non deve cambiare (%d,%d)" % [dst, x, y])
				if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
					changed += 1
		assert_gt(changed, 20, "%s deve differire dall'originale nel colore" % dst)


func test_era_crate_icon_points_to_own_png() -> void:
	for n in range(2, 13):
		var it: Dictionary = DataRegistry.item("crate_era_%d" % n)
		assert_eq(str(it.icon), "res://assets/icons/crates/crate_era_%d.png" % n)
		assert_true(ResourceLoader.exists(str(it.icon)))


func test_raid_panel_roles_use_only_included_font_glyphs() -> void:
	for role in RaidPanel.ROLE_ICON:
		assert_false(str(RaidPanel.ROLE_ICON[role]).contains("⚔"))
