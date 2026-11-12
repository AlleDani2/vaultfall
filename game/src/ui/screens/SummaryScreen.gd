class_name SummaryScreen
extends GameScreen
## Riepilogo come cruscotto (progetto di interfaccia D22, fase F6, docs/ui_redesign/06 §3.6):
##   ADESSO (attività + barra del livello) · PROSSIMO PASSO (l'unico posto dell'obiettivo in questa schermata, con [Vai]) ·
##   DA FARE (solo se c'è qualcosa: stessa sorgente dei segnali del menù, `SidebarBadges.signals()`) · numeri chiave in una riga ·
##   sezioni richiudibili con stato ricordato (Titolo e profilo, Prossimi traguardi) · una riga con chiacchiera e Gazzetta.
## In banda larga (≥ 1440 px) Adesso, Prossimo passo e Da fare stanno sulla stessa riga di carte.
## Solo presentazione: legge i sistemi.

@onready var _mode_row: HBoxContainer = %ModeRow
@onready var _mode: Label = %ModeValue
@onready var _numbers: Label = %Numbers
@onready var _gold: Label = %GoldValue          # nascosto: l'Oro sta nella barra alta (D18); resta per i test e per chi lo legge
@onready var _milestones: VBoxContainer = %Milestones
@onready var _tip: Label = %Tip

const NEW_GAME_S := 900.0       # sotto questo tempo di gioco il Riepilogo propone «Vai a <mansione>»
const MILESTONES_OPEN_S := 7200.0   # «Prossimi traguardi» è aperto di default nelle prime 2 ore di gioco (D22)
const TODO_MAX := 5             # righe di «Da fare» mostrate: il resto è «e altri N» (revisione grafica 1.0, punto 5)
const NOW_ICON_PX := 96         # icona della mansione: PNG 32×32 a scala 3× esatta (D-6)
const FOLD_PROFILE := "summary_profile"
const FOLD_MILESTONES := "summary_milestones"

var _milestones_sig: String = ""
var _todo_sig: String = ""
var _band: String = ""
var _title_built: bool = false
var _top_row: HBoxContainer
var _now_card: PanelContainer
var _step_card: PanelContainer
var _todo_card: PanelContainer
var _todo_box: VBoxContainer
var _now_icon: TextureRect            # icona grande dell'attività (mansione o Eroe)
var _now_open: Button                 # «Apri <mansione>»
var _now_target: String = ""
var _stats_row: HBoxContainer         # tre mini-schede: livello totale · Deposito · Bonus
var _acts_row: HBoxContainer          # azioni della scheda Adesso: «Apri …» e «Bonus attivi (N)»
var _lv_big: Label
var _lv_card: Control
var _bank_big: Label
var _bank_bar: SmoothBar
var _bank_card: Control
var _todo_more: Label
var _now_l: Label                     # attività in corso
var _now_bar: ProgressBar             # avanzamento verso il prossimo livello della mansione
var _now_eta: Label
var _step_title: Label                # missione principale
var _step_obj: Label
var _step_bar: ProgressBar
var _step_num: Label
var _step_btn: Button
var _step_target: Dictionary = {}     # bersaglio del pulsante «Vai» (vuoto: apre Missioni)
var _start_btn: Button                # «Vai a <mansione>»: solo all'inizio, quando non c'è ancora nulla in corso
var _start_skill: String = ""
var _profile: ProfileCard
var _profile_fold: Button
var _bonus_btn: Button
var _city: CityStrip


func wants_scroll() -> bool:
	return true


func _ready() -> void:
	_build_dashboard()
	_build_secondary()


# ------------------------------------------------------------------ costruzione

