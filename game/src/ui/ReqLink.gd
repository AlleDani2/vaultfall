class_name ReqLink
extends RefCounted
## «Nessun vicolo cieco» (docs/16 §1.2, G37): ogni requisito mancante (livello, oggetto, edificio, sblocco) porta a dove
## si ottiene. Qui vive la logica comune: dato un requisito ritorna il BERSAGLIO {screen, params, hint} (vuoto se non
## esiste una strada), `link()` costruisce il testo cliccabile e `go()` apre la schermata giusta, già filtrata, tramite
## EventBus.screen_requested (MainScreen.show_screen). Solo presentazione: legge DataRegistry, GameState e i sistemi.
##
## Parametri riconosciuti dalle schermate (tutti facoltativi, ignorati se la schermata non li conosce):
##   SkillScreen   {"skill": id, "produces": item_id}  solo le azioni che producono l'oggetto
##                 {"skill": id, "filter": "available"} solo le azioni avviabili adesso (livello e ingredienti)
##                 {"skill": id, "focus": "queue"}      apre e porta in vista la coda azioni
##   EstateScreen  {"building": id}                     porta in vista e illumina la carta dell'edificio
##   QuestScreen   {"quest": id}                        porta in vista e illumina la missione
##   VaultWorkshop {"tab": id}                          (già esistente) scheda della Bottega

const LINK_COLOR := Color(0.93, 0.76, 0.42)

static var _producers: Dictionary = {}       # item_id -> Array[String] (id mansione, in ordine di dati)
static var _avail: Dictionary = {}           # schermata -> disponibile (cache, vedi _available)
static var _avail_n: int = -1


## Mansioni che producono l'oggetto (azioni con outputs o raccolti dell'orto), in ordine.
static func producers_of(item_id: String) -> Array:
	if _producers.is_empty():
		var acts: Dictionary = DataRegistry.all_actions()
		for aid in acts:
			var a: Dictionary = acts[aid]
			var sk := str(a.get("skill", ""))
			for o in a.get("outputs", []):
				if o is Dictionary:
					var it := str(o.get("item", ""))
					if it.is_empty():
						continue
					if not _producers.has(it):
						_producers[it] = []
					if not (_producers[it] as Array).has(sk):
						(_producers[it] as Array).append(sk)
		if _producers.is_empty():
			_producers["_"] = []             # dati assenti (test): evita di riscansionare a ogni chiamata
	return _producers.get(item_id, [])


static func _unlocks() -> Array:
	return GameState.data.get("unlocks", [])


static func _available(screen_id: String) -> bool:
	var un := _unlocks()
	if un.size() != _avail_n:                 # la cache vale finché gli sblocchi non cambiano (get_entry ricostruisce l'elenco)
		_avail_n = un.size()
		_avail.clear()
	if not _avail.has(screen_id):
		var e := ScreenRegistry.get_entry(screen_id)
		_avail[screen_id] = not e.is_empty() and ScreenRegistry.is_available(e, un)
	return bool(_avail[screen_id])


## Svuota le cache (test, cambio partita).
static func reset_cache() -> void:
	_avail.clear()
	_avail_n = -1
	_producers.clear()


static func _t(screen: String, params: Dictionary, hint: String = "") -> Dictionary:
	return {"screen": screen, "params": params, "hint": hint}


## Dove si ottiene un oggetto: la mansione sbloccata che lo produce (filtrata su di lui); se nessuna è sbloccata, la
## missione che sblocca la prima; altrimenti il Mercato (se vendibile e sbloccato). {} se non c'è strada.
static func target_for_item(item_id: String) -> Dictionary:
	var first_locked := ""
	for sk in producers_of(item_id):
		if _available("skill:" + str(sk)):
			return _t("skill:" + str(sk), {"skill": sk, "produces": item_id}, "UI_UIB_REQ_HINT_PRODUCE")
		if first_locked.is_empty():
			first_locked = str(sk)
	if not first_locked.is_empty():
		var t := target_for_token("skill:" + first_locked)
		if not t.is_empty():
			return t
	if _available("market") and bool(DataRegistry.item(item_id).get("tradeable", false)):
		return _t("market", {"item": item_id}, "UI_UIB_REQ_HINT_BUY")
	return {}


