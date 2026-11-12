class_name InputBindings
extends RefCounted
## Comandi rimappabili (1.0, docs/review_1_0/03 punti 3 e 4): ogni scorciatoia è un'azione di InputMap («vf_<id>»), con i tasti
## predefiniti qui sotto e le scelte del giocatore in Settings["keybinds"]. Pura e statica: nessun nodo.
##   InputBindings.install()                    crea le azioni e applica le scelte salvate (lo fa Settings all'avvio)
##   InputBindings.matches(event, "bank")       l'evento è questa azione? (tasto: keycode + Ctrl/Alt, Maiusc solo se richiesto)
##   InputBindings.assign("bank", event, false) rimappa; ritorna {ok, conflicts}; con swap=true scambia con chi la usava
##   InputBindings.reset_all()                  predefiniti
## Salvato come {id: [{"t":"key","c":keycode,"ctrl":b,"alt":b,"shift":b} | {"t":"pad","b":joy_button}]}.
## «ui_accept» e «ui_cancel» di Godot seguono il pulsante di conferma e di indietro del controller.

const PREFIX := "vf_"
const KIND_KEY := "key"
const KIND_PAD := "pad"

## Voci: id, gruppo (per l'elenco), kind, testo (chiave) e predefiniti. keys = [[codice, ctrl, alt, shift], ...]; pad = pulsante.
## «n» = parametro del testo (voci del menù laterale). «fixed»: non rimappabile (si mostra ma non si cambia).
const ACTIONS: Array[Dictionary] = [
	{"id": "menu_1", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 1, "keys": [[KEY_1, false, false, false]]},
	{"id": "menu_2", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 2, "keys": [[KEY_2, false, false, false]]},
	{"id": "menu_3", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 3, "keys": [[KEY_3, false, false, false]]},
	{"id": "menu_4", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 4, "keys": [[KEY_4, false, false, false]]},
	{"id": "menu_5", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 5, "keys": [[KEY_5, false, false, false]]},
	{"id": "menu_6", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 6, "keys": [[KEY_6, false, false, false]]},
	{"id": "menu_7", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 7, "keys": [[KEY_7, false, false, false]]},
	{"id": "menu_8", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 8, "keys": [[KEY_8, false, false, false]]},
	{"id": "menu_9", "group": "nav", "kind": "key", "text": "UI_I10_ACT_MENU_N", "n": 9, "keys": [[KEY_9, false, false, false]]},
	{"id": "bank", "group": "screens", "kind": "key", "text": "UI_UIB_SC_BANK", "keys": [[KEY_B, false, false, false]]},
	{"id": "hero", "group": "screens", "kind": "key", "text": "UI_UIB_SC_HERO", "keys": [[KEY_C, false, false, false]]},
	{"id": "quests", "group": "screens", "kind": "key", "text": "UI_QG_SC_QUESTS", "keys": [[KEY_M, false, false, false]]},
	{"id": "manual", "group": "screens", "kind": "key", "text": "UI_UIB_SC_MANUAL", "keys": [[KEY_F1, false, false, false]]},
	{"id": "queue", "group": "screens", "kind": "key", "text": "UI_UIB_SC_QUEUE", "keys": [[KEY_Q, false, false, false]]},
	{"id": "column", "group": "game", "kind": "key", "text": "UI_UIB_SC_COLUMN", "keys": [[KEY_L, false, false, false]]},
	{"id": "pause", "group": "game", "kind": "key", "text": "UI_TOP_SC_PAUSE", "keys": [[KEY_P, false, false, false]]},
	{"id": "push", "group": "game", "kind": "key", "text": "UI_PUSH_SC", "keys": [[KEY_T, false, false, false]]},
	{"id": "reel", "group": "game", "kind": "key", "text": "UI_UIB_SC_REEL", "keys": [[KEY_SPACE, false, false, false]]},
	{"id": "search", "group": "game", "kind": "key", "text": "UI_UIB_SC_SEARCH", "keys": [[KEY_F, true, false, false]]},
	{"id": "escape", "group": "game", "kind": "key", "text": "UI_UIB_SC_ESCAPE", "keys": [[KEY_ESCAPE, false, false, false]], "fixed": true},
	{"id": "fullscreen", "group": "window", "kind": "key", "text": "UI_I10_ACT_FULLSCREEN", "keys": [[KEY_F11, false, false, false]]},
	{"id": "bank_tab_prev", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_TAB_PREV", "keys": [[KEY_BRACKETLEFT, false, false, false], [KEY_PAGEUP, true, false, false]]},
	{"id": "bank_tab_next", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_TAB_NEXT", "keys": [[KEY_BRACKETRIGHT, false, false, false], [KEY_PAGEDOWN, true, false, false]]},
	{"id": "bank_select", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_SELECT", "keys": [[KEY_S, false, false, false]]},
	{"id": "bank_sell", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_SELL", "keys": [[KEY_V, false, false, false]]},
	{"id": "bank_lock", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_LOCK", "keys": [[KEY_L, false, false, true]]},
	{"id": "bank_move", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_MOVE", "keys": [[KEY_M, false, false, true]]},
	{"id": "bank_sort", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_SORT", "keys": [[KEY_O, false, false, false]]},
	{"id": "bank_all", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_ALL", "keys": [[KEY_A, true, false, false]]},
	{"id": "bank_rename", "group": "bank", "kind": "key", "text": "UI_BANKG_SC_RENAME", "keys": [[KEY_F2, false, false, false]]},
	{"id": "bank_tab_left", "group": "bank", "kind": "key", "text": "UI_I10_ACT_BANK_TAB_LEFT", "keys": [[KEY_LEFT, false, true, false]]},
	{"id": "bank_tab_right", "group": "bank", "kind": "key", "text": "UI_I10_ACT_BANK_TAB_RIGHT", "keys": [[KEY_RIGHT, false, true, false]]},
	# --- controller: pulsanti dedicati
	{"id": "pad_confirm", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_CONFIRM", "pad": JOY_BUTTON_A},
	{"id": "pad_back", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_BACK", "pad": JOY_BUTTON_B},
	{"id": "pad_tab_prev", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_TAB_PREV", "pad": JOY_BUTTON_LEFT_SHOULDER},
	{"id": "pad_tab_next", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_TAB_NEXT", "pad": JOY_BUTTON_RIGHT_SHOULDER},
	{"id": "pad_menu", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_MENU", "pad": JOY_BUTTON_START},
	{"id": "pad_sand", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_SAND", "pad": JOY_BUTTON_X},
	{"id": "pad_context", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_CONTEXT", "pad": JOY_BUTTON_Y},
	{"id": "pad_bank", "group": "pad", "kind": "pad", "text": "UI_I10_PAD_BANK", "pad": JOY_BUTTON_BACK},
]

## Tasti che la navigazione dell'interfaccia usa già: non si assegnano ai comandi (si perderebbe il modo di muoversi).
const RESERVED_KEYS: Array[int] = [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ESCAPE,
	KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END]
const MODIFIER_KEYS: Array[int] = [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META, KEY_CAPSLOCK]


static func action_name(id: String) -> StringName:
	return StringName(PREFIX + id)


static func entry(id: String) -> Dictionary:
	for e in ACTIONS:
		if str(e.id) == id:
			return e
	return {}


static func ids_of_kind(kind: String) -> Array[String]:
	var out: Array[String] = []
	for e in ACTIONS:
		if str(e.kind) == kind:
			out.append(str(e.id))
	return out


# ------------------------------------------------------------------ eventi

static func key_event(code: int, ctrl: bool = false, alt: bool = false, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.shift_pressed = shift
	return ev


static func pad_event(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button as JoyButton
	return ev


static func default_events(id: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var e := entry(id)
	if e.is_empty():
		return out
	if str(e.kind) == KIND_PAD:
		out.append(pad_event(int(e.pad)))
	else:
		for k in e.keys:
			out.append(key_event(int(k[0]), bool(k[1]), bool(k[2]), bool(k[3])))
	return out


## Evento -> dizionario salvabile (o {} se non è né tasto né pulsante).
static func serialize(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"t": KIND_KEY, "c": int(k.keycode), "ctrl": k.ctrl_pressed, "alt": k.alt_pressed, "shift": k.shift_pressed}
	if ev is InputEventJoypadButton:
		return {"t": KIND_PAD, "b": int((ev as InputEventJoypadButton).button_index)}
	return {}


static func deserialize(d: Variant) -> InputEvent:
	if not (d is Dictionary):
		return null
	var t: Variant = d.get("t", "")
	if not (t is String):
		return null
	if t == KIND_KEY and _is_num(d.get("c")) and int(d.c) > 0:
		return key_event(int(d.c), _flag(d, "ctrl"), _flag(d, "alt"), _flag(d, "shift"))
	if t == KIND_PAD and _is_num(d.get("b")) and int(d.b) >= 0 and int(d.b) < int(JOY_BUTTON_SDL_MAX):
		return pad_event(int(d.b))
	return null


## Numero finito (int o float): un file modificato a mano può avere array, stringhe o NaN dove ci aspettiamo un numero.
static func _is_num(v: Variant) -> bool:
	if v is int:
		return true
	return v is float and is_finite(v) and absf(v) < 1.0e9


## Flag booleano del file: solo un vero bool vale; qualunque altro tipo (stringa «yes», numero) conta come falso.
static func _flag(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key, false)
	return v is bool and v


## Ripulisce i comandi letti da settings.cfg: tiene solo azioni note, liste di eventi che si decodificano e sono del
## tipo giusto (tasto/pulsante), senza ripetizioni dentro la stessa azione. Mai errori, qualunque sia il contenuto.
static func sanitize(saved: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (saved is Dictionary):
		return out
	for e in ACTIONS:
		var id := str(e.id)
		if bool(e.get("fixed", false)) or not saved.has(id) or not (saved[id] is Array):
			continue
		var evs: Array = []
		for d in saved[id]:
			var ev := deserialize(d)
			if ev == null or str(serialize(ev).t) != str(e.kind):
				continue
			var sd := serialize(ev)
			if not evs.has(sd):
				evs.append(sd)
		if not evs.is_empty():
			out[id] = evs
	return out


# ------------------------------------------------------------------ installazione

## Crea le azioni (se mancano) e applica i valori salvati. Idempotente.
static func install() -> void:
	apply_saved(Settings.get_value("keybinds"))


## Riporta ogni azione ai predefiniti e poi applica le scelte salvate (`saved` = Settings["keybinds"]).
static func apply_saved(saved: Variant) -> void:
	var map: Dictionary = saved if saved is Dictionary else {}
	for e in ACTIONS:
		var id := str(e.id)
		var a := action_name(id)
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
		InputMap.action_erase_events(a)
		var evs: Array[InputEvent] = []
		if map.has(id) and map[id] is Array and not bool(e.get("fixed", false)):
			for d in map[id]:
				var ev := deserialize(d)
				if ev != null and str(serialize(ev).t) == str(e.kind):
					evs.append(ev)
		if evs.is_empty():
			evs = default_events(id)
		for ev in evs:
			InputMap.action_add_event(a, ev)
	_sync_ui_actions()


## «ui_accept»/«ui_cancel»: tolgono i pulsanti del controller predefiniti di Godot e mettono quelli scelti (conferma/indietro).
static func _sync_ui_actions() -> void:
	_replace_pad(&"ui_accept", events_of("pad_confirm"))
	_replace_pad(&"ui_cancel", events_of("pad_back"))


static func _replace_pad(ui_action: StringName, pads: Array[InputEvent]) -> void:
	if not InputMap.has_action(ui_action):
		return
	for ev in InputMap.action_get_events(ui_action):
		if ev is InputEventJoypadButton:
			InputMap.action_erase_event(ui_action, ev)
	for p in pads:
		InputMap.action_add_event(ui_action, p.duplicate())


static func events_of(id: String) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var a := action_name(id)
	if InputMap.has_action(a):
		for ev in InputMap.action_get_events(a):
			out.append(ev)
	return out


# ------------------------------------------------------------------ riconoscimento

## L'evento è l'azione `id`? Tasto: stesso keycode, stessi Ctrl/Alt/Meta, e Maiusc uguale solo se il comando lo richiede
## (come prima: «B» vale anche con Maiusc, «Maiusc+L» no senza; con `strict_shift` Maiusc deve coincidere, come nel Deposito).
## Pulsante del controller: stesso pulsante. Non guarda pressed/echo.
static func matches(event: InputEvent, id: String, strict_shift: bool = false) -> bool:
	var a := action_name(id)
	if event == null or not InputMap.has_action(a):
		return false
	if event is InputEventKey:
		var k := event as InputEventKey
		var code: int = int(k.keycode) if int(k.keycode) != 0 else int(k.physical_keycode)
		for ev in InputMap.action_get_events(a):
			var b := ev as InputEventKey
			if b == null:
				continue
			if int(b.keycode) == code and b.ctrl_pressed == k.ctrl_pressed and b.alt_pressed == k.alt_pressed \
					and b.meta_pressed == k.meta_pressed \
					and ((b.shift_pressed == k.shift_pressed) if strict_shift else (not b.shift_pressed or k.shift_pressed)):
				return true
		return false
	if event is InputEventJoypadButton:
		var j := event as InputEventJoypadButton
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == j.button_index:
				return true
	return false


## Come matches, ma solo per eventi «premuti» (senza ripetizione).
static func pressed(event: InputEvent, id: String) -> bool:
	if event is InputEventKey:
		if not (event as InputEventKey).pressed or (event as InputEventKey).echo:
			return false
	elif event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return false
	else:
		return false
	return matches(event, id)


# ------------------------------------------------------------------ etichette

const _NAMES := {KEY_ESCAPE: "Esc", KEY_PAGEUP: "PgUp", KEY_PAGEDOWN: "PgDn", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓"}


static func key_text(ev: InputEventKey) -> String:
	var parts: PackedStringArray = []
	if ev.ctrl_pressed:
		parts.append("Ctrl")
	if ev.alt_pressed:
		parts.append("Alt")
	if ev.shift_pressed:
		parts.append("Maiusc" if str(Settings.get_value("locale")) == "it" else "Shift")
	var code := int(ev.keycode) if int(ev.keycode) != 0 else int(ev.physical_keycode)
	parts.append(_NAMES.get(code, OS.get_keycode_string(code as Key)))
	return " + ".join(parts)


## Testo dei tasti/pulsanti di un'azione, ad esempio «[  ·  Ctrl + PageUp». Vuoto se non ha eventi.
static func label_for(id: String, style: String = "xbox") -> String:
	var parts: PackedStringArray = []
	for ev in events_of(id):
		if ev is InputEventKey:
			parts.append(key_text(ev as InputEventKey))
		elif ev is InputEventJoypadButton:
			parts.append(GamepadGlyphs.button_label(int((ev as InputEventJoypadButton).button_index), style))
	return "  ·  ".join(parts)


static func is_default(id: String) -> bool:
	var cur: Array = []
	for ev in events_of(id):
		cur.append(serialize(ev))
	var dflt: Array = []
	for ev in default_events(id):
		dflt.append(serialize(ev))
	return cur == dflt


# ------------------------------------------------------------------ modifica

## Azioni che usano già `ev` (stesso tipo di comando, stessa combinazione), escluso `id`.
static func conflicts(id: String, ev: InputEvent) -> Array[String]:
	var out: Array[String] = []
	var want := serialize(ev)
	var kind := str(entry(id).get("kind", ""))
	for other in ids_of_kind(kind):
		if other == id:
			continue
		for oe in events_of(other):
			if serialize(oe) == want:
				out.append(other)
				break
	return out


## Un tasto che non si può assegnare (navigazione, solo modificatori). "" se va bene, altrimenti la chiave del motivo.
static func rejects(id: String, ev: InputEvent) -> String:
	var e := entry(id)
	if e.is_empty() or bool(e.get("fixed", false)):
		return "UI_I10_CTL_FIXED"
	if str(e.kind) == KIND_KEY:
		var k := ev as InputEventKey
		if k == null:
			return "UI_I10_CTL_NEED_KEY"
		var code := int(k.keycode)
		if MODIFIER_KEYS.has(code) or code == 0:
			return "UI_I10_CTL_NEED_KEY"
		if RESERVED_KEYS.has(code) and not k.ctrl_pressed and not k.alt_pressed:
			return "UI_I10_CTL_RESERVED"
	elif not (ev is InputEventJoypadButton):
		return "UI_I10_CTL_NEED_BUTTON"
	return ""


## Assegna `ev` all'azione `id` (sostituisce i suoi tasti). Se un'altra azione lo usa: senza `swap` non fa nulla e ritorna
## {ok:false, conflicts:[...]}; con `swap` quell'azione riceve i tasti che `id` aveva. Salva in Settings.
static func assign(id: String, ev: InputEvent, swap: bool = false) -> Dictionary:
	var why := rejects(id, ev)
	if not why.is_empty():
		return {"ok": false, "conflicts": [], "reason": why}
	var cl := conflicts(id, ev)
	if not cl.is_empty() and not swap:
		return {"ok": false, "conflicts": cl, "reason": "conflict"}
	var saved: Dictionary = (Settings.get_value("keybinds") as Dictionary).duplicate(true)
	var old: Array = []
	for oe in events_of(id):
		old.append(serialize(oe))
	for other in cl:
		saved[other] = old.duplicate(true)
	saved[id] = [serialize(ev)]
	Settings.set_value("keybinds", saved)
	return {"ok": true, "conflicts": cl}


## Rimette i tasti predefiniti di `id`. Se un altro comando li usa ora, lo scambio è automatico: quel comando riceve i
## tasti che `id` aveva (come «Scambia» in assign) e la UI avvisa con la lista `swapped`. Nessun doppione, mai.
## Ritorna {swapped: [id di comandi toccati]}.
static func reset_one(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty() or bool(e.get("fixed", false)):
		return {"swapped": []}
	var kind := str(e.kind)
	var want: Array = []
	for ev in default_events(id):
		want.append(serialize(ev))
	var mine: Array = []                                  # i tasti che id ha adesso, da dare a chi li perde
	for ev in events_of(id):
		mine.append(serialize(ev))
	var now: Dictionary = {}                              # stato effettivo di tutti i comandi dello stesso tipo
	for other in ids_of_kind(kind):
		var l: Array = []
		for ev in events_of(other):
			l.append(serialize(ev))
		now[other] = l
	var swapped: Array[String] = []
	var gift := mine.duplicate(true)
	for other in ids_of_kind(kind):
		if other == id:
			continue
		var keep: Array = []
		var lost := false
		for sd in now[other]:
			if want.has(sd):
				lost = true
			else:
				keep.append(sd)
		if not lost:
			continue
		for sd in gift:                                   # il primo che perde un tasto riceve quelli di id
			if not keep.has(sd):
				keep.append(sd)
		gift = []
		if keep.is_empty():
			keep = _default_serialized(other)
		now[other] = keep
		swapped.append(other)
	now[id] = want
	var saved: Dictionary = (Settings.get_value("keybinds") as Dictionary).duplicate(true)
	saved.erase(id)
	for other in swapped:
		saved[other] = now[other]
	if _clash(now):                                        # caso estremo (tre comandi sullo stesso tasto): si riparte dai predefiniti
		saved = {}
		swapped.clear()
	Settings.set_value("keybinds", saved)
	return {"swapped": swapped}


static func _default_serialized(id: String) -> Array:
	var out: Array = []
	for ev in default_events(id):
		out.append(serialize(ev))
	return out


## true se due comandi dello stesso tipo condividono una combinazione.
static func _clash(state: Dictionary) -> bool:
	var seen: Dictionary = {}
	for id in state:
		for sd in state[id]:
			var k := str(sd)
			if seen.has(k):
				return true
			seen[k] = id
	return false


static func reset_all() -> void:
	Settings.set_value("keybinds", {})
