extends GameScreen
## Combattimento (docs/16 §3.3): scelta zona/mostro, barre vita che scorrono, ritratto del mostro con tremolio,
## numeri di danno fluttuanti, risorsa dell'eroe, barra delle tecniche con ricariche, effetti attivi, meccaniche del boss,
## avanzamento del dungeon, registro, uccisioni e bottino recente. Solo presentazione: legge CombatSystem.
## "Riduci animazioni" (Settings.reduce_motion): niente tremolio né numeri che salgono, solo aggiornamento diretto.

const LOG_LINES_MAX := 60
const DROPS_MAX := 8
const DPS_WINDOW_S := 8.0                # finestra (secondi reali) del DPS mostrato: è solo presentazione
const INTRO_ID := "combat"               # voce di Settings.seen_intro: la frase «a cosa serve» compare alla prima visita
## Composizione dell'arena (revisione grafica 1.0): altezza = quota dell'altezza logica della finestra, tra un minimo e un massimo;
## punti d'ancoraggio orizzontali dei due ritratti; spazio riservato alle targhe in alto e al «terreno» in basso.
const ARENA_H_FRAC := 0.42
const ARENA_H_MIN := 250.0
const ARENA_H_MAX := 420.0
const PLATE_W := 300.0
const BAR_H := 24.0
const ARENA_PLATE_H := 100.0
const SPRITE_GROUND := 16.0
const HERO_X := 0.25
const ENEMY_X := 0.75
const ABIL_W := 108.0
const HOTBAR_FOOD_MIN := 600.0
const HOTBAR_ABIL_MIN := ABIL_W * 3.0 + 16.0 + 24.0        # tre caselle in fila, il resto va a capo
const TARGET_W := 176.0
const TARGET_H := 54.0
const SAFE_COLORS := {"green": Color("5fbf6a"), "yellow": Color("e0b640"), "red": Color("d9544d")}

var _combat: CombatSystem
var _zone_id: String = ""
var _monster_id: String = ""            # "" = a caso tra i normali
var _last_log_id: int = 0
var _log_lines: PackedStringArray = []
var _log_cats: PackedStringArray = []     # categoria di ogni riga (vedi _add_line)
var _log_filter: OptionButton
var _log_on: CheckButton
var _fallback_on: CheckButton
var _drops: PackedStringArray = []
var _abil_sig: String = ""
var _slots: Dictionary = {}              # id abilità -> {panel, cd_bar, cd_label, ready}
var _shown_enemy: String = ""
var _hero_style: String = "melee"      # stile dell'eroe (solo per scegliere il fendente)
var _cast_style: String = ""           # stile della classe dell'ultima tecnica lanciata (per il fendente del suo colpo)

var _zone_opt: OptionButton
var _zone_ids: Array = []
var _zone_banner: TextureRect
var _monster_list: HFlowContainer
var _monster_group := ButtonGroup.new()
var _start_btn: Button
var _dungeon_btn: Button
var _safety: Label
var _prep_lbl: Label                      # Q97: avviso «impreparato» (manca arma, armatura o cibo)
var _prep_go: Button                      # «Vai: Eroe» sotto l'avviso: dove si indossa e si dà il cibo (playtest novizio 121)
var _prep_dlg: ConfirmationDialog
var _status: Label
var _portrait: TextureRect
var _enemy_name: Label
var _enemy_mechs: Label
var _enemy_bar: ProgressBar
var _enemy_hp: Label
var _enemy_state: Label
var _hero_bar: ProgressBar
var _hero_hp: Label
var _res_bar: ProgressBar
var _res_label: Label
var _buffs_label: Label
var _hero_box: Control
var _fx_layer: Control
var _stage: Control                      # palco dell'arena (ritratti + effetti): scosse del boss e dei critici
var _hero_sprite: TextureRect             # ritratto della classe dell'eroe (a sinistra del quadro)
var _hero_name: Label
var _rest_hint: Label
var _abil_panel: Control
var _hero_status: VBoxContainer           # note dell'eroe sotto il quadro
var _arena_h: float = 0.0
var _fx_budget: int = 0                  # effetti «grandi» consentiti per aggiornamento (i numeri non hanno tetto qui)
var _banner: Label
var _abil_row: HFlowContainer
var _abil_hint: Label
var _wave_row: HBoxContainer
var _wave_label: Label
var _wave_bar: ProgressBar
var _log: RichTextLabel
var _kills: Label
var _drops_label: Label
var _wounded: Label
# COMBAT-3: postura, cibo, pericolo, avvisi del boss, reliquie, Prova, riepilogo
var _stance_lbl: Label
var _food_lbl: Label
var _food_panel: FoodPanel
var _thr_mark: ColorRect
var _danger_lbl: Label
var _danger_state: String = ""
var _relic_lbl: Label
var _relic_sig: String = ""
var _threat_lbl: Label
var _threat_pop: String = ""
var _trial_lbl: Label
var _summary_lbl: Label
var _summary_title: Label
# F8: testata, riga Tecniche, fisarmonica, colpo/max/DPS
var _risk_chip: PanelContainer
var _chip_sig: String = ""
var _help_btn: Button
var _intro_lbl: Label
var _hero_hits: Label
var _run_panel: RunPanel
var _sec_btn: Dictionary = {}              # id sezione -> intestazione
var _sec_body: Dictionary = {}             # id sezione -> corpo
var _open_section: String = ""             # "" = tutte chiuse; mai più di una aperta
var _run_seen: String = ""                 # ultima scelta della Corsa che ha aperto la sezione da sola
var _banner_has: bool = false
var _hits: Array = []                      # [istante_s, danno] degli ultimi colpi (per il DPS misurato)
var _last_hit: float = 0.0
var _max_hit: float = 0.0
var _was_fighting: bool = false
## Ultima sezione aperta della fisarmonica: resta tra una visita e l'altra della schermata (solo per questa sessione).
static var _last_section: String = ""


func open(params: Dictionary) -> void:
	_combat = Game.system("combat") as CombatSystem
	_build()
	var a: Dictionary = GameState.data.get("activity", {})
	if str(a.get("type", "")) == "combat":
		_zone_id = str(a.zone)
		_monster_id = str(a.monster)
	if not str(params.get("zone", "")).is_empty():       # da «Vai» delle Missioni: zona e mostro già scelti
		_zone_id = str(params.zone)
		_monster_id = str(params.get("monster", ""))
	_fill_zones()
	_last_log_id = _combat.log_last_id()
	_show_intro_once()
	refresh()
	if str(params.get("focus", "")) == "start" and _start_btn != null:
		ReqLink.reveal.call_deferred(_start_btn)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()       # la schermata scorre invece di tagliare (1280x720)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	page.add_child(_build_header())
	_intro_lbl = CombatUi.text_label(String(UiKit.INTRO_HINT), true)
	_intro_lbl.text = tr("UI_F8_INTRO")
	_intro_lbl.visible = false
	page.add_child(_intro_lbl)
	ScreenKit.cap_text(_intro_lbl)
	_prep_lbl = CombatUi.text_label("", true)             # Q97: avviso «impreparato» (manca arma, armatura o cibo)
	_prep_lbl.add_theme_color_override("font_color", SAFE_COLORS["red"])
	_prep_lbl.visible = false
	page.add_child(_prep_lbl)
	_prep_go = Button.new()                                # «Vai: Eroe» sotto l'avviso: dove si indossa e si dà il cibo
	_prep_go.name = "PrepGoHero"
	_prep_go.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_prep_go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_prep_go.visible = false
	_prep_go.pressed.connect(_open_hero)
	page.add_child(_prep_go)
	_trial_lbl = CombatUi.text_label("SectionLabel", true)
	_trial_lbl.visible = false
	page.add_child(_trial_lbl)
	# composizione (revisione grafica 1.0, punto 7): ARENA grande con eroe a sinistra e nemico a destra (barre sopra ciascuno),
	# sotto le note di stato, poi i bersagli come carte, poi la hotbar (Cibo + Tecniche); registro e bottino restano ripiegati
	page.add_child(_build_arena())
	page.add_child(_build_status_strip())
	page.add_child(_build_targets())
	var hotbar := HFlowContainer.new()
	hotbar.name = "Hotbar"
	hotbar.add_theme_constant_override("h_separation", 12)
	hotbar.add_theme_constant_override("v_separation", 8)
	page.add_child(hotbar)
	_food_panel = FoodPanel.new(true, true)
	hotbar.add_child(_food_panel)
	_abil_panel = _build_abilities_row()
	hotbar.add_child(_abil_panel)
	hotbar.resized.connect(_fit_hotbar.bind(hotbar))
	# avanzamento del dungeon (solo dentro un dungeon)
	_wave_row = HBoxContainer.new()
	_wave_row.add_theme_constant_override("separation", 8)
	_wave_label = CombatUi.text_label("SectionLabel")
	_wave_row.add_child(_wave_label)
	_wave_bar = CombatUi.bar(Color("c8a24a"), 14.0)
	_wave_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wave_row.add_child(_wave_bar)
	page.add_child(_wave_row)
	page.add_child(_build_accordion())


