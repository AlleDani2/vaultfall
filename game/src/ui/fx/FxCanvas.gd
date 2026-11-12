class_name FxCanvas
extends Control
## Tela unica degli effetti «disegnati» (numeri, anelli di pixel, graffi, cornici, bagliori, oggetti in volo con scia,
## lampi e vignette). Un solo nodo, un solo _draw: le forme sono un pool preallocato di FxShape (nessuna allocazione
## durante il gioco). Si ridisegna SOLO quando c'è qualcosa di attivo (set_process(false) altrimenti).
## Tutto a pixel quadrati: anelli fatti di quadratini, posizioni arrotondate, nessun antialiasing.

const MAX_SHAPES := 128
const MAX_NUMBERS := 22
const RING_DIRS := 48
const NUM_TIERS := [14, 18, 24, 32, 44]

var shapes: Array[FxShape] = []
var host: Node = null
var _dirs: PackedVector2Array = PackedVector2Array()
var _kind_count: PackedInt32Array = PackedInt32Array()
var _active: int = 0
var _font: Font = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in MAX_SHAPES:
		shapes.append(FxShape.new())
	_kind_count.resize(16)
	for i in RING_DIRS:
		var a := TAU * float(i) / float(RING_DIRS)
		_dirs.append(Vector2(cos(a), sin(a)))
	set_process(false)


func _ready() -> void:
	set_process(_active > 0)              # il motore accende _process alla READY: a riposo resta spento


func active_count() -> int:
	return _active


func count_of(kind: int) -> int:
	return _kind_count[kind]


func clear_all() -> void:
	for s in shapes:
		if s.kind != FxShape.Kind.NONE:
			_release(s)
	_active = 0
	set_process(false)
	queue_redraw()


## Prende una forma libera. Pool pieno: ruba la più vecchia a priorità <= quella richiesta; null se non c'è posto.
func acquire(kind: int, priority: int = 0) -> FxShape:
	if kind == FxShape.Kind.NUMBER and _kind_count[kind] >= MAX_NUMBERS and priority < 5:
		return null
	var pick: FxShape = null
	for s in shapes:
		if s.kind == FxShape.Kind.NONE:
			pick = s
			break
	if pick == null:
		for s in shapes:
			if s.priority <= priority and (pick == null or s.priority < pick.priority \
					or (s.priority == pick.priority and s.age > pick.age)):
				pick = s
		if pick == null:
			return null
		_release(pick)
	pick.reset()
	pick.kind = kind
	pick.priority = priority
	_kind_count[kind] += 1
	_active += 1
	set_process(true)
	return pick


func _release(s: FxShape) -> void:
	if s.kind != FxShape.Kind.NONE:
		_kind_count[s.kind] -= 1
		_active -= 1
	s.reset()


func step(dt: float) -> void:
	if _active <= 0:
		set_process(false)
		queue_redraw()
		return
	for s in shapes:
		if s.kind == FxShape.Kind.NONE:
			continue
		s.age += dt
		if s.kind == FxShape.Kind.FLY and s.age >= s.delay:
			_trail_push(s)
		if s.age - s.delay >= s.life:
			if s.kind == FxShape.Kind.FLY and host != null and host.has_method("on_fly_arrived"):
				host.call("on_fly_arrived", s)
			_release(s)
	queue_redraw()
	if _active <= 0:
		set_process(false)


func _trail_push(s: FxShape) -> void:
	var p := _fly_pos(s)
	s.trail[s.trail_i % FxShape.TRAIL_N] = p
	s.trail_i += 1


func _fly_pos(s: FxShape) -> Vector2:
	var u := s.t()
	u = u * u * (3.0 - 2.0 * u)
	var a := s.from.lerp(s.ctrl, u)
	var b := s.ctrl.lerp(s.to, u)
	return a.lerp(b, u)


func _font_get() -> Font:
	if _font == null:
		_font = get_theme_default_font()
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


func _draw() -> void:
	if _active <= 0:
		return
	for s in shapes:
		if s.kind == FxShape.Kind.NONE or s.age < s.delay:
			continue
		match s.kind:
			FxShape.Kind.NUMBER: _draw_number(s)
			FxShape.Kind.RING: _draw_ring(s)
			FxShape.Kind.SLASH: _draw_slash(s)
			FxShape.Kind.FRAME: _draw_frame(s)
			FxShape.Kind.GLOW: _draw_glow(s)
			FxShape.Kind.FLY: _draw_fly(s)
			FxShape.Kind.FLASH: _draw_flash(s)
			FxShape.Kind.VIGNETTE: _draw_vignette(s)
			FxShape.Kind.ARC: _draw_arc(s)
			FxShape.Kind.BOLT: _draw_bolt(s)
			FxShape.Kind.RAYS: _draw_rays(s)


