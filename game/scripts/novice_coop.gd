extends "res://scripts/novice_base.gd"
## Playtest COOP del novizio (resoconto 121): DUE processi, ciascuno con la UI vera (xvfb), si parlano in rete (ENet, localhost).
## L'host crea la stanza dalla Lobby, il client entra con IP:porta; si scambiano il codice-eroe (VFH1), la prova settimanale
## (VFR1), fanno versamenti e votano nella Gilda di amici, con latenza e perdita simulate. I due processi si sincronizzano con
## piccoli file in <condivisa>.
##   xvfb-run -a <godot> --path game --rendering-driver opengl3 --resolution 1280x720 -s res://scripts/novice_coop.gd -- \
##       host|client <cartella-uscita> <cartella-condivisa> [it|en] [porta] [latenza_ms] [perdita_%]

var role := "host"
var port := 24731
var lat := 0.0
var loss := 0.0
var svc: Object
var my_nick := "Alba"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	out = a[1]
	shared = a[2]
	if a.size() > 3:
		loc = a[3]
	if a.size() > 4:
		port = int(a[4])
	if a.size() > 5:
		lat = float(a[5])
	if a.size() > 6:
		loss = float(a[6])
	my_nick = "Alba" if role == "host" else "Bruno"
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.make_dir_recursive_absolute(shared)
	root.get_node("SaveService").set("save_dir", "user://coop_%s_saves" % role)
	root.get_node("SaveService").set("autosave_enabled", false)
	root.get_node("Settings").call("set_value", "locale", loc)
	root.get_node("Settings").call("set_value", "tutorials", false)
	root.get_node("Settings").call("set_value", "reduce_motion", false)
	_run.call_deferred()


func _run() -> void:
	say("[%s] avvio, lingua=%s" % [role, loc])
	if not await start_new_game_ui():
		save_diary()
		quit(1)
		return
	# il novizio ha già giocato fino alla prima Incursione e alla Breccia: gli sblocchi sono dati dal setup (non dalla UI)
	var un := uns()
	for t in ["feature:coop", "feature:rift", "feature:combat", "skill:hero", "chapter:1", "feature:market"]:
		if not un.has(t):
			un.append(t)
	_main.call("build_menu")
	system("quests").call("mark_intro_seen")
	# chiude la finestra di benvenuto, come farebbe lui
	var wb := overlay_btn()
	if wb != null:
		await click(wb, "benvenuto")
	await frames(10)
	svc = root.get_node("CoopNet") if root.has_node("CoopNet") else null
	say("servizio rete: " + str(svc))
	await shot("partita_pronta")
	await start_action_ui()
	await lobby_step()
	await codes_step()
	await guild_step()
	await net_quality_step()
	await sync_wait_done()
	save_diary()
	say("FINE [%s]: problemi=%d" % [role, _problems.size()])
	quit(0)


func panel_text() -> String:
	var fp := _main.find_child("*", true, false)
	return ""


func friends_panel() -> Node:
	for n in _main.find_children("*", "PanelContainer", true, false):
		if n.get_script() != null and n.get_script().get_global_name() == &"FriendsPanel":
			return n
	return null


# ------------------------------------------------------------------ Lobby

