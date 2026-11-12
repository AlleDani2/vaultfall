extends GutTest
## Revisione grafica 1.0 (rapporto 08, punti 5, 7, 8, 19, 20, 21, 27, 28): Combattimento con arena grande, Prestigio con intestazione-evento,
## Riepilogo come cruscotto, Eroe con scheda del personaggio, Talenti con catena dei livelli, Dungeon con «Entra» sopra i dettagli, Taglie a carte.
## Test sulla STRUTTURA (misure, nodi, stili), non sui pixel. Le regole di gioco restano nei sistemi.

const COMBAT := "res://src/ui/screens/CombatScreen.tscn"
const PRESTIGE := "res://src/ui/screens/PrestigeScreen.tscn"
const SUMMARY := "res://src/ui/screens/SummaryScreen.tscn"
const HERO := "res://src/ui/screens/HeroScreen.tscn"
const TALENTS := "res://src/ui/screens/TalentScreen.tscn"
const DUNGEON := "res://src/ui/screens/DungeonScreen.tscn"
const BOUNTY := "res://src/ui/screens/BountyScreen.tscn"

var _old_dir: String
var _old_seen: Variant
var _old_locale: Variant


func before_each() -> void:
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_grafica_schermate_a_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false
	_old_seen = Settings.get_value("seen_intro")
	_old_locale = Settings.get_value("locale")
	Settings.set_value("seen_intro", ["combat", "summary", "dungeon", "bounty", "prestige", "talents", "hero"])
	assert_true(Game.new_game(1, "normal", 7))
	GameState.data.skills["hero"] = {"xp": 0.0, "level": 40, "record_level": 40, "stars": 0, "perks": {}, "unlocked": true}
	(GameState.data.unlocks as Array).append_array(["feature:combat", "zone:millbrook", "zone:saltreach", "skill:hero", "feature:talents",
		"feature:prestige", "feature:bounties", "dungeon:cursed_granary"])


func after_each() -> void:
	Settings.set_value("seen_intro", _old_seen)
	Settings.set_value("locale", _old_locale)
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true


func _open(path: String, params: Dictionary = {}) -> GameScreen:
	var s: GameScreen = (load(path) as PackedScene).instantiate()
	add_child_autofree(s)
	s.open(params)
	await wait_process_frames(2)
	s.refresh()
	return s


