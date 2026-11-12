class_name TotalLevelText
extends RefCounted
## Testo del «Livello totale»: a inizio partita vale già quanto il numero di mansioni (ognuna parte da 1), e un «17» nudo
## fa pensare di essere a metà strada. Finché il totale è meno del doppio del minimo si aggiunge «(minimo 17)».
## Classe pura: il minimo è il numero di mansioni dei dati, nessun numero scritto qui.

static func base() -> int:
	return DataRegistry.skill_ids().size()


static func show_base(total: int, base_value: int) -> bool:
	return base_value > 0 and total < base_value * 2


## «17 (minimo 17)» finché si è all'inizio, altrimenti solo il numero formattato.
static func text(total: int, base_value: int = -1) -> String:
	var b := base() if base_value < 0 else base_value
	var n := NumberFormat.fmt(total)
	if show_base(total, b):
		return Loc.tf("UI_TOTLV_WITH_MIN", {"n": n, "min": NumberFormat.fmt(b)})
	return n