func lobby_step() -> void:
	if not await open_menu("coop_lobby"):
		return
	var host := _main.find_child("Host", true, false)
	await shot("lobby_" + role)
	check_texts(host, "Lobby")
	# testi d'aiuto: Hamachi, ZeroTier, LAN, firewall
	var all := "\n".join(visible_texts(host))
	for must in ["Hamachi", "ZeroTier", "firewall" if loc == "en" else "Firewall"]:
		if not all.to_lower().contains(must.to_lower()):
			problem("Lobby: nei testi d'aiuto manca «%s»" % must)
	# scorre in fondo per vedere le istruzioni
	var sc := _main.find_child("ScreenScroll", true, false) as ScrollContainer
	var inner: ScrollContainer = null
	for s in host.find_children("*", "ScrollContainer", true, false):
		inner = s
		break
	if inner != null:
		inner.scroll_vertical = 100000
		await frames(6)
		await shot("lobby_aiuto_" + role)
		inner.scroll_vertical = 0
	# soprannome digitato
	var nick: LineEdit = null
	for le in host.find_children("*", "LineEdit", true, false):
		if le.placeholder_text == "UI_COOPNET_LOBBY_NICK_HINT" or le.get("placeholder_text") == tr_en("UI_COOPNET_LOBBY_NICK_HINT"):
			nick = le
			break
	if nick != null:
		await type_text(nick, my_nick)
		say("[%s] soprannome digitato: «%s»" % [role, nick.text])
		if nick.text != my_nick:
			problem("la digitazione nel campo del soprannome ha dato «%s»" % nick.text)
	else:
		problem("campo soprannome non trovato")
	var diag := buttons(host, func(b): return shown(b) == tr_en("UI_COOPNET_DIAG_BTN"))
	if role == "host":
		await click(diag[0], "Controlla connessione (host)")
		await frames(6)
		await shot("diagnosi_host")
		say("[host] diagnosi: " + " | ".join(diag_lines(host)))
		var hspin: SpinBox = host.find_children("*", "SpinBox", true, false)[0]
		hspin.value = port                  # la porta della stanza (di solito si lascia quella proposta: qui una libera per la prova)
		var hb := buttons(host, func(b): return shown(b) == tr_en("UI_COOPNET_LOBBY_HOST_BTN"))
		await click(hb[0], "Crea stanza")
		await frames(20)
		await shot("stanza_creata_host")
		say("[host] stato: " + status_text(host))
		sync_set("host_ready", str(port))
	else:
		# prima che l'host ci sia: «Controlla connessione» con IP vuoto, poi con IP giusto ma stanza assente
		await click(diag[diag.size() - 1], "Controlla connessione (entra)")
		await frames(6)
		await shot("diagnosi_client_senza_ip")
		say("[client] diagnosi senza IP: " + " | ".join(diag_lines(host)))
		var ip_edit: LineEdit = null
		for le in host.find_children("*", "LineEdit", true, false):
			if le.placeholder_text == tr_en("UI_COOPNET_LOBBY_IP_HINT") or le.placeholder_text == "UI_COOPNET_LOBBY_IP_HINT":
				ip_edit = le
		if ip_edit == null:
			problem("campo IP non trovato")
			return
		await type_text(ip_edit, "127.0.0.1")
		await click(diag[diag.size() - 1], "Controlla connessione (con IP)")
		await frames(6)
		await shot("diagnosi_client_con_ip")
		say("[client] diagnosi con IP: " + " | ".join(diag_lines(host)))
		await sync_wait("host_ready")
		var spin: SpinBox = null
		for sp in host.find_children("*", "SpinBox", true, false):
			spin = sp                      # l'ultimo SpinBox è la porta di «Entra con IP»
		spin.value = port
		var jb := buttons(host, func(b): return shown(b) == tr_en("UI_COOPNET_LOBBY_JOIN_BTN"))
		await click(jb[0], "Entra")
		for i in 60:
			await frames(10)
			if svc != null and str(svc.get("status")) == "connected":
				break
		await shot("client_connesso")
		say("[client] stato: %s, rtt=%s" % [str(svc.get("status")), str(svc.get("rtt_ms"))])
		sync_set("client_in")
	if role == "host":
		await sync_wait("client_in")
		for i in 40:
			await frames(10)
			if svc.call("friends").size() > 0:
				break
	await frames(30)
	var fp := friends_panel()
	say("[%s] amici visibili: %d" % [role, svc.call("friends").size()])
	await shot("amici_" + role)
	if fp != null:
		check_texts(fp, "Riquadro Amici")
		say("   riquadro: " + " | ".join(visible_texts(fp)))


func diag_lines(host: Node) -> Array:
	var res := []
	for t in visible_texts(host):
		if t.begins_with("✔") or t.begins_with("✖") or t.begins_with("!") or t.begins_with("•") or t.begins_with("i ") or t.begins_with("✓") or t.begins_with("✗"):
			res.append(t.left(160))
	return res


func status_text(host: Node) -> String:
	for l in host.find_children("*", "Label", true, false):
		var t: String = l.text
		if t.contains("Stanza") or t.contains("room") or t.contains("Room") or t.contains("collegat") or t.contains("connected"):
			return t
	return ""


# ------------------------------------------------------------------ codici

