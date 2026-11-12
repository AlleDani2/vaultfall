extends Node
## AudioManager (autoload) — musica e effetti (docs/21 §4). SOLO presentazione: ascolta EventBus, non decide nulla
## e non usa mai `Rng` (la variazione di tono ha un generatore proprio, fuori dalla simulazione).
## - Bus: Master, Music, SFX, UI, Reel (nomi e volumi da `Settings`: volume_master/music/sfx/ui/reel).
## - Voci: al massimo MAX_VOICES insieme, MAX_PER_SOUND per lo stesso suono e MAX_PER_GROUP per gruppo (mansioni).
## - Moderazione: gli eventi frequenti (azioni, colpi, vendite) hanno un intervallo minimo; con "riduci animazioni"
##   l'intervallo raddoppia, il volume scende e i passaggi musicali sono brevi.
## - Musica: 12 contesti (CONTEXT_TRACKS, stesso elenco di assets_plan/audio_manifest.csv), 2-3 varianti per
##   contesto che ruotano a ogni ingresso e ogni ROTATE_S secondi; crossfade di 2 s.
## - Ducking: la musica scende durante stinger e rivelazioni (effetto Amplify sul bus Music) e risale piano.
## - Silenzio: finestra ridotta a icona (opzione `mute_in_background`) e simulazione offline aggregata
##   (`Simulation.offline_running`): nessun suono finché il tempo in blocco viene consumato.
## - Rullo delle Casse: `hook_reel(reel)` collega tick_sound/reveal_sound (bus Reel).
## - Caricamento pigro: ogni file si carica alla prima riproduzione e resta in cache (gli OGG restano compressi).
## File generati da `tools/make_audio.py` in res://assets/audio/{sfx,music}/<id>.ogg (o .wav).

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const MAX_VOICES := 12
const MAX_PER_SOUND := 2
const MAX_PER_GROUP := 2
const CROSSFADE_S := 2.0
const CROSSFADE_REDUCED_S := 0.5
const ROTATE_S := 150.0
const SILENT_DB := -60.0
const MUSIC_DB := -4.0
const DUCK_DB := -9.0
const DUCK_ATTACK_S := 0.12
const DUCK_RELEASE_S := 0.9
const POLL_S := 0.5
const PITCH_VARIATION := 0.05
const EVENT_MUSIC_S := 120.0
const REDUCED_DB := -4.0
const SKILL_IDS: PackedStringArray = [
	"woodcutting", "mining", "fishing", "foraging", "trapping", "smithing", "woodworking", "tailoring", "cooking",
	"alchemy", "jewelcrafting", "runecarving", "keysmithing", "thievery", "farming", "hero", "bounty"]
const BASE_SFX_IDS: PackedStringArray = [
	"ui_click", "ui_confirm", "ui_error", "ui_notify", "ui_achievement", "ui_pet", "ui_star", "ui_welcome", "ui_unlock",
	"action_done", "level_up", "quest_done", "crate_open", "reel_tick", "reveal_rare", "reveal_epic", "reveal_legendary",
	"reveal_mythic", "reveal_relic", "hit", "victory", "defeat", "death", "prestige", "era", "coin", "sell",
	"hit_crit", "dodge", "hurt", "kill", "buy", "crate_found", "drop_rare", "coop_link"]
const BUSES: PackedStringArray = ["Master", "Music", "SFX", "UI", "Reel"]
## Massimo di voci simultanee per suoni che per natura si sovrappongono (tick del rullo).
const PER_SOUND_LIMIT := {"reel_tick": 3, "ui_click": 3, "hit": 1, "hit_crit": 1, "hurt": 1, "dodge": 1, "coin": 1, "buy": 1}
## Suoni con variazione di tono casuale ±5% (azioni ripetute).
const VARIED := ["hit", "hit_crit", "hurt", "dodge", "kill", "coin", "sell", "buy", "ui_click", "drop_rare"]