## Testata: titolo · Zona [▾] · [Combatti/Smetti] [Dungeon…] · UN chip di rischio · «?».
func _build_header() -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 6)
	var title := ScreenKit.title_style(CombatUi.label("UI_MENU_COMBAT", "TitleLabel"))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)
	_zone_opt = OptionButton.new()                        # «Zona [▾]»: la zona scelta si legge sul pulsante, il nome della voce è nel tooltip
	_zone_opt.tooltip_text = "UI_COMBAT_ZONE"
	_zone_opt.fit_to_longest_item = false
	_zone_opt.custom_minimum_size = Vector2(170, 0)
	_zone_opt.item_selected.connect(_on_zone_selected)
	h.add_child(_zone_opt)
	_start_btn = Button.new()
	_start_btn.theme_type_variation = &"AccentButton"
	_start_btn.pressed.connect(_on_start_pressed)
	h.add_child(_start_btn)
	TutorialTargets.mark(_start_btn, "combat_start")
	_dungeon_btn = Button.new()
	_dungeon_btn.text = "UI_C2_OPEN_DUNGEON"
	_dungeon_btn.pressed.connect(func() -> void: EventBus.screen_requested.emit("dungeon", {}))
	h.add_child(_dungeon_btn)
	_risk_chip = PanelContainer.new()                     # l'UNICO posto del rischio (D18): Sicuro in idle / Rischio / Pericolo
	_risk_chip.name = "RiskChip"
	_risk_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_risk_chip.visible = false
	_safety = CombatUi.text_label("")
	_safety.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_risk_chip.add_child(_safety)
	h.add_child(_risk_chip)
	_help_btn = Button.new()
	_help_btn.name = "CombatHelp"
	_help_btn.text = "?"
	_help_btn.tooltip_text = tr("UI_F8_INTRO")
	_help_btn.toggle_mode = true
	_help_btn.toggled.connect(func(on: bool) -> void: _intro_lbl.visible = on)
	h.add_child(_help_btn)
	return h


# ------------------------------------------------------------------ composizione (revisione grafica 1.0, punto 7)

## Targa semitrasparente sopra l'arena (nome + barre): fondo scuro e bordo sottile, il quadro dietro resta visibile.
func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.80)
	sb.border_color = ScreenKit.EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = PLATE_W
	return p


## Arena: quadro a tutta larghezza (≈ 42% dell'altezza della finestra) con l'eroe a sinistra e il nemico a destra, ciascuno con la
## propria targa (nome, Vita, risorsa) sopra. I ritratti sono a scala INTERA (mai frazioni, D-6); gli effetti restano dentro il quadro.
func _build_arena() -> Control:
	var stage := Panel.new()
	stage.name = "Arena"
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#12151d")
	bg.border_color = ScreenKit.EDGE
	bg.set_border_width_all(1)
	stage.add_theme_stylebox_override("panel", bg)
	stage.custom_minimum_size = Vector2(0, ARENA_H_MIN)
	stage.clip_contents = true                  # knockback e tremolii restano dentro il proprio riquadro (rapporto 104)
	stage.resized.connect(_fit_sprites)
	_stage = stage
	_zone_banner = TextureRect.new()             # l'immagine della zona è lo sfondo dell'arena
	_zone_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zone_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_zone_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_zone_banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_zone_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_banner.modulate = Color(1, 1, 1, 0.85)
	stage.add_child(_zone_banner)
	_hero_sprite = _new_sprite(HERO_X)
	stage.add_child(_hero_sprite)
	_portrait = _new_sprite(ENEMY_X)
	stage.add_child(_portrait)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_fx_layer)
	_banner = CombatUi.text_label("SectionLabel")
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 6.0
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_banner)
	# targa dell'eroe (in alto a sinistra)
	var hp := _plate()
	hp.name = "HeroPlate"
	hp.position = Vector2(12, 12)
	stage.add_child(hp)
	_hero_box = VBoxContainer.new()
	_hero_box.add_theme_constant_override("separation", 3)
	hp.add_child(_hero_box)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	_hero_box.add_child(hrow)
	_hero_name = CombatUi.text_label("SectionLabel")
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_name.add_theme_stylebox_override("normal", StyleBoxEmpty.new())      # dentro la targa: niente barra decorativa
	_hero_name.clip_text = true
	hrow.add_child(_hero_name)
	_hero_hp = CombatUi.text_label("MonoLabel")
	_hero_bar = CombatUi.bar(Color("4f9d5d"), BAR_H)
	_hero_box.add_child(_hero_bar)
	_bar_text(_hero_bar, _hero_hp)
	_thr_mark = ColorRect.new()                 # segno bianco: sotto questa vita l'eroe mangia da solo
	_thr_mark.color = Color(1, 1, 1, 0.85)
	_thr_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thr_mark.size = Vector2(2, BAR_H)
	_thr_mark.visible = false
	_hero_bar.add_child(_thr_mark)
	_res_label = CombatUi.text_label("MutedLabel")
	_hero_box.add_child(_res_label)
	_res_bar = CombatUi.bar(Color("5b8def"), 14.0)       # la Furia (o Focus/Mana): una barra vera, non un filo
	_hero_box.add_child(_res_bar)
	# targa del nemico (in alto a destra)
	var ep := _plate()
	ep.name = "EnemyPlate"
	ep.anchor_left = 1.0
	ep.anchor_right = 1.0
	ep.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ep.offset_right = -12.0
	ep.offset_top = 12.0
	stage.add_child(ep)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 3)
	ep.add_child(ev)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 8)
	ev.add_child(erow)
	_enemy_name = CombatUi.text_label("SectionLabel")
	_enemy_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_name.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_enemy_name.clip_text = true
	_enemy_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	erow.add_child(_enemy_name)
	_enemy_hp = CombatUi.text_label("MonoLabel")
	_enemy_bar = CombatUi.bar(Color("b8433b"), BAR_H)
	ev.add_child(_enemy_bar)
	_bar_text(_enemy_bar, _enemy_hp)
	_rest_hint = CombatUi.text_label("MutedLabel", true)         # a riposo, senza un mostro scelto: la targa dice cosa fare
	_rest_hint.text = tr("UI_GSA_COMBAT_REST")
	_rest_hint.custom_minimum_size.x = 120
	ev.add_child(_rest_hint)
	return stage


## Il valore (es. «214 / 518») scritto SULLA barra, centrato con un contorno scuro: una riga in meno nella targa.
func _bar_text(bar: ProgressBar, l: Label) -> void:
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	bar.add_child(l)


func _new_sprite(x_anchor: float) -> TextureRect:
	var t := TextureRect.new()
	t.anchor_left = x_anchor
	t.anchor_right = x_anchor
	t.anchor_top = 1.0
	t.anchor_bottom = 1.0
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## Dimensione di un ritratto a SCALA INTERA (×1, ×2, ×3, ×4 della PNG) nello spazio sotto le targhe, poi lo centra sul suo punto.
func _fit_sprites() -> void:
	if _stage == null or _hero_sprite == null:
		return
	var avail := _stage.size.y - ARENA_PLATE_H - SPRITE_GROUND
	for t in [_hero_sprite, _portrait]:
		var sz := CombatUi.int_fit(t.texture, avail)
		if sz == Vector2.ZERO:
			sz = Vector2(128, 128)
		t.offset_left = -sz.x * 0.5
		t.offset_right = sz.x * 0.5
		t.offset_top = -sz.y - SPRITE_GROUND
		t.offset_bottom = -SPRITE_GROUND


## Sotto il quadro: a sinistra le note dell'eroe (colpo/DPS, effetti, postura, pericolo, reliquie, uccisioni), a destra quelle del nemico.
func _build_status_strip() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_hero_status = VBoxContainer.new()
	_hero_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_status.add_theme_constant_override("separation", 2)
	h.add_child(_hero_status)
	var enemy_status := VBoxContainer.new()
	enemy_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_status.add_theme_constant_override("separation", 2)
	h.add_child(enemy_status)
	_hero_hits = CombatUi.text_label("MutedLabel", true)       # colpo / massimo / DPS misurati negli ultimi secondi
	_hero_hits.custom_minimum_size.x = 100
	_hero_status.add_child(_hero_hits)
	_buffs_label = CombatUi.text_label("MutedLabel", true)
	_buffs_label.custom_minimum_size.x = 100
	_hero_status.add_child(_buffs_label)
	_wounded = CombatUi.text_label("MutedLabel", true)
	_wounded.custom_minimum_size.x = 100
	_hero_status.add_child(_wounded)
	_stance_lbl = CombatUi.text_label("", true)
	_stance_lbl.custom_minimum_size.x = 100
	_stance_lbl.visible = false
	_stance_lbl.tooltip_text = tr("UI_C3_STANCE_TIP")
	_hero_status.add_child(_stance_lbl)
	_food_lbl = CombatUi.text_label("MutedLabel", true)
	_food_lbl.visible = false                    # sostituita dalla riga «Cibo» (slot, soglia, scorta nel ⓘ)
	_hero_status.add_child(_food_lbl)
	_danger_lbl = CombatUi.text_label("SectionLabel", true)
	_danger_lbl.custom_minimum_size.x = 100
	_danger_lbl.visible = false
	_hero_status.add_child(_danger_lbl)
	_relic_lbl = CombatUi.text_label("MutedLabel", true)
	_relic_lbl.custom_minimum_size.x = 100
	_relic_lbl.visible = false
	_hero_status.add_child(_relic_lbl)
	_enemy_mechs = CombatUi.text_label("MutedLabel", true)
	_enemy_mechs.custom_minimum_size.x = 120
	enemy_status.add_child(_enemy_mechs)
	_enemy_state = CombatUi.text_label("MutedLabel", true)
	_enemy_state.custom_minimum_size.x = 120
	enemy_status.add_child(_enemy_state)
	_threat_lbl = CombatUi.text_label("SectionLabel", true)
	_threat_lbl.custom_minimum_size.x = 120
	_threat_lbl.visible = false
	enemy_status.add_child(_threat_lbl)
	return h


## Hotbar: Cibo e Tecniche stanno in una riga se c'è posto (Cibo ≈ 60%, Tecniche il resto), altrimenti ognuno a tutta larghezza.
## Il minimo del Cibo non supera mai la larghezza della riga: la testata resta sempre dentro la finestra.
func _fit_hotbar(hotbar: Control) -> void:
	var w := hotbar.size.x
	if w <= 0.0 or _food_panel == null:
		return
	var sep := 12.0
	var food_w := HOTBAR_FOOD_MIN
	if w >= HOTBAR_FOOD_MIN + HOTBAR_ABIL_MIN + sep:
		food_w = clampf((w - sep) * 0.6, HOTBAR_FOOD_MIN, w - sep - HOTBAR_ABIL_MIN)
	food_w = minf(food_w, w)
	if absf(_food_panel.custom_minimum_size.x - food_w) > 0.5:
		_food_panel.custom_minimum_size.x = food_w