func _texts(n: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var c := n as Control
	if c != null and not c.is_visible_in_tree():
		return out
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for ch in n.get_children():
		_texts(ch, out)
	return out


# ------------------------------------------------------------------ Combattimento (punto 7)

func test_combattimento_arena_grande_con_targhe_dentro_il_quadro() -> void:
	var cs := await _open(COMBAT)
	var vh: float = cs.get_viewport_rect().size.y
	assert_almost_eq(cs._stage.custom_minimum_size.y, clampf(vh * cs.ARENA_H_FRAC, cs.ARENA_H_MIN, cs.ARENA_H_MAX), 1.0,
		"l'altezza dell'arena segue la finestra (≈ 42%), entro i limiti")
	assert_gte(cs._stage.custom_minimum_size.y, 250.0, "mai un francobollo (era 190)")
	for n in [cs._hero_bar, cs._enemy_bar, cs._res_bar, cs._hero_hp, cs._enemy_hp, cs._hero_name, cs._enemy_name]:
		assert_true(cs._stage.is_ancestor_of(n), "barre e nomi stanno nel quadro, sopra ciascun combattente")
	assert_gte(cs._hero_bar.custom_minimum_size.y, 20.0, "barra della Vita evidente")
	assert_gte(cs._res_bar.custom_minimum_size.y, 12.0, "la Furia è una barra vera")
	assert_ne(cs._hero_name.text, "", "il nome della classe c'è")
	assert_not_null(cs._hero_sprite.texture, "il ritratto della classe dell'eroe c'è")


func test_combattimento_ritratti_a_scala_intera_e_ancorati_a_meta_quadro() -> void:
	var cs := await _open(COMBAT)
	assert_true(cs._combat.start("millbrook", ""))
	for i in 40:
		Game.sim.tick(FixedStepClock.STEP)
	cs.refresh()
	await wait_process_frames(2)
	assert_not_null(cs._hero_sprite.texture)
	var tex: Texture2D = cs._hero_sprite.texture
	var k: float = cs._hero_sprite.offset_right * 2.0 / tex.get_size().x
	assert_almost_eq(k, roundf(k), 0.001, "l'eroe è ingrandito di un fattore intero (D-6): ×%s" % k)
	assert_lt(cs._hero_sprite.anchor_left, 0.5, "eroe nella metà sinistra")
	assert_gt(cs._portrait.anchor_left, 0.5, "nemico nella metà destra")
	assert_eq(CombatUi.int_fit(null, 200.0), Vector2.ZERO)
	assert_eq(CombatUi.int_fit(tex, 300.0), tex.get_size() * 2.0, "128 px in 300: ×2")
	assert_eq(CombatUi.int_fit(tex, 50.0), tex.get_size(), "mai sotto ×1")


func test_combattimento_bersagli_come_carte_e_tecniche_visibili() -> void:
	var cs := await _open(COMBAT)
	assert_gt(cs._monster_list.get_child_count(), 2)
	for i in cs._monster_list.get_child_count():
		var b := cs._monster_list.get_child(i) as Button
		assert_gte(b.custom_minimum_size.y, 48.0, "carta alta, non una riga grigia")
		if i > 0:                                  # la prima è «un mostro comune a caso»: una riga sola
			assert_string_contains(b.text, "\n", "nome e livello su due righe")
	assert_true(cs._monster_list is HFlowContainer, "le carte vanno a capo, affiancate")
	assert_true(cs._abil_row.get_parent().get_parent().name == "AbilitiesPanel", "le tecniche sono una hotbar, non una frase")


# ------------------------------------------------------------------ Prestigio (punto 8)

func test_prestigio_intestazione_evento_con_polvere_grande() -> void:
	var pr := await _open(PRESTIGE)
	var head := pr.find_child("EventHeader", true, false)
	assert_not_null(head, "intestazione-evento")
	assert_eq(pr._dust_l.value_l.get_theme_font_size("font_size"), UiType.NUMBER_HERO, "la Polvere Stellare è il numero più grande")
	assert_true(pr._ev_title.text != "", "titolo del riquadro «se agisci ora» / «prossimo passo»")


func test_prestigio_con_un_rito_pronto_mostra_guadagno_anteprima_e_un_solo_pulsante_pieno() -> void:
	GameState.data.skills.woodcutting.level = 100
	GameState.data.skills.woodcutting.record_level = 100
	var pr := await _open(PRESTIGE)
	var ps := Game.system("prestige") as PrestigeSystem
	var a := ps.advise()
	assert_true(["star", "rite"].has(str(a.kind)), "con la mansione al massimo il Consigliere propone Stella o Rito")
	assert_true(pr._ev_btn.visible, "il pulsante dell'evento c'è")
	assert_string_contains(pr._ev_gain.text, NumberFormat.fmt(float(a.dust)), "il guadagno di Polvere è un numero grande")
	assert_eq(pr._ev_btn.theme_type_variation, &"AccentButton")
	assert_false(pr._ev_bar.visible)
	# anteprima Perdi / Conservi / Guadagni dentro la scheda Consigliere
	var texts := _texts(pr._adv_prev)
	assert_true(texts.has(tr("UI_PRESTIGE_LOSE")) and texts.has(tr("UI_PRESTIGE_KEEP")) and texts.has(tr("UI_PRESTIGE_GAIN")), str(texts))


func test_prestigio_senza_azione_mostra_il_passo_piu_vicino_e_gli_strati_futuri() -> void:
	var pr := await _open(PRESTIGE)
	assert_false(pr._ev_btn.visible, "nulla da fare: niente pulsante")
	assert_true(pr._ev_bar.visible or pr._ev_detail.text != "", "il passo più vicino o la frase di attesa")
	var texts := _texts(pr._adv_teaser)
	assert_true(texts.has(tr("UI_GSA_PR_COMING")), "«Cosa arriverà»")
	assert_true(texts.has(tr("UI_PRESTIGE_TAB_ERA")), "le Ere si vedono anche chiuse (P9)")
	assert_gte(texts.count(tr("UI_GSA_PR_LOCKED")), 2, "grigie, con «Bloccato»")


func test_frase_introduttiva_non_oltre_circa_90_caratteri_per_riga() -> void:
	var pr := await _open(PRESTIGE)
	await wait_process_frames(3)
	assert_lte(pr._intro.custom_minimum_size.x, ScreenKit.CAP_TEXT_PX + 0.5, "la frase ha una larghezza massima (punto 21)")
	var l := Label.new()
	l.text = "x".repeat(300)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1500, 100)
	add_child_autofree(box)
	box.add_child(l)
	ScreenKit.cap_text(l)
	await wait_process_frames(3)
	assert_lte(l.custom_minimum_size.x, ScreenKit.CAP_TEXT_PX + 0.5)
	assert_gt(l.custom_minimum_size.x, 100.0, "non si riduce a niente in un contenitore largo")


