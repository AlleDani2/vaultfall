class_name VaultHead
extends RefCounted
## Testata e schede condivise da Sala dei Caveau, Album e Guardaroba (progetto di interfaccia F11, docs/ui_redesign/06 §3.13).
## Solo presentazione. La frase «a cosa serve» compare alla PRIMA visita (D17, Settings.seen_intro) e poi si richiude
## in un «?» accanto al titolo. Le schede della Sala sono 5 (Casse · Contratti · Affinatura · Banco · Sfida): Album e
## Guardaroba hanno la loro voce nel menù (un posto solo, P11); una scheda chiusa è un 🔒 con tooltip e «Vai» al clic.

const CONTENTS_ID := "vault_hall_contents"

## Schede della Sala (id di CrateUi.TAB_DEFS).
const HALL_TABS: PackedStringArray = ["hall", "contracts", "refine", "bank", "challenge"]

static var _intro_open: Dictionary = {}       # id -> aperta? (solo sessione)


## Vero se il giocatore ha già visto la frase di `id` (Settings.seen_intro).
static func seen(id: String) -> bool:
	return (Settings.get_value("seen_intro") as Array).has(id)


## Segna `id` come visto (persistente nelle impostazioni, mai nel salvataggio di gioco).
static func mark_seen(id: String) -> void:
	var arr: Array = (Settings.get_value("seen_intro") as Array).duplicate()
	if not arr.has(id):
		arr.append(id)
		Settings.set_value("seen_intro", arr)


## Titolo + «?» + frase «a cosa serve» (aperta solo alla prima visita). Il «?» la riapre/richiude.
static func header(parent: Control, id: String, title_key: String, intro_key: String) -> void:
	var row := HBoxContainer.new()
	row.name = "HeadRow"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var title := Label.new()
	title.text = TranslationServer.translate(title_key)
	ScreenKit.title_style(title)
	row.add_child(title)
	if intro_key.is_empty():
		return
	var open: bool
	if _intro_open.has(id):
		open = bool(_intro_open[id])
	else:
		open = not seen(id)
		_intro_open[id] = open
		if open:
			mark_seen(id)
	var help := Button.new()
	help.name = "IntroToggle"
	help.text = "?"
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help.tooltip_text = TranslationServer.translate("UI_VUX_WHAT_FOR")
	help.focus_mode = Control.FOCUS_ALL
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.custom_minimum_size = Vector2(32, 0)
	row.add_child(help)
	var intro := Label.new()
	intro.name = "IntroText"
	intro.text = TranslationServer.translate(intro_key)
	intro.theme_type_variation = &"MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.visible = open
	parent.add_child(intro)
	help.pressed.connect(func() -> void:
		intro.visible = not intro.visible
		_intro_open[id] = intro.visible)


## Schede della Sala dei Caveau. Chiusa = 🔒 con tooltip (come si apre) e «Vai» alla missione che la sblocca al clic.
static func hall_tabs(parent: Control, current: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Tabs"
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 6)
	parent.add_child(row)
	for t in CrateUi.TAB_DEFS:
		if not HALL_TABS.has(str(t.id)):
			continue
		var b := Button.new()
		b.name = "Tab_" + str(t.id)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = TranslationServer.translate(str(t.key))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 24)
		var ic: Array = VaultKit.TAB_ICON.get(str(t.id), ["items", "vault_shard"])
		if t.id == current:
			b.theme_type_variation = &"AccentButton"
			b.focus_mode = Control.FOCUS_NONE
			b.icon = IconLib.icon(str(ic[0]), str(ic[1]))
		elif not CrateUi.unlocked(str(t.token)):
			b.icon = IconLib.ui("ui_lock")
			var hint := UnlockSystem.hint_for(str(t.token), DataRegistry)
			if hint.is_empty():
				hint = str(TranslationServer.translate("UI_CRATES2_TAB_LOCKED"))
			var target := ReqLink.target_for_token(str(t.token))
			if target.is_empty():
				b.disabled = true
				b.tooltip_text = hint
			else:
				b.tooltip_text = hint + "\n" + Loc.tf("UI_VUX_GO", {"to": TranslationServer.translate("UI_MENU_QUESTS")})
				b.pressed.connect(ReqLink.go.bind(target))
			b.set_meta("locked", true)
		else:
			b.icon = IconLib.icon(str(ic[0]), str(ic[1]))
			var scr: String = t.screen
			var params := {} if str(t.tab).is_empty() else {"tab": str(t.tab)}
			b.pressed.connect(func() -> void: EventBus.screen_requested.emit(scr, params))
		var badge := VaultKit.tab_badge(str(t.id))
		if not badge.is_empty() and not b.disabled and not b.has_meta("locked"):
			b.text += "  (%s)" % badge
		row.add_child(b)
	return row
