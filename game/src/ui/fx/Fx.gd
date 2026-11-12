class_name Fx
extends RefCounted
## Facciata statica degli effetti «juice» (VFX). Solo presentazione: nessuna logica di gioco, nessun numero di
## bilanciamento. Posizioni sempre in coordinate GLOBALI dello schermo (quelle di Control.global_position).
##
## Livelli (Fx.level()):
##   2 = pieni  ·  1 = ridotti (impostazione «Effetti: ridotti»: ~40% particelle, niente scosse né lampi a schermo intero)
##   0 = «riduci animazioni» (Settings.reduce_motion): nessun movimento; per gli eventi importanti resta solo un
##       contorno FERMO per un attimo (lampo statico), il resto è già nelle notifiche.
## Limiti fissi (vedi FxCanvas.MAX_SHAPES / MAX_NUMBERS e FxBurst.MAX_EMITTERS / MAX_PARTICLES): oltre, gli effetti
## nuovi di priorità bassa si scartano, quelli di priorità alta rubano il posto ai più vecchi.
## Catalogo: number · hit · burst · ring · slash · screen_flash · vignette · frame_flash · glow · static_mark ·
## rarity reveal · confetti · fly · coins · job · shake · pop · pop_in · glow_pulse · breathe · shine · number_tick ·
## dissolve · bar_flash · banner · ceremony.

const NUM_S := 16
const NUM_M := 22
const NUM_L := 30
const NUM_XL := 42
## Tetti di contenimento (rapporto 104): nessun knockback/affondo sposta un elemento oltre questi pixel, così non esce dal suo pannello.
const IMPACT_PUSH_MAX := 6.0
const IMPACT_SHAKE_MAX := 3.0

static var force_level: int = -1       # per galleria e test (-1 = dalle impostazioni)
static var _host: FxHost = null
static var _host_pending: bool = false
static var _banner_cur: FxBanner = null
static var _banner_queue: Array = []
static var _ceremony_cur: FxCeremony = null


# ------------------------------------------------------------------ livello e host

static func level() -> int:
	if force_level >= 0:
		return force_level
	if bool(Settings.get_value("reduce_motion")) or not Clock.focused:       # in secondo piano: niente effetti (resoconto 100)
		return 0
	return 1 if str(Settings.get_value("fx_mode")) == "reduced" else 2


static func enabled() -> bool:
	return level() > 0


## Crea l'host (differito: sicuro anche durante _ready). Ritorna true se già pronto.
static func ensure() -> bool:
	if _host != null and is_instance_valid(_host) and _host.is_inside_tree():
		return true
	if _host != null and not is_instance_valid(_host):
		_host = null
	if _host == null and not _host_pending:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return false
		_host = FxHost.new()
		_host_pending = true
		tree.root.add_child.call_deferred(_host)
		_host.tree_entered.connect(func() -> void: _host_pending = false, CONNECT_ONE_SHOT)
	return _host != null and _host.is_inside_tree()


static func host() -> FxHost:
	if not ensure():
		return null
	return _host


## Smonta tutto (test, uscita dalla partita): libera l'host e azzera le code.
static func reset() -> void:
	if _banner_cur != null and is_instance_valid(_banner_cur):
		_banner_cur.queue_free()
	if _ceremony_cur != null and is_instance_valid(_ceremony_cur):
		_ceremony_cur.queue_free()
	_banner_cur = null
	_ceremony_cur = null
	_banner_queue.clear()
	_anchors.clear()
	if _host != null and is_instance_valid(_host):
		if _host.is_inside_tree():
			_host.get_parent().remove_child(_host)
		_host.free()
	_host = null
	_host_pending = false
	force_level = -1


static func clear_all() -> void:
	if _host != null and is_instance_valid(_host):
		_host.clear_all()


