extends Node
## Loc (autoload) — testi localizzati (docs/17 §8, CLAUDE.md regola 6).
## - Testi dei DATI: Loc.t(item.name) con item.name = {"it": "...", "en": "..."} (ripiego EN, poi IT).
## - Testi d'INTERFACCIA: tr("UI_CHIAVE") dal CSV localization/ui_strings.csv (fonte nella cartella
##   localization/ della radice; copiato in game/ da tools/sync_data.py).
## - Con segnaposto: Loc.tf("UI_IDLE_WARNING", {"hours": 3}) -> "Attenzione: il cibo finisce tra ~3 h".

const FALLBACK := "en"


func locale() -> String:
	return TranslationServer.get_locale().substr(0, 2)


## Testo {it,en} dei dati nella lingua attiva.
func t(text: Variant) -> String:
	if text is String:
		return text
	if not (text is Dictionary):
		return ""
	var d: Dictionary = text
	var lang := locale()
	if d.has(lang):
		return str(d[lang])
	if d.has(FALLBACK):
		return str(d[FALLBACK])
	return str(d.values()[0]) if not d.is_empty() else ""


## tr() con sostituzione dei segnaposto {nome}. Il «1» davanti a un plurale diventa singolare («1 pezzo», «1 level»).
func tf(key: String, params: Dictionary = {}) -> String:
	return fix_plural(tr(key).format(params), locale())


const PLURALS := {
	"it": {"pezzi": "pezzo", "livelli": "livello", "punti": "punto", "volte": "volta", "porzioni": "porzione", "oggetti": "oggetto",
		"minuti": "minuto", "ore": "ora", "secondi": "secondo", "giorni": "giorno", "mostri": "mostro", "uccisioni": "uccisione",
		"missioni": "missione", "soci": "socio", "coloni": "colono", "Stelle": "Stella", "stelle": "stella", "casse": "cassa",
		"Casse": "Cassa", "chiavi": "chiave", "monete": "moneta", "ranghi": "rango", "stanze": "stanza", "nemici": "nemico"},
	"en": {"pieces": "piece", "levels": "level", "points": "point", "times": "time", "portions": "portion", "items": "item",
		"minutes": "minute", "hours": "hour", "seconds": "second", "days": "day", "monsters": "monster", "kills": "kill",
		"quests": "quest", "members": "member", "settlers": "settler", "Stars": "Star", "stars": "star", "crates": "crate",
		"Crates": "Crate", "keys": "key", "coins": "coin", "ranks": "rank", "rooms": "room", "enemies": "enemy"},
}


## «1 pezzi» -> «1 pezzo» (solo quando l'1 è un numero intero a sé: non tocca «11 pezzi», «0,1 ore», «1/2 ore»).
func fix_plural(text: String, lang: String) -> String:
	if not text.contains("1 "):
		return text
	var table: Dictionary = PLURALS.get(lang, {})
	if table.is_empty():
		return text
	var out := text
	for plural: String in table:
		var needle := "1 " + plural
		var from := 0
		while true:
			var i := out.find(needle, from)
			if i < 0:
				break
			from = i + needle.length()
			var before := out.substr(i - 1, 1) if i > 0 else ""
			var after := out.substr(i + needle.length(), 1)
			if before != "" and (before.is_valid_int() or before in [",", ".", "/", "-"]):
				continue
			if after != "" and after.unicode_at(0) > 32 and (after.to_lower() != after.to_upper() or after.is_valid_int()):
				continue                    # parola più lunga («1 oreficeria»)
			out = out.substr(0, i) + "1 " + str(table[plural]) + out.substr(i + needle.length())
			from = i + 2 + str(table[plural]).length()
	return out


func set_locale(code: String) -> void:
	Settings.set_value("locale", code)
