class_name CodexTotalsView
extends VBoxContainer
## Scheda «Totali» del Compendio (docs/15 §2, UI-A G16): percentuale di completamento totale e per sezione, e i contatori
## a vita (uccisioni, azioni, casse aperte, ★ trovate, oro guadagnato, tempo giocato e offline).

var _codex: CodexSystem
var _bars: VBoxContainer
var _counters: GridContainer
var _total: Label
var _total_bar: ProgressBar
var _sig := ""


func setup(codex: CodexSystem) -> void:
	_codex = codex
	add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = "UI_UIA_CODEX_TOTAL"
	t.theme_type_variation = &"SectionLabel"
	add_child(t)
	_total = Label.new()
	_total.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_total.theme_type_variation = &"NumberLabel"
	add_child(_total)
	_total_bar = ProgressBar.new()
	_total_bar.show_percentage = false
	_total_bar.custom_minimum_size = Vector2(0, 18)
	add_child(_total_bar)
	_bars = VBoxContainer.new()
	_bars.add_theme_constant_override("separation", 6)
	add_child(_bars)
	var c := Label.new()
	c.text = "UI_UIA_CODEX_LIFETIME"
	c.theme_type_variation = &"SectionLabel"
	add_child(c)
	var help := Label.new()
	help.text = "UI_UIA_CODEX_LIFETIME_HELP"
	help.theme_type_variation = &"MutedLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	_counters = GridContainer.new()
	_counters.columns = 2
	_counters.add_theme_constant_override("h_separation", 24)
	_counters.add_theme_constant_override("v_separation", 4)
	add_child(_counters)
	refresh()


func refresh() -> void:
	var comp := _codex.completion()
	var life := _codex.lifetime()
	var sig := "%s|%s|%s|%d" % [Loc.locale(), JSON.stringify(comp), JSON.stringify(life), floori(float(life.playtime_s) / 60.0)]
	if sig == _sig:
		return
	_sig = sig
	_total.text = Loc.tf("UI_UIA_CODEX_TOTAL_LINE", {"pct": str(comp.pct_text), "have": NumberFormat.fmt(int(comp.have)), "total": NumberFormat.fmt(int(comp.total))})
	_total_bar.max_value = maxf(1.0, float(comp.total))
	_total_bar.value = float(comp.have)
	for c in _bars.get_children():
		c.queue_free()
	for sec in ["items", "monsters", "uniques", "pets"]:
		var p: Dictionary = comp[sec]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nm := Label.new()
		nm.text = "UI_UIA_CODEX_SEC_" + sec.to_upper()
		nm.custom_minimum_size.x = 150
		row.add_child(nm)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(p.total))
		bar.value = float(p.have)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(120, 14)
		row.add_child(bar)
		var num := Label.new()
		num.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		num.theme_type_variation = &"MonoLabel"
		num.custom_minimum_size.x = 150
		num.text = "%s / %s  (%s)" % [NumberFormat.fmt(int(p.have)), NumberFormat.fmt(int(p.total)), CodexSystem.pct_text(int(p.have), int(p.total))]
		row.add_child(num)
		_bars.add_child(row)
	for c in _counters.get_children():
		c.queue_free()
	for k in ["kills", "actions", "crates", "stars", "gold", "playtime_s", "offline_s"]:
		var l := Label.new()
		l.text = "UI_UIA_CODEX_LT_" + k.to_upper()
		l.theme_type_variation = &"MutedLabel"
		_counters.add_child(l)
		var v := Label.new()
		v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		v.theme_type_variation = &"MonoLabel"
		v.text = NumberFormat.fmt_time(float(life[k])) if k.ends_with("_s") else NumberFormat.fmt(int(life[k]))
		_counters.add_child(v)
