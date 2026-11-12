extends GutTest
## Settings (user://settings.cfg), Loc e NumberFormat (docs/16 §5).

var _old_path: String
var _old_values: Dictionary


func before_each() -> void:
	_old_path = Settings.path
	_old_values = Settings._values.duplicate(true)
	Settings.path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()


func after_each() -> void:
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _old_values
	Settings.apply_all()


func test_impostazioni_persistono_e_validano() -> void:
	watch_signals(EventBus)
	assert_true(Settings.set_value("volume_music", 0.25))
	assert_signal_emitted_with_parameters(EventBus, "settings_changed", ["volume_music", 0.25])
	assert_true(Settings.set_value("reduce_motion", true))
	assert_true(Settings.set_value("ui_scale", 9.0), "fuori intervallo: viene limitato")
	assert_eq(Settings.get_value("ui_scale"), 1.25)
	assert_false(Settings.set_value("volume_music", "alto"), "tipo sbagliato")
	assert_false(Settings.set_value("chiave_inesistente", 1))
	assert_false(Settings.set_value("locale", "de"), "lingua non supportata")
	Settings.load_settings()
	assert_eq(Settings.get_value("volume_music"), 0.25, "riletto dal file")
	assert_eq(Settings.get_value("reduce_motion"), true)


func test_cambio_lingua_istantaneo() -> void:
	watch_signals(EventBus)
	Settings.set_value("locale", "it")
	assert_eq(tr("UI_NEW_GAME"), "Nuova partita")
	assert_eq(Loc.t({"it": "Spada", "en": "Sword"}), "Spada")
	Settings.set_value("locale", "en")
	assert_eq(tr("UI_NEW_GAME"), "New game")
	assert_eq(Loc.t({"it": "Spada", "en": "Sword"}), "Sword")
	assert_eq(Loc.t({"it": "Solo IT"}), "Solo IT", "ripiego sull'unica lingua presente")
	assert_signal_emitted(EventBus, "locale_changed")
	assert_eq(Loc.tf("UI_IDLE_WARNING", {"hours": 3}).find("{hours}"), -1, "segnaposto sostituito")


func test_numeri() -> void:
	assert_eq(NumberFormat.format_number(12450, "short", "it"), "12.450")
	assert_eq(NumberFormat.format_number(12450, "short", "en"), "12,450")
	assert_eq(NumberFormat.format_number(99999, "short", "en"), "99,999")
	assert_eq(NumberFormat.format_number(125000, "short", "en"), "125K")
	assert_eq(NumberFormat.format_number(1250000, "short", "it"), "1,25 M")
	assert_eq(NumberFormat.format_number(1250000, "short", "en"), "1.25M")
	assert_eq(NumberFormat.format_number(999950, "short", "en"), "1.00M", "arrotondamento al suffisso successivo")
	assert_eq(NumberFormat.format_number(3.2e15, "short", "en"), "3.20Qa")
	assert_eq(NumberFormat.format_number(1.25e36, "short", "it"), "1,25e36", "oltre Dc: scientifica")
	assert_eq(NumberFormat.format_number(1250000, "full", "it"), "1.250.000")
	assert_eq(NumberFormat.format_number(1250000, "scientific", "en"), "1.25e6")
	assert_eq(NumberFormat.format_number(-1500, "short", "en"), "-1,500")
	assert_eq(NumberFormat.format_number(0, "short", "en"), "0")


func test_percentuali_e_tempi() -> void:
	assert_eq(NumberFormat.format_pct(0.3, "it"), "0,3%")
	assert_eq(NumberFormat.format_pct(56.4, "en"), "56%")
	var u := {"s": "s", "min": "min", "h": "h", "d": "g"}
	assert_eq(NumberFormat.format_duration(3.2, u, "it"), "3,2 s")
	assert_eq(NumberFormat.format_duration(42, u, "it"), "42 s")
	assert_eq(NumberFormat.format_duration(18 * 60 + 5, u, "it"), "18 min")
	assert_eq(NumberFormat.format_duration(4 * 3600 + 12 * 60, u, "it"), "4 h 12 min")
	assert_eq(NumberFormat.format_duration(3 * 86400 + 2 * 3600, u, "it"), "3 g 2 h")
	assert_eq(NumberFormat.format_duration(7200, u, "it"), "2 h")
