extends GutTest
## AudioManager (docs/21): mappatura evento->suono, limite voci, moderazione, volumi da Settings, file presenti.

var _old_path: String
var _old_values: Dictionary


func before_each() -> void:
	_old_path = Settings.path
	_old_values = Settings._values.duplicate(true)
	Settings.path = "user://test_audio_settings_%d.cfg" % Time.get_ticks_usec()
	Settings.set_value("reduce_motion", false)     # altri test nello stesso processo possono lasciarla accesa: qui parte spenta
	AudioManager.stop_all_sfx()
	AudioManager._last_ms.clear()
	AudioManager._time_override_ms = 100000
	AudioManager.played_log.clear()


func after_each() -> void:
	AudioManager.stop_all_sfx()
	AudioManager._time_override_ms = -1
	AudioManager._event_until_ms = -1
	DirAccess.remove_absolute(Settings.path)
	Settings.path = _old_path
	Settings._values = _old_values
	Settings.apply_all()
	AudioManager.apply_volumes()


func test_file_audio_esistono_e_non_vuoti() -> void:
	assert_eq(AudioManager.sfx_ids.size(), AudioManager.BASE_SFX_IDS.size() + 17 * 3)
	for id in AudioManager.sfx_ids:
		var p := AudioManager.sfx_path(id)
		assert_ne(p, "", "manca l'effetto " + id)
		assert_gt(FileAccess.get_file_as_bytes(p).size(), 500, id)
		assert_not_null(load(p), id)
	for id in AudioManager.all_tracks():
		var p := AudioManager.music_path(id)
		assert_ne(p, "", "manca la traccia " + id)
		assert_gt(FileAccess.get_file_as_bytes(p).size(), 10000, id)
		assert_not_null(load(p), id)


func test_mappatura_evento_suono() -> void:
	assert_eq(AudioManager.sound_for("level_up"), "level_up")
	assert_eq(AudioManager.sound_for("crate_opened"), "crate_open")
	assert_eq(AudioManager.sound_for("quest_completed"), "quest_done")
	assert_eq(AudioManager.sound_for("monster_killed"), "kill")
	assert_eq(AudioManager.sound_for("player_died"), "death")
	assert_eq(AudioManager.sound_for("item_sold"), "sell")
	assert_eq(AudioManager.sound_for("action_batch_completed"), "", "l'offline non suona")
	assert_eq(AudioManager.sound_for("important_event", "quest"), "", "la missione ha già il suo suono")
	assert_eq(AudioManager.sound_for("important_event", "shop_upgrade"), "ui_notify")
	assert_eq(AudioManager.sound_for("important_event", "rite"), "prestige")
	assert_eq(AudioManager.sound_for("important_event", "era"), "era")
	assert_eq(AudioManager.sound_for("important_event", "raid"), "victory")
	assert_eq(AudioManager.sound_for("important_event", "trial_fail"), "defeat")
	assert_eq(AudioManager.sound_for("important_event", "crate"), "", "la cassa ha già i suoi suoni")
	assert_eq(AudioManager.sound_for("offline_progress"), "ui_welcome")
	assert_eq(AudioManager.sound_for("segnale_inesistente"), "")
	assert_eq(AudioManager.notice_sound("error"), "ui_error")
	assert_eq(AudioManager.notice_sound("info"), "")
	for ev in AudioManager.EVENT_MAP:
		var id: String = AudioManager.EVENT_MAP[ev].sfx
		assert_true(id == "skill_step" or AudioManager.sfx_ids.has(id), "suono sconosciuto per " + ev)


func test_eventbus_fa_suonare() -> void:
	EventBus.level_up.emit("mining", 5)
	assert_eq(AudioManager.played_log.back(), "level_up")
	EventBus.player_died.emit("x")
	assert_eq(AudioManager.played_log.back(), "death")
	AudioManager.played_log.clear()
	EventBus.action_batch_completed.emit("a", 1000, [])
	assert_eq(AudioManager.played_log.size(), 0)


func test_moderazione_azioni() -> void:
	assert_true(AudioManager.trigger("action_completed", "wc_pine"))
	assert_false(AudioManager.trigger("action_completed", "wc_pine"), "troppo vicina")
	AudioManager._time_override_ms += 1000
	assert_true(AudioManager.trigger("action_completed", "wc_pine"))
	assert_true(AudioManager.played_log.back().begins_with("sk_woodcutting_"))


