class_name UiBands
extends RefCounted
## Costanti di interfaccia della cornice (NON di bilanciamento: la regola 2 di CLAUDE.md non si applica) e bande di larghezza
## (docs/ui_redesign/06 §3.17). Un solo file: qui stanno anche le costanti della scala automatica (UiScale).

## Area logica di progetto e scala automatica (UiScale): 1280×720 è il minimo di progetto. La scala fisica automatica scatta
## su gradini che tengono nitidi i glifi e la pixel art (revisione grafica 1.0, problema 1): mai valori frazionari come 1,04.
const DESIGN_W := 1280.0
const DESIGN_H := 720.0
const SCALE_STEPS := [1.0, 1.5, 2.0, 3.0, 4.0]
const SCALE_STEP_TOLERANCE := 0.95      # un gradino vale già da 95% del suo valore (1080p con barre della finestra: 1,43 → 1,5)
const MIN_LOGICAL := Vector2(1024.0, 576.0)
const MIN_WINDOW := Vector2(960.0, 540.0)      # minimo della finestra (WindowFit.MIN_SIZE)
const USER_SCALE_MIN := 0.8
const USER_SCALE_MAX := 1.25

## Layout adattivo (QA overflow, resoconto 107): larghezza LOGICA (dopo stretch e «Scala interfaccia») sotto cui
## la colonna destra diventa un cassetto sopra il contenuto e la barra in alto usa etichette brevi.
const NARROW_W := 1100.0
const COMPACT_W := 1000.0
const WIDE_W := 1440.0
const SIDEBAR_W := 200.0
const SIDEBAR_W_NARROW := 168.0

const BAND_NARROW := "narrow"
const BAND_NORMAL := "normal"
const BAND_WIDE := "wide"


## Banda di larghezza logica: stretta < NARROW_W, normale fino a WIDE_W (escluso), larga da WIDE_W in su.
static func band(width: float) -> String:
	if width < NARROW_W:
		return BAND_NARROW
	if width < WIDE_W:
		return BAND_NORMAL
	return BAND_WIDE