## Contesto musicale -> varianti (ordine = manifest). Tutte le tracce hanno 29-48 s e la stessa loudness stimata.
const CONTEXT_TRACKS := {
	"menu": ["mus_menu_1", "mus_menu_2", "mus_menu_3"],
	"skilling": ["mus_skilling_1", "mus_skilling_2", "mus_skilling_3"],
	"combat_early": ["mus_combat_early_1", "mus_combat_early_2"],
	"combat_mid": ["mus_combat_mid_1", "mus_combat_mid_2"],
	"combat_late": ["mus_combat_late_1", "mus_combat_late_2"],
	"dungeon": ["mus_dungeon_1", "mus_dungeon_2"],
	"boss": ["mus_boss_1", "mus_boss_2"],
	"rift": ["mus_rift_1", "mus_rift_2"],
	"estate": ["mus_estate_1", "mus_estate_2"],
	"prestige": ["mus_prestige_1", "mus_prestige_2"],
	"vault": ["mus_vault_1", "mus_vault_2"],
	"event": ["mus_event_1", "mus_event_2"],
}
## Zone 1-4 / 5-7 / 8-10 (tier della zona nei dati) -> contesto di combattimento.
const TIER_LATE_FROM := 8
const TIER_MID_FROM := 5
## Schermate -> contesto (le altre usano "menu"). Il combattimento dipende dall'attività in corso.
const SCREEN_CONTEXT := {
	"estate": "estate", "prestige": "prestige", "vault_hall": "vault", "album": "vault", "wardrobe": "vault",
	"vault_workshop": "vault", "skills": "skilling",
}
## Stinger -> secondi di abbassamento della musica (ducking).
const DUCK_HOLD := {
	"level_up": 1.2, "quest_done": 1.2, "victory": 2.0, "defeat": 2.2, "death": 1.2, "prestige": 3.0, "era": 3.2,
	"reveal_rare": 0.5, "reveal_epic": 0.8, "reveal_legendary": 1.2, "reveal_mythic": 1.6, "reveal_relic": 2.6,
	"drop_rare": 0.5, "ui_achievement": 1.2, "ui_star": 1.0, "ui_welcome": 1.4, "ui_pet": 0.8, "crate_open": 0.6,
}

