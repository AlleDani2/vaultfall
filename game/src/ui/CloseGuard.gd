class_name CloseGuard
extends RefCounted
## Conferma di chiusura con un combattimento attivo (docs/05 §6, UI-A G20). Classe di presentazione: legge CombatSystem
## (`idle_safety`, lo stesso indicatore «Sicuro in idle» della scheda Combattimento) e costruisce la finestra di conferma.
## SaveService la usa per la X della finestra; il pulsante «Esci» delle Impostazioni e del menù iniziale restano immediati.


## Stato del combattimento in corso: {} se non c'è, altrimenti {"mode": zona|dungeon|raid|…, "level": green|yellow|red|"",
## "food_hours": float (-1 = nessun consumo), "monster": id}.
static func combat_status() -> Dictionary:
	if not GameState.active:
		return {}
	var cb := Game.system("combat") as CombatSystem
	if cb == null or not cb.in_combat():
		return {}
	var act: Dictionary = GameState.data.get("activity", {})
	var mid := str(act.get("monster", ""))
	if mid.is_empty():
		var best := ""
		for m in cb.monsters_of(str(act.get("zone", ""))):
			if best.is_empty() or str(m.type) == "normal":
				best = str(m.id)               # come la scheda Combattimento: il più forte dei normali, criterio prudente
		mid = best
	var out := {"mode": str(act.get("mode", "zone")), "level": "", "food_hours": -1.0, "monster": mid}
	if not mid.is_empty() and not cb.in_dungeon():
		var s := cb.idle_safety(mid)
		if not s.is_empty():
			out["level"] = str(s.level)
			out["food_hours"] = float(s.food_hours)
	return out


static func needs_confirmation() -> bool:
	return bool(Settings.get_value("confirm_quit")) and not combat_status().is_empty()


## Testo della finestra: cosa succede se si chiude e come sta l'eroe.
static func message(st: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(TranslationServer.translate("UI_UIA_QUIT_BODY"))
	var level := str(st.get("level", ""))
	if level.is_empty():
		lines.append(TranslationServer.translate("UI_UIA_QUIT_NOSAFE"))
	else:
		lines.append(Loc.tf("UI_UIA_QUIT_SAFETY", {"state": TranslationServer.translate("UI_COMBAT_SAFE_" + level.to_upper())}))
		var h := float(st.get("food_hours", -1.0))
		lines.append(Loc.tf("UI_UIA_QUIT_FOOD", {"time": str(TranslationServer.translate("UI_COMBAT_FOOD_INF")) if h < 0.0
			else NumberFormat.fmt_time(h * 3600.0)}))
	return "\n".join(lines)


## Finestra di conferma già pronta (non aggiunta all'albero). `on_quit` si chiama con «Salva ed esci».
static func build_dialog(st: Dictionary, on_quit: Callable) -> ConfirmationDialog:
	var dlg := ConfirmationDialog.new()
	dlg.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dlg.title = TranslationServer.translate("UI_UIA_QUIT_TITLE")
	dlg.ok_button_text = TranslationServer.translate("UI_UIA_QUIT_OK")
	dlg.cancel_button_text = TranslationServer.translate("UI_UIA_QUIT_CANCEL")
	dlg.dialog_text = message(st)
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(460, 0)
	dlg.exclusive = true
	dlg.confirmed.connect(on_quit)
	return dlg
