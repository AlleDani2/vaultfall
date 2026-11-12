extends GameScreen
## Lobby degli amici (COOP-2): crea una stanza (questo PC fa da host) o entra con IP:porta; istruzioni passo-passo
## per Hamachi, ZeroTier e LAN; soci e stato della connessione. Solo presentazione: chiama CoopNetService.

var _svc: CoopNetService
var _nick: LineEdit
var _gname: LineEdit
var _port_host: SpinBox
var _pw_host: LineEdit
var _ip: LineEdit
var _port_join: SpinBox
var _pw_join: LineEdit
var _status: Label
var _members: VBoxContainer
var _resume: VBoxContainer
var _ips: Label
var _leave: Button
var _diag_host: VBoxContainer
var _diag_join: VBoxContainer
var _scroll: ScrollContainer
var ip_ack_dialog: ConfirmationDialog       # conferma una tantum sull'indirizzo IP (docs/24 §7.1); null se non aperta


func open(_params: Dictionary) -> void:
	_svc = CoopNetService.instance()
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(ScreenKit.title_style(_label("UI_COOPNET_LOBBY_TITLE", &"TitleLabel")))
	v.add_child(_wrap("UI_COOPNET_LOBBY_INTRO"))
	# stato
	var st := HBoxContainer.new()
	v.add_child(st)
	_status = Label.new()
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(_status)
	_leave = Button.new()
	_leave.text = "UI_COOPNET_LOBBY_LEAVE_ROOM"
	_leave.pressed.connect(func() -> void: _svc.leave_room())
	st.add_child(_leave)
	var guild_btn := Button.new()
	guild_btn.text = "UI_COOPNET_LOBBY_GO_GUILD"
	guild_btn.pressed.connect(func() -> void: EventBus.screen_requested.emit("coop_guild", {}))
	st.add_child(guild_btn)
	# soprannome
	var nk := HBoxContainer.new()
	v.add_child(nk)
	nk.add_child(_label("UI_COOPNET_LOBBY_NICK"))
	_nick = LineEdit.new()
	_nick.max_length = 16
	_nick.placeholder_text = "UI_COOPNET_LOBBY_NICK_HINT"
	_nick.text = _svc.saved_nick()
	_nick.custom_minimum_size.x = 220
	nk.add_child(_nick)
	v.add_child(_wrap("UI_COOPNET_LOBBY_PRIVACY", &"MutedLabel"))
	# crea stanza
	var host_box := _card(v, "UI_COOPNET_LOBBY_HOST_TITLE")
	host_box.add_child(_wrap("UI_COOPNET_LOBBY_HOST_DESC", &"MutedLabel"))
	var hg := GridContainer.new()
	hg.columns = 2
	hg.add_theme_constant_override("h_separation", 12)
	hg.add_theme_constant_override("v_separation", 6)
	host_box.add_child(hg)
	hg.add_child(_label("UI_COOPNET_LOBBY_GUILD_NAME"))
	_gname = LineEdit.new()
	_gname.max_length = 24
	_gname.custom_minimum_size.x = 260
	_gname.placeholder_text = "UI_COOPNET_LOBBY_GUILD_NAME_HINT"
	hg.add_child(_gname)
	hg.add_child(_label("UI_COOPNET_LOBBY_PORT"))
	_port_host = _port_spin()
	hg.add_child(_port_host)
	hg.add_child(_label("UI_COOPNET_LOBBY_PASSWORD"))
	_pw_host = LineEdit.new()
	_pw_host.max_length = 32
	_pw_host.custom_minimum_size.x = 260
	_pw_host.secret = true
	_pw_host.placeholder_text = "UI_COOPNET_LOBBY_PASSWORD_HINT"
	hg.add_child(_pw_host)
	var hb := Button.new()
	hb.text = "UI_COOPNET_LOBBY_HOST_BTN"
	hb.theme_type_variation = &"AccentButton"
	hb.pressed.connect(_on_host)
	host_box.add_child(hb)
	_ips = Label.new()
	_ips.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_box.add_child(_ips)
	_resume = VBoxContainer.new()
	host_box.add_child(_resume)
	_diag_host = _diag_row(host_box, "host")
	# entra con IP
	var join_box := _card(v, "UI_COOPNET_LOBBY_JOIN_TITLE")
	join_box.add_child(_wrap("UI_COOPNET_LOBBY_JOIN_DESC", &"MutedLabel"))
	var jg := GridContainer.new()
	jg.columns = 2
	jg.add_theme_constant_override("h_separation", 12)
	jg.add_theme_constant_override("v_separation", 6)
	join_box.add_child(jg)
	jg.add_child(_label("UI_COOPNET_LOBBY_IP"))
	_ip = LineEdit.new()
	_ip.max_length = 64
	_ip.custom_minimum_size.x = 260
	_ip.placeholder_text = "UI_COOPNET_LOBBY_IP_HINT"
	_ip.text = str(_svc.last_host().get("ip", ""))
	jg.add_child(_ip)
	jg.add_child(_label("UI_COOPNET_LOBBY_PORT"))
	_port_join = _port_spin()
	if _svc.last_host().has("port"):
		_port_join.value = int(_svc.last_host().port)
	jg.add_child(_port_join)
	jg.add_child(_label("UI_COOPNET_LOBBY_PASSWORD"))
	_pw_join = LineEdit.new()
	_pw_join.max_length = 32
	_pw_join.custom_minimum_size.x = 260
	_pw_join.secret = true
	jg.add_child(_pw_join)
	var jb := Button.new()
	jb.text = "UI_COOPNET_LOBBY_JOIN_BTN"
	jb.theme_type_variation = &"AccentButton"
	jb.pressed.connect(_on_join)
	join_box.add_child(jb)
	_diag_join = _diag_row(join_box, "join")
	# soci
	var mem_box := _card(v, "UI_COOPNET_LOBBY_MEMBERS")
	_members = VBoxContainer.new()
	mem_box.add_child(_members)
	# istruzioni passo-passo
	var help := _card(v, "UI_COOPNET_HELP_TITLE")
	for k in ["UI_COOPNET_HELP_START", "UI_COOPNET_HELP_HAMACHI", "UI_COOPNET_HELP_ZEROTIER", "UI_COOPNET_HELP_LAN", "UI_COOPNET_HELP_FIREWALL",
			"UI_COOPNET_HELP_TROUBLE"]:
		help.add_child(_label(k + "_T", &"SectionLabel"))
		help.add_child(_wrap(k))
	_svc.status_changed.connect(_on_status)
	_svc.guild_changed.connect(refresh)
	_svc.notice.connect(_on_notice)
	_fill_ips()
	refresh()


