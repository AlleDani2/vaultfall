class_name CrateUi
extends RefCounted
## Utilità di presentazione per le schermate delle Casse (Sala dei Caveau, Rullo, Guardaroba, Album).
## Solo lettura: colori, simboli e nomi vengono dai dati (crate_rules.json) e dal CSV; nessuna logica di gioco.
## Colori ORIGINALI del progetto (crate_rules.rarities): niente colori di altri giochi (CLAUDE.md regola 8).


static func crates() -> CrateSystem:
	return Game.system("crates") as CrateSystem if GameState.active else null


static func bank() -> GameSystem:
	return Game.system("bank") if GameState.active else null


static func rules() -> Dictionary:
	return DataRegistry.rules("crate_rules")


static func _rarity(rarity: String) -> Dictionary:
	for r in rules().get("rarities", []):
		if r.id == rarity:
			return r
	return {}


static func rarity_color(rarity: String) -> Color:
	return Color(str(_rarity(rarity).get("color", "#8DA2B8")))


static func rarity_symbol(rarity: String) -> String:
	return str(_rarity(rarity).get("symbol", ""))


static func rarity_name(rarity: String) -> String:
	return TranslationServer.translate("UI_CRATES_RARITY_" + rarity.to_upper())


## "◆◆ Epica": simbolo + nome (la rarità non è mai solo colore).
static func rarity_label(rarity: String) -> String:
	return "%s %s" % [rarity_symbol(rarity), rarity_name(rarity)]


static func condition_name(cond_id: String) -> String:
	for c in rules().get("conditions", []):
		if c.id == cond_id:
			return Loc.t(c.name)
	return cond_id


static func def_name(def_id: String) -> String:
	var d := DataRegistry.item(def_id)
	if d.is_empty():
		d = DataRegistry.get_def("pets", def_id)
	return Loc.t(d.get("name", def_id)) if not d.is_empty() else def_id


static func def_icon(def_id: String) -> Texture2D:
	var d := DataRegistry.item(def_id)
	if d.is_empty():
		return IconLib.portrait("pets", def_id)
	match str(d.get("category", "")):
		"skin":
			return IconLib.icon("skins", def_id)
		"relic":
			return IconLib.icon("relics", def_id)
		"cosmetic":
			return IconLib.icon("cosmetics", def_id)
		"crate":
			return IconLib.icon("crates", def_id)
	return IconLib.icon("items", def_id)


static func slot_name(slot: String) -> String:
	return TranslationServer.translate("UI_CRATES_SLOT_" + slot.to_upper())


static func group_name(group: String) -> String:
	return TranslationServer.translate("UI_CRATES_GROUP_" + group.to_upper())


static func _lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


## Numero con al massimo 2 decimali, zeri finali tolti ("79,2", "0,56", "13,2").
static func num(v: float, decimals: int = 2) -> String:
	var s := NumberFormat.decimal(v, decimals, _lang())
	var sep := NumberFormat.decimal(0.5, 1, _lang()).substr(1, 1)
	if s.contains(sep):
		s = s.rstrip("0").rstrip(sep)
	return s


## Percentuale delle probabilità: "79,2%", "0,3%", "0,56%".
static func pct(p: float) -> String:
	return num(p, 2) + "%"


## Testo di un modificatore: "Esperienza [Raccolta]: +1,5%".
static func mod_text(m: Dictionary) -> String:
	var parts := str(m.key).split(":")
	var fam := DataRegistry.modifier_family(parts[0])
	# QA119: nome breve della famiglia («Velocità», «Prodotto doppio»), non la descrizione tecnica con formule e tetti
	var cdef := BonusSummary.family_def(parts[0])
	var desc := Loc.t(cdef.get("name", {})) if not cdef.is_empty() else (Loc.t(fam.get("desc", parts[0])) if not fam.is_empty() else parts[0])
	var scope := ""
	if parts.size() > 1:
		var sk := DataRegistry.get_def("skills", parts[1])
		var scope_name := parts[1]
		if not sk.is_empty():
			scope_name = Loc.t(sk.name)
		else:
			var gk := "UI_VUX_SCOPE_" + parts[1].to_upper()          # ambiti-gruppo (raccolta, produzione…): mai l'id grezzo
			if str(TranslationServer.translate(gk)) != gk:
				scope_name = str(TranslationServer.translate(gk))
		scope = " [%s]" % scope_name
	var v := float(m.value)
	var unit := str(fam.get("unit", "pct"))
	return "%s%s: %s%s%s" % [desc, scope, "+" if v >= 0.0 else "", num(v, 2), "%" if unit.begins_with("pct") else ""]