## Segnale EventBus -> suono. `sfx`: id (o "skill_step" = suono della mansione, una variante a rotazione); `db`: volume;
## `bus`; `gap_ms`: intervallo minimo tra due riproduzioni dello stesso segnale (moderazione); `calm`: true = si attenua
## con "riduci animazioni".
const EVENT_MAP := {
	"level_up": {"sfx": "level_up", "bus": "SFX", "db": 0.0, "gap_ms": 400},
	"crate_opened": {"sfx": "crate_open", "bus": "Reel", "db": 0.0, "gap_ms": 300},
	"quest_completed": {"sfx": "quest_done", "bus": "SFX", "db": 0.0, "gap_ms": 800},
	"action_completed": {"sfx": "skill_step", "bus": "SFX", "db": -7.0, "gap_ms": 900, "calm": true},
	"monster_killed": {"sfx": "kill", "bus": "SFX", "db": -3.0, "gap_ms": 350, "calm": true},
	"combat_hit": {"sfx": "hit", "bus": "SFX", "db": -5.0, "gap_ms": 220, "calm": true},     # il suono dipende dal tipo (COMBAT_HIT_MAP)
	"rare_drop": {"sfx": "drop_rare", "bus": "SFX", "db": -4.0, "gap_ms": 1200},
	"crate_found": {"sfx": "crate_found", "bus": "SFX", "db": -4.0, "gap_ms": 1000},
	"item_bought": {"sfx": "buy", "bus": "SFX", "db": -4.0, "gap_ms": 250, "calm": true},
	"player_died": {"sfx": "death", "bus": "SFX", "db": 0.0, "gap_ms": 1500},
	"item_sold": {"sfx": "sell", "bus": "SFX", "db": -4.0, "gap_ms": 250, "calm": true},
	"order_completed": {"sfx": "coin", "bus": "SFX", "db": -3.0, "gap_ms": 500},
	"expedition_finished": {"sfx": "action_done", "bus": "SFX", "db": -3.0, "gap_ms": 800},
	"faction_rank_up": {"sfx": "quest_done", "bus": "SFX", "db": -3.0, "gap_ms": 800},
	"achievement_unlocked": {"sfx": "ui_achievement", "bus": "UI", "db": 0.0, "gap_ms": 800},
	"star_gained": {"sfx": "ui_star", "bus": "UI", "db": 0.0, "gap_ms": 800},
	"pet_found": {"sfx": "ui_pet", "bus": "UI", "db": 0.0, "gap_ms": 800},
	"unlocked": {"sfx": "ui_unlock", "bus": "UI", "db": -3.0, "gap_ms": 1000},
	"offline_progress": {"sfx": "ui_welcome", "bus": "UI", "db": 0.0, "gap_ms": 1000},   # jingle "Bentornato"
	"important_event": {"sfx": "ui_notify", "bus": "UI", "db": -6.0, "gap_ms": 1500},
}
## Tipo di colpo (`combat_hit`) -> suono e volume relativo (dB). Il critico si sente di più, il colpo subito è sordo e basso.
const COMBAT_HIT_MAP := {"hit": ["hit", 0.0], "crit": ["hit_crit", 4.0], "hurt": ["hurt", -1.0], "dodge": ["dodge", -1.0]}
## Rarità degli oggetti caduti che fanno scattare `rare_drop` (la rivelazione delle Casse ha i suoi suoni).
const RARE_DROP_RARITIES := ["rare", "epic", "legendary", "mythic", "relic"]
## Motivo di `important_event` -> suono ("" = già coperto da un altro segnale). Gli altri motivi usano ui_notify.
const IMPORTANT_MAP := {
	"quest": "", "star": "", "achievement": "", "pet": "", "crate": "",
	"raid": "victory", "world_boss": "victory", "trial": "victory", "trial_fail": "defeat",
	"rite": "prestige", "refounding": "prestige", "era": "era", "warden": "era",
	"constellation": "ui_unlock", "secret_spot": "ui_unlock", "secret_run": "ui_unlock", "coop": "coop_link",
}
## Notifiche per tipo: solo errori, successi e avvisi suonano (info/level/loot hanno già un loro suono).
const NOTICE_MAP := {"error": "ui_error", "success": "ui_confirm", "warning": "ui_notify"}
## Eventi che NON devono suonare (aggregati dell'offline: decine di migliaia di emissioni).
const SILENT_EVENTS := ["action_batch_completed", "monsters_killed_batch"]

var sfx_ids: PackedStringArray = []
var context: String = ""
var current_track: String = ""
var ducks: int = 0                      # quante volte è scattato il ducking (test/debug)
var _voices: Array = []                 # [{player, id, group}]
var _free: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _last_ms: Dictionary = {}           # chiave di moderazione -> istante dell'ultima riproduzione
var _skill_last: Dictionary = {}        # mansione -> ultima variante (non si ripete mai due volte di fila)
var _next_variant: Dictionary = {}      # contesto -> prossima variante
var _skill_of: Dictionary = {}          # azione -> mansione (cache)
var _rng := RandomNumberGenerator.new()
var _music: Array[AudioStreamPlayer] = []
var _music_cur: int = 0
var _tween: Tween
var _duck_tween: Tween
var _duck_fx: AudioEffectAmplify
var _track_age_s: float = 0.0
var _event_until_ms: int = -1
var _time_override_ms: int = -1         # solo per i test
var _minimized: bool = false
var played_log: Array = []              # ultimi suoni avviati (id), per i test e il debug
var enabled: bool = true


func _init() -> void:
	sfx_ids = BASE_SFX_IDS.duplicate()
	for s in SKILL_IDS:
		for v in 3:
			sfx_ids.append("sk_%s_%d" % [s, v + 1])


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	apply_volumes()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_music.append(p)
	var timer := Timer.new()
	timer.wait_time = POLL_S
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	_connect_events()
	get_tree().node_added.connect(_on_node_added)
	set_context("menu")


