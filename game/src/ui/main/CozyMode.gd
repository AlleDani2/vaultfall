class_name CozyMode
extends RefCounted
## Modalità Cozy (G53, opzionale): più XP per chi vuole giocare rilassato. La regola vive in ModeSystem (stato della partita,
## sorgente Modifiers «mode:cozy», applicata a new_game/load_game e al cambio impostazione): vale anche offline e non dipende
## dalla UI. Qui solo letture per le schermate. Il valore (+%) viene da constants.json → cozy.xp_pct (core.py::COZY_XP_PCT).
## Non conta per le classifiche: ModeSystem.run_tags() marca le partite Cozy.

const SOURCE := ModeSystem.COZY_SOURCE


static func xp_pct() -> float:
	return float(DataRegistry.constants.get("cozy", {}).get("xp_pct", 0.0))


## Preferenza del PC (vale per le nuove partite e, se cambia in partita, per quella in corso).
static func is_on() -> bool:
	return bool(Settings.get_value("cozy_mode"))


## La partita in corso è in Cozy.
static func game_is_cozy() -> bool:
	var ms := Game.system("modes") as ModeSystem
	return ms != null and ms.is_cozy()
