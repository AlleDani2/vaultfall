class_name TopBar
extends RefCounted
## Barra alta di MainScreen (docs/16 §2; F2 del progetto di interfaccia, docs/ui_redesign/06 §3.2, D4–D8).
## Da sinistra: marchio · Oro (clic = finestra Valute) · Polvere Stellare (dopo il Prestigio; clic = Costellazioni) ·
## Deposito «▣ N liberi» (ambra/rosso) · separatore · attività in un solo controllo · indicatore di modalità · ×N (debug) ·
## Pausa · Salva con stato · Impostazioni · Aiuto · pulsante colonna (passa a F3).
## Solo presentazione: legge GameState, BankSystem, SkillSystem, Clock; ascolta EventBus. I nodi stanno nella scena
## MainScreen.tscn (percorsi invariati: Root/TopBar/HBox/..., %GoldValue, %Activity, %ActivityBar, %LevelEta, ...);
## questa classe ne possiede la logica. MainScreen la crea in `_ready` e le delega i metodi pubblici.

const GOLD_ICON := "res://assets/ui/ui_currency_gold.png"
const DUST_ICON := "res://assets/ui/ui_currency_stardust.png"
const GROUP_IN := 6               # spazio fra elementi dello stesso gruppo (interfaccia)
const GROUP_GAP := 18             # larghezza dello spazio con filetto fra due gruppi
const CHIP_H := 32                # altezza comune di riquadri e icone
const SAVE_NOW_S := 5.0           # entro questi secondi dal salvataggio il tooltip dice «adesso» (interfaccia, non bilanciamento)

## Gradini con cui la barra si restringe quando il contenuto non entra nella finestra (si prova dal primo, si prende il primo che
## entra): barra sottile dell'attività corta · solo l'emblema al posto del lockup · numeri in formato corto e Deposito col solo
## numero · niente marchio · niente barra sottile. Il nome dell'attività si accorcia da sé (ActivityChip.fit_text).
const L_FULL := 0
const L_SLIM := 1
const L_EMBLEM := 2
const L_SHORT := 3
const L_NO_BRAND := 4
const L_NO_BAR := 5

## Larghezza logica sotto COMPACT_W: sparisce il marchio, i numeri passano al formato corto, il Deposito mostra il solo numero.
var compact: bool = false
## Gradino di restringimento in uso (L_FULL = barra intera).
var fit_level: int = L_FULL
var _short: bool = false

var _ms: Control
var _bar: Control
var _hbox: HBoxContainer
var _title: Control
var _gold_chip: TopCurrency
var _gold_value: Label
var _dust_chip: TopCurrency
var _dust_value: Label
var _bank_chip: BankChip
var _act_chip: ActivityChip
var _activity: Label
var _level_eta: Label
var _speed_btn: Button
var _pause_btn: TopIcon
var _save_btn: TopIcon
var _settings_btn: TopIcon
var _help_btn: Button
var _save_busy: bool = false
var _save_dirty: bool = false


func _init(ms: Control) -> void:
	_ms = ms
	_bar = ms.get_node("Root/TopBar")
	_hbox = ms.get_node("Root/TopBar/HBox")
	_title = _hbox.get_node("Title")
	_gold_chip = _hbox.get_node("GoldChip")
	_gold_value = ms.get_node("%GoldValue")
	_dust_chip = _hbox.get_node("DustChip")
	_dust_value = ms.get_node("%DustValue")
	_bank_chip = _hbox.get_node("BankChip")
	_act_chip = _hbox.get_node("ActivityChip")
	_activity = ms.get_node("%Activity")
	_level_eta = ms.get_node("%LevelEta")
	_speed_btn = ms.get_node("%SpeedButton")
	_pause_btn = ms.get_node("%PauseButton")
	_save_btn = ms.get_node("%SaveButton")
	_settings_btn = ms.get_node("%SettingsButton")


func gold_value() -> Label:
	return _gold_value


func level_eta() -> Label:
	return _level_eta


