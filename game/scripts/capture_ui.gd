extends SceneTree
## Catture del tema UI: menù iniziale (con slot) e «galleria dei controlli» (pannelli, pulsanti negli stati, campi, barre,
## rarità, accenti di sezione, finestra modale, stato vuoto). Serve un display (anche virtuale):
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     -s res://scripts/capture_ui.gd -- <cartella> <it|en>
## Con --resolution 1920x1080 si ottiene la cattura a 1080p (scala 1x). Non tocca i salvataggi veri.

const START := "res://src/ui/start/StartScreen.tscn"
var _out := "user://capture_ui"
var _tag := "it"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	root.get_node("SaveService").set("save_dir", "user://capture_ui_saves")
	root.get_node("SaveService").set("autosave_enabled", false)
	if args.size() > 1:
		_tag = args[1]
		root.get_node("Settings").call("set_value", "locale", args[1])
	if DisplayServer.window_get_size().x >= 1500:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(8)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s_%dx%d.png" % [_out, name, _tag, img.get_width(), img.get_height()]
	img.save_png(path)
	print("CATTURA ", path)


func _run() -> void:
	var game: Node = root.get_node("Game")
	var start: Control = (load(START) as PackedScene).instantiate()
	root.add_child(start)
	await _shot("menu_iniziale")
	start.call("show_slots")
	await _shot("menu_slot")
	start.queue_free()
	await _frames(2)
	var g := _gallery()
	root.add_child(g)
	await _shot("galleria_controlli")
	g.queue_free()
	await _frames(2)
	var g2 := _gallery_sections()
	root.add_child(g2)
	await _shot("galleria_sezioni_rarita")
	quit(0)


func _bg() -> Panel:
	var bg := Panel.new()
	bg.theme_type_variation = &"BackdropPanel"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg


