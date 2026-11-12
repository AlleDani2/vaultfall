class_name FxAmbient
extends Control
## Vita ambientale di un edificio della Tenuta: ruota, fumo, luci alle finestre e scintille, DISEGNATE con quadratini
## sopra l'icona (nessuno sprite nuovo, il PNG dell'edificio non viene toccato). Si mette come figlio dell'icona.
## - `active` = l'edificio lavora (livello > 0): solo allora si anima e si ridisegna (a ~20 Hz, non a ogni frame);
## - Fx.level() 0 («Riduci animazioni»): nessun movimento, nessun disegno; 1 («Effetti ridotti»): più lento e con
##   la metà degli elementi; 2: pieno;
## - fermo quando l'icona non si vede (scheda cambiata, fuori dallo scorrimento): nessun costo.

const STEP_S := 0.05                    # ridisegno a 20 Hz
const MAX_ELEMENTS := 20                # tetto di quadratini per edificio

## Ricetta per edificio: elementi disegnati. Ogni voce: [tipo, x, y] con x, y = frazione dell'icona (0..1).
const RECIPES := {
	"cottage": [["smoke", 0.62, 0.12], ["light", 0.35, 0.62], ["light", 0.62, 0.55]],
	"sawmill": [["wheel", 0.30, 0.82], ["smoke", 0.70, 0.10], ["light", 0.55, 0.55]],
	"mine_shaft": [["lamp", 0.50, 0.58], ["dust", 0.25, 0.90], ["glint", 0.70, 0.78]],
	"fishery": [["wheel", 0.28, 0.80], ["glint", 0.72, 0.84], ["light", 0.60, 0.45]],
	"fields": [["vane", 0.50, 0.28], ["glint", 0.25, 0.80]],
	"ranch": [["smoke", 0.68, 0.14], ["light", 0.40, 0.60], ["glint", 0.75, 0.85]],
	"shopfront": [["lamp", 0.30, 0.50], ["lamp", 0.70, 0.50], ["glint", 0.50, 0.30]],
	"warehouse": [["light", 0.50, 0.55], ["dust", 0.30, 0.92]],
	"private_vault": [["glow", 0.50, 0.55], ["glint", 0.30, 0.35], ["glint", 0.72, 0.62]],
	"academy": [["light", 0.35, 0.50], ["light", 0.65, 0.50], ["glint", 0.50, 0.12]],
	"tavern": [["smoke", 0.60, 0.10], ["lamp", 0.38, 0.55], ["light", 0.66, 0.60]],
}
const DEFAULT_RECIPE := [["light", 0.5, 0.55], ["glint", 0.7, 0.3]]

const LIGHT := Color("ffd24a")
const LIGHT_D := Color("e8a23a")
const SMOKE_C := Color("b9b6ae")

var building_id: String = ""
var active: bool = false:
	set(v):
		if v == active:
			return
		active = v
		_update_processing()
var t: float = 0.0                       # tempo dell'animazione (secondi)
var drawn_elements: int = 0              # ultimo numero di quadratini disegnati (test e prestazioni)
var _acc: float = 0.0
var _seed: float = 0.0
var _dry: bool = false


static func attach(icon: Control, bid: String) -> FxAmbient:
	var a := FxAmbient.new()
	a.building_id = bid
	a._seed = float(abs(hash(bid)) % 997) / 997.0 * TAU
	icon.add_child(a)
	return a


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	name = "FxAmbient"
	set_process(false)


func _ready() -> void:
	visibility_changed.connect(_update_processing)
	_update_processing()


func recipe() -> Array:
	return RECIPES.get(building_id, DEFAULT_RECIPE)


## Vero se, adesso, qualcosa si muove (livello effetti > 0, edificio attivo, icona visibile).
func is_animating() -> bool:
	return active and Fx.level() > 0 and is_inside_tree() and is_visible_in_tree()


func _update_processing() -> void:
	var on := is_animating()
	set_process(on)
	if not on:
		drawn_elements = 0
		queue_redraw()


func _process(dt: float) -> void:
	if Fx.level() <= 0:
		_update_processing()
		return
	t += dt * (1.0 if Fx.level() >= 2 else 0.6)
	_acc += dt
	if _acc >= STEP_S:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	_render()


## Calcola gli elementi senza disegnare (test e prestazioni): ritorna quanti quadratini verrebbero disegnati.
func count_elements() -> int:
	_dry = true
	_render()
	_dry = false
	return drawn_elements


func _render() -> void:
	drawn_elements = 0
	if not is_animating():
		return
	var lv := Fx.level()
	var budget := MAX_ELEMENTS if lv >= 2 else MAX_ELEMENTS >> 1
	var i := 0
	for r in recipe():
		if lv < 2 and i % 2 == 1:                  # effetti ridotti: la metà degli elementi
			i += 1
			continue
		var p := Vector2(float(r[1]) * size.x, float(r[2]) * size.y)
		var n := 0
		match str(r[0]):
			"smoke": n = _smoke(p, budget - drawn_elements, float(i))
			"wheel": n = _wheel(p, budget - drawn_elements, false)
			"vane": n = _wheel(p, budget - drawn_elements, true)
			"light": n = _light(p, float(i), LIGHT)
			"lamp": n = _lamp(p, float(i))
			"glint": n = _glint(p, float(i))
			"glow": n = _glow(p)
			"dust": n = _dust(p, budget - drawn_elements, float(i))
		drawn_elements += n
		i += 1


