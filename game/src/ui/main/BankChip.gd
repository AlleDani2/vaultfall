class_name BankChip
extends TopCurrency
## Pulsante Deposito della barra alta (D6, docs/ui_redesign/06 §3.2): «▣ N liberi» neutro; ambra dalla soglia
## constants.bank.warn_pct (la legge BankSystem.nearly_full, nessun numero qui); rosso a pieno con «PIENO · n» = pezzi nel
## Carro di Ritiro. Il tooltip dice spazi usati/totali, Carro e tasto. Il segnale rosso è l'unico di tutta la barra.

enum State { NORMAL, WARN, FULL }

var state: int = State.NORMAL
var compact: bool = false
var _label: Label


func _ready() -> void:
	super._ready()
	_label = ensure_row().get_node_or_null("BankLabel") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "BankLabel"
		row.add_child(_label)
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.theme_type_variation = &"MonoLabel"


func label() -> Label:
	return _label


## Stato dai dati del Deposito (puro: serve ai test). Ritorna {state, free, used, cap, cart}.
static func read(bank: BankSystem) -> Dictionary:
	if bank == null:
		return {"state": State.NORMAL, "free": 0, "used": 0, "cap": 0, "cart": 0}
	var st := State.NORMAL
	if bank.is_full():
		st = State.FULL
	elif bank.nearly_full():
		st = State.WARN
	return {"state": st, "free": bank.free_slots(), "used": bank.used_slots(), "cap": bank.capacity(), "cart": bank.overflow_count()}


## Aggiorna testo, colore e tooltip. `key_label` = tasto del Deposito (da ShortcutMap).
func refresh(bank: BankSystem, key_label: String) -> void:
	if _label == null:
		return
	var d := read(bank)
	state = int(d.state)
	var free := int(d.free)
	var cart := int(d.cart)
	var txt := ""
	match state:
		State.FULL:
			if compact:
				txt = "▣ 0" + (" · %d" % cart if cart > 0 else "")
			else:
				txt = "▣ " + (Loc.tf("UI_TOP_BANK_FULL_CART", {"n": NumberFormat.fmt(cart)}) if cart > 0 else str(TranslationServer.translate("UI_TOP_BANK_FULL")))
		State.WARN:
			txt = "▣ %s" % NumberFormat.fmt(free) if compact else "▣ " + Loc.tf("UI_TOP_BANK_FREE_WARN_ONE" if free == 1 else "UI_TOP_BANK_FREE_WARN", {"n": NumberFormat.fmt(free)})
		_:
			txt = "▣ %s" % NumberFormat.fmt(free) if compact else "▣ " + Loc.tf("UI_TOP_BANK_FREE_ONE" if free == 1 else "UI_TOP_BANK_FREE", {"n": NumberFormat.fmt(free)})
	if _label.text != txt:
		_label.text = txt
	match state:
		State.FULL:
			tint = UiKit.DANGER
			_label.add_theme_color_override("font_color", UiKit.DANGER_TEXT)
		State.WARN:
			tint = UiKit.BADGE_AMBER
			_label.add_theme_color_override("font_color", UiKit.BADGE_AMBER_TEXT)
		_:
			tint = Color(0, 0, 0, 0)
			_label.remove_theme_color_override("font_color")
	tooltip_text = Loc.tf("UI_TOP_BANK_TIP", {"used": NumberFormat.fmt(int(d.used)), "cap": NumberFormat.fmt(int(d.cap)),
		"cart": NumberFormat.fmt(cart), "key": key_label})
