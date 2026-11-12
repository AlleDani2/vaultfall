extends Node
## Galleria deterministica del «juice»: tre palchi (mischia / distanza / magia) con un mostro e un eroe-segnaposto,
## colpo normale e critico a istanti fissi dopo l'impatto; poi una fila di mansioni (attrezzo + bersaglio) a istanti
## fissi del ciclo. Salva i fotogrammi in <cartella>/<nome>_<modo>.png.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path game --rendering-driver opengl3 --resolution 1280x720 \
##     res://scripts/capture_juice.tscn -- <cartella> [full|reduced|off]

var _out := "user://juice"
var _mode := "full"
var _stages: Array = []          # {portrait, hero}
var _tools: Array = []           # {tool, target, skill}
var _root: Control
var _n := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mode = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.set_value("locale", "it")
	Settings.set_value("reduce_motion", _mode == "off")
	Settings.set_value("fx_mode", "reduced" if _mode == "reduced" else "full")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(tag: String) -> void:
	await _frames(1)
	var img := get_tree().root.get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_out, tag, _mode])
	_n += 1
	print("CATTURA ", tag)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("1a1c24")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var mons := ["ancestral_roc", "animated_scarecrow", "ancestral_roc"]
	for i in 3:
		var x := 40.0 + 410.0 * float(i)
		var stage := Control.new()
		stage.position = Vector2(x, 30)
		stage.size = Vector2(380, 250)
		_root.add_child(stage)
		var p := TextureRect.new()
		p.texture = IconLib.portrait("monsters", mons[i])
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		p.position = Vector2(30, 40)
		p.size = Vector2(128, 128)
		stage.add_child(p)
		var hero := TextureRect.new()
		hero.texture = IconLib.icon("skills", "hero")
		hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hero.position = Vector2(270, 60)
		hero.size = Vector2(80, 80)
		stage.add_child(hero)
		_stages.append({"portrait": p, "hero": hero})
	var skills := ["woodcutting", "mining", "fishing", "smithing", "cooking", "tailoring"]
	for i in skills.size():
		var x := 50.0 + 200.0 * float(i)
		var t := TextureRect.new()
		t.texture = IconLib.icon("skills", skills[i])
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.position = Vector2(x, 380)
		t.size = Vector2(64, 64)
		_root.add_child(t)
		var g := TextureRect.new()
		g.texture = IconLib.icon("skills", skills[i])
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		g.modulate = Color(0.8, 1.0, 0.8)
		g.position = Vector2(x, 500)
		g.size = Vector2(64, 64)
		_root.add_child(g)
		_tools.append({"tool": t, "target": g, "skill": skills[i]})


func _center(n: Control) -> Vector2:
	return n.get_global_rect().get_center()


func _hit(i: int, crit: bool) -> void:
	var st: Dictionary = _stages[i]
	var p: TextureRect = st.portrait
	var hero: Control = st.hero
	var style: String = ["melee", "ranged", "arcane"][i]
	var c := _center(p)
	var d := FxJuice.dir(_center(hero), c)
	Fx.number(c + Vector2(0, -50), "42!" if crit else "17", Color("ffd24a") if crit else Color.WHITE, Fx.NUM_XL if crit else Fx.NUM_M, 50.0, 1.0, 1)
	Fx.strike(style, _center(hero), c, Color("ffd24a") if crit else FxPalette.WHITE, crit)
	Fx.hit(c, crit, Color("ffd24a") if crit else Color.WHITE)
	Fx.hit_flash(p, crit)
	Fx.impact(p, d, 14.0 if crit else 7.0, 9.0 if crit else 4.0, 0.24 if crit else 0.16)
	Fx.impact(hero, d, 18.0 if crit else 12.0, 0.0, 0.2)


func _run() -> void:
	Fx.ensure()
	await _frames(3)
	_build()
	await _frames(4)
	for crit in [false, true]:
		for k in 3:
			FxJuice.reset_limiter()
			for i in 3:
				_hit(i, crit)
			await _frames(1 + k * 2)
			await _snap("hit_%s_%d" % ["crit" if crit else "norm", k])
			await get_tree().create_timer(0.7).timeout
	for i in _tools.size():
		var tt: Dictionary = _tools[i]
		Fx.tool_start(tt.tool, tt.target, tt.skill, 1.0, 0.0)
	await get_tree().create_timer(0.72).timeout
	await _snap("tool_windup")
	await get_tree().create_timer(0.3).timeout
	for i in _tools.size():
		var tt: Dictionary = _tools[i]
		Fx.tool_strike(tt.tool, tt.target, tt.skill)
		Fx.job(tt.skill, _center(tt.target))
	await _frames(2)
	await _snap("tool_strike_a")
	await _frames(2)
	await _snap("tool_strike_b")
	await get_tree().create_timer(0.5).timeout
	await _snap("tool_rest")
	print("JUICE_OK ", _n)
	get_tree().quit(0)