# ---------------------------------------------------------------- bus e volumi
func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var mb := AudioServer.get_bus_index("Music")
	if mb >= 0:
		_duck_fx = null
		for i in AudioServer.get_bus_effect_count(mb):
			if AudioServer.get_bus_effect(mb, i) is AudioEffectAmplify:
				_duck_fx = AudioServer.get_bus_effect(mb, i)
		if _duck_fx == null:
			_duck_fx = AudioEffectAmplify.new()
			AudioServer.add_bus_effect(mb, _duck_fx)


## Applica ai bus i volumi di Settings (Settings lo fa già per i bus esistenti; qui dopo la creazione).
func apply_volumes() -> void:
	for key in Settings.VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(Settings.VOLUME_BUSES[key])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(0.0001, float(Settings.get_value(key)))))
	_apply_mute()


func _apply_mute() -> void:
	var mute := _minimized and bool(Settings.get_value("mute_in_background"))
	AudioServer.set_bus_mute(0, mute)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if Settings.VOLUME_BUSES.has(key) or key == "mute_in_background":
		apply_volumes()


func reduced() -> bool:
	return bool(Settings.get_value("reduce_motion"))


## Vero mentre l'offline aggregato sta consumando il tempo in blocco: niente suoni.
func offline_silent() -> bool:
	return "sim" in Game and bool(Game.sim.offline_running)


# ---------------------------------------------------------------- eventi
func _connect_events() -> void:
	var eb := EventBus
	eb.level_up.connect(func(_s: String, _l: int) -> void: trigger("level_up"))
	eb.crate_opened.connect(func(_r: Dictionary) -> void: trigger("crate_opened"))
	eb.quest_completed.connect(func(_q: String) -> void: trigger("quest_completed"))
	eb.action_completed.connect(func(a: String, _o: Array) -> void: trigger("action_completed", a))
	eb.monster_killed.connect(_on_monster_killed)
	eb.combat_hit.connect(func(kind: String) -> void: trigger("combat_hit", kind))
	eb.crate_found.connect(func(_c: String, _s: String) -> void: trigger("crate_found"))
	eb.item_bought.connect(func(_d: String, _q: int) -> void: trigger("item_bought"))
	eb.player_died.connect(func(_c: String) -> void: trigger("player_died"))
	eb.item_sold.connect(func(_d: String, _q: int, _g: int) -> void: trigger("item_sold"))
	eb.order_completed.connect(func(_o: String) -> void: trigger("order_completed"))
	eb.expedition_finished.connect(func(_i: String, _r: Dictionary) -> void: trigger("expedition_finished"))
	eb.faction_rank_up.connect(func(_f: String, _r: String) -> void: trigger("faction_rank_up"))
	eb.achievement_unlocked.connect(func(_i: String) -> void: trigger("achievement_unlocked"))
	eb.star_gained.connect(func(_s: String) -> void: trigger("star_gained"))
	eb.pet_found.connect(func(_p: String) -> void: trigger("pet_found"))
	eb.unlocked.connect(func(_t: String) -> void: trigger("unlocked"))
	eb.offline_progress.connect(func(_s: float, _r: Dictionary) -> void: trigger("offline_progress"))
	eb.important_event.connect(func(reason: String) -> void: trigger("important_event", reason))
	eb.market_event.connect(func(_e: String) -> void: start_event_music())
	eb.notice.connect(func(kind: String, _t: String, _d: Dictionary) -> void: notice(kind))
	eb.settings_changed.connect(_on_settings_changed)
	eb.game_stopped.connect(func() -> void: set_context("menu"))


func _on_monster_killed(_m: String, drops: Array) -> void:
	trigger("monster_killed")
	if has_rare_drop(drops):
		trigger("rare_drop")


## Vero se tra gli oggetti caduti ([{id, qty}]) ce n'è uno di rarità Rara o superiore.
func has_rare_drop(drops: Array) -> bool:
	for d in drops:
		if d is Dictionary and RARE_DROP_RARITIES.has(str(DataRegistry.get_def("items", str(d.get("id", ""))).get("rarity", ""))):
			return true
	return false