static func stats() -> Dictionary:
	var h := _host if (_host != null and is_instance_valid(_host)) else null
	if h == null:
		return {"level": level(), "shapes": 0, "numbers": 0, "particles": 0, "emitters": 0, "ema_us": 0.0, "peak_us": 0.0, "dropped": 0}
	return {"level": level(), "shapes": h.canvas.active_count(), "numbers": h.canvas.count_of(FxShape.Kind.NUMBER),
		"particles": h.burst.live_particles(), "emitters": h.burst.live_emitters(), "ema_us": h.ema_us, "peak_us": h.peak_us,
		"dropped": h.burst.dropped}


# ------------------------------------------------------------------ ancoraggi (bersagli noti: oro, Deposito, menù)

static var _anchors: Dictionary = {}      # nome -> Control (weak: si controlla is_instance_valid)


## MainScreen/FxDirector registrano i bersagli noti ("gold", "bank", "activity", id delle voci del menù).
static func register_anchor(anchor_name: String, node: Control) -> void:
	_anchors[anchor_name] = node


static func anchor_node(anchor_name: String) -> Control:
	var n: Variant = _anchors.get(anchor_name)
	if is_instance_valid(n) and n is Control and (n as Control).is_inside_tree():
		return n
	return null


## Centro globale del bersaglio; `fallback` se non c'è (es. schermata senza menù, test).
static func anchor_pos(anchor_name: String, fallback: Vector2 = Vector2(640, 40)) -> Vector2:
	var n := anchor_node(anchor_name)
	return center_of(n) if n != null else fallback


# ------------------------------------------------------------------ geometria

static func center_of(n: Control) -> Vector2:
	return n.get_global_rect().get_center()


static func rect_of(n: Control) -> Rect2:
	return n.get_global_rect()


# ------------------------------------------------------------------ forme disegnate

## Porta posizione e salita di un numero dentro `bounds` (spazio globale). Il testo è centrato in x e disegnato con la linea di
## base in `pos.y`: in alto serve almeno l'altezza del font (con margine per il «pop»), ai lati metà larghezza stimata.
static func _fit_number(pos: Vector2, text: String, size_px: int, rise: float, bounds: Rect2) -> Array:
	var fs := float(size_px) * 1.35
	var half_w := minf(float(text.length()) * float(size_px) * 0.32 + 2.0, bounds.size.x * 0.5)
	var x_lo := bounds.position.x + half_w
	var x_hi := bounds.end.x - half_w
	pos.x = clampf(pos.x, x_lo, maxf(x_lo, x_hi))
	var y_lo := bounds.position.y + minf(fs, bounds.size.y)
	pos.y = clampf(pos.y, y_lo, maxf(y_lo, bounds.end.y))
	return [pos, clampf(rise, 0.0, pos.y - y_lo)]


## Numero fluttuante. `size_px`: NUM_S/M/L/XL. `priority` >= 1: «pop» di nascita e non scartato dal limite dei numeri.
## `bounds`: rettangolo globale di confine facoltativo (size zero = nessun confine, comportamento invariato): il numero nasce
## dentro il rettangolo e la sua salita non lo porta fuori.
static func number(pos: Vector2, text: String, color: Color, size_px: int = NUM_M, rise: float = 44.0, life: float = 0.9,
		priority: int = 0, delay: float = 0.0, bounds: Rect2 = Rect2()) -> bool:
	if level() <= 0:
		return false
	if bounds.has_area():
		var fit := _fit_number(pos, text, size_px, rise, bounds)
		pos = fit[0]
		rise = fit[1]
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.NUMBER, priority)
	if s == null:
		return false
	s.pos = pos
	s.text = text
	s.color = color
	s.size = float(size_px)
	s.amount = rise
	s.life = life
	s.delay = delay
	return true


## Anello di quadratini che si espande (livello, critico, rivelazione).
static func ring(pos: Vector2, color: Color, radius: float = 80.0, life: float = 0.6, color2: Color = Color.WHITE,
		priority: int = 0) -> bool:
	if level() < 2:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.RING, priority)
	if s == null:
		return false
	s.pos = pos
	s.color = color
	s.color2 = color2
	s.size = radius
	s.life = life
	return true


