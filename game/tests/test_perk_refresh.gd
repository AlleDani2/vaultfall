extends GutTest
## Il pannello dei talenti di mansione si aggiorna da solo al level-up (prima serviva chiudere e riaprire la scheda).

const SkillScreenScene := preload("res://src/ui/screens/SkillScreen.gd")


func after_each() -> void:
	Game.stop_game(false)


func test_le_scelte_si_sbloccano_al_level_up_a_scheda_aperta() -> void:
	assert_true(Game.new_game(1, "normal", 7))
	var sk := Game.system("skills") as SkillSystem
	var screen := SkillScreenScene.new() as Control
	add_child_autofree(screen)
	screen.open({"skill": "mining"})
	await get_tree().process_frame
	var pp := screen.get("_perks") as SkillPerkPanel
	pp.set_open(true)
	var sig0 := str(pp.call("_perk_signature"))
	sk.state["mining"]["level"] = 20
	screen.call("refresh")
	await get_tree().process_frame
	assert_ne(str(pp.get("_perk_sig")), sig0, "il pannello si è ricostruito dopo il salto di livello")
	assert_gt(pp.choosable_buttons(), 0, "almeno una scelta del livello 20 è attiva senza riaprire la scheda")
