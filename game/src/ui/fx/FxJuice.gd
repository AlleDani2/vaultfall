class_name FxJuice
extends RefCounted
## «Juice» dei colpi: lampo bianco sul bersaglio (shader), con limite di sicurezza fotosensibilità (max 3 lampi
## al secondo in tutto il gioco), e fendenti disegnati per stile di combattimento. Solo presentazione.
##   melee  = arco largo (crescente) che attraversa il bersaglio · ranged = traccia veloce con punta dall'attaccante
##   arcane = raggi rotanti attorno a un rombo (rune) · pesante = più grande, doppio.

const FLASH_SHADER := preload("res://src/ui/fx/hitflash.gdshader")
const META_MAT := "fx_flash_mat"
const META_TW := "fx_flash_tw"
const MAX_FLASH_PER_SEC := 3
const WINDOW_MS := 1000

static var _flash_times: Array[int] = []
static var flashes_started: int = 0          # per i test
static var _side: float = 1.0                # alterna il verso dei fendenti


## Può partire un lampo ORA? (max 3 nella finestra di 1 s). Se sì, lo registra.
static func _flash_allowed() -> bool:
	var now := Time.get_ticks_msec()
	while not _flash_times.is_empty() and now - _flash_times[0] >= WINDOW_MS:
		_flash_times.pop_front()
	if _flash_times.size() >= MAX_FLASH_PER_SEC:
		return false
	_flash_times.append(now)
	return true


static func reset_limiter() -> void:
	_flash_times.clear()
	flashes_started = 0


## Lampo bianco sullo sprite `n` (~0,08 s; critico un po' più lungo). Livello 0: niente. Livello 1 (effetti ridotti):
## più tenue. Ritorna true se partito.
static func hit_flash(n: CanvasItem, crit: bool = false) -> bool:
	var lv := Fx.level()
	if lv <= 0 or n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var mat: ShaderMaterial = n.get_meta(META_MAT) if n.has_meta(META_MAT) else null
	if n.material != null and n.material != mat:
		return false                                   # c'è già un materiale di qualcun altro: non lo tocco
	if not _flash_allowed():
		return false
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = FLASH_SHADER
		n.set_meta(META_MAT, mat)
	var peak := 0.55 if lv == 1 else 0.9
	var secs := 0.12 if (crit and lv >= 2) else 0.08
	if n.has_meta(META_TW):
		var old: Variant = n.get_meta(META_TW)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	mat.set_shader_parameter("flash", peak)
	n.material = mat
	flashes_started += 1
	var tw := n.create_tween()
	n.set_meta(META_TW, tw)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("flash", v), peak, 0.0, secs)
	tw.tween_callback(_end_flash.bind(n, mat))
	return true


static func _end_flash(n: CanvasItem, mat: ShaderMaterial) -> void:
	if not is_instance_valid(n):
		return
	if n.material == mat:
		n.material = null
	if n.has_meta(META_TW):
		n.remove_meta(META_TW)


## Direzione normalizzata da `a` a `b` (a destra se coincidono).
static func dir(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	return d.normalized() if d.length() > 0.5 else Vector2.RIGHT


## Fendente per stile. `from`: centro dell'attaccante, `to`: centro del bersaglio. `heavy`: tecnica / critico.
static func strike(style: String, from: Vector2, to: Vector2, color: Color, heavy: bool = false) -> void:
	if Fx.level() <= 0:
		return
	var h := Fx.host()
	if h == null:
		return
	match style:
		"ranged":
			_bolt(h, from, to, color, heavy)
		"arcane":
			_rays(h, to, color, heavy)
		_:
			_arc(h, to, dir(from, to), color, heavy)


static func _arc(h: FxHost, center: Vector2, d: Vector2, color: Color, heavy: bool) -> void:
	_side = -_side
	var base := d.angle() + PI                          # il fendente arriva dal lato dell'attaccante
	var r := 44.0 if not heavy else 60.0
	_arc_shape(h, center, r, base - _side * 0.5, _side * 2.0, color, 8.0 if not heavy else 12.0, 0.22, 1 if heavy else 0)
	if heavy:                                           # secondo fendente incrociato
		_arc_shape(h, center, r * 0.85, base + _side * 0.5, -_side * 2.0, FxPalette.WHITE, 7.0, 0.24, 1)


static func _arc_shape(h: FxHost, c: Vector2, r: float, a0: float, sweep: float, color: Color, w: float, life: float, prio: int) -> void:
	var s := h.canvas.acquire(FxShape.Kind.ARC, prio)
	if s == null:
		return
	s.pos = c
	s.size = r
	s.from = Vector2(a0, sweep)
	s.amount = w
	s.color = color
	s.life = life


static func _bolt(h: FxHost, from: Vector2, to: Vector2, color: Color, heavy: bool) -> void:
	var s := h.canvas.acquire(FxShape.Kind.BOLT, 1 if heavy else 0)
	if s == null:
		return
	s.from = from
	s.to = to
	s.color = color
	s.size = 4.0 if not heavy else 6.0
	s.life = 0.2
	if heavy:
		var s2 := h.canvas.acquire(FxShape.Kind.BOLT, 0)
		if s2 != null:
			var n := dir(from, to)
			var off := Vector2(-n.y, n.x) * 12.0
			s2.from = from + off
			s2.to = to + off * 0.4
			s2.color = FxPalette.WHITE
			s2.size = 3.0
			s2.life = 0.22
			s2.delay = 0.04


static func _rays(h: FxHost, c: Vector2, color: Color, heavy: bool) -> void:
	var s := h.canvas.acquire(FxShape.Kind.RAYS, 1 if heavy else 0)
	if s == null:
		return
	s.pos = c
	s.size = 40.0 if not heavy else 62.0
	s.amount = 8.0 if not heavy else 12.0
	s.color = color
	s.color2 = FxPalette.WHITE
	s.life = 0.32
	s.vel = Vector2(_side, 0.0)
	_side = -_side
