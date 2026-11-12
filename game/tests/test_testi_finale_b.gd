extends GutTest
## Revisione finale B (docs/review_1_0/33 F-1, F-6, F-7): i testi delle Casse non dicono «solo valuta e cosmetici», Esc è descritto
## com'è davvero (finestra aperta, altrimenti menù di pausa), la pagina «Impostazioni» del Manuale conosce le sei schede.

var _old_locale := ""


func before_each() -> void:
	_old_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_old_locale)


func test_i_testi_delle_casse_dicono_la_verita_in_it_e_en() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		for k in ["UI_QUESTS_TUT_CRATES_2", "UI_QUESTS_MAN_START_4", "UI_MAN2_CRATES_WHAT", "UI_TUT_F_CRATES_B"]:
			var t := str(TranslationServer.translate(k))
			assert_ne(t, k, "chiave tradotta: " + k)
			assert_true(t.contains("permanent"), "%s (%s) dice dei bonus permanenti: %s" % [k, loc, t])
			if k == "UI_MAN2_CRATES_WHAT":      # qui «solo cosmetici» vale esplicitamente per Capsule e Casse evento
				assert_true(t.contains("Capsul"), "%s (%s) limita «cosmetici» alle Capsule: %s" % [k, loc, t])
			else:
				assert_false(t.to_lower().contains("cosmetic"), "%s (%s) non dice «cosmetici»: %s" % [k, loc, t])


func test_esc_nel_pannello_scorciatoie_apre_il_menu_di_pausa() -> void:
	var row := {}
	for r in ShortcutMap.TABLE:
		if r.id == "escape":
			row = r
	assert_false(row.is_empty())
	TranslationServer.set_locale("it")
	assert_true(str(TranslationServer.translate(row.text)).contains("pausa"))
	TranslationServer.set_locale("en")
	assert_true(str(TranslationServer.translate(row.text)).contains("pause menu"))


func test_il_manuale_delle_impostazioni_nomina_le_sei_schede() -> void:
	for loc in ["it", "en"]:
		TranslationServer.set_locale(loc)
		var t := ManualPages.build("settings", DataRegistry, [])
		for k in ["UI_I10_TAB_GAME", "UI_I10_TAB_SCREEN", "UI_I10_TAB_AUDIO", "UI_I10_TAB_A11Y", "UI_I10_TAB_CONTROLS", "UI_I10_TAB_DATA"]:
			assert_true(t.contains(str(TranslationServer.translate(k))), "%s: scheda %s nel Manuale" % [loc, k])
		assert_true(t.contains("VSync"))
		assert_false(t.contains("{"), "nessun segnaposto rimasto: " + loc)
		assert_true(t.contains("125"), "la riga dei numeri mostra le scale del testo (da Accessibility)")
	TranslationServer.set_locale("it")
	var it_text := ManualPages.build("settings", DataRegistry, [])
	assert_true(it_text.contains("Sabbia"))
	assert_true(it_text.contains("Esc"))


func test_la_pagina_iniziale_del_manuale_spiega_esc() -> void:
	TranslationServer.set_locale("en")
	assert_true(ManualPages.build("start", DataRegistry, []).contains("pause menu"))