## Collegamenti dei pulsanti e proprietà dei testi (era l'inizio di MainScreen._ready).
func setup() -> void:
	TopCurrency.as_pic(_gold_chip.get_node("Row/GoldIcon") as Control).texture = load(GOLD_ICON) if ResourceLoader.exists(GOLD_ICON) else null
	TopCurrency.as_pic(_dust_chip.get_node("Row/DustIcon") as Control).texture = load(DUST_ICON) if ResourceLoader.exists(DUST_ICON) else null
	TopCurrency.as_brand(_title, TranslationServer.translate("UI_GAME_TITLE"))
	_gold_value.theme_type_variation = &"MonoLabel"
	_dust_value.theme_type_variation = &"MonoLabel"
	_gold_chip.activated.connect(_on_gold)
	_dust_chip.activated.connect(_on_dust)
	_bank_chip.activated.connect(_on_bank)
	_act_chip.activated.connect(_on_activity)
	_settings_btn.kind = TopIcon.Kind.SETTINGS
	_speed_btn.visible = OS.is_debug_build()
	_speed_btn.flat = true                                    # solo debug: non deve competere con le icone vere
	_speed_btn.add_theme_font_size_override("font_size", 12)
	_speed_btn.modulate = Color(1, 1, 1, 0.55)
	_group_bar()
	_speed_btn.pressed.connect(Clock.cycle_debug_speed)
	_pause_btn.pressed.connect(Clock.toggle_pause)
	_save_btn.pressed.connect(_on_save_pressed)
	_settings_btn.pressed.connect(_ms.show_screen.bind("settings"))
	_build_help_button()
	EventBus.save_completed.connect(_on_save_completed)
	EventBus.important_event.connect(_on_important)
	var pk := PauseKey.new()
	pk.name = "PauseKey"
	_ms.add_child(pk)
	_dust_chip.visible = false
	_ms.resized.connect(fit)          # finestra o scala cambiate: la barra si riadatta subito, senza attendere il ciclo a 10 Hz


