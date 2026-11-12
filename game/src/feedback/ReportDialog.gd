class_name ReportDialog
extends ConfirmationDialog
## Finestra «Segnala un problema»: spiega in parole semplici cosa finirà nello ZIP, chiede (facoltativamente) cosa si stava
## facendo, crea il file in una cartella visibile e la apre. NIENTE viene inviato: il file lo manda la persona, a mano.
## Uso: ReportDialog.show_for(un_nodo_qualsiasi)

var out_dir: String = ""               # solo test: cartella alternativa
var last_result: Dictionary = {}

var _note: TextEdit
var _result: Label
var _folder_btn: Button
var _done: bool = false


static func show_for(host: Node) -> ReportDialog:
	var d := ReportDialog.new()
	host.get_tree().root.add_child(d)
	d.popup_centered(Vector2i(700, 560))
	return d


func _init() -> void:
	title = "UI_FB_REPORT_TITLE"
	dialog_hide_on_ok = false
	ok_button_text = "UI_FB_REPORT_CREATE"
	cancel_button_text = "UI_FB_REPORT_CANCEL"
	exclusive = false


func _ready() -> void:
	var scroll := ScrollContainer.new()               # altezza fissa: sul portatile piccolo la finestra non esce dallo schermo
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(640, 430)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(_para("UI_FB_REPORT_INTRO", &""))
	if AppConfig.has_support():              # contatto di assistenza: un solo punto di configurazione (game/app_config.json)
		var sup := Label.new()
		sup.text = Loc.tf("UI_PLAT_SUPPORT_LINE", {"contact": AppConfig.support_contact()})
		sup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		sup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sup.custom_minimum_size = Vector2(300, 0)
		box.add_child(sup)
		var sup_btn := Button.new()
		sup_btn.text = "UI_PLAT_OPEN_SUPPORT"
		sup_btn.pressed.connect(AppConfig.open_support)
		box.add_child(sup_btn)
	box.add_child(_para("UI_FB_REPORT_CONTENTS", &"MutedLabel"))
	box.add_child(_para("UI_FB_REPORT_PRIVACY", &"MutedLabel"))
	var nl := Label.new()
	nl.text = "UI_FB_REPORT_NOTE_LABEL"
	nl.theme_type_variation = &"SectionLabel"
	box.add_child(nl)
	_note = TextEdit.new()
	_note.placeholder_text = tr("UI_FB_REPORT_NOTE_HINT")
	_note.custom_minimum_size = Vector2(0, 110)
	_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_note)
	_result = Label.new()
	_result.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(300, 0)
	_result.visible = false
	box.add_child(_result)
	_folder_btn = Button.new()
	_folder_btn.text = "UI_FB_REPORT_OPEN_FOLDER"
	_folder_btn.visible = false
	_folder_btn.pressed.connect(open_folder)
	box.add_child(_folder_btn)
	confirmed.connect(_on_ok)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)


func _para(key: String, variation: StringName) -> Label:
	var l := Label.new()
	l.text = key
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 0)
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _on_ok() -> void:
	if _done:
		queue_free()
		return
	create_report()


## Crea lo ZIP con la nota scritta e mostra l'esito. Ritorna il risultato di ReportBuilder.build().
func create_report() -> Dictionary:
	var rb: Variant = Feedback.new_report(_note.text if _note != null else "")
	rb.out_dir = out_dir
	last_result = rb.build()
	_done = true
	if _result != null:
		_result.visible = true
		if last_result.ok:
			_result.text = Loc.tf("UI_FB_REPORT_DONE", {"path": ReportBuilder.scrub(str(last_result.path))})
			_folder_btn.visible = true
		else:
			_result.text = Loc.tf("UI_FB_REPORT_FAILED", {"err": str(last_result.error)})
		get_ok_button().text = tr("UI_FB_REPORT_CLOSE")
		get_cancel_button().visible = false
	return last_result


func open_folder() -> void:
	if last_result.get("ok", false):
		OS.shell_open(ProjectSettings.globalize_path(str(last_result.path).get_base_dir()))