func _draw_number(s: FxShape) -> void:
	var p := s.t()
	var rise := s.amount * (1.0 - pow(1.0 - p, 2.0))
	var fs := int(s.size)
	if s.age - s.delay < 0.07 and s.priority >= 1:
		fs = _next_tier(fs)                      # «pop» a gradini: il numero nasce più grosso e si assesta
	var a := 1.0 if p < 0.6 else 1.0 - (p - 0.6) / 0.4
	var pos := Vector2(roundf(s.pos.x), roundf(s.pos.y - rise))
	var col := Color(s.color.r, s.color.g, s.color.b, s.color.a * a)
	var oc := Color(0.03, 0.02, 0.03, 0.9 * a)
	var f := _font_get()
	pos.x -= 200.0
	draw_string_outline(f, pos, s.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, fs, maxi(3, int(float(fs) / 6.0)), oc)
	draw_string(f, pos, s.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, fs, col)


static func _next_tier(fs: int) -> int:
	for t in NUM_TIERS:
		if t > fs:
			return t
	return fs


func _draw_ring(s: FxShape) -> void:
	var p := s.t()
	var r := s.size * (1.0 - pow(1.0 - p, 3.0))
	var n := clampi(int(r * TAU / 6.0), 12, RING_DIRS)
	var stp := float(RING_DIRS) / float(n)
	var sq := 4.0 if s.size < 90.0 else 5.0
	var col := Color(s.color.r, s.color.g, s.color.b, s.color.a * (1.0 - p))
	var col2 := Color(s.color2.r, s.color2.g, s.color2.b, col.a)
	for i in n:
		var d := _dirs[int(float(i) * stp) % RING_DIRS]
		var q := s.pos + d * r
		draw_rect(Rect2(Vector2(roundf(q.x - sq * 0.5), roundf(q.y - sq * 0.5)), Vector2(sq, sq)), col if (i % 3) != 0 else col2)


func _draw_slash(s: FxShape) -> void:
	var p := s.t()
	var head := s.from.lerp(s.to, minf(1.0, p * 2.2))
	var tail := s.from.lerp(s.to, clampf((p - 0.25) * 1.6, 0.0, 1.0))
	var a := 1.0 - p
	var w := maxf(1.0, s.size * (1.0 - p))
	draw_line(tail.round(), head.round(), Color(s.color.r, s.color.g, s.color.b, a * 0.8), w + 2.0)
	draw_line(tail.round(), head.round(), Color(1, 1, 1, a), maxf(1.0, w - 1.0))


func _draw_frame(s: FxShape) -> void:
	var p := s.t()
	if s.vel.x > 0.5:                       # lampo STATICO (riduci animazioni): contorno fermo, nessun movimento
		draw_rect(Rect2(s.rect.position.round(), s.rect.size.round()), Color(s.color.r, s.color.g, s.color.b, s.amount), false, 3.0)
		return
	for k in 3:
		var a := (1.0 - p) * s.amount * (1.0 - 0.3 * float(k))
		if a <= 0.01:
			continue
		var r := s.rect.grow(s.size * p + float(k) * 3.0)
		draw_rect(Rect2(r.position.round(), r.size.round()), Color(s.color.r, s.color.g, s.color.b, a), false, 2.0)


func _draw_glow(s: FxShape) -> void:
	var p := s.t()
	var env := minf(p * 6.0, 1.0) * minf((1.0 - p) * 4.0, 1.0)
	var pulse := 0.65 + 0.35 * sin((s.age - s.delay) * TAU * 1.6)
	for i in 4:
		var a := s.amount * 0.16 * (1.0 - float(i) / 4.0) * env * pulse
		var r := s.rect.grow(s.size * float(4 - i))
		draw_rect(Rect2(r.position.round(), r.size.round()), Color(s.color.r, s.color.g, s.color.b, a))


func _draw_fly(s: FxShape) -> void:
	var p := _fly_pos(s)
	var n: int = mini(s.trail_i, FxShape.TRAIL_N)
	for k in n:
		var idx := (s.trail_i - 1 - k) % FxShape.TRAIL_N
		var q: Vector2 = s.trail[idx]
		var f := 1.0 - float(k) / float(FxShape.TRAIL_N)
		var sq := maxf(2.0, s.size * 0.35 * f)
		draw_rect(Rect2((q - Vector2(sq, sq) * 0.5).round(), Vector2(sq, sq)), Color(s.color.r, s.color.g, s.color.b, 0.55 * f))
	if s.texture != null:
		var sz := s.size
		draw_texture_rect(s.texture, Rect2((p - Vector2(sz, sz) * 0.5).round(), Vector2(sz, sz)), false)
	else:
		var q := p.round()
		var sq := maxf(4.0, s.size * 0.4)
		draw_rect(Rect2(q - Vector2(sq, sq) * 0.5, Vector2(sq, sq)), s.color)
		draw_rect(Rect2(q - Vector2(sq, sq) * 0.5, Vector2(sq * 0.5, sq * 0.5)), s.color2)