# ------------------------------------------------------------------ Riepilogo (punto 5)

func test_riepilogo_scheda_adesso_con_icona_a_scala_3x() -> void:
	var s := await _open(SUMMARY)
	assert_not_null(s.find_child("NowCard", true, false))
	assert_eq(s._now_icon.custom_minimum_size, Vector2(96, 96))
	assert_not_null(s._now_icon.texture)
	assert_eq(s._now_icon.texture.get_size() * 3.0, Vector2(96, 96), "icona 32×32 a scala 3× esatta")
	var sk := Game.system("skills") as SkillSystem
	sk.start(str(DataRegistry.actions_for_skill("woodcutting")[0].id))
	s.refresh()
	assert_true(s._now_open.visible, "«Apri <mansione>»")
	assert_eq(s._now_target, "skill:woodcutting")
	assert_string_contains(s._now_open.text, Loc.t(DataRegistry.get_def("skills", "woodcutting").name))


func test_riepilogo_da_fare_massimo_cinque_righe_e_mini_schede() -> void:
	var s := await _open(SUMMARY)
	assert_eq(s.TODO_MAX, 5)
	var rows: Array = s._todo_box.find_children("TodoGo", "Button", true, false)
	assert_lte(rows.size(), s.TODO_MAX)
	var stats := s.find_child("StatsRow", true, false)
	assert_not_null(stats)
	assert_gte(stats.get_child_count(), 2, "livello totale e Deposito come mini-schede")
	assert_eq(s._lv_big.text, TotalLevelText.text(GameState.total_level()))
	assert_not_null(s._bonus_btn.get_parent(), "il pulsante dei bonus resta")


# ------------------------------------------------------------------ Eroe (punto 19)

func test_eroe_scheda_del_personaggio_con_ritratto_e_statistiche() -> void:
	var hs := await _open(HERO)
	var doll: EquipDoll = hs._doll
	var fig := doll.find_child("HeroFigure", true, false) as Control
	assert_not_null(fig)
	assert_true(fig.is_visible_in_tree())
	assert_eq(doll._fig_vals.size(), EquipDoll.FIGURE_STATS.size())
	for k in doll._fig_vals:
		assert_ne((doll._fig_vals[k] as Label).text, "", str(k))
	assert_eq(doll._fig_portrait.texture.get_size(), Vector2(128, 128))
	assert_eq(doll._fig_portrait.custom_minimum_size, Vector2(128, 128), "ritratto a scala 1× (D-6)")
	assert_ne(doll._fig_name.text, "")


# ------------------------------------------------------------------ Talenti (punto 20)

