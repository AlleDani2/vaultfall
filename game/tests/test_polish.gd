extends GutTest
## Polish finale (resoconto 50): nomi delle Ere mostrati, banner ritagliati con una region (PNG intatti), testi lunghi che vanno a capo.

const _GS := preload("res://src/autoload/GameState.gd")
const BANNERS := "res://assets/banners/"

var _old_loc: String
var _old_dir: String


func before_each() -> void:
	_old_loc = str(Settings.get_value("locale"))
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_polish_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Settings.set_value("locale", _old_loc)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _ps_world() -> Dictionary:
	var state := _GS.default_state()
	var stack := ModifierStack.new()
	stack.set_catalog(DataRegistry.table("modifier_catalog"))
	var bus: Node = (load("res://src/autoload/EventBus.gd") as GDScript).new()
	autofree(bus)
	var ctx := SystemContext.make(DataRegistry, state, stack, RngStreams.new(5), bus)
	var sim := Simulation.new()
	var ps := PrestigeSystem.new()
	sim.setup(ctx, [BankSystem.new(), SkillSystem.new(), UnlockSystem.new(), ps])
	sim.bind_state(state)
	return {"ps": ps, "bus": bus, "state": state}


# ------------------------------------------------------------------ nomi delle Ere

func test_nomi_delle_dodici_ere_in_entrambe_le_lingue() -> void:
	var w := _ps_world()
	var ps: PrestigeSystem = w.ps
	var seen := {}
	for loc in ["it", "en"]:
		Settings.set_value("locale", loc)
		for n in range(1, 13):
			var nm := ps.era_name(n)
			assert_true(nm.contains("—"), "Era %d (%s) ha un nome dopo il numero: %s" % [n, loc, nm])
			assert_false(nm.begins_with("UI_"), "nessuna chiave grezza")
			seen[loc + nm] = true
	assert_eq(seen.size(), 24, "24 nomi distinti (12 × 2 lingue)")
	Settings.set_value("locale", "it")
	assert_eq(ps.era_name(1), "Era I — La Quiete Sospetta")


func test_era_oltre_la_dodicesima_ricade_su_era_n() -> void:
	var w := _ps_world()
	var ps: PrestigeSystem = w.ps
	Settings.set_value("locale", "it")
	assert_eq(ps.era_name(13), "Era 13")
	assert_eq(ps.era_name(0), "Era 0")


func test_avviso_di_sblocco_mostra_il_nome() -> void:
	var w := _ps_world()
	var ps: PrestigeSystem = w.ps
	Settings.set_value("locale", "it")
	var texts: Array = []
	w.bus.notice.connect(func(_k: String, t: String, _d: Dictionary) -> void: texts.append(t))
	ps.on_warden_defeated(1)
	var joined := "\n".join(PackedStringArray(texts))
	assert_true(joined.contains(ps.era_name(2)), "l'avviso dice «%s»: %s" % [ps.era_name(2), joined])


func test_stringhe_nuove_delle_ere_esistono() -> void:
	for k in ["UI_ERA_CURRENT_N", "UI_ERA_UNLOCKED_N"]:
		Settings.set_value("locale", "it")
		assert_ne(tr(k), k, k + " tradotta (it)")
		Settings.set_value("locale", "en")
		assert_ne(tr(k), k, k + " tradotta (en)")


# ------------------------------------------------------------------ banner

func _image(path: String) -> Image:
	return (load(path) as Texture2D).get_image()


func test_banner_con_fasce_scure_viene_ritagliato_senza_toccare_il_png() -> void:
	var path := BANNERS + "zones/ashen.png"
	var full := _image(path)
	var tex := IconLib.banner(path)
	assert_true(tex is AtlasTexture, "una region, non un nuovo file")
	var at := tex as AtlasTexture
	assert_eq(at.atlas.resource_path, path, "l'atlante è il PNG originale")
	assert_eq(int(at.region.size.x), full.get_width(), "larghezza intera")
	assert_between(int(at.region.position.y), 8, 12, "fascia superiore tolta")
	assert_lt(int(at.region.size.y), full.get_height() - 16, "anche quella inferiore")
	# il PNG resta identico: 320x96 e righe scure ancora presenti (D-6, CLAUDE.md regola 10)
	assert_eq(full.get_size(), Vector2i(320, 96))
	assert_lt(full.get_pixel(0, 0).v, 0.1, "la fascia scura è ancora nel file")


func test_banner_senza_fasce_resta_intero() -> void:
	var path := BANNERS + "zones/frostspire.png"
	var tex := IconLib.banner(path)
	assert_false(tex is AtlasTexture, "niente da togliere")
	assert_eq(tex.get_size(), Vector2(320, 96))


