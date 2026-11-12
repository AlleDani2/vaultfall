class_name ShortcutMap
extends RefCounted
## Scorciatoie da tastiera (G23, docs/16 §Accessibilità): tabella unica + risoluzione di un tasto in un'azione.
## Pura (nessun nodo): MainScreen passa l'evento e le voci del menù disponibili, riceve {"type": ..., ...} ed esegue.
## Anche il pannello «Scorciatoie» delle Impostazioni e i tooltip leggono da qui: una sola fonte di verità.
##
## Tasti (senza modificatori, tranne Ctrl+F):
##   1–9     le prime nove voci disponibili della barra laterale (Riepilogo e mansioni)
##   Ctrl+F  cerca (porta il cursore nel campo di ricerca della schermata, se c'è)
##   Esc     chiude la finestra aperta; senza finestre apre il menù di pausa (Riprendi, Salva adesso, Impostazioni, Menù principale, Esci)
##   Q       coda azioni      B Deposito      C Eroe      M Missioni      F1 Manuale
##   L       mostra/nascondi la colonna destra
##   T       Sabbia del Custode (F14): un clic; tenuto premuto = «tieni premuto» (lo gestisce PushButton)
##   P       Pausa/Riprendi (lo gestisce TopBar.PauseKey: qui solo la riga della tabella)
##   Spazio  salta il rullo delle Casse (gestito dalla Sala dei Caveau)

## Voci della tabella: id, tasti da mostrare e chiave del testo. «keys» è già un'etichetta di tasti (non si traduce).
const TABLE: Array[Dictionary] = [
	{"id": "menu", "keys": "1 – 9", "text": "UI_UIB_SC_MENU"},
	{"id": "search", "keys": "Ctrl + F", "text": "UI_UIB_SC_SEARCH"},
	{"id": "escape", "keys": "Esc", "text": "UI_UIB_SC_ESCAPE"},
	{"id": "queue", "keys": "Q", "text": "UI_UIB_SC_QUEUE"},
	{"id": "bank", "keys": "B", "text": "UI_UIB_SC_BANK"},
	{"id": "hero", "keys": "C", "text": "UI_UIB_SC_HERO"},
	{"id": "quests", "keys": "M", "text": "UI_QG_SC_QUESTS"},
	{"id": "manual", "keys": "F1", "text": "UI_UIB_SC_MANUAL"},
	{"id": "column", "keys": "L", "text": "UI_UIB_SC_COLUMN"},
	{"id": "pause", "keys": "P", "text": "UI_TOP_SC_PAUSE"},
	{"id": "push", "keys": "T", "text": "UI_PUSH_SC"},
	{"id": "reel", "keys": "Space", "text": "UI_UIB_SC_REEL"},
]

## Tasti LOCALI del Deposito (F17, docs/ui_redesign/02 §5.2 e 06 §3.9): valgono solo con il Deposito aperto e il fuoco dentro
## (BankScreen li legge con resolve_bank prima delle scorciatoie globali). Nessun tasto vende e nessun tasto elimina: «V» apre
## solo la modalità vendita (servono poi la selezione e l'anteprima a due passaggi); Canc non fa nulla. L e M da sole restano
## globali (cassetto, Missioni): nel Deposito si usano con Maiusc.
const BANK_TABLE: Array[Dictionary] = [
	{"act": "tab_prev", "keys": "[  ·  Ctrl + PgUp", "text": "UI_BANKG_SC_TAB_PREV"},
	{"act": "tab_next", "keys": "]  ·  Ctrl + PgDn", "text": "UI_BANKG_SC_TAB_NEXT"},
	{"act": "select", "keys": "S", "text": "UI_BANKG_SC_SELECT"},
	{"act": "sell_mode", "keys": "V", "text": "UI_BANKG_SC_SELL"},
	{"act": "lock", "keys": "Shift + L", "text": "UI_BANKG_SC_LOCK"},
	{"act": "move", "keys": "Shift + M", "text": "UI_BANKG_SC_MOVE"},
	{"act": "sort", "keys": "O", "text": "UI_BANKG_SC_SORT"},
	{"act": "select_all", "keys": "Ctrl + A", "text": "UI_BANKG_SC_ALL"},
	{"act": "rename", "keys": "F2", "text": "UI_BANKG_SC_RENAME"},
	{"act": "tab_left", "keys": "Alt + ←/→", "text": "UI_BANKG_SC_TAB_MOVE"},
]

const MENU_KEYS := 9
## Id della tabella → azione di InputBindings (quando diverso).
const ACT_OF := {"menu": "menu_1"}