func test_talenti_catena_dei_livelli_punti_in_grande_e_nota_neutra() -> void:
	var ts := await _open(TALENTS)
	var active := 0
	for t in ts._build.talent_nodes():
		if ts._build.branch_active(str(t.branch)):
			active += 1
	assert_eq(ts._tiers.size(), active, "un segno di livello per ogni nodo del ramo attivo")
	assert_gt(active, 0)
	assert_eq(ts._points_stat.value_l.get_theme_font_size("font_size"), UiType.NUMBER_HERO, "i punti liberi sono il numero più grande")
	# nessun punto speso: «niente da azzerare» è una nota grigia, non rossa
	assert_eq(ts._respec_reason.get_theme_color("font_color"), Color(ScreenKit.TEXT_DIM), "nota neutra")
	assert_ne(ts._respec_reason.get_theme_color("font_color"), Color(ScreenKit.BAD))


func test_talenti_pulsante_spendi_porta_sul_primo_nodo_acquistabile() -> void:
	var ts := await _open(TALENTS)
	var free: int = ts._build.points_free()
	assert_eq(ts._spend_btn.visible, free > 0)
	if free > 0:
		ts._on_spend()
		assert_eq(ts._build.why_not(ts._detail_id), "", "il riquadro di dettaglio mostra un nodo acquistabile")


# ------------------------------------------------------------------ Dungeon e Taglie (punti 27, 28)

func test_dungeon_entra_sopra_i_dettagli_e_titolo_di_sezione() -> void:
	var ds := await _open(DUNGEON, {"dungeon": "cursed_granary"})
	await wait_process_frames(2)
	var reward := ds._detail2.get_child(0) as Control
	assert_not_null(reward)
	assert_lt(ds._enter_btn.global_position.y, reward.global_position.y, "«Entra» sta sopra le ricompense")
	assert_gte(ds._enter_btn.custom_minimum_size.y, 44.0, "il pulsante del fine della pagina è grande")
	var title := ds._detail.get_child(0).get_child(0) as Label
	assert_ne(title.theme_type_variation, &"TitleLabel", "il nome del dungeon è un titolo di sezione, non di pagina")
	var tabs_row := ds._tab_btns["dungeon"].get_parent() as Control
	assert_gt(ds._hint.get_index(), tabs_row.get_index(), "l'avviso sta sotto le schede")


func test_taglie_offerte_in_carte_affiancate_con_azioni_sotto() -> void:
	var bs := await _open(BOUNTY)
	assert_true(bs._offers_box is HFlowContainer)
	var offers: Array = (Game.system("bounty") as BountySystem).offers()
	assert_gt(offers.size(), 0)
	assert_eq(bs._offers_box.get_child_count(), offers.size())
	for card in bs._offers_box.get_children():
		assert_gte((card as Control).custom_minimum_size.x, bs.OFFER_W - 0.5, "carta larga al più come serve, non 1300 px")
		var btns: Array = card.find_children("*", "Button", true, false)
		assert_gte(btns.size(), 2, "Accetta e Cambia")
		for b in btns:
			assert_gt((b as Control).global_position.y, (card.find_children("*", "TextureRect", true, false)[0] as Control).global_position.y,
				"le azioni stanno sotto il ritratto")


# ------------------------------------------------------------------ testi bilingui

func test_testi_nuovi_in_italiano_e_inglese() -> void:
	var f := FileAccess.open("res://localization/ui_strings.csv", FileAccess.READ)
	assert_not_null(f)
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or not row[0].begins_with("UI_GSA_"):
			continue
		n += 1
		assert_ne(row[1].strip_edges(), "", "inglese: " + row[0])
		assert_ne(row[2].strip_edges(), "", "italiano: " + row[0])
		for loc in ["it", "en"]:
			TranslationServer.set_locale(loc)
			assert_ne(TranslationServer.translate(row[0]), row[0], "%s tradotta in %s" % [row[0], loc])
	TranslationServer.set_locale("it")
	assert_gt(n, 25, "le stringhe UI_GSA_* ci sono")