func test_tutti_i_banner_dei_dati_si_ritagliano_in_modo_sensato() -> void:
	var n := 0
	for tbl in ["zones", "dungeons", "raids"]:
		for d in DataRegistry.table(tbl):
			var p := str(d.get("banner", ""))
			assert_true(ResourceLoader.exists(p), "%s: il banner esiste (%s)" % [d.id, p])
			var tex := IconLib.banner(p)
			assert_gte(tex.get_height(), 60.0, "%s: resta almeno l'immagine centrale" % d.id)
			assert_lte(tex.get_height(), 96.0)
			assert_eq(tex.get_width(), 320.0)
			n += 1
	assert_gte(n, 20)


func test_banner_rect_senza_png_si_nasconde() -> void:
	var r := CombatUi.banner_rect("res://assets/banners/zones/non_esiste.png")
	autofree(r)
	assert_false(r.visible)
	assert_null(r.texture)
	var ok := CombatUi.banner_rect(BANNERS + "zones/ashen.png", 64.0)
	autofree(ok)
	assert_true(ok.visible)
	assert_eq(ok.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "riempie senza deformare")
	assert_eq(ok.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art nitida")


# ------------------------------------------------------------------ testi lunghi

func _main() -> Control:
	Game.new_game(1, "normal", 4243)
	var un: Object = Game.system("unlock")
	for t in ["combat", "raids", "world_bosses", "rift", "prestige", "constellations", "eras", "trials", "crates", "wardrobe", "talents", "bounties"]:
		un.grant("feature:" + t)
	un.grant("skill:hero")
	un.grant("dungeon:cursed_granary")
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	return main


func _buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_buttons(c, out)


func test_talenti_e_liste_vanno_a_capo_invece_di_tagliare() -> void:
	var main := await _main()
	var host := main.get("_host") as Control
	main.call("show_screen", "talents")
	await get_tree().process_frame
	var btns: Array = []
	_buttons(host.get_child(host.get_child_count() - 1), btns)
	var nodes := 0
	for pr in host.get_child(host.get_child_count() - 1).find_children("*", "PanelContainer", true, false):
		if pr is ScreenKit.PickRow:        # nodi a riquadro: il titolo va a capo, non si taglia
			nodes += 1
			var tl := (pr as ScreenKit.PickRow).title_l
			assert_false(tl.clip_text, "%s non taglia" % tl.text)
			assert_ne(tl.autowrap_mode, TextServer.AUTOWRAP_OFF, "%s va a capo" % tl.text)
	assert_gt(nodes, 4, "nodi dei talenti trovati")
	main.call("show_screen", "dungeon")
	await get_tree().process_frame
	for tab in ["dungeon", "raids", "worldboss"]:
		(host.get_child(host.get_child_count() - 1)).call("_set_tab", tab)
		await get_tree().process_frame
		btns.clear()
		_buttons(host.get_child(host.get_child_count() - 1), btns)
		var lst := 0
		for b in btns:
			if (b as Button).toggle_mode and (b as Button).button_group != null:
				lst += 1
				assert_false((b as Button).clip_text, "%s: voce dell'elenco senza ritaglio" % tab)
		assert_gt(lst, 0, tab + ": elenco trovato")
	Game.stop_game(false)


func test_banner_visibile_nelle_schermate_dungeon_e_incursioni() -> void:
	var main := await _main()
	var host := main.get("_host") as Control
	main.call("show_screen", "dungeon")
	await get_tree().process_frame
	var scr := host.get_child(host.get_child_count() - 1)
	var found := 0
	for tab in ["dungeon", "raids"]:
		scr.call("_set_tab", tab)
		await get_tree().process_frame
		await get_tree().process_frame
		var rects := scr.find_children("*", "TextureRect", true, false)
		for r in rects:
			var t := (r as TextureRect).texture
			if t != null and t.get_width() == 320 and (r as TextureRect).stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED:
				found += 1
				assert_true((r as TextureRect).visible)
	assert_gte(found, 2, "un banner nel dettaglio del dungeon e uno in quello dell'incursione")
	main.call("show_screen", "combat")
	await get_tree().process_frame
	var cs := host.get_child(host.get_child_count() - 1)
	var zb := 0
	for r in cs.find_children("*", "TextureRect", true, false):
		var t2 := (r as TextureRect).texture
		if t2 != null and t2.get_width() == 320:
			zb += 1
	assert_eq(zb, 1, "banner della zona nella colonna sinistra del Combattimento")
	Game.stop_game(false)