func _on_status(_s: String) -> void:
	refresh()


func close() -> void:
	if _svc != null:
		if _svc.status_changed.is_connected(_on_status):
			_svc.status_changed.disconnect(_on_status)
		if _svc.notice.is_connected(_on_notice):
			_svc.notice.disconnect(_on_notice)
		if _svc.guild_changed.is_connected(refresh):
			_svc.guild_changed.disconnect(refresh)


func refresh() -> void:
	if _svc == null or _status == null:
		return
	var key := _svc.status_key()
	_status.text = Loc.tf(key, {"ms": _svc.rtt_ms}) if _svc.status == CoopNetService.ST_CONNECTED else tr(key)
	_leave.disabled = _svc.status == CoopNetService.ST_OFFLINE
	for c in _members.get_children():
		c.queue_free()
	var gs := _svc.guild_state()
	if gs.is_empty():
		_members.add_child(_wrap("UI_COOPNET_LOBBY_NO_GUILD", &"MutedLabel"))
	else:
		var online := {}
		for f in _svc.friends():
			if str(f.state) != "offline":
				online[str(f.uid)] = true
		for uid in gs.members:
			var m: Dictionary = gs.members[uid]
			if not bool(m.active):
				continue
			var l := Label.new()
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			var where := "UI_COOPNET_MEMBER_YOU" if str(uid) == _svc.my_uid() else \
				("UI_COOPNET_MEMBER_ONLINE" if online.has(str(uid)) else "UI_COOPNET_MEMBER_AWAY")
			l.text = Loc.tf("UI_COOPNET_MEMBER_ROW", {"name": str(m.name),
				"role": tr("UI_COOPNET_ROLE_" + str(m.role).to_upper()), "where": tr(where)})
			_members.add_child(l)
	for c in _resume.get_children():
		c.queue_free()
	if _svc.status == CoopNetService.ST_OFFLINE:
		for gid in _svc.store.list_ids():
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = Loc.tf("UI_COOPNET_LOBBY_RESUME", {"id": gid})
			b.pressed.connect(_on_host.bind(gid))
			_resume.add_child(b)


func _on_host(resume_id: String = "") -> void:
	if _ask_ip_ack(_do_host.bind(resume_id)):
		_do_host(resume_id)


func _do_host(resume_id: String = "") -> void:
	var err := _svc.host_room(int(_port_host.value), _nick.text, _gname.text, _pw_host.text, resume_id)
	if not err.is_empty():
		EventBus.notice.emit("warning", tr("UI_COOPNET_ERR_" + err.to_upper()), {})
	refresh()


func _on_join() -> void:
	if _ask_ip_ack(_do_join):
		_do_join()


func _do_join() -> void:
	var err := _svc.join_room(_ip.text, int(_port_join.value), _nick.text, _pw_join.text)
	if not err.is_empty():
		EventBus.notice.emit("warning", tr("UI_COOPNET_ERR_" + err.to_upper()), {})
	refresh()