## Clic dell'interfaccia: ogni pulsante che entra nell'albero suona ui_click (bus UI) quando viene premuto.
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_on_button_pressed):
		n.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	if _gap_ok("ui_click", 40):
		play("ui_click", "UI", -6.0)


## Suono associato a un segnale ("" se non suona). Pura: usata anche dai test.
## Per `important_event` l'argomento è il motivo; per `action_completed` ritorna "skill_step" (risolto da `trigger`).
func sound_for(event: String, arg: String = "") -> String:
	if SILENT_EVENTS.has(event) or not EVENT_MAP.has(event):
		return ""
	if event == "important_event":
		return str(IMPORTANT_MAP[arg]) if IMPORTANT_MAP.has(arg) else str(EVENT_MAP[event].sfx)
	if event == "combat_hit":
		return str(COMBAT_HIT_MAP[arg][0]) if COMBAT_HIT_MAP.has(arg) else ""
	return str(EVENT_MAP[event].sfx)


func notice_sound(kind: String) -> String:
	return str(NOTICE_MAP.get(kind, ""))


## Mansione di un'azione (dai dati, con cache). "" se sconosciuta.
func skill_of(action_id: String) -> String:
	if not _skill_of.has(action_id):
		_skill_of[action_id] = str(DataRegistry.get_def("actions", action_id).get("skill", ""))
	return str(_skill_of[action_id])


## Suono della mansione: una delle 3 varianti, mai la stessa due volte di fila. "" se la mansione non ha suoni.
func skill_sound(skill: String) -> String:
	if not SKILL_IDS.has(skill):
		return ""
	var last: int = int(_skill_last.get(skill, _rng.randi() % 3))
	var v := (last + 1 + _rng.randi() % 2) % 3
	_skill_last[skill] = v
	return "sk_%s_%d" % [skill, v + 1]


## Riproduce il suono dell'evento, con moderazione. Ritorna true se è partito.
func trigger(event: String, arg: String = "") -> bool:
	var id := sound_for(event, arg)
	if id.is_empty() or offline_silent():
		return false
	var e: Dictionary = EVENT_MAP[event]
	var calm: bool = bool(e.get("calm", false)) and reduced()
	if not _gap_ok(event + (":" + arg if event == "combat_hit" else ""), int(e.gap_ms) * (2 if calm else 1)):
		return false
	if id == "skill_step":
		id = skill_sound(skill_of(arg))
		if id.is_empty():
			return false
	var db := float(e.db) + (REDUCED_DB if calm else 0.0)
	if event == "combat_hit":
		db += float(COMBAT_HIT_MAP[arg][1])
	if event == "important_event" and id != str(e.sfx):
		db = 0.0 if id in ["prestige", "era", "victory", "defeat"] else -3.0
	return play(id, str(e.bus), db)


func notice(kind: String) -> bool:
	var id := notice_sound(kind)
	if id.is_empty() or not _gap_ok("notice:" + kind, 300):
		return false
	return play(id, "UI")


func _gap_ok(key: String, gap_ms: int) -> bool:
	var now := now_ms()
	if _last_ms.has(key) and now - int(_last_ms[key]) < gap_ms:
		return false
	_last_ms[key] = now
	return true


func now_ms() -> int:
	return _time_override_ms if _time_override_ms >= 0 else Time.get_ticks_msec()


# ---------------------------------------------------------------- voci
func active_voices(id: String = "") -> int:
	var n := 0
	for v in _voices:
		if id.is_empty() or v.id == id:
			n += 1
	return n


func _group_voices(group: String) -> int:
	var n := 0
	for v in _voices:
		if v.group == group:
			n += 1
	return n


## Gruppo di limitazione: tutte le varianti di tutte le mansioni condividono MAX_PER_GROUP voci.
func group_of(id: String) -> String:
	return "skill" if id.begins_with("sk_") else id


