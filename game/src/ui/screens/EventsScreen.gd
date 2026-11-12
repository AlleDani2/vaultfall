extends GameScreen
## Eventi stagionali (docs/27 §2, T-11.3): evento in corso o prossimo con conto alla rovescia, missioni, Negozio a prezzo fisso,
## Cassa cosmetica con le probabilità, Eco per rigiocare un evento passato e interruttore per disattivare gli eventi.
## Solo presentazione: legge e comanda SeasonalEventSystem ("seasonal"). Le carte si ricostruiscono quando cambia lo stato
## (evento, progressi, possessi), il conto alla rovescia si aggiorna sul posto (≤ 10 Hz, testo una volta al secondo).

var _ev: SeasonalEventSystem
var _col: VBoxContainer
var _sel: String = ""
var _sig: String = ""
var _hint: ScreenKit.KitHint
var _head_line: Label
var _count_line: Label
var _prog: Dictionary = {}           # id missione -> Label del progresso


func open(params: Dictionary) -> void:
	_ev = Game.system("seasonal") as SeasonalEventSystem
	IntroOnce.title_row(self, tr("UI_MENU_EVENTS"), "UI_EVENTS_INTRO" if _ev != null else "", "events")      # frase introduttiva: solo alla prima visita (D17)
	if _ev == null:
		return
	_sel = str(params.get("event", ""))
	_hint = ScreenKit.intro(self, "", "events")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 8)
	scroll.add_child(_col)
	refresh()


func refresh() -> void:
	if _ev == null or _col == null:
		return
	var st := _ev.status()
	if _sel.is_empty() or not _ev.event_def(_sel).has("id"):
		_sel = _default_event(st)
	var parts := PackedStringArray([Loc.locale(), str(st.mode), str(st.event), _sel, str(st.enabled), str(st.trusted), str(st.ok),
		str(_ev.currency_count(_sel)), str(_ev.claimable().size()), _ev.echo_event()])
	for m in _ev.missions(_sel):
		parts.append("%s:%s:%s" % [m.id, m.claimed, m.done])
	for s in _ev.shop(_sel):
		parts.append("%s:%s:%s" % [s.id, s.owned, s.affordable])
	var sig := "|".join(parts)
	if sig != _sig:
		_sig = sig
		_rebuild(st)
	_update(st)
	_refresh_hint(st)


func _default_event(st: Dictionary) -> String:
	for k in ["event", "next_event"]:
		if not str(st.get(k, "")).is_empty():
			return str(st[k])
	var ids := _ev.event_ids()
	return str(ids[0]) if not ids.is_empty() else ""


func _lab(parent: Control, text: String, variation: StringName = &"", dynamic: bool = true) -> Label:
	var l := Label.new()
	if dynamic:
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	parent.add_child(l)
	return l


func _card(parent: Control, edge: Color = Color(ScreenKit.EDGE)) -> VBoxContainer:
	var v := ScreenKit.card(parent, edge, 4)
	v.add_theme_constant_override("separation", 4)
	return v


## «Cosa fare ora»: riscuoti > evento in corso > prossimo evento.
func _refresh_hint(st: Dictionary) -> void:
	if not bool(st.enabled):
		_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_EV_H_OFF"))
	elif not _ev.claimable().is_empty():
		_hint.show_hint(ScreenKit.Kind.TODO, tr("UI_RS_EV_H_CLAIM"))
	elif str(st.mode) == "event":
		_hint.show_hint(ScreenKit.Kind.TODO, Loc.tf("UI_RS_EV_H_NOW", {"name": Loc.t(_ev.event_def(str(st.event)).get("name", {})), "t": NumberFormat.fmt_time(float(st.ends_in_s))}))
	elif not str(st.get("next_event", "")).is_empty():
		_hint.show_hint(ScreenKit.Kind.INFO, Loc.tf("UI_RS_EV_H_NEXT", {"name": Loc.t(_ev.event_def(str(st.next_event)).get("name", {})), "t": NumberFormat.fmt_time(float(st.next_in_s))}))
	else:
		_hint.show_hint(ScreenKit.Kind.INFO, tr("UI_RS_EV_H_NONE"))


