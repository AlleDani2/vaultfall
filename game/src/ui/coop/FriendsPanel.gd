class_name FriendsPanel
extends PanelContainer
## Riquadro «Amici» (COOP-2, livello A): sempre visibile in cima alla colonna destra, ripiegabile. Mostra i
## personaggini animati degli amici collegati alla stanza, con nome, livello, una riga di attività, indicatore di
## connessione e latenza. Clic sul personaggino = scheda dell'amico (con il codice-eroe di COOP-1 se arriva).
## Solo presentazione: legge CoopNetService e compone i testi con i dati e la lingua LOCALI.

const REFRESH_S := 0.5
const STATE_COLORS := {"online": Color(0.45, 0.85, 0.45), "stale": Color(0.95, 0.8, 0.3), "offline": Color(0.6, 0.6, 0.6)}

var _svc: CoopNetService
var _main: Node
var _collapsed := false
var _header: Button
var _status: Label
var _list: VBoxContainer
var _empty: VBoxContainer
var _timer := Timer.new()
var _card: AcceptDialog


## Aggancia il riquadro a MainScreen: dentro «AmiciSlot» del cassetto destro (sezione Amici, F3 del progetto di interfaccia;
## prima stava in cima alla colonna destra). Una riga in MainScreen._ready. Se lo slot manca ripiega sulla colonna.
static func attach(main: Node) -> FriendsPanel:
	var p := FriendsPanel.new()
	p._main = main
	var slot: Node = main.get_node_or_null("Root/Body/RightColumn/RightScroll/VBox/AmiciSlot")
	if slot == null:
		slot = main.find_child("AmiciSlot", true, false)
	if slot != null:
		slot.add_child(p)
		return p
	var col: Node = main.get_node_or_null("Root/Body/RightColumn/RightScroll/VBox")
	if col == null:
		main.add_child(p)
	else:
		col.add_child(p)
		col.move_child(p, 0)
	return p


func _ready() -> void:
	_svc = CoopNetService.instance()
	theme_type_variation = &"InsetPanel"
	var v := VBoxContainer.new()
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_header = Button.new()
	_header.flat = true
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.pressed.connect(_toggle)
	top.add_child(_header)
	_status = Label.new()
	_status.theme_type_variation = &"MutedLabel"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	top.add_child(_status)
	_list = VBoxContainer.new()
	v.add_child(_list)
	_empty = VBoxContainer.new()
	v.add_child(_empty)
	var hint := Label.new()
	hint.theme_type_variation = &"MutedLabel"
	hint.text = "UI_COOPNET_PANEL_EMPTY"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(hint)
	var open := Button.new()
	open.text = "UI_COOPNET_PANEL_OPEN_LOBBY"
	open.pressed.connect(func() -> void: EventBus.screen_requested.emit("coop_lobby", {}))
	_empty.add_child(open)
	_card = AcceptDialog.new()
	_card.title = "UI_COOPNET_CARD_TITLE"
	add_child(_card)
	_svc.friends_changed.connect(_rebuild)
	_svc.status_changed.connect(_on_status)
	EventBus.unlocked.connect(_on_unlocked)
	_timer.wait_time = REFRESH_S
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	_rebuild()


func _on_status(_s: String) -> void:
	_rebuild()


func _on_unlocked(_token: String) -> void:
	_rebuild()


func _exit_tree() -> void:
	if EventBus.unlocked.is_connected(_on_unlocked):
		EventBus.unlocked.disconnect(_on_unlocked)
	if _svc != null:
		if _svc.friends_changed.is_connected(_rebuild):
			_svc.friends_changed.disconnect(_rebuild)
		if _svc.status_changed.is_connected(_on_status):
			_svc.status_changed.disconnect(_on_status)


func _toggle() -> void:
	_collapsed = not _collapsed
	_rebuild()


func _tick() -> void:
	if _main != null and "current_id" in _main:
		_svc.current_screen = str(_main.current_id)      # Tenuta / Mercato nella presenza
	_rebuild()


## Il riquadro compare solo quando gli Amici sono sbloccati (feature:coop) o c'è già una stanza aperta: prima il suo «Apri la
## Lobby» portava a una schermata chiusa e il clic restava muto (playtest novizio 121).
func is_unlocked() -> bool:
	return (GameState.data.get("unlocks", []) as Array).has("feature:coop") or _svc.status != CoopNetService.ST_OFFLINE


func _rebuild() -> void:
	if not is_inside_tree():
		return
	visible = is_unlocked()
	if not visible:
		return
	var fl := _svc.friends()
	var online := 0
	for f in fl:
		if str(f.state) == "online":
			online += 1
	_header.text = Loc.tf("UI_COOPNET_PANEL_TITLE", {"n": online, "arrow": "▸" if _collapsed else "▾"})
	_status.text = _status_text()
	_status.add_theme_color_override("font_color", _status_color())
	_list.visible = not _collapsed
	_empty.visible = not _collapsed and fl.is_empty()
	for c in _list.get_children():
		c.queue_free()
	if _collapsed:
		return
	var max_n := int(_svc.rules["presence"]["max_friends_shown"]) if not _svc.rules.is_empty() else 0
	for i in mini(fl.size(), max_n):
		_list.add_child(_row(fl[i]))