func sfx_path(id: String) -> String:
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(SFX_DIR + id + ext):
			return SFX_DIR + id + ext
	return ""


func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func cached_files() -> int:
	return _cache.size()


## Riproduce un effetto. Ritorna false se scartato (spento, offline, file mancante, limite di voci).
func play(id: String, bus: String = "SFX", volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if not enabled or not sfx_ids.has(id) or offline_silent():
		return false
	var group := group_of(id)
	if _voices.size() >= MAX_VOICES or active_voices(id) >= int(PER_SOUND_LIMIT.get(id, MAX_PER_SOUND)) \
			or (group != id and _group_voices(group) >= MAX_PER_GROUP):
		return false
	var stream := _load_stream(sfx_path(id))
	if stream == null:
		return false
	var p: AudioStreamPlayer = _free.pop_back() if not _free.is_empty() else null
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		p.finished.connect(_on_finished.bind(p))
	p.stream = stream
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.volume_db = volume_db
	var vary := 1.0
	if VARIED.has(id) or group == "skill":
		vary = 1.0 + _rng.randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	p.pitch_scale = pitch * vary
	_voices.append({"player": p, "id": id, "group": group})
	played_log.append(id)
	if played_log.size() > 64:
		played_log.pop_front()
	p.play()
	if DUCK_HOLD.has(id):
		duck(float(DUCK_HOLD[id]))
	return true


func _on_finished(p: AudioStreamPlayer) -> void:
	_release(p)


func _release(p: AudioStreamPlayer) -> void:
	for i in _voices.size():
		if _voices[i].player == p:
			_voices.remove_at(i)
			break
	if not _free.has(p):
		_free.append(p)


func stop_all_sfx() -> void:
	for v in _voices.duplicate():
		v.player.stop()
		_release(v.player)


# ---------------------------------------------------------------- ducking
## Abbassa la musica di DUCK_DB per `seconds` (stinger, rivelazioni) e la fa risalire piano.
func duck(seconds: float) -> void:
	ducks += 1
	if _duck_fx == null or not is_inside_tree():
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_duck_fx, "volume_db", DUCK_DB, 0.05 if reduced() else DUCK_ATTACK_S)
	_duck_tween.tween_interval(maxf(0.0, seconds))
	_duck_tween.tween_property(_duck_fx, "volume_db", 0.0, DUCK_RELEASE_S)


func duck_db() -> float:
	return _duck_fx.volume_db if _duck_fx != null else 0.0


# ---------------------------------------------------------------- Rullo delle Casse
func hook_reel(reel: Object) -> void:
	if reel.has_signal("tick_sound") and not reel.is_connected("tick_sound", _on_reel_tick):
		reel.connect("tick_sound", _on_reel_tick)
	if reel.has_signal("reveal_sound") and not reel.is_connected("reveal_sound", _on_reel_reveal):
		reel.connect("reveal_sound", _on_reel_reveal)


## volume 1→0,25 e tono 1,25→0,8 decrescenti con la velocità (CrateReel).
func _on_reel_tick(volume: float, pitch: float) -> void:
	play("reel_tick", "Reel", linear_to_db(clampf(volume, 0.05, 1.0)) - 6.0, clampf(pitch, 0.5, 2.0))


func _on_reel_reveal(rarity: String) -> void:
	play(reveal_sound_for(rarity), "Reel")


func reveal_sound_for(rarity: String) -> String:
	var id := "reveal_" + rarity
	return id if sfx_ids.has(id) else "reveal_rare"


# ---------------------------------------------------------------- musica
## Contesto musicale di una schermata. `activity` = GameState.data.activity (combattimento in corso).
func context_for_screen(screen_id: String, activity: Dictionary = {}) -> String:
	if screen_id == "combat" or screen_id == "hero" or screen_id == "dungeon":
		var c := combat_context(activity)
		if not c.is_empty():
			return c
		return "dungeon" if screen_id == "dungeon" else ("combat_early" if screen_id == "combat" else "menu")
	if screen_id.begins_with("skill:"):
		return "skilling"
	return str(SCREEN_CONTEXT.get(screen_id, "menu"))