func _card(parent: Control, header_key: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ContentPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = header_key
	v.add_child(head)
	return v


## Adesso (scheda grande con icona e barra larga) · Prossimo passo · Da fare · tre mini-schede. Sta sopra il resto: è la prima cosa
## che chi torna al gioco vuole sapere (wireframe 02_riepilogo).
func _build_dashboard() -> void:
	var at := _tip.get_index() + 1
	# ADESSO: icona 96 px · nome e tempo · barra larga · azioni
	_now_card = PanelContainer.new()
	_now_card.name = "NowCard"
	_now_card.theme_type_variation = &"ContentPanel"
	_now_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_now_card)
	move_child(_now_card, at)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 16)
	_now_card.add_child(nrow)
	_now_icon = TextureRect.new()
	_now_icon.custom_minimum_size = Vector2(NOW_ICON_PX, NOW_ICON_PX)
	_now_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_now_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_now_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_now_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(_now_icon)
	var now := VBoxContainer.new()
	now.add_theme_constant_override("separation", 6)
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(now)
	var head := Label.new()
	head.theme_type_variation = &"SectionLabel"
	head.text = "UI_UXA_NOW_TITLE"
	now.add_child(head)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	now.add_child(line)
	_now_l = _label(&"")
	_now_l.add_theme_font_size_override("font_size", UiType.NUMBER_BIG)
	_now_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_l.custom_minimum_size.x = 160
	line.add_child(_now_l)
	_now_eta = Label.new()
	_now_eta.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_now_eta.add_theme_color_override("font_color", Color(ScreenKit.GOLD))
	_now_eta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_now_eta.visible = false
	line.add_child(_now_eta)
	_now_bar = ProgressBar.new()
	_now_bar.show_percentage = false
	_now_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_bar.custom_minimum_size = Vector2(120, 22)
	_now_bar.visible = false
	now.add_child(_now_bar)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	now.add_child(acts)
	_acts_row = acts
	_start_btn = Button.new()
	_start_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_start_btn.theme_type_variation = &"AccentButton"
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_btn.visible = false
	_start_btn.pressed.connect(func() -> void:
		if not _start_skill.is_empty():
			EventBus.screen_requested.emit("skill:" + _start_skill, {}))
	acts.add_child(_start_btn)
	_now_open = Button.new()
	_now_open.name = "NowOpen"
	_now_open.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_now_open.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_now_open.visible = false
	_now_open.pressed.connect(func() -> void:
		if not _now_target.is_empty():
			EventBus.screen_requested.emit(_now_target, {}))
	acts.add_child(_now_open)
	# riga 2: PROSSIMO PASSO · DA FARE
	_top_row = HBoxContainer.new()
	_top_row.name = "TopRow"
	_top_row.add_theme_constant_override("separation", 10)
	add_child(_top_row)
	move_child(_top_row, at + 1)
	var step := _card(_top_row, "UI_SCR_SUMMARY_NEXT")
	_step_card = step.get_parent() as PanelContainer
	_step_card.name = "StepCard"
	_step_card.size_flags_stretch_ratio = 1.3
	_step_title = _label(&"SectionLabel")
	step.add_child(_step_title)
	_step_obj = _label(&"")
	_step_obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_obj.custom_minimum_size.x = 160
	step.add_child(_step_obj)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	step.add_child(row)
	_step_bar = ProgressBar.new()
	_step_bar.show_percentage = false
	_step_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_step_bar.custom_minimum_size = Vector2(90, 16)
	row.add_child(_step_bar)
	_step_num = _label(&"MonoLabel")
	_step_num.custom_minimum_size.x = 70
	row.add_child(_step_num)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step.add_child(spacer)
	_step_btn = Button.new()                 # l'UNICO pulsante pieno della scheda
	_step_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_step_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_step_btn.pressed.connect(func() -> void:
		if _step_target.is_empty() or not ReqLink.go(_step_target):
			EventBus.screen_requested.emit("quests", {}))
	step.add_child(_step_btn)
	# DA FARE (compare solo se c'è qualcosa; solo in banda stretta va sotto, a tutta larghezza)
	_todo_box = _card(_top_row, "UI_SCR_SUMMARY_TODO")
	_todo_card = _todo_box.get_parent() as PanelContainer
	_todo_card.name = "TodoCard"
	_todo_card.visible = false
	# riga 3: tre mini-schede (Livello totale · Deposito · Bonus)
	_stats_row = HBoxContainer.new()
	_stats_row.name = "StatsRow"
	_stats_row.add_theme_constant_override("separation", 10)
	add_child(_stats_row)
	move_child(_stats_row, at + 2)
	var lv := _card(_stats_row, "UI_GSA_SUM_LEVEL")
	_lv_card = lv.get_parent()
	_lv_big = _label(&"")
	_lv_big.add_theme_font_size_override("font_size", UiType.NUMBER_BIG)
	lv.add_child(_lv_big)
	var bk := _card(_stats_row, "UI_GSA_SUM_BANK")
	_bank_card = bk.get_parent()
	_bank_big = _label(&"")
	_bank_big.add_theme_font_size_override("font_size", UiType.NUMBER_BIG)
	bk.add_child(_bank_big)
	_bank_bar = ScreenKit.bar(bk, Color("#c8a24a"), 10)


