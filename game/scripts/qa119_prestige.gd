extends SceneTree
## QA119: giro del prestigio sul sistema vero partendo da un checkpoint: Rito, Stella, Costellazioni, Rifondazione, Ere.
## Stampa «Q119R ...» per ogni passo (esito, motivo del rifiuto, anteprima) e controlla che dopo ognuno il gioco giri.
##   <godot> --headless --path game -s res://scripts/qa119_prestige.gd -- <cartella_checkpoint>

var G: Node


func _initialize() -> void:
	_run.call_deferred()


func _steps(n: int) -> void:
	for i in n:
		G.call("_on_step", 0.1)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var ss := root.get_node("SaveService")
	var save_dir := "user://q119r_saves"
	DirAccess.make_dir_recursive_absolute(save_dir)
	for f in DirAccess.get_files_at(save_dir):
		DirAccess.remove_absolute(save_dir + "/" + f)
	for f in DirAccess.get_files_at(args[0]):
		DirAccess.copy_absolute(args[0] + "/" + f, save_dir + "/" + f)
	ss.set("save_dir", save_dir)
	ss.set("autosave_enabled", false)
	G = root.get_node("Game")
	G.call("load_game", 1)
	var pr: Object = G.call("system", "prestige")
	var sk: Object = G.call("system", "skills")
	var data: Object = root.get_node("DataRegistry")
	var gold0: int = G.call("system", "bank").gold()
	print("Q119R inizio: stelle=%d polvere=%d soci=%d era=%d/%d consigliere=%s" % [pr.stars_total(), pr.dust(), pr.partners(), pr.era_current(), pr.era_max(), JSON.stringify(pr.advise()).left(200)])
	# --- Rito / Stella per ogni mansione
	var done_rite := 0
	var refused := {}
	for s in data.table("skills"):
		var sid := str(s.id)
		if sid == "hero" or sid == "bounty" or str(s.get("group", "")) == "combat":
			continue
		var why: String = pr.can_rite(sid)
		var why2: String = pr.can_star(sid)
		if why == "" and not pr.rite_done(sid):
			var pv: Dictionary = pr.preview_star(sid, true)
			var lv0: int = sk.level(sid)
			var r: Dictionary = pr.do_star(sid, true)
			_steps(50)
			print("Q119R RITO %s livello %d -> %d ok=%s polvere=%d %s" % [sid, lv0, sk.level(sid), r.get("ok", r), pr.dust(), JSON.stringify(pv).left(160)])
			done_rite += 1
		else:
			refused[sid] = "%s|%s" % [why, why2]
	print("Q119R riti fatti: %d; rifiuti: %s" % [done_rite, JSON.stringify(refused).left(700)])
	# --- Stella: porto una mansione a 100 con XP e provo la Stella vera
	var target := "woodcutting"
	var guard := 0
	while sk.level(target) < 100 and guard < 400:
		guard += 1
		var p: Array = sk.xp_progress(target)
		sk.add_xp(target, maxf(1.0, float(p[1]) - float(p[0]) + 1.0))
	print("Q119R Stella %s: can_star='%s' livello=%d" % [target, pr.can_star(target), sk.level(target)])
	if pr.can_star(target) == "":
		var r2: Dictionary = pr.do_star(target, false)
		_steps(50)
		print("Q119R STELLA ok=%s livello dopo=%d stelle=%d polvere=%d" % [r2.get("ok", r2), sk.level(target), pr.stars(target), pr.dust()])
	# --- Costellazioni: compro tutto il comprabile
	var bought := 0
	for nd in pr.nodes():
		var nid := str(nd.id)
		var qty: int = pr.max_buyable(nid)
		if qty > 0:
			var rb: Dictionary = pr.buy_node(nid, qty)
			if bool(rb.get("ok", false)):
				bought += qty
	_steps(50)
	print("Q119R Costellazioni: livelli comprati=%d polvere residua=%d" % [bought, pr.dust()])
	# --- Rifondazione
	var est: Object = G.call("system", "estate")
	print("Q119R Rifondazione: can='%s' guadagno=%d unita_vita=%.0f minimo=%.0f" % [pr.can_refound(), pr.refound_gain(), pr.lifetime_units(), pr.refound_min_units()])
	var prev: Dictionary = pr.preview_refound()
	print("Q119R anteprima: ", JSON.stringify(prev).left(500))
	if pr.can_refound() == "":
		var rf: Dictionary = pr.do_refound()
		_steps(100)
		print("Q119R RIFONDAZIONE ok=%s soci=%d casolare=%d coloni=%d" % [rf.get("ok", rf), pr.partners(), est.level_of("cottage"), est.settlers()])
	# --- Ere
	for e in range(2, 5):
		print("Q119R Era %d: %s" % [e, JSON.stringify(pr.preview_era(e)).left(400)])
		var re2: Dictionary = pr.do_select_era(e)
		print("Q119R   selezione Era %d -> %s" % [e, JSON.stringify(re2).left(200)])
	_steps(100)
	print("Q119R fine: gioco ancora in marcia, oro %d (prima %d)" % [G.call("system", "bank").gold(), gold0])
	quit(0)
