extends GutTest
## ETICA (CLAUDE.md regola 5, docs/24 R-LEG-5): la Sabbia del Custode non tocca le Casse. L'esito dell'N-esima apertura dipende solo
## da (seme, id cassa, N): stessa sequenza di aperture con e senza Spinta => stessi oggetti, stesso seme, stesso contatore draw_n.

const CRATE := "crate_millbrook"
const N := 30

var _old_dir: String
var _old_auto: bool


func before_all() -> void:
	_old_dir = SaveService.save_dir
	_old_auto = SaveService.autosave_enabled
	SaveService.save_dir = "user://test_time_push_crates_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	if GameState.active:
		Game.stop_game(false)


func after_all() -> void:
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = _old_auto


func _setup(seed_value: int, with_push: bool) -> Dictionary:
	assert_true(Game.new_game(1, "normal", seed_value))
	var bank := Game.system("bank") as BankSystem
	var crates := Game.system("crates") as CrateSystem
	var key: Variant = DataRegistry.item(CRATE).crate.get("key")
	bank.add(CRATE, N)
	if key != null:
		bank.add(str(key), N)
	var tp := Game.system("time_push") as TimePushSystem
	if with_push:
		(Game.system("unlock") as UnlockSystem).grant(str(DataRegistry.constants.time_push.unlock_token))
		tp.state["gift_given"] = true
		tp.state["reserve_s"] = 200.0
		GameState.data.unlocks.append("skill:woodcutting")
		var sk := Game.system("skills") as SkillSystem
		for a in DataRegistry.actions_for_skill("woodcutting"):
			if int(a.get("level_req", 1)) <= 1 and sk.start(str(a.id)):
				break
	var out: Array = []
	for i in N:
		if with_push:
			Game.debug_push(10)
			tp.drain(int(DataRegistry.constants.time_push.max_steps_per_frame))
		var r := crates.open(CRATE, 1, true)
		assert_eq(r.size(), 1, "apertura %d" % i)
		var inst: Dictionary = (r[0].instance as Dictionary).duplicate(true)
		inst.erase("uid")
		out.append([r[0].def_id, r[0].rarity, inst, r[0].stop_frac, r[0].reel])
	return {"results": out, "draw_n": crates.state.draw_n.duplicate(true), "draw_seed": str(crates.state.draw_seed),
		"pity": crates.state.pity.duplicate(true), "pushed": tp.pushed_total_s()}


func test_stesse_aperture_con_e_senza_sabbia() -> void:
	var a := _setup(9001, false)
	Game.stop_game(false)
	var b := _setup(9001, true)
	assert_gt(float(b.pushed), 0.0, "la Sabbia e' stata davvero spesa durante la sequenza")
	assert_eq(a.results, b.results, "stessi oggetti, stesse condizioni, stesso rullo")
	assert_eq(a.draw_n, b.draw_n, "stesso contatore draw_n")
	assert_eq(a.draw_seed, b.draw_seed, "stesso seme di estrazione")
	assert_eq(a.pity, b.pity, "stessa pity")
	assert_eq(int(a.draw_n[CRATE]), N)


func test_la_sabbia_non_cambia_seme_ne_contatori_delle_casse() -> void:
	assert_true(Game.new_game(1, "normal", 4242))
	var crates := Game.system("crates") as CrateSystem
	var tp := Game.system("time_push") as TimePushSystem
	var before: Dictionary = {"n": crates.state.draw_n.duplicate(true), "seed": str(crates.state.draw_seed)}
	(Game.system("unlock") as UnlockSystem).grant(str(DataRegistry.constants.time_push.unlock_token))
	tp.state["reserve_s"] = 100.0
	GameState.data.unlocks.append("skill:woodcutting")
	var sk := Game.system("skills") as SkillSystem
	for a in DataRegistry.actions_for_skill("woodcutting"):
		if int(a.get("level_req", 1)) <= 1 and sk.start(str(a.id)):
			break
	Game.debug_push(50)
	tp.drain(1000)
	assert_eq(crates.state.draw_n, before.n)
	assert_eq(str(crates.state.draw_seed), before.seed)
