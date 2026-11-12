class_name UiScale
extends RefCounted
## Scala automatica dell'area logica (docs/ui_redesign/06 §3.17, D2). Logica pura e statica: dalla dimensione della finestra e
## dalla preferenza del giocatore calcola il `content_scale_factor` della finestra radice (stretch canvas_items + expand).
## Le costanti numeriche stanno in UiBands (sono di interfaccia, non di bilanciamento).
##   base   = min(finestra_w / 1280, finestra_h / 720)      scala di Godot a csf 1,0
##   auto   = gradino(base)  ∈ {1,0; 1,5; 2,0; 3,0; 4,0}      scala fisica desiderata: il gradino più alto che sta nella finestra
##            (1600×900 → 1,0 · 1080p → 1,5 · 1440p → 2,0 · 4K → 3,0 · Steam Deck 1280×800 → 1,0): glifi e pixel art nitidi
##   csf    = auto × dimensione_utente / base                (con la scala automatica accesa; ≠ 100% è una scelta esplicita, non a gradini)
##   logico = finestra / (base × csf), mai sotto 1024×576 (la scala fisica si limita di conseguenza)


## Scala di Godot con stretch canvas_items + expand quando il content_scale_factor vale 1,0.
static func base_scale(window: Vector2i) -> float:
	if window.x <= 0 or window.y <= 0:
		return 1.0
	return minf(float(window.x) / UiBands.DESIGN_W, float(window.y) / UiBands.DESIGN_H)


## Scala fisica (pixel dello schermo per pixel logico) che si ottiene con le preferenze date.
## `auto_on` spento = comportamento classico: la scala fisica è base × dimensione_utente.
static func physical_scale(window: Vector2i, user: float, auto_on: bool) -> float:
	var base := base_scale(window)
	var u := clampf(user, UiBands.USER_SCALE_MIN, UiBands.USER_SCALE_MAX)
	var phys := base * u
	if auto_on:
		phys = step_for(base) * u
	if window.x > 0 and window.y > 0:     # vincolo: area logica almeno 1024×576
		var cap := minf(float(window.x) / UiBands.MIN_LOGICAL.x, float(window.y) / UiBands.MIN_LOGICAL.y)
		phys = minf(phys, cap)
	return phys


## Gradino «pulito» della scala fisica per una scala di Godot `base` (finestra / 1280×720): il più alto con
## gradino × tolleranza ≤ base, mai sotto 1,0. L'eccesso di finestra non va in scala ma nell'area logica (layout adattivo).
static func step_for(base: float) -> float:
	var best := float(UiBands.SCALE_STEPS[0])
	for s in UiBands.SCALE_STEPS:
		if float(s) * UiBands.SCALE_STEP_TOLERANCE <= base + 0.0001:
			best = float(s)
	return best


## `content_scale_factor` da assegnare alla finestra radice.
static func content_scale_factor(window: Vector2i, user: float, auto_on: bool) -> float:
	if float(window.x) < UiBands.MIN_WINDOW.x or float(window.y) < UiBands.MIN_WINDOW.y:
		return clampf(user, UiBands.USER_SCALE_MIN, UiBands.USER_SCALE_MAX)       # finestra sotto il minimo supportato (es. i test headless a 64×64): comportamento classico
	var base := base_scale(window)
	if base <= 0.0:
		return 1.0
	return physical_scale(window, user, auto_on) / base


## Area logica che ne risulta (finestra / scala fisica).
static func logical_size(window: Vector2i, csf: float) -> Vector2:
	var phys := base_scale(window) * csf
	if phys <= 0.0:
		return Vector2(window)
	return Vector2(window) / phys


## Vecchi valori di «Dimensione interfaccia» (0,75 / 1,0 / 1,25, assoluti) → dimensione relativa (0,8–1,25).
static func migrate_old_scale(old: float) -> float:
	if old < UiBands.USER_SCALE_MIN:
		return UiBands.USER_SCALE_MIN
	return old


## Voci di «Dimensione interfaccia» (Impostazioni): [scala automatica, dimensione]. Automatica e le percentuali ≠ 100% sono
## relative alla scala automatica; «100%» spegne la scala automatica (area classica 1280×720, come prima di F5).
const SIZE_CHOICES := [[true, 1.0], [true, 0.8], [true, 0.9], [false, 1.0], [true, 1.1], [true, 1.25]]


## Voce del menù che corrisponde alle preferenze (la più vicina se il valore non è esattamente una delle voci).
static func size_index(auto_on: bool, user: float) -> int:
	if not auto_on and is_equal_approx(user, 1.0):
		return 3
	var best := 0
	var best_d := 1e9
	for i in SIZE_CHOICES.size():
		if not bool(SIZE_CHOICES[i][0]):
			continue
		var d := absf(float(SIZE_CHOICES[i][1]) - user)
		if d < best_d - 0.0001:
			best_d = d
			best = i
	return best
