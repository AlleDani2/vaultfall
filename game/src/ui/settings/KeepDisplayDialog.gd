class_name KeepDisplayDialog
extends ConfirmationDialog
## «Mantieni queste impostazioni?» dopo un cambio di modalità, risoluzione o monitor: se non si conferma entro 10 secondi
## (schermo nero, finestra fuori dal monitor) tutto torna com'era. Il conto alla rovescia gira anche con il gioco in pausa.
##   KeepDisplayDialog.show_for(host, snapshot_prima)

signal resolved(kept: bool)

var before: Dictionary = {}
var seconds_left: int = DisplayOptions.KEEP_SECONDS
var _timer: Timer
var _done := false


static func show_for(host: Node, snap: Dictionary) -> KeepDisplayDialog:
	var d := KeepDisplayDialog.new()
	d.before = snap
	host.add_child(d)
	d.popup_centered()
	return d


func _init() -> void:
	name = "KeepDisplayDialog"
	process_mode = Node.PROCESS_MODE_ALWAYS
	exclusive = true


func _ready() -> void:
	title = tr("UI_I10_KEEP_TITLE")
	ok_button_text = tr("UI_I10_KEEP_YES")
	cancel_button_text = tr("UI_I10_KEEP_NO")
	_update_text()
	confirmed.connect(keep)
	canceled.connect(revert)
	close_requested.connect(revert)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	get_ok_button().grab_focus.call_deferred()


func _update_text() -> void:
	dialog_text = Loc.tf("UI_I10_KEEP_TEXT", {"n": seconds_left})


func _tick() -> void:
	seconds_left -= 1
	if seconds_left <= 0:
		revert()
	else:
		_update_text()


## Conferma: le impostazioni restano (sono già salvate).
func keep() -> void:
	if _done:
		return
	_done = true
	Settings.set_value("display_revert", {})
	resolved.emit(true)
	queue_free()


## Annulla (o tempo scaduto): torna alle impostazioni di prima.
func revert() -> void:
	if _done:
		return
	_done = true
	DisplayOptions.restore(before)
	Settings.set_value("display_revert", {})
	resolved.emit(false)
	queue_free()