func _build_secondary() -> void:
	_bonus_btn = Button.new()
	_bonus_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_bonus_btn.theme_type_variation = &"AccentButton"
	_bonus_btn.text = TranslationServer.translate("UI_UIA_BONUS_BTN")
	_bonus_btn.tooltip_text = TranslationServer.translate("UI_UIA_BONUS_BTN_TIP")
	_bonus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_bonus_btn.pressed.connect(open_bonus_panel)
	_acts_row.add_child(_bonus_btn)
	var pbody := IntroOnce.fold(self, FOLD_PROFILE, TranslationServer.translate("UI_SCR_SUMMARY_PROFILE"))
	_profile_fold = find_child("Fold_" + FOLD_PROFILE, true, false) as Button
	_profile = ProfileCard.new()
	pbody.add_child(_profile)
	var new_player := GameState.active and float(GameState.data.get("stats", {}).get("playtime_s", 0.0)) < MILESTONES_OPEN_S
	var mbody := IntroOnce.fold(self, FOLD_MILESTONES, Loc.tf("UI_SCR_SUMMARY_MILESTONES", {"n": 0}), new_player)
	remove_child(_milestones)
	mbody.add_child(_milestones)
	_milestones.owner = self                  # il nome unico «%Milestones» resta valido dopo lo spostamento
	_city = CityStrip.make_row()
	add_child(_city)


func open_bonus_panel() -> BonusDialog:
	return BonusDialog.open_on(self)


func _label(variation: StringName) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	return l


func open(_params: Dictionary) -> void:
	if not _title_built:
		_title_built = true
		var parts := IntroOnce.title_row(self, tr("UI_MENU_SUMMARY"), "UI_SCR_SUMMARY_PURPOSE", "summary")
		move_child((parts.title as Control).get_parent(), 0)
		if parts.intro != null:
			move_child(parts.intro as Control, 1)
			ScreenKit.cap_text(parts.intro as Label)
	refresh()


# ------------------------------------------------------------------ dati (puri, testabili)

## Partita appena iniziata: poco tempo di gioco E nessuna missione ancora completata (a 7 minuti, con Forgiatura e Cucina già
## sbloccate, il consiglio «apri Taglialegna e premi Avvia» era fuori luogo: PT118).
static func is_new_game() -> bool:
	if not GameState.active:
		return false
	var done: Variant = Game.system("quests").state.done if Game.system("quests") != null else []
	if done is Array and not (done as Array).is_empty():
		return false
	return float(GameState.data.get("stats", {}).get("playtime_s", 0.0)) < NEW_GAME_S


## Prima mansione sbloccata nell'ordine del menù (all'inizio: Taglialegna).
func first_unlocked_skill() -> String:
	var sk := Game.system("skills") as SkillSystem
	if sk == null:
		return ""
	for d in DataRegistry.table("skills"):
		if sk.is_unlocked(str(d.id)):
			return str(d.id)
	return ""


