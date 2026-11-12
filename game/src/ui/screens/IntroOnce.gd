class_name IntroOnce
extends RefCounted
## Prosa a richiesta (progetto di interfaccia D17, fase F6): la frase «a cosa serve» di una schermata compare alla PRIMA visita
## e poi si richiude in un «?» accanto al titolo; le spiegazioni lunghe stanno in sezioni richiudibili (Disclosure) il cui stato
## il giocatore ritrova alla visita dopo. Tutto vive in `Settings.seen_intro` (lista di testi):
##   "<id schermata>"        la frase è già stata mostrata una volta
##   "open:<id>" / "shut:<id>"  la sezione richiudibile è stata lasciata aperta / chiusa dal giocatore
## Solo presentazione: nessun numero di bilanciamento.

const KEY := "seen_intro"
const OPEN := "open:"
const SHUT := "shut:"


static func _list() -> Array:
	var v: Variant = Settings.get_value(KEY)
	return (v as Array).duplicate() if v is Array else []


static func seen(screen_id: String) -> bool:
	return _list().has(screen_id)


static func mark_seen(screen_id: String) -> void:
	var l := _list()
	if not l.has(screen_id):
		l.append(screen_id)
		Settings.set_value(KEY, l)


## Titolo + «?» + (alla prima visita) la frase «a cosa serve». `title_text` è già tradotto; `intro_key` può essere vuoto.
## Ritorna {"title": Label, "help": Button, "intro": Label (o null)}. La frase si considera vista appena la schermata si apre.
static func title_row(parent: Control, title_text: String, intro_key: String, screen_id: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "TitleRow"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var title := Label.new()
	title.name = "Title"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ScreenKit.title_style(title)
	title.text = title_text
	row.add_child(title)
	var out := {"title": title, "help": null, "intro": null}
	if intro_key.is_empty():
		return out
	var help := Button.new()
	help.name = "IntroHelp"
	help.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	help.text = "?"
	help.flat = true
	help.focus_mode = Control.FOCUS_ALL
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.tooltip_text = TranslationServer.translate("UI_SCR_SUMMARY_WHAT_TIP")
	row.add_child(help)
	var intro := Label.new()
	intro.name = "IntroText"
	intro.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	intro.theme_type_variation = UiKit.INTRO_HINT
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = TranslationServer.translate(intro_key)
	intro.visible = not seen(screen_id)
	parent.add_child(intro)
	help.pressed.connect(func() -> void: intro.visible = not intro.visible)
	mark_seen(screen_id)
	out["help"] = help
	out["intro"] = intro
	return out


# ------------------------------------------------------------------ sezioni richiudibili con stato ricordato

static func fold_is_open(fold_id: String, default_open: bool) -> bool:
	var l := _list()
	if l.has(OPEN + fold_id):
		return true
	if l.has(SHUT + fold_id):
		return false
	return default_open


static func set_fold_open(fold_id: String, open: bool) -> void:
	var l := _list()
	l.erase(OPEN + fold_id)
	l.erase(SHUT + fold_id)
	l.append((OPEN if open else SHUT) + fold_id)
	Settings.set_value(KEY, l)


## Sezione richiudibile: pulsante con freccia (Disclosure) + corpo, in UN contenitore («FoldBox_<id>», figlio di `parent`: conta come
## un solo elemento della scheda). `title` è già tradotto. Ritorna il corpo (VBoxContainer): ci si aggiungono i figli.
## Il pulsante si chiama «Fold_<id>» (per i test), il corpo «Body_<id>».
static func fold(parent: Control, fold_id: String, title: String, default_open: bool = false) -> VBoxContainer:
	var open := fold_is_open(fold_id, default_open)
	var box := VBoxContainer.new()
	box.name = "FoldBox_" + fold_id
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var btn := Button.new()
	btn.name = "Fold_" + fold_id
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.set_meta("fold_title", title)
	btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	btn.text = (Disclosure.OPEN if open else Disclosure.CLOSED) + title
	box.add_child(btn)
	var body := VBoxContainer.new()
	body.name = "Body_" + fold_id
	body.add_theme_constant_override("separation", 6)
	body.visible = open
	body.set_meta("fold_button", btn)         # per chi deve raggiungere il pulsante (tooltip) senza cercarlo per nome
	box.add_child(body)
	btn.pressed.connect(func() -> void:
		var now := not body.visible
		body.visible = now
		btn.text = (Disclosure.OPEN if now else Disclosure.CLOSED) + str(btn.get_meta("fold_title"))
		set_fold_open(fold_id, now))
	return body


## Cambia il titolo di una sezione già creata (il conteggio nel titolo cambia: «Prossimi traguardi (2)»).
static func retitle(parent: Control, fold_id: String, title: String) -> void:
	var btn := parent.find_child("Fold_" + fold_id, true, false) as Button
	if btn == null:
		return
	btn.set_meta("fold_title", title)
	var body := parent.find_child("Body_" + fold_id, true, false) as Control
	btn.text = (Disclosure.OPEN if body != null and body.visible else Disclosure.CLOSED) + title
