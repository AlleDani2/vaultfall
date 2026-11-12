extends GutTest
## Rapporto 104: Registro a sezioni colorate. Palette (distinta, mai i colori delle rarità), mappa messaggio → sezione,
## formato della riga (striscia, sigla, titolo/dettaglio, nessun troncamento), voce di menù e Impostazioni con lo
## stesso colore, testi bilingui, «Riduci animazioni» (nessuna animazione nel Registro).

const MAIN := "res://src/ui/main/MainScreen.tscn"


func before_each() -> void:
	Settings.set_value("tutorials", false)


func _main() -> Control:
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


# ------------------------------------------------------------------ palette

func _lab(c: Color) -> Vector3:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var h := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = h.call(x)
	var fy: float = h.call(y)
	var fz: float = h.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func test_every_section_has_a_color_and_they_are_all_different() -> void:
	assert_eq(LogCategory.ORDER.size(), LogCategory.COLORS.size())
	for s in LogCategory.ORDER:
		assert_true(LogCategory.COLORS.has(s), "colore per " + s)
	for i in LogCategory.ORDER.size():
		for j in range(i + 1, LogCategory.ORDER.size()):
			var d := _lab(LogCategory.color(LogCategory.ORDER[i])).distance_to(_lab(LogCategory.color(LogCategory.ORDER[j])))
			assert_gt(d, 14.0, "%s e %s troppo simili (%.1f)" % [LogCategory.ORDER[i], LogCategory.ORDER[j], d])


func test_no_section_reuses_a_rarity_color() -> void:
	var rules: Dictionary = DataRegistry.rules("crate_rules")
	var rarities: Array = rules.get("rarities", [])
	assert_gt(rarities.size(), 0)
	for r in rarities:
		var rc := Color(str(r.color))
		for s in LogCategory.ORDER:
			var d := _lab(LogCategory.color(s)).distance_to(_lab(rc))
			assert_gt(d, 20.0, "%s ricorda la rarità %s (%.1f)" % [s, str(r.id), d])


func test_section_colors_are_readable_on_the_dark_background() -> void:
	var bg := Color("14171f")
	for s in LogCategory.ORDER:
		var c := LogCategory.color(s)
		var ratio := (_lum(c) + 0.05) / (_lum(bg) + 0.05)
		assert_gt(ratio, 4.5, "contrasto di %s sul fondo scuro: %.1f" % [s, ratio])
		# la sigla scura sulla pastiglia piena resta leggibile
		var on := (_lum(c) + 0.05) / (_lum(LogCategory.ON_COLOR) + 0.05)
		assert_gt(on, 4.5, "sigla su %s: %.1f" % [s, on])


func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


func test_texts_are_bilingual_and_tags_are_short_and_unique() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	var rows := {}
	f.get_csv_line()
	while not f.eof_reached():
		var l := f.get_csv_line()
		if l.size() >= 3 and not l[0].is_empty():
			rows[l[0]] = l
	var tags_it := {}
	var tags_en := {}
	for s in LogCategory.ORDER:
		for k in ["UI_LOGCAT_" + s.to_upper(), "UI_LOGCAT_%s_TAG" % s.to_upper()]:
			assert_true(rows.has(k), "manca " + k)
			assert_false(str(rows[k][1]).is_empty() or str(rows[k][2]).is_empty(), "testo bilingue " + k)
		var tag_en: String = rows["UI_LOGCAT_%s_TAG" % s.to_upper()][1]
		var tag_it: String = rows["UI_LOGCAT_%s_TAG" % s.to_upper()][2]
		assert_true(tag_en.length() == 2 and tag_it.length() == 2, "sigla di 2 lettere: " + s)
		assert_false(tags_it.has(tag_it), "sigla IT doppia " + tag_it)
		assert_false(tags_en.has(tag_en), "sigla EN doppia " + tag_en)
		tags_it[tag_it] = true
		tags_en[tag_en] = true


# ------------------------------------------------------------------ messaggio → sezione