func test_limite_voci() -> void:
	assert_true(AudioManager.play("sell"))
	assert_true(AudioManager.play("sell"))
	assert_false(AudioManager.play("sell"), "max 2 voci per lo stesso suono")
	for id in AudioManager.sfx_ids:
		AudioManager.play(id)
	assert_lte(AudioManager.active_voices(), AudioManager.MAX_VOICES)
	assert_false(AudioManager.play("non_esiste"))


func test_rullo_collegato() -> void:
	var reel := CrateReel.new()
	add_child_autofree(reel)
	AudioManager.hook_reel(reel)
	reel.tick_sound.emit(1.0, 1.2)
	assert_eq(AudioManager.played_log.back(), "reel_tick")
	reel.reveal_sound.emit("relic")
	assert_eq(AudioManager.played_log.back(), "reveal_relic")
	assert_eq(AudioManager.reveal_sound_for("sconosciuta"), "reveal_rare")


func test_volumi_da_settings() -> void:
	Settings.set_value("volume_music", 0.5)
	Settings.set_value("volume_sfx", 0.25)
	Settings.set_value("volume_master", 0.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.5), 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.25), 0.01)
	assert_lt(AudioServer.get_bus_volume_db(0), -60.0)
	for b in AudioManager.BUSES:
		assert_gte(AudioServer.get_bus_index(b), 0, b)


func test_contesti_musica() -> void:
	var z := {"type": "combat", "mode": "zone", "zone": "millbrook"}
	assert_eq(AudioManager.context_for_screen("combat", z), "combat_early")
	z.zone = "gallmire"
	assert_eq(AudioManager.context_for_screen("combat", z), "combat_mid")
	z.zone = "archive"
	assert_eq(AudioManager.context_for_screen("hero", z), "combat_late")
	assert_eq(AudioManager.context_for_screen("combat", {}), "combat_early")
	assert_eq(AudioManager.context_for_screen("hero", {}), "menu")
	assert_eq(AudioManager.context_for_screen("dungeon", {}), "dungeon")
	assert_eq(AudioManager.context_for_screen("dungeon", {"type": "combat", "mode": "dungeon"}), "dungeon")
	assert_eq(AudioManager.context_for_screen("dungeon", {"type": "combat", "mode": "raid"}), "boss")
	assert_eq(AudioManager.context_for_screen("dungeon", {"type": "combat", "mode": "wboss"}), "boss")
	assert_eq(AudioManager.context_for_screen("dungeon", {"type": "combat", "mode": "rift"}), "rift")
	assert_eq(AudioManager.context_for_screen("skill:mining"), "skilling")
	assert_eq(AudioManager.context_for_screen("estate"), "estate")
	assert_eq(AudioManager.context_for_screen("prestige"), "prestige")
	assert_eq(AudioManager.context_for_screen("vault_hall"), "vault")
	assert_eq(AudioManager.context_for_screen("bank"), "menu")
	AudioManager.context = ""
	assert_true(AudioManager.set_context("combat_mid"))
	assert_false(AudioManager.set_context("combat_mid"))
	assert_false(AudioManager.set_context("inesistente"))
	assert_true(AudioManager.CONTEXT_TRACKS["combat_mid"].has(AudioManager.current_track))
	AudioManager.set_context("menu")


func test_ogni_contesto_ha_varianti_e_file() -> void:
	for ctx in AudioManager.CONTEXT_TRACKS:
		var list: Array = AudioManager.CONTEXT_TRACKS[ctx]
		assert_gte(list.size(), 2, "serve più di una variante per " + ctx)
		for t in list:
			assert_ne(AudioManager.music_path(t), "", "manca " + t)
			assert_true(str(t).begins_with("mus_" + ctx + "_"), t)
	for needed in ["menu", "skilling", "combat_early", "combat_mid", "combat_late", "dungeon", "boss", "rift", "estate", "prestige", "vault", "event"]:
		assert_true(AudioManager.CONTEXT_TRACKS.has(needed), needed)


func test_rotazione_varianti() -> void:
	AudioManager.context = ""
	AudioManager.set_context("skilling")
	var first := AudioManager.current_track
	var seen := {first: true}
	for i in 5:
		AudioManager._track_age_s = AudioManager.ROTATE_S
		assert_true(AudioManager.rotate_if_due(0.0))
		assert_true(AudioManager.CONTEXT_TRACKS["skilling"].has(AudioManager.current_track))
		seen[AudioManager.current_track] = true
	assert_gte(seen.size(), 3, "le tre varianti ruotano")
	assert_false(AudioManager.rotate_if_due(0.5), "troppo presto")
	AudioManager.set_context("menu")