func codes_step() -> void:
	if not await open_menu("coop"):
		return
	var host := _main.find_child("Host", true, false)
	check_texts(host, "Compagni d'armi")
	await shot("compagni_" + role)
	var cp := buttons(host, func(b): return shown(b) == tr_en("UI_COOP_BTN_COPY_MINE"))
	await click(cp[0], "Copia il mio codice")
	var code := DisplayServer.clipboard_get()
	say("[%s] codice-eroe copiato: %s… (%d caratteri)" % [role, code.left(8), code.length()])
	if not code.begins_with("VFH1."):
		problem("il codice non comincia con VFH1: «%s»" % code.left(12))
	await shot("codice_copiato_" + role)
	sync_set("code_" + role, code)
	var other := "client" if role == "host" else "host"
	var oc := await sync_wait("code_" + other)
	DisplayServer.clipboard_set(oc)
	var pb := buttons(host, func(b): return shown(b) == tr_en("UI_COOP_BTN_PASTE"))
	await click(pb[0], "Incolla")
	var ib := buttons(host, func(b): return shown(b) == tr_en("UI_COOP_BTN_IMPORT"))
	await click(ib[0], "Importa")
	await frames(12)
	var scr: Object = _main.call("current_screen")
	var fb: String = (scr.get("_feedback") as Label).text
	say("[%s] dopo l'importazione: %s" % [role, fb])
	var fbl: Label = scr.get("_feedback")
	var vis := root.get_visible_rect()
	if not vis.encloses(fbl.get_global_rect().grow(-1.0)):
		problem("dopo «Importa» l'esito «%s» non è in vista (%s)" % [fb.left(40), str(fbl.get_global_rect())])
	await shot("compagno_importato_" + role)
	var other_nick := "Bruno" if role == "host" else "Alba"
	var comps: Array = scr.get("_co").call("companions")
	var names := PackedStringArray(comps.map(func(c): return str(c.sheet.name)))
	say("[%s] compagni d'armi: %s" % [role, ", ".join(names)])
	if not names.has(other_nick):
		problem("dopo «Importa» il compagno «%s» non c'è: %s" % [other_nick, ", ".join(names)])
	# codice rovinato: un errore chiaro
	var pe: TextEdit = null
	for te in host.find_children("*", "TextEdit", true, false):
		if te.editable:
			pe = te
	if pe != null:
		pe.text = "VFH1.questoNonEUnCodiceVero"
		await click(ib[0], "Importa (codice rovinato)")
		await frames(6)
		var errs := visible_texts(host)
		say("[%s] codice rovinato -> %s" % [role, " | ".join(PackedStringArray(Array(errs).filter(func(t): return t.contains("codice") or t.contains("code"))).slice(0, 4))])
		await shot("codice_rovinato_" + role)
	# prova della settimana
	var run := buttons(host, func(b): return shown(b) == tr_en("UI_COOP_BTN_WEEK_RUN"))
	if run.is_empty():
		problem("«Affronta la prova» non disponibile (o disattivato) con Breccia sbloccata")
	else:
		await click(run[0], "Affronta la prova")
		await frames(10)
		await shot("prova_" + role)
		var cr := buttons(host, func(b): return shown(b) == tr_en("UI_COOP_BTN_COPY_RESULT"))
		if cr.is_empty():
			problem("dopo la prova manca «Copia il mio risultato»")
		else:
			await click(cr[0], "Copia il mio risultato")
			var rc := DisplayServer.clipboard_get()
			say("[%s] codice-risultato: %s… (%d)" % [role, rc.left(8), rc.length()])
			if not rc.begins_with("VFR1."):
				problem("il codice-risultato non comincia con VFR1: «%s»" % rc.left(12))
			sync_set("res_" + role, rc)
			var orc := await sync_wait("res_" + other)
			DisplayServer.clipboard_set(orc)
			await click(pb[0], "Incolla")
			await click(ib[0], "Importa")
			await frames(10)
			await shot("classifica_" + role)
			say("[%s] classifica: %s" % [role, " | ".join(PackedStringArray(Array(visible_texts(host)).filter(func(t): return t.begins_with("#") or t.contains(" 1.") or t.contains("1°"))).slice(0, 4))])


# ------------------------------------------------------------------ Gilda di amici