## Bersagli: una carta per mostro (nome e livello su due righe), in fila che va a capo; la scelta è un interruttore di gruppo.
func _build_targets() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var t := CombatUi.label("UI_COMBAT_MONSTER", "SectionLabel")
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	_status = CombatUi.text_label("MutedLabel", true)        # solo «A riposo…» e il conto alla rovescia dopo la morte
	_status.custom_minimum_size.x = 120
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_status)
	_kills = CombatUi.text_label("", true)
	_kills.custom_minimum_size.x = 100
	_kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_kills)
	_monster_list = HFlowContainer.new()
	_monster_list.add_theme_constant_override("h_separation", 6)
	_monster_list.add_theme_constant_override("v_separation", 6)
	v.add_child(_monster_list)
	return v


## Hotbar delle Tecniche: una casella grande per tecnica (icona a scala 2×, numero = priorità, ricarica che si svuota) e,
## sotto, il suggerimento «prossima tecnica». Il Cibo è la sua riga accanto (FoodPanel compatto).
func _build_abilities_row() -> Control:
	var panel := PanelContainer.new()
	panel.name = "AbilitiesPanel"
	panel.theme_type_variation = &"ContentPanel"
	panel.custom_minimum_size.x = HOTBAR_ABIL_MIN
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var t := CombatUi.label("UI_C2_ABILITIES", "SectionLabel")
	v.add_child(t)
	_abil_row = HFlowContainer.new()          # a capo se le tecniche non stanno in riga
	_abil_row.add_theme_constant_override("h_separation", 8)
	_abil_row.add_theme_constant_override("v_separation", 8)
	v.add_child(_abil_row)
	_abil_hint = CombatUi.text_label("MutedLabel", true)
	_abil_hint.custom_minimum_size.x = 120
	v.add_child(_abil_hint)
	return panel


## Fisarmonica: tre intestazioni in riga e UN solo corpo aperto alla volta (La Corsa · Bottino recente · Registro).
func _build_accordion() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var heads := HFlowContainer.new()
	heads.add_theme_constant_override("h_separation", 8)
	heads.add_theme_constant_override("v_separation", 4)
	v.add_child(heads)
	var bodies := VBoxContainer.new()
	v.add_child(bodies)
	_run_panel = RunPanel.new()                # CORSA (resoconto 91): riquadro della Corsa a scelte (si nasconde se bloccata)
	TutorialTargets.mark(_run_panel, "run_panel")
	var loot := VBoxContainer.new()
	loot.add_theme_constant_override("separation", 4)
	_drops_label = CombatUi.text_label("", true)
	_drops_label.custom_minimum_size.x = 120
	loot.add_child(_drops_label)
	_summary_title = CombatUi.label("UI_C3_SUMMARY", "SectionLabel")
	loot.add_child(_summary_title)
	_summary_lbl = CombatUi.text_label("", true)
	_summary_lbl.custom_minimum_size.x = 120
	_summary_lbl.text = tr("UI_C3_SUMMARY_NONE")
	loot.add_child(_summary_lbl)
	var logb := VBoxContainer.new()
	logb.add_theme_constant_override("separation", 4)
	logb.add_child(_build_log_tools())
	_log = RichTextLabel.new()
	_log.theme_type_variation = &"LogPanel"
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 140)
	_log.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	logb.add_child(_log)
	for def in [["run", _run_panel], ["loot", loot], ["log", logb]]:
		var id := str(def[0])
		var b := Button.new()
		b.name = "Section_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _set_section("" if _open_section == id else id))
		heads.add_child(b)
		var body_box := VBoxContainer.new()
		body_box.visible = false
		body_box.add_child(def[1] as Control)
		bodies.add_child(body_box)
		_sec_btn[id] = b
		_sec_body[id] = body_box
	TutorialTargets.mark(_sec_btn["run"], "run_panel")      # chiusa, il tutorial indica l'intestazione
	_open_section = _last_section
	_apply_sections()
	return v


## Sezione aperta della fisarmonica ("" = tutte chiuse). Se ne apre una sola alla volta; la scelta resta tra le visite.
func _set_section(id: String) -> void:
	_open_section = id
	_last_section = id
	_apply_sections()


func _apply_sections() -> void:
	var run_ok := _run_unlocked()
	if _open_section == "run" and not run_ok:
		_open_section = ""
	for id in _sec_body:
		(_sec_body[id] as Control).visible = id == _open_section
		var b := _sec_btn[id] as Button
		b.visible = id != "run" or run_ok
		var key := {"run": "UI_RUN_TITLE", "loot": "UI_COMBAT_RECENT_DROPS", "log": "UI_COMBAT_LOG"}[id] as String
		var txt := Disclosure.label(key, id == _open_section)
		if id == "run" and _run_pending():
			txt += "  •  " + tr("UI_F8_RUN_WAITING")           # puntino: una scelta aspetta, anche a sezione chiusa
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = txt


func _run_unlocked() -> bool:
	var rs := Game.system("run") as RunSystem
	return rs != null and str(rs.status().phase) != "locked"


func _run_pending() -> bool:
	var rs := Game.system("run") as RunSystem
	return rs != null and str(rs.status().phase) != "locked" and not (rs.state.offer as Array).is_empty()


## La Corsa si apre DA SOLA quando compare una scelta nuova (una volta per scelta: chi chiude non viene richiamato a ogni aggiornamento).
func _refresh_sections() -> void:
	var rs := Game.system("run") as RunSystem
	if rs != null and _run_pending():
		var sig := "%d|%s" % [(rs.state.picks as Array).size(), ",".join(PackedStringArray(rs.state.offer))]
		if sig != _run_seen:
			_run_seen = sig
			_open_section = "run"
			_last_section = "run"
	_apply_sections()


## Filtri e interruttore del registro (docs/05 §13, UI-A G21): salvati nelle Impostazioni.
func _build_log_tools() -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 8)
	_log_on = CheckButton.new()
	_log_on.text = "UI_UIA_LOG_ON"
	_log_on.tooltip_text = "UI_UIA_LOG_ON_TIP"
	_log_on.button_pressed = bool(Settings.get_value("combat_log"))
	_log_on.toggled.connect(func(on: bool) -> void:
		Settings.set_value("combat_log", on)
		if not on:
			_log_lines = PackedStringArray()
			_log_cats = PackedStringArray()
			_log.text = "")
	h.add_child(_log_on)
	_fallback_on = CheckButton.new()
	_fallback_on.text = "UI_OFFL_FALLBACK_OPT"
	_fallback_on.tooltip_text = "UI_OFFL_FALLBACK_OPT_TIP"
	_fallback_on.toggled.connect(func(on: bool) -> void:
		if _combat != null:
			_combat.set_safe_fallback(on))
	h.add_child(_fallback_on)
	_log_filter = OptionButton.new()
	_log_filter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for m in ["all", "rare", "boss"]:
		_log_filter.add_item(tr("UI_UIA_LOG_F_" + str(m).to_upper()))
	_log_filter.select(maxi(0, ["all", "rare", "boss"].find(str(Settings.get_value("combat_log_filter")))))
	_log_filter.item_selected.connect(func(i: int) -> void:
		Settings.set_value("combat_log_filter", ["all", "rare", "boss"][i]))
	h.add_child(_log_filter)
	return h


# ------------------------------------------------------------------ zone e mostri

func _fill_zones() -> void:
	_zone_opt.clear()
	_zone_ids.clear()
	var first_unlocked := -1
	for z in _combat.zones():
		var idx := _zone_opt.item_count
		_zone_opt.add_item(Loc.t(z.def.name) + ("" if z.unlocked else "  (" + tr("UI_COMBAT_LOCKED") + ")"))
		_zone_opt.set_item_disabled(idx, not z.unlocked)
		_zone_ids.append(str(z.id))
		if z.unlocked and first_unlocked < 0:
			first_unlocked = idx
	var sel := _zone_ids.find(_zone_id)
	if sel < 0 or _zone_opt.is_item_disabled(sel):
		sel = maxi(0, first_unlocked)
		_zone_id = str(_zone_ids[sel]) if not _zone_ids.is_empty() else ""
		_monster_id = ""
	_zone_opt.select(sel)
	_fill_monsters()


func _on_zone_selected(idx: int) -> void:
	_zone_id = str(_zone_ids[idx])
	_monster_id = ""
	_fill_monsters()


func _fill_monsters() -> void:
	CombatUi.set_banner(_zone_banner, str(_combat.zone_def(_zone_id).get("banner", "")))
	_banner_has = _zone_banner.texture != null
	_apply_band()
	for c in _monster_list.get_children():
		c.queue_free()
	_add_monster_button("", tr("UI_COMBAT_RANDOM"), "")
	for m in _combat.monsters_of(_zone_id):
		var txt := "%s\n%s %d" % [Loc.t(m.name), tr("UI_COMBAT_LV"), int(m.level)]
		if str(m.type) != "normal":
			txt += "  [%s]" % tr("UI_COMBAT_TYPE_" + str(m.type).to_upper())
		_add_monster_button(str(m.id), txt, str(m.id))


func _add_monster_button(mid: String, text: String, _tag: String) -> void:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.tooltip_text = text.replace("\n", " · ")             # carta a due righe: il nome intero sta nel tooltip
	b.custom_minimum_size = Vector2(TARGET_W, TARGET_H)
	b.toggle_mode = true
	b.button_group = _monster_group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.button_pressed = mid == _monster_id
	if not mid.is_empty():
		var mdef: Dictionary = DataRegistry.get_def("monsters", mid)
		if not (mdef.get("mechanics", []) as Array).is_empty():
			# CORSA (resoconto 91): la Preparazione si legge PRIMA dello scontro, sul pulsante del boss
			b.mouse_entered.connect(func() -> void:
				b.tooltip_text = text.replace("\n", " · ") + "\n" + _mechanics_text(mdef) + "\n" + _mechanics_tip(mdef))
	b.pressed.connect(func() -> void:
		_monster_id = mid
		if _combat.in_combat() and not _combat.in_dungeon():
			_combat.start(_zone_id, _monster_id))
	_monster_list.add_child(b)