func test_notice_sections_by_data() -> void:
	assert_eq(LogCategory.of_notice("info", {"section": "combat"}), "combat")
	assert_eq(LogCategory.of_notice("success", {"quest": "q"}), "quests")
	assert_eq(LogCategory.of_notice("success", {"digest": "ach"}), "feats")
	assert_eq(LogCategory.of_notice("info", {"digest": "event"}), "events")
	assert_eq(LogCategory.of_notice("warning", {"reason": "bank_full", "item": "x"}), "loot")
	assert_eq(LogCategory.of_notice("success", {"contract": "c"}), "market")
	assert_eq(LogCategory.of_notice("success", {"trial": "t"}), "prestige")
	assert_eq(LogCategory.of_notice("info", {"estate_event": "e"}), "estate")
	assert_eq(LogCategory.of_notice("info", {"offer": 1}), "combat")
	assert_eq(LogCategory.of_notice("info", {"category": "boss"}), "combat")
	assert_eq(LogCategory.of_notice("loot", {}), "loot")


func test_notice_without_data_follows_the_open_screen() -> void:
	assert_eq(LogCategory.of_notice("success", {}, "market"), "market")
	assert_eq(LogCategory.of_notice("info", {}, "skill:fishing"), "skills")
	assert_eq(LogCategory.of_notice("info", {}, "coop_lobby"), "coop")
	assert_eq(LogCategory.of_notice("info", {}, "summary"), "system", "il Riepilogo non è una sezione: Sistema")
	assert_eq(LogCategory.of_notice("info", {}, ""), "system")
	assert_eq(LogCategory.of_notice("info", {"section": "inventata"}, "market"), "market", "sezione sconosciuta ignorata")


func test_every_menu_screen_has_a_section_or_is_the_summary() -> void:
	for e in ScreenRegistry.entries():
		var id := str(e.id)
		if id == "summary":
			continue
		assert_true(LogCategory.is_valid(LogCategory.of_screen(id)), "la voce %s non ha una sezione" % id)


func test_notify_categories_map_to_sections() -> void:
	for c in NoticeFilter.CATEGORIES:
		assert_true(LogCategory.is_valid(LogCategory.of_notify_category(c)), "categoria di notifica " + c)


