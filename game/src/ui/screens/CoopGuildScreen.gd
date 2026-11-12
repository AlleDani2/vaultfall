extends GameScreen
@warning_ignore_start("integer_division")
## Gilda di amici (COOP-2, livello B): fondo comune A SOLO VERSAMENTO, progetti con bonus uguali per tutti, Boss della
## settimana a danno cumulativo, registro. Solo presentazione: legge CoopNetService.guild_state() e chiama i suoi
## metodi pubblici (deposit, propose, vote, decide, boss_attack, kick, leave_guild). Nessun prelievo possibile.

var _svc: CoopNetService
var _root: VBoxContainer
var _dirty := true
var _last_gseq := -1
var _item: OptionButton
var _qty: SpinBox
var _confirm: ConfirmationDialog


func open(_params: Dictionary) -> void:
	_svc = CoopNetService.instance()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	scroll.add_child(_root)
	_confirm = ConfirmationDialog.new()
	DialogKit.style_confirm(_confirm)
	_confirm.dialog_text = "UI_COOPNET_LEAVE_PENDING"
	_confirm.confirmed.connect(func() -> void: _report(_svc.leave_guild(true)))
	add_child(_confirm)
	_svc.guild_changed.connect(_mark)
	_build()


func close() -> void:
	if _svc != null and _svc.guild_changed.is_connected(_mark):
		_svc.guild_changed.disconnect(_mark)


func _mark() -> void:
	_dirty = true


func refresh() -> void:
	var g := _svc.guild
	var gs := g.gseq() if g != null else -1
	if _dirty or gs != _last_gseq:
		_build()