func _on_start_pressed() -> void:
	if _combat.in_combat():
		_combat.stop()
	elif bool(_combat.readiness().unprepared):
		_ask_unprepared()          # Q97: avviso chiaro prima di combattere impreparati (si può comunque andare)
		return
	else:
		_combat.start(_zone_id, _monster_id)
	refresh()


func _start_anyway() -> void:
	_combat.start(_zone_id, _monster_id)
	refresh()


func _ask_unprepared() -> void:
	if _prep_dlg == null:
		_prep_dlg = ConfirmationDialog.new()
		_prep_dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_prep_dlg.dialog_autowrap = true
		_prep_dlg.min_size = Vector2i(460, 0)
		_prep_dlg.confirmed.connect(_start_anyway)
		_prep_dlg.get_cancel_button().pressed.connect(_open_hero)       # «Mi preparo»: si va dove ci si prepara
		add_child(_prep_dlg)
	_prep_dlg.title = tr("UI_Q97_PREP_TITLE")
	_prep_dlg.ok_button_text = tr("UI_Q97_PREP_GO")
	_prep_dlg.cancel_button_text = tr("UI_Q97_PREP_WAIT")
	_prep_dlg.dialog_text = _prep_text(_combat.readiness())
	_prep_dlg.popup_centered()


## Testo dell'avviso: elenca cosa manca (arma, armatura, cibo) e dove rimediare.
func _prep_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for m in r.missing:
		parts.append(tr("UI_Q97_MISSING_" + str(m).to_upper()))
	return Loc.tf("UI_Q97_PREP_BODY", {"list": ", ".join(parts)})


func _refresh_prep() -> void:
	var r: Dictionary = _combat.readiness()
	var warn: bool = bool(r.unprepared) and not _combat.in_combat()
	_prep_lbl.visible = warn
	var hero := _hero_target()
	_prep_go.visible = warn and not hero.is_empty()
	if warn:
		_prep_lbl.text = _prep_text(r)
		if not hero.is_empty():
			_prep_go.text = QuestGuide.go_label(hero)


## Schermata Eroe se è già aperta (si indossa l'equipaggiamento e si assegna il cibo lì), altrimenti {}.
func _hero_target() -> Dictionary:
	var e := ScreenRegistry.get_entry("hero")
	if e.is_empty() or not ScreenRegistry.is_available(e, GameState.data.get("unlocks", [])):
		return {}
	return {"screen": "hero", "params": {}, "hint": "UI_QG_HINT_GO"}


func _open_hero() -> void:
	if not _hero_target().is_empty():
		EventBus.screen_requested.emit("hero", {})


## D17: la frase «a cosa serve» compare alla prima visita (poi la richiama il «?» della testata).
func _show_intro_once() -> void:
	var seen: Array = Settings.get_value("seen_intro")
	if seen.has(INTRO_ID):
		return
	_help_btn.set_pressed(true)
	seen = seen.duplicate()
	seen.append(INTRO_ID)
	Settings.set_value("seen_intro", seen)


## Altezza dell'arena e sfondo della zona.
func _apply_band() -> void:
	_zone_banner.visible = _banner_has                    # l'arena è a tutta larghezza: lo sfondo resta anche in banda stretta
	var h := clampf(get_viewport_rect().size.y * ARENA_H_FRAC, ARENA_H_MIN, ARENA_H_MAX)
	if absf(h - _arena_h) > 0.5 and _stage != null:
		_arena_h = h
		_stage.custom_minimum_size.y = h


# ------------------------------------------------------------------ aggiornamento (≤ 10 Hz)

func refresh() -> void:
	if _combat == null:
		return
	_fx_budget = 6
	if _fallback_on != null and _fallback_on.button_pressed != _combat.safe_fallback():
		_fallback_on.set_pressed_no_signal(_combat.safe_fallback())
	var fighting := _combat.in_combat()
	if fighting and not _was_fighting:
		_hits.clear()
		_last_hit = 0.0
		_max_hit = 0.0
	_was_fighting = fighting
	_apply_band()
	_start_btn.text = tr("UI_COMBAT_STOP") if fighting else tr("UI_COMBAT_START")
	_start_btn.disabled = not fighting and _zone_id.is_empty()
	var st := _combat.hero_stats()
	_hero_style = str(st.get("style", "melee"))
	var cls_id := str(_combat.state.get("class", "warrior"))
	_hero_name.text = Loc.t(DataRegistry.get_def("classes", cls_id).get("name", ""))
	var htex := IconLib.portrait("classes", cls_id)
	if htex != _hero_sprite.texture:
		_hero_sprite.texture = htex
		_fit_sprites()
	CombatUi.set_bar(_hero_bar, float(_combat.hp()) / maxf(1.0, float(st.hp)))
	_hero_hp.text = "%s / %s" % [NumberFormat.fmt(floorf(_combat.hp())), NumberFormat.fmt(float(st.hp))]
	_wounded.text = Loc.tf("UI_COMBAT_WOUNDED", {"time": NumberFormat.fmt_time(float(_combat.state.wounded_s))}) \
		if float(_combat.state.wounded_s) > 0.0 else ""
	_refresh_resource()
	_refresh_abilities()
	_refresh_enemy(fighting)
	_refresh_dungeon()
	_refresh_safety()
	_refresh_prep()
	_refresh_c3(fighting)
	_consume_log()
	_refresh_hits(fighting)
	_refresh_sections()
	_drops_label.text = "\n".join(_drops) if not _drops.is_empty() else tr("UI_COMBAT_NO_DROPS")
	_log.text = "\n".join(CombatUi.filter_lines(_log_lines, _log_cats, str(Settings.get_value("combat_log_filter"))))
	var kills := 0
	if _monster_id.is_empty():
		for m in _combat.monsters_of(_zone_id):
			kills += _combat.kills_of(str(m.id))
	else:
		kills = _combat.kills_of(_monster_id)
	_kills.text = Loc.tf("UI_COMBAT_KILLS", {"n": NumberFormat.fmt(kills)})
	for l in [_hero_hits, _buffs_label, _wounded, _enemy_mechs, _enemy_state]:      # una nota vuota non occupa una riga
		(l as Label).visible = not (l as Label).text.is_empty()


## Colpo / massimo / DPS: misurati dai colpi del registro (ultimi DPS_WINDOW_S secondi), non calcolati qui.
func _note_damage(v: float) -> void:
	_last_hit = v
	_max_hit = maxf(_max_hit, v)
	_hits.append([Time.get_ticks_msec() / 1000.0, v])
	if _hits.size() > 200:
		_hits = _hits.slice(_hits.size() - 200)


func _refresh_hits(fighting: bool) -> void:
	if not fighting or _max_hit <= 0.0:
		_hero_hits.text = ""
		return
	var now := Time.get_ticks_msec() / 1000.0
	var total := 0.0
	var first := now
	for h in _hits:
		if now - float(h[0]) <= DPS_WINDOW_S:
			total += float(h[1])
			first = minf(first, float(h[0]))
	var span := clampf(now - first, 1.0, DPS_WINDOW_S)
	_hero_hits.text = Loc.tf("UI_F8_HITS", {"last": NumberFormat.fmt(roundf(_last_hit)), "max": NumberFormat.fmt(roundf(_max_hit)),
		"dps": NumberFormat.fmt(roundf(total / span))})


func _refresh_resource() -> void:
	var info := _combat.resource_info()
	if str(info.id).is_empty():
		_res_label.text = ""
		_res_bar.visible = false
		return
	_res_bar.visible = true
	var rd: Dictionary = DataRegistry.get_def("resources", str(info.id))
	CombatUi.set_bar_color(_res_bar, CombatUi.COL_RES.get(str(info.id), Color("5b8def")))
	CombatUi.set_bar(_res_bar, float(info.cur) / maxf(1.0, float(info.max)))
	_res_label.text = "%s  %d / %d" % [Loc.t(rd.get("name", "")), int(floor(float(info.cur))), int(floor(float(info.max)))]


## Barra delle tecniche: una casella per tecnica equipaggiata con icona, costo e ricarica che si svuota.
func _refresh_abilities() -> void:
	var equipped := _combat.build.abilities_equipped()
	var sig := ""
	for ab in equipped:
		sig += str(ab.id) + ","
	if sig != _abil_sig:
		_abil_sig = sig
		_rebuild_abilities(equipped)
	var status := _combat.ability_status()
	var res := float(_combat.state.rt.res)
	for ab in equipped:
		var slot: Dictionary = _slots.get(str(ab.id), {})
		if slot.is_empty():
			continue
		var cd := float(status.cd.get(str(ab.id), 0.0))
		var total := maxf(0.1, float(ab.cooldown_s))
		(slot.cd_bar as ProgressBar).value = cd / total
		var is_ready := cd <= 0.0 and res >= float(ab.cost)
		var lbl := slot.cd_label as Label
		if cd > 0.0:
			lbl.text = CombatUi.secs_text(cd)
			lbl.remove_theme_color_override("font_color")
		elif is_ready:
			lbl.text = tr("UI_C3_READY")
			lbl.add_theme_color_override("font_color", CombatUi.COL_HEAL)
		else:
			lbl.text = tr("UI_C3_NO_RES")
			lbl.add_theme_color_override("font_color", CombatUi.COL_WARN)
		if is_ready != bool(slot.ready):
			slot["ready"] = is_ready
			CombatUi.glow(slot.panel as CanvasItem, is_ready and _combat.in_combat())
	_abil_hint.text = tr("UI_C2_NO_ABILITIES") if equipped.is_empty() else _next_ability_text(equipped, status, res)
	# effetti attivi (potenziamenti, evocazioni, scudo)
	var parts: PackedStringArray = []
	for bid in status.buffs:
		var ab: Dictionary = DataRegistry.get_def("abilities", str(bid))
		parts.append("%s %s" % [Loc.t(ab.get("name", str(bid))), NumberFormat.fmt_time(float(status.buffs[bid].left))])
	for sid in status.summons:
		var ab2: Dictionary = DataRegistry.get_def("abilities", str(sid))
		parts.append("%s %s" % [Loc.t(ab2.get("name", str(sid))), NumberFormat.fmt_time(float(status.summons[sid].left))])
	if float(status.shield) > 0.0:
		parts.append(Loc.tf("UI_C2_STATUS_SHIELD_N", {"n": NumberFormat.fmt(float(status.shield))}))
	var pot: Dictionary = _combat.active_potion()
	if not pot.is_empty():
		parts.append(Loc.tf("UI_C2_POTION_ACTIVE", {"name": Loc.t(DataRegistry.item(str(pot.def)).get("name", "")), "n": int(pot.charges)}))
	_buffs_label.text = ", ".join(parts)