func _btn(text: String, cb: Callable, disabled: bool = false, tip: String = "") -> Button:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _rebuild(st: Dictionary) -> void:
	for c in _col.get_children():
		c.queue_free()
	_prog.clear()
	_head_line = null
	_count_line = null
	if not bool(st.enabled):
		var off := _card(_col)
		_lab(off, tr("UI_EVENTS_OFF_TITLE"), &"SectionLabel", false)
		_lab(off, tr("UI_EVENTS_OFF_TEXT"), &"MutedLabel", false)
		var on_btn := _btn(tr("UI_EVENTS_TURN_ON"), _on_toggle.bind(true))
		on_btn.theme_type_variation = &"AccentButton"
		off.add_child(on_btn)
		return
	# stato del calendario
	var box := _card(_col, ScreenKit.accent("events"))
	if not bool(st.ok):
		_lab(box, tr("UI_EVENTS_NO_DATE"), &"MutedLabel", false)
	else:
		_head_line = _lab(box, "", &"SectionLabel")
		_count_line = _lab(box, "", &"MonoLabel")
		if not bool(st.trusted):
			_lab(box, tr("UI_EVENTS_CLOCK_VIRTUAL"), &"MutedLabel", false)
	# selettore dell'evento
	_lab(_col, tr("UI_EVENTS_ALL"), &"SectionLabel", false)
	var sel_row := HFlowContainer.new()
	sel_row.add_theme_constant_override("h_separation", 8)
	_col.add_child(sel_row)
	for eid in _ev.event_ids():
		var d := _ev.event_def(str(eid))
		var b := _btn(Loc.t(d.name), _on_select.bind(str(eid)))
		b.toggle_mode = true
		b.set_pressed_no_signal(str(eid) == _sel)
		ScreenKit.style_tab(b, ScreenKit.accent("events"))
		if str(eid) == str(st.get("event", "")):
			b.tooltip_text = tr("UI_RS_EV_TIP_NOW")
		sel_row.add_child(b)
	_build_event(st)
	# interruttore generale: raro, quindi discreto e in fondo
	var off_btn := _btn(tr("UI_EVENTS_TURN_OFF"), _on_toggle.bind(false), false, tr("UI_RS_EV_TIP_OFF"))
	off_btn.flat = true
	_col.add_child(off_btn)


