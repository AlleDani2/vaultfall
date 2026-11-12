class_name NumberFormat
extends RefCounted
## Formattazione dei numeri (docs/16 §5). Funzioni pure: lingua e modo passati esplicitamente;
## le scorciatoie fmt()/fmt_time()/fmt_pct() usano la lingua attiva e le impostazioni.
## - sotto 100.000: separatore delle migliaia della lingua (IT 12.450 · EN 12,450);
## - da 100.000: 3 cifre significative + K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc (IT "1,25 M" · EN "1.25M");
## - oltre Dc: notazione scientifica (1,25e36);
## - modi: "short" (predefinito) · "full" · "scientific".
## Le convenzioni tipografiche per lingua (separatori, suffissi) stanno in LOCALE_FORMATS; le unità di tempo
## sono stringhe d'interfaccia (UI_TIME_*) nel CSV.

const SHORT_FROM := 100000.0
## Testo per un valore non rappresentabile (NaN, divisione per zero): mai un errore di script nella UI.
const NOT_A_NUMBER := "-"
const INFINITY_TEXT := "∞"
## Oltre questa durata (1e9 giorni) il testo e' «∞»: un int a 64 bit andrebbe in overflow nel calcolo dei giorni.
const MAX_DURATION_S := 8.64e13
const LOCALE_FORMATS := {
	"en": {"thousands": ",", "decimal": ".", "suffix_sep": "",
		"suffixes": ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]},
	"it": {"thousands": ".", "decimal": ",", "suffix_sep": " ",
		"suffixes": ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]},
}


static func _lf(lang: String) -> Dictionary:
	return LOCALE_FORMATS.get(lang, LOCALE_FORMATS["en"])


## Intero con separatore delle migliaia (valori fino a ~9e18; oltre si usa la notazione scientifica).
static func group_int(n: float, lang: String = "en") -> String:
	if not is_finite(n):
		return _non_finite(n)
	var a := absf(n)
	if a >= 9.0e18:
		return scientific(n, lang)
	var s := str(Formulas.rhalf(a))
	var neg := n < 0.0 and s != "0"             # -0.0001 -> "0", non "-0"
	var sep: String = _lf(lang).thousands
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if neg else "") + out


static func decimal(n: float, decimals: int, lang: String = "en") -> String:
	if not is_finite(n):
		return _non_finite(n)
	var s: String = ("%." + str(maxi(0, decimals)) + "f") % Formulas.rdec(n, maxi(0, decimals))
	return s.replace(".", _lf(lang).decimal)


static func _non_finite(n: float) -> String:
	if is_inf(n):
		return INFINITY_TEXT if n > 0.0 else "-" + INFINITY_TEXT
	return NOT_A_NUMBER


static func scientific(n: float, lang: String = "en") -> String:
	if not is_finite(n):
		return _non_finite(n)
	if n == 0.0:
		return "0"
	var a := absf(n)
	var e := int(floor(log(a) / log(10.0)))
	var m := a / pow(10.0, e)
	if Formulas.rdec(m, 2) >= 10.0:
		m /= 10.0
		e += 1
	return ("-" if n < 0.0 else "") + decimal(m, 2, lang) + "e" + str(e)


## Numero secondo docs/16 §5.
static func format_number(n: float, mode: String = "short", lang: String = "en") -> String:
	if not is_finite(n):
		return _non_finite(n)
	var a := absf(n)
	if a < SHORT_FROM or mode == "full":
		return group_int(n, lang)
	if mode == "scientific":
		return scientific(n, lang)
	var lf := _lf(lang)
	var suffixes: Array = lf.suffixes
	var idx := int(floor(log(a) / log(1000.0)))
	var v := a / pow(1000.0, idx)
	var dec := 2 - int(floor(log(v) / log(10.0)))
	if Formulas.rdec(v, dec) >= 1000.0:      # 999.95K -> 1.00M
		idx += 1
		v /= 1000.0
		dec = 2
	if idx >= suffixes.size():
		return scientific(n, lang)
	return ("-" if n < 0.0 else "") + decimal(v, maxi(0, dec), lang) + lf.suffix_sep + str(suffixes[idx])