func _rebuild_abilities(equipped: Array) -> void:
	CombatUi.clear_children(_abil_row)
	_slots.clear()
	for ab in equipped:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(ABIL_W, 0)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var icon := TextureRect.new()                 # icona 32×32 a scala 2× esatta (D-6)
		icon.texture = IconLib.icon("abilities", str(ab.id))
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		var nm := CombatUi.text_label("MutedLabel")
		nm.text = "%d. %s" % [equipped.find(ab) + 1, Loc.t(ab.name)]      # numero = priorità: la prima pronta parte
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(nm)
		var cdb := CombatUi.bar(Color(0, 0, 0, 0.55), 8.0)
		cdb.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		cdb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cdb)
		var cdl := CombatUi.text_label("MonoLabel")
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cdl)
		panel.tooltip_text = Loc.tf("UI_C2_ABILITY_TIP", {"desc": Loc.t(ab.desc), "cost": int(ab.cost), "cd": int(ab.cooldown_s)}) \
			+ "\n" + tr("UI_C3_PRIORITY_TIP")
		_abil_row.add_child(panel)
		_slots[str(ab.id)] = {"panel": panel, "cd_bar": cdb, "cd_label": cdl, "ready": false}


func _refresh_enemy(fighting: bool) -> void:
	var a: Dictionary = GameState.data.get("activity", {})
	var e: Dictionary = a.get("enemy", {}) if fighting else {}
	if float(a.get("revive_s", 0.0)) > 0.0 and fighting:
		_status.text = Loc.tf("UI_COMBAT_DEAD", {"time": NumberFormat.fmt_time(float(a.revive_s))})
	elif not fighting:
		_status.text = tr("UI_COMBAT_IDLE")
	else:
		_status.text = ""                      # in combattimento niente battuta fissa (F8)
	_status.visible = not _status.text.is_empty()
	if e.is_empty():
		var shown := _monster_id if not _monster_id.is_empty() else ""
		if fighting and not str(a.get("monster", "")).is_empty():
			shown = str(a.monster)
		_portrait.texture = IconLib.portrait("monsters", shown) if not shown.is_empty() else null
		_fit_sprites()
		_enemy_name.text = Loc.t(DataRegistry.get_def("monsters", shown).get("name", "")) if not shown.is_empty() else tr("UI_COMBAT_RANDOM")
		_rest_hint.visible = shown.is_empty()
		_enemy_mechs.text = ""
		_enemy_state.text = ""
		CombatUi.set_bar(_enemy_bar, 1.0 if fighting else 0.0)
		_enemy_hp.text = ""
		_shown_enemy = ""
		return
	var mon: Dictionary = _combat._enemy_mon(a)
	var mx: float = maxf(1.0, float(e.get("max", 1.0)))
	_rest_hint.visible = false
	var ptex := IconLib.portrait("monsters", str(mon.id))
	if ptex != _portrait.texture:
		_portrait.texture = ptex
		_fit_sprites()
	var nm := "%s  (%s %d)" % [Loc.t(mon.name), tr("UI_COMBAT_LV"), int(mon.level)]
	if bool(e.get("wanted", false)):
		nm += "  [%s]" % tr("UI_C2_WANTED")
	_enemy_name.text = nm
	if _shown_enemy != str(mon.id):
		_shown_enemy = str(mon.id)
		_enemy_mechs.text = _mechanics_text(mon)
		_enemy_mechs.tooltip_text = _mechanics_tip(mon)
	CombatUi.set_bar(_enemy_bar, float(e.hp) / mx)
	_enemy_hp.text = "%s / %s" % [NumberFormat.fmt(ceilf(maxf(0.0, float(e.hp)))), NumberFormat.fmt(mx)]
	var st: PackedStringArray = []
	if float(e.get("shield_s", 0.0)) > 0.0:
		st.append(tr("UI_C2_STATUS_SHIELD"))
	if float(e.get("poison_s", 0.0)) > 0.0:
		st.append(tr("UI_C2_STATUS_POISON"))
	var alive := 0
	for ad in e.get("adds", []):
		if float(ad.hp) > 0.0:
			alive += 1
	if alive > 0:
		st.append(Loc.tf("UI_C2_STATUS_ADDS", {"n": alive}))
	if float(e.get("slow_s", 0.0)) > 0.0:
		st.append(tr("UI_C2_STATUS_SLOW"))
	for did in e.get("dots", {}):
		st.append(tr("UI_C2_STATUS_DOT"))
		break
	_enemy_state.text = ", ".join(st)


func _mechanics_text(mon: Dictionary) -> String:
	var names: PackedStringArray = []
	var mech: Dictionary = _combat.mechanics()
	for mid in mon.get("mechanics", []):
		names.append(Loc.t(mech.get(str(mid), {}).get("name", str(mid))))
	if names.is_empty():
		return ""
	var txt := tr("UI_C2_MECHS") + ": " + ", ".join(names)
	var ans: Array = _combat.boss_answers(mon)           # CORSA (resoconto 91): Preparazione dei boss
	if not ans.is_empty():
		var ok := 0
		for an in ans:
			ok += 1 if bool(an.ready) else 0
		txt += " · " + Loc.tf("UI_PREP_SUMMARY", {"n": ok, "t": ans.size()})
	return txt


func _mechanics_tip(mon: Dictionary) -> String:
	var lines: PackedStringArray = []
	var mech: Dictionary = _combat.mechanics()
	var ans := {}
	for an in _combat.boss_answers(mon):
		ans[str(an.id)] = an
	for mid in mon.get("mechanics", []):
		var m: Dictionary = mech.get(str(mid), {})
		lines.append("%s: %s" % [Loc.t(m.get("name", "")), Loc.t(m.get("desc", ""))])
		if ans.has(str(mid)):
			var an2: Dictionary = ans[str(mid)]
			lines.append("   " + Loc.tf("UI_PREP_ANS_" + str(an2.kind).to_upper(), {"v": NumberFormat.fmt(roundf(float(an2.value))),
				"min": NumberFormat.fmt(float(an2.need))}) + " — " + tr("UI_PREP_READY" if bool(an2.ready) else "UI_PREP_MISSING"))
	return "\n".join(lines)


func _refresh_dungeon() -> void:
	var p := _combat.dungeon_progress()
	_wave_row.visible = not p.is_empty()
	_dungeon_btn.disabled = false
	if p.is_empty():
		return
	var d := _combat.dungeon_def(str(p.id))
	_wave_label.text = Loc.tf("UI_C2_DUNGEON_WAVE", {"name": Loc.t(d.name), "n": int(p.wave) + 1, "total": int(p.total)})
	CombatUi.set_bar(_wave_bar, float(p.wave) / maxf(1.0, float(p.total)), 0.25)


func _refresh_safety() -> void:
	var mid := _monster_id
	if mid.is_empty():
		var normals := _combat.monsters_of(_zone_id)
		mid = str(normals[0].id) if not normals.is_empty() else ""
		for m in normals:
			if str(m.type) == "normal":
				mid = str(m.id)       # il più forte dei normali: criterio prudente
	_food_panel.target_monster = "" if _combat.in_dungeon() else mid
	_food_panel.refresh()
	if mid.is_empty() or _combat.in_dungeon():
		_set_chip("", "", "")
		return
	var s := _combat.idle_safety(mid)
	if s.is_empty():
		_set_chip("", "", "")
		return
	var lvl := str(s.level)
	var hours: String = tr("UI_COMBAT_FOOD_INF") if float(s.food_hours) < 0.0 else NumberFormat.fmt_time(float(s.food_hours) * 3600.0)
	var tip := Loc.tf("UI_COMBAT_SAFE_TIP", {"hit": NumberFormat.fmt(float(s.worst_hit)),
		"thr": NumberFormat.fmt(float(s.threshold_hp)), "food": hours})
	match lvl:
		"green":
			_set_chip("ok", "✓ " + tr("UI_COMBAT_SAFE_GREEN"), tip)
		"yellow":
			_set_chip("warn", "⚠ " + tr("UI_COMBAT_SAFE_YELLOW"), tip)
		_:
			if str(s.get("reason", "")) == "food":
				_set_chip("warn", "⚠ " + tr("UI_COMBAT_SAFE_RED_FOOD"), tip)
			else:
				_set_chip("bad", "✗ " + tr("UI_F8_RISK_BAD"), tip)


