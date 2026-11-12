class_name TutorialCatalog
extends RefCounted
## Catalogo dei passi del tutorial guidato (una riga per passo). Solo struttura: i testi stanno in
## localization/parts/tutorial.csv (UI_TUT_<ID>_T titolo, UI_TUT_<ID>_B testo), i numeri nei testi vengono dai dati
## (TutorialSystem.text_params). Nessun numero di bilanciamento qui.
##
## Campi di un passo:
##   id        unico, minuscolo (la chiave del testo è UI_TUT_<ID maiuscolo>_T / _B)
##   cat       gruppo nella checklist: guide | skills | adventure | city | progress
##   token     sblocco richiesto (token di GameState.data.unlocks); "" = nessuno
##   cond      condizione in più: [tipo, argomento] (vedi TutorialSystem.cond_ok)
##   after     id del passo che deve essere già visto
##   screen    schermata (id di ScreenRegistry) a cui il passo si riferisce
##   target    controllo da evidenziare (chiave di TutorialTargets, o lista in ordine di preferenza)
##   mode      "ack" = scheda con «Avanti» (predefinito) · "act" = avanza da solo quando il giocatore fa l'azione
##   done      per "act": {"screen": id} oppure {"action": id azione}
##   skip_if   condizioni che rendono inutile il passo (già fatto): lista di [tipo, argomento]
##   goto      true = porta il giocatore sulla schermata del passo prima di mostrarlo
##   prep      preparazione della schermata (es. "extras" apre il pannello Coda/Pozioni)
##   covers    token di sblocco la cui vecchia scheda da 3 righe è sostituita da questo passo
##
## Progetto di interfaccia (docs/ui_redesign/06 D29): le chiavi esistenti NON si rinominano né si tolgono (topbar:save,
## topbar:settings, topbar:pause, topbar:help, topbar:column, goal_go, sidebar, menu:<id>, content…). Chiavi nuove PREVISTE,
## che le fasi proprietarie marcheranno con TutorialTargets.mark (in F0 nessun passo le usa ancora):
##   topbar:bank (F2) · topbar:stardust (F2) · topbar:activity (F2) · rail (F3) · rail:log (F3) · rail:push (F14, pulsante Sabbia).
## `topbar:column` passerà in F3 al pulsante «apri cassetto» del binario. `target` può essere una LISTA in ordine di preferenza
## (es. ["topbar:quests", "menu:quests"]): è già supportato e serve per il ripiego sulla vecchia chiave finché la nuova non esiste.
## Un gruppo del menù laterale che contiene il bersaglio di un passo si apre da solo (F4), altrimenti il passo verrebbe saltato.

const CATS: PackedStringArray = ["guide", "skills", "adventure", "city", "progress"]

