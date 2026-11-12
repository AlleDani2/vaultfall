extends SceneTree
## QA119 (playtest ARTIGIANO): carica un checkpoint di partita, apre la UI vera e, per ogni schermata sbloccata, scatta
## una cattura e fa una scansione automatica (chiavi nude, segnaposto non sostituiti, righe ripetute, elementi fuori
## dalla finestra, pulsanti senza testo). Stampa le righe «Q119 ...». Uso (display virtuale 1280x720):
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 -s res://scripts/capture_qa119.gd -- <cartella_checkpoint> <out> [it|en] [id_schermate_separati_da_virgola|all] [azione...]
## Non tocca i salvataggi veri (cartella temporanea in user://). Azioni facoltative dopo le schermate:
##   skillcats  per ogni mansione sbloccata e per ogni categoria del filtro, una cattura

const MAIN := "res://src/ui/main/MainScreen.tscn"
var _out := "user://q119"
var _n := 0
var _issues: Array = []
var _popup_n := 0
var _bare := RegEx.new()
var _ph := RegEx.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[1] if args.size() > 1 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	var save_dir := "user://q119_saves"
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir + "/" + f)
	for f in DirAccess.get_files_at(args[0]):
		DirAccess.copy_absolute(args[0] + "/" + f, save_dir + "/" + f)
	root.get_node("SaveService").set("save_dir", save_dir)
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 2:
		root.get_node("Settings").call("set_value", "locale", args[2])
	_bare.compile("^[A-Z][A-Z0-9]+(_[A-Z0-9]+)+$")
	_ph.compile("(\\{[a-z_]+\\}|%[sd]|\\bnull\\b|\\bNaN\\b|\\binf\\b)")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(5)
	_n += 1
	var path := "%s/%02d_%s.png" % [_out, _n, name.replace(":", "_")]
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var code := OS.execute("import", ["-window", "root", abs_path])
	if code != 0:
		root.get_texture().get_image().save_png(abs_path)


func _txt(c: Node) -> String:
	if c is Label:
		return TranslationServer.translate((c as Label).text)
	if c is Button:
		return TranslationServer.translate((c as Button).text)
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	return ""


func _in_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			return true
		p = p.get_parent()
	return false


func _scan(where: String, node: Node, seen: Dictionary) -> void:
	var vis := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	var prev := ""
	for c in node.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var t := _txt(c).strip_edges()
			if t != "":
				var shown := t
				if _bare.search(shown) != null and not seen.has("b" + shown):
					seen["b" + shown] = true
					_issues.append("%s | CHIAVE NUDA «%s» (%s)" % [where, shown, c.get_path()])
				var m := _ph.search(shown)
				if m != null and not seen.has("p" + shown):
					seen["p" + shown] = true
					_issues.append("%s | SEGNAPOSTO «%s» in «%s»" % [where, m.get_string(), shown.left(80)])
				if t == prev and (c is Label) and t.length() > 3:
					_issues.append("%s | RIGA RIPETUTA «%s»" % [where, t.left(70)])
				prev = t
			else:
				prev = ""
			var r := (c as Control).get_global_rect()
			if r.size.x > 4 and r.size.y > 4 and not _in_scroll(c) and (r.end.x > vis.end.x + 2 or r.end.y > vis.end.y + 2):
				if not seen.has("o" + str(c.get_path())):
					seen["o" + str(c.get_path())] = true
					_issues.append("%s | FUORI FINESTRA %s rect=%s" % [where, c.get_path(), r])
		_scan(where, c, seen)