## Il chip di rischio UNICO della testata (D18/§2.4). kind: "" nascosto · "ok" · "warn" · "bad". Colori e contrasto: UiKit.RISK_*.
func _set_chip(kind: String, text: String, tip: String) -> void:
	var sig := kind + "|" + text + "|" + tip
	if sig == _chip_sig:
		return
	_chip_sig = sig
	_risk_chip.visible = not kind.is_empty()
	if kind.is_empty():
		_safety.text = ""
		return
	var bg: Color = UiKit.RISK_OK
	var fg: Color = UiKit.RISK_OK_TEXT
	if kind == "warn":
		bg = UiKit.RISK_WARN
		fg = UiKit.RISK_WARN_TEXT
	elif kind == "bad":
		bg = UiKit.RISK_BAD
		fg = UiKit.RISK_BAD_TEXT
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_risk_chip.add_theme_stylebox_override("panel", sb)
	_safety.add_theme_color_override("font_color", fg)
	_safety.text = text
	_risk_chip.tooltip_text = tip


# ------------------------------------------------------------------ registro ed effetti

func _consume_log() -> void:
	for e in _combat.log_since(_last_log_id):
		_last_log_id = int(e.id)
		match str(e.k):
			"hit":
				_note_damage(float(e.v))
				_fx_hit(float(e.v), bool(e.crit))
				_add_line("[color=#c9c4b4]" + Loc.tf("UI_COMBAT_LOG_HIT" if not e.crit else "UI_COMBAT_LOG_CRIT",
					{"n": NumberFormat.fmt(roundf(float(e.v)))}) + "[/color]")
			"ahit":
				_note_damage(float(e.v))
				var ac := _enemy_center()
				Fx.number(ac + Vector2(randf_range(-30.0, 30.0), -50.0), NumberFormat.fmt(roundf(float(e.v))) + ("!" if e.crit else ""),
					CombatUi.COL_ABILITY, Fx.NUM_L if e.crit else Fx.NUM_M, 56.0, 1.0, 1 if e.crit else 0, 0.0, _arena_rect())
				if _fx_budget > 0:
					_fx_budget -= 1
					Fx.hit(ac, bool(e.crit), CombatUi.COL_ABILITY)
				Fx.strike(_cast_style if not _cast_style.is_empty() else _hero_style, _hero_center(), ac, CombatUi.COL_ABILITY, true)
				Fx.hit_flash(_portrait, bool(e.crit))
				Fx.impact(_portrait, FxJuice.dir(_hero_center(), ac), 13.0 if bool(e.crit) else 9.0, 9.0, 0.22)
			"dot":
				var dc := _enemy_center()
				Fx.number(dc + Vector2(randf_range(-30.0, 30.0), -34.0), NumberFormat.fmt(roundf(float(e.v))), CombatUi.COL_DOT, Fx.NUM_S, 32.0, 0.7, 0, 0.0, _arena_rect())
				if _fx_budget > 0:
					_fx_budget -= 1
					Fx.burst("smoke", dc + Vector2(0, 20), [FxPalette.GREEN_D, CombatUi.COL_DOT], 0.6, 0.5, Vector2(18, 4))
			"cast":
				var ab: Dictionary = DataRegistry.get_def("abilities", str(e.ab))
				_add_line("[color=#7fc8ff]" + Loc.tf("UI_C2_LOG_CAST", {"name": Loc.t(ab.get("name", str(e.ab)))}) + "[/color]")
				var slot: Dictionary = _slots.get(str(e.ab), {})
				if not slot.is_empty():
					CombatUi.pop(slot.panel as Control, 1.12)
				var cdef: Dictionary = DataRegistry.get_def("classes", str(ab.get("class", "")))
				_cast_style = str(cdef.get("style", "")) if cdef.has("style") and cdef.style != null else _hero_style
				_fx_cast(str(ab.get("effect", {}).get("type", "")), slot)
			"miss":
				Fx.number(_enemy_center() + Vector2(randf_range(-30.0, 30.0), -50.0), tr("UI_COMBAT_MISS"), CombatUi.COL_HIT, Fx.NUM_S, 36.0, 0.8, 0, 0.0, _arena_rect())
			"mhit":
				_fx_hurt(float(e.v))
				CombatUi.flash(_hero_box, Color(1.3, 0.8, 0.8), 0.2)
				CombatUi.pop(_hero_box, 1.02, 0.12)
				_add_line("[color=#d9a09a]" + Loc.tf("UI_COMBAT_LOG_MHIT", {"n": NumberFormat.fmt(roundf(float(e.v)))}) + "[/color]")
			"mmiss":
				var hc := _hero_center()
				Fx.number(hc + Vector2(randf_range(-20.0, 20.0), -30.0), tr("UI_COMBAT_DODGE"), FxPalette.BLUE, Fx.NUM_M, 36.0, 0.8, 0, 0.0, _arena_rect())
				if _fx_budget > 0:
					_fx_budget -= 1
					Fx.burst("dust", hc + Vector2(0, 28), [], 0.7, 0.7, Vector2(20, 3))
			"heavy":
				_banner_text(tr("UI_C2_LOG_MECH_HEAVY"))
				_add_line("[color=#e0b640]" + tr("UI_COMBAT_LOG_HEAVY") + "[/color]", "boss")
				_fx_boss(FxPalette.AMBER, 7.0)
			"mech":
				var key: String = CombatUi.MECH_LOG.get(str(e.m), "")
				if not key.is_empty():
					_banner_text(tr(key))
					_add_line("[color=#e0b640]" + tr(key) + "[/color]", "boss")
					_fx_boss(FxPalette.ORANGE if str(e.m) != "shield_phase" else FxPalette.BLUE, 5.0)
			"phase":
				_fx_boss(FxPalette.ORANGE, 10.0, true)
			"eat":
				var ec := _hero_center()
				Fx.number(ec + Vector2(randf_range(-20.0, 20.0), -30.0), "+" + NumberFormat.fmt(roundf(float(e.v))), CombatUi.COL_HEAL, Fx.NUM_M, 40.0, 0.9, 0, 0.0, _arena_rect())
				Fx.burst("heal", ec + Vector2(0, 20), [], 0.8, 0.8, Vector2(24, 4))
				_add_line("[color=#7fcf8a]" + Loc.tf("UI_COMBAT_LOG_EAT", {"n": NumberFormat.fmt(roundf(float(e.v)))}) + "[/color]")
			"kill":
				_on_kill_line(e)
				_fx_kill(e)
			"die":
				_add_line("[color=#d9544d]" + tr("UI_COMBAT_LOG_DIE") + "[/color]")
				CombatUi.pop(_hero_box, 1.06, 0.3)
				Fx.vignette(_hero_box.get_global_rect(), FxPalette.RED, 1.0, 8.0, 0.8)
				Fx.burst("shard", _hero_center(), [FxPalette.RED, FxPalette.RED_L, FxPalette.STONE], 0.9, 0.8, Vector2(30, 20), 1)
				_show_summary(e.get("fight", {}), true)
			"stance":
				var sty_name: String = tr("UI_RAID_STYLE_" + str(e.style).to_upper())
				_banner_text(Loc.tf("UI_C3_STANCE_BANNER", {"style": sty_name}))
				_add_line("[color=#7fc8ff]" + Loc.tf("UI_C3_STANCE_LOG", {"style": sty_name}) + "[/color]")
				CombatUi.pop(_stance_lbl, 1.12, 0.25)
			"phase":
				_add_line("[color=#e0b640]" + Loc.tf("UI_RAID_PHASE_BANNER", {"n": int(e.i) + 1,
					"style": tr("UI_RAID_STYLE_" + str(e.style).to_upper())}) + "[/color]", "boss")
			"trial_nofood":
				_add_line("[color=#e0b640]" + tr("UI_C3_TRIAL_NOFOOD_LOG") + "[/color]")
			"ambush":
				var ar: Dictionary = _combat.ambush_rules()
				var am: Dictionary = DataRegistry.get_def("monsters", str(e.m))
				_banner_text(tr("UI_FIXC_AMBUSH_BANNER"))
				_add_line("[color=#e0b640]" + Loc.tf("UI_FIXC_AMBUSH_LOG", {"name": Loc.t(am.get("name", e.m)),
					"hp": NumberFormat.fmt(float(ar.get("hp_mult", 1.0))), "reward": NumberFormat.fmt(float(ar.get("reward_mult", 1.0)))}) + "[/color]")
			"ambush_fled":
				_add_line("[color=#9a968c]" + tr("UI_FIXC_AMBUSH_FLED") + "[/color]")
			"champion":
				var cm: Dictionary = DataRegistry.get_def("monsters", str(e.m))
				_banner_text(tr("UI_RUN_BANNER_CHAMPION"))
				_add_line("[color=#e0b640]" + Loc.tf("UI_RUN_LOG_CHAMPION", {"name": Loc.t(cm.get("name", e.m))}) + "[/color]", "boss")
			"champion_won":
				_add_line("[color=#e0b640]" + tr("UI_RUN_LOG_CHAMPION_WON") + "[/color]", "boss")
			"champion_fled":
				_add_line("[color=#9a968c]" + tr("UI_RUN_LOG_CHAMPION_FLED") + "[/color]")
			"revive":
				_add_line("[color=#9a968c]" + tr("UI_COMBAT_LOG_REVIVE") + "[/color]")
			"revive_once":
				_banner_text(tr("UI_C2_LOG_REVIVE_ONCE"))
				_add_line("[color=#7fcf8a]" + tr("UI_C2_LOG_REVIVE_ONCE") + "[/color]")
				Fx.ring(_hero_center(), CombatUi.COL_HEAL, 90.0, 0.7, FxPalette.WHITE, 1)
				Fx.burst("heal", _hero_center(), [], 1.2, 1.4, Vector2(30, 6), 1)
			"dungeon_done":
				var dd: Dictionary = _combat.dungeon_def(str(e.d))
				_banner_text(tr("UI_C2_DUNGEON_CLEARED"))
				_summary_lbl.text = CombatUi.run_text(e.get("run", {}), Loc.t(dd.get("name", "")))
				_summary_title.text = tr("UI_C3_SUMMARY_RUN")
				CombatUi.pop(_summary_lbl, 1.06, 0.4)
				CombatUi.flash(_summary_lbl, Color(1.4, 1.3, 0.8), 0.6)
				_add_line("[color=#e0b640]" + Loc.tf("UI_C2_LOG_DUNGEON_DONE", {"name": Loc.t(dd.get("name", "")),
					"gold": NumberFormat.fmt(float(e.gold))}) + "[/color]", "boss")
				Fx.banner(tr("UI_C2_DUNGEON_CLEARED"), Loc.t(dd.get("name", "")), FxPalette.GOLD)
				Fx.confetti(Rect2(get_global_rect().position + Vector2(size.x * 0.2, 0), Vector2(size.x * 0.6, 8)), 2)
				Fx.coins(_enemy_center(), Fx.anchor_pos("gold", _enemy_center()), 6)
			"dungeon_failed":
				_banner_text(tr("UI_C2_DUNGEON_FAILED"))
				_add_line("[color=#d9544d]" + tr("UI_C2_LOG_DUNGEON_FAIL") + "[/color]", "boss")
				Fx.vignette(get_global_rect(), FxPalette.RED, 0.8, 8.0, 0.7)
			"offline":
				_add_line("[color=#9a968c]" + Loc.tf("UI_COMBAT_LOG_OFFLINE", {"n": NumberFormat.fmt(int(e.kills))}) + "[/color]")


