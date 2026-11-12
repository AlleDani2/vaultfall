extends GutTest
## Comandi rimappabili (InputBindings, scheda Comandi): predefiniti, riconoscimento, conflitti, ripristino, salvataggio.

var _saved: Dictionary = {}
var _old_path: String


func before_each() -> void:
	_saved = Settings._values.duplicate(true)
	_old_path = Settings.path
	Settings.path = "user://test_comandi_%d.cfg" % Time.get_ticks_usec()
	InputBindings.reset_all()


func after_each() -> void:
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _saved
	Settings.apply_all()
	InputBindings.install()


func _key(code: int, ctrl: bool = false, alt: bool = false, shift: bool = false) -> InputEventKey:
	var k := InputBindings.key_event(code, ctrl, alt, shift)
	k.pressed = true
	return k


func _pad(btn: int) -> InputEventJoypadButton:
	var j := InputBindings.pad_event(btn)
	j.pressed = true
	return j


func test_ogni_azione_ha_la_sua_azione_di_inputmap_con_i_predefiniti() -> void:
	for e in InputBindings.ACTIONS:
		var a := InputBindings.action_name(str(e.id))
		assert_true(InputMap.has_action(a), "azione " + str(e.id))
		assert_gt(InputMap.action_get_events(a).size(), 0, "eventi " + str(e.id))
		assert_true(InputBindings.is_default(str(e.id)), "predefinita " + str(e.id))
		assert_ne(tr(str(e.text)), str(e.text), "testo tradotto " + str(e.id))
	assert_eq(InputBindings.ACTIONS.size(), 9 + 5 + 5 + 1 + 1 + 11 + 8, "9 menù, 5 schermate, 5 gioco (colonna, pausa, Sabbia, rullo, cerca), Esc, F11, 11 Deposito, 8 controller")


func test_id_unici_e_testi_in_entrambe_le_lingue() -> void:
	var seen := {}
	for e in InputBindings.ACTIONS:
		assert_false(seen.has(e.id), "id doppio " + str(e.id))
		seen[e.id] = true
	var csv := FileAccess.get_file_as_string("res://localization/ui_strings.csv")
	for e in InputBindings.ACTIONS:
		assert_true(csv.contains(str(e.text) + ","), "chiave nel CSV: " + str(e.text))


func test_i_predefiniti_non_hanno_conflitti_tra_azioni_dello_stesso_tipo() -> void:
	for kind in [InputBindings.KIND_KEY, InputBindings.KIND_PAD]:
		var used := {}
		for id in InputBindings.ids_of_kind(kind):
			for ev in InputBindings.events_of(id):
				var key := JSON.stringify(InputBindings.serialize(ev))
				assert_false(used.has(key), "tasto doppio nei predefiniti: %s e %s" % [id, used.get(key, "")])
				used[key] = id


func test_riconoscimento_tasti_come_prima() -> void:
	assert_true(InputBindings.matches(_key(KEY_B), "bank"))
	assert_true(InputBindings.matches(_key(KEY_B, false, false, true), "bank"), "Maiusc non cambia le scorciatoie globali")
	assert_false(InputBindings.matches(_key(KEY_B, true), "bank"), "Ctrl+B non è B")
	assert_true(InputBindings.matches(_key(KEY_F, true), "search"))
	assert_false(InputBindings.matches(_key(KEY_F), "search"))
	assert_true(InputBindings.matches(_key(KEY_L, false, false, true), "bank_lock"))
	assert_false(InputBindings.matches(_key(KEY_L), "bank_lock"), "L da sola non è «Blocca»")
	assert_false(InputBindings.matches(_key(KEY_O, false, false, true), "bank_sort", true), "con Maiusc stretto: Maiusc+O non è Ordina")
	assert_true(InputBindings.matches(_key(KEY_O), "bank_sort", true))


func test_resolve_usa_i_comandi_cambiati() -> void:
	assert_eq(ShortcutMap.resolve(_key(KEY_B), []).get("id", ""), "bank")
	var r := InputBindings.assign("bank", InputBindings.key_event(KEY_J))
	assert_true(bool(r.ok))
	assert_eq(ShortcutMap.resolve(_key(KEY_J), []).get("id", ""), "bank", "il nuovo tasto apre il Deposito")
	assert_true(ShortcutMap.resolve(_key(KEY_B), []).is_empty(), "il vecchio non fa più nulla")
	assert_eq(ShortcutMap.key_label_for("bank", []), "J", "il tooltip del menù mostra il tasto attuale")
	assert_eq(TopBar.key_for("bank"), "J")


