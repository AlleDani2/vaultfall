extends SceneTree
## Scrive nel file indicato (argomento utente dopo `--`) la licenza di Godot e i testi delle licenze di terze parti
## incorporate nel motore (obbligo di distribuirli con il gioco). Lanciato da tools/make_release.py:
##   godot --headless --script tools/dump_godot_licenses.gd -- <file di uscita>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "GODOT_LICENSES.txt"
	var t := PackedStringArray()
	t.append("Godot Engine %s" % Engine.get_version_info().get("string", ""))
	t.append("https://godotengine.org\n")
	t.append(Engine.get_license_text())
	t.append("\n\n==================== COMPONENTI DI TERZE PARTI ====================\n")
	var info: Dictionary = Engine.get_license_info()
	for k in info:
		t.append("---- %s ----" % k)
		t.append(str(info[k]) + "\n")
	t.append("\n==================== COPYRIGHT DEI COMPONENTI ====================\n")
	for part in Engine.get_copyright_info():
		t.append("---- %s ----" % part.get("name", ""))
		for c in part.get("parts", []):
			t.append("Files: %s" % ", ".join(c.get("files", [])))
			t.append("Copyright: %s" % "; ".join(c.get("copyright", [])))
			t.append("License: %s\n" % c.get("license", ""))
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(t))
	f.close()
	quit(0)