func _draw_flash(s: FxShape) -> void:
	var p := s.t()
	var a := s.amount * pow(1.0 - p, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(s.color.r, s.color.g, s.color.b, a))


func _draw_vignette(s: FxShape) -> void:
	var p := s.t()
	var r := s.rect if s.rect.size.x > 0.0 else Rect2(Vector2.ZERO, size)
	var th := s.size
	for i in 4:
		var a := s.amount * (1.0 - p) * (1.0 - float(i) / 4.0) * 0.5
		var c := Color(s.color.r, s.color.g, s.color.b, a)
		var o := float(i) * th
		draw_rect(Rect2(r.position.x, r.position.y + o, r.size.x, th), c)
		draw_rect(Rect2(r.position.x, r.end.y - o - th, r.size.x, th), c)
		draw_rect(Rect2(r.position.x + o, r.position.y + th + o, th, r.size.y - 2.0 * (th + o)), c)
		draw_rect(Rect2(r.end.x - o - th, r.position.y + th + o, th, r.size.y - 2.0 * (th + o)), c)


## Fendente ad arco (mischia): centro `pos`, raggio `size`, angolo iniziale `from.x`, ampiezza `from.y`, spessore `amount`.
## La testa avanza veloce, la coda la segue: mezzaluna che si assottiglia verso la coda. Segmenti a pixel interi.
func _draw_arc(s: FxShape) -> void:
	var p := s.t()
	var head := clampf(p * 2.4, 0.0, 1.0)
	var tail := clampf((p - 0.2) * 1.7, 0.0, 1.0)
	if tail >= head:
		return
	var fade := 1.0 - p
	var n := 12
	var prev := Vector2.ZERO
	for i in n + 1:
		var u := lerpf(tail, head, float(i) / float(n))
		var a := s.from.x + s.from.y * u
		var q := (s.pos + Vector2(cos(a), sin(a)) * s.size).round()
		if i > 0:
			var k := float(i) / float(n)                    # 0 = coda, 1 = testa
			var w := maxf(1.0, s.amount * k * (1.0 - 0.5 * p))
			draw_line(prev, q, Color(s.color.r, s.color.g, s.color.b, 0.85 * fade), w + 2.0)
			draw_line(prev, q, Color(1, 1, 1, fade), maxf(1.0, w - 1.0))
		prev = q


## Traccia di un proiettile (distanza): linea sottile veloce con punta quadrata e piccolo «X» all'impatto.
func _draw_bolt(s: FxShape) -> void:
	var p := s.t()
	var head := s.from.lerp(s.to, clampf(p * 3.0, 0.0, 1.0))
	var tail := s.from.lerp(s.to, clampf(p * 3.0 - 0.55, 0.0, 1.0))
	var fade := 1.0 - maxf(0.0, p - 0.5) * 2.0
	if p < 0.34:
		draw_line(tail.round(), head.round(), Color(s.color.r, s.color.g, s.color.b, 0.9), maxf(1.0, s.size * 0.5))
		draw_line(tail.round(), head.round(), Color(1, 1, 1, 0.9), 1.0)
		var sq := s.size
		draw_rect(Rect2((head - Vector2(sq, sq) * 0.5).round(), Vector2(sq, sq)), Color.WHITE)
	elif fade > 0.0:
		var r := s.size * (1.2 + 2.0 * (p - 0.34))
		var c := s.to.round()
		var col := Color(s.color.r, s.color.g, s.color.b, fade)
		draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 2.0)
		draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, 2.0)


## Raggi rotanti attorno a un rombo (magia): `amount` raggi, raggio finale `size`, verso `vel.x`.
func _draw_rays(s: FxShape) -> void:
	var p := s.t()
	var fade := 1.0 - p
	var r1 := s.size * (1.0 - pow(1.0 - p, 3.0))
	var r0 := r1 * 0.35
	var rot := p * 1.1 * signf(s.vel.x if absf(s.vel.x) > 0.01 else 1.0)
	var n := int(s.amount)
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		var d := Vector2(cos(a), sin(a))
		var col := s.color if (i % 2 == 0) else s.color2
		draw_line((s.pos + d * r0).round(), (s.pos + d * r1).round(), Color(col.r, col.g, col.b, fade), 3.0 if i % 2 == 0 else 2.0)
	var dm := maxf(3.0, r1 * 0.22) * minf(1.0, fade * 2.0)
	var c := s.pos.round()
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -dm), c + Vector2(dm, 0), c + Vector2(0, dm), c + Vector2(-dm, 0)]),
		Color(s.color2.r, s.color2.g, s.color2.b, fade))