## Graffio di taglio da `a` a `b`.
static func slash(a: Vector2, b: Vector2, color: Color = FxPalette.WHITE, width: float = 4.0, life: float = 0.16) -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.SLASH)
	if s == null:
		return false
	s.from = a
	s.to = b
	s.color = color
	s.size = width
	s.life = life
	return true


## Lampo a schermo intero (cerimonie): morbido, mai sopra 0,3 di opacità e al massimo uno ogni 0,4 s. Solo livello 2.
static func screen_flash(color: Color, alpha: float = 0.22, life: float = 0.4) -> bool:
	if level() < 2:
		return false
	var h := host()
	if h == null:
		return false
	var now := Time.get_ticks_msec()
	if now - h.last_flash_ms < 400:
		return false
	var s := h.canvas.acquire(FxShape.Kind.FLASH, 2)
	if s == null:
		return false
	h.last_flash_ms = now
	s.color = color
	s.amount = minf(alpha, 0.3)
	s.life = life
	return true


## Vignetta ai bordi di un rettangolo (danno subito: rosso discreto). Rect vuoto = tutto lo schermo.
static func vignette(rect: Rect2, color: Color, strength: float = 0.7, band: float = 6.0, life: float = 0.4) -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.VIGNETTE)
	if s == null:
		return false
	s.rect = rect
	s.color = color
	s.amount = strength
	s.size = band
	s.life = life
	return true


## Cornice che si allarga e svanisce (bordi della tessera, pannelli).
static func frame_flash(rect: Rect2, color: Color, grow: float = 16.0, life: float = 0.5, intensity: float = 1.0, priority: int = 0) -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.FRAME, priority)
	if s == null:
		return false
	s.rect = rect
	s.color = color
	s.size = grow
	s.life = life
	s.amount = intensity
	s.vel = Vector2.ZERO
	return true


## LAMPO STATICO: contorno fermo (nessun movimento) per `secs`. È ciò che resta degli effetti con «riduci animazioni».
static func static_mark(rect: Rect2, color: Color, secs: float = 0.8) -> bool:
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.FRAME, 2)
	if s == null:
		return false
	s.rect = rect
	s.color = color
	s.size = 0.0
	s.life = secs
	s.amount = 0.9
	s.vel = Vector2(1, 0)
	return true


## Alone a gradini dietro un rettangolo che respira per `life` secondi (tessera vincente).
static func glow(rect: Rect2, color: Color, life: float = 1.4, amount: float = 1.0, thickness: float = 4.0, priority: int = 1) -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.GLOW, priority)
	if s == null:
		return false
	s.rect = rect
	s.color = color
	s.life = life
	s.amount = amount
	s.size = thickness
	return true


## Oggetto in volo con scia verso `to` (il +N che va al Deposito, le monete). `target`: Control che fa «pop» all'arrivo.
static func fly(texture: Texture2D, from: Vector2, to: Vector2, secs: float = 0.7, color: Color = FxPalette.GOLD,
		arrive_burst: String = "glint", target: Control = null, delay: float = 0.0, size_px: float = 22.0,
		priority: int = 0) -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	var s := h.canvas.acquire(FxShape.Kind.FLY, priority)
	if s == null:
		return false
	s.from = from
	s.to = to
	s.ctrl = (from + to) * 0.5 + Vector2(0.0, -minf(120.0, from.distance_to(to) * 0.35))
	s.texture = texture
	s.color = color
	s.color2 = FxPalette.lighten(color, 0.6)
	s.life = secs
	s.delay = delay
	s.size = size_px
	s.arrive_burst = arrive_burst
	s.target = target
	return true