func _sq(c: Vector2, s: float, col: Color) -> void:
	if _dry:
		return
	draw_rect(Rect2((c - Vector2(s, s) * 0.5).round(), Vector2(s, s)), col)


## Fumo: 3 sbuffi quadrati che salgono, si allargano e svaniscono, sfasati.
func _smoke(p: Vector2, room: int, k: float) -> int:
	var n := mini(3, room)
	for j in n:
		var u := fposmod(t * 0.45 + float(j) / 3.0 + k * 0.17 + _seed, 1.0)
		var c := p + Vector2(sin(u * 5.0 + k + float(j)) * 4.0, -u * 26.0)
		_sq(c, 4.0 + 5.0 * u, Color(0.1, 0.1, 0.12, 0.35 * (1.0 - u)))                    # ombra scura: si legge anche su fondi chiari
		_sq(c, 3.0 + 4.0 * u, Color(SMOKE_C.r, SMOKE_C.g, SMOKE_C.b, 0.95 * (1.0 - u)))
	return n


## Ruota (otto raggi che girano) oppure pala a quattro bracci (`vane`).
func _wheel(p: Vector2, room: int, vane: bool) -> int:
	var spokes := 4 if vane else 8
	if Fx.level() < 2:
		spokes = maxi(1, spokes >> 1)                  # effetti ridotti: metà raggi
	var r_max := 12.0 if vane else 7.0
	var n := 0
	var ang := t * (1.6 if vane else 2.4) + _seed
	for j in spokes:
		if n + (3 if vane else 1) > room:
			break
		var a := ang + TAU * float(j) / float(spokes)
		var d := Vector2(cos(a), sin(a))
		if vane:
			for q in 3:
				_sq(p + d * (5.0 + 4.0 * float(q)), 4.0, Color(0.1, 0.08, 0.06, 0.7))
				_sq(p + d * (5.0 + 4.0 * float(q)), 2.0, Color(0.97, 0.94, 0.85, 1.0))
			n += 3
		else:
			_sq(p + d * r_max, 5.0, Color(0.1, 0.08, 0.06, 0.75))
			_sq(p + d * r_max, 3.0, Color(1.0, 0.82, 0.5, 1.0))
			n += 1
	_sq(p, 5.0, Color(0.12, 0.09, 0.06, 0.9))
	_sq(p, 3.0, Color(0.9, 0.75, 0.45, 1.0))
	return n + 1


## Luce di finestra che «trema» (candela): due toni, vicina allo spegnimento ogni tanto.
func _light(p: Vector2, k: float, col: Color) -> int:
	var f := 0.65 + 0.35 * sin(t * 3.1 + k * 2.3 + _seed) * sin(t * 1.3 + k)
	_sq(p, 8.0, Color(col.r, col.g, col.b, 0.18 * clampf(f, 0.25, 1.0)))
	_sq(p, 4.0, Color(col.r, col.g, col.b, clampf(f, 0.3, 1.0)))
	return 2


## Lanterna: alone a due livelli che respira.
func _lamp(p: Vector2, k: float) -> int:
	var f := 0.5 + 0.5 * sin(t * 2.2 + k * 1.7 + _seed)
	_sq(p, 12.0, Color(LIGHT_D.r, LIGHT_D.g, LIGHT_D.b, 0.14 + 0.14 * f))
	_sq(p, 7.0, Color(LIGHT_D.r, LIGHT_D.g, LIGHT_D.b, 0.22 + 0.2 * f))
	_sq(p, 4.0, Color(LIGHT.r, LIGHT.g, LIGHT.b, 0.8 + 0.2 * f))
	return 3


## Scintilla a croce che compare e sparisce (un ciclo ogni ~2,4 s, sfasata).
func _glint(p: Vector2, k: float) -> int:
	var u := fposmod(t * 0.42 + k * 0.31 + _seed, 1.0)
	if u > 0.3:
		return 0
	var s := sin(u / 0.3 * PI)                 # 0 -> 1 -> 0
	var arm := 2.0 + 5.0 * s
	var col := Color(1.0, 0.97, 0.82, 1.0 * s)
	_sq(p, 3.0, col)
	_sq(p + Vector2(arm, 0), 3.0, col)
	_sq(p - Vector2(arm, 0), 3.0, col)
	_sq(p + Vector2(0, arm), 3.0, col)
	_sq(p - Vector2(0, arm), 3.0, col)
	return 5


## Bagliore del caveau: quadrato morbido che respira dietro la serratura.
func _glow(p: Vector2) -> int:
	var f := 0.5 + 0.5 * sin(t * 1.9 + _seed)
	_sq(p, 20.0 + 6.0 * f, Color(0.71, 0.55, 1.0, 0.14 + 0.1 * f))
	_sq(p, 10.0, Color(0.9, 0.8, 1.0, 0.4 + 0.3 * f))
	return 2


## Polvere che sale dal terreno (scavo, magazzino).
func _dust(p: Vector2, room: int, k: float) -> int:
	var n := mini(2, room)
	for j in n:
		var u := fposmod(t * 0.55 + float(j) * 0.5 + k * 0.2 + _seed, 1.0)
		_sq(p + Vector2(float(j) * 10.0 + u * 5.0, -u * 12.0), 3.0, Color(0.85, 0.76, 0.6, 0.9 * (1.0 - u)))
	return n
