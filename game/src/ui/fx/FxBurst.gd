class_name FxBurst
extends Node
## Scoppi di particelle a pixel quadrati con un POOL fisso di CPUParticles2D (Compatibility: niente GPUParticles).
## - al massimo MAX_EMITTERS emettitori e MAX_PARTICLES particelle vive in tutto: oltre, lo scoppio nuovo si scarta
##   (priorità alta: ruba il più vecchio);
## - i nodi si creano una volta sola (a pigrizia, fino al massimo) e poi si riusano: nessuna allocazione per frame;
## - le particelle sono quadrati nitidi (texture 2x2 bianca, filtro nearest), colori da pochi toni (rampa a gradini);
## - l'intensità segue Fx.level(): pieni = 1, ridotti = ~0,4, «riduci animazioni» = nessuno scoppio.

const MAX_EMITTERS := 16
const MAX_PARTICLES := 420
const SIZE_MULT := 1.5         # i preset sono scritti in «mezzi pixel»: x1,5 li rende quadrati ben leggibili

## Parametri dei preset. dir: direzione base (y negativo = su), spread: apertura in gradi (180 = a raggiera),
## v: velocità min/max px/s, g: gravità, damp: smorzamento, sc: scala min/max (1 = 2 px), cols: toni a gradini,
## fade/shrink: sfuma / rimpicciolisce, rect: emissione su un rettangolo (coriandoli).
const PRESETS := {
	"spark": {"n": 12, "life": 0.38, "dir": Vector2(0, -1), "spread": 180.0, "v": [90.0, 230.0], "g": Vector2(0, 380),
		"damp": [40.0, 90.0], "sc": [1.0, 2.0], "cols": [FxPalette.WHITE, FxPalette.GOLD, FxPalette.AMBER], "shrink": true},
	"impact": {"n": 8, "life": 0.3, "dir": Vector2(0, -1), "spread": 180.0, "v": [60.0, 150.0], "g": Vector2(0, 220),
		"damp": [30.0, 60.0], "sc": [1.0, 1.8], "cols": [FxPalette.WHITE, FxPalette.CREAM, FxPalette.STONE], "shrink": true},
	"shard": {"n": 16, "life": 0.75, "dir": Vector2(0, -1), "spread": 180.0, "v": [70.0, 220.0], "g": Vector2(0, 520),
		"damp": [20.0, 50.0], "sc": [1.5, 3.0], "cols": [FxPalette.STONE, FxPalette.SMOKE, FxPalette.CREAM], "shrink": true},
	"star": {"n": 28, "life": 0.95, "dir": Vector2(0, -1), "spread": 180.0, "v": [120.0, 320.0], "g": Vector2(0, 70),
		"damp": [160.0, 260.0], "sc": [1.0, 2.6], "cols": [FxPalette.GOLD, FxPalette.WHITE, FxPalette.AMBER], "fade": true},
	"confetti": {"n": 56, "life": 1.7, "dir": Vector2(0, -1), "spread": 70.0, "v": [160.0, 420.0], "g": Vector2(0, 520),
		"damp": [60.0, 120.0], "sc": [1.4, 2.6], "cols": [FxPalette.GOLD, FxPalette.RED_L, FxPalette.BLUE, FxPalette.GREEN, FxPalette.VIOLET, FxPalette.WHITE],
		"fade": true},
	"chip": {"n": 10, "life": 0.6, "dir": Vector2(0, -1), "spread": 70.0, "v": [80.0, 190.0], "g": Vector2(0, 520),
		"damp": [0.0, 20.0], "sc": [1.6, 2.6], "cols": [FxPalette.BROWN, FxPalette.BROWN_D, FxPalette.CREAM], "fade": true},
	"forge": {"n": 14, "life": 0.6, "dir": Vector2(0, -1), "spread": 55.0, "v": [80.0, 230.0], "g": Vector2(0, 320),
		"damp": [10.0, 40.0], "sc": [1.0, 1.8], "cols": [FxPalette.GOLD, FxPalette.AMBER, FxPalette.ORANGE, FxPalette.WHITE], "shrink": true},
	"ember": {"n": 6, "life": 1.0, "dir": Vector2(0, -1), "spread": 30.0, "v": [20.0, 60.0], "g": Vector2(0, -40),
		"damp": [0.0, 10.0], "sc": [1.0, 1.6], "cols": [FxPalette.ORANGE, FxPalette.AMBER], "fade": true},
	"bubble": {"n": 8, "life": 1.1, "dir": Vector2(0, -1), "spread": 25.0, "v": [30.0, 75.0], "g": Vector2(0, -30),
		"damp": [0.0, 10.0], "sc": [1.6, 2.6], "cols": [FxPalette.BLUE, FxPalette.WHITE, FxPalette.TEAL], "fade": true},
	"leaf": {"n": 8, "life": 1.2, "dir": Vector2(0, -1), "spread": 80.0, "v": [40.0, 110.0], "g": Vector2(0, 110),
		"damp": [20.0, 40.0], "sc": [1.6, 2.6], "cols": [FxPalette.GREEN, FxPalette.GREEN_D, FxPalette.GOLD_D], "fade": true},
	"steam": {"n": 8, "life": 1.2, "dir": Vector2(0, -1), "spread": 20.0, "v": [25.0, 60.0], "g": Vector2(0, -25),
		"damp": [0.0, 10.0], "sc": [2.6, 4.0], "cols": [FxPalette.WHITE, FxPalette.CREAM], "fade": true, "alpha": 0.55},
	"dust": {"n": 8, "life": 0.7, "dir": Vector2(0, -1), "spread": 180.0, "v": [40.0, 110.0], "g": Vector2(0, 80),
		"damp": [30.0, 60.0], "sc": [1.6, 2.4], "cols": [Color("c8a878"), Color("a58d6a"), FxPalette.CREAM], "fade": true, "alpha": 0.8},
	"glint": {"n": 5, "life": 0.5, "dir": Vector2(0, -1), "spread": 180.0, "v": [10.0, 50.0], "g": Vector2(0, 0),
		"damp": [10.0, 30.0], "sc": [1.0, 1.8], "cols": [FxPalette.WHITE, Color("c8f0ff")], "shrink": true},
	"coin": {"n": 6, "life": 0.6, "dir": Vector2(0, -1), "spread": 60.0, "v": [80.0, 190.0], "g": Vector2(0, 520),
		"damp": [0.0, 20.0], "sc": [1.4, 2.0], "cols": [FxPalette.GOLD, FxPalette.GOLD_D, FxPalette.WHITE], "fade": true},
	"heal": {"n": 10, "life": 1.0, "dir": Vector2(0, -1), "spread": 40.0, "v": [20.0, 70.0], "g": Vector2(0, -60),
		"damp": [0.0, 10.0], "sc": [1.0, 1.8], "cols": [FxPalette.GREEN, FxPalette.WHITE], "fade": true},
	"mote": {"n": 8, "life": 1.1, "dir": Vector2(0, -1), "spread": 180.0, "v": [25.0, 75.0], "g": Vector2(0, -20),
		"damp": [0.0, 20.0], "sc": [1.4, 2.2], "cols": [FxPalette.VIOLET, FxPalette.BLUE, FxPalette.WHITE], "fade": true},
	"smoke": {"n": 8, "life": 1.1, "dir": Vector2(0, -1), "spread": 25.0, "v": [25.0, 65.0], "g": Vector2(0, -20),
		"damp": [0.0, 10.0], "sc": [2.6, 4.0], "cols": [Color("5a4a78"), Color("3a3050"), FxPalette.VIOLET], "fade": true, "alpha": 0.5},
	"sweep": {"n": 18, "life": 0.9, "dir": Vector2(0, -1), "spread": 180.0, "v": [30.0, 110.0], "g": Vector2(0, 0),
		"damp": [20.0, 60.0], "sc": [1.0, 2.0], "cols": [FxPalette.WHITE, FxPalette.GOLD], "fade": true},
}

