class_name CreditsView
extends VBoxContainer
## Crediti / Informazioni (docs/24 §6, LICENSES.md): versione, chi ha fatto il gioco, motore, caratteri, arte e suoni, strumenti,
## uso di strumenti di IA, ringraziamenti e licenze di terze parti (finestra dedicata, in forma pubblica).
## Solo presentazione: i testi sono chiavi `UI_CRED_*` / `UI_M10_*`. Si usa nel menù iniziale (pannello con «Indietro»,
## segnale `closed`) e nelle Impostazioni (finestra, `show_dialog`).

signal closed

## Sezioni: [titolo (o ""), [chiavi dei paragrafi]]. Prima le persone, poi gli strumenti, come in ogni titolo di coda.
const SECTIONS: Array = [
	["UI_M10_CRED_TEAM_H", ["UI_M10_CRED_DEV", "UI_M10_CRED_ART_BY", "UI_M10_CRED_MUSIC_BY", "UI_M10_CRED_TEST"]],
	["UI_CRED_ENGINE_H", ["UI_CRED_ENGINE"]],
	["UI_CRED_FONTS_H", ["UI_CRED_FONT_ATKINSON", "UI_CRED_FONT_DEPARTURE", "UI_CRED_FONT_SYMBOLS"]],
	["UI_CRED_ART_H", ["UI_CRED_ART"]],
	["UI_CRED_TOOLS_H", ["UI_CRED_TOOLS"]],
	["UI_M10_CRED_AI_H", ["UI_M10_CRED_AI"]],
	["UI_M10_CRED_THANKS_H", ["UI_M10_CRED_THANKS"]],
	["", ["UI_CRED_ORIGINAL"]],
]

## Licenze di terze parti (forma pubblica di LICENSES.md): [titolo, testo].
const LICENSE_SECTIONS: Array = [
	["UI_M10_LIC_GODOT_H", "UI_M10_LIC_GODOT"],
	["UI_M10_LIC_FONTS_H", "UI_M10_LIC_FONTS"],
	["UI_M10_LIC_IMAGES_H", "UI_M10_LIC_IMAGES"],
	["UI_M10_LIC_MORE_H", "UI_M10_LIC_MORE"],
]

const LOCKUP: Texture2D = preload("res://assets/brand/logo_lockup.png")      # lo stesso marchio compatto della barra alta
var with_back: bool = true


## Lockup compatto del marchio (emblema + parola) a scala intera 2, filtro nearest: 236×32 logici.
static func make_lockup() -> TextureRect:
	var t := TextureRect.new()
	t.name = "Lockup"
	t.texture = LOCKUP
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = LOCKUP.get_size() * 2.0
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.free()
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	if with_back:
		var back := Button.new()
		back.name = "BackButton"
		back.text = "UI_BACK"
		back.custom_minimum_size = Vector2(120, 40)         # lo stesso «Indietro» delle Impostazioni (stessa forma e misura)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.pressed.connect(func() -> void: closed.emit())
		head.add_child(back)
	var title := ScreenKit.title_style(_text("UI_CRED_TITLE", &"TitleLabel"))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2.ZERO
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	head.add_child(make_lockup())
	var ver := Label.new()
	ver.name = "VersionLabel"
	ver.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ver.theme_type_variation = &"SectionLabel"
	ver.text = Loc.tf("UI_FB_VERSION", {"v": AppInfo.version_label(), "build": AppInfo.build()})
	add_child(ver)
	var scroll := ScrollContainer.new()
	scroll.name = "CreditsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.follow_focus = true
	add_child(scroll)
	var margin := MarginContainer.new()          # margine a destra: la barra di scorrimento non copre il testo
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_text("UI_CRED_INTRO", &"MutedLabel"))
	# sezioni in SCHEDE a due colonne (una sola se stretto): ogni scheda ha titolo e paragrafi, l'uso dell'IA ha il suo riquadro ambra
	var grid := GridContainer.new()
	grid.name = "CreditsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	scroll.resized.connect(func() -> void: grid.columns = 2 if scroll.size.x >= 860.0 else 1)
	var tail: Array = []
	for sec in SECTIONS:
		if str(sec[0]) == "":
			tail.append(sec)
			continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_FILL
		card.add_theme_stylebox_override("panel", ScreenKit.card_style(FxPalette.AMBER if str(sec[0]) == "UI_M10_CRED_AI_H" else Color(ScreenKit.EDGE), 4, true))
		grid.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		cv.add_child(_text(str(sec[0]), &"SectionLabel"))
		for key in sec[1]:
			cv.add_child(_text(str(key), &""))
	for sec in tail:
		for key in sec[1]:
			box.add_child(_text(str(key), &"MutedLabel"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	var lic := Button.new()
	lic.name = "LicensesButton"
	lic.text = "UI_M10_LIC_BUTTON"
	lic.pressed.connect(func() -> void: show_licenses(self))
	row.add_child(lic)
	var folder := licenses_folder()
	if not folder.is_empty():
		var open := Button.new()
		open.name = "LicensesFolderButton"
		open.text = "UI_M10_LIC_FOLDER"
		open.pressed.connect(func() -> void: OS.shell_open(folder))
		row.add_child(open)
	box.add_child(_text("UI_CRED_THANKS", &"SectionLabel"))
	box.add_child(_text("UI_M10_CRED_COPYRIGHT", &"MutedLabel"))


## Cartella `licenses` accanto all'eseguibile (le licenze complete distribuite con il gioco), «» se non c'è (es. dall'editor).
static func licenses_folder() -> String:
	var dir := OS.get_executable_path().get_base_dir().path_join("licenses")
	return dir if DirAccess.dir_exists_absolute(dir) else ""


func _text(key: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = key                                  # chiave: il Label la traduce da solo (e segue il cambio lingua)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 0)
	if variation != &"":
		l.theme_type_variation = variation
	return l


## Finestra dei Crediti (Impostazioni).
static func show_dialog(host: Node) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.title = "UI_CRED_TITLE"
	d.ok_button_text = "UI_FB_REPORT_CLOSE"
	var v := CreditsView.new()
	v.with_back = false
	v.custom_minimum_size = Vector2(600, 400)
	d.add_child(v)
	d.canceled.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	host.get_tree().root.add_child(d)
	d.popup_centered(Vector2i(680, 520))
	return d


## Finestra «Licenze di terze parti»: testo pubblico (copyright e licenze), non le note interne di LICENSES.md.
static func show_licenses(host: Node) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.name = "LicensesDialog"
	d.title = "UI_M10_LIC_BUTTON"
	d.ok_button_text = "UI_FB_REPORT_CLOSE"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(620, 380)
	d.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	for sec in LICENSE_SECTIONS:
		for i in 2:
			var l := Label.new()
			l.text = str(sec[i])
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size = Vector2(300, 0)
			l.theme_type_variation = &"SectionLabel" if i == 0 else &"MutedLabel"
			box.add_child(l)
	d.canceled.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	host.get_tree().root.add_child(d)
	d.popup_centered(Vector2i(700, 520))
	return d
