class_name ConstellationMap
extends Control
## Mappa stellare delle Costellazioni (docs/13 §3, docs/16): 5 rami, ogni nodo è una stella collegata alla precedente.
## Solo presentazione: legge PrestigeSystem, non cambia nulla. Il clic su un nodo emette `node_selected`.
## Stati di un nodo: bloccato (grigio) · acquistabile (anello luminoso) · posseduto (pieno, con il livello) ·
## al massimo (anello dorato) · dormiente (puntino vuoto: l'effetto si accende quando il sistema arriva).

signal node_selected(node_id: String)

const MARGIN_X := 150.0
const MARGIN_R := 30.0
const BAND_H := 62.0
const NODE_R := 15.0
const BRANCH_HUES: Array[float] = [0.12, 0.45, 0.0, 0.78, 0.58]     # Viandante, Mercante, Guerriero, Sorte, Custode

var _ps: PrestigeSystem
var _rows: Array = []                 # [{id, name, nodes: [node dict]}]
var _pos: Dictionary = {}             # node_id -> Vector2
var _selected: String = ""
var _pulse: float = 0.0
var _flash: Dictionary = {}           # node_id -> 0..1 (lampo dopo l'acquisto)
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(560, BAND_H * 5.0 + 20.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func setup(ps: PrestigeSystem) -> void:
	_ps = ps
	_rows.clear()
	var order: Array = []
	var by_id := {}
	for nd in ps.nodes():
		var cid := str(nd.constellation)
		if not by_id.has(cid):
			by_id[cid] = {"id": cid, "name": nd.constellation_name, "nodes": []}
			order.append(cid)
		by_id[cid].nodes.append(nd)
	for cid in order:
		by_id[cid].nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) < int(b.index))
		_rows.append(by_id[cid])
	custom_minimum_size = Vector2(560, BAND_H * maxf(1.0, float(_rows.size())) + 20.0)
	_start_pulse()
	queue_redraw()


func set_selected(node_id: String) -> void:
	_selected = node_id
	queue_redraw()


func selected() -> String:
	return _selected


## Lampo di soddisfazione sul nodo appena comprato (tween; con "riduci animazioni" solo un ridisegno).
func flash(node_id: String) -> void:
	if Settings.get_value("reduce_motion"):
		queue_redraw()
		return
	_flash[node_id] = 1.0
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_flash[node_id] = v
		queue_redraw(), 1.0, 0.0, 0.8)
	tw.tween_callback(func() -> void: _flash.erase(node_id))


func refresh() -> void:
	queue_redraw()


func node_position(node_id: String) -> Vector2:
	_layout()
	return _pos.get(node_id, Vector2.ZERO)


func _start_pulse() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if Settings.get_value("reduce_motion") or not is_inside_tree():
		_pulse = 0.0
		return
	_tween = create_tween().set_loops()
	_tween.tween_method(_set_pulse, 0.0, 1.0, 1.2)
	_tween.tween_method(_set_pulse, 1.0, 0.0, 1.2)


## Il battito è a gradini di 1/PULSE_STEPS (resoconto 100): ridisegna solo quando il gradino cambia (~10 Hz, non 60).
const PULSE_STEPS := 12.0


func _set_pulse(v: float) -> void:
	var q := roundf(v * PULSE_STEPS) / PULSE_STEPS
	if is_equal_approx(q, _pulse):
		return
	_pulse = q
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not _rows.is_empty():
		_start_pulse()


func _layout() -> void:
	_pos.clear()
	var w := maxf(size.x, custom_minimum_size.x)
	for r in _rows.size():
		var nodes: Array = _rows[r].nodes
		var n := maxi(1, nodes.size())
		var step := (w - MARGIN_X - MARGIN_R) / maxf(1.0, float(n - 1))
		var cy := 10.0 + BAND_H * (float(r) + 0.5)
		for i in nodes.size():
			var wob := -9.0 if i % 2 == 0 else 9.0
			_pos[str(nodes[i].id)] = Vector2(MARGIN_X + step * float(i), cy + wob)


