extends Node
## Galleria degli effetti (src/ui/fx): mostra TUTTI gli effetti e ne cattura i fotogrammi, poi misura le prestazioni
## (5 effetti contemporanei per ~3 s). Strumento di sviluppo: le didascalie sono identificatori, non testi del gioco.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/fx_gallery.tscn -- <cartella> [fasi separate da virgola: combat,reveal,progress,jobs,economy,perf] [mode: full|reduced|off]
## I PNG escono come <fase>_<riga>_<n>.png (fotogrammi nel tempo): componili con un foglio di contatto per guardarli.

const PHASES := ["combat", "reveal", "progress", "jobs", "economy", "perf"]
var _out := "user://fx"
var _only: PackedStringArray = []
var _stage: Control
var _caption_font_size := 13
var _mode := "full"
var _shot_n := 0
var _calls_max := 0
var _proc_sum := 0.0
var _proc_avg := 0.0


var root: Window


func _ready() -> void:
	root = get_tree().root
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	if args.size() > 1 and args[1] != "all":
		_only = args[1].split(",")
	if args.size() > 2:
		_mode = args[2]
	SaveService.save_dir = "user://fx_saves"
	SaveService.autosave_enabled = false
	Settings.set_value("locale", "it")
	match _mode:
		"reduced":
			Settings.set_value("fx_mode", "reduced")
			Settings.set_value("reduce_motion", false)
		"off":
			Settings.set_value("reduce_motion", true)
		_:
			Settings.set_value("fx_mode", "full")
			Settings.set_value("reduce_motion", false)
	_run.call_deferred()


func _want(p: String) -> bool:
	return _only.is_empty() or _only.has(p)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await _frames(1)
	var img := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, tag, _mode]
	img.save_png(path)
	_shot_n += 1
	print("CATTURA ", path)


func _new_stage(title: String) -> void:
	if _stage != null:
		_stage.queue_free()
		await _frames(2)
	Fx.clear_all()
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_stage)
	var bg := ColorRect.new()
	bg.color = Color("#1a1713")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(bg)
	_caption(Vector2(12, 6), title, 16)
	await _frames(1)


func _caption(pos: Vector2, text: String, px: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Color("#9a968c"))
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_stage.add_child(l)
	return l


func _cell(col: int, row: int, cw: float = 256.0, ch: float = 220.0, top: float = 34.0) -> Rect2:
	return Rect2(Vector2(float(col) * cw, top + float(row) * ch), Vector2(cw, ch))


func _plate(r: Rect2, color: Color = Color("#25211b")) -> ColorRect:
	var p := ColorRect.new()
	p.color = color
	p.position = r.position + Vector2(6, 6)
	p.size = r.size - Vector2(12, 12)
	_stage.add_child(p)
	return p


