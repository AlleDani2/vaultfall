class_name AbilityDragRow
extends HBoxContainer
## Riga di una abilità dell'Eroe riordinabile a trascinamento (docs/16 §3.6, UI-A G18): la rotazione automatica prova le
## abilità nell'ordine delle righe, quindi trascinare la maniglia «≡» su un'altra riga cambia la priorità.
## Emette `moved(da, a)` con gli indici delle righe; chi la usa applica il nuovo ordine (HeroScreen.reorder_ids).

signal moved(from_index: int, to_index: int)

const DRAG_KEY := "ability_slot"

var index: int = 0
var _grip: Label


func _init(slot_index: int = 0) -> void:
	index = slot_index
	add_theme_constant_override("separation", 6)
	_grip = Label.new()
	_grip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_grip.text = "≡"
	_grip.theme_type_variation = &"MutedLabel"
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_grip.tooltip_text = TranslationServer.translate("UI_UIA_DRAG_TIP")
	_grip.set_drag_forwarding(_grip_drag, Callable(), Callable())
	add_child(_grip)


## Fa accettare il rilascio anche a un figlio (un OptionButton blocca il mouse e non lo passerebbe alla riga).
func accept_drops_on(ctrl: Control) -> void:
	ctrl.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)


func _grip_drag(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	preview.text = "≡ %d" % (index + 1)
	set_drag_preview(preview)
	return {DRAG_KEY: index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has(DRAG_KEY) and int(data[DRAG_KEY]) != index


func _drop_data(_at: Vector2, data: Variant) -> void:
	moved.emit(int(data[DRAG_KEY]), index)


## Nuovo ordine di una lista di id dopo aver spostato la voce `from` nella posizione `to` (le altre scorrono).
static func reorder_ids(ids: Array, from: int, to: int) -> Array:
	var out := ids.duplicate()
	if from < 0 or from >= out.size() or to < 0 or to >= out.size() or from == to:
		return out
	var v: Variant = out[from]
	out.remove_at(from)
	out.insert(to, v)
	return out
