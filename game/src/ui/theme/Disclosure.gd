class_name Disclosure
extends RefCounted
## Testo dei pulsanti a scomparsa con freccia (▸ chiuso, ▾ aperto): senza freccia sembrano pulsanti normali
## e il giocatore non capisce che si aprono (QA-UX A). Il pulsante deve avere auto_translate disattivato.

const CLOSED := "▸ "
const OPEN := "▾ "


static func label(text_key: String, open: bool) -> String:
	return (OPEN if open else CLOSED) + TranslationServer.translate(text_key)


## Imposta il testo con la freccia e disattiva la traduzione automatica del pulsante (il testo è già tradotto).
static func apply(button: Button, text_key: String, open: bool) -> void:
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = label(text_key, open)