func test_loop_attivo_e_cache_pigra() -> void:
	AudioManager.context = ""
	AudioManager.set_context("vault")
	var st: AudioStream = AudioManager._load_stream(AudioManager.music_path(AudioManager.current_track))
	assert_not_null(st)
	if st is AudioStreamOggVorbis:
		assert_true(st.loop)
	var before := AudioManager.cached_files()
	AudioManager._load_stream(AudioManager.music_path(AudioManager.current_track))
	assert_eq(AudioManager.cached_files(), before, "il secondo caricamento usa la cache")
	AudioManager.set_context("menu")


func test_perf_caricamento_a_freddo_trascurabile() -> void:
	if PerfGate.skip_if_deferred(self):
		return
	var f0 := PerfGate.wall_factor()
	var t0 := Time.get_ticks_msec()
	for id in AudioManager.CONTEXT_TRACKS["event"]:
		assert_not_null(load(AudioManager.music_path(id)))
	for id in ["level_up", "reveal_relic", "sk_mining_1", "ui_click"]:
		assert_not_null(load(AudioManager.sfx_path(id)))
	PerfGate.assert_time(self, "caricare 2 tracce e 4 effetti (quasi istantaneo)", float(Time.get_ticks_msec() - t0), 1500.0, maxf(f0, PerfGate.wall_factor()))


func test_peso_totale_audio() -> void:
	var total := 0
	for sub in ["sfx", "music"]:
		var d := DirAccess.open("res://assets/audio/" + sub)
		assert_not_null(d)
		for f in d.get_files():
			if f.ends_with(".ogg") or f.ends_with(".wav"):
				total += FileAccess.get_file_as_bytes("res://assets/audio/%s/%s" % [sub, f]).size()
	assert_lt(total, 12 * 1024 * 1024, "peso totale ≤ 12 MB")


func test_mansioni_distinte_con_tre_varianti() -> void:
	var seen := {}
	for s in AudioManager.SKILL_IDS:
		for v in 3:
			var p := AudioManager.sfx_path("sk_%s_%d" % [s, v + 1])
			assert_ne(p, "", "%s variante %d" % [s, v + 1])
			var h := FileAccess.get_file_as_bytes(p).hex_encode().md5_text()
			assert_false(seen.has(h), "suono duplicato " + p)
			seen[h] = true
	assert_eq(AudioManager.SKILL_IDS.size(), 17)


func test_suono_mansione_non_si_ripete_di_fila() -> void:
	var last := ""
	for i in 30:
		var id := AudioManager.skill_sound("mining")
		assert_true(id.begins_with("sk_mining_"))
		assert_ne(id, last)
		last = id
	assert_eq(AudioManager.skill_sound("combat"), "")
	assert_eq(AudioManager.skill_of("wc_pine"), "woodcutting")


func test_gruppo_mansioni_limitato() -> void:
	assert_true(AudioManager.play("sk_mining_1"))
	assert_true(AudioManager.play("sk_fishing_2"))
	assert_false(AudioManager.play("sk_cooking_3"), "le mansioni condividono 2 voci")
	assert_true(AudioManager.play("coin"))


func test_ducking_con_stinger() -> void:
	var n := AudioManager.ducks
	assert_true(AudioManager.play("reveal_relic", "Reel"))
	assert_eq(AudioManager.ducks, n + 1)
	assert_true(AudioManager.play("coin"))
	assert_eq(AudioManager.ducks, n + 1, "le monete non abbassano la musica")
	assert_lte(AudioManager.DUCK_DB, -6.0)


func test_silenzio_durante_offline_aggregato() -> void:
	Game.sim.offline_running = true
	assert_false(AudioManager.trigger("level_up"))
	assert_false(AudioManager.play("coin"))
	Game.sim.offline_running = false
	assert_true(AudioManager.trigger("level_up"))


func test_riduci_animazioni_attenua_e_dilata() -> void:
	Settings.set_value("reduce_motion", true)
	assert_true(AudioManager.trigger("monster_killed"))
	AudioManager._time_override_ms += 500
	assert_false(AudioManager.trigger("monster_killed"), "con riduci animazioni l'intervallo raddoppia")
	AudioManager._time_override_ms += 400
	assert_true(AudioManager.trigger("monster_killed"))


func test_musica_evento_temporanea() -> void:
	assert_false(AudioManager.event_music_active())
	EventBus.market_event.emit("fiera")
	assert_true(AudioManager.event_music_active())
	AudioManager._time_override_ms += int(AudioManager.EVENT_MUSIC_S * 1000.0) + 10
	assert_false(AudioManager.event_music_active())