static var _tex: Texture2D = null
static var _fade: Gradient = null
static var _shrink: Curve = null
static var _ramps: Dictionary = {}

var _emitters: Array[CPUParticles2D] = []
var _end: PackedFloat64Array = PackedFloat64Array()
var _amount: PackedInt32Array = PackedInt32Array()
var _prio: PackedInt32Array = PackedInt32Array()
var _live: int = 0
var _now: float = 0.0
var dropped: int = 0          # scoppi scartati per i limiti (utile ai test)
var spawned: int = 0


static func texture() -> Texture2D:
	if _tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_tex = ImageTexture.create_from_image(img)
	return _tex


static func _ramp_for(cols: Array) -> Gradient:
	var key := ""
	for c in cols:
		key += (c as Color).to_html() + ","
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var n := cols.size()
	var offs := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in n:
		offs.append(float(i) / float(n))
		colors.append(cols[i])
	g.offsets = offs
	g.colors = colors
	_ramps[key] = g
	return g


static func _fade_ramp() -> Gradient:
	if _fade == null:
		_fade = Gradient.new()
		_fade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		_fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _fade


static func _shrink_curve() -> Curve:
	if _shrink == null:
		_shrink = Curve.new()
		_shrink.add_point(Vector2(0.0, 1.0))
		_shrink.add_point(Vector2(0.6, 0.8))
		_shrink.add_point(Vector2(1.0, 0.0))
	return _shrink


func live_particles() -> int:
	return _live


func live_emitters() -> int:
	var n := 0
	for i in _emitters.size():
		if _emitters[i].visible:
			n += 1
	return n


