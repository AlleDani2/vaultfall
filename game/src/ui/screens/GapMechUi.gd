class_name GapMechUi
extends RefCounted
## Pezzi di interfaccia delle meccaniche colmate da GAP-MECCANICHE (audit 71): Rango degli oggetti (G03), Clessidra del
## Custode (G05). Solo presentazione: i numeri e le decisioni sono di PrestigeSystem e Hourglass; ogni azione che spende
## qualcosa chiede conferma mostrando l'anteprima ESATTA (costo e beneficio).


static func _line(parent: Control, text: String, variation: String = "") -> Label:
	var l := CombatUi.text_label(variation, true)
	l.text = text
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ Rango (G03)

## Testo dell'anteprima: «Rango 3 → 4 (massimo 24) · costo · Danno 120 → 125 …».
static func rank_text(p: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(Loc.tf("UI_GAPM_RANK_LINE", {"from": int(p.rank), "to": int(p.rank_after), "cap": int(p.cap)}))
	lines.append(Loc.tf("UI_GAPM_RANK_COST", {"essence": NumberFormat.fmt(float(p.essence)), "have_e": NumberFormat.fmt(float(p.essence_have)),
		"gold": NumberFormat.fmt(float(p.gold)), "have_g": NumberFormat.fmt(float(p.gold_have))}))
	var stats := PackedStringArray()
	for s in p.get("stats", []):
		stats.append("%s %s → %s" % [TranslationServer.translate("UI_HERO_STAT_" + str(s.key).to_upper()),
			NumberFormat.decimal(float(s.before), 1, Loc.locale()), NumberFormat.decimal(float(s.after), 1, Loc.locale())])
	if not stats.is_empty():
		lines.append(Loc.tf("UI_GAPM_RANK_GAIN", {"stats": ", ".join(stats)}))
	return "\n".join(lines)


## Riquadro «Rango» per un'istanza: anteprima, motivo se bloccato, pulsante con conferma. `on_done` dopo la salita,
## differita: ricostruisce il riquadro (e la finestra di conferma) e non si può fare mentre il segnale è in corso.
static func rank_box(uid: String, on_done: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var ps := Game.system("prestige") as PrestigeSystem
	# nessuna meccanica prima del suo sblocco (Era II): fino ad allora il riquadro non compare
	if ps == null or uid.is_empty() or not ps.is_rankable(uid) or not ps.ranks_unlocked():
		return box
	var p := ps.preview_rank_up(uid)
	box.add_child(CombatUi.label("UI_GAPM_RANK_TITLE", "SectionLabel"))
	_line(box, rank_text(p))
	if not bool(p.ok):
		_line(box, tr_of(str(p.reason)), "MutedLabel")
	var b := Button.new()
	b.text = "UI_GAPM_RANK_BUTTON"
	b.disabled = not bool(p.ok)
	b.pressed.connect(func() -> void:
		var now := ps.preview_rank_up(uid)
		if not bool(now.ok):
			return
		CrateUi.confirm(box, Loc.tf("UI_GAPM_RANK_CONFIRM", {"text": rank_text(now)}), func() -> void:
			if not ps.do_rank_up(uid).is_empty():
				EventBus.notice.emit("success", Loc.tf("UI_GAPM_RANK_DONE", {"rank": int(now.rank_after)}), {})
				on_done.call_deferred()))
	box.add_child(b)
	return box


static func tr_of(key: String) -> String:
	return TranslationServer.translate(key)


# ------------------------------------------------------------------ Clessidra del Custode (G05)

## Riquadro «Usa la Clessidra» (Deposito): limiti spiegati, motivo se non si può, conferma e Bentornato.
static func hourglass_box(on_done: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if Game.ctx == null or not GameState.active:
		return box
	var p := Hourglass.preview(Game.ctx)
	_line(box, tr_of("UI_GAPM_HG_RULES"), "MutedLabel")
	if not bool(p.ok):
		_line(box, tr_of(str(p.reason)), "MutedLabel")
	var b := Button.new()
	b.text = "UI_GAPM_HG_USE"
	b.disabled = not bool(p.ok)
	b.pressed.connect(func() -> void:
		CrateUi.confirm(box, Loc.tf("UI_GAPM_HG_CONFIRM", {"time": NumberFormat.fmt_time(float(p.seconds))}), func() -> void:
			Game.use_hourglass()
			on_done.call_deferred()))
	box.add_child(b)
	return box
