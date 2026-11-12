class_name LayoutChecker
extends RefCounted
## Controllo di layout (QA overflow, resoconto 107): dato un albero di Control e il rettangolo visibile della finestra,
## elenca i controlli VISIBILI il cui rettangolo globale esce dalla finestra. Sono esentati i contenuti dentro uno
## ScrollContainer (scorrono) e i nodi interni di RichTextLabel/ItemList/Tree/TextEdit (hanno scorrimento proprio).
## Usato da `scripts/layout_audit.gd` (catture e giro completo) e da `tests/test_layout_resolutions.gd`.

const TOL := 1.5


## Un trasgressore: {path, cls, rect, over: Vector2 (px oltre i bordi), text, name}.
static func scan(root_node: Node, view: Rect2, skip_overlay: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk(root_node, view, out, false, skip_overlay)
	return out


static func _walk(n: Node, view: Rect2, out: Array[Dictionary], clipped: bool, skip_overlay: bool) -> void:
	var ctl := n as Control
	if ctl != null:
		if not ctl.visible:
			return
		if skip_overlay and ctl.get_script() != null and str((ctl.get_script() as Script).get_global_name()) == "OverlayHost":
			return
		if not clipped and (ctl.scale != Vector2.ONE or ctl.rotation != 0.0):
			clipped = true             # controllo animato (pulsazione, rimbalzo): il suo rettangolo globale è provvisorio
		if not clipped and ctl.size.x > 0.5 and ctl.size.y > 0.5:
			var r := ctl.get_global_rect()
			var over := Vector2(maxf(0.0, r.end.x - view.end.x), maxf(0.0, r.end.y - view.end.y))
			var under := Vector2(maxf(0.0, view.position.x - r.position.x), maxf(0.0, view.position.y - r.position.y))
			if over.x > TOL or over.y > TOL or under.x > TOL or under.y > TOL:
				var txt := ""
				if ctl is Button or ctl is Label:
					txt = str(ctl.get("text")).left(28)
				out.append({"path": str(ctl.get_path()), "cls": ctl.get_class(), "rect": r, "over": over + under, "text": txt,
					"name": str(ctl.name)})
		if ctl is ScrollContainer:
			# dentro uno scorrimento il contenuto può eccedere solo lungo l'asse che scorre davvero; sull'altro asse deve
			# stare nel suo rettangolo (altrimenti verrebbe tagliato senza poterlo raggiungere). Lo scorrimento
			# orizzontale di ScreenScroll è solo un ripiego: lì la larghezza conta come vincolo.
			var sc := ctl as ScrollContainer
			var sr := sc.get_global_rect()
			var v := view
			var inf := 1.0e6
			if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED or sc.name == &"ScreenScroll":
				v.position.x = maxf(view.position.x, sr.position.x)
				v.end.x = minf(view.end.x, sr.end.x)
			else:
				v.position.x = -inf
				v.end.x = inf
			if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				v.position.y = maxf(view.position.y, sr.position.y)
				v.end.y = minf(view.end.y, sr.end.y)
			else:
				v.position.y = -inf
				v.end.y = inf
			view = v
		elif ctl.clip_contents or ctl is RichTextLabel or ctl is ItemList or ctl is Tree or ctl is TextEdit:
			clipped = true
	for c in n.get_children():
		if c is Window:
			continue
		_walk(c, view, out, clipped, skip_overlay)


## ScrollContainer visibili il cui contenuto è più largo dell'area (servirebbe scorrere in orizzontale): [{name, content, page, path}].
## Sono i punti in cui una schermata è troppo larga per la finestra e ha solo uno scorrimento di ripiego.
static func wide_scrolls(root_node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in root_node.find_children("*", "ScrollContainer", true, false):
		var sc := n as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		var kid_w := 0.0
		for c in sc.get_children():
			if c is Control and (c as Control).visible and not (c is ScrollBar):
				kid_w = maxf(kid_w, (c as Control).get_combined_minimum_size().x)
		if kid_w > sc.size.x + 1.0:
			out.append({"hidden": sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "name": str(sc.name), "content": int(kid_w), "page": int(sc.size.x), "path": str(sc.get_path())})
	return out


## Riassunto: gli N peggiori per sbordo (px), una riga ciascuno.
static func worst(list: Array[Dictionary], n: int = 6) -> PackedStringArray:
	var arr := list.duplicate()
	arr.sort_custom(func(a, b): return maxf(a.over.x, a.over.y) > maxf(b.over.x, b.over.y))
	var lines := PackedStringArray()
	for i in mini(n, arr.size()):
		var d: Dictionary = arr[i]
		var rr: Rect2 = d.rect
		lines.append("    %s %s «%s» sbordo=(%d,%d) rect=(%d,%d %dx%d)" % [d.cls, d.name, d.text, int(d.over.x), int(d.over.y), int(rr.position.x), int(rr.position.y), int(rr.size.x), int(rr.size.y)])
	return lines