func emitter_count() -> int:
	return _emitters.size()


func clear_all() -> void:
	for i in _emitters.size():
		_emitters[i].emitting = false
		_emitters[i].visible = false
		_amount[i] = 0
	_live = 0


## Spegne gli emettitori finiti (chiamato dall'host a ogni frame, solo se ce n'è di attivi).
func step(dt: float) -> void:
	_now += dt
	if _live <= 0:
		return
	for i in _emitters.size():
		if _amount[i] > 0 and _now >= _end[i]:
			_emitters[i].emitting = false
			_emitters[i].visible = false
			_live -= _amount[i]
			_amount[i] = 0


func _free_slot(n: int, priority: int) -> int:
	var idle := -1
	for i in _emitters.size():
		if _amount[i] == 0:
			idle = i
			break
	if idle < 0 and _emitters.size() < MAX_EMITTERS:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.emitting = false
		p.visible = false
		p.local_coords = false
		p.explosiveness = 1.0
		p.texture = texture()
		p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(p)
		_emitters.append(p)
		_end.append(0.0)
		_amount.append(0)
		_prio.append(0)
		idle = _emitters.size() - 1
	if idle < 0:
		# pool pieno: si ruba il più vecchio SOLO a uno di priorità minore (a pari priorità lo scoppio nuovo si scarta)
		var best := -1
		for i in _emitters.size():
			if _prio[i] < priority and (best < 0 or _end[i] < _end[best]):
				best = i
		if best >= 0:
			_stop(best)
			idle = best
	if idle >= 0 and _live + n > MAX_PARTICLES:
		# troppe particelle vive: si tolgono i più vecchi di priorità minore finché c'è posto, altrimenti si scarta
		while _live + n > MAX_PARTICLES:
			var oldest := -1
			for i in _emitters.size():
				if _amount[i] > 0 and _prio[i] < priority and (oldest < 0 or _end[i] < _end[oldest]):
					oldest = i
			if oldest < 0:
				return -1
			_stop(oldest)
	return idle


func _stop(i: int) -> void:
	_emitters[i].emitting = false
	_emitters[i].visible = false
	_live -= _amount[i]
	_amount[i] = 0


## Lancia uno scoppio. `colors` ([] = toni del preset), `scale` = moltiplica velocità e dimensione,
## `count_mult` = moltiplica il numero di particelle (già ridotto dal livello), `extents` = emissione su un
## rettangolo (semi-larghezza, semi-altezza), `dir` = direzione (Vector2.ZERO = quella del preset).
## Ritorna false se scartato (limiti, livello 0).
func spawn(preset: String, pos: Vector2, colors: Array = [], scale: float = 1.0, count_mult: float = 1.0,
		extents: Vector2 = Vector2.ZERO, priority: int = 0, dir: Vector2 = Vector2.ZERO) -> bool:
	var lv := Fx.level()
	if lv <= 0 or not PRESETS.has(preset):
		return false
	var d: Dictionary = PRESETS[preset]
	var factor := 1.0 if lv >= 2 else 0.4
	var n := clampi(int(round(float(d.n) * count_mult * factor)), 3, 64)
	var slot := _free_slot(n, priority)
	if slot < 0:
		dropped += 1
		return false
	var p := _emitters[slot]
	var cols: Array = colors if not colors.is_empty() else d.cols
	p.emitting = false
	p.amount = n
	p.lifetime = float(d.life) * (0.85 + 0.15 * scale)
	p.global_position = pos.round()
	p.direction = dir.normalized() if dir != Vector2.ZERO else d.dir
	p.spread = float(d.spread)
	p.gravity = d.g
	p.initial_velocity_min = float(d.v[0]) * scale
	p.initial_velocity_max = float(d.v[1]) * scale
	p.damping_min = float(d.damp[0])
	p.damping_max = float(d.damp[1])
	p.scale_amount_min = float(d.sc[0]) * clampf(scale, 0.7, 2.0) * SIZE_MULT
	p.scale_amount_max = float(d.sc[1]) * clampf(scale, 0.7, 2.0) * SIZE_MULT
	p.randomness = 0.4
	p.color_initial_ramp = _ramp_for(cols)
	p.color = Color(1, 1, 1, float(d.get("alpha", 1.0)))
	p.color_ramp = _fade_ramp() if (bool(d.get("fade", false)) or bool(d.get("shrink", false))) else null
	p.scale_amount_curve = _shrink_curve() if bool(d.get("shrink", false)) else null
	if extents != Vector2.ZERO:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = extents
	else:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.visible = true
	p.restart()
	p.emitting = true
	_end[slot] = _now + p.lifetime + 0.1
	_amount[slot] = n
	_prio[slot] = priority
	_live += n
	spawned += 1
	return true