## docs/24 §7.1: la PRIMA volta che si ospita o si entra serve una conferma esplicita sull'indirizzo IP, poi ricordata nelle
## Impostazioni («coop_ip_ack»). Ritorna true se si può procedere subito; altrimenti apre la finestra e chiama `on_ok` solo alla conferma.
func _ask_ip_ack(on_ok: Callable) -> bool:
	if bool(Settings.get_value("coop_ip_ack")):
		return true
	ip_ack_dialog = ConfirmationDialog.new()
	ip_ack_dialog.name = "IpAckDialog"
	DialogKit.style_confirm(ip_ack_dialog, 520)
	ip_ack_dialog.title = "UI_COOPNET_IPACK_TITLE"
	ip_ack_dialog.dialog_text = "UI_COOPNET_IPACK_TEXT"
	ip_ack_dialog.ok_button_text = "UI_COOPNET_IPACK_OK"
	ip_ack_dialog.confirmed.connect(func() -> void:
		Settings.set_value("coop_ip_ack", true)
		on_ok.call())
	ip_ack_dialog.canceled.connect(func() -> void: ip_ack_dialog = null)
	ip_ack_dialog.confirmed.connect(func() -> void: ip_ack_dialog = null)
	add_child(ip_ack_dialog)
	ip_ack_dialog.popup_centered()
	return false


func _on_notice(key: String, params: Dictionary) -> void:
	EventBus.notice.emit("info", Loc.tf(key, params), {})


## Indirizzi di questo PC da dare agli amici (IPv4, senza 127.x). 25.x = Hamachi, gli altri = LAN/ZeroTier/Tailscale.
func _fill_ips() -> void:
	var list := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var tag := tr("UI_COOPNET_IP_HAMACHI") if a.begins_with("25.") else tr("UI_COOPNET_IP_OTHER")
		list.append("%s  (%s)" % [a, tag])
	_ips.text = Loc.tf("UI_COOPNET_LOBBY_MY_IPS", {"list": ", ".join(list) if not list.is_empty() else tr("UI_COOPNET_IP_NONE")})


## Pulsante «Controlla connessione» + area dei risultati, sotto la scheda `mode` ("host" o "join").
func _diag_row(parent: Control, mode: String) -> VBoxContainer:
	var b := Button.new()
	b.text = "UI_COOPNET_DIAG_BTN"
	b.pressed.connect(_on_diag.bind(mode))
	parent.add_child(b)
	var out := VBoxContainer.new()
	parent.add_child(out)
	return out


## 1 = la porta si può aprire, 0 = occupata da un altro programma, -1 = non so (la stanza è già aperta da noi).
func _port_free(port: int) -> int:
	if _svc.status == CoopNetService.ST_HOSTING:
		return -1
	var u := UDPServer.new()
	var e := u.listen(port)
	if e != OK:
		return 0
	u.stop()
	return 1


func _on_diag(mode: String) -> void:
	var host_side := mode == "host"
	var port := int(_port_host.value if host_side else _port_join.value)
	var inp := {"mode": mode, "local_ips": IP.get_local_addresses(), "ip": "" if host_side else _ip.text, "port": port,
		"default_port": _svc.default_port(), "status": _svc.status, "problem": "" if host_side else _svc.last_problem,
		"port_free": _port_free(port) if host_side else -1, "rtt_ms": _svc.rtt_ms}
	var box := _diag_host if host_side else _diag_join
	for c in box.get_children():
		c.queue_free()
	for r in CoopDiagnose.analyze(inp):
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 300
		l.text = tr("UI_COOPNET_DIAG_MARK_" + str(r.level).to_upper()) + " " + Loc.tf(CoopDiagnose.text_key(r), r.params)
		if r.id == "verdict":
			l.theme_type_variation = &"SectionLabel"
		elif r.level == CoopDiagnose.INFO:
			l.theme_type_variation = &"MutedLabel"
		box.add_child(l)
	_reveal_diag(box)


## Il risultato di «Controlla connessione» sta sotto il pulsante, spesso oltre il bordo della finestra (soprattutto in «Entra con
## IP»): senza scorrere il clic sembrava non fare nulla (playtest novizio 121). Porta in vista l'ultima riga (il verdetto).
func _reveal_diag(box: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _scroll != null and is_instance_valid(_scroll) and box.get_child_count() > 0 and is_instance_valid(box):
		_scroll.ensure_control_visible(box.get_child(box.get_child_count() - 1))


func _port_spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = CoopDiagnose.PORT_MIN
	s.max_value = CoopDiagnose.PORT_MAX
	s.value = _svc.default_port()
	return s


func _card(parent: Control, title_key: String) -> VBoxContainer:
	var v := ScreenKit.card(parent, ScreenKit.accent("coop_lobby"), 4)
	v.add_child(_label(title_key, &"SectionLabel"))
	return v


func _label(key: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = key
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _wrap(key: String, variation: StringName = &"") -> Label:
	var l := _label(key, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l
