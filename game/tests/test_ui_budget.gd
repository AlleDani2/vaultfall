extends GutTest
## Budget della densità dell'interfaccia (progetto di interfaccia, docs/ui_redesign/06 D30, fase F0).
## Nuova partita (seme 4242), tutto sbloccato, tutorial spenti, finestra 1280×720, Taglialegna in corso. Misura la cornice
## (barra alta, menù, colonna destra) e 10 schermate campione con lo stesso conteggio dell'audit (helpers/ui_census.gd),
## scrive reports/ui_budget.json e confronta con SOGLIE. Le soglie si STRINGONO fase dopo fase (F1…F12, F18): chi riduce la
## densità abbassa il numero qui, mai il contrario. Un test che fallisce per un valore PIÙ ALTO del limite vuol dire che la
## fase ha aggiunto cornice o contenuto di troppo.

## Schermate campione (id di ScreenRegistry).
const SCREENS: PackedStringArray = ["summary", "quests", "skill:woodcutting", "skill:smithing", "combat", "bank", "estate",
	"hero", "vault_hall", "talents"]

## Soglie MASSIME. In F0 = valore misurato oggi + 5% (arrotondato per eccesso): il test deve passare senza cambiare il gioco.
## Accanto a ogni soglia, tra parentesi, l'OBIETTIVO FINALE (docs/ui_redesign/06 §2.3 budget della cornice, §2.5 metriche).
## Chiave = "<gruppo>.<metrica>"; gruppi: "cornice" (regioni misurate nel Riepilogo; la striscia Città nel Deposito) e "mediana" (mediana sulle 10 schermate).
const SOGLIE := {
	"cornice.top_elementi": 12,           # barra alta (F2: ≤ 12, obiettivo raggiunto)
	"cornice.side_elementi": 19,          # menù laterale (F4: misurato 18, tetto di accettazione ≤ 26)
	"cornice.right_elementi": 3,          # binario destro (F18: misurato 1; obiettivo ≤ 5 raggiunto)
	"cornice.city_elementi": 0,          # striscia Città: F6 l'ha spostata nel Riepilogo (obiettivo 0 raggiunto)
	"cornice.totale_elementi": 34,        # somma della cornice (F18: misurato 30; obiettivo ≤ 45 raggiunto)
	"cornice.side_badge": 0,             # pillole nel menù (oggi 0 in questo scenario: nessun premio da riscuotere; obiettivo ≤ 5 numeri)
	"mediana.elementi_info": 80,           # elementi informativi, finestra (F18: misurato 74,5; obiettivo ≤ 80 raggiunto in questo scenario)
	"mediana.controlli_visibili": 175,     # controlli visibili (F18: misurato 156,5; obiettivo ≤ 160: nell'audit a 60 h 195, vedi 08_RISULTATI). 170 → 175 (grafica 25, 29/10/2026): le Missioni a DUE colonne e le mansioni a carte mostrano più pulsanti nella stessa finestra (misurato 170,5), non più elementi per carta
	"mediana.competitori_attenzione": 9,  # concorrenti d'attenzione (F18: misurato 7; obiettivo ≤ 10 raggiunto)
	"mediana.righe_testo": 70,             # righe di testo (F18: misurato 64,5; obiettivo ≤ 70 raggiunto in questo scenario)
	"mediana.badge_pillole": 2,          # badge/pillole contemporanei (F18: misurato 0; obiettivo ≤ 5 raggiunto)
	"mediana.parole_prosa": 55,           # parole di prosa visibili, finestra intera (F18: misurato 50 alla PRIMA visita, con le frasi «a cosa serve» aperte; alla seconda ≈ 24; obiettivo ≤ 40)
	"mediana.ripetizioni_extra": 3,      # ripetizioni extra (F18: misurato 1,5; obiettivo ≤ 1: non raggiunto, vedi 08_RISULTATI)
}
## Soglie MASSIME per singola schermata: "<id schermata>.<metrica>"; la metrica si cerca prima nel solo contenuto (regione «content»), poi nella finestra.
const SOGLIE_SCHERMATA := {
	"combat.righe_testo": 45,             # F8: righe di testo del contenuto ≤ 45 (nell'audit a 60 h erano 124)
	"hero.pagine": 1.5,                   # F10: l'Eroe sta in 1,5 pagine al massimo
	"talents.controlli_visibili": 180,    # F10: i Talenti in 180 controlli
	"skill:woodcutting.elementi_info": 45,  # F7: contenuto di Taglialegna ≤ 45 elementi informativi (prima 38 a livello 1)
	"skill:smithing.elementi_info": 45,     # F7: idem Forgiatura (prima 34)
	"vault_hall.pagine": 2.0,             # F11: Sala dei Caveau ≤ 2 pagine di scorrimento
	# F6: Riepilogo ≤ 30 elementi di contenuto; Missioni: senza il blocco «Da scoprire» in cima entrano più carte (34 contro 24), la prosa non supera il valore di prima
	"summary.elementi_info": 30,
	"summary.parole_prosa": 50,
	"summary.ripetizioni_extra": 1,
	# grafica 25 (29/10/2026, problema 18 del rapporto 08): le Missioni sono carte a DUE colonne con ricompense a icone: nella stessa
	# finestra entrano il doppio delle carte (e dei loro elementi/ripetizioni, p. es. «Riscatta»). Per carta non cambia nulla.
	"quests.elementi_info": 50,
	"quests.parole_prosa": 111,
	"quests.ripetizioni_extra": 5,
}
## Quota di cornice mediana (fra 0 e 1): MASSIMA oggi (misurata 0,59) + 5% (obiettivo ≤ 0,45).
const SOGLIA_QUOTA_CROMO := 0.50      # F18: misurata 0,46 in questo scenario (obiettivo ≤ 0,45: nell'audit a 60 h 0,46)
## Soglie per schermata (F9, accettazione 06 §4.3): la Tenuta sta in al più 2 pagine da 720 px, il Dungeon in al più 200 controlli.
const SOGLIA_PAGINE_TENUTA := 2.0
const SOGLIA_CONTROLLI_DUNGEON := 200