## Pioggia di monete verso un bersaglio (vendite, ricompense).
static func coins(from: Vector2, to: Vector2, n: int = 5, target: Control = null) -> void:
	if level() <= 0:
		return
	var k := clampi(n, 1, 8) if level() >= 2 else clampi(int(n / 2.0), 1, 3)
	for i in k:
		var jitter := Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 10.0))
		fly(null, from + jitter, to, 0.55 + 0.04 * float(i), FxPalette.GOLD, "glint" if i == k - 1 else "", \
			target if i == k - 1 else null, 0.06 * float(i), 20.0)


# ------------------------------------------------------------------ particelle

## Scoppio di particelle (vedi FxBurst.PRESETS). Ritorna true se lanciato.
static func burst(preset: String, pos: Vector2, colors: Array = [], scale: float = 1.0, count_mult: float = 1.0,
		extents: Vector2 = Vector2.ZERO, priority: int = 0, dir: Vector2 = Vector2.ZERO) -> bool:
	var h := host()
	if h == null:
		return false
	return h.burst.spawn(preset, pos, colors, scale, count_mult, extents, priority, dir)


## Coriandoli su un rettangolo (vittoria dungeon, cerimonie, rarità altissime).
static func confetti(rect: Rect2, priority: int = 1, colors: Array = []) -> bool:
	return burst("confetti", rect.get_center(), colors, 1.0, 1.0, rect.size * 0.5, priority)


## Particelle tematiche di una mansione al completamento di un'azione.
static func job(skill_id: String, pos: Vector2, scale: float = 1.0) -> void:
	var h := host()
	if h == null or level() <= 0:
		return
	FxThemes.job(h.burst, skill_id, pos, scale)


## Colpo: scintille + graffio. `crit`: più grande, con anello. Il numero lo mette il chiamante (colore e posizione).
static func hit(pos: Vector2, crit: bool = false, color: Color = FxPalette.WHITE) -> void:
	if level() <= 0:
		return
	var cols: Array = [FxPalette.WHITE, color, FxPalette.GOLD] if crit else [FxPalette.WHITE, color, FxPalette.CREAM]
	burst("spark", pos, cols, 1.35 if crit else 0.9, 1.5 if crit else 0.8, Vector2.ZERO, 1 if crit else 0)
	var ang := randf_range(-0.9, 0.9)
	var d := Vector2(cos(ang), sin(ang)) * (36.0 if crit else 24.0)
	slash(pos - d, pos + d, color if crit else FxPalette.WHITE, 5.0 if crit else 3.0)
	if crit:
		ring(pos, FxPalette.GOLD, 56.0, 0.4, FxPalette.WHITE, 1)


## Rivelazione di una Cassa: bagliore e particelle CRESCONO con la rarità (dalla scala dei dati), colori ORIGINALI.
## Da chiamare SOLO dopo che il risultato è noto (alla fermata del rullo): non anticipa né suggerisce nulla.
## Rarità bassa: «consolazione elegante» (cornice morbida + un paio di scintille), niente fanfara.
static func reveal(rect: Rect2, rarity_id: String) -> void:
	var col := FxPalette.rarity(rarity_id)
	var t := FxPalette.rarity_t(rarity_id)
	var lv := level()
	if lv <= 0:
		static_mark(rect, col, 0.9)
		return
	var light := FxPalette.lighten(col, 0.5)
	frame_flash(rect, col, 12.0 + 26.0 * t, 0.5 + 0.3 * t, 0.9, 1)
	glow(rect, col, 1.2 + 1.3 * t, 0.7 + 0.5 * t, 4.0)
	if t < 0.2:
		burst("glint", rect.get_center(), [light, FxPalette.WHITE], 0.9, 0.9, rect.size * 0.4, 1)
		return
	burst("star", rect.get_center(), [col, light, FxPalette.WHITE], 0.7 + 0.8 * t, 0.4 + 1.0 * t, rect.size * 0.35, 2)
	if t >= 0.45:
		ring(rect.get_center(), col, 70.0 + 70.0 * t, 0.55 + 0.25 * t, light, 2)
	if t >= 0.7:
		screen_flash(light, 0.10 + 0.10 * t, 0.5)
	if t >= 0.85:
		confetti(Rect2(rect.position + Vector2(0, -20), Vector2(rect.size.x, 10)), 2, [col, light, FxPalette.WHITE, FxPalette.GOLD])