func _build_event(st: Dictionary) -> void:
	var d := _ev.event_def(_sel)
	if d.is_empty():
		return
	var cur_id := str(d.currency)
	var box := _card(_col, ScreenKit.accent("events"))
	_lab(box, Loc.t(d.name), &"SectionLabel")
	_lab(box, Loc.tf("UI_EVENTS_DATES", {"a": _fmt_md(str(d.dates.start)), "b": _fmt_md(str(d.dates["end"]))}), &"MutedLabel")
	_lab(box, Loc.t(d.intro))
	var cfg: Dictionary = DataRegistry.rules("event_rules").get("seasonal", {})
	var info := _ev.drops_info(_sel)
	var nums := ScreenKit.stat_row(box)
	var s1 := ScreenKit.stat(nums, CrateUi.def_name(cur_id), "UI_RS_EV_TIP_CUR", Color(ScreenKit.GOLD))
	s1.set_value(NumberFormat.fmt(_ev.currency_count(_sel)), "")
	var s2 := ScreenKit.stat(nums, "UI_RS_EV_ST_EARNED", "UI_RS_EV_TIP_EARNED", Color(ScreenKit.GOLD))
	s2.set_value(str(int(info.earned)), "/ %d" % int(info.cap))
	var s3 := ScreenKit.stat(nums, "UI_RS_EV_ST_ECHO", "UI_RS_EV_TIP_ECHO", Color(ScreenKit.GOLD))
	s3.set_value(str(int(info.echo_earned)), "/ %d" % int(info.echo_cap))
	_lab(box, tr("UI_EVENTS_BONUS"), &"MutedLabel", false)
	_lab(box, CrateUi.mods_text(d.modifiers), &"MonoLabel")
	# le spiegazioni (come cade la valuta, missioni, Negozio, Eco) stanno in UNA sezione richiudibile (D17); le probabilità della Cassa no
	var how := IntroOnce.fold(box, "events_how", tr("UI_SCR_SUMMARY_HOW"))
	_lab(how, Loc.tf("UI_EVENTS_HOW", {"m": int(round(float(d.get("currency_drop_every_s", cfg["drop_every_s"])) / 60.0)),
		"cap": int(cfg["max_drops_per_occurrence"]), "cost": int(cfg["crate_cost"])}), &"MutedLabel")
	for k in ["UI_EVENTS_MISSIONS_NOTE", "UI_EVENTS_SHOP_NOTE", "UI_EVENTS_ECHO_NOTE", "UI_EVENTS_RECOVERY"]:
		_lab(how, tr(k), &"MutedLabel", false)

	# missioni
	var mb := _card(_col)
	_lab(mb, tr("UI_EVENTS_MISSIONS"), &"SectionLabel", false)
	if str(st.event) != _sel or str(st.mode) not in ["event", "echo"]:
		_lab(mb, tr("UI_EVENTS_MISSIONS_PAST"), &"MutedLabel", false)
	for m in _ev.missions(_sel):
		var mc := ScreenKit.card(mb, Color("#5f8f5f") if bool(m.claimed) else (Color("#d2b574") if bool(m.done) else Color(ScreenKit.EDGE)), 3)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		mc.add_child(line)
		var txt := VBoxContainer.new()
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(txt)
		_lab(txt, Loc.t(m.name), &"SectionLabel")
		_lab(txt, Loc.t(m.desc), &"MutedLabel")
		var pl := _lab(line, "", &"MonoLabel")
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		_prog[str(m.id)] = [pl, m]
		if bool(m.claimed):
			line.add_child(ScreenKit.pill(tr("UI_EVENTS_CLAIMED"), Color(ScreenKit.GOOD)))
		else:
			var cb2 := _btn(Loc.tf("UI_EVENTS_CLAIM", {"n": int(m.reward)}), _on_claim.bind(str(m.id), str(m.occ)), not bool(m.done), "" if bool(m.done) else tr("UI_RS_EV_WHY_CLAIM"))
			if bool(m.done):
				cb2.theme_type_variation = &"AccentButton"
			line.add_child(cb2)
	_lab(mb, Loc.tf("UI_EVENTS_TITLE_REWARD", {"name": Loc.t(d.title.name)}), &"MutedLabel")

	# negozio
	var sb := _card(_col)
	_lab(sb, tr("UI_EVENTS_SHOP"), &"SectionLabel", false)
	for s in _ev.shop(_sel):
		var sc := ScreenKit.card(sb, Color("#5f8f5f") if bool(s.owned) else (Color("#d2b574") if bool(s.affordable) else Color(ScreenKit.EDGE)), 3)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		sc.add_child(r)
		var nm := _lab(r, CrateUi.def_name(str(s.id)), &"")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind_key := "UI_EVENTS_KIND_PET" if str(s.kind) == "pet" else "UI_EVENTS_KIND_COSMETIC"
		var rar := str(DataRegistry.item(str(s.id)).get("rarity", ""))
		var sub := tr(kind_key) if rar.is_empty() else "%s · %s" % [tr(kind_key), CrateUi.rarity_label(rar)]
		r.add_child(ScreenKit.pill(sub, Color("#8a8f9a")))
		if bool(s.owned):
			r.add_child(ScreenKit.pill(tr("UI_EVENTS_OWNED"), Color(ScreenKit.GOOD)))
		else:
			var missing := maxi(0, int(s.price) - _ev.currency_count(_sel))
			var tip := "" if missing == 0 else Loc.tf("UI_EVENTS_NEED", {"n": missing})
			var bb := _btn(Loc.tf("UI_EVENTS_BUY", {"price": int(s.price)}), _on_buy.bind(str(s.id)), missing > 0, tip)
			if missing == 0:
				bb.theme_type_variation = &"AccentButton"
			r.add_child(bb)
			if missing > 0:
				_lab(sc, tip, &"MutedLabel").add_theme_color_override("font_color", Color(ScreenKit.BAD))

	# cassa evento
	var cb := _card(_col)
	_lab(cb, tr("UI_EVENTS_CRATE"), &"SectionLabel", false)
	_lab(cb, tr("UI_EVENTS_ODDS"), &"MutedLabel", false)
	for o in _ev.crate_odds(_sel):
		var l := _lab(cb, Loc.tf("UI_EVENTS_ODDS_LINE", {"rarity": CrateUi.rarity_label(str(o.rarity)), "pct": CrateUi.pct(float(o.pct)),
			"n": int(o.count)}), &"MonoLabel")
		l.add_theme_color_override("font_color", CrateUi.rarity_color(str(o.rarity)))
	_lab(cb, tr("UI_CRATES_NO_PITY"), &"MutedLabel", false)
	cb.add_child(_btn(tr("UI_EVENTS_OPEN_VAULT"), _on_open_vault.bind(str(d.crate))))

	# recupero: Eco
	var eb := _card(_col)
	_lab(eb, tr("UI_EVENTS_ECHO_HEAD"), &"SectionLabel", false)
	if _ev.echo_event() == _sel:
		_lab(eb, tr("UI_EVENTS_ECHO_ACTIVE"), &"MonoLabel", false)
	else:
		eb.add_child(_btn(tr("UI_EVENTS_ECHO_USE"), _on_echo.bind(_sel)))