## Gruppi della barra (rapporto 08 punto 11): [marchio] [risorse: Oro · Polvere · Deposito] | [attività, si allarga] | [comandi].
## I nodi restano figli diretti di HBox (percorsi stabili per test e tutorial): i gruppi si leggono dallo spazio, non dal nido.
## Dentro un gruppo 6 px, fra gruppi un filetto con respiro; tutto alto uguale e centrato in verticale.
func _group_bar() -> void:
	_hbox.add_theme_constant_override("separation", GROUP_IN)
	var sep := _hbox.get_node("Sep") as Control
	sep.add_theme_constant_override("separation", GROUP_GAP)
	var sep2 := VSeparator.new()
	sep2.name = "Sep2"
	sep2.add_theme_constant_override("separation", GROUP_GAP)
	_hbox.add_child(sep2)
	_hbox.move_child(sep2, _speed_btn.get_index())
	_hbox.move_child(_title, 0)
	for chip in [_gold_chip, _dust_chip, _bank_chip, _act_chip]:
		(chip as Control).custom_minimum_size.y = CHIP_H
		(chip as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Chiavi stabili dei controlli della barra che il tutorial può evidenziare (TutorialTargets): mai il testo tradotto.
func mark_targets() -> void:
	TutorialTargets.mark(_settings_btn, "topbar:settings")
	TutorialTargets.mark(_save_btn, "topbar:save")
	TutorialTargets.mark(_pause_btn, "topbar:pause")
	TutorialTargets.mark(_bank_chip, "topbar:bank")
	TutorialTargets.mark(_dust_chip, "topbar:stardust")
	TutorialTargets.mark(_act_chip, "topbar:activity")
	if _help_btn != null:
		TutorialTargets.mark(_help_btn, "topbar:help")


## Icona «?» nella barra in alto (visibile in ogni schermata): apre la pagina del Manuale della schermata corrente
## (la mappa schermata -> pagina è in ManualCatalog). Stessa azione del tasto F1.
func _build_help_button() -> void:
	var b := TopIcon.new()
	b.name = "HelpButton"
	b.kind = TopIcon.Kind.HELP
	b.add_theme_color_override("font_color", Color(0, 0, 0, 0))           # il «?» lo disegna TopIcon: il testo resta solo per gli ausili
	b.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	b.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	b.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
	b.text = "UI_MAN2_HELP"
	b.tooltip_text = "UI_MAN2_HELP_TIP"
	b.pressed.connect(_ms.open_help)
	_help_btn = b
	_settings_btn.get_parent().add_child(b)
	_settings_btn.get_parent().move_child(b, _settings_btn.get_index() + 1)


## Indicatore della modalità nella barra in alto (solo Autarchica ed Estrema): dopo l'attività, con tooltip esplicativo.
func build_mode_badge() -> void:
	var m := GameState.mode()
	if m == ModeRules.NORMAL:
		return
	var badge := Label.new()
	badge.name = "ModeBadge"
	badge.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	badge.theme_type_variation = &"SectionLabel"
	badge.text = "[%s]" % tr_key(ModeRules.label_key(m))
	badge.tooltip_text = tr_key("UI_MODES_DESC_" + m.to_upper())
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	_hbox.add_child(badge)
	_hbox.move_child(badge, _act_chip.get_index() + 1)


# ------------------------------------------------------------------ clic

func _on_gold() -> void:
	CurrencyPopup.open(_ms)


func _on_dust() -> void:
	_ms.show_screen("prestige", {"tab": "constellations"})      # scheda Costellazioni (se già visibile; altrimenti la prima)


func _on_bank() -> void:
	_ms.show_screen("bank")


func _on_activity() -> void:
	var id := str(MenuActivity.main_mark().get("id", ""))
	if id.is_empty() or not _ms.show_screen(id):
		_ms.show_screen("summary")


func _on_save_pressed() -> void:
	_save_busy = true
	SaveService.request_save()
	refresh_top()


func _on_save_completed(ok: bool) -> void:
	_save_busy = false
	_save_dirty = not ok


func _on_important(_reason: String) -> void:
	_save_dirty = true


# ------------------------------------------------------------------ larghezza

## Larghezza logica cambiata: con poco spazio sparisce il marchio e i numeri passano al formato corto.
func set_compact(value: bool) -> void:
	if value == compact:
		return
	compact = value
	apply_topbar()


func apply_topbar() -> void:
	_act_chip.set_compact(compact)
	refresh_top()
	_reshow_counter(_gold_value)
	_reshow_counter(_dust_value)


## Dopo un cambio di formato il contatore mostra subito il numero nel formato nuovo (senza attendere un cambio di valore).
func _reshow_counter(l: Label) -> void:
	if l.has_meta(FxCounter.META):
		var c: Variant = l.get_meta(FxCounter.META)
		if c is FxCounter and is_instance_valid(c):
			(c as FxCounter)._show()


## Formato dei numeri della barra: normale (impostazione del giocatore) oppure corto in banda compatta.
func _formatter() -> Callable:
	if _short:
		return func(v: float) -> String: return NumberFormat.format_number(v, "short", TranslationServer.get_locale().substr(0, 2))
	return func(v: float) -> String: return NumberFormat.fmt(v)


# ------------------------------------------------------------------ aggiornamento (10 Hz)

func pause_text() -> String:
	return "UI_RESUME" if Clock.paused else "UI_PAUSE"


func refresh_top() -> void:
	_refresh_values()
	fit()


## Larghezza che la barra può occupare: quella della schermata meno i margini del riquadro della barra.
func _avail_width() -> float:
	var sb := _bar.get_theme_stylebox("panel")
	return _ms.size.x - (sb.get_minimum_size().x if sb != null else 0.0)


## Larghezza minima del contenuto adesso: il nome dell'attività conta come il suo testo più corto (si ritaglia).
func _needed_width() -> float:
	return _hbox.get_combined_minimum_size().x + _act_chip.shrink_adjust()


## Restringe la barra solo quanto serve perché NIENTE esca dalla finestra: dal gradino più largo al più stretto si applica il
## primo per cui la larghezza minima entra. In banda compatta (`compact`) si parte da «niente marchio».
func fit() -> void:
	var avail := _avail_width()
	if avail <= 1.0:
		return
	_act_chip.width_cap = avail
	var lvl := L_NO_BRAND if compact else L_FULL
	while true:
		_apply_level(lvl)
		if lvl >= L_NO_BAR or _needed_width() <= avail:
			break
		lvl += 1
	fit_level = lvl
	_act_chip.refit()
	# Se un minimo largo di prima ha tenuto la colonna principale più larga della finestra, il minimo ora è sceso ma Godot non la
	# rimpicciolisce da solo: la si riporta alla larghezza della schermata.
	var root := _bar.get_parent() as Control
	if root != null and (root.size.x > _ms.size.x + 0.5 or absf(root.position.x) > 0.5):
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)       # cresciuta da entrambi i lati: anche la posizione torna a 0


func _apply_level(lvl: int) -> void:
	_title.visible = lvl < L_NO_BRAND
	if _title is TopCurrency.Brand:
		(_title as TopCurrency.Brand).emblem_only = lvl >= L_EMBLEM
	_act_chip.set_slim(lvl >= L_SLIM)
	_act_chip.set_bar_hidden(lvl >= L_NO_BAR)
	var short := compact or lvl >= L_SHORT
	if short != _short:
		_short = short
		_bank_chip.compact = short
		_refresh_values()
		_reshow_counter(_gold_value)
		_reshow_counter(_dust_value)