func test_systems_emit_valid_sections() -> void:
	for path in ["res://src/systems/CombatSystem.gd", "res://src/systems/SkillSystem.gd", "res://src/autoload/Game.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var from := 0
		while true:
			var i := src.find("\"section\": \"", from)
			if i < 0:
				break
			var j := src.find("\"", i + 12)
			assert_true(LogCategory.is_valid(src.substr(i + 12, j - i - 12)), "sezione valida in " + path)
			from = j


# ------------------------------------------------------------------ formato della riga

func test_split_text() -> void:
	assert_eq(LogCategory.split_text("Missione completata: Percorso: Taglialegna I. Riscatta!"),
		PackedStringArray(["Missione completata", "Percorso: Taglialegna I. Riscatta!"]))
	assert_eq(LogCategory.split_text("Hai vinto. Complimenti per la fatica"), PackedStringArray(["Hai vinto.", "Complimenti per la fatica"]))
	assert_eq(LogCategory.split_text("Solo un titolo"), PackedStringArray(["Solo un titolo", ""]))
	assert_eq(LogCategory.split_text("Una frase sola."), PackedStringArray(["Una frase sola.", ""]))
	var long_head := "x".repeat(60) + ": resto"
	assert_eq((LogCategory.split_text(long_head))[1], "", "titolo troppo lungo: niente taglio ai due punti")


func test_log_view_builds_rows_with_strip_chip_and_wrapped_text() -> void:
	var v := LogView.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	v.set_empty_text("vuoto")
	v.add_entry("combat", "Colpito: danni per 14 punti vita da un granchio piuttosto arrabbiato", "20:31")
	await wait_process_frames(1)
	assert_eq(v.row_count(), 1)
	assert_eq(v.row_section(0), "combat")
	var row: Control = v._rows[0].node
	var strip := row.get_node("Strip") as ColorRect
	assert_eq(strip.color, LogCategory.color("combat"), "la striscia ha il colore della sezione")
	assert_not_null(row.find_child("Chip", true, false), "pastiglia con la sigla")
	assert_eq((row.find_child("Tag", true, false) as Label).text, LogCategory.tag("combat"))
	assert_eq((row.find_child("Time", true, false) as Label).text, "20:31")
	var body := row.find_child("Body", true, false) as RichTextLabel
	assert_true(body.fit_content and body.autowrap_mode != TextServer.AUTOWRAP_OFF, "testo a capo, mai troncato")
	assert_string_contains(body.text, "[b]")


func test_log_view_escapes_brackets_and_caps_rows() -> void:
	assert_false(LogView.body_bbcode("a [color=red]b").contains("[color=red]"), "le parentesi del testo non diventano tag")
	var v := LogView.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	for i in LogView.MAX_ROWS + 25:
		v.add_entry("system", "riga %d" % i)
	assert_eq(v.row_count(), LogView.MAX_ROWS)
	assert_true(v.plain_text().ends_with("riga %d" % (LogView.MAX_ROWS + 24)))


func test_log_view_has_no_animation_so_reduce_motion_is_respected() -> void:
	Settings.set_value("reduce_motion", true)
	var v := LogView.new()
	add_child_autofree(v)
	await wait_process_frames(1)
	v.add_entry("loot", "Test: nessuna animazione")
	assert_eq(v.row_count(), 1)
	Settings.set_value("reduce_motion", false)


# ------------------------------------------------------------------ MainScreen

func test_main_screen_logs_notices_with_their_section() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var main := await _main()
	var lv := main.get_node("%Log") as LogView
	EventBus.notice.emit("success", "Missione completata: Prova", {"quest": "main_c1_q1"})
	EventBus.notice.emit("warning", "Deposito pieno: qualcosa", {"section": "loot"})
	EventBus.notice.emit("info", "Un messaggio senza dati", {})
	assert_eq(lv.row_section(lv.row_count() - 3), "quests")
	assert_eq(lv.row_section(lv.row_count() - 2), "loot")
	assert_true(LogCategory.is_valid(lv.row_section(lv.row_count() - 1)))
	(Game.system("unlock") as UnlockSystem).grant("feature:market")
	assert_true(main.show_screen("market"))
	EventBus.notice.emit("success", "Venduto", {})
	assert_eq(lv.row_section(lv.row_count() - 1), "market", "senza dati vale la schermata aperta")
	Game.stop_game(false)


func test_digest_lines_carry_their_section() -> void:
	var d := LogDigest.new()
	d.add_level("Taglialegna", 5)
	d.absorb("warning", "Deposito pieno: Pino", {"reason": "bank_full", "item": "Pino"})
	d.absorb("success", "Impresa", {"digest": "ach", "ach": "x"})
	var secs := {}
	for line in d.flush():
		secs[str(line.section)] = true
	assert_true(secs.has("skills") and secs.has("loot") and secs.has("feats"), str(secs))


func test_menu_buttons_and_content_edge_share_the_log_color() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var main := await _main()
	var found := 0
	for id in main._buttons:
		var b: Button = main._buttons[id]
		var sec := LogCategory.of_screen(str(id))
		if sec.is_empty():
			assert_null(b.get_node_or_null("SectionBar"), "il Riepilogo non ha barretta")
			continue
		var bar := b.get_node_or_null("SectionBar") as ColorRect
		assert_not_null(bar, "barretta su " + str(id))
		if bar != null:
			assert_eq(bar.color, LogCategory.color(sec))
			found += 1
	assert_gt(found, 5)
	main.show_screen("quests")
	assert_eq(LogCategory.of_screen(main.current_id), "quests")
	Game.stop_game(false)


func test_settings_notification_toggles_show_the_section_chip() -> void:
	var scr: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(scr)
	await wait_process_frames(2)
	var chips := scr.find_children("Chip", "PanelContainer", true, false)
	assert_gte(chips.size(), NoticeFilter.CATEGORIES.size(), "una pastiglia per ogni categoria di notifica")