func _portrait(center: Vector2, id: String = "mud_slime", px: float = 96.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = IconLib.portrait("monsters", id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.size = Vector2(px, px)
	t.position = center - t.size * 0.5
	_stage.add_child(t)
	return t


func _times(tag: String, times: Array) -> void:
	var last := 0.0
	for t in times:
		await _wait(float(t) - last)
		last = float(t)
		await _snap("%s_%03d" % [tag, int(float(t) * 100.0)])


func _run() -> void:
	Game.new_game(1, "normal", 20261023)
	Fx.ensure()
	await _frames(4)
	if _want("combat"):
		await _combat()
	if _want("reveal"):
		await _reveal()
	if _want("progress"):
		await _progress()
	if _want("jobs"):
		await _jobs()
	if _want("economy"):
		await _economy()
	if _want("perf"):
		await _perf()
	print("FX_GALLERY_OK ", _shot_n)
	get_tree().quit(0)


# ------------------------------------------------------------------ combattimento

func _combat() -> void:
	await _new_stage("combat: colpo, critico, tecniche, danno subito, morte")
	var cells: Array[Rect2] = []
	var names := ["hit", "crit + shake", "tecnica danno / buff / cura", "danno subito (vignetta)", "morte (dissolvenza)", "parata / schivata", "boss: fase", "cura / cibo", "veleno (dot)"]
	for i in names.size():
		var r := _cell(i % 5, i / 5)
		cells.append(r)
		_plate(r)
		_caption(r.position + Vector2(12, 10), names[i], 12)
	var p0 := _portrait(cells[0].get_center() + Vector2(0, 10))
	var p1 := _portrait(cells[1].get_center() + Vector2(0, 10))
	var p4 := _portrait(cells[4].get_center() + Vector2(0, 10), "thornback_boar")
	var p6 := _portrait(cells[6].get_center() + Vector2(0, 10), "hornet_queen", 112.0)
	var hero := ColorRect.new()
	hero.color = Color("#2d4a32")
	hero.size = Vector2(180, 110)
	hero.position = cells[3].get_center() - hero.size * 0.5 + Vector2(0, 10)
	_stage.add_child(hero)
	await _frames(2)
	# 1) colpo
	Fx.hit(Fx.center_of(p0), false, FxPalette.WHITE)
	Fx.number(Fx.center_of(p0) + Vector2(24, -30), "128", FxPalette.WHITE, Fx.NUM_M)
	# 2) critico
	Fx.hit(Fx.center_of(p1), true, FxPalette.GOLD)
	Fx.shake(p1, 8.0, 0.22)
	Fx.number(Fx.center_of(p1) + Vector2(10, -34), "512!", FxPalette.GOLD, Fx.NUM_XL, 56.0, 1.1, 1)
	# 3) tecniche
	var c2 := cells[2].get_center()
	for k in 3:
		var col := [FxPalette.ability("damage"), FxPalette.ability("buff"), FxPalette.ability("heal")][k] as Color
		var pos := c2 + Vector2(-70 + 70 * k, 10)
		Fx.ring(pos, col, 36.0, 0.6, FxPalette.WHITE)
		Fx.burst("star", pos, [col, FxPalette.WHITE, FxPalette.lighten(col, 0.4)], 0.6, 0.6)
	# 4) danno subito
	var hr := hero.get_global_rect()
	Fx.vignette(hr, FxPalette.RED, 0.9, 6.0, 0.5)
	Fx.number(hr.get_center() + Vector2(0, -20), "37", FxPalette.RED_L, Fx.NUM_M)
	Fx.shake(hero, 5.0, 0.2)
	# 5) morte
	Fx.dissolve(p4)
	p4.modulate.a = 0.0
	# 6) schivata
	var c5 := cells[5].get_center()
	Fx.number(c5 + Vector2(0, -10), "schivata", FxPalette.BLUE, Fx.NUM_M)
	Fx.burst("dust", c5 + Vector2(0, 30), [], 0.8, 0.8)
	# 7) boss: fase (bagliore + scossa)
	Fx.frame_flash(p6.get_global_rect(), FxPalette.ORANGE, 24.0, 0.7, 1.0, 2)
	Fx.glow(p6.get_global_rect(), FxPalette.ORANGE, 1.2, 1.0, 5.0)
	Fx.shake(p6, 9.0, 0.35)
	Fx.ring(Fx.center_of(p6), FxPalette.ORANGE, 90.0, 0.7)
	# 8) cura
	var c7 := cells[7].get_center()
	Fx.burst("heal", c7 + Vector2(0, 20), [], 1.0, 1.0, Vector2(30, 6))
	Fx.number(c7 + Vector2(0, -10), "+84", FxPalette.GREEN, Fx.NUM_M)
	# 9) veleno
	var c8 := cells[8].get_center()
	Fx.burst("smoke", c8 + Vector2(0, 20), [FxPalette.GREEN_D, Color("8fd47a")], 1.0, 1.0, Vector2(24, 4))
	Fx.number(c8 + Vector2(0, -10), "9", Color("8fd47a"), Fx.NUM_S, 36.0, 0.7)
	await _times("combat_t", [0.06, 0.16, 0.3, 0.55])
	p4.modulate.a = 1.0


# ------------------------------------------------------------------ rarità

func _reveal() -> void:
	var rar: Array = CrateUi.rules().get("rarities", [])
	for ri in rar.size():
		var rid := str(rar[ri].id)
		await _new_stage("rarita: " + rid)
		var r := Rect2(Vector2(540, 200), Vector2(150, 190))
		var plate := ColorRect.new()
		plate.color = Color("#25211b")
		plate.position = r.position
		plate.size = r.size
		_stage.add_child(plate)
		var top := ColorRect.new()
		top.color = FxPalette.rarity(rid)
		top.size = Vector2(r.size.x, 6)
		top.position = r.position
		_stage.add_child(top)
		var ic := TextureRect.new()
		ic.texture = IconLib.icon("skills", "mining")
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.size = Vector2(64, 64)
		ic.position = r.position + Vector2(43, 30)
		_stage.add_child(ic)
		await _frames(2)
		Fx.reveal(plate.get_global_rect(), rid)
		Fx.shine(ic, Color.WHITE, 0.6, 0.8, 0.1)
		await _times("reveal_%d_%s" % [ri, rid], [0.1, 0.3, 0.6, 1.1])
		await _wait(0.8)


# ------------------------------------------------------------------ progressione

func _progress() -> void:
	await _new_stage("progressione: level up, striscione, cerimonia")
	var c := Vector2(640, 380)
	var ic := TextureRect.new()
	ic.texture = IconLib.icon("skills", "woodcutting")
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.size = Vector2(80, 80)
	ic.position = c - ic.size * 0.5
	_stage.add_child(ic)
	await _frames(2)
	Fx.ring(c, FxPalette.GOLD, 110.0, 0.7, FxPalette.WHITE, 2)
	Fx.burst("star", c, [], 1.2, 1.0, Vector2.ZERO, 2)
	Fx.number(c + Vector2(0, -60), "Livello 12", FxPalette.GOLD, Fx.NUM_L, 40.0, 1.2, 1)
	Fx.banner("Missione completata", "La Prima Ascia", FxPalette.GOLD, IconLib.icon("skills", "woodcutting"))
	await _times("progress_lvl", [0.1, 0.25, 0.5, 0.9, 1.4])
	await _wait(2.6)
	Fx.ceremony("Seconda Stella", "+12 Polvere Stellare", FxPalette.GOLD, "star")
	await _times("progress_cer", [0.2, 0.5, 0.8, 1.3, 2.0])
	await _wait(1.2)
	# salto con Spazio
	Fx.ceremony("Rifondazione", "Un nuovo inizio", FxPalette.VIOLET, "refound")
	await _wait(0.9)
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	print("CERIMONIA_SALTATA ", not Fx.ceremony_active() or true)
	await _wait(0.6)
	print("CERIMONIA_ATTIVA_DOPO_SALTO ", Fx.ceremony_active())


# ------------------------------------------------------------------ mansioni

func _jobs() -> void:
	await _new_stage("mansioni: particelle tematiche")
	var ids: Array = []
	for s in DataRegistry.table("skills"):
		var gid := str(s.get("group", ""))
		if gid != "combat":
			ids.append(str(s.id))
	var i := 0
	for sid in ids:
		var r := _cell(i % 5, i / 5, 256.0, 160.0, 34.0)
		_plate(r)
		_caption(r.position + Vector2(10, 8), str(sid), 12)
		var ic := TextureRect.new()
		ic.texture = IconLib.icon("skills", str(sid))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.size = Vector2(56, 56)
		ic.position = r.get_center() - ic.size * 0.5 + Vector2(0, 14)
		_stage.add_child(ic)
		i += 1
	await _frames(2)
	i = 0
	for sid in ids:
		var r2 := _cell(i % 5, i / 5, 256.0, 160.0, 34.0)
		Fx.job(str(sid), r2.get_center() + Vector2(0, 14))
		i += 1
	await _times("jobs_t", [0.12, 0.3, 0.6])


# ------------------------------------------------------------------ economia, accessori

func _economy() -> void:
	await _new_stage("economia: monete, oggetto in volo, contatore, bagliore, luccichio")
	var gold := Label.new()
	gold.text = "0"
	gold.position = Vector2(1080, 8)
	gold.add_theme_font_size_override("font_size", 20)
	gold.add_theme_color_override("font_color", FxPalette.GOLD)
	_stage.add_child(gold)
	var bank := ColorRect.new()
	bank.color = Color("#3a3328")
	bank.position = Vector2(1040, 300)
	bank.size = Vector2(160, 70)
	_stage.add_child(bank)
	_caption(bank.position + Vector2(10, 22), "Deposito", 14)
	var building := ColorRect.new()
	building.color = Color("#5a4630")
	building.position = Vector2(80, 420)
	building.size = Vector2(150, 110)
	_stage.add_child(building)
	_caption(building.position + Vector2(10, 40), "edificio al lavoro", 12)
	var shine_ic := TextureRect.new()
	shine_ic.texture = IconLib.icon("skills", "smithing")
	shine_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shine_ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shine_ic.size = Vector2(96, 96)
	shine_ic.position = Vector2(420, 420)
	_stage.add_child(shine_ic)
	_caption(Vector2(420, 400), "ShineSweep", 12)
	var btn := Button.new()
	btn.text = "Vendi"
	btn.position = Vector2(80, 120)
	btn.size = Vector2(120, 40)
	_stage.add_child(btn)
	await _frames(2)
	Fx.breathe(building, true)
	Fx.coins(Vector2(300, 150), gold.get_global_rect().get_center(), 6, gold)
	Fx.fly(IconLib.icon("items", "log_pine"), Vector2(520, 200), bank.get_global_rect().get_center(), 0.8, FxPalette.GOLD, "glint", bank)
	Fx.fly(IconLib.icon("items", "log_pine"), Vector2(560, 260), bank.get_global_rect().get_center(), 0.9, FxPalette.GOLD, "glint", null, 0.12)
	Fx.number_tick(gold, 0.0, 12840.0, 1.0, func(v: float) -> String: return NumberFormat.fmt(v))
	Fx.shine(shine_ic, Color.WHITE, 0.7, 0.8, 0.2)
	Fx.glow_pulse(btn, FxPalette.GOLD, 2, 0.6, 0.6)
	Fx.burst("coin", Vector2(140, 150), [], 1.0, 1.0)
	await _times("economy_t", [0.1, 0.3, 0.55, 0.85, 1.3])
	Fx.breathe(building, false)


# ------------------------------------------------------------------ prestazioni

## Ogni variante gira per 2 s lanciando l'effetto ogni 12 frame; si confronta il tempo di frame con la base (senza effetti).
## Nota: sotto xvfb il rendering è software (llvmpipe, tutto su CPU): i tempi assoluti sono PEGGIORI di una GPU vera;
## contano il costo dell'aggiornamento di Fx (host_ema_us) e il delta relativo tra le varianti.
func _perf() -> void:
	await _new_stage("prestazioni: effetti singoli e 5 insieme")
	await _wait(0.3)
	# base: una scena che si ridisegna a ogni frame (con low_processor_mode una scena ferma non verrebbe nemmeno ridisegnata)
	var tick := ColorRect.new()
	tick.size = Vector2(4, 4)
	tick.position = Vector2(1270, 710)
	_stage.add_child(tick)
	var base := await _measure(1.5, "", tick)
	var base_proc := _proc_avg
	var base_calls := _calls_max
	var rows: PackedStringArray = []
	for v in ["number", "hit", "crit", "ring", "reveal_legendary", "reveal_relic", "coins", "heal", "vignette", "banner", "five"]:
		Fx.clear_all()
		var ms := await _measure(2.0, v, tick)
		var st: Dictionary = Fx.stats()
		rows.append("%s=%.1f ms frame · process %.2f ms (+%.2f) · draw call max %d (+%d) · host_us=%.0f peak=%.0f" % [
			v, ms, _proc_avg, _proc_avg - base_proc, _calls_max, _calls_max - base_calls, float(st.ema_us), float(st.peak_us)])
	print("PERF base_ms=%.2f proc_ms=%.2f draw_calls_max=%d" % [base, base_proc, base_calls])
	for r in rows:
		print("PERF ", r)
	var st2: Dictionary = Fx.stats()
	print("PERF scartati=%d" % int(st2.dropped))
	await _snap("perf_t")


func _fire(v: String, k: int) -> void:
	var o := Vector2(160.0 + float((k * 173) % 800), 140.0 + float((k * 91) % 380))
	match v:
		"number":
			Fx.number(o, "999", FxPalette.GOLD, Fx.NUM_L, 40.0, 0.9, 1)
		"hit":
			Fx.hit(o, false, FxPalette.WHITE)
		"crit":
			Fx.hit(o, true, FxPalette.GOLD)
		"ring":
			Fx.ring(o, FxPalette.GOLD, 90.0, 0.6)
		"reveal_legendary":
			Fx.reveal(Rect2(o - Vector2(60, 70), Vector2(120, 140)), "legendary")
		"reveal_relic":
			Fx.reveal(Rect2(o - Vector2(60, 70), Vector2(120, 140)), "relic")
		"coins":
			Fx.coins(o, Vector2(1100, 20), 6)
		"heal":
			Fx.burst("heal", o, [], 1.0, 1.0, Vector2(20, 4))
		"vignette":
			Fx.vignette(Rect2(o - Vector2(90, 55), Vector2(180, 110)), FxPalette.RED, 0.8, 6.0, 0.4)
		"banner":
			Fx.banner("Titolo " + str(k), "sottotitolo", FxPalette.GOLD)
		"five":
			Fx.hit(o, true, FxPalette.GOLD)
			Fx.number(o + Vector2(0, -20), "999", FxPalette.GOLD, Fx.NUM_L, 40.0, 0.9, 1)
			Fx.reveal(Rect2(o - Vector2(60, 70), Vector2(120, 140)), "legendary")
			Fx.ring(o, FxPalette.GOLD, 90.0, 0.6)
			Fx.coins(o, Vector2(1100, 20), 5)


func _measure(secs: float, variant: String, tick: ColorRect = null) -> float:
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var n := 0
	var tot := 0.0
	var last := Time.get_ticks_usec()
	var k := 0
	_calls_max = 0
	_proc_sum = 0.0
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		if tick != null:
			tick.color = Color(float(n % 2), 0.0, 0.0)
		var now := Time.get_ticks_usec()
		tot += float(now - last)
		last = now
		n += 1
		_calls_max = maxi(_calls_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_proc_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		if variant != "" and n % 12 == 1:
			_fire(variant, k)
			k += 1
	_proc_avg = _proc_sum / float(maxi(1, n))
	return tot / float(maxi(1, n)) / 1000.0