# ------------------------------------------------------------------ effetti visivi (Fx): solo presentazione

## Rettangolo globale dell'arena (palco del mostro + riquadro dell'eroe): i numeri fluttuanti restano qui dentro.
## Senza arena ancora costruita: nessun confine (rettangolo vuoto).
func _arena_rect() -> Rect2:
	if _stage == null or not is_instance_valid(_stage) or not _stage.is_inside_tree():
		return Rect2()
	var r := _stage.get_global_rect()
	if _hero_box != null and is_instance_valid(_hero_box) and _hero_box.is_inside_tree():
		r = r.merge(_hero_box.get_global_rect())
	return r


func _enemy_center() -> Vector2:
	return Fx.center_of(_portrait) if _portrait != null and _portrait.is_inside_tree() else Vector2(400, 200)


# ------------------------------------------------------------------ COMBAT-3: riepilogo, avvisi, cibo, postura

func _show_summary(f: Dictionary, big: bool) -> void:
	_summary_title.text = tr("UI_C3_SUMMARY")
	_summary_lbl.text = CombatUi.fight_text(f)
	if big:
		CombatUi.pop(_summary_lbl, 1.05, 0.3)
		CombatUi.flash(_summary_lbl, Color(1.35, 1.25, 0.8), 0.5)


## «Prossima tecnica»: la prima pronta nella lista di priorità (è quella che parte al prossimo attacco).
func _next_ability_text(equipped: Array, status: Dictionary, res: float) -> String:
	if not _combat.in_combat():
		return ""
	for ab in equipped:
		if float(status.cd.get(str(ab.id), 0.0)) <= 0.0 and res >= float(ab.cost):
			return Loc.tf("UI_C3_NEXT_ABILITY", {"name": Loc.t(ab.name)})
	return tr("UI_C3_NEXT_WAIT")


func _enemy_style(a: Dictionary, e: Dictionary) -> String:
	if e.is_empty():
		return ""
	var mon: Dictionary = _combat._enemy_mon(a)
	var phases: Variant = mon.get("phases")
	if phases is Array and (phases as Array).size() > 1:
		return str(((phases as Array)[clampi(int(e.get("phase", 0)), 0, (phases as Array).size() - 1)] as Dictionary).style)
	return str(mon.get("style", ""))


func _refresh_c3(fighting: bool) -> void:
	var a: Dictionary = GameState.data.get("activity", {})
	var e: Dictionary = a.get("enemy", {}) if fighting else {}
	_refresh_stance(a, e)
	_refresh_food(fighting)
	_refresh_threats(fighting)
	_refresh_trial()
	_refresh_relics()


func _refresh_stance(a: Dictionary, e: Dictionary) -> void:
	var cd := _combat.class_def()
	_stance_lbl.visible = bool(cd.get("hybrid", false))
	if not _stance_lbl.visible:
		return
	var sty := str(_combat.hero_stats().style)
	var ms := _enemy_style(a, e)
	var edge := "EVEN"
	if not ms.is_empty():
		var tm := Formulas.triangle_mult(sty, ms)
		edge = "ADV" if tm > 1.0 else ("DIS" if tm < 1.0 else "EVEN")
	_stance_lbl.text = Loc.tf("UI_C3_STANCE", {"style": tr("UI_RAID_STYLE_" + sty.to_upper()), "edge": tr("UI_C3_EDGE_" + edge)})


func _refresh_food(fighting: bool) -> void:
	var fi := _combat.food_info()
	if bool(fi.blocked):
		_food_lbl.text = tr("UI_C3_FOOD_BLOCKED")
	elif int(fi.count) <= 0:
		_food_lbl.text = tr("UI_C3_FOOD_NONE")
	else:
		_food_lbl.text = Loc.tf("UI_C3_FOOD", {"n": NumberFormat.fmt(int(fi.count)),
			"name": Loc.t(DataRegistry.item(str(fi.def)).get("name", "")), "heal": NumberFormat.fmt(floorf(float(fi.heal))),
			"thr": int(round(float(fi.threshold_pct)))})
	_thr_mark.visible = true
	_thr_mark.size = Vector2(2, _hero_bar.size.y)
	_thr_mark.position = Vector2(_hero_bar.size.x * float(fi.threshold_pct) / 100.0 - 1.0, 0.0)
	var danger := _combat.danger_level() if fighting else ""
	if danger == _danger_state:
		return
	_danger_state = danger
	_danger_lbl.visible = not danger.is_empty()
	if danger.is_empty():
		CombatUi.glow(_danger_lbl, false)
		return
	_danger_lbl.text = tr("UI_C3_DANGER_" + danger.to_upper())
	_danger_lbl.add_theme_color_override("font_color", CombatUi.COL_HURT if danger == "critical" else CombatUi.COL_WARN)
	CombatUi.pop(_danger_lbl, 1.1, 0.3)
	CombatUi.glow(_danger_lbl, danger == "critical")


func _refresh_threats(fighting: bool) -> void:
	var lines: PackedStringArray = []
	var worst := 1e9
	var worst_id := ""
	if fighting:
		var mech: Dictionary = _combat.mechanics()
		for t in _combat.threats():
			var nm := Loc.t((mech.get(str(t.id), {}) as Dictionary).get("name", str(t.id)))
			if str(t.kind) == "timer":
				if float(t.in_s) <= CombatUi.THREAT_WARN_S:
					lines.append(Loc.tf("UI_C3_THREAT_TIMER", {"name": nm, "s": CombatUi.secs_text(float(t.in_s))}))
					if float(t.in_s) < worst:
						worst = float(t.in_s)
						worst_id = str(t.id)
			elif bool(t.get("active", false)):
				lines.append(Loc.tf("UI_C3_THREAT_ENRAGE", {"name": nm}))
	_threat_lbl.visible = not lines.is_empty()
	_threat_lbl.text = "\n".join(lines)
	var imminent := worst <= CombatUi.THREAT_NOW_S
	_threat_lbl.add_theme_color_override("font_color", CombatUi.COL_HURT if imminent else CombatUi.COL_WARN)
	var key := worst_id if imminent else ""
	if key != _threat_pop:
		_threat_pop = key
		if imminent:
			CombatUi.pop(_threat_lbl, 1.12, 0.25)
			CombatUi.shake(_portrait, 4.0, 0.2)


func _refresh_trial() -> void:
	var ts := _combat.trial_status()
	_trial_lbl.visible = not ts.is_empty()
	if ts.is_empty():
		return
	var pr: Variant = Game.system("prestige")
	var tdef: Dictionary = pr.trial_def(str(ts.id)) if pr != null else {}
	var txt := Loc.tf("UI_C3_TRIAL", {"name": Loc.t(tdef.get("name", {})), "tier": int(ts.tier)})
	var rules: PackedStringArray = []
	for r in ts.rules:
		rules.append(Loc.tf(str(r.key), r.params))
	if not rules.is_empty():
		txt += "  [" + ", ".join(rules) + "]"
	var left := float(ts.time_left_s)
	if left >= 0.0:
		txt += "  " + Loc.tf("UI_C3_TRIAL_TIME", {"s": CombatUi.secs_text(left)})
		_trial_lbl.add_theme_color_override("font_color", CombatUi.COL_HURT if left <= 10.0 else CombatUi.COL_WARN)
	else:
		_trial_lbl.add_theme_color_override("font_color", CombatUi.COL_WARN)
	_trial_lbl.text = txt


func _refresh_relics() -> void:
	var rel := _combat.relic_effects()
	var sig := ""
	for r in rel:
		sig += str(r.uid) + ","
	if sig == _relic_sig:
		return
	_relic_sig = sig
	_relic_lbl.visible = not rel.is_empty()
	if rel.is_empty():
		return
	var names: PackedStringArray = []
	var tips: PackedStringArray = []
	for r in rel:
		names.append(Loc.t(r.name))
		tips.append(Loc.t(r.name) + "\n" + CrateUi.mods_text(r.mods))
	_relic_lbl.text = Loc.tf("UI_C3_RELICS", {"list": ", ".join(names)})
	_relic_lbl.tooltip_text = tr("UI_C3_RELICS_TIP") + "\n\n" + "\n\n".join(tips)


func _rand_pos(x0: float = 40.0) -> Vector2:
	return Vector2(x0 + randf_range(0.0, 60.0), 40.0)


func _hero_center() -> Vector2:
	return Fx.center_of(_hero_sprite) if _hero_sprite != null and _hero_sprite.is_inside_tree() else Vector2(400, 200)


