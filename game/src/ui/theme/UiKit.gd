class_name UiKit
extends RefCounted
## Ponte tra i telai UI generati (assets/ui/frames, `python tools/make_ui_frames.py`) e le schermate: accenti di sezione,
## cornici di rarità, riempimento tinto delle barre, stati vuoti con illustrazione. Solo presentazione, nessuna regola di gioco.
## Il tema vero (colori, font, pulsanti…) è main_theme.tres, generato da scripts/build_theme.gd.

const THEME_DIR := "res://src/ui/theme/"
const FRAMES := "res://assets/ui/frames/"
const RARITY_KEYS: PackedStringArray = ["common", "rare", "epic", "legendary", "mythic", "relic"]

## Colori semantici condivisi della cornice (docs/ui_redesign/06 §2.2 D14, §3.3). In F0 sono solo DEFINIZIONI: le usano le
## fasi F2 (barra alta, chip Deposito), F4 (segnali del menù), F8 (chip di rischio). Ogni coppia sfondo/testo ha contrasto
## ≥ 4,5:1 (verificato da `contrast()` in test_ui_budget.gd).
## Rosso = pericolo o perdita in corso; ambra = azione possibile ora; puntino = novità non urgente; neutro = informazione.
const DANGER := Color("#b8472a")              # sfondo del segnale di pericolo (era BADGE_COLOR del menù)
const DANGER_TEXT := Color("#fff4e0")         # testo sul rosso: 4,85:1
const BADGE_AMBER := Color("#e0a43a")         # sfondo del numero ambra «azione possibile ora»
const BADGE_AMBER_TEXT := Color("#1a1408")    # testo scuro sull'ambra: 8,3:1
const DOT := Color("#f0d9a0")                 # puntino di novità (6 px), oro chiaro (non è testo)
const RISK_OK := Color("#2f6b46")             # chip di rischio: «Sicuro in idle»
const RISK_OK_TEXT := Color("#f2fff6")        # 6,2:1
const RISK_WARN := Color("#e0a43a")           # chip di rischio: «Rischio»
const RISK_WARN_TEXT := Color("#1a1408")      # 8,3:1
const RISK_BAD := Color("#b8472a")            # chip di rischio: «Pericolo»
const RISK_BAD_TEXT := Color("#fff4e0")       # 4,85:1
## Variazione di tema per la frase «a cosa serve» richiudibile di ogni schermata (generata da scripts/build_theme.gd).
const INTRO_HINT := &"IntroHint"

static var _manifest: Dictionary = {}
static var _themes: Dictionary = {}


## Tema di sovrapposizione per la sezione del menù (null = accento di default, ottone).
## Mansioni = oliva, Avventura = ruggine, Progresso = viola/azzurro, Città/Riepilogo = ottone.
static func accent_theme(section: String) -> Theme:
	if not ["skills", "adventure", "progress"].has(section):
		return null
	if not _themes.has(section):
		var path := "%saccent_%s.tres" % [THEME_DIR, section]
		_themes[section] = load(path) as Theme if ResourceLoader.exists(path) else null
	return _themes[section]


## Rapporto di contrasto WCAG tra due colori opachi (1 = identici, 21 = nero su bianco).
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var ch: Array[float] = []
	for v in [c.r, c.g, c.b]:
		ch.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(FRAMES + "frames.json", FileAccess.READ)
		if f != null:
			_manifest = JSON.parse_string(f.get_as_text())
	return _manifest


static func texture(frame: String) -> Texture2D:
	var p := FRAMES + frame + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Chiave di rarità riconosciuta dai telai (le sconosciute diventano "common").
static func rarity_key(rarity: String) -> String:
	return rarity if RARITY_KEYS.has(rarity) else "common"


## Variazione di tema di un riquadro: "Card<Rarità>" (cornice grande) oppure "Slot<Rarità>" (cornice sottile per le icone).
static func rarity_variation(rarity: String, big: bool = false) -> StringName:
	return StringName(("Card" if big else "Slot") + rarity_key(rarity).capitalize())


## Riempimento tinto per le barre: il telaio "progress_fill_white" moltiplicato per il colore (HP rosso, ecc.).
static func tinted_fill(col: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture("progress_fill_white")
	var m: Array = manifest().get("progress_fill_white", {}).get("margin", [2, 2, 2, 2])
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.modulate_color = col
	return sb


## Stato vuoto: piccola illustrazione + testo smorzato (kind: chest, scroll, shelf). `text_key` è una chiave del CSV.
static func empty_state(kind: String, text_key: String) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.texture = texture("empty_" + kind)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var l := Label.new()
	l.text = text_key
	l.theme_type_variation = &"MutedLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return box