func guild_step() -> void:
	if not await open_menu("coop_guild"):
		return
	var host := _main.find_child("Host", true, false)
	await frames(10)
	check_texts(host, "Gilda di amici")
	await shot("gilda_" + role)
	var all := "\n".join(visible_texts(host)).to_lower()
	for bad in ["scambi", "regal", "trade", "gift", "puntat", "scommess", "bet", "wager", "ritira", "withdraw"]:
		# i testi d'etica dicono «non si può scambiare/regalare»: si segnala solo se c'è un PULSANTE col verbo
		pass
	for b in buttons(host):
		var t := shown(b).to_lower()
		for bad in ["scambia", "regala", "trade", "gift", "punta", "scommetti", "bet", "preleva", "withdraw", "ritira"]:
			if t.contains(bad):
				problem("Gilda: pulsante sospetto «%s»" % shown(b))
	var dep := buttons(host, func(b): return shown(b) == tr_en("UI_COOPNET_FUND_DEPOSIT"))
	if dep.is_empty():
		problem("Gilda: nessun pulsante «Versa» (stato: %s)" % str(svc.get("status")))
		return
	system("bank").call("add_gold", 5000)
	_main.call("show_screen", "coop_guild")
	await frames(10)
	dep = buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_COOPNET_FUND_DEPOSIT"))
	await click(dep[0], "Versa")
	await frames(40)
	await shot("gilda_versamento_" + role)
	say("[%s] dopo il versamento: %s" % [role, " | ".join(PackedStringArray(Array(visible_texts(_main.find_child("Host", true, false))).filter(func(t): return t.contains("punti") or t.contains("points") or t.contains("Fondo") or t.contains("Fund"))).slice(0, 5))])
	if role == "host":
		await sync_wait("client_deposited")
		await frames(30)
		# il Capo propone un progetto
		var prop := buttons(_main.find_child("Host", true, false), func(b): return shown(b).begins_with(tr_en("UI_COOPNET_PROJ_PROPOSE").split("{")[0].strip_edges()))
		say("[host] pulsanti «Proponi»: %d" % prop.size())
		if prop.size() > 0:
			await click(prop[0], "Proponi")
			await frames(40)
			await shot("gilda_proposta_host")
		sync_set("host_proposed")
		await sync_wait("client_voted")
		await frames(30)
		var dec := buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_COOPNET_PROJ_DECIDE"))
		if dec.size() > 0:
			await click(dec[0], "Decidi")
		await frames(40)
		await shot("gilda_progetto_host")
		# boss
		var at := buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_COOPNET_BOSS_ATTACK"))
		if at.size() > 0:
			await click(at[0], "Attacca il boss")
			await frames(60)
			await shot("gilda_boss_host")
		sync_set("host_boss")
	else:
		sync_set("client_deposited")
		await sync_wait("host_proposed")
		await frames(40)
		_main.call("show_screen", "coop_guild")
		await frames(10)
		var yes := buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_COOPNET_PROJ_VOTE_YES"))
		say("[client] pulsanti «Sì»: %d" % yes.size())
		if yes.size() > 0:
			await shot("gilda_voto_client")
			await click(yes[0], "Voto Sì")
			await frames(40)
		sync_set("client_voted")
		await sync_wait("host_boss")
		await frames(30)
		_main.call("show_screen", "coop_guild")
		await frames(10)
		var at2 := buttons(_main.find_child("Host", true, false), func(b): return shown(b) == tr_en("UI_COOPNET_BOSS_ATTACK"))
		if at2.size() > 0:
			await click(at2[0], "Attacca il boss")
			await frames(60)
		await shot("gilda_finale_client")
	# registro e coerenza dello stato
	var h: String = svc.get("guild").call("state_hash") if svc.get("guild") != null else ""
	say("[%s] hash gilda: %s" % [role, h])
	sync_set("hash_" + role, h)
	var oh := await sync_wait("hash_" + ("client" if role == "host" else "host"))
	if oh != h:
		say("[%s] hash diversi (può essere un'operazione in volo): %s vs %s" % [role, h, oh])


# ------------------------------------------------------------------ rete cattiva

func net_quality_step() -> void:
	if svc == null:
		return
	svc.set("sim_latency_ms", 250.0)
	svc.set("sim_jitter_ms", 80.0)
	svc.set("sim_loss_pct", 12.0)
	var tr_obj: Object = svc.get("transport")
	if tr_obj != null:
		tr_obj.set("sim_latency_ms", 250.0)
		tr_obj.set("sim_jitter_ms", 80.0)
		tr_obj.set("sim_loss_pct", 12.0)
	say("[%s] rete cattiva: 250±80 ms, 12%% di perdita" % role)
	await frames(20)
	for i in 3:
		await frames(60)
		system("bank").call("add_gold", 1000)
		var e := str(svc.call("deposit", "gold", 200))
		say("[%s] versamento %d con rete cattiva: %s" % [role, i, "ok" if e.is_empty() else e])
	for i in 60:
		await frames(10)
		if int(svc.call("pending_commands")) == 0:
			break
	say("[%s] comandi ancora in attesa: %d, rtt=%s" % [role, int(svc.call("pending_commands")), str(svc.get("rtt_ms"))])
	_main.call("show_screen", "coop_guild")
	await frames(20)
	await shot("rete_cattiva_" + role)
	var fp := friends_panel()
	if fp != null:
		say("   riquadro Amici: " + " | ".join(visible_texts(fp)))
	await frames(120)
	var h: String = svc.get("guild").call("state_hash") if svc.get("guild") != null else ""
	sync_set("nhash_" + role, h)
	var oh := await sync_wait("nhash_" + ("client" if role == "host" else "host"))
	if oh != h:
		problem("hash della gilda diversi dopo la rete cattiva: %s vs %s" % [h, oh])
	else:
		say("[%s] stato della gilda identico sui due PC dopo la rete cattiva (%s)" % [role, h])


func sync_wait_done() -> void:
	sync_set("done_" + role)
	await sync_wait("done_" + ("client" if role == "host" else "host"), 60.0)


## Il giocatore fa partire il Pino dalla UI (così gli amici lo vedono tagliare nel riquadro «Amici»).
func start_action_ui() -> void:
	if not await open_menu("skill:woodcutting"):
		return
	var btn := TutorialTargets.find(self, "action:wc_pine") as Button
	if btn == null:
		problem("Pino: pulsante Avvia non trovato")
		return
	await click(btn, "Avvia Pino")
	await frames(10)
	say("[%s] attività avviata: %s" % [role, str(system("skills").call("current_action"))])