static func mods_text(mods: Array) -> String:
	var lines := PackedStringArray()
	for m in mods:
		lines.append(mod_text(m))
	return "\n".join(lines)


## Descrizione di un'istanza (nome, condizione, float, Annalista) per tooltip e schede.
static func instance_text(inst: Dictionary) -> String:
	var lines := PackedStringArray([tagged_name(inst)])
	if inst.has("condition"):
		lines.append("%s · %s" % [condition_name(str(inst.condition)), NumberFormat.decimal(float(inst.get("float", 0.0)), 4, _lang())])
	if bool(inst.get("annalist", false)):
		lines.append(TranslationServer.translate("UI_CRATES_ANNALIST"))
	if inst.has("seed") and str(inst.get("kind", "")) != "cosmetic":
		lines.append(Loc.tf("UI_CRATES_PATTERN", {"n": int(inst.seed)}))
	if str(inst.get("phase", "")) != "":
		for p in rules().get("relic_phases", []):
			if p.id == inst.phase:
				lines.append(Loc.t(p.name))
	return "\n".join(lines)


## Sintesi leggibile di un'istanza (scena di rivelazione): condizione a parole, Annalista, fase colore. Niente valori tecnici
## (numero di usura, motivo): quelli stanno in `instance_detail`, dietro il pulsante «i».
static func instance_summary(inst: Dictionary) -> String:
	var lines := PackedStringArray()
	if inst.has("condition"):
		lines.append(condition_name(str(inst.condition)))
	if bool(inst.get("annalist", false)):
		lines.append(TranslationServer.translate("UI_CRATES_ANNALIST"))
	if str(inst.get("phase", "")) != "":
		for p in rules().get("relic_phases", []):
			if p.id == inst.phase:
				lines.append(Loc.t(p.name))
	return "\n".join(lines)


## Valori tecnici di un'istanza («Logoro · 0,5402 · Motivo 184»): sempre disponibili, mai in primo piano.
static func instance_detail(inst: Dictionary) -> String:
	var parts := PackedStringArray()
	if inst.has("condition"):
		parts.append("%s · %s" % [condition_name(str(inst.condition)), NumberFormat.decimal(float(inst.get("float", 0.0)), 4, _lang())])
	if inst.has("seed") and str(inst.get("kind", "")) != "cosmetic":
		parts.append(Loc.tf("UI_CRATES_PATTERN", {"n": int(inst.seed)}))
	return " · ".join(parts)


## Tooltip dei contenuti di una cassa: probabilità dell'oggetto, float, condizioni, Annalista.
static func item_tooltip(row: Dictionary, item: Dictionary) -> String:
	var lines := PackedStringArray([def_name(str(item.def_id)), rarity_label(str(row.rarity)),
		Loc.tf("UI_CRATES_TIP_ITEM_PCT", {"p": pct(float(item.pct)), "r": pct(float(item.pct_in_rarity))})])
	var co: Dictionary = item.condition_odds
	if not co.is_empty():
		lines.append(Loc.tf("UI_CRATES_TIP_FLOAT", {"a": num(float(item.float_min), 2), "b": num(float(item.float_max), 2)}))
		for c in rules().get("conditions", []):
			if co.has(c.id):
				lines.append("  %s %s" % [condition_name(c.id), pct(float(co[c.id]))])
	if float(item.annalist_pct) > 0.0:
		lines.append(Loc.tf("UI_CRATES_TIP_ANNALIST", {"p": pct(float(item.annalist_pct))}))
	return "\n".join(lines)


static func reduce_motion() -> bool:
	return bool(Settings.get_value("reduce_motion"))


# ------------------------------------------------------------------ CRATES-2: schede, azioni, celle

## Nome dell'istanza con l'eventuale Targhetta del giocatore: «Spiga Dorata «Pippo»».
static func tagged_name(inst: Dictionary) -> String:
	var n := def_name(str(inst.get("def_id", inst.get("def", ""))))
	var tag := str(inst.get("tag", ""))
	return n if tag.is_empty() else "%s «%s»" % [n, tag]