func _build() -> void:
	_dirty = false
	for c in _root.get_children():
		c.queue_free()
	var g := _svc.guild
	_last_gseq = g.gseq() if g != null else -1
	_root.add_child(ScreenKit.title_style(_label("UI_COOPNET_GUILD_TITLE", &"TitleLabel")))
	if g == null or not g.is_member(_svc.my_uid()):
		ScreenKit.empty(_root, tr("UI_RS_CG_NONE"), tr("UI_COOPNET_GUILD_NONE"), [[tr("UI_COOPNET_PANEL_OPEN_LOBBY"), ScreenKit.target("coop_lobby")]])
		return
	var st: Dictionary = g.state
	var me := _svc.my_uid()
	var leader := g.role_of(me) == CoopGuild.ROLE_LEADER
	var ts := int(Time.get_unix_time_from_system())
	_root.add_child(_text(Loc.tf("UI_COOPNET_GUILD_HEADER", {"name": str(st.name), "n": g.n_active(),
		"trophies": int(st.trophies), "role": tr("UI_COOPNET_ROLE_" + g.role_of(me).to_upper())})))
	if not _svc.is_online():
		_root.add_child(_wrap("UI_COOPNET_GUILD_PAUSED", &"MutedLabel"))
	if _svc.pending_commands() > 0:
		_root.add_child(_text(Loc.tf("UI_COOPNET_GUILD_PENDING", {"n": _svc.pending_commands()}), &"MutedLabel"))
	# --- fondo comune
	var fund := _card("UI_COOPNET_FUND_TITLE")
	fund.add_child(_wrap("UI_COOPNET_FUND_DESC", &"MutedLabel"))
	fund.add_child(_text(Loc.tf("UI_COOPNET_FUND_POINTS", {"pts": NumberFormat.fmt(g.fund_points()),
		"spent": NumberFormat.fmt(int(st.fund.spent))})))
	fund.add_child(_text(Loc.tf("UI_COOPNET_FUND_ALLOW", {"pts": NumberFormat.fmt(g.allowance(me, ts)),
		"days": int(_svc.rules["deposit"]["drawer_days"])}), &"MutedLabel"))
	var dep := HBoxContainer.new()
	fund.add_child(dep)
	_item = OptionButton.new()
	_item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var bank: Object = Game.system("bank")
	_item.add_item(Loc.tf("UI_COOPNET_FUND_GOLD", {"n": NumberFormat.fmt(bank.gold() if bank != null else 0)}))
	_item.set_item_metadata(0, "gold")
	for id in _svc.rules["deposit"]["items"]:
		var have: int = bank.count(str(id)) if bank != null else 0
		if have <= 0:
			continue
		_item.add_item("%s (%s)" % [Loc.t(DataRegistry.item(str(id)).get("name", id)), NumberFormat.fmt(have)])
		_item.set_item_metadata(_item.item_count - 1, str(id))
	dep.add_child(_item)
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = int(_svc.rules["deposit"]["max_qty_per_cmd"])
	_qty.value = 100
	dep.add_child(_qty)
	var db := Button.new()
	db.text = "UI_COOPNET_FUND_DEPOSIT"
	db.theme_type_variation = &"AccentButton"
	db.pressed.connect(func() -> void: _report(_svc.deposit(str(_item.get_item_metadata(_item.selected)), int(_qty.value))))
	dep.add_child(db)
	# --- progetti
	var pj := _card("UI_COOPNET_PROJ_TITLE")
	pj.add_child(_wrap("UI_COOPNET_PROJ_DESC", &"MutedLabel"))
	var pr: Dictionary = st.proposal
	if not pr.is_empty():
		var t: Array = _tally(st)
		pj.add_child(_text(Loc.tf("UI_COOPNET_PROJ_PROPOSAL", {"name": Loc.t(g.project_def(str(pr.project)).name),
			"yes": t[0], "no": t[1], "need": int(g.n_active() / 2) + 1})))
		var vb := HBoxContainer.new()
		pj.add_child(vb)
		var y := Button.new()
		y.text = "UI_COOPNET_PROJ_VOTE_YES"
		y.pressed.connect(func() -> void: _report(_svc.vote(true)))
		vb.add_child(y)
		var n := Button.new()
		n.text = "UI_COOPNET_PROJ_VOTE_NO"
		n.pressed.connect(func() -> void: _report(_svc.vote(false)))
		vb.add_child(n)
		if leader:
			var d := Button.new()
			d.text = "UI_COOPNET_PROJ_DECIDE"
			d.tooltip_text = "UI_COOPNET_PROJ_DECIDE_HINT"
			d.pressed.connect(func() -> void: _report(_svc.decide()))
			vb.add_child(d)
	if not str(st.target).is_empty():
		var tid := str(st.target)
		pj.add_child(_text(Loc.tf("UI_COOPNET_PROJ_TARGET", {"name": Loc.t(g.project_def(tid).name),
			"pts": NumberFormat.fmt(g.project_cost(tid, g.project_level(tid) + 1))})))
	for p in _svc.rules["projects"]:
		var pid := str(p.id)
		var lv := g.project_level(pid)
		var row := HBoxContainer.new()
		pj.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var cur := float(p.value_by_level[lv])
		var nxt := float(p.value_by_level[mini(lv + 1, int(p.max_level))])
		info.add_child(_text(Loc.tf("UI_COOPNET_PROJ_ROW", {"name": Loc.t(p.name), "lv": lv, "max": int(p.max_level),
			"cur": NumberFormat.fmt_pct(cur), "next": NumberFormat.fmt_pct(nxt), "cap": int(p.cap_pct)})))
		info.add_child(_text(Loc.t(p.desc), &"MutedLabel"))
		if leader and pr.is_empty() and str(st.target).is_empty() and lv < int(p.max_level):
			var prop_btn := Button.new()
			prop_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			prop_btn.text = Loc.tf("UI_COOPNET_PROJ_PROPOSE", {"pts": NumberFormat.fmt(g.project_cost(pid, lv + 1))})
			prop_btn.pressed.connect(func() -> void: _report(_svc.propose(pid)))
			row.add_child(prop_btn)
	pj.add_child(_text(Loc.tf("UI_COOPNET_PROJ_BONUS", {"cap": int(_svc.rules["bonus_cap_pct"])}), &"MutedLabel"))
	# --- Boss della settimana
	var bs := _card("UI_COOPNET_BOSS_TITLE")
	var b: Dictionary = st.boss
	if not b.is_empty():
		var bdef := {}
		for d in _svc.rules["boss"]["bosses"]:
			if str(d.id) == str(b.id):
				bdef = d
		bs.add_child(_text(Loc.t(bdef.get("name", b.id)), &"SectionLabel"))
		bs.add_child(_text(Loc.t(bdef.get("desc", "")), &"MutedLabel"))
		var bar := ProgressBar.new()
		bar.max_value = maxi(1, int(b.hp))
		bar.value = int(b.dmg)
		bar.custom_minimum_size = Vector2(240, 16)
		bar.show_percentage = false
		bs.add_child(bar)
		bs.add_child(_text(Loc.tf("UI_COOPNET_BOSS_HP", {"dmg": NumberFormat.fmt(int(b.dmg)), "hp": NumberFormat.fmt(int(b.hp))})))
		bs.add_child(_text(Loc.tf("UI_COOPNET_BOSS_MINE", {"mine": NumberFormat.fmt(int(b.by_member.get(me, 0))),
			"cap": NumberFormat.fmt(int(b.cap)), "att": g.boss_attempts(me, ts)}), &"MutedLabel"))
		if bool(b.done):
			bs.add_child(_wrap("UI_COOPNET_BOSS_DONE"))
		else:
			var ab := Button.new()
			ab.text = "UI_COOPNET_BOSS_ATTACK"
			ab.theme_type_variation = &"AccentButton"
			ab.pressed.connect(_attack)
			bs.add_child(ab)
		bs.add_child(_wrap("UI_COOPNET_BOSS_DESC", &"MutedLabel"))
	# --- soci (espulsione solo per il Capo; i contributi restano)
	var mb := _card("UI_COOPNET_LOBBY_MEMBERS")
	for uid in st.members:
		var m: Dictionary = st.members[uid]
		if not bool(m.active):
			continue
		var r := HBoxContainer.new()
		mb.add_child(r)
		var l := _text(Loc.tf("UI_COOPNET_MEMBER_DEP", {"name": str(m.name), "role": tr("UI_COOPNET_ROLE_" + str(m.role).to_upper()),
			"pts": NumberFormat.fmt(int(m.dep_total))}))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		if leader and str(uid) != me:
			var k := Button.new()
			k.text = "UI_COOPNET_MEMBER_KICK"
			k.tooltip_text = "UI_COOPNET_MEMBER_KICK_HINT"
			k.pressed.connect(func() -> void: _report(_svc.kick(str(uid))))
			r.add_child(k)
	var lv_btn := Button.new()
	lv_btn.text = "UI_COOPNET_GUILD_LEAVE"
	lv_btn.pressed.connect(_leave)
	mb.add_child(lv_btn)
	# --- registro
	var lg := _card("UI_COOPNET_LOG_TITLE")
	var entries: Array = st.log
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 21), -1):
		lg.add_child(_text(log_line(entries[i], st, _svc.rules), &"MutedLabel"))


