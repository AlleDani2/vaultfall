class_name WorkshopView
extends VBoxContainer
## Base delle schede della Bottega dei Caveau (Contratti, Affinatura, Banco, Sfida). Presentazione soltanto:
## i numeri vengono da CrateSystem; la scheda si ricostruisce solo quando la "firma" dei dati cambia
## (refresh ≤ 10 Hz senza sfarfallii né perdita del testo che si sta scrivendo).

var crates: CrateSystem
var _sig: String = ""


func setup(c: CrateSystem, params: Dictionary) -> void:
	crates = c
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_params(params)
	rebuild(true)


func refresh() -> void:
	if crates != null:
		rebuild(false)


func rebuild(force: bool) -> void:
	var s := signature()
	if s == _sig and not force:
		return
	_sig = s
	for c in get_children():
		remove_child(c)
		c.queue_free()
	build()


# --- da sovrascrivere
func _apply_params(_params: Dictionary) -> void:
	pass


func signature() -> String:
	return ""


func build() -> void:
	pass


# --- utilità
func bank_revision() -> int:
	var b := CrateUi.bank()
	return int(b.revision) if b != null else 0


func gold() -> int:
	var b := CrateUi.bank()
	return int(b.gold()) if b != null else 0


## Funzione ancora bloccata: scheda chiara con lucchetto, a cosa servirà, come si sblocca e, «nessun vicolo cieco» (G37),
## il pulsante Vai alla missione che la concede.
func _locked_note(token: String, title_key: String = "", what_key: String = "") -> void:
	var hint := UnlockSystem.hint_for(token, DataRegistry)
	var steps := PackedStringArray([hint if not hint.is_empty() else CrateUi.why("locked_feature")])
	var gos: Array = []
	var t := ReqLink.target_for_token(token)
	if not t.is_empty():
		gos.append({"text": tr("UI_MENU_QUESTS"), "primary": true, "target": t})
	var title := tr(title_key) if not title_key.is_empty() else CrateUi.why("locked_feature")
	var what := tr(what_key) if not what_key.is_empty() else ""
	VaultKit.empty_card(self, IconLib.ui("ui_lock"), title, what, steps, gos)


func _label(text: String, muted: bool = true) -> Label:
	return CrateUi.note(self, text, muted)


func _section(text: String) -> Label:
	return CrateUi.section(self, text)


func _instances_of(kinds: Array) -> Array:
	var out: Array = []
	var b := CrateUi.bank()
	if b == null:
		return out
	for inst in b.list_instances():
		if kinds.has(str(inst.get("kind", ""))):
			out.append(inst)
	return out


func _rarity_option(include_all: bool, rarities: Array, selected: String) -> OptionButton:
	var ob := OptionButton.new()
	var sel_idx := 0
	if include_all:
		ob.add_item(TranslationServer.translate("UI_CRATES2_FILTER_ALL"))
		ob.set_item_metadata(ob.item_count - 1, "")
	for r in rarities:
		ob.add_item(CrateUi.rarity_label(str(r)))
		ob.set_item_metadata(ob.item_count - 1, str(r))
		if str(r) == selected:
			sel_idx = ob.item_count - 1
	ob.select(sel_idx)
	return ob