## Quantità nella cella del Deposito (F16, docs/ui_redesign/02 §5.3): 1…9.999 intero con le migliaia della lingua; da 10.000
## 3 cifre significative con zeri finali tolti e suffisso («12,3 K», «123 K», «1,25 M»; EN «12.3K», «1.25M»). Il valore esatto
## sta nel tooltip. Nessuna soglia di colore: la quantità non dipende dal colore.
static func cell(n: float, lang: String = "en") -> String:
	if not is_finite(n):
		return _non_finite(n)
	var a := absf(n)
	if a < 10000.0:
		return group_int(n, lang)
	var lf := _lf(lang)
	var suffixes: Array = lf.suffixes
	var idx := int(floor(log(a) / log(1000.0)))
	var v := a / pow(1000.0, idx)
	var dec := 2 - int(floor(log(v) / log(10.0)))
	if Formulas.rdec(v, maxi(0, dec)) >= 1000.0:        # 999.999 -> 1 M
		idx += 1
		v /= 1000.0
		dec = 2
	if idx >= suffixes.size():
		return scientific(n, lang)
	var txt := decimal(v, maxi(0, dec), lang)
	var dsep: String = lf.decimal
	if txt.contains(dsep):                               # «12,30» -> «12,3»; «1,00» -> «1»
		txt = txt.rstrip("0").trim_suffix(dsep)
	return ("-" if n < 0.0 else "") + txt + lf.suffix_sep + str(suffixes[idx])


## Percentuale: 1 decimale sotto il 10%, intera sopra (pct in punti percentuali: 0.3 -> "0,3%").
static func format_pct(pct: float, lang: String = "en") -> String:
	if not is_finite(pct):
		return _non_finite(pct)
	if absf(pct) < 10.0:
		return decimal(Formulas.rdec(pct, 1), 1, lang) + "%"
	return str(Formulas.rhalf(pct)) + "%"


## Durata: "3,2 s" · "18 s" · "18 min" · "4 h 12 min" · "3 g 2 h". units: {"s","min","h","d"} già tradotte.
static func format_duration(seconds: float, units: Dictionary, lang: String = "en") -> String:
	if is_nan(seconds):
		return NOT_A_NUMBER
	if seconds >= MAX_DURATION_S:
		return INFINITY_TEXT
	var s := maxf(0.0, seconds)
	if s < 10.0:
		return decimal(Formulas.rdec(s, 1), 1, lang) + " " + units.s
	if s < 60.0:
		return "%d %s" % [int(floor(s)), units.s]
	var total_min := int(floor(s / 60.0))
	if s < 3600.0:
		return "%d %s" % [total_min, units.min]
	var h := int(floor(s / 3600.0))
	if s < 86400.0:
		var m := total_min - h * 60
		return "%d %s" % [h, units.h] + (" %d %s" % [m, units.min] if m > 0 else "")
	var d := int(floor(s / 86400.0))
	var hh := h - d * 24
	return "%d %s" % [d, units.d] + (" %d %s" % [hh, units.h] if hh > 0 else "")


# ------------------------------------------------------------------ scorciatoie (lingua e impostazioni attive)

static func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func fmt(n: float) -> String:
	var mode := "short"
	var st: Node = Engine.get_main_loop().root.get_node_or_null("/root/Settings") if Engine.get_main_loop() is SceneTree else null
	if st != null:
		mode = str(st.get_value("number_format"))
	return format_number(n, mode, _lang())


## Prezzo unitario: sotto 10 oro i decimali contano («0,3 oro» per un pesce da 130 pezzi, non «0 oro»); da 10 in su come fmt (PT118).
static func fmt_unit(n: float) -> String:
	if n >= 10.0 or is_equal_approx(n, roundf(n)):
		return fmt(n)
	return decimal(n, 2 if n < 1.0 else 1, _lang())


## Valore con segno per i bonus («+5», «+0,05», «−2,5»): i valori sotto 1 non si arrotondano a «+0» (PT118).
static func fmt_signed(v: float) -> String:
	var a := absf(v)
	var sign := "+" if v >= 0.0 else "−"
	if a >= 1000.0 or is_equal_approx(a, roundf(a)):
		return sign + fmt(a)
	return sign + decimal(a, 2 if a < 1.0 else 1, _lang())


static func fmt_pct(pct: float) -> String:
	return format_pct(pct, _lang())


static func fmt_cell(n: float) -> String:
	return cell(n, _lang())


static func fmt_time(seconds: float) -> String:
	var units := {"s": TranslationServer.translate("UI_TIME_S"), "min": TranslationServer.translate("UI_TIME_MIN"),
		"h": TranslationServer.translate("UI_TIME_H"), "d": TranslationServer.translate("UI_TIME_D")}
	return format_duration(seconds, units, _lang())