func test_menu_numerato_si_rimappa() -> void:
	assert_eq(ShortcutMap.keys_label("menu"), "1 – 9")
	assert_true(bool(InputBindings.assign("menu_1", InputBindings.key_event(KEY_F5)).ok))
	assert_eq(ShortcutMap.resolve(_key(KEY_F5), ["summary", "quests"]).get("id", ""), "summary")
	assert_ne(ShortcutMap.keys_label("menu"), "1 – 9", "non più i tasti di serie")
	assert_eq(ShortcutMap.key_label_for("summary", ["summary"]), "F5")


func test_resolve_bank_con_tasti_cambiati() -> void:
	assert_eq(ShortcutMap.resolve_bank(_key(KEY_S)), "select")
	assert_true(bool(InputBindings.assign("bank_select", InputBindings.key_event(KEY_X)).ok))
	assert_eq(ShortcutMap.resolve_bank(_key(KEY_X)), "select")
	assert_eq(ShortcutMap.resolve_bank(_key(KEY_S)), "")
	assert_eq(ShortcutMap.bank_keys_label("select"), "X")


func test_pausa_sabbia_rullo_e_manuale_seguono_i_comandi() -> void:
	assert_true(TopBar.is_pause_key(_key(KEY_P)))
	assert_true(bool(InputBindings.assign("pause", InputBindings.key_event(KEY_K)).ok))
	assert_false(TopBar.is_pause_key(_key(KEY_P)))
	assert_true(TopBar.is_pause_key(_key(KEY_K)))
	assert_eq(ShortcutMap.resolve(_key(KEY_T), []).get("type", ""), "push")
	assert_true(bool(InputBindings.assign("push", InputBindings.key_event(KEY_G)).ok))
	assert_eq(ShortcutMap.resolve(_key(KEY_G), []).get("type", ""), "push")
	assert_eq(ShortcutMap.resolve(_key(KEY_T), []).get("type", ""), "")


func test_conflitto_segnalato_e_nessuna_modifica() -> void:
	var r := InputBindings.assign("bank", InputBindings.key_event(KEY_C))
	assert_false(bool(r.ok))
	assert_eq(r.conflicts, ["hero"], "«C» è già dell'Eroe")
	assert_true(InputBindings.is_default("bank"), "niente è cambiato")
	assert_true(InputBindings.is_default("hero"))
	assert_eq(Settings.get_value("keybinds"), {})


func test_scambio_dopo_un_conflitto() -> void:
	var r := InputBindings.assign("bank", InputBindings.key_event(KEY_C), true)
	assert_true(bool(r.ok))
	assert_eq(InputBindings.label_for("bank"), "C")
	assert_eq(InputBindings.label_for("hero"), "B", "l'Eroe riceve il tasto che il Deposito aveva")
	assert_eq(ShortcutMap.resolve(_key(KEY_B), []).get("id", ""), "hero")


func test_conflitto_tra_tastiera_e_controller_non_esiste() -> void:
	var r := InputBindings.assign("pad_sand", _pad(JOY_BUTTON_Y))
	assert_eq(r.conflicts, ["pad_context"], "Y è già di «Menù dell'oggetto / Ordina»")
	var k := InputBindings.assign("bank", InputBindings.key_event(KEY_Y))
	assert_true(bool(k.ok), "il tasto Y della tastiera è libero")


func test_tasti_non_assegnabili_e_azione_fissa() -> void:
	assert_eq(InputBindings.rejects("bank", InputBindings.key_event(KEY_TAB)), "UI_I10_CTL_RESERVED")
	assert_eq(InputBindings.rejects("bank", InputBindings.key_event(KEY_UP)), "UI_I10_CTL_RESERVED")
	assert_eq(InputBindings.rejects("bank", InputBindings.key_event(KEY_ENTER)), "UI_I10_CTL_RESERVED")
	assert_eq(InputBindings.rejects("bank", InputBindings.key_event(KEY_SHIFT)), "UI_I10_CTL_NEED_KEY")
	assert_eq(InputBindings.rejects("bank", InputBindings.pad_event(JOY_BUTTON_A)), "UI_I10_CTL_NEED_KEY")
	assert_eq(InputBindings.rejects("pad_back", InputBindings.key_event(KEY_B)), "UI_I10_CTL_NEED_BUTTON")
	assert_eq(InputBindings.rejects("escape", InputBindings.key_event(KEY_J)), "UI_I10_CTL_FIXED")
	assert_eq(InputBindings.rejects("bank", InputBindings.key_event(KEY_UP, true)), "", "Ctrl+freccia è libera")
	assert_false(bool(InputBindings.assign("escape", InputBindings.key_event(KEY_J)).ok))
	assert_true(InputBindings.is_default("escape"))
	assert_eq(ShortcutMap.resolve(_key(KEY_ESCAPE), []).get("type", ""), "escape")


