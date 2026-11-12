class_name ChallengeView
extends WorkshopView
## Scheda Sfida dei Collezionisti (docs/09 §12): classifica settimanale contro 3 rivali PNG. Punteggio = punti-rarità
## di ciò che TROVI aprendo casse nella settimana. Nessuna scommessa, nessun oggetto in palio, nessuna penalità se
## salti una settimana (docs/24 R-LEG-3, R-LEG-6). I premi (Schegge e chiavi) restano in attesa finché non li ritiri.

var _msg: String = ""


func signature() -> String:
	if not crates.challenge_unlocked():
		return "locked"
	var info := crates.challenge_info()
	return "%d|%d|%d|%s|%s" % [int(info.score), int(float(info.progress) * 100.0), bank_revision(), str(crates.challenge_pending().get("week", -1)), _msg]


func build() -> void:
	if not crates.challenge_unlocked():
		_locked_note(CrateSystem.TOKEN_CHALLENGE, "UI_VUX_CH_LOCKED_TITLE", "UI_VUX_CH_LOCKED_WHAT")
		_label(tr("UI_VUX_CH_PREVIEW_PRIZE"))
		return
	if not _msg.is_empty():
		_label(_msg, false)

	# --- premio in attesa
	var pend := crates.challenge_pending()
	if not pend.is_empty():
		_section(tr("UI_CRATES2_CH_PENDING"))
		var parts := PackedStringArray()
		for e in pend.rewards:
			parts.append("%s ×%s" % [CrateUi.def_name(str(e.item)), NumberFormat.fmt(int(e.qty))])
		_label(Loc.tf("UI_CRATES2_CH_PENDING_TEXT", {"place": int(pend.place), "score": NumberFormat.fmt(int(pend.score)),
			"rewards": ", ".join(parts) if not parts.is_empty() else tr("UI_CRATES2_CH_NO_REWARD")}), false)
		var cb := Button.new()
		cb.text = tr("UI_CRATES2_CH_CLAIM")
		cb.theme_type_variation = &"AccentButton"
		var why := crates.challenge_claim_check()
		cb.disabled = not why.is_empty()
		if cb.disabled:
			cb.tooltip_text = CrateUi.why(why)
		cb.pressed.connect(claim)
		add_child(cb)

	# --- classifica
	var info := crates.challenge_info()
	_section(tr("UI_CRATES2_CH_BOARD"))
	_label(Loc.tf("UI_CRATES2_CH_TIME", {"t": NumberFormat.fmt_time(float(info.time_left_s))}))
	var board := crates.challenge_board()
	var top := 1
	for e in board:
		top = maxi(top, int(e.score))
	for k in board.size():
		var e: Dictionary = board[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var nm := Label.new()
		nm.custom_minimum_size = Vector2(190, 0)
		nm.clip_text = true
		nm.text = "%d. %s" % [k + 1, tr("UI_CRATES2_CH_YOU") if bool(e.player) else Loc.t(e.name)]
		if bool(e.player):
			nm.theme_type_variation = &"SectionLabel"
		row.add_child(nm)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0
		bar.max_value = top
		bar.value = int(e.score)
		bar.custom_minimum_size = Vector2(120, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var sc := Label.new()
		sc.text = NumberFormat.fmt(int(e.score))
		sc.custom_minimum_size = Vector2(70, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(sc)

	# --- punti e premi (sempre visibili)
	_section(tr("UI_CRATES2_CH_POINTS"))
	var pts := PackedStringArray()
	for rar in CrateSystem.RARITIES:
		pts.append("%s %d" % [CrateUi.rarity_symbol(rar), crates.challenge_points(rar)])
	_label(" · ".join(pts) + "\n" + tr("UI_CRATES2_CH_POINTS_NOTE"))
	_section(tr("UI_CRATES2_CH_PRIZES"))
	var rw: Dictionary = CrateUi.rules().collectors_challenge.rewards_by_place
	for place in ["1", "2", "3", "4"]:
		var items := PackedStringArray()
		for e in rw.get(place, []):
			items.append("%s ×%s" % [CrateUi.def_name(str(e.item)), NumberFormat.fmt(int(e.qty))])
		_label("%s. %s" % [place, ", ".join(items) if not items.is_empty() else tr("UI_CRATES2_CH_NO_REWARD")], false)
	_label(Loc.tf("UI_CRATES2_CH_STATS", {"w": int(info.wins), "b": int(info.best_place) if int(info.best_place) > 0 else 0, "t": int(info.tier)}))
	_label(tr("UI_CRATES2_CH_NO_STAKES"))


func claim() -> void:
	if crates.challenge_claim():
		_msg = tr("UI_CRATES2_CH_CLAIMED")
	rebuild(true)