func _status_text() -> String:
	match _svc.status:
		CoopNetService.ST_HOSTING: return tr("UI_COOPNET_ST_HOSTING")
		CoopNetService.ST_CONNECTED: return Loc.tf("UI_COOPNET_ST_CONNECTED", {"ms": _svc.rtt_ms})
		CoopNetService.ST_CONNECTING: return tr("UI_COOPNET_ST_CONNECTING")
		CoopNetService.ST_SUSPENDED: return tr(_svc.status_key())
	return tr("UI_COOPNET_ST_OFFLINE")


func _status_color() -> Color:
	match _svc.status:
		CoopNetService.ST_HOSTING, CoopNetService.ST_CONNECTED: return STATE_COLORS.online
		CoopNetService.ST_CONNECTING, CoopNetService.ST_SUSPENDED: return STATE_COLORS.stale
	return STATE_COLORS.offline


func _row(f: Dictionary) -> Control:
	var h := HBoxContainer.new()
	var spr := FriendSprite.new()
	spr.setup(str(f.cls), CoopPresence.anim_of(f), str(f.state) != "offline")
	spr.tooltip_text = "UI_COOPNET_CARD_HINT"
	spr.clicked.connect(_open_card.bind(f))
	h.add_child(spr)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var name_l := Label.new()
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.text = Loc.tf("UI_COOPNET_ROW_NAME", {"name": str(f.name), "lvl": int(f.lvl)})
	v.add_child(name_l)
	var act := Label.new()
	act.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	act.theme_type_variation = &"MutedLabel"
	act.text = activity_text(f)
	act.clip_text = true
	act.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	act.custom_minimum_size.x = 140
	v.add_child(act)
	var conn := Label.new()
	conn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	conn.theme_type_variation = &"MutedLabel"
	conn.add_theme_color_override("font_color", STATE_COLORS.get(str(f.state), STATE_COLORS.offline))
	conn.text = Loc.tf("UI_COOPNET_ROW_CONN_" + str(f.state).to_upper(), {"ms": int(f.ping)})
	v.add_child(conn)
	return h


## Riga di attività composta con i dati LOCALI (nomi di mansioni, azioni, zone e mostri nella lingua di chi guarda).
static func activity_text(f: Dictionary) -> String:
	var sk := str(f.get("sk", ""))
	var det := str(f.get("det", ""))
	match str(f.get("act", "")):
		"skill":
			return Loc.tf("UI_COOPNET_ACT_SKILL", {"skill": Loc.t(DataRegistry.get_def("skills", sk).get("name", sk)),
				"action": Loc.t(DataRegistry.action(det).get("name", det))})
		"combat", "dungeon":
			var zone: Variant = DataRegistry.get_def("zones", det).get("name", "")
			if zone is String and str(zone).is_empty():
				zone = DataRegistry.get_def("dungeons", det).get("name", det)
			var mon: Variant = DataRegistry.get_def("monsters", sk).get("name", "")
			var key := "UI_COOPNET_ACT_COMBAT" if not (mon is String and str(mon).is_empty()) else "UI_COOPNET_ACT_COMBAT_ZONE"
			return Loc.tf(key, {"zone": Loc.t(zone), "monster": Loc.t(mon)})
		"raid": return TranslationServer.translate("UI_COOPNET_ACT_RAID")
		"wboss": return TranslationServer.translate("UI_COOPNET_ACT_WBOSS")
		"rift": return TranslationServer.translate("UI_COOPNET_ACT_RIFT")
		"estate": return TranslationServer.translate("UI_COOPNET_ACT_ESTATE")
		"crate": return TranslationServer.translate("UI_COOPNET_ACT_CRATE")
		"market": return TranslationServer.translate("UI_COOPNET_ACT_MARKET")
		"rest", "idle": return TranslationServer.translate("UI_COOPNET_ACT_REST")
	return TranslationServer.translate("UI_COOPNET_ACT_MENU")


func _open_card(f: Dictionary) -> void:
	var cls_name: Variant = DataRegistry.get_def("classes", str(f.cls)).get("name", "")
	var lines := PackedStringArray([
		Loc.tf("UI_COOPNET_CARD_NAME", {"name": str(f.name)}),
		Loc.tf("UI_COOPNET_CARD_CLASS", {"cls": Loc.t(cls_name) if not (cls_name is String and str(cls_name).is_empty()) else tr("UI_COOPNET_CARD_NO_CLASS")}),
		Loc.tf("UI_COOPNET_CARD_LEVELS", {"lvl": int(f.lvl), "hl": int(f.hl)}),
		Loc.tf("UI_COOPNET_CARD_ACT", {"act": activity_text(f)}),
		Loc.tf("UI_COOPNET_CARD_PING", {"ms": int(f.ping)}),
	])
	var code := str(f.get("code", ""))
	if code.is_empty():
		lines.append(tr("UI_COOPNET_CARD_NO_CODE"))
	else:
		lines.append(Loc.tf("UI_COOPNET_CARD_CODE", {"code": code}))
		DisplayServer.clipboard_set(code)
		lines.append(tr("UI_COOPNET_CARD_CODE_COPIED"))
	_card.dialog_text = "\n".join(lines)
	_card.popup_centered()
