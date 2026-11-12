class_name LogCategory
extends RefCounted
## Sezioni del Registro (colonna destra) e della navigazione, ognuna con UN colore proprio (rapporto 104).
## Il giocatore associa subito riga ↔ sezione: lo stesso colore compare come striscia sulla riga del Registro, come
## barretta sulla voce del menù laterale, come filo lungo il bordo della schermata e accanto agli interruttori delle
## notifiche nelle Impostazioni. Non basta il colore: ogni sezione ha anche un nome breve e una sigla di 2 lettere
## (UI_LOGCAT_<ID> e UI_LOGCAT_<ID>_TAG nel CSV).
## Solo presentazione (nessun numero di bilanciamento). Nessun colore coincide con quelli delle rarità (test_log_registry).

const SKILLS := "skills"
const COMBAT := "combat"
const LOOT := "loot"
const QUESTS := "quests"
const FEATS := "feats"
const ESTATE := "estate"
const MARKET := "market"
const PRESTIGE := "prestige"
const EVENTS := "events"
const COOP := "coop"
const SYSTEM := "system"

## Ordine di presentazione e colore (sRGB). Toni scelti per leggere bene sullo sfondo scuro del Registro.
const ORDER: PackedStringArray = ["skills", "combat", "loot", "quests", "feats", "estate", "market", "prestige", "events", "coop", "system"]
const COLORS := {
	"skills": "#8CCB4E",     # verde lime
	"combat": "#F0575A",     # rosso corallo
	"loot": "#2EC4B6",       # turchese
	"quests": "#4FA8F5",     # azzurro
	"feats": "#E6A0C4",      # rosa cipria
	"estate": "#B08A5A",     # terra di Siena
	"market": "#C9D86B",     # giallo-verde chiaro
	"prestige": "#C792EA",   # lilla
	"events": "#F59E7A",     # salmone
	"coop": "#6FE3A8",       # menta
	"system": "#B5B0A4",     # grigio caldo
}
## Colore del testo scritto SOPRA la striscia piena (sigla): scuro, contrasto alto con ogni tono sopra.
const ON_COLOR := Color("14171f")

## Voci del menù e schermate → sezione ("" = nessuna: il Riepilogo non appartiene a una sezione sola).
const SCREEN_SECTION := {
	"combat": COMBAT, "hero": COMBAT, "talents": COMBAT, "dungeon": COMBAT, "bounty": COMBAT,
	"bank": LOOT, "vault_hall": LOOT, "album": LOOT, "wardrobe": LOOT, "vault_workshop": LOOT,
	"market": MARKET, "shop": MARKET, "orders": MARKET, "factions": MARKET,
	"estate": ESTATE, "guild": ESTATE,
	"secrets": EVENTS, "events": EVENTS,
	"quests": QUESTS, "guide": SYSTEM, "prestige": PRESTIGE, "compendium": FEATS,
	"coop": COOP, "coop_lobby": COOP, "coop_guild": COOP,
	"settings": SYSTEM, "news": SYSTEM, "manual": SYSTEM,
}

## Categorie delle notifiche spegnibili (NoticeFilter.CATEGORIES, UI-A) → sezione di cui usano il colore.
const NOTIFY_SECTION := {
	"loot": LOOT, "progress": QUESTS, "achievements": FEATS, "levels": SKILLS, "events": EVENTS, "boss": COMBAT, "info": SYSTEM,
}


static func is_valid(section: String) -> bool:
	return COLORS.has(section)


static func color(section: String) -> Color:
	return Color(str(COLORS.get(section, COLORS.system)))


static func label(section: String) -> String:
	return TranslationServer.translate("UI_LOGCAT_" + section.to_upper())


static func tag(section: String) -> String:
	return TranslationServer.translate("UI_LOGCAT_%s_TAG" % section.to_upper())


## Sezione di una voce del menù / schermata ("skill:woodcutting" incluso). "" se non ne ha una.
static func of_screen(screen_id: String) -> String:
	if screen_id.begins_with("skill:"):
		return SKILLS
	return str(SCREEN_SECTION.get(screen_id, ""))


static func of_notify_category(category: String) -> String:
	return str(NOTIFY_SECTION.get(category, SYSTEM))


## Sezione di un messaggio dell'EventBus. Ordine: campo esplicito `section` · tipo di digest · chiavi note dei dati ·
## categoria di notifica · schermata aperta (per i messaggi nati dalla UI, che non portano dati) · Sistema.
static func of_notice(kind: String, data: Dictionary, screen_id: String = "") -> String:
	var explicit := str(data.get("section", ""))
	if is_valid(explicit):
		return explicit
	match str(data.get("digest", "")):
		"ach", "title", "frame", "pet", "pet_dupe":
			return FEATS
		"event", "event_buy", "secret", "rank":
			return EVENTS
		"boss_soon":
			return COMBAT
	if str(data.get("reason", "")) in ["bank_full", "overflow_claimed"] or data.has("crate") or data.has("def_id") or data.has("item"):
		return LOOT
	if data.has("quest") or data.has("npc"):
		return QUESTS
	if data.has("contract"):
		return MARKET
	if data.has("offer"):
		return COMBAT
	if data.has("era") or data.has("trial"):
		return PRESTIGE
	if data.has("estate_event"):
		return ESTATE
	if data.has("slot") or data.has("action") or data.has("crop"):
		return SKILLS
	match str(data.get("category", "")):
		"loot":
			return LOOT
		"boss":
			return COMBAT
		"levels":
			return SKILLS
		"events":
			return EVENTS
	if kind == "loot":
		return LOOT
	var s := of_screen(screen_id)
	return s if not s.is_empty() else SYSTEM


## «Titolo: dettaglio» → [titolo, dettaglio]. Taglia al primo «: » (titolo ≤ 44 caratteri) oppure alla prima frase;
## un testo breve e di una sola frase resta tutto titolo.
static func split_text(text: String) -> PackedStringArray:
	var t := text.strip_edges()
	var i := t.find(": ")
	if i > 0 and i <= 44:
		return PackedStringArray([t.substr(0, i), t.substr(i + 2).strip_edges()])
	for sep in [". ", "! ", "? "]:
		var j := t.find(sep)
		if j > 0 and j + 2 < t.length():
			return PackedStringArray([t.substr(0, j + 1), t.substr(j + 2).strip_edges()])
	return PackedStringArray([t, ""])