## Le righe di «Da fare»: una per CAUSA, ricavate da `SidebarBadges.signals()` (stessa sorgente del menù: i due non divergono).
## [{"key": chiave del testo ({n}), "n": quantità, "id": voce di destinazione, "params": {}, "kind": count|dot|danger}], prima i
## pericoli, poi le azioni da fare adesso, poi le novità. «Sbloccata e mai aperta» non è un lavoro da fare: non compare.
static func todo_rows() -> Array[Dictionary]:
	var recent: Array = []
	for d in DataRegistry.table("skills"):
		recent.append(ScreenRegistry.menu_id_for_skill(str(d.id)))
	var sig := SidebarBadges.signals({"recent": recent})
	var by_key: Dictionary = {}
	var rows: Array[Dictionary] = []
	for id in sig:
		var s: Dictionary = sig[id]
		for c in s.get("causes", []):
			var key := str(c[0])
			if key == SidebarBadges.CAUSE_NEW_ENTRY:
				continue
			if by_key.has(key):
				var r: Dictionary = rows[int(by_key[key])]
				r["n"] = int(r.n) + int(c[1])
				continue
			by_key[key] = rows.size()
			rows.append({"key": key, "n": int(c[1]), "id": str(id), "kind": str(s.get("kind", "")),
				"params": {"tab": "discover"} if key == SidebarBadges.CAUSE_DISCOVERY else {}})
	var rank := {SidebarBadges.KIND_DANGER: 0, SidebarBadges.KIND_COUNT: 1, SidebarBadges.KIND_DOT: 2}
	for i in rows.size():
		rows[i]["order"] = i
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(rank.get(a.kind, 3))
		var rb := int(rank.get(b.kind, 3))
		return int(a.order) < int(b.order) if ra == rb else ra < rb)
	return rows


# ------------------------------------------------------------------ aggiornamento

func refresh() -> void:
	_refresh_mode()
	_gold.text = NumberFormat.fmt(_bank_gold())
	_refresh_numbers()
	_refresh_now()
	_refresh_todo()
	_refresh_milestones()
	if _profile != null:
		_profile.refresh()
		if _profile_fold != null:
			_profile_fold.visible = _profile.visible
	if _bonus_btn != null:           # «Bonus attivi (N)»: quanti bonus ci sono adesso
		_bonus_btn.text = Loc.tf("UI_BONUS_BTN_N", {"n": BonusSummary.count(Modifiers.stack)})
	_place_todo()
	var first := is_new_game()
	_tip.visible = first                  # il consiglio c'è solo nei primi minuti: niente suggerimento comico in cima
	_tip.text = tr("UI_UXC_TIP_FIRST") if first else ""


func _bank_gold() -> float:
	var bank := Game.system("bank") as BankSystem
	return float(bank.gold() if bank != null else GameState.gold())


## I numeri chiave in una riga: livello totale · tempo di gioco · Deposito · Polvere Stellare (solo se il Prestigio è aperto).
func _refresh_numbers() -> void:
	var bank := Game.system("bank") as BankSystem
	var parts := PackedStringArray()
	parts.append(Loc.tf("UI_SCR_SUMMARY_NUMBERS_LV", {"n": TotalLevelText.text(GameState.total_level())}))
	parts.append(Loc.tf("UI_SCR_SUMMARY_NUMBERS_PLAY", {"t": NumberFormat.fmt_time(float(GameState.data.get("stats", {}).get("playtime_s", 0.0)))}))
	if bank != null:
		parts.append(Loc.tf("UI_SCR_SUMMARY_NUMBERS_BANK", {"u": NumberFormat.fmt(bank.used_slots()), "c": NumberFormat.fmt(bank.capacity())}))
		var dust := bank.currency(PrestigeSystem.DUST)
		if dust > 0 or TopBar.prestige_unlocked():
			parts.append(Loc.tf("UI_SCR_SUMMARY_NUMBERS_DUST", {"n": NumberFormat.fmt(dust)}))
	_numbers.text = " · ".join(parts)
	_numbers.visible = false                 # la stessa informazione sta nelle tre mini-schede; la riga resta per chi la legge (test, lettori)
	_lv_big.text = TotalLevelText.text(GameState.total_level())
	_lv_big.tooltip_text = Loc.tf("UI_TOTLV_TIP", {"min": NumberFormat.fmt(TotalLevelText.base())}) if TotalLevelText.show_base(GameState.total_level(), TotalLevelText.base()) else ""
	_lv_card.tooltip_text = Loc.tf("UI_SCR_SUMMARY_NUMBERS_PLAY", {"t": NumberFormat.fmt_time(float(GameState.data.get("stats", {}).get("playtime_s", 0.0)))})
	if bank != null:
		_bank_big.text = "%s / %s" % [NumberFormat.fmt(bank.used_slots()), NumberFormat.fmt(bank.capacity())]
		_bank_bar.set_target(clampf(float(bank.used_slots()) / maxf(1.0, float(bank.capacity())), 0.0, 1.0), 0.0)
		_bank_card.tooltip_text = Loc.tf("UI_GSA_SUM_FREE", {"n": NumberFormat.fmt(maxi(0, bank.capacity() - bank.used_slots()))})


