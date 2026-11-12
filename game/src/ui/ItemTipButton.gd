class_name ItemTipButton
extends Button
## Pulsante-riga con il tooltip degli oggetti (ItemTooltip) e il segnale del tasto destro (menù contestuale, UI-A G25).
## Chi lo usa imposta `def_id` e `inst` (istanza o {} per le pile) a ogni (ri)collegamento della riga e riceve
## `context_requested(position_globale)` al clic destro.

signal context_requested(global_pos: Vector2)

var def_id: String = ""
var inst: Dictionary = {}


func _init() -> void:
	tooltip_text = " "              # il testo vero lo costruisce _make_custom_tooltip; un testo vuoto spegnerebbe il tooltip


func set_item(new_def: String, new_inst: Dictionary = {}) -> void:
	def_id = new_def
	inst = new_inst


func _make_custom_tooltip(_for_text: String) -> Object:
	return ItemTooltip.make_control(def_id, inst) if not def_id.is_empty() else null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(get_global_mouse_position())
		accept_event()
