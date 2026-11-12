class_name TutorialTargets
extends RefCounted
## Come il tutorial trova i controlli da evidenziare: ogni controllo "importante" si marca con una chiave stabile
## (mai il testo tradotto) e finisce nel gruppo `tut:<chiave>`. Quando il controllo viene liberato (cambio schermata,
## ricostruzione del menù) esce da solo dal gruppo: nessun riferimento da tenere aggiornato.
##
## Chiavi in uso: sidebar · menu:<id schermata> · topbar:settings|help|save|pause|column|quests · content · skill_header ·
## action:<id azione> · mastery:<id azione> · row:<id azione> · perk_btn · extras_toggle|extras_queue|extras_potion|extras_feast ·
## combat_start · run_panel · bank_expand_btn (pulsante «Espandi Deposito») · goal_go (pulsante «Vai» dell'Obiettivo attuale) · quest_go (primo «Vai» della scheda di una missione).

const GROUP_PREFIX := "tut:"
const META := "tut"


static func mark(node: Node, key: String) -> void:
	if node == null:
		return
	node.set_meta(META, key)
	node.add_to_group(GROUP_PREFIX + key)


## Primo controllo visibile con questa chiave, o null.
static func find(tree: SceneTree, key: String) -> Control:
	if tree == null or key.is_empty():
		return null
	for n in tree.get_nodes_in_group(GROUP_PREFIX + key):
		var c := n as Control
		if c != null and c.is_visible_in_tree() and c.size.x > 1.0 and c.size.y > 1.0:
			return c
	return null


## Primo controllo trovato scorrendo la lista di chiavi in ordine di preferenza: {"key": String, "node": Control} o {}.
static func find_any(tree: SceneTree, keys: Array) -> Dictionary:
	for k in keys:
		var c := find(tree, str(k))
		if c != null:
			return {"key": str(k), "node": c}
	return {}


## Se il controllo sta dentro un'area a scorrimento e non si vede, la fa scorrere fino a mostrarlo.
static func reveal(node: Control) -> void:
	var p := node.get_parent()
	while p != null:
		var sc := p as ScrollContainer
		if sc != null:
			var vis := sc.get_global_rect()
			var r := node.get_global_rect()
			if r.position.y < vis.position.y or r.end.y > vis.end.y:
				sc.ensure_control_visible(node)
			return
		p = p.get_parent()