func _report(where: String) -> void:
	var seen := {}
	var before := _issues.size()
	_scan(where, root, seen)
	for i in range(before, _issues.size()):
		print("Q119 ", _issues[i])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var game: Node = root.get_node("Game")
	var res: Dictionary = game.call("load_game", 1)
	if not bool(res.get("ok", false)):
		print("Q119 load fallito ", res)
		quit(2)
		return
	var main: Control = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(4)
	for k in 30:
		for nm in ["WbCollect", "TutorialOk", "WelcomeGo", "TutorialSkipAll"]:
			var b := main.find_child(nm, true, false) as Button
			if b != null and b.is_visible_in_tree():
				b.pressed.emit()
		await _frames(1)
	if args.has("fullbank"):
		var bank0: Object = game.call("system", "bank")
		var ids0: Array = root.get_node("DataRegistry").call("all_items").keys()
		ids0.sort()
		for iid in ids0:
			if bank0.call("free_slots") <= 0:
				break
			var itd: Dictionary = root.get_node("DataRegistry").call("item", str(iid))
			if str(itd.get("category", "")) in ["material", "food", "seed"]:
				bank0.call("add", str(iid), 1, "qa119")
		print("Q119 Deposito riempito: liberi=", bank0.call("free_slots"), " usati=", bank0.call("used_slots"))
		var sk0: Object = game.call("system", "skills")
		sk0.call("start", "wc_pine")
		for i in 600:
			game.call("_on_step", 0.1)
		print("Q119 dopo 60 s di mansione a Deposito pieno: overflow=", bank0.call("overflow_count"), " liberi=", bank0.call("free_slots"))
	var want: PackedStringArray = []
	if args.size() > 3 and args[3] != "all":
		want = args[3].split(",")
	var unl: Array = root.get_node("GameState").data.get("unlocks", [])
	var ids: Array = []
	for e in ScreenRegistry.entries():
		if ScreenRegistry.is_available(e, unl):
			if want.is_empty() or want.has(str(e.id)):
				ids.append(str(e.id))
	print("Q119 schermate: ", ids)
	for id in ids:
		if id.begins_with("coop") or id == "settings" or id == "news":
			continue
		var ok: bool = main.show_screen(id)
		await _frames(3)
		game.call("_on_step", 0.1)
		main.call("_on_ui_tick")
		await _shot(id)
		_report(id)
		if args.has("scrolls"):
			var sc := _best_scroll(main.get("_current"))
			if sc == null:
				sc = main.find_child("ScreenScroll", true, false) as ScrollContainer
			if sc != null:
				var vmax := int(sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page)
				var pos := 0
				var k := 0
				while pos < vmax and k < 3:
					pos += int(sc.size.y) - 60
					k += 1
					sc.scroll_vertical = pos
					await _frames(2)
					await _shot("%s_s%d" % [id, k])
					_report("%s@%d" % [id, pos])
				sc.scroll_vertical = 0
	if args.has("skillcats"):
		for id in ids:
			if not id.begins_with("skill:") or id == "skill:farming":
				continue
			main.show_screen(id)
			await _frames(3)
			var scr: Node = main.get("_current")
			var f: OptionButton = scr.get("_filter") if scr != null else null
			if f == null:
				continue
			for i in f.item_count:
				f.select(i)
				f.item_selected.emit(i)
				await _frames(3)
				await _shot("%s_cat%d" % [id, i])
				_report("%s#%d" % [id, i])
	if args.has("reel"):
		main.show_screen("vault_hall")
		await _frames(4)
		var card_names: Array = []
		for cd in main.find_children("CrateCard_*", "Control", true, false):
			card_names.append(str(cd.name))
		for cn in card_names:
			var cd2 := main.find_child(cn, true, false)
			if cd2 == null:
				continue
			var cb: Button = null
			for ch in cd2.get_children():
				if ch is Button:
					cb = ch
			if cb != null:
				cb.pressed.emit()
				await _frames(3)
				var ready := false
				var bl: Array = []
				_buttons(main.get("_current"), bl)
				for bv2 in bl:
					if is_instance_valid(bv2) and (bv2 as Button).is_visible_in_tree() and not (bv2 as Button).disabled and TranslationServer.translate((bv2 as Button).text) == "Apri":
						ready = true
				print("Q119 reel: carta ", cn, " apribile=", ready)
				if ready:
					break
		var cands: Array = []
		_buttons(main.get("_current"), cands)
		var pressed := false
		for bv in cands:
			if is_instance_valid(bv) and (bv as Button).is_visible_in_tree() and not (bv as Button).disabled and TranslationServer.translate((bv as Button).text) == "Apri":
				(bv as Button).pressed.emit()
				pressed = true
				break
		print("Q119 reel: premuto Apri = ", pressed)
		for k3 in 6:
			await _frames(25)
			await _shot("reel_%d" % k3)
			_report("reel#%d" % k3)
		for k3 in 3:
			for nm in ["CrateContinue", "ReelContinue", "RevealOk"]:
				var bb2 := main.find_child(nm, true, false) as Button
				if bb2 != null:
					print("Q119 reel: bottone ", nm)
	if args.has("refound_ui"):
		main.show_screen("estate")
		await _frames(4)
		var bl2: Array = []
		_buttons(main.get("_current"), bl2)
		for bv3 in bl2:
			if is_instance_valid(bv3) and (bv3 as Button).is_visible_in_tree() and not (bv3 as Button).disabled and TranslationServer.translate((bv3 as Button).text) == "Rifondazione":
				(bv3 as Button).pressed.emit()
				break
		await _frames(6)
		await _shot("refound_dialog_1")
		var ws: Array = main.find_children("*", "Window", true, false)
		for w in ws:
			if (w as Window).visible:
				print("Q119 dialogo aperto: ", w.get_class(), " ", w.name)
		_report("refound_ui")
	if args.has("vtabs"):
		main.show_screen("vault_workshop")
		await _frames(4)
		var tabnames: Array = []
		for tb in main.find_children("Tab_*", "Button", true, false):
			tabnames.append(str(tb.name))
		for tn in tabnames:
			var tb2 := main.find_child(tn, true, false) as Button
			if tb2 != null and not tb2.disabled:
				tb2.pressed.emit()
				await _frames(4)
				game.call("_on_step", 0.1)
				await _shot("vtab_" + tn)
				_report("vtab:" + tn)
	if args.has("tabs"):
		for id in ids:
			if id.begins_with("coop") or id == "settings" or id == "news":
				continue
			main.show_screen(id)
			await _frames(3)
			var cur2: Variant = main.get("_current")
			if not is_instance_valid(cur2):
				continue
			for tc in (cur2 as Node).find_children("*", "TabContainer", true, false):
				var tcc := tc as TabContainer
				if not tcc.is_visible_in_tree():
					continue
				for i in tcc.get_tab_count():
					tcc.current_tab = i
					await _frames(3)
					game.call("_on_step", 0.1)
					await _shot("tab_%s_%d" % [id, i])
					_report("tab:%s#%d" % [id, i])
	if args.has("expand"):
		for id in ids:
			if not id.begins_with("skill:") or id == "skill:farming":
				continue
			main.show_screen(id)
			await _frames(3)
			var heads: Array = []
			_buttons(main.get("_current"), heads)
			for hv in heads:
				if is_instance_valid(hv) and (hv as Button).is_visible_in_tree() and (hv as Button).toggle_mode and not (hv as Button).button_pressed:
					(hv as Button).button_pressed = true
					await _frames(3)
			await _shot("expand_" + id)
			_report("expand:" + id)
			var sc2 := _best_scroll(main.get("_current"))
			if sc2 == null:
				sc2 = main.find_child("ScreenScroll", true, false) as ScrollContainer
			if sc2 != null:
				sc2.scroll_vertical = 520
				await _frames(3)
				await _shot("expand2_" + id)
				sc2.scroll_vertical = 1040
				await _frames(3)
				await _shot("expand3_" + id)
				sc2.scroll_vertical = 0
	if args.has("mash"):
		for id in ids:
			if (id.begins_with("coop") or id == "settings" or id == "news" or id == "prestige" or id == "guide") and not args.has("mashall"):
				continue
			main.show_screen(id)
			await _frames(3)
			var btns: Array = []
			var cur: Variant = main.get("_current")
			_buttons(cur if is_instance_valid(cur) else null, btns)
			var done := 0
			for bv in btns:
				if not is_instance_valid(bv):
					continue
				var b: Button = bv
				if not b.is_visible_in_tree() or b.disabled:
					continue
				var txt := TranslationServer.translate(b.text).strip_edges()
				if _skip_btn(txt):
					continue
				done += 1
				if done > 50:
					break
				print("Q119 PRESS ", id, " | ", txt.left(50), " | ", b.get_path().get_name(b.get_path().get_name_count() - 1))
				b.pressed.emit()
				await _frames(2)
				game.call("_on_step", 0.1)
				var wins: Array = []
				for w in main.find_children("*", "Window", true, false):
					if (w as Window).visible:
						wins.append(w)
				if not wins.is_empty():
					_popup_n += 1
					for w0 in wins:
						var wt := TranslationServer.translate((w0 as Window).title)
						var r0 := Rect2((w0 as Window).position, (w0 as Window).size)
						print("Q119 POPUP «", txt, "» in ", id, " titolo=«", wt, "» rect=", r0, " ", w0.get_class())
						if wt in ["Alert!", "Please Confirm...", ""] or wt.begins_with("UI_"):
							print("Q119 POPUP TITOLO NON TRADOTTO «", wt, "» in ", id)
						if r0.end.x > 1282 or r0.end.y > 722 or r0.position.x < -2 or r0.position.y < -2:
							print("Q119 POPUP FUORI FINESTRA in ", id, " ", r0)
					if _popup_n <= 30:
						await _shot("popup_%d_%s" % [_popup_n, id])
					for k2 in 8:                                # circa 1 s di partita: la finestra deve restare aperta
						for q in 10:
							game.call("_on_step", 0.1)
						main.call("_on_ui_tick")
						await _frames(2)
					for w in wins:
						if not is_instance_valid(w) or not (w as Window).visible:
							print("Q119 POPUP SI CHIUDE DA SOLO dopo «", txt, "» in ", id)
						else:
							(w as Window).hide()
					await _frames(2)
				for nm in ["WbCollect", "TutorialOk", "TutorialSkipAll"]:
					var bb := main.find_child(nm, true, false) as Button
					if bb != null and bb.is_visible_in_tree():
						bb.pressed.emit()
				if main.get("_current") == null or not is_instance_valid(main.get("_current")):
					break
			await _shot("mash_" + id)
			_report("mash:" + id)
	print("Q119 fine, problemi: ", _issues.size())
	quit(0)


func _buttons(n: Node, out: Array) -> void:
	if n == null:
		return
	for c in n.get_children():
		if c is Button and not (c is OptionButton) and not (c is CheckBox):
			out.append(c)
		_buttons(c, out)


func _skip_btn(t: String) -> bool:
	var low := t.to_lower()
	for w in ["rifondaz", "elimina", "cancella", "azzera", "reset", "esci", "ritira", "abbandon", "ricomincia", "rito", "stella", "reimposta", "vendi tutto", "vendi in blocco", "scarta", "ricicla", "sacrifica", "licenzia", "congeda"]:
		if low.contains(w):
			return true
	return false


func _best_scroll(n: Variant) -> ScrollContainer:
	if not is_instance_valid(n):
		return null
	var best: ScrollContainer = null
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is ScrollContainer and (c as Control).is_visible_in_tree():
			var sb := (c as ScrollContainer).get_v_scroll_bar()
			if sb.max_value - sb.page > 40 and (best == null or (c as Control).size.y > best.size.y):
				best = c
		for k in c.get_children():
			stack.append(k)
	return best
