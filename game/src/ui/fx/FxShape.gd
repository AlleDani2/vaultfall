class_name FxShape
extends RefCounted
## Una forma disegnata da FxCanvas (numero, anello, graffio, cornice, bagliore, oggetto in volo). Gli oggetti sono
## preallocati in un pool fisso: lo stato si riscrive, non si crea nulla durante il gioco.

enum Kind { NONE, NUMBER, RING, SLASH, FRAME, GLOW, FLY, FLASH, VIGNETTE, ARC, BOLT, RAYS }

const TRAIL_N := 8

var kind: int = Kind.NONE
var age: float = 0.0
var life: float = 1.0
var delay: float = 0.0
var pos: Vector2 = Vector2.ZERO
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
var ctrl: Vector2 = Vector2.ZERO
var rect: Rect2 = Rect2()
var color: Color = Color.WHITE
var color2: Color = Color.WHITE
var size: float = 16.0            # NUMBER: px del font · RING: raggio finale · GLOW: spessore
var amount: float = 1.0           # intensità / numero di pixel dell'anello
var text: String = ""
var texture: Texture2D = null
var target: Variant = null        # nodo che «riceve» l'oggetto in volo (pop all'arrivo)
var arrive_burst: String = ""
var trail: PackedVector2Array = PackedVector2Array()
var trail_i: int = 0
var priority: int = 0
var vel: Vector2 = Vector2.ZERO


func _init() -> void:
	trail.resize(TRAIL_N)


func active() -> bool:
	return kind != Kind.NONE


func reset() -> void:
	kind = Kind.NONE
	age = 0.0
	delay = 0.0
	texture = null
	target = null
	arrive_burst = ""
	text = ""
	trail_i = 0
	priority = 0


## 0..1 dell'avanzamento (dopo l'eventuale ritardo).
func t() -> float:
	return clampf((age - delay) / maxf(0.0001, life), 0.0, 1.0)