## Etichetta dei tasti di una voce di TABLE come sono adesso (comandi cambiati compresi). «1 – 9» se i nove tasti del menù sono quelli di serie.
static func keys_label(id: String) -> String:
	if id == "menu":
		var all_default := true
		for i in range(1, MENU_KEYS + 1):
			all_default = all_default and InputBindings.is_default("menu_%d" % i)
		if all_default:
			return "1 – 9"
		var parts: PackedStringArray = []
		for i in range(1, MENU_KEYS + 1):
			parts.append(InputBindings.label_for("menu_%d" % i))
		return " ".join(parts)
	var l := InputBindings.label_for(str(ACT_OF.get(id, id)))
	if l.is_empty():
		for e in TABLE:
			if str(e.id) == id:
				return str(e.keys)
	return l


## Come keys_label, per le voci di BANK_TABLE (id azione senza prefisso: tab_prev, select, ...).
static func bank_keys_label(act: String) -> String:
	var map := {"tab_prev": "bank_tab_prev", "tab_next": "bank_tab_next", "select": "bank_select", "sell_mode": "bank_sell",
		"lock": "bank_lock", "move": "bank_move", "sort": "bank_sort", "select_all": "bank_all", "rename": "bank_rename"}
	if map.has(act):
		return InputBindings.label_for(str(map[act]))
	return ""


## Risolve un evento tastiera. `menu_ids` = id delle voci del menù disponibili, nell'ordine in cui compaiono.
## Ritorna {} se il tasto non è una scorciatoia. Tipi: screen {id}, search, escape, queue, column, push.
## I tasti vengono da InputBindings (rimappabili in Impostazioni → Comandi).
static func resolve(event: InputEvent, menu_ids: Array) -> Dictionary:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return {}
	if InputBindings.matches(k, "search"):
		return {"type": "search"}
	for i in MENU_KEYS:
		if InputBindings.matches(k, "menu_%d" % (i + 1)):
			return {"type": "screen", "id": str(menu_ids[i])} if i < menu_ids.size() else {}
	if InputBindings.matches(k, "escape"):
		return {"type": "escape"}
	if InputBindings.matches(k, "queue"):
		return {"type": "queue"}
	if InputBindings.matches(k, "column"):
		return {"type": "column"}
	if InputBindings.matches(k, "push"):
		return {"type": "push"}
	for id in ["bank", "hero", "manual", "quests"]:
		if InputBindings.matches(k, id):
			return {"type": "screen", "id": id}
	return {}


## Tasti locali del Deposito (BANK_TABLE): ritorna l'azione ("" se il tasto non è del Deposito). Pura e testabile.
## Azioni: tab_prev, tab_next, select, sell_mode, lock, move, sort, select_all, rename, tab_left, tab_right, search, escape.
## Qui Maiusc deve coincidere (Maiusc+O non è Ordina).
static func resolve_bank(event: InputEvent) -> String:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return ""
	var order := [["tab_prev", "bank_tab_prev"], ["tab_next", "bank_tab_next"], ["select_all", "bank_all"], ["search", "search"],
		["tab_left", "bank_tab_left"], ["tab_right", "bank_tab_right"], ["lock", "bank_lock"], ["move", "bank_move"],
		["select", "bank_select"], ["sell_mode", "bank_sell"], ["sort", "bank_sort"], ["rename", "bank_rename"], ["escape", "escape"]]
	for o in order:
		if InputBindings.matches(k, str(o[1]), true):
			return str(o[0])
	return ""


## Etichetta del tasto di una voce del menù (per i tooltip): «3», «B», «F1» o "" se non ne ha.
static func key_label_for(screen_id: String, menu_ids: Array) -> String:
	if ["bank", "hero", "manual", "quests"].has(screen_id):
		return InputBindings.label_for(screen_id)
	var i := menu_ids.find(screen_id)
	return InputBindings.label_for("menu_%d" % (i + 1)) if i >= 0 and i < MENU_KEYS else ""


## Destinazione del tasto Q (coda azioni): la mansione della prima voce in coda, altrimenti l'attività in corso,
## altrimenti la prima mansione sbloccata. {} se non c'è alcuna mansione.
static func queue_target() -> Dictionary:
	var sk := Game.system("skills") as SkillSystem
	if sk == null:
		return {}
	var skill := ""
	var q := Game.system("queue") as QueueSystem
	if q != null and q.size() > 0:
		skill = sk.skill_of(str(q.head().get("action", "")))
	if skill.is_empty():
		var aid := sk.current_action()
		skill = sk.skill_of(aid) if not aid.is_empty() else ""
	if skill.is_empty():
		for s in DataRegistry.table("skills"):
			# l'Orto ha una schermata sua, senza pannello coda; il combattimento non è una mansione da coda
			if sk.is_unlocked(str(s.id)) and str(s.id) != "farming" and not ScreenRegistry.SKILL_GROUPS_HIDDEN.has(str(s.get("group", ""))):
				skill = str(s.id)
				break
	if skill.is_empty():
		return {}
	return {"id": "skill:" + skill, "params": {"skill": skill, "focus": "queue"}}
