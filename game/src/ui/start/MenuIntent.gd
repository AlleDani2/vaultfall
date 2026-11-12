class_name MenuIntent
extends RefCounted
## Cosa fare appena la partita si apre dal menù principale (es. «Cooperativa (LAN)» → aprire la Lobby).
## Il menù lo imposta prima di caricare lo slot; MainScreen lo legge una volta sola e lo azzera.

static var screen: String = ""


## Schermata richiesta dal menù ("" se nessuna); si consuma alla lettura.
static func take() -> String:
	var s := screen
	screen = ""
	return s
