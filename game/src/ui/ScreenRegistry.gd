class_name ScreenRegistry
extends RefCounted
## UNICO registro delle schermate del menù laterale (docs/16 §2). MainScreen costruisce il menù da qui.
## Per aggiungere una schermata:
##   1) creare src/ui/screens/MiaScreen.tscn con radice che estende GameScreen;
##   2) aggiungere/aggiornare UNA riga in SCREENS (una riga per voce, virgola finale: merge banale tra agenti);
##   3) aggiungere la chiave del titolo in localization/ui_strings.csv (poi copia in game/localization/).
## Campi: id (unico) · section (id di SECTIONS) · title (chiave CSV) · icon (res://… facoltativa, ignorata se
## il file non esiste) · scene ("" = non ancora realizzata: voce grigia) · unlock ("" = sempre; altrimenti un
## token di GameState.data.unlocks, es. "feature:crates") · order (posizione nella sezione) · hint_unlock (facoltativo:
## token da cui ricavare il suggerimento «Si sblocca con: missione …» quando quello di sblocco non viene da una
## missione; es. Prestigio: feature:prestige lo concede PrestigeSystem al livello di rito OPPURE con
## feature:skill_prestige della missione main_c8_q3).
## menu (facoltativo, F4): "hidden" = la voce non sta nel menù laterale ma la schermata esiste (Impostazioni: ⚙ in barra alta);
## "coop_used" = compare nel menù solo dopo il primo uso del coop (Lobby, Gilda d'amici).
## Le mansioni sono voci generate dai dati (skills.json): una per mansione, tutte con SKILL_SCENE
## (escluse quelle del gruppo SKILL_GROUPS_HIDDEN, i cui livelli si vedono nelle schermate di combattimento).

const SECTIONS: Array[Dictionary] = [
	{"id": "summary", "title": ""},
	{"id": "skills", "title": "UI_MENU_SKILLS"},
	{"id": "adventure", "title": "UI_MENU_ADVENTURE"},
	{"id": "city", "title": "UI_MENU_CITY"},
	{"id": "vault", "title": "UI_SIDE_GROUP_VAULT"},
	{"id": "progress", "title": "UI_MENU_PROGRESS"},
]

## Scena unica delle mansioni (riceve params {"skill": id}): SkillScreen.
const SKILL_SCENE := "res://src/ui/screens/SkillScreen.tscn"
## Mansioni con schermata dedicata al posto di SKILL_SCENE (stessa voce del menù, stesso sblocco).
const SKILL_SCENE_OVERRIDE := {"farming": "res://src/ui/screens/FarmScreen.tscn"}
const SKILL_GROUPS_HIDDEN: PackedStringArray = ["combat"]

