
extends RefCounted
## Occhi e mani del bot NOVIZIO (QA 95): trova i pulsanti per testo, li preme con eventi mouse/tastiera veri
## (Viewport.push_input), e controlla la schermata (chiavi nude, testi nella lingua sbagliata, pulsanti coperti,
## schermate vuote). Nessuna logica di gioco qui: solo interfaccia.

const KEY_RE = "(?<![A-Za-z0-9_])[A-Z][A-Z0-9]{1,}(?:_[A-Z0-9]+){2,}(?![A-Za-z0-9_])"
## Parole che in italiano non compaiono mai in un testo inglese (e viceversa). Solo parole intere, minuscole.
const IT_WORDS = ["della", "delle", "degli", "nella", "nelle", "sono", "non", "che", "una", "per", "con", "hai", "puoi", "del", "dei", "alla", "dal", "più", "già", "tuo", "tua", "sul", "sulla"]
const EN_WORDS = ["the", "and", "you", "your", "with", "for", "of", "is", "are", "to", "this", "that", "from", "have", "will", "can"]

var tree: SceneTree
var _key_re = RegEx.new()


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	_key_re.compile(KEY_RE)


# ------------------------------------------------------------------ ricerca nodi

## Tutti i nodi sotto `n` (compresi i Window incorporati), in ordine di profondità.
func walk(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children(true):          # anche i figli interni (pulsanti OK/Annulla dei dialoghi)
		walk(c, out)
	return out


func visible_controls(n: Node) -> Array:
	var r: Array = []
	for x in walk(n):
		var c = x as Control
		if c != null and c.is_visible_in_tree():
			r.append(c)
	return r


func disp(c: Node) -> String:
	## Testo come lo vede il giocatore (tradotto).
	var t = ""
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is OptionButton:
		var ob = c as OptionButton
		return ob.atr(ob.get_item_text(ob.selected)) if ob.selected >= 0 else ""
	if c is Label:
		t = (c as Label).text
	elif c is BaseButton and "text" in c:
		t = str(c.get("text"))
	elif c is LineEdit:
		t = (c as LineEdit).text
	if t.is_empty():
		return ""
	return (c as Control).atr(t)


func tip(c: Control) -> String:
	return c.atr(c.tooltip_text) if not c.tooltip_text.is_empty() else ""


## Pulsanti visibili sotto `n` il cui testo (grezzo o tradotto) coincide con una delle chiavi/testi dati.
func find_buttons(n: Node, keys: Array, only_enabled: bool = false) -> Array:
	var r: Array = []
	var want: Array = []
	for k in keys:
		want.append(str(k).to_lower())
		want.append(tree.root.tr(str(k)).to_lower())
	for x in walk(n):
		var b = x as BaseButton
		if b == null or not b.is_visible_in_tree():
			continue
		if only_enabled and b.disabled:
			continue
		var raw = str(b.get("text")).to_lower() if "text" in b else ""
		if raw in want or disp(b).to_lower() in want or b.name.to_lower() in want:
			r.append(b)
	return r


func buttons(n: Node, only_enabled: bool = true) -> Array:
	var r: Array = []
	for c in visible_controls(n):
		var b = c as BaseButton
		if b != null and (not only_enabled or not b.disabled) and b.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			r.append(b)
	return r


func label_with(n: Node, text: String) -> Control:
	for c in visible_controls(n):
		if (c is Label or c is RichTextLabel) and disp(c) == text:
			return c
	return null


func open_windows() -> Array:
	## Finestre secondarie (ConfirmationDialog, AcceptDialog, popup) visibili.
	var r: Array = []
	for x in walk(tree.root):
		var w = x as Window
		if w != null and w != tree.root and w.visible:
			r.append(w)
	return r


# ------------------------------------------------------------------ controlli di testo

func bare_keys(text: String) -> Array:
	var r: Array = []
	for m in _key_re.search_all(text):
		r.append(m.get_string())
	return r


func foreign_words(text: String, locale: String) -> Array:
	## Parole dell'altra lingua dentro un testo (solo frasi di 4+ parole: i nomi propri e le sigle non contano).
	var words = text.to_lower().replace("\n", " ")
	var toks: Array = []
	for w in words.split(" ", false):
		var s = w.strip_edges()
		for ch in [",", ".", ";", ":", "(", ")", "!", "?", "«", "»", "\"", "·", "—"]:
			s = s.replace(ch, "")
		if not s.is_empty():
			toks.append(s)
	if toks.size() < 4:
		return []
	var bad: Array = []
	var list: Array = EN_WORDS if locale == "it" else IT_WORDS
	for tk in toks:
		if tk in list:
			bad.append(tk)
	# una sola parola ambigua ("per", "non"...) non basta: serve almeno 2 parole straniere distinte
	var uniq: Dictionary = {}
	for b in bad:
		uniq[b] = true
	return uniq.keys() if uniq.size() >= 2 else []


# ------------------------------------------------------------------ input veri

func viewport_of(c) -> Viewport:
	return c.get_viewport()


func center_of(b) -> Vector2:
	return b.get_global_transform_with_canvas() * (b.size * 0.5)


func in_view(b) -> bool:
	var vp = b.get_viewport()
	var r = b.get_global_rect()
	var vr = Rect2(Vector2.ZERO, vp.get_visible_rect().size)
	return vr.encloses(r.grow(-1.0)) or vr.has_point(center_of(b))


func scroll_to(b) -> void:
	var p = b.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(b)
		p = p.get_parent()


func mouse_move(vp: Viewport, pos: Vector2, via_input: bool = false) -> void:
	var ev = InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	if via_input:
		ev.position = tree.root.get_final_transform() * pos          # pixel della finestra (scala a 1080p)
		ev.global_position = ev.position
		Input.parse_input_event(ev)      # finestre incorporate (dialoghi): il percorso vero dall'evento della finestra principale
	else:
		vp.push_input(ev, true)


func mouse_click(vp: Viewport, pos: Vector2, via_input: bool = false) -> void:
	for pressed in [true, false]:
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		if via_input:
			ev.position = tree.root.get_final_transform() * pos
			ev.global_position = ev.position
			Input.parse_input_event(ev)
		else:
			vp.push_input(ev, true)


func key_press(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var ev = InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.shift_pressed = shift
		ev.ctrl_pressed = ctrl
		Input.parse_input_event(ev)


func hover_ok(vp, b) -> bool:
	if vp != tree.root:
		return true                          # finestra incorporata: il suo viewport non espone il controllo sotto il mouse
	var h = vp.gui_get_hovered_control()
	return h != null and (h == b or b.is_ancestor_of(h))


## Vero se il controllo è davvero visibile nella finestra: dentro la finestra e dentro ogni area di scorrimento/ritaglio
## che lo contiene (le righe di un elenco virtuale possono stare fuori dall'area visibile).
func really_visible(b) -> bool:
	if not b.is_visible_in_tree() or not in_view(b):
		return false
	var c = center_of(b)
	var p = b.get_parent()
	while p != null:
		var pc = p as Control
		if pc != null and (pc is ScrollContainer or pc.clip_contents):
			if not pc.get_global_rect().has_point(c):
				return false
		p = p.get_parent()
	return true


func type_text(le: LineEdit, text: String) -> void:
	for ch in text:
		for pressed in [true, false]:
			var ev = InputEventKey.new()
			ev.unicode = ch.unicode_at(0)
			ev.keycode = ch.to_upper().unicode_at(0) as Key
			ev.pressed = pressed
			Input.parse_input_event(ev)