## Colpo dell'eroe: scintille + graffio, numero (grande e dorato se critico), scossa e lampo del ritratto.
func _fx_hit(v: float, crit: bool) -> void:
	var c := _enemy_center()
	var txt := NumberFormat.fmt(roundf(v)) + ("!" if crit else "")
	Fx.number(c + Vector2(randf_range(-30.0, 30.0), -50.0), txt, CombatUi.COL_CRIT if crit else CombatUi.COL_HIT,
		Fx.NUM_XL if crit else Fx.NUM_M, 58.0 if crit else 44.0, 1.1 if crit else 0.9, 1 if crit else 0, 0.0, _arena_rect())
	if _fx_budget > 0 or crit:
		_fx_budget -= 1
		Fx.hit(c + Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0)), crit, CombatUi.COL_CRIT if crit else CombatUi.COL_HIT)
	var d := FxJuice.dir(_hero_center(), c)
	Fx.strike(_hero_style, _hero_center(), c, CombatUi.COL_CRIT if crit else FxPalette.WHITE, crit)
	Fx.hit_flash(_portrait, crit)                                       # lampo bianco ~0,08 s (max 3/s)
	Fx.impact(_portrait, d, 14.0 if crit else 7.0, 9.0 if crit else 4.0, 0.24 if crit else 0.16)      # knockback + tremolio
	if crit:
		Fx.shake(_stage, 3.0, 0.2)


## Danno subito: numero rosso sopra la barra, vignetta rossa DISCRETA sul riquadro dell'eroe, piccola scossa.
func _fx_hurt(v: float) -> void:
	var hc := _hero_center()
	Fx.number(hc + Vector2(randf_range(-20.0, 20.0), -26.0), NumberFormat.fmt(roundf(v)), CombatUi.COL_HURT, Fx.NUM_M, 40.0, 0.9, 0, 0.0, _arena_rect())
	Fx.vignette(Rect2(_stage.get_global_position(), Vector2(_stage.size.x * 0.5, _stage.size.y)), FxPalette.RED, 0.55, 5.0, 0.35)      # metà sinistra del quadro: l'eroe
	var ec := _enemy_center()
	var d := FxJuice.dir(ec, _hero_center())
	var a: Dictionary = GameState.data.get("activity", {})
	var sty := _enemy_style(a, a.get("enemy", {}))
	Fx.strike(sty if not sty.is_empty() else "melee", ec, _hero_center(), FxPalette.RED_L, false)
	Fx.hit_flash(_hero_bar)
	Fx.impact(_portrait, d, 5.0, 0.0, 0.2)                              # piccolo affondo del mostro (contenuto nello stage)


## Abilità lanciata: anello e scintille del colore del suo tipo sull'eroe (o sul mostro per i malus), niente di invasivo.
func _fx_cast(effect_type: String, slot: Dictionary) -> void:
	var col := FxPalette.ability(effect_type)
	var cols: Array = [col, FxPalette.WHITE, FxPalette.lighten(col, 0.45)]
	var hc := _hero_center()
	var ec := _enemy_center()
	match effect_type:
		"damage":
			Fx.ring(ec, col, 64.0, 0.45, FxPalette.WHITE)
		"debuff", "dot":
			Fx.ring(ec, col, 56.0, 0.5, FxPalette.WHITE)
			Fx.burst("mote", ec, cols, 0.9, 0.9, Vector2(24, 24))
		"heal":
			Fx.ring(hc, col, 60.0, 0.55, FxPalette.WHITE)
			Fx.burst("heal", hc + Vector2(0, 20), cols, 1.0, 1.2, Vector2(26, 5))
		"shield":
			Fx.frame_flash(_hero_box.get_global_rect(), col, 10.0, 0.55, 0.9)
			Fx.ring(hc, col, 64.0, 0.55, FxPalette.WHITE)
		"summon":
			Fx.burst("mote", hc, cols, 1.0, 1.2, Vector2(30, 14))
			Fx.ring(hc, col, 64.0, 0.55, FxPalette.WHITE)
		_:
			Fx.ring(hc, col, 64.0, 0.55, FxPalette.WHITE)
			Fx.burst("star", hc, cols, 0.7, 0.7)
	if not slot.is_empty() and (slot.panel as Control).is_visible_in_tree():      # il dettaglio delle tecniche può essere chiuso
		Fx.glow_pulse(slot.panel as CanvasItem, col, 1, 0.3, 0.6)


## Meccanica o fase del boss: bagliore sul ritratto, scossa del palco, anello.
func _fx_boss(col: Color, px: float, big: bool = false) -> void:
	var r := _portrait.get_global_rect() if _portrait != null and _portrait.is_inside_tree() else Rect2()
	if r.size == Vector2.ZERO:
		return
	Fx.frame_flash(r, col, 20.0 if big else 14.0, 0.7, 1.0, 2)
	Fx.shake(_stage, px, 0.35 if big else 0.22)
	Fx.ring(r.get_center(), col, 100.0 if big else 70.0, 0.7, FxPalette.WHITE, 1)
	if big:
		Fx.glow(r, col, 1.6, 0.9, 5.0)
		Fx.burst("ember", r.get_center(), [], 1.2, 1.2, r.size * 0.35, 1)


## Morte del mostro: dissolvenza a blocchi + frammenti, monete e oggetti che volano verso il Deposito.
func _fx_kill(e: Dictionary) -> void:
	if Fx.level() <= 0:
		return
	var c := _enemy_center()
	var tex: Texture2D = IconLib.portrait("monsters", str(e.m))
	if _portrait.has_meta(FxShakeBehavior.META):                       # il colpo fatale non deve sfalsare la copia che si dissolve
		FxShakeBehavior.on(_portrait).stop()
	Fx.dissolve(_portrait, FxPalette.AMBER, tex)
	Fx.number(c + Vector2(0, 30), "+" + NumberFormat.fmt(float(e.gold)), FxPalette.GOLD, Fx.NUM_S, 34.0, 0.9, 0, 0.1, _arena_rect())
	var bank_pos := Fx.anchor_pos("bank", c + Vector2(-200, 0))
	var n := 0
	for it in e.items:
		if n >= 2:
			break
		n += 1
		Fx.fly(IconLib.icon("items", str(it.id)), c, bank_pos, 0.8, FxPalette.GOLD, "glint", Fx.anchor_node("bank"), 0.1 * float(n), 22.0)
	for cid in e.crates:
		Fx.fly(IconLib.icon("crates", str(cid)), c, Fx.anchor_pos("vault_hall", bank_pos), 0.9, FxPalette.VIOLET, "glint", Fx.anchor_node("vault_hall"), 0.2, 26.0, 1)
		Fx.ring(c, FxPalette.VIOLET, 80.0, 0.6, FxPalette.WHITE, 1)
	# il nuovo mostro «compare» invece di apparire di colpo
	if _portrait != null and _portrait.is_inside_tree():
		_portrait.modulate.a = 0.0
		var tw := _portrait.create_tween()
		tw.tween_interval(0.25)
		tw.tween_property(_portrait, "modulate:a", 1.0, 0.25)


func _banner_text(text: String) -> void:
	_banner.text = text
	if CombatUi.reduce() or not is_inside_tree():
		_banner.modulate.a = 1.0
		return
	_banner.modulate.a = 1.0
	var tw := _banner.create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _on_kill_line(e: Dictionary) -> void:
	var mdef: Dictionary = DataRegistry.get_def("monsters", str(e.m))
	var name_txt := Loc.t(mdef.get("name", ""))
	var big: bool = str(mdef.get("type", "normal")) != "normal"
	_show_summary(e.get("fight", {}), big)
	if big:
		_banner_text(Loc.tf("UI_C3_BOSS_DOWN", {"name": name_txt}))
	_add_line(Loc.tf("UI_COMBAT_LOG_KILL", {"name": name_txt, "xp": NumberFormat.fmt(float(e.xp)), "gold": NumberFormat.fmt(float(e.gold))}),
		"boss" if big else "")
	if bool(e.get("wanted", false)):
		_add_line("[color=#e0b640]" + tr("UI_C2_LOG_WANTED") + "[/color]", "rare")
	for it in e.items:
		var d := DataRegistry.item(str(it.id))
		var line := "%s ×%d" % [Loc.t(d.get("name", str(it.id))), int(it.qty)]
		_push_drop(line)
		if bool(d.get("unique", false)):               # un unico è sempre un drop raro (filtro del registro)
			_add_line("[color=#e0b640]" + Loc.tf("UI_UIA_LOG_RARE_DROP", {"name": line}) + "[/color]", "rare")
	for gid in e.get("gear", []):
		_push_drop(Loc.t(DataRegistry.item(str(gid)).get("name", str(gid))))
	for cid in e.crates:
		_push_drop(Loc.t(DataRegistry.item(str(cid)).get("name", str(cid))))
		_add_line("[color=#e0b640]" + Loc.tf("UI_COMBAT_LOG_CRATE", {"name": Loc.t(DataRegistry.item(str(cid)).get("name", str(cid)))}) + "[/color]", "rare")
	for pid in e.pets:
		_add_line("[color=#e0b640]" + tr("UI_COMBAT_LOG_PET") + "[/color]", "rare")


func _push_drop(line: String) -> void:
	_drops.append(line)
	if _drops.size() > DROPS_MAX:
		_drops = _drops.slice(_drops.size() - DROPS_MAX)


## Aggiunge una riga al registro. `cat` = "" (normale), "rare" (drop rari) o "boss" (eventi del boss): serve ai filtri
## del registro (UI-A G21). Con il registro disattivato nelle Impostazioni non si conserva nulla.
func _add_line(bb: String, cat: String = "") -> void:
	if not bool(Settings.get_value("combat_log")):
		return
	_log_lines.append(bb)
	_log_cats.append(cat)
	if _log_lines.size() > LOG_LINES_MAX:
		_log_lines = _log_lines.slice(_log_lines.size() - LOG_LINES_MAX)
		_log_cats = _log_cats.slice(_log_cats.size() - LOG_LINES_MAX)

