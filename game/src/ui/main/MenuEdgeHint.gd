class_name MenuEdgeHint
extends Button
## Piccolo indicatore ai bordi del menù laterale: quando la voce dell'attività principale è fuori vista (menù più lungo
## della finestra) compare in alto o in basso con «In corso: nome» e una freccia; un clic scorre il menù fino alla voce.
## Solo presentazione (resoconto UI 05): niente auto-scroll che sposti il menù mentre l'utente lo sta usando.

const H := 24.0
const BG := Color(0.07, 0.08, 0.10, 0.94)
const CHEVRON := Color("#f0d9a0")

var up: bool = false


func _init(is_up: bool = false) -> void:
	up = is_up
	name = "EdgeUp" if up else "EdgeDown"
	visible = false
	flat = false
	focus_mode = Control.FOCUS_NONE                       # il menù ha già le sue voci con il focus
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(0, H)
	add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = BG if st != "hover" else BG.lightened(0.1)
		sb.content_margin_left = 24
		sb.content_margin_right = 8
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		if up:
			sb.border_width_bottom = 2
		else:
			sb.border_width_top = 2
		sb.border_color = CHEVRON
		add_theme_stylebox_override(st, sb)


func _draw() -> void:
	var cy := size.y * 0.5
	var d := 4.0 if up else -4.0                         # freccia verso la voce nascosta
	var pts := PackedVector2Array([Vector2(8.0, cy + d), Vector2(13.0, cy - d), Vector2(18.0, cy + d)])
	draw_polyline(pts, CHEVRON, 2.0)