func test_clic_dei_pulsanti() -> void:
	var b := Button.new()
	add_child_autofree(b)
	b.pressed.emit()
	assert_eq(AudioManager.played_log.back(), "ui_click")


func test_riproduzione_con_tono_del_rullo() -> void:
	assert_true(AudioManager.play("reel_tick", "Reel", 0.0, 1.2))
	var p: AudioStreamPlayer = AudioManager._voices.back().player
	assert_almost_eq(p.pitch_scale, 1.2, 0.001)


# ---------------------------------------------------------------- matrice evento -> suono (AUDIO-3)
func test_combat_hit_suoni_per_tipo() -> void:
	assert_eq(AudioManager.sound_for("combat_hit", "hit"), "hit")
	assert_eq(AudioManager.sound_for("combat_hit", "crit"), "hit_crit")
	assert_eq(AudioManager.sound_for("combat_hit", "hurt"), "hurt")
	assert_eq(AudioManager.sound_for("combat_hit", "dodge"), "dodge")
	assert_eq(AudioManager.sound_for("combat_hit", "boh"), "")
	EventBus.combat_hit.emit("crit")
	assert_eq(AudioManager.played_log.back(), "hit_crit")
	EventBus.combat_hit.emit("dodge")
	assert_eq(AudioManager.played_log.back(), "dodge", "tipi diversi non si sopprimono a vicenda")


func test_combat_hit_antispam() -> void:
	assert_true(AudioManager.trigger("combat_hit", "hit"))
	assert_false(AudioManager.trigger("combat_hit", "hit"), "stesso tipo troppo vicino")
	AudioManager._time_override_ms += 300
	AudioManager.stop_all_sfx()
	assert_true(AudioManager.trigger("combat_hit", "hit"))
	Settings.set_value("reduce_motion", true)
	AudioManager._time_override_ms += 300
	assert_false(AudioManager.trigger("combat_hit", "hit"), "con riduci animazioni l'intervallo raddoppia")
	AudioManager._time_override_ms += 300
	AudioManager.stop_all_sfx()
	assert_true(AudioManager.trigger("combat_hit", "hit"))


func test_nuovi_eventi_hanno_suono() -> void:
	var cases := {"crate_found": "crate_found", "item_bought": "buy", "rare_drop": "drop_rare", "monster_killed": "kill"}
	for ev in cases:
		assert_eq(AudioManager.sound_for(ev), cases[ev], ev)
		assert_true(AudioManager.sfx_ids.has(cases[ev]))
	assert_eq(AudioManager.sound_for("important_event", "coop"), "coop_link")
	EventBus.item_bought.emit("wood_log", 1)
	assert_eq(AudioManager.played_log.back(), "buy")
	EventBus.crate_found.emit("crate_basic", "test")
	assert_eq(AudioManager.played_log.back(), "crate_found")


func test_rare_drop_riconosce_la_rarita() -> void:
	var rare_id := ""
	var common_id := ""
	var all: Dictionary = DataRegistry.all_items()
	for id in all:
		var r := str((all[id] as Dictionary).get("rarity", ""))
		if rare_id.is_empty() and r == "epic":
			rare_id = str(id)
		if common_id.is_empty() and r == "":
			common_id = str(id)
	assert_ne(rare_id, "")
	assert_false(AudioManager.has_rare_drop([{"id": common_id, "qty": 1}]))
	assert_true(AudioManager.has_rare_drop([{"id": common_id, "qty": 1}, {"id": rare_id, "qty": 1}]))
	EventBus.monster_killed.emit("m", [{"id": rare_id, "qty": 1}])
	assert_true(AudioManager.played_log.has("drop_rare"))


func test_ogni_segnale_importante_ha_un_suono_o_un_motivo() -> void:
	## Matrice: segnali di gioco "da sentire" -> voce di EVENT_MAP (o già coperti da un altro suono).
	var covered := ["level_up", "crate_opened", "crate_found", "quest_completed", "action_completed", "monster_killed",
		"combat_hit", "player_died", "item_sold", "item_bought", "order_completed", "expedition_finished", "faction_rank_up",
		"achievement_unlocked", "star_gained", "pet_found", "unlocked", "offline_progress", "important_event"]
	for ev in covered:
		assert_true(AudioManager.EVENT_MAP.has(ev), "senza suono: " + ev)
	for reason in ["rite", "refounding", "era", "raid", "world_boss", "trial", "trial_fail", "coop"]:
		assert_ne(AudioManager.sound_for("important_event", reason), "ui_notify", reason)