func _attack() -> void:
	var res := _svc.boss_attack()
	if not str(res.err).is_empty():
		_report(str(res.err))
	else:
		EventBus.notice.emit("info", Loc.tf("UI_COOPNET_BOSS_RESULT", {"pts": int(res.pts)}), {})
	_dirty = true


func _leave() -> void:
	var e := _svc.leave_guild()
	if e == "pending":
		_confirm.popup_centered()
	else:
		_report(e)


func _report(err: String) -> void:
	if not err.is_empty():
		EventBus.notice.emit("warning", tr("UI_COOPNET_ERR_" + err.to_upper()), {})
	_dirty = true


func _tally(st: Dictionary) -> Array:
	var yes := 0
	var no := 0
	for u in st.proposal.get("votes", {}):
		if st.members.has(u) and bool(st.members[u].active):
			if bool(st.proposal.votes[u]):
				yes += 1
			else:
				no += 1
	return [yes, no]


## Riga del registro tradotta localmente: [gseq, ts, tipo, uid, a, b].
static func log_line(e: Array, st: Dictionary, rules: Dictionary) -> String:
	var who := str(st.members.get(str(e[3]), {}).get("name", ""))
	var a := str(e[4])
	var b := str(e[5])
	var kind := str(e[2])
	var params := {"who": who, "a": a, "b": b}
	match kind:
		"deposit":
			params["a"] = Loc.t(DataRegistry.item(a).get("name", a)) if a != "gold" else str(TranslationServer.translate("UI_COOPNET_GOLD"))
		"propose", "approved", "rejected", "level":
			for p in rules["projects"]:
				if str(p.id) == a:
					params["a"] = Loc.t(p.name)
		"boss_new", "boss_down":
			for d in rules["boss"]["bosses"]:
				if str(d.id) == a:
					params["a"] = Loc.t(d.name)
		"kick":
			params["a"] = str(st.members.get(a, {}).get("name", ""))
		"vote":
			params["b"] = str(TranslationServer.translate("UI_COOPNET_PROJ_VOTE_YES" if b == "1" else "UI_COOPNET_PROJ_VOTE_NO"))
	return Loc.tf("UI_COOPNET_LOG_" + kind.to_upper(), params)


func _card(title_key: String) -> VBoxContainer:
	var v := ScreenKit.card(_root, ScreenKit.accent("coop_guild"), 4)
	v.add_child(_label(title_key, &"SectionLabel"))
	return v


func _label(key: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = key
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _text(s: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _wrap(key: String, variation: StringName = &"") -> Label:
	var l := _label(key, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l
