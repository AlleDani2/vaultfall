class_name DialogKit
extends RefCounted
## Finestre di conferma coerenti (QA119): titolo e pulsanti tradotti (prima restavano «Please Confirm...», «OK», «Cancel» in
## inglese), testo a capo e larghezza minima (prima una frase lunga correva fuori dalla finestra, tagliata a destra).
## Le chiavi si lasciano come chiavi: Godot le traduce da solo e segue il cambio di lingua.


static func style_confirm(d: ConfirmationDialog, min_w: int = 460) -> void:
	d.title = "UI_DLG_CONFIRM_TITLE"
	d.ok_button_text = "UI_DLG_OK"
	d.cancel_button_text = "UI_DLG_CANCEL"
	d.dialog_autowrap = true
	d.min_size = Vector2i(min_w, 0)