func _refresh_values() -> void:
	var fmt := _formatter()
	FxCounter.set_value(_gold_value, float(GameState.gold()), fmt)      # il contatore scorre (immediato con «riduci animazioni»)
	_refresh_dust(fmt)
	var bank := Game.system("bank") as BankSystem
	_bank_chip.refresh(bank, key_for("bank"))
	_speed_btn.text = "×%d" % int(Clock.speed)
	_refresh_icons()
	_act_chip.refresh()
	_gold_chip.tooltip_text = Loc.tf("UI_TOP_GOLD_TIP", {"n": NumberFormat.format_number(float(GameState.gold()), "full", TranslationServer.get_locale().substr(0, 2))})


## Polvere Stellare: nascosta finché il Prestigio non è sbloccato e la Polvere è 0 (D5).
func _refresh_dust(fmt: Callable) -> void:
	var bank := Game.system("bank") as BankSystem
	var dust := bank.currency(PrestigeSystem.DUST) if bank != null else 0
	var shown := dust > 0 or prestige_unlocked()
	_dust_chip.visible = shown
	if not shown:
		return
	FxCounter.set_value(_dust_value, float(dust), fmt)
	_dust_chip.tooltip_text = Loc.tf("UI_TOP_DUST_TIP", {"n": NumberFormat.format_number(float(dust), "full", TranslationServer.get_locale().substr(0, 2))})


## La schermata Prestigio è disponibile per la partita in corso.
static func prestige_unlocked() -> bool:
	return ScreenRegistry.is_available(ScreenRegistry.get_entry("prestige"), GameState.data.get("unlocks", []))


func _refresh_icons() -> void:
	_pause_btn.kind = TopIcon.Kind.PLAY if Clock.paused else TopIcon.Kind.PAUSE
	_pause_btn.tooltip_text = Loc.tf("UI_TOP_PAUSE_TIP_ON" if Clock.paused else "UI_TOP_PAUSE_TIP", {"key": key_for("pause")})
	if _save_busy:
		_save_btn.kind = TopIcon.Kind.SAVE_BUSY
	elif _save_dirty:
		_save_btn.kind = TopIcon.Kind.SAVE_DIRTY
	else:
		_save_btn.kind = TopIcon.Kind.SAVE_OK
	var age := maxf(0.0, SaveService.seconds_since_save())          # dall'ultimo salvataggio vero (anche di una sessione precedente)
	var when := tr_key("UI_TOP_SAVE_NOW") if age < SAVE_NOW_S else Loc.tf("UI_TOP_SAVE_AGO", {"time": NumberFormat.fmt_time(age)})
	_save_btn.tooltip_text = Loc.tf("UI_TOP_SAVE_TIP", {"when": when})
	_settings_btn.tooltip_text = Loc.tf("UI_TOP_SETTINGS_TIP", {"key": "Esc"})


## Mansione attiva sempre visibile (compatibilità: chiamata dai vecchi punti d'ingresso).
func refresh_activity() -> void:
	_act_chip.refresh()


## «Tempo al livello» nella barra (2 Hz).
func update_eta() -> void:
	_act_chip.update_eta()
	fit()                    # il tempo al livello cambia la larghezza minima: la barra si adatta subito


## Etichetta del tasto di una scorciatoia della tabella (ShortcutMap): una sola fonte per tooltip e Impostazioni.
static func key_for(id: String) -> String:
	return ShortcutMap.keys_label(id)


## Il tasto P (Pausa) è questo evento? Pura: la usano il gestore e i test.
static func is_pause_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and InputBindings.matches(k, "pause")


## Traduzione tramite MainScreen (Node.tr non esiste in RefCounted).
func tr_key(key: String) -> String:
	return _ms.tr(key)


## Tasto P = Pausa/Riprendi. Nodo figlio di MainScreen: riceve solo i tasti non consumati (un campo di testo con il focus li tiene)
## e cede il passo quando una finestra è aperta.
class PauseKey extends Node:
	func _unhandled_key_input(event: InputEvent) -> void:
		if not TopBar.is_pause_key(event):
			return
		var ov: Variant = get_parent().get("_overlay")
		if ov != null and ov.has_method("is_busy") and ov.is_busy():
			return
		Clock.toggle_pause()
		get_viewport().set_input_as_handled()
