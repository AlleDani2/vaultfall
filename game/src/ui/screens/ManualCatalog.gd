class_name ManualCatalog
extends RefCounted
## Elenco delle pagine del Manuale in gioco e collegamento schermata -> pagina (icona «?» e tasto F1).
## Funzioni pure, nessuno stato. I testi stanno in localization/parts/manual2.csv (chiavi UI_MAN2_<PAGINA>_*), i
## numeri nelle pagine sono generati dai dati da ManualFacts. Per aggiungere una pagina: una riga in GROUPS,
## le chiavi nel CSV, un caso in ManualFacts.params (se ha numeri) e, se ha una schermata, una riga in SCREEN_PAGES.

## Gruppi mostrati nell'indice (chiave del titolo del gruppo, pagine nell'ordine di lettura).
const GROUPS: Array[Dictionary] = [
	{"title": "UI_MAN2_G_START", "pages": ["start", "guide", "quests", "modes", "settings", "feedback", "coop"]},
	{"title": "UI_MAN2_G_SKILLS", "pages": ["skills", "queue", "push", "farm", "alchemy", "apprentices"]},
	{"title": "UI_MAN2_G_ADVENTURE", "pages": ["combat", "classes", "bounty", "raids", "worldboss", "rift"]},
	{"title": "UI_MAN2_G_CITY", "pages": ["bank", "crates", "vault_tools", "album", "market", "orders", "factions", "estate",
		"guild", "mercenaries", "expeditions", "secrets"]},
	{"title": "UI_MAN2_G_PROGRESS", "pages": ["prestige", "constellations", "refound", "eras", "compendium", "events"]},
	{"title": "UI_MAN2_G_REFERENCE", "pages": ["formulas", "drops", "unlocks", "glossary"]},
]

## Pagine nate con il primo Manuale: titolo con le chiavi UI_QUESTS_MAN_P_*.
const LEGACY: PackedStringArray = ["formulas", "crates", "drops", "unlocks", "glossary", "start"]

## Tutte le pagine (nello stesso ordine di GROUPS).
const PAGES: PackedStringArray = [
	"start", "guide", "quests", "modes", "settings", "feedback", "coop",
	"skills", "queue", "push", "farm", "alchemy", "apprentices",
	"combat", "classes", "bounty", "raids", "worldboss", "rift",
	"bank", "crates", "vault_tools", "album", "market", "orders", "factions", "estate", "guild", "mercenaries", "expeditions", "secrets",
	"prestige", "constellations", "refound", "eras", "compendium", "events",
	"formulas", "drops", "unlocks", "glossary",
]

## Pagina del Manuale per ogni voce di ScreenRegistry (le mansioni "skill:<id>" hanno la regola dopo).
const SCREEN_PAGES := {
	"summary": "start", "manual": "start", "guide": "guide", "quests": "quests", "settings": "settings", "news": "feedback",
	"combat": "combat", "hero": "classes", "talents": "classes", "dungeon": "raids", "bounty": "bounty",
	"bank": "bank", "vault_hall": "crates", "album": "album", "wardrobe": "album", "vault_workshop": "vault_tools",
	"market": "market", "shop": "market", "orders": "orders", "factions": "factions", "estate": "estate",
	"guild": "guild", "secrets": "secrets", "prestige": "prestige", "events": "events", "compendium": "compendium",
	"coop": "coop", "friends": "coop",
}

## Mansioni con pagina propria; tutte le altre usano "skills".
const SKILL_PAGES := {"farming": "farm", "alchemy": "alchemy"}


static func has_page(page: String) -> bool:
	return PAGES.has(page)


## Chiave del titolo della pagina.
static func title_key(page: String) -> String:
	if LEGACY.has(page):
		return "UI_QUESTS_MAN_P_" + page.to_upper()
	return "UI_MAN2_%s_T" % page.to_upper()


## Pagina da aprire per una schermata del menù ("skill:mining" -> "skills"). Sconosciuta -> "start".
static func page_for_screen(screen_id: String) -> String:
	if screen_id.begins_with("skill:"):
		return str(SKILL_PAGES.get(screen_id.substr(6), "skills"))
	if SCREEN_PAGES.has(screen_id):
		return str(SCREEN_PAGES[screen_id])
	if screen_id.begins_with("coop") or screen_id.begins_with("friend"):
		return "coop"
	return "start"