## Contesto del combattimento in corso ("" se non si combatte): modalità (dungeon, boss, Breccia) o tier della zona.
func combat_context(activity: Dictionary) -> String:
	if str(activity.get("type", "")) != "combat":
		return ""
	match str(activity.get("mode", "zone")):
		"dungeon":
			return "dungeon"
		"raid", "wboss":
			return "boss"
		"rift":
			return "rift"
	var tier := int(DataRegistry.get_def("zones", str(activity.get("zone", ""))).get("tier", 1))
	if tier >= TIER_LATE_FROM:
		return "combat_late"
	return "combat_mid" if tier >= TIER_MID_FROM else "combat_early"


func music_path(track: String) -> String:
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(MUSIC_DIR + track + ext):
			return MUSIC_DIR + track + ext
	return ""


## Tutti i file musicali attesi (per i test): ogni contesto ha le sue varianti.
func all_tracks() -> PackedStringArray:
	var out := PackedStringArray()
	for c in CONTEXT_TRACKS:
		out.append_array(PackedStringArray(CONTEXT_TRACKS[c]))
	return out


## Prossima variante del contesto (a rotazione, la prima a caso). `avoid` = traccia da non ripetere.
func pick_track(ctx: String, avoid: String = "") -> String:
	var list: Array = CONTEXT_TRACKS.get(ctx, [])
	if list.is_empty():
		return ""
	var i: int = int(_next_variant.get(ctx, _rng.randi() % list.size()))
	var t := str(list[i % list.size()])
	if t == avoid and list.size() > 1:
		i += 1
		t = str(list[i % list.size()])
	_next_variant[ctx] = (i + 1) % list.size()
	return t


func start_event_music(seconds: float = EVENT_MUSIC_S) -> void:
	_event_until_ms = now_ms() + int(seconds * 1000.0)


func event_music_active() -> bool:
	return _event_until_ms >= 0 and now_ms() < _event_until_ms


## Cambia contesto musicale con crossfade. Ritorna false se il contesto è sconosciuto o già attivo.
func set_context(ctx: String) -> bool:
	if not CONTEXT_TRACKS.has(ctx) or ctx == context:
		return false
	context = ctx
	_play_track(pick_track(ctx, current_track))
	return true


func _play_track(track: String) -> void:
	current_track = track
	_track_age_s = 0.0
	if _music.is_empty() or track.is_empty():
		return
	var stream := _load_stream(music_path(track))
	if stream == null:
		return
	_loop(stream)
	var fade_s := CROSSFADE_REDUCED_S if reduced() else CROSSFADE_S
	var old := _music[_music_cur]
	_music_cur = 1 - _music_cur
	var new_p := _music[_music_cur]
	new_p.stream = stream
	new_p.volume_db = SILENT_DB
	new_p.play()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(new_p, "volume_db", MUSIC_DB, fade_s)
	if old.playing:
		_tween.tween_property(old, "volume_db", SILENT_DB, fade_s)
		_tween.chain().tween_callback(old.stop)


func _loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / (4 if stream.stereo else 2)


## Dopo ROTATE_S secondi nello stesso contesto passa a un'altra variante (anti fatica d'ascolto).
func rotate_if_due(dt: float) -> bool:
	_track_age_s += dt
	if _track_age_s < ROTATE_S or not CONTEXT_TRACKS.has(context) or (CONTEXT_TRACKS[context] as Array).size() < 2:
		return false
	_play_track(pick_track(context, current_track))
	return true


func _wanted_context() -> String:
	var ctx := "menu"
	var scene := get_tree().current_scene
	if scene != null and "current_id" in scene and GameState.active:
		ctx = context_for_screen(str(scene.current_id), GameState.data.get("activity", {}))
	if ctx == "menu" and event_music_active():
		ctx = "event"
	return ctx


func _poll() -> void:
	set_context(_wanted_context())
	rotate_if_due(POLL_S)
	var m := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	if m != _minimized:
		_minimized = m
		_apply_mute()