## Modalità di gioco: la riga compare solo se non è Normale (nome, descrizione nel tooltip, in Estrema il conto delle vite perse).
func _refresh_mode() -> void:
	var m := GameState.mode()
	_mode_row.visible = m != "normal"
	_mode.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var t := tr(ModeRules.label_key(m))
	var md: Variant = GameState.data.get("modes", {})
	if GameState.mode_rules().has_permadeath() and md is Dictionary and int(md.get("deaths_lost", 0)) > 0:
		t += " · " + Loc.tf("UI_MODES_SUMMARY_LOST", {"n": int(md.deaths_lost)})
	_mode.text = t
	_mode.tooltip_text = tr("UI_MODES_DESC_" + m.to_upper())
	_mode.mouse_filter = Control.MOUSE_FILTER_STOP


func _refresh_now() -> void:
	_now_l.text = ActivityText.text() if ActivityText.is_active() else tr("UI_UXA_NOW_IDLE")
	var eta := LevelEta.info() if ActivityText.is_active() else {}
	_now_bar.visible = not eta.is_empty()
	_now_eta.visible = not eta.is_empty() and not LevelEta.short_text(eta).is_empty()
	if not eta.is_empty():
		_now_bar.max_value = 1.0
		_now_bar.value = float(eta.frac)
		_now_eta.text = LevelEta.short_text(eta)
	_refresh_now_icon()
	_start_skill = first_unlocked_skill() if (is_new_game() and not ActivityText.is_active()) else ""
	_start_btn.visible = not _start_skill.is_empty()
	if _start_btn.visible:
		_start_btn.text = Loc.tf("UI_UXC_GO_SKILL", {"skill": Loc.t(DataRegistry.get_def("skills", _start_skill).get("name", {}))})
	var quests := Game.system("quests") as QuestSystem
	var qid := quests.current_main() if quests != null else ""
	if qid.is_empty():
		_step_title.text = tr("UI_UXA_NOW_NO_QUEST")
		_set_step_visible(false, false)
		return
	var d := quests.quest_def(qid)
	var is_done := quests.is_ready(qid)
	_step_title.text = Loc.tf("UI_UXA_NOW_QUEST_READY", {"title": QuestText.title(d)}) if is_done else QuestText.title(d)
	# primo obiettivo non ancora raggiunto
	var objs: Array = d.get("objectives", [])
	var pr := quests.progress_of(qid)
	var shown := -1
	for i in objs.size():
		if i >= pr.size() or int(pr[i]) < QuestSystem.target_of(objs[i]):
			shown = i
			break
	_set_step_visible(shown >= 0 and not is_done, true)
	if shown >= 0 and not is_done:
		var tg := QuestSystem.target_of(objs[shown])
		var cur := int(pr[shown]) if shown < pr.size() else 0
		_step_obj.text = QuestText.objective(objs[shown], DataRegistry)
		_step_bar.max_value = maxf(1.0, float(tg))
		_step_bar.value = float(cur)
		_step_num.text = "%s / %s" % [NumberFormat.fmt(cur), NumberFormat.fmt(tg)]
	var goal := QuestGuide.current_goal(quests)
	_step_target = {} if is_done else (goal.target as Dictionary)
	_step_btn.theme_type_variation = &"AccentButton"
	if is_done:
		_step_btn.text = tr("UI_UXA_NOW_GO_CLAIM")
	elif not _step_target.is_empty():
		_step_btn.text = QuestGuide.go_label(_step_target)
	else:
		_step_btn.text = tr("UI_UXA_NOW_OPEN_QUESTS")