func _fmt_md(md: String) -> String:
	return "%s/%s" % [md.substr(3, 2), md.substr(0, 2)] if Loc.locale() == "it" else "%s/%s" % [md.substr(0, 2), md.substr(3, 2)]


func _update(st: Dictionary) -> void:
	if _head_line != null:
		var mode := str(st.mode)
		var nm := Loc.t(_ev.event_def(str(st.event)).get("name", {}))
		if mode == "event":
			_head_line.text = Loc.tf("UI_EVENTS_NOW", {"name": nm})
			_count_line.text = Loc.tf("UI_EVENTS_ENDS_IN", {"t": NumberFormat.fmt_time(float(st.ends_in_s))})
		else:
			var nx := Loc.t(_ev.event_def(str(st.next_event)).get("name", {}))
			_head_line.text = tr("UI_EVENTS_NOTHING_NOW") if mode != "echo" else Loc.tf("UI_EVENTS_ECHO_NOW", {"name": nm,
				"m": int(round(float(DataRegistry.rules("event_rules")["seasonal"]["echo_every_s"]) / 60.0))})
			_count_line.text = Loc.tf("UI_EVENTS_NEXT", {"name": nx, "t": NumberFormat.fmt_time(float(st.next_in_s))}) if not nx.is_empty() else ""
	for m in _ev.missions(_sel):
		if _prog.has(str(m.id)):
			((_prog[str(m.id)] as Array)[0] as Label).text = Loc.tf("UI_EVENTS_PROGRESS",
				{"n": NumberFormat.fmt(int(m.prog)), "qty": NumberFormat.fmt(int(m.qty))})


func _on_toggle(on: bool) -> void:
	_ev.set_events_enabled(on)
	_sig = ""


func _on_select(event_id: String) -> void:
	_sel = event_id
	_sig = ""


func _on_claim(mission_id: String, occ: String) -> void:
	_ev.claim(mission_id, occ)
	_sig = ""


func _on_buy(def_id: String) -> void:
	if _ev.buy(_sel, def_id):
		EventBus.notice.emit("success", Loc.tf("UI_EVENTS_BOUGHT", {"name": CrateUi.def_name(def_id)}), {"digest": "event_buy"})
	_sig = ""


func _on_echo(event_id: String) -> void:
	_ev.set_echo_event(event_id)
	_sig = ""


func _on_open_vault(crate_id: String) -> void:
	EventBus.screen_requested.emit("vault_hall", {"crate": crate_id})