## Riga breve per elenchi: «Nome · Condizione · float ✎ 🔒».
static func inst_line(inst: Dictionary) -> String:
	var parts := PackedStringArray([tagged_name(inst)])
	if inst.has("condition"):
		parts.append("%s %s" % [condition_name(str(inst.condition)), NumberFormat.decimal(float(inst.get("float", 0.0)), 3, _lang())])
	var s := " · ".join(parts)
	if bool(inst.get("annalist", false)):
		s += " ✎"
	if bool(inst.get("locked", false)):
		s += " " + TranslationServer.translate("UI_CRATES2_LOCKED_MARK")
	return s


## Traduzione come String (TranslationServer ritorna StringName: nei ternari serve lo stesso tipo).
static func tx(key: String) -> String:
	return str(TranslationServer.translate(key))


## Motivo di un rifiuto, in chiaro (chiavi UI_CRATES2_WHY_*).
static func why(reason: String) -> String:
	return TranslationServer.translate("UI_CRATES2_WHY_" + reason.to_upper())


static func unlocked(token: String) -> bool:
	return token.is_empty() or (GameState.data.get("unlocks", []) as Array).has(token)


## Schede delle schermate delle Casse. `current`: hall | album | wardrobe | contracts | refine | bank | challenge.
const TAB_DEFS: Array[Dictionary] = [
	{"id": "hall", "key": "UI_CRATES_TAB_CRATES", "screen": "vault_hall", "tab": "", "token": ""},
	{"id": "album", "key": "UI_CRATES_TAB_ALBUM", "screen": "album", "tab": "", "token": "feature:wardrobe"},
	{"id": "wardrobe", "key": "UI_CRATES_TAB_WARDROBE", "screen": "wardrobe", "tab": "", "token": "feature:wardrobe"},
	{"id": "contracts", "key": "UI_CRATES_TAB_TRADE", "screen": "vault_workshop", "tab": "contracts", "token": "feature:tradeup"},
	{"id": "refine", "key": "UI_CRATES_TAB_REFINE", "screen": "vault_workshop", "tab": "refine", "token": "feature:refinery"},
	{"id": "bank", "key": "UI_CRATES_TAB_BANK", "screen": "vault_workshop", "tab": "bank", "token": ""},
	{"id": "challenge", "key": "UI_CRATES_TAB_CHALLENGE", "screen": "vault_workshop", "tab": "challenge", "token": "feature:collectors_challenge"},
]


static func build_tabs(parent: Control, current: String) -> HFlowContainer:
	return VaultKit.tabs(parent, current)


## Cella con icona, nome, sottotitolo e bordo del colore della rarità (sala dei Caveau, risultati, esiti).
static func cell(def_id: String, rarity: String, sub: String, tip: String, size: Vector2 = Vector2(118, 112), glow: bool = false, icon_scale: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.tooltip_text = tip
	p.theme_type_variation = UiKit.rarity_variation(rarity, glow)       # cornice della rarità (angoli e bordo diversi)
	var col := rarity_color(rarity)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var tr_ := TextureRect.new()
	tr_.texture = def_icon(def_id)
	tr_.custom_minimum_size = Vector2(32, 32) * float(maxi(1, icon_scale))      # PNG 32x32: sempre a scala intera
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(tr_)
	var n := Label.new()
	n.text = def_name(def_id)
	n.add_theme_font_size_override("font_size", UiType.NOTE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	var s := Label.new()
	s.text = "%s %s" % [rarity_symbol(rarity), sub]
	s.add_theme_font_size_override("font_size", UiType.NOTE)
	s.add_theme_color_override("font_color", col)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	return p


## Testo semplice a capo automatico (etichette informative).
static func note(parent: Control, text: String, muted: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if muted:
		l.theme_type_variation = &"MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


static func section(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SectionLabel"
	parent.add_child(l)
	return l


## Conferma modale (Fondi/Vendi/Contratti consumano oggetti). `on_yes` è chiamata solo dopo il «Sì».
static func confirm(host: Node, text: String, on_yes: Callable) -> void:
	var d := ConfirmationDialog.new()
	DialogKit.style_confirm(d, 420)
	d.dialog_text = text
	d.ok_button_text = TranslationServer.translate("UI_CRATES2_YES")
	d.cancel_button_text = TranslationServer.translate("UI_CRATES2_NO")
	d.confirmed.connect(on_yes)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	host.add_child(d)
	d.popup_centered()