func _draw() -> void:
	if _ps == null:
		return
	_layout()
	var font := ThemeDB.fallback_font
	for r in _rows.size():
		var hue: float = BRANCH_HUES[r % BRANCH_HUES.size()]
		var base := Color.from_hsv(hue, 0.55, 0.95)
		var cy := 10.0 + BAND_H * (float(r) + 0.5)
		# nome del ramo a capo su due righe (fino a 26 caratteri) invece di tagliarsi sotto il primo nodo
		var lw := MARGIN_X - 24.0
		var rname := Loc.t(_rows[r].name)
		var two := font.get_string_size(rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > lw
		draw_multiline_string(font, Vector2(8.0, cy - 3.0 if two else cy + 5.0), rname, HORIZONTAL_ALIGNMENT_LEFT, lw, 15, 2,
			base.lightened(0.15))
		var nodes: Array = _rows[r].nodes
		for i in nodes.size():
			var nid := str(nodes[i].id)
			var p: Vector2 = _pos[nid]
			if i > 0:
				var prev: Vector2 = _pos[str(nodes[i - 1].id)]
				var lit := _ps.node_level(str(nodes[i - 1].id)) >= 1 and _ps.node_level(nid) >= 1
				var open := _ps.node_level(str(nodes[i - 1].id)) >= 1
				var col := base if lit else (base.darkened(0.45) if open else Color(0.35, 0.37, 0.42))
				draw_line(prev, p, Color(col, 0.9 if lit else 0.55), 3.0 if lit else 1.5, true)
			_draw_node(nodes[i], p, base, font)


func _draw_node(nd: Dictionary, p: Vector2, base: Color, font: Font) -> void:
	var nid := str(nd.id)
	var lv := _ps.node_level(nid)
	var mx := _ps.node_max_level(nid)
	var maxed := mx >= 0 and lv >= mx
	var can := _ps.can_buy_node(nid).is_empty()
	var req: Variant = nd.get("requires")
	var reachable := req == null or _ps.node_level(str(req[0])) >= int(req[1])
	var fill := Color(0.16, 0.17, 0.2)
	var ring := Color(0.4, 0.42, 0.48)
	if lv > 0:
		fill = base.darkened(0.25)
		ring = base
	elif reachable:
		ring = base.darkened(0.2)
	if maxed:
		ring = Color(1.0, 0.82, 0.3)
	if can:
		var glow := 0.25 + 0.35 * _pulse
		draw_circle(p, NODE_R + 7.0, Color(base, glow))
	var fl: float = float(_flash.get(nid, 0.0))
	if fl > 0.0:
		draw_circle(p, NODE_R + 6.0 + 22.0 * (1.0 - fl), Color(1, 1, 1, 0.5 * fl))
	draw_circle(p, NODE_R, fill)
	draw_arc(p, NODE_R, 0.0, TAU, 28, ring, 2.5 if nid != _selected else 4.0, true)
	if nid == _selected:
		draw_arc(p, NODE_R + 5.0, 0.0, TAU, 28, Color(1, 1, 1, 0.85), 1.5, true)
	if lv > 0:
		draw_string(font, p + Vector2(-NODE_R, 5.0), str(lv), HORIZONTAL_ALIGNMENT_CENTER, NODE_R * 2.0, 14, Color.WHITE)
	elif _ps.is_dormant(nid):
		draw_arc(p, 4.0, 0.0, TAU, 12, Color(0.6, 0.62, 0.68), 1.0, true)
	else:
		draw_circle(p, 3.0, Color(ring, 0.8))


func _gui_input(event: InputEvent) -> void:
	if _ps == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := node_at(event.position)
		if not hit.is_empty():
			_selected = hit
			node_selected.emit(hit)
			queue_redraw()


## Id del nodo sotto il punto (coordinate locali) o "".
func node_at(point: Vector2) -> String:
	_layout()
	var best := ""
	var best_d := NODE_R + 8.0
	for nid in _pos:
		var d := point.distance_to(_pos[nid])
		if d <= best_d:
			best_d = d
			best = str(nid)
	return best
