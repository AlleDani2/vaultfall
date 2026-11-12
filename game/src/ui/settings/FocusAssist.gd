class_name FocusAssist
extends RefCounted
## Aiuti per la navigazione col controller e da tastiera (1.0, docs/review_1_0/03 punto 3): con nessun controllo a fuoco
## la prima pressione di una direzione/conferma porta il fuoco sul primo controllo utile della finestra in primo piano
## (dialogo, menù di pausa, finestra di MainScreen o schermata). Pura sugli alberi di nodi: testabile.


## Gruppo delle schermate che sanno da sole dove mettere il fuoco (hanno `focus_entry_point() -> bool`): MainScreen.
const ENTRY_GROUP := &"focus_entry"


## Il controllo può ricevere il fuoco adesso?
static func is_focusable(c: Control) -> bool:
	if c == null or c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree():
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	if c is LineEdit and not (c as LineEdit).editable:
		return false
	return true


## Primo controllo a fuoco possibile sotto `root` (in ordine di albero), saltando i rami nascosti. null se non c'è.
static func first_focusable(root: Node) -> Control:
	if root == null:
		return null
	if root is CanvasItem and not (root as CanvasItem).visible:
		return null
	if root is Control and is_focusable(root as Control):
		return root as Control
	for c in root.get_children():
		if c is Window:
			continue
		var f := first_focusable(c)
		if f != null:
			return f
	return null


## Radici in cui cercare, dalla più in primo piano: finestre (dialoghi) visibili, menù di pausa, finestra modale di MainScreen,
## poi la scena corrente. `tree` = SceneTree.
static func focus_roots(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	var root := tree.root
	for w in _visible_windows(root):
		out.append(w)
	for c in root.get_children():
		if c is PauseMenu:
			out.append(c)
		elif c is CanvasLayer and not (c is PauseMenu) and c.has_meta("focus_root"):
			out.append(c)
	for n in tree.get_nodes_in_group(ENTRY_GROUP):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree() and n.has_method("focus_entry_point"):
			out.append(n)
	var scene := tree.current_scene
	if scene != null and not out.has(scene):
		out.append(scene)
	return out


static func _visible_windows(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		if c is Window and (c as Window).visible and (c as Window).get_parent() != null:
			out.append_array(_visible_windows(c))
			out.append(c)
		elif not (c is Window):
			out.append_array(_visible_windows(c))
	return out


## Porta il fuoco sul primo controllo utile. true se l'ha dato. Se la schermata offre un suo punto d'ingresso
## (`focus_entry_point`) si usa quello.
static func ensure_focus(tree: SceneTree) -> bool:
	var roots := focus_roots(tree)
	if roots.is_empty():
		return false
	var vp := roots[0].get_viewport()
	if vp == null or vp.gui_get_focus_owner() != null:
		return false
	for r in roots:
		if r.has_method("focus_entry_point"):
			if bool(r.call("focus_entry_point")):
				return true
			continue
		var f := first_focusable(r)
		if f != null:
			f.grab_focus()
			return true
	return false