func test_ripristino_singolo_e_totale() -> void:
	InputBindings.assign("bank", InputBindings.key_event(KEY_J))
	InputBindings.assign("hero", InputBindings.key_event(KEY_K))
	assert_false(InputBindings.is_default("bank"))
	InputBindings.reset_one("bank")
	assert_true(InputBindings.is_default("bank"))
	assert_false(InputBindings.is_default("hero"))
	InputBindings.reset_all()
	assert_true(InputBindings.is_default("hero"))
	assert_eq(Settings.get_value("keybinds"), {})


func test_salvataggio_e_ricarica_dal_file() -> void:
	InputBindings.assign("bank", InputBindings.key_event(KEY_J, true))
	InputBindings.assign("pad_sand", _pad(JOY_BUTTON_RIGHT_STICK))
	var path := Settings.path
	Settings.flush()                                   # scritture ravvicinate della stessa chiave si fondono: qui si vuole il file aggiornato
	Settings._values = Settings.DEFAULTS.duplicate(true)
	InputBindings.apply_saved({})
	assert_true(InputBindings.is_default("bank"), "azzerato")
	Settings.load_settings()
	InputBindings.install()
	assert_eq(InputBindings.label_for("bank"), "Ctrl + J", "riletto dal file")
	assert_true(InputBindings.matches(_key(KEY_J, true), "bank"))
	assert_true(InputBindings.matches(_pad(JOY_BUTTON_RIGHT_STICK), "pad_sand"))
	assert_eq(Settings.path, path)


func test_dati_salvati_rovinati_non_rompono_nulla() -> void:
	Settings._values["keybinds"] = {"bank": [{"t": "key", "c": 0}], "hero": [42], "nonesiste": [{"t": "key", "c": KEY_J}],
		"pad_back": [{"t": "key", "c": KEY_J}], "menu_1": []}
	InputBindings.install()
	assert_true(InputBindings.is_default("bank"), "evento non valido: si torna al predefinito")
	assert_true(InputBindings.is_default("hero"))
	assert_true(InputBindings.is_default("pad_back"), "un tasto su un'azione del controller non vale")
	assert_true(InputBindings.is_default("menu_1"))


func test_conferma_e_indietro_del_controller_guidano_ui_accept_e_ui_cancel() -> void:
	var has_a := func(action: StringName, btn: int) -> bool:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == btn:
				return true
		return false
	assert_true(has_a.call(&"ui_accept", JOY_BUTTON_A))
	assert_true(has_a.call(&"ui_cancel", JOY_BUTTON_B))
	InputBindings.assign("pad_confirm", _pad(JOY_BUTTON_X), true)       # scambia con «Sabbia»
	assert_true(has_a.call(&"ui_accept", JOY_BUTTON_X))
	assert_false(has_a.call(&"ui_accept", JOY_BUTTON_A))
	assert_true(has_a.call(&"ui_accept", JOY_BUTTON_X), "la conferma segue la scelta")
	var tastiera := false
	for ev in InputMap.action_get_events(&"ui_accept"):
		tastiera = tastiera or ev is InputEventKey
	assert_true(tastiera, "Invio e Spazio restano")
	InputBindings.reset_all()
	assert_true(has_a.call(&"ui_accept", JOY_BUTTON_A))


func test_etichette_leggibili() -> void:
	assert_eq(InputBindings.label_for("bank_tab_prev"), "[  ·  Ctrl + PgUp")
	assert_eq(InputBindings.label_for("search"), "Ctrl + F")
	assert_eq(InputBindings.label_for("escape"), "Esc")
	assert_eq(InputBindings.label_for("pad_tab_prev", "xbox"), "LB")
	assert_eq(InputBindings.label_for("pad_tab_prev", "playstation"), "L1")
	assert_eq(InputBindings.label_for("pad_confirm", "xbox"), "A")