## Dove si ottiene uno sblocco (token): la missione che lo concede; per un edificio la Tenuta.
static func target_for_token(token: String) -> Dictionary:
	if token.begins_with("building:") and _available("estate"):
		return _t("estate", {"building": token.substr(9)}, "UI_UIB_REQ_HINT_BUILD")
	var qid := UnlockSystem.quest_for_token(token, DataRegistry)
	if not qid.is_empty() and _available("quests"):
		return _t("quests", {"quest": qid}, "UI_UIB_REQ_HINT_QUEST")
	return {}


## Missione richiesta (edifici e funzioni sbloccati da una missione).
static func target_for_quest(quest_id: String) -> Dictionary:
	if not quest_id.is_empty() and _available("quests"):
		return _t("quests", {"quest": quest_id}, "UI_UIB_REQ_HINT_QUEST")
	return {}


## Livello mancante in una mansione: la sua schermata, filtrata sulle azioni che si possono già fare (per salire di livello).
static func target_for_level(skill_id: String) -> Dictionary:
	if _available("skill:" + skill_id):
		return _t("skill:" + skill_id, {"skill": skill_id, "filter": "available"}, "UI_UIB_REQ_HINT_LEVEL")
	return target_for_token("skill:" + skill_id)


## Edificio da costruire/migliorare.
static func target_for_building(building_id: String) -> Dictionary:
	if _available("estate"):
		return _t("estate", {"building": building_id}, "UI_UIB_REQ_HINT_BUILD")
	return {}


## Apre la schermata del bersaglio. false se il bersaglio è vuoto.
static func go(target: Dictionary) -> bool:
	if target.is_empty():
		return false
	EventBus.screen_requested.emit(str(target.screen), target.get("params", {}))
	return true


## Testo cliccabile (già tradotto) che porta al bersaglio: un Button piatto color ottone, allineato a sinistra e troncato se
## troppo lungo (non allarga la schermata). Con bersaglio vuoto ritorna un'etichetta normale: mai un link morto.
static func link(text: String, target: Dictionary) -> Control:
	if target.is_empty():
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.text = text
		return l
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true                                   # un testo lungo non allarga mai la schermata: si tronca (il tooltip lo ripete)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, LINK_COLOR)
	var hint := tr_hint(target)
	b.tooltip_text = text if hint.is_empty() else text + "\n" + hint
	b.pressed.connect(go.bind(target))
	return b


## Suggerimento del bersaglio («Clic per aprire la mansione che lo produce»).
static func tr_hint(target: Dictionary) -> String:
	var k := str(target.get("hint", ""))
	return str(TranslationServer.translate(k)) if not k.is_empty() else ""


## BBCode cliccabile per i RichTextLabel: il chiamante collega `meta_clicked` a `meta_go`. Meta = "req:<screen>|<json params>".
static func bbcode(text: String, target: Dictionary, color: String = "#edc26b") -> String:
	if target.is_empty():
		return text
	var meta := "req:%s|%s" % [target.screen, JSON.stringify(target.get("params", {}))]
	return "[url=%s][u][color=%s]%s[/color][/u][/url]" % [meta, color, text]


## Gestore di `meta_clicked` per i RichTextLabel (ignora i meta che non iniziano con «req:»).
static func meta_go(meta: Variant) -> void:
	var s := str(meta)
	if not s.begins_with("req:"):
		return
	var parts := s.substr(4).split("|", true, 1)
	var params: Variant = JSON.parse_string(parts[1]) if parts.size() > 1 else {}
	EventBus.screen_requested.emit(parts[0], params if params is Dictionary else {})


## Porta in vista un controllo dentro il ScrollContainer che lo contiene e lo illumina (nessun effetto con «riduci animazioni»).
static func reveal(target: Variant) -> void:
	if target == null or not is_instance_valid(target):       # chiamata differita: il nodo può essere già stato tolto
		return
	var node := target as Control
	var tree := node.get_tree()
	if tree == null:
		return
	await tree.process_frame                                   # il layout (altezze delle carte) è pronto solo dopo qualche frame
	await tree.process_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var p := node.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p != null:
		(p as ScrollContainer).ensure_control_visible(node)
	if Fx.enabled():
		_glow(node)


static func _glow(target: Variant) -> void:
	if target != null and is_instance_valid(target) and (target as Control).is_inside_tree():
		Fx.glow_pulse(target as Control, FxPalette.GOLD, 2, 0.5, 0.6)