const STEPS: Array[Dictionary] = [
	# --- primi passi (percorso guidato della nuova partita)
	{"id": "g_sidebar", "cat": "guide", "target": "sidebar"},
	{"id": "g_open_pine", "cat": "guide", "token": "skill:woodcutting", "after": "g_sidebar", "mode": "act", "screen": "skill:woodcutting",
		"target": "menu:skill:woodcutting", "done": {"screen": "skill:woodcutting"}, "skip_if": [["quest_done", "main_c0_q1"]], "covers": "skill:woodcutting"},
	{"id": "g_pine", "cat": "guide", "token": "skill:woodcutting", "after": "g_open_pine", "mode": "act", "screen": "skill:woodcutting",
		"target": "action:wc_pine", "done": {"action": "wc_pine"}, "skip_if": [["quest_done", "main_c0_q1"]]},
	{"id": "g_quests", "cat": "guide", "after": "g_pine", "screen": "quests", "target": ["topbar:quests", "menu:quests"],
		"skip_if": [["quest_done", "main_c0_q1"]]},
	{"id": "g_open_copper", "cat": "guide", "token": "skill:mining", "cond": ["quest_reached", "main_c0_q2"], "after": "g_quests", "mode": "act",
		"screen": "skill:mining", "target": "menu:skill:mining", "done": {"screen": "skill:mining"}, "skip_if": [["quest_done", "main_c0_q2"]], "covers": "skill:mining"},
	{"id": "g_copper", "cat": "guide", "token": "skill:mining", "after": "g_open_copper", "mode": "act", "screen": "skill:mining",
		"target": "action:mine_copper", "done": {"action": "mine_copper"}, "skip_if": [["quest_done", "main_c0_q2"]]},
	{"id": "g_move", "cat": "guide", "after": "g_copper", "target": "sidebar"},
	{"id": "g_move2", "cat": "guide", "after": "g_move", "target": "topbar:settings"},
	# --- livello e maestria
	{"id": "b_level", "cat": "skills", "after": "g_move2", "screen": "skill:woodcutting", "target": "skill_header", "goto": true},
	{"id": "b_mastery", "cat": "skills", "after": "b_level", "screen": "skill:woodcutting", "target": "mastery:wc_pine", "goto": true},
	{"id": "b_compare", "cat": "skills", "after": "b_mastery", "screen": "skill:woodcutting", "target": "row:wc_pine", "goto": true},
	# --- mansioni
	{"id": "f_perks", "cat": "skills", "token": "feature:perks", "after": "g_move2", "screen": "skill:woodcutting", "target": "perk_btn", "covers": "feature:perks"},
	{"id": "f_queue", "cat": "skills", "cond": ["queue_slots", ""], "after": "g_move2", "screen": "skill:woodcutting", "target": ["extras_queue", "extras_toggle"], "prep": "extras"},
	{"id": "f_potions", "cat": "skills", "token": "skill:alchemy", "after": "g_move2", "screen": "skill:alchemy", "target": ["extras_potion", "extras_toggle"], "prep": "extras", "covers": "skill:alchemy"},
	{"id": "f_feast", "cat": "skills", "token": "skill:cooking", "after": "g_move2", "screen": "skill:cooking", "target": ["extras_feast", "extras_toggle"], "prep": "extras", "covers": "skill:cooking"},
	{"id": "f_farm", "cat": "skills", "token": "skill:farming", "after": "g_move2", "screen": "skill:farming", "target": "content", "covers": "skill:farming"},
	{"id": "f_keysmith", "cat": "skills", "token": "skill:keysmithing", "after": "g_move2", "screen": "skill:keysmithing", "target": "content", "covers": "skill:keysmithing"},
	# --- avventura
	# l'Eroe si apre INSIEME al Combattimento e il suo passo viene prima: si indossa e si assegna il cibo, poi si combatte
	{"id": "f_hero", "cat": "adventure", "token": "skill:hero", "after": "g_move2", "screen": "hero", "target": "content", "covers": "skill:hero"},
	{"id": "f_combat", "cat": "adventure", "token": "feature:combat", "after": "f_hero", "screen": "combat", "target": ["combat_start", "content"], "covers": "feature:combat"},
	{"id": "f_talents", "cat": "adventure", "token": "feature:talents", "after": "g_move2", "screen": "talents", "target": "content", "covers": "feature:talents"},
	{"id": "f_run", "cat": "adventure", "token": "feature:run", "after": "f_combat", "screen": "combat", "target": ["run_panel", "content"], "covers": "feature:run"},
	{"id": "f_bounty", "cat": "adventure", "token": "feature:bounties", "after": "g_move2", "screen": "bounty", "target": "content", "covers": "feature:bounties"},
	{"id": "f_dungeon", "cat": "adventure", "token": "dungeon:cursed_granary", "after": "f_combat", "screen": "dungeon", "target": "content", "covers": "dungeon:cursed_granary"},
	{"id": "f_worldboss", "cat": "adventure", "token": "feature:world_bosses", "after": "f_dungeon", "screen": "dungeon", "target": "content", "covers": "feature:world_bosses"},
	{"id": "f_rift", "cat": "adventure", "token": "feature:rift", "after": "f_dungeon", "screen": "dungeon", "target": "content", "covers": "feature:rift"},
	# --- città
	{"id": "f_bank", "cat": "city", "token": "chapter:1", "after": "g_move2", "screen": "bank", "target": "content"},
	{"id": "f_market", "cat": "city", "token": "feature:market", "after": "g_move2", "screen": "market", "target": "content", "covers": "feature:market"},
	{"id": "f_shop", "cat": "city", "token": "feature:market", "after": "f_market", "screen": "shop", "target": "content"},
	{"id": "f_orders", "cat": "city", "token": "feature:orders", "after": "g_move2", "screen": "orders", "target": "content", "covers": "feature:orders"},
	{"id": "f_crates", "cat": "city", "token": "feature:crates", "after": "g_move2", "screen": "vault_hall", "target": "content", "covers": "feature:crates"},
	{"id": "f_album", "cat": "city", "token": "feature:wardrobe", "after": "g_move2", "screen": "wardrobe", "target": "content", "covers": "feature:wardrobe"},
	{"id": "f_vault_tools", "cat": "city", "token": "feature:tradeup", "after": "f_crates", "screen": "vault_workshop", "target": "content", "covers": "feature:tradeup"},
	{"id": "f_estate", "cat": "city", "token": "feature:estate", "after": "g_move2", "screen": "estate", "target": "content", "covers": "feature:estate"},
	{"id": "f_apprentices", "cat": "city", "token": "feature:mercenaries", "cond": ["building", "academy"], "after": "f_estate", "screen": "guild", "target": "content"},
	{"id": "f_guild", "cat": "city", "token": "feature:mercenaries", "after": "g_move2", "screen": "guild", "target": "content", "covers": "feature:mercenaries"},
	{"id": "f_expeditions", "cat": "city", "token": "feature:expeditions", "after": "f_guild", "screen": "guild", "target": "content", "covers": "feature:expeditions"},
	# --- progresso
	{"id": "f_compendium", "cat": "progress", "token": "chapter:1", "after": "g_move2", "screen": "compendium", "target": "content"},
	{"id": "f_offline", "cat": "progress", "token": "chapter:1", "after": "g_move2", "target": "topbar:save"},
	{"id": "f_bank_expand", "cat": "city", "cond": ["bank_nearly_full", ""], "after": "g_move2", "screen": "bank", "target": ["bank_expand_btn", "content"], "goto": true},
	# F17: schede del Deposito, una volta sola quando lo Spazio usato supera constants.bank.ui.tabs_hint_used (soglia dai dati)
	{"id": "f_bank_tabs", "cat": "city", "cond": ["bank_used_over", "tabs_hint_used"], "after": "g_move2", "screen": "bank", "target": ["bank_tabs", "content"]},
	{"id": "f_push", "cat": "progress", "token": "feature:time_push", "after": "g_move2", "target": "rail:push", "covers": "feature:time_push"},
	{"id": "f_hourglass", "cat": "progress", "cond": ["item", "hourglass_1h"], "after": "g_move2", "screen": "bank", "target": "content"},
	{"id": "f_cozy", "cat": "progress", "token": "chapter:2", "after": "g_move2", "screen": "settings", "target": "content"},
	{"id": "f_prestige", "cat": "progress", "token": "feature:prestige", "after": "g_move2", "screen": "prestige", "target": "content", "covers": "feature:prestige"},
	{"id": "f_constellations", "cat": "progress", "token": "feature:constellations", "after": "f_prestige", "screen": "prestige", "target": "content", "covers": "feature:constellations"},
	{"id": "f_eras", "cat": "progress", "token": "feature:eras", "after": "f_prestige", "screen": "prestige", "target": "content", "covers": "feature:eras"},
	{"id": "f_coop", "cat": "progress", "token": "feature:coop", "after": "g_move2", "screen": "coop", "target": "content", "covers": "feature:coop"},
]


static func get_step(step_id: String) -> Dictionary:
	for s in STEPS:
		if s.id == step_id:
			return s
	return {}


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in STEPS:
		out.append(str(s.id))
	return out


static func title_key(step_id: String) -> String:
	return "UI_TUT_%s_T" % step_id.to_upper()


static func body_key(step_id: String) -> String:
	return "UI_TUT_%s_B" % step_id.to_upper()


static func targets_of(step: Dictionary) -> Array:
	var t: Variant = step.get("target", "")
	if t is Array:
		return t
	return [] if str(t).is_empty() else [str(t)]


## Token di sblocco le cui vecchie schede da 3 righe sono sostituite da un passo del tutorial guidato.
static func covered_tokens() -> PackedStringArray:
	var out := PackedStringArray()
	for s in STEPS:
		if s.has("covers"):
			out.append(str(s.covers))
	return out