## Icona grande e pulsante «Apri …» dell'attività: la mansione in corso, il Combattimento, oppure l'Eroe attenuato se non si fa nulla.
func _refresh_now_icon() -> void:
	var sk := Game.system("skills") as SkillSystem
	var aid := sk.current_action() if sk != null else ""
	var skill_id := sk.skill_of(aid) if not aid.is_empty() else ""
	_now_target = ""
	var what := ""
	if not skill_id.is_empty():
		_now_icon.texture = IconLib.icon("skills", skill_id)
		_now_icon.modulate = Color.WHITE
		_now_target = "skill:" + skill_id
		what = Loc.t(DataRegistry.get_def("skills", skill_id).get("name", {}))
	elif ActivityText.is_active():
		_now_icon.texture = IconLib.icon("skills", "hero")
		_now_icon.modulate = Color.WHITE
		_now_target = "combat"
		what = tr("UI_MENU_COMBAT")
	else:
		_now_icon.texture = IconLib.icon("skills", "hero")
		_now_icon.modulate = Color(1, 1, 1, 0.45)
	_now_open.visible = not _now_target.is_empty()
	if _now_open.visible:
		_now_open.text = Loc.tf("UI_GSA_SUM_OPEN", {"what": what})


func _set_step_visible(progress: bool, button: bool) -> void:
	_step_obj.visible = progress
	_step_bar.visible = progress
	_step_num.visible = progress
	_step_btn.visible = button


## «Da fare»: ricostruita solo se le righe cambiano; la carta sparisce se non c'è nulla.
func _refresh_todo() -> void:
	var rows := todo_rows()
	var sig := JSON.stringify(rows)
	if sig != _todo_sig:
		_todo_sig = sig
		for c in _todo_box.get_children():
			if c is Label and (c as Label).theme_type_variation == &"SectionLabel" and c != _todo_more:
				continue                                  # l'intestazione resta
			_todo_box.remove_child(c)
			c.free()
		for i in mini(rows.size(), TODO_MAX):
			_todo_box.add_child(_todo_row(rows[i]))
		_todo_more = null
		if rows.size() > TODO_MAX:
			_todo_more = _label(&"MutedLabel")
			_todo_more.name = "TodoMore"
			_todo_more.text = Loc.tf("UI_GSA_SUM_TODO_MORE", {"n": rows.size() - TODO_MAX})
			_todo_box.add_child(_todo_more)
	_todo_card.visible = not rows.is_empty()


func _todo_row(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.name = "Todo_" + str(r.key)
	h.add_theme_constant_override("separation", 8)
	var l := _label(&"")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 140
	l.text = Loc.tf(str(r.key), {"n": NumberFormat.fmt(int(r.n))})
	h.add_child(l)
	var b := Button.new()
	b.name = "TodoGo"
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = tr("UI_SCR_SUMMARY_SEE") if str(r.kind) == SidebarBadges.KIND_DOT else tr("UI_SCR_SUMMARY_GO")
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var id := str(r.id)
	var params: Dictionary = r.params
	b.pressed.connect(func() -> void: EventBus.screen_requested.emit(id, params))
	h.add_child(b)
	return h


## Banda larga: Adesso, Prossimo passo e Da fare sulla stessa riga; altrimenti Da fare va sotto, a tutta larghezza.
func _place_todo() -> void:
	var vp := get_viewport()
	var w := vp.get_visible_rect().size.x if vp != null else 0.0
	var band := UiBands.band(w)
	if band == _band:
		return
	_band = band
	var want_row := band != UiBands.BAND_NARROW
	var in_row := _todo_card.get_parent() == _top_row
	if want_row == in_row:
		return
	_todo_card.get_parent().remove_child(_todo_card)
	if want_row:
		_top_row.add_child(_todo_card)
	else:
		add_child(_todo_card)
		move_child(_todo_card, _top_row.get_index() + 1)


## Prossimi traguardi: ricostruito solo se il testo cambia.
func _refresh_milestones() -> void:
	var quests := Game.system("quests") as QuestSystem
	if quests == null:
		return
	var rows := Milestones.lines(quests, DataRegistry)
	var sig := JSON.stringify(rows)
	if sig == _milestones_sig:
		return
	_milestones_sig = sig
	IntroOnce.retitle(self, FOLD_MILESTONES, Loc.tf("UI_SCR_SUMMARY_MILESTONES", {"n": rows.size()}))
	for c in _milestones.get_children():
		c.queue_free()
	for r in rows:
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = r.text
		if r.muted:
			l.theme_type_variation = &"MutedLabel"
		_milestones.add_child(l)