const SCREENS: Array[Dictionary] = [
	{"id": "summary", "section": "summary", "title": "UI_MENU_SUMMARY", "icon": "", "scene": "res://src/ui/screens/SummaryScreen.tscn", "unlock": "", "order": 0},
	{"id": "combat", "section": "adventure", "title": "UI_MENU_COMBAT", "icon": "", "scene": "res://src/ui/screens/CombatScreen.tscn", "unlock": "feature:combat", "order": 10},
	{"id": "hero", "section": "adventure", "title": "UI_MENU_HERO", "icon": "", "scene": "res://src/ui/screens/HeroScreen.tscn", "unlock": "skill:hero", "order": 20},
	{"id": "talents", "section": "adventure", "title": "UI_MENU_TALENTS", "icon": "", "scene": "res://src/ui/screens/TalentScreen.tscn", "unlock": "feature:talents", "order": 30},
	{"id": "dungeon", "section": "adventure", "title": "UI_MENU_DUNGEON", "icon": "", "scene": "res://src/ui/screens/DungeonScreen.tscn", "unlock": "dungeon:cursed_granary", "order": 40},
	{"id": "bounty", "section": "adventure", "title": "UI_MENU_BOUNTY", "icon": "", "scene": "res://src/ui/screens/BountyScreen.tscn", "unlock": "feature:bounties", "order": 50},
	{"id": "bank", "section": "city", "title": "UI_MENU_BANK", "icon": "", "scene": "res://src/ui/screens/BankScreen.tscn", "unlock": "", "order": 10},
	{"id": "vault_hall", "section": "vault", "title": "UI_MENU_VAULT_HALL", "icon": "", "scene": "res://src/ui/screens/VaultHallScreen.tscn", "unlock": "feature:crates", "order": 20},
	{"id": "album", "section": "vault", "title": "UI_MENU_ALBUM", "icon": "", "scene": "res://src/ui/screens/AlbumScreen.tscn", "unlock": "feature:wardrobe", "order": 21},
	{"id": "wardrobe", "section": "vault", "title": "UI_MENU_WARDROBE", "icon": "", "scene": "res://src/ui/screens/WardrobeScreen.tscn", "unlock": "feature:wardrobe", "order": 22},
	{"id": "vault_workshop", "section": "vault", "title": "UI_MENU_VAULT_WORKSHOP", "icon": "", "scene": "res://src/ui/screens/VaultWorkshopScreen.tscn", "unlock": "feature:crates", "order": 23},
	{"id": "market", "section": "city", "title": "UI_MENU_MARKET", "icon": "", "scene": "res://src/ui/screens/MarketScreen.tscn", "unlock": "feature:market", "order": 30},
	{"id": "shop", "section": "city", "title": "UI_MENU_SHOP", "icon": "", "scene": "res://src/ui/screens/ShopScreen.tscn", "unlock": "feature:market", "order": 31},
	{"id": "orders", "section": "city", "title": "UI_MENU_ORDERS", "icon": "", "scene": "res://src/ui/screens/OrdersScreen.tscn", "unlock": "feature:market", "order": 32},
	{"id": "factions", "section": "city", "title": "UI_MENU_FACTIONS", "icon": "", "scene": "res://src/ui/screens/FactionsScreen.tscn", "unlock": "feature:factions", "order": 33},
	{"id": "estate", "section": "city", "title": "UI_MENU_ESTATE", "icon": "", "scene": "res://src/ui/screens/EstateScreen.tscn", "unlock": "feature:estate", "order": 40},
	{"id": "guild", "section": "city", "title": "UI_MENU_GUILD", "icon": "", "scene": "res://src/ui/screens/GuildScreen.tscn", "unlock": "feature:mercenaries", "order": 50},
	{"id": "secrets", "section": "city", "title": "UI_MENU_SECRETS", "icon": "", "scene": "res://src/ui/screens/SecretsScreen.tscn", "unlock": "feature:secrets", "order": 51},
	{"id": "quests", "section": "summary", "title": "UI_MENU_QUESTS", "icon": "", "scene": "res://src/ui/screens/QuestScreen.tscn", "unlock": "", "order": 5},
	{"id": "prestige", "section": "progress", "title": "UI_MENU_PRESTIGE", "icon": "", "scene": "res://src/ui/screens/PrestigeScreen.tscn", "unlock": "feature:prestige", "hint_unlock": "feature:skill_prestige", "order": 20},
	{"id": "events", "section": "progress", "title": "UI_MENU_EVENTS", "icon": "", "scene": "res://src/ui/screens/EventsScreen.tscn", "unlock": "feature:crates", "order": 35},
	{"id": "compendium", "section": "progress", "title": "UI_MENU_COMPENDIUM", "icon": "", "scene": "res://src/ui/screens/CompendiumScreen.tscn", "unlock": "", "order": 30},
	{"id": "coop", "section": "progress", "title": "UI_MENU_COOP", "icon": "", "scene": "res://src/ui/screens/CoopScreen.tscn", "unlock": "feature:coop", "order": 36},
	{"id": "manual", "section": "progress", "title": "UI_MENU_MANUAL", "icon": "", "scene": "res://src/ui/screens/ManualScreen.tscn", "unlock": "", "order": 40},
	{"id": "coop_lobby", "section": "progress", "title": "UI_MENU_COOP_LOBBY", "icon": "", "scene": "res://src/ui/screens/CoopLobbyScreen.tscn", "unlock": "feature:coop", "menu": "coop_used", "order": 60},
	{"id": "coop_guild", "section": "progress", "title": "UI_MENU_COOP_GUILD", "icon": "", "scene": "res://src/ui/screens/CoopGuildScreen.tscn", "unlock": "feature:coop", "menu": "coop_used", "order": 61},
	{"id": "guide", "section": "progress", "title": "UI_MENU_GUIDE", "icon": "", "scene": "res://src/ui/screens/TutorialScreen.tscn", "unlock": "", "order": 41},
	{"id": "news", "section": "progress", "title": "UI_FB_NEWS_TITLE", "icon": "", "scene": "res://src/ui/screens/NewsScreen.tscn", "unlock": "", "order": 85},
	{"id": "settings", "section": "progress", "title": "UI_MENU_SETTINGS", "icon": "", "scene": "res://src/ui/screens/SettingsScreen.tscn", "unlock": "", "menu": "hidden", "order": 90},
]


## Tutte le voci (statiche + mansioni dai dati), ordinate per sezione e order.
## Le voci delle mansioni hanno "title_text" già tradotto (nome dai dati) al posto di "title".
static func entries(data: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in SCREENS:
		out.append(e)
	var dr: Object = data if data != null else _data_registry()
	if dr != null:
		for s in dr.table("skills"):
			if SKILL_GROUPS_HIDDEN.has(str(s.get("group", ""))):
				continue
			out.append({"id": "skill:" + str(s.id), "section": "skills", "title": "", "title_data": s.name,
				"icon": str(s.get("icon", "")), "scene": SKILL_SCENE_OVERRIDE.get(str(s.id), SKILL_SCENE), "unlock": "skill:" + str(s.id),
				"order": int(s.get("order", 0)), "params": {"skill": s.id}})
	var sec_index := {}
	for i in SECTIONS.size():
		sec_index[SECTIONS[i].id] = i
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = sec_index.get(a.section, 99)
		var sb: int = sec_index.get(b.section, 99)
		return sa < sb if sa != sb else int(a.order) < int(b.order))
	return out


## Id della voce di menù che apre la schermata di una mansione: quasi sempre «skill:<id>», ma l'Eroe e le Taglie hanno la
## propria schermata (voci «hero» e «bounty»). Pallino e pannello dei talenti si riferiscono a questa voce (rapporto 116).
const SKILL_MENU_OVERRIDE := {"hero": "hero", "bounty": "bounty"}


static func menu_id_for_skill(skill_id: String) -> String:
	return str(SKILL_MENU_OVERRIDE.get(skill_id, "skill:" + skill_id))


static func get_entry(id: String, data: Object = null) -> Dictionary:
	for e in entries(data):
		if e.id == id:
			return e
	return {}


## La voce è sbloccata per la partita in corso (o non richiede sblocchi).
static func is_unlocked(entry: Dictionary, unlocks: Array) -> bool:
	var tok: String = entry.get("unlock", "")
	return tok.is_empty() or unlocks.has(tok)


## La voce si può aprire: scena esistente e sbloccata.
static func is_available(entry: Dictionary, unlocks: Array) -> bool:
	return not str(entry.get("scene", "")).is_empty() and is_unlocked(entry, unlocks)


static func _data_registry() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("/root/DataRegistry") if tree != null else null