# ------------------------------------------------------------------ comportamenti su nodi

## Scossa a gradini di un nodo (livello 2; con effetti ridotti niente scossa).
static func shake(n: CanvasItem, px: float = 6.0, secs: float = 0.16) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or level() < 2:
		return
	FxShakeBehavior.on(n).start(px, secs)


## Lampo bianco (shader, ~0,08 s) sullo sprite colpito. Max 3 lampi al secondo in tutto il gioco. Livello 1: più tenue.
static func hit_flash(n: CanvasItem, crit: bool = false) -> bool:
	return FxJuice.hit_flash(n, crit)


## Fendente per stile ("melee" arco · "ranged" traccia · "arcane" raggi). `heavy`: critico / tecnica.
static func strike(style: String, from: Vector2, to: Vector2, color: Color = FxPalette.WHITE, heavy: bool = false) -> void:
	FxJuice.strike(style, from, to, color, heavy)


## Spinta fluida di un nodo lungo `direction` (knockback del bersaglio o affondo dell'attaccante), con scossa opzionale.
## Solo livello 2 (con effetti ridotti / riduci animazioni nessun movimento).
static func impact(n: CanvasItem, direction: Vector2, push_px: float = 6.0, shake_px: float = 0.0, secs: float = 0.2) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or level() < 2:
		return
	FxShakeBehavior.on(n).start(minf(shake_px, IMPACT_SHAKE_MAX), secs, direction.normalized() * minf(push_px, IMPACT_PUSH_MAX))


## Mansioni: ciclo dell'attrezzo (colpetti + carica a fine ciclo), colpo al completamento, riposo.
static func tool_start(tool: Control, target: Control, skill_id: String, cycle_s: float, elapsed: float = 0.0) -> void:
	FxToolAnim.start(tool, target, skill_id, cycle_s, elapsed)


static func tool_strike(tool: Control, target: Control, skill_id: String) -> void:
	FxToolAnim.strike(tool, target, skill_id)


static func tool_stop(tool: Control, target: Control = null) -> void:
	FxToolAnim.stop(tool, target)


## Rimbalzo di scala di un Control (livello >= 1).
static func pop(n: Control, factor: float = 1.15, secs: float = 0.2) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or level() <= 0:
		return
	if n.has_meta("fx_pop_tw"):
		var old: Variant = n.get_meta("fx_pop_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.scale = Vector2.ONE
	n.pivot_offset = n.size * 0.5
	var tw := n.create_tween()
	n.set_meta("fx_pop_tw", tw)
	tw.tween_property(n, "scale", Vector2(factor, factor), secs * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2.ONE, secs * 0.6)


## Ingresso con rimbalzo (notifiche): parte piccolo e trasparente.
static func pop_in(n: Control, secs: float = 0.26) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or level() <= 0:
		return
	n.modulate.a = 0.0
	await n.get_tree().process_frame            # dopo il layout: il perno è il centro vero
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	n.pivot_offset = n.size * 0.5
	n.scale = Vector2(0.82, 0.82)
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "modulate:a", 1.0, secs * 0.6)


static func glow_pulse(n: CanvasItem, color: Color, pulses: int = 2, secs: float = 0.5, strength: float = 0.5) -> void:
	FxGlowPulse.pulse(n, color, pulses, secs, strength)


static func breathe(n: CanvasItem, on: bool = true, color: Color = Color(1.0, 0.95, 0.75)) -> void:
	FxGlowPulse.breathe(n, on, color)


