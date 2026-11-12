class_name Accessibility
extends RefCounted
## Accessibilità (1.0, docs/review_1_0/03 punto 6): modalità per daltonici, alto contrasto, testo grande.
## Regola D-6: si cambia solo il COLORE, mai la geometria né i PNG. Daltonismo e contrasto sono un filtro sull'immagine
## finale (VisionFilter + vision_filter.gdshader); il testo grande scala i corpi dei caratteri del tema.
## Questa classe: valori ammessi, parametri del filtro e calcolo identico a quello dello shader (per test e anteprime).

const COLORBLIND_MODES: PackedStringArray = ["off", "protanopia", "deuteranopia", "tritanopia"]
const TEXT_SCALES: Array[float] = [1.0, 1.25, 1.5]
const HIGH_CONTRAST := 1.35
const HIGH_SATURATION := 1.12

## Matrici di simulazione (Machado et al. 2009, gravità 1,0), righe.
const SIM := {
	"protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	"deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	"tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}

static var _base_sizes: Dictionary = {}          # tema → {"default": int, "types": {tipo: {nome: int}}} dei corpi originali


static func mode_index(mode: String) -> int:
	return maxi(0, COLORBLIND_MODES.find(mode))


## Parametri dello shader per le impostazioni date: {"mode": int, "contrast": float, "saturation": float, "active": bool}.
static func filter_params(colorblind: String, high_contrast: bool) -> Dictionary:
	var m := mode_index(colorblind)
	return {
		"mode": m,
		"contrast": HIGH_CONTRAST if high_contrast else 1.0,
		"saturation": HIGH_SATURATION if high_contrast else 1.0,
		"active": m > 0 or high_contrast,
	}


static func _simulate(c: Color, mode: String) -> Color:
	var m: Array = SIM[mode]
	return Color(
		m[0][0] * c.r + m[0][1] * c.g + m[0][2] * c.b,
		m[1][0] * c.r + m[1][1] * c.g + m[1][2] * c.b,
		m[2][0] * c.r + m[2][1] * c.g + m[2][2] * c.b, c.a)


## Lo stesso calcolo dello shader su un colore (correzione daltonizzante + contrasto/saturazione).
static func daltonize(c: Color, mode: String, contrast: float = 1.0, saturation: float = 1.0) -> Color:
	var o := Color(c.r, c.g, c.b, c.a)
	if SIM.has(mode):
		var s := _simulate(c, mode)
		var er := c.r - s.r
		var eg := c.g - s.g
		var eb := c.b - s.b
		if mode == "tritanopia":
			o = Color(clampf(c.r - eb, 0.0, 1.0), clampf(c.g + eb, 0.0, 1.0), c.b, c.a)
		else:
			o = Color(c.r, clampf(c.g + 0.7 * er + eg, 0.0, 1.0), clampf(c.b + 0.7 * er + eb, 0.0, 1.0), c.a)
	var lum := o.r * 0.299 + o.g * 0.587 + o.b * 0.114
	var r := lerpf(lum, o.r, saturation)
	var g := lerpf(lum, o.g, saturation)
	var b := lerpf(lum, o.b, saturation)
	return Color(clampf((r - 0.5) * contrast + 0.5, 0.0, 1.0), clampf((g - 0.5) * contrast + 0.5, 0.0, 1.0),
		clampf((b - 0.5) * contrast + 0.5, 0.0, 1.0), c.a)


## Distanza di colore percepita grossolana (somma dei canali) tra due colori: usata dal test per dire che il filtro distingue.
static func color_gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## Scala i corpi dei caratteri del tema (`scale` 1,0 / 1,25 / 1,5). Ricorda i valori originali alla prima chiamata, quindi
## è ripetibile e 1,0 li riporta com'erano. I corpi impostati a mano in un controllo (override) non cambiano.
static func apply_text_scale(theme: Theme, scale: float) -> void:
	if theme == null:
		return
	var key := theme.get_instance_id()
	if not _base_sizes.has(key):
		var types := {}
		for t in theme.get_font_size_type_list():
			var names := {}
			for n in theme.get_font_size_list(t):
				names[str(n)] = theme.get_font_size(n, t)
			types[str(t)] = names
		_base_sizes[key] = {"default": theme.default_font_size, "types": types}
	var base: Dictionary = _base_sizes[key]
	var f := clampf(scale, 1.0, 1.5)
	if int(base.default) > 0:
		theme.default_font_size = int(round(float(base.default) * f))
	for t in base.types:
		for n in base.types[t]:
			theme.set_font_size(n, t, int(round(float(base.types[t][n]) * f)))


## Il tema del progetto (quello di project.godot), se c'è.
static func project_theme() -> Theme:
	return ThemeDB.get_project_theme()