var _old_dir: String
var _old_size: Vector2i
var _old_scale: float
var _old_fps: int
var _old_settings: Dictionary = {}


func before_all() -> void:
	_old_fps = Engine.max_fps
	Engine.max_fps = 0
	_old_size = get_tree().root.size
	_old_scale = get_tree().root.content_scale_factor


func after_all() -> void:
	Engine.max_fps = _old_fps


func before_each() -> void:
	# Stato isolato (deterministico): impostazioni di default (lingua italiana, nessun gruppo del menù richiuso, tutorial spenti)
	# e orologio di gioco FERMO: altrimenti il tempo reale dei frame fa avanzare la partita (più lenta la macchina, più passi
	# per frame) e una missione può diventare «da riscuotere» durante le misure, accendendo un badge nel menù.
	_old_settings.clear()
	for k in Settings.DEFAULTS:
		_old_settings[k] = Settings.get_value(k)
	Settings.reset_to_defaults()
	Settings.set_value("locale", "it")
	Settings.set_value("tutorials", false)
	_old_dir = SaveService.save_dir
	SaveService.save_dir = "user://test_ui_budget_%d" % Time.get_ticks_usec()
	SaveService.autosave_enabled = false


func after_each() -> void:
	Clock.core.speed = 1.0
	_set_window(_old_size)
	get_tree().root.content_scale_factor = _old_scale
	if GameState.active:
		Game.stop_game(false)
	for s in range(1, SaveService.SLOTS + 1):
		SaveService.delete_slot(s)
	DirAccess.remove_absolute(SaveService.save_dir)
	SaveService.save_dir = _old_dir
	SaveService.autosave_enabled = true
	for k in _old_settings:
		Settings.set_value(k, _old_settings[k])