# ------------------------------------------------------------------ pannello

func _panel() -> ControlsPanel:
	var p := ControlsPanel.new()
	add_child_autofree(p)
	await wait_process_frames(1)
	return p


func test_pannello_elenca_ogni_azione_con_il_suo_tasto() -> void:
	var p := await _panel()
	for e in InputBindings.ACTIONS:
		var row := p.find_child("Row_" + str(e.id), true, false)
		assert_not_null(row, "riga " + str(e.id))
	var bank := p.find_child("Row_bank", true, false)
	assert_eq((bank.find_child("Keys", true, false) as Label).text, "B")
	assert_true((bank.find_child("Reset", true, false) as Button).disabled, "ripristina grigio se predefinito")
	assert_true((p.find_child("Row_escape", true, false).find_child("Change", true, false) as Button).disabled, "Esc è fisso")


func test_pannello_cambia_un_tasto_con_la_cattura() -> void:
	var p := await _panel()
	p.begin_capture("hero")
	assert_eq(p.capturing, "hero")
	p._input(_key(KEY_SHIFT))
	assert_eq(p.capturing, "hero", "un modificatore da solo non basta")
	p._input(_key(KEY_J))
	assert_eq(p.capturing, "")
	assert_eq(InputBindings.label_for("hero"), "J")
	await wait_process_frames(1)
	assert_eq((p.find_child("Row_hero", true, false).find_child("Keys", true, false) as Label).text, "J", "la riga si aggiorna")


func test_pannello_esc_annulla_la_cattura() -> void:
	var p := await _panel()
	p.begin_capture("hero")
	p._input(_key(KEY_ESCAPE))
	assert_eq(p.capturing, "")
	assert_true(InputBindings.is_default("hero"))


func test_pannello_segnala_il_conflitto_e_offre_lo_scambio() -> void:
	var p := await _panel()
	p.begin_capture("bank")
	p._input(_key(KEY_C))
	var status := p.find_child("Status", true, false) as Label
	assert_true(status.visible)
	assert_string_contains(status.text, ControlsPanel.row_title(InputBindings.entry("hero")))
	assert_true(p.find_child("ConflictRow", true, false).visible)
	assert_true(InputBindings.is_default("bank"), "finché non si sceglie, nulla cambia")
	p._on_swap()
	assert_eq(InputBindings.label_for("bank"), "C")
	assert_eq(InputBindings.label_for("hero"), "B")
	assert_false(status.visible)


func test_pannello_annulla_dopo_il_conflitto() -> void:
	var p := await _panel()
	p.begin_capture("bank")
	p._input(_key(KEY_C))
	p._clear_message()
	assert_true(InputBindings.is_default("bank"))
	assert_false(p.find_child("ConflictRow", true, false).visible)


func test_pannello_rifiuta_un_tasto_riservato_con_il_motivo() -> void:
	var p := await _panel()
	p.begin_capture("bank")
	p._input(_key(KEY_TAB))
	var status := p.find_child("Status", true, false) as Label
	assert_true(status.visible)
	assert_false(p.find_child("ConflictRow", true, false).visible, "nessuna scelta di scambio")
	assert_true(InputBindings.is_default("bank"))


func test_pannello_cattura_un_pulsante_del_controller() -> void:
	var p := await _panel()
	p.begin_capture("pad_bank")
	p._input(_key(KEY_J))
	assert_eq(p.capturing, "pad_bank", "un tasto non è un pulsante")
	p._input(_pad(JOY_BUTTON_LEFT_STICK))
	assert_eq(p.capturing, "")
	assert_true(InputBindings.matches(_pad(JOY_BUTTON_LEFT_STICK), "pad_bank"))


func test_pannello_ripristina_tutto() -> void:
	var p := await _panel()
	InputBindings.assign("bank", InputBindings.key_event(KEY_J))
	p.reset_all()
	assert_true(InputBindings.is_default("bank"))


func test_la_scheda_comandi_nelle_impostazioni_ha_il_pannello() -> void:
	var s: Control = (load("res://src/ui/screens/SettingsScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	s.open({})
	await wait_process_frames(2)
	assert_not_null(s.controls_panel)
	assert_eq(s.tabs.get_tab_control(4).find_child("ControlsPanel", true, false), s.controls_panel)