static func shine(n: CanvasItem, color: Color = Color.WHITE, secs: float = 0.6, strength: float = 0.75, delay: float = 0.0) -> bool:
	return FxShine.sweep(n, color, secs, strength, delay)


static func number_tick(label: Label, from: float, to: float, secs: float = 0.7, fmt: Callable = Callable()) -> void:
	FxNumberTick.run(label, from, to, secs, fmt)


## Barra che «brilla» al riempimento.
static func bar_flash(n: CanvasItem) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or level() <= 0 or FxGlowPulse.is_active(n):
		return
	FxGlowPulse.pulse(n, FxPalette.GOLD, 1, 0.28, 0.6)


## Morte del mostro: una copia del ritratto si dissolve a blocchi + frammenti.
static func dissolve(src: TextureRect, edge: Color = FxPalette.AMBER, tex: Texture2D = null) -> void:
	if tex == null and src != null:
		tex = src.texture
	if src == null or not is_instance_valid(src) or not src.is_inside_tree() or tex == null or level() <= 0:
		return
	var h := host()
	if h == null:
		return
	var r := src.get_global_rect()
	burst("shard", r.get_center(), [], 1.0, 1.0, r.size * 0.3, 1)
	if level() < 2:
		return
	var ghost := TextureRect.new()
	ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = src.stretch_mode
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = r.position
	ghost.size = r.size
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/fx/dissolve.gdshader")
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("amount", 0.0)
	ghost.material = m
	h.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 0.0, 1.0, 0.5)
	tw.tween_callback(ghost.queue_free)


# ------------------------------------------------------------------ striscioni e cerimonie

## Striscione con luccichio. In coda se ce n'è già uno (max 3 in attesa; i doppioni identici si scartano).
static func banner(title: String, subtitle: String = "", accent: Color = FxPalette.GOLD, icon: Texture2D = null) -> bool:
	var h := host()
	if h == null:
		return false
	for q in _banner_queue:
		if str(q.title) == title and str(q.sub) == subtitle:
			return false
	if _banner_cur != null and is_instance_valid(_banner_cur) and _banner_cur.title == title and _banner_cur.subtitle == subtitle:
		return false
	if _banner_queue.size() >= 3:
		_banner_queue.pop_front()
	_banner_queue.append({"title": title, "sub": subtitle, "accent": accent, "icon": icon})
	_banner_next()
	return true


static func _banner_next() -> void:
	if _banner_cur != null and is_instance_valid(_banner_cur):
		return
	if _banner_queue.is_empty():
		return
	var h := host()
	if h == null:
		return
	var q: Dictionary = _banner_queue.pop_front()
	var b := FxBanner.new()
	b.setup(str(q.title), str(q.sub), q.accent, q.icon)
	b.done.connect(func() -> void:
		_banner_cur = null
		_banner_next())
	_banner_cur = b
	h.add_child(b)


static func banner_active() -> bool:
	return _banner_cur != null and is_instance_valid(_banner_cur)


## Cerimonia saltabile (Stella / Rito / Rifondazione). Ritorna true se è partita. Con «riduci animazioni»: no.
static func ceremony(title: String, subtitle: String = "", accent: Color = FxPalette.GOLD, kind: String = "star") -> bool:
	if level() <= 0:
		return false
	var h := host()
	if h == null:
		return false
	if _ceremony_cur != null and is_instance_valid(_ceremony_cur):
		_ceremony_cur.skip()
	var c := FxCeremony.new()
	c.setup(title, subtitle, accent, kind)
	c.done.connect(func() -> void: _ceremony_cur = null)
	_ceremony_cur = c
	h.add_child(c)
	return true


static func ceremony_active() -> bool:
	return _ceremony_cur != null and is_instance_valid(_ceremony_cur)


## Feedback sui pulsanti (hover/clic) per tutti i Button che compaiono nell'albero. Idempotente.
static func enable_button_feedback(on: bool = true) -> void:
	var h := host()
	if h != null:
		h.set_button_feedback(on)
