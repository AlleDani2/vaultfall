class_name FxHost
extends CanvasLayer
## Contenitore unico degli effetti: un CanvasLayer sopra l'interfaccia (sopravvive ai cambi di scena), con la tela
## FxCanvas e il pool di particelle FxBurst. Un solo _process per tutti gli effetti; con niente di attivo non fa nulla.
## Misura il proprio costo (media mobile in µs per frame) per i controlli di prestazioni.

const LAYER := 90
const STEP_MAX := 0.05         # un frame lento non fa «saltare» le animazioni

var canvas: FxCanvas
var burst: FxBurst
var ema_us: float = 0.0        # costo medio dell'aggiornamento per frame (esclude il disegno del motore)
var peak_us: float = 0.0
var frames_active: int = 0
var last_flash_ms: int = -100000
var arrivals: int = 0


func _init() -> void:
	layer = LAYER
	name = "FxHost"
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = FxCanvas.new()
	canvas.name = "Canvas"
	canvas.host = self
	add_child(canvas)
	burst = FxBurst.new()
	burst.name = "Burst"
	add_child(burst)


func is_busy() -> bool:
	return canvas.active_count() > 0 or burst.live_particles() > 0


func _process(delta: float) -> void:
	var busy := is_busy()
	if not busy:
		burst.step(0.0)
		return
	var t0 := Time.get_ticks_usec()
	var dt := minf(delta, STEP_MAX)
	canvas.step(dt)
	burst.step(dt)
	var us := float(Time.get_ticks_usec() - t0)
	frames_active += 1
	ema_us = lerpf(ema_us, us, 0.1) if frames_active > 1 else us
	peak_us = maxf(peak_us * 0.995, us)


## Un oggetto in volo è arrivato: scintilla a destinazione e «pop» del bersaglio.
func on_fly_arrived(s: FxShape) -> void:
	arrivals += 1
	if not s.arrive_burst.is_empty():
		burst.spawn(s.arrive_burst, s.to, [], 0.7, 0.6)
	if is_instance_valid(s.target) and s.target is Control:
		Fx.pop(s.target as Control, 1.12, 0.18)


## Hover/clic dei pulsanti: un respiro di luce leggero al passaggio e 3 pixel al clic. Si aggancia ai nodi nuovi.
func set_button_feedback(on: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	if on and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	elif not on and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is PanelContainer and (n as PanelContainer).theme_type_variation == &"CardPanel":
		FxUi.card_hover(n as Control)                 # riquadri-carta: il bordo si illumina al passaggio (idempotente)
		return
	if n is Button and not n.has_meta("fx_btn"):
		n.set_meta("fx_btn", true)
		(n as Button).mouse_entered.connect(_btn_hover.bind(n))
		(n as Button).button_down.connect(_btn_down.bind(n))


func _btn_hover(b: Button) -> void:
	if is_instance_valid(b) and not b.disabled and Fx.level() >= 1 and not FxGlowPulse.is_active(b):
		FxGlowPulse.pulse(b, Color.WHITE, 1, 0.22, 0.18)


func _btn_down(b: Button) -> void:
	if is_instance_valid(b) and not b.disabled and Fx.level() >= 2:
		burst.spawn("glint", b.get_global_mouse_position(), [], 0.6, 0.6)
		FxUi.press(b)                                  # si «schiaccia» e torna con un piccolo rimbalzo


func clear_all() -> void:
	canvas.clear_all()
	burst.clear_all()