func _set_window(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	get_tree().root.size = sz


## Stesso avvio di test_layout_resolutions._main(): tutto sbloccato, tutorial spenti.
func _main() -> Control:
	Game.new_game(1, "normal", 4242)
	var un: Object = Game.system("unlock")
	for e in ScreenRegistry.entries():
		var tok := str(e.get("unlock", ""))
		if tok != "":
			un.grant(tok)
	Settings.set_value("tutorials", false)
	Clock.core.speed = 0.0       # orologio reale scollegato dalla partita (senza «In pausa», che cambierebbe la barra): avanzano solo i _steps() espliciti
	var main: Control = (load("res://src/ui/main/MainScreen.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	await wait_process_frames(3)
	var ov := main.find_child("WelcomeGo", true, false) as Button
	if ov != null:
		ov.pressed.emit()
	await wait_process_frames(2)
	main.call("build_menu")
	return main


func _steps(n: int) -> void:
	for i in n:
		Game.call("_on_step", 0.1)


func _start_woodcutting() -> void:
	var sk := Game.system("skills") as SkillSystem
	if not sk.is_active():
		sk.start("wc_pine")
		_steps(5)


func _first_zone(cb: CombatSystem) -> String:
	var best := ""
	for z in cb.zones():
		if cb.zone_unlocked(z.id):
			best = z.id
	return best


## Nessuna missione da riscuotere durante le misure (il badge «Missioni» è un segnale legittimo, ma qui falserebbe la cornice).
func _claim_ready_quests() -> void:
	var q := Game.system("quests") as QuestSystem
	for n in 20:
		if q.ready_count() == 0:
			return
		for a in q.active_quests():
			if a.ready:
				q.claim(str(a.id))


func _measure_screen(main: Control, id: String) -> Dictionary:
	var cb := Game.system("combat") as CombatSystem
	if id == "combat":
		cb.start(_first_zone(cb))
		_steps(150)
	else:
		_start_woodcutting()
	assert_true(main.show_screen(id), "schermata campione apribile: " + id)
	await wait_process_frames(4)
	_steps(30)
	main.call("_on_ui_tick")
	await wait_process_frames(6)
	var toasts := main.find_child("Toasts", true, false)
	if toasts != null:
		for c in toasts.get_children():
			c.free()
	_claim_ready_quests()
	main.call("_on_ui_tick")
	await wait_process_frames(3)
	var res := UiCensus.measure(main, get_viewport().get_visible_rect())
	res["pagine"] = _pagine_di(main)
	if id == "combat":
		cb.stop()
	return res


## Pagine di scorrimento della schermata aperta: il massimo fra contenuto e altezza visibile dei ScrollContainer in vista.
func _pagine_di(main: Control) -> float:
	var host := main.get("_host") as Control
	if host == null or host.get_child_count() == 0:
		return 0.0
	var scr := host.get_child(host.get_child_count() - 1)
	var best := 1.0
	for sc in scr.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if not s.is_visible_in_tree():
			continue
		var sb := s.get_v_scroll_bar()
		best = maxf(best, sb.max_value / maxf(1.0, sb.page))
	if scr is ScrollContainer:
		var sb2 := (scr as ScrollContainer).get_v_scroll_bar()
		best = maxf(best, sb2.max_value / maxf(1.0, sb2.page))
	return best


func _median(values: Array) -> float:
	var v := values.duplicate()
	v.sort()
	var n := v.size()
	if n == 0:
		return 0.0
	return float(v[n / 2]) if n % 2 == 1 else (float(v[n / 2 - 1]) + float(v[n / 2])) / 2.0


func test_budget_cornice_e_schermate() -> void:
	var main: Control = await _main()
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	_start_woodcutting()
	var per_screen := {}
	for id in SCREENS:
		per_screen[id] = await _measure_screen(main, id)
	var summary: Dictionary = per_screen["summary"]
	var frame := {
		"top_elementi": int(summary.get("top", {}).get("elementi_info", 0)),
		"side_elementi": int(summary.get("side", {}).get("elementi_info", 0)),
		"right_elementi": int(summary.get("right", {}).get("elementi_info", 0)),
		"city_elementi": int(per_screen["bank"].get("city", {}).get("elementi_info", 0)),   # la striscia compare solo nelle voci della Città
		"totale_elementi": int(summary.cornice_elementi),
		"side_badge": int(summary.get("side", {}).get("badge_pillole", 0)),
	}
	var med := {}
	for metric in ["elementi_info", "controlli_visibili", "competitori_attenzione", "righe_testo", "badge_pillole", "parole_prosa"]:
		var vals: Array = []
		for id in SCREENS:
			vals.append(per_screen[id].window[metric])
		med[metric] = _median(vals)
	var reps: Array = []
	var quote: Array = []
	for id in SCREENS:
		reps.append(per_screen[id].ripetizioni_extra)
		quote.append(per_screen[id].quota_cromo)
	med["ripetizioni_extra"] = _median(reps)
	var quota_mediana := _median(quote)
	_write_report(frame, med, quota_mediana, per_screen)

	var failures := PackedStringArray()
	for key in SOGLIE:
		var parts := str(key).split(".")
		var value: float = float(frame[parts[1]]) if parts[0] == "cornice" else float(med[parts[1]])
		if value > float(SOGLIE[key]):
			failures.append("%s = %s > soglia %s" % [key, str(value), str(SOGLIE[key])])
	for key in SOGLIE_SCHERMATA:
		var parts: PackedStringArray = str(key).rsplit(".", true, 1)
		var sid := parts[0]
		var metric := parts[1]
		var content: Dictionary = per_screen[sid].get("content", {})
		var got: float = float(content[metric]) if content.has(metric) else float(per_screen[sid].get(metric, per_screen[sid].window.get(metric, 0)))
		if got > float(SOGLIE_SCHERMATA[key]):
			failures.append("%s = %s > soglia %s" % [key, str(got), str(SOGLIE_SCHERMATA[key])])
	if quota_mediana > SOGLIA_QUOTA_CROMO:
		failures.append("quota_cromo = %s > soglia %s" % [str(quota_mediana), str(SOGLIA_QUOTA_CROMO)])
	if not failures.is_empty():
		gut.p("\n".join(failures))
	assert_eq(failures.size(), 0, "valori sopra le soglie (elenco sopra)")


func test_colori_condivisi_hanno_contrasto_del_testo() -> void:
	# D14/F0: ogni coppia sfondo/testo dei segnali ha contrasto >= 4,5:1 (WCAG AA per il testo normale)
	var pairs := {
		"pericolo": [UiKit.DANGER, UiKit.DANGER_TEXT],
		"ambra": [UiKit.BADGE_AMBER, UiKit.BADGE_AMBER_TEXT],
		"rischio_ok": [UiKit.RISK_OK, UiKit.RISK_OK_TEXT],
		"rischio_attenzione": [UiKit.RISK_WARN, UiKit.RISK_WARN_TEXT],
		"rischio_alto": [UiKit.RISK_BAD, UiKit.RISK_BAD_TEXT],
	}
	for k in pairs:
		var c := UiKit.contrast(pairs[k][0], pairs[k][1])
		assert_true(c >= 4.5, "%s: contrasto %.2f >= 4,5" % [k, c])
	assert_almost_eq(UiKit.contrast(Color.BLACK, Color.WHITE), 21.0, 0.01, "controllo della formula")


func test_intro_hint_nel_tema() -> void:
	var theme := load("res://src/ui/theme/main_theme.tres") as Theme
	assert_true(theme.get_type_variation_base(UiKit.INTRO_HINT) == &"Label", "IntroHint è una variazione di Label")
	var col := theme.get_color("font_color", UiKit.INTRO_HINT)
	assert_true(UiKit.contrast(col, Color("#15171c")) >= 4.5, "testo IntroHint leggibile sul pannello scuro")


func test_bande_di_larghezza() -> void:
	assert_eq(UiBands.band(1099.0), UiBands.BAND_NARROW)
	assert_eq(UiBands.band(1100.0), UiBands.BAND_NORMAL)
	assert_eq(UiBands.band(1439.0), UiBands.BAND_NORMAL)
	assert_eq(UiBands.band(1440.0), UiBands.BAND_WIDE)
	assert_eq(UiBands.WIDE_W, 1440.0)


func test_chiavi_settings_dell_ondata_a_non_cambiano_il_comportamento() -> void:
	assert_eq(Settings.DEFAULTS["ui_layout_rev"], 1)
	assert_eq(Settings.DEFAULTS["drawer_section"], "log")
	assert_eq(Settings.DEFAULTS["sidebar_groups_closed"], [])
	assert_eq(Settings.DEFAULTS["seen_intro"], [])
	assert_eq(Settings.DEFAULTS["ui_scale_auto"], true, "F5: la scala automatica è accesa")
	assert_false(Settings.DEFAULTS["right_col_visible"], "dalla F3 la colonna destra è un cassetto: fissata solo su richiesta")


func _write_report(frame: Dictionary, med: Dictionary, quota: float, per_screen: Dictionary) -> void:
	var screens := {}
	for id in per_screen:
		var r: Dictionary = per_screen[id]
		screens[id] = {"window": r.window, "pagine": r.get("pagine", 0.0), "quota_cromo": r.quota_cromo, "ripetizioni_extra": r.ripetizioni_extra,
			"regioni": {"top": r.get("top", {}), "side": r.get("side", {}), "right": r.get("right", {}),
				"city": r.get("city", {}), "content": r.get("content", {})}}
	var out := {"scenario": "nuova partita seme 4242, tutto sbloccato, 1280x720, Taglialegna in corso", "fase": "F0",
		"cornice": frame, "mediana": med, "quota_cromo_mediana": quota, "schermate": screens}
	# il file tracciato reports/ui_budget.json si riscrive SOLO su richiesta (VAULTFALL_WRITE_REPORTS=1); altrimenti i test
	# scrivono in user:// e `git status` resta pulito dopo ogni giro
	var dir := ProjectSettings.globalize_path("res://").path_join("../reports").simplify_path() \
		if OS.get_environment("VAULTFALL_WRITE_REPORTS") == "1" else ProjectSettings.globalize_path("user://reports_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("ui_budget.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()


## Altezza del contenuto scorrevole della schermata aperta, in pagine della finestra (offset dall'alto compreso).
func _pagine(main: Control, win_h: float) -> float:
	var host := main.get("_host") as Control
	var scr := host.get_child(host.get_child_count() - 1)
	var pages := 0.0
	for c in scr.find_children("*", "ScrollContainer", true, false):
		var sc := c as ScrollContainer
		if not sc.is_visible_in_tree() or sc.get_child_count() == 0:
			continue
		var inner := sc.get_child(0) as Control
		pages = maxf(pages, (sc.global_position.y - scr.global_position.y + inner.get_combined_minimum_size().y) / win_h)
	return pages


func test_tenuta_e_dungeon_sotto_le_soglie_di_schermata() -> void:
	var main: Control = await _main()
	get_tree().root.content_scale_factor = 1.0
	_set_window(Vector2i(1280, 720))
	await wait_process_frames(3)
	_start_woodcutting()
	var est := await _measure_screen(main, "estate")
	var pagine := _pagine(main, 720.0)
	gut.p("Tenuta: %.2f pagine, %d controlli visibili (finestra)" % [pagine, int(est.window.controlli_visibili)])
	assert_lte(pagine, SOGLIA_PAGINE_TENUTA, "Tenuta: %.2f pagine (soglia %.1f)" % [pagine, SOGLIA_PAGINE_TENUTA])
	assert_gt(int(est.window.controlli_visibili), 0)
	var dun := await _measure_screen(main, "dungeon")
	var n := int(dun.window.controlli_visibili)
	gut.p("Dungeon: %d controlli visibili (finestra), %d nel contenuto" % [n, int(dun.content.controlli_visibili)])
	assert_lte(n, SOGLIA_CONTROLLI_DUNGEON, "Dungeon: %d controlli visibili (soglia %d)" % [n, SOGLIA_CONTROLLI_DUNGEON])