func _lbl(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _btn(text: String, variation: StringName = &"", disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = disabled
	if variation != &"":
		b.theme_type_variation = variation
	return b


func _gallery() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(_bg())
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 16)
	c.add_child(m)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	m.add_child(cols)

	# colonna 1: titoli, pulsanti, campi
	var p1 := PanelContainer.new()
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(p1)
	var v1 := VBoxContainer.new()
	v1.add_theme_constant_override("separation", 8)
	p1.add_child(v1)
	v1.add_child(_lbl("Titolo di schermata", &"TitleLabel"))
	v1.add_child(_lbl("Sezione", &"SectionLabel"))
	v1.add_child(_lbl("Testo normale di prova, 1234567890", &""))
	v1.add_child(_lbl("Testo smorzato per le descrizioni lunghe", &"MutedLabel"))
	v1.add_child(_lbl("12.345.678", &"NumberLabel"))
	v1.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_btn("Normale"))
	row.add_child(_btn("Primario", &"AccentButton"))
	row.add_child(_btn("Disattivato", &"", true))
	v1.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var tg := _btn("Interruttore attivo")
	tg.toggle_mode = true
	tg.button_pressed = true
	row2.add_child(tg)
	var foc := _btn("Con focus")
	row2.add_child(foc)
	foc.grab_focus.call_deferred()
	v1.add_child(row2)
	var cb := CheckBox.new()
	cb.text = "Casella spuntata"
	cb.button_pressed = true
	cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v1.add_child(cb)
	var cb2 := CheckBox.new()
	cb2.text = "Casella vuota"
	cb2.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v1.add_child(cb2)
	var sw := CheckButton.new()
	sw.text = "Interruttore"
	sw.button_pressed = true
	sw.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v1.add_child(sw)
	var sw2 := CheckButton.new()
	sw2.text = "Interruttore spento"
	sw2.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v1.add_child(sw2)
	var le := LineEdit.new()
	le.text = "Campo di testo"
	v1.add_child(le)
	var se := LineEdit.new()
	se.placeholder_text = "Cerca…"
	se.theme_type_variation = &"SearchField"
	v1.add_child(se)
	var ob := OptionButton.new()
	ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ob.add_item("Elenco a discesa")
	ob.add_item("Seconda voce")
	v1.add_child(ob)
	var hs := HSlider.new()
	hs.value = 60
	hs.custom_minimum_size = Vector2(0, 20)
	v1.add_child(hs)
	for pair in [[0.7, ""], [0.35, "x"]]:
		var pb := ProgressBar.new()
		pb.max_value = 1.0
		pb.value = pair[0]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 16)
		v1.add_child(pb)
	var pbt := ProgressBar.new()
	pbt.max_value = 1.0
	pbt.show_percentage = false
	pbt.custom_minimum_size = Vector2(0, 16)
	pbt.add_theme_stylebox_override("fill", UiKit.tinted_fill(Color("#d05050")))
	pbt.value = 0.55
	v1.add_child(pbt)

	# colonna 2: pannelli, tab, lista, finestra
	var v2 := VBoxContainer.new()
	v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v2.add_theme_constant_override("separation", 10)
	cols.add_child(v2)
	for pair in [[&"PanelContainer", "Pannello base"], [&"RaisedPanel", "Pannello rialzato"], [&"InsetPanel", "Pannello incassato"],
			[&"CardPanel", "Card"], [&"LogPanel", "Registro"]]:
		var pc := PanelContainer.new()
		pc.theme_type_variation = pair[0]
		pc.add_child(_lbl(pair[1]))
		v2.add_child(pc)
	var tabs := TabContainer.new()
	for n in ["Prima", "Seconda"]:
		var t := _lbl("Contenuto " + n)
		t.name = n
		tabs.add_child(t)
	tabs.custom_minimum_size = Vector2(0, 80)
	v2.add_child(tabs)
	var il := ItemList.new()
	for n in ["Voce uno", "Voce due (scelta)", "Voce tre"]:
		il.add_item(n)
	il.select(1)
	il.custom_minimum_size = Vector2(0, 80)
	v2.add_child(il)
	v2.add_child(_lbl("Titolo finestra", &"WindowTitle"))
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", (load("res://src/ui/theme/main_theme.tres") as Theme).get_stylebox("panel", "TooltipPanel"))
	tip.add_child(_lbl("Suggerimento (tooltip) con bordo"))
	v2.add_child(tip)

	# colonna 3: stato vuoto, scroll
	var p3 := PanelContainer.new()
	p3.theme_type_variation = &"ContentPanel"
	p3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(p3)
	var v3 := VBoxContainer.new()
	v3.add_theme_constant_override("separation", 10)
	p3.add_child(v3)
	v3.add_child(_lbl("Pannello contenuto", &"SectionLabel"))
	var grp := ButtonGroup.new()
	for n in ["Voce del menù", "Voce selezionata", "Voce con mouse"]:
		var sbtn := _btn(n, &"SidebarButton")
		sbtn.toggle_mode = true
		sbtn.button_group = grp
		sbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sbtn.button_pressed = n == "Voce selezionata"
		v3.add_child(sbtn)
	v3.add_child(UiKit.empty_state("chest", "Il Deposito è vuoto"))
	v3.add_child(UiKit.empty_state("scroll", "Nessuna missione attiva"))
	v3.add_child(UiKit.empty_state("shelf", "Niente da vendere"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 70)
	var sv := VBoxContainer.new()
	for i in 12:
		sv.add_child(_lbl("Riga %d" % i))
	sc.add_child(sv)
	v3.add_child(sc)
	return c


func _gallery_sections() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(_bg())
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 16)
	c.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	var secs := HBoxContainer.new()
	secs.add_theme_constant_override("separation", 12)
	v.add_child(secs)
	for sec in ["city", "skills", "adventure", "progress"]:
		var host := PanelContainer.new()
		host.theme_type_variation = &"ContentPanel"
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.theme = UiKit.accent_theme(sec)
		var hv := VBoxContainer.new()
		hv.add_theme_constant_override("separation", 8)
		host.add_child(hv)
		hv.add_child(_lbl("Sezione " + sec, &"TitleLabel"))
		hv.add_child(_lbl("Sottotitolo", &"SectionLabel"))
		var cp := PanelContainer.new()
		cp.theme_type_variation = &"CardPanel"
		cp.add_child(_lbl("Card di sezione"))
		hv.add_child(cp)
		var pb := ProgressBar.new()
		pb.max_value = 1.0
		pb.value = 0.6
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 14)
		hv.add_child(pb)
		hv.add_child(_btn("Azione", &"AccentButton"))
		secs.add_child(host)
	var rar := HBoxContainer.new()
	rar.add_theme_constant_override("separation", 12)
	v.add_child(rar)
	for r in UiKit.RARITY_KEYS:
		var cell := PanelContainer.new()
		cell.theme_type_variation = UiKit.rarity_variation(r, true)
		cell.custom_minimum_size = Vector2(150, 90)
		cell.add_child(_lbl(String(r).capitalize()))
		rar.add_child(cell)
	var rar2 := HBoxContainer.new()
	rar2.add_theme_constant_override("separation", 12)
	v.add_child(rar2)
	for r in UiKit.RARITY_KEYS:
		var cell := PanelContainer.new()
		cell.theme_type_variation = UiKit.rarity_variation(r, false)
		cell.custom_minimum_size = Vector2(150, 70)
		cell.add_child(_lbl("Slot " + String(r)))
		rar2.add_child(cell)
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Vuoi davvero cominciare una nuova partita? Il vecchio salvataggio resta nel backup."
	dlg.title = "Conferma"
	dlg.dialog_autowrap = true
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	v.add_child(dlg)
	dlg.popup_centered.call_deferred(Vector2i(420, 150))
	var tb := PanelContainer.new()
	tb.theme_type_variation = &"TopBarPanel"
	tb.add_child(_lbl("Barra superiore", &"BrandLabel"))
	v.add_child(tb)
	return c
