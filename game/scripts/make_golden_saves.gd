extends SceneTree
## Genera i salvataggi di riferimento di schema 3 e 4 (tests/golden/) dal salvataggio REALE di schema 2 (c3q1, giocato dal bot)
## passando per le funzioni di migrazione ufficiali di SaveCodec. Non esiste nel repository un salvataggio v3/v4 scritto da una
## build di quelle versioni: questo e' il file che quelle build avrebbero scritto dalla stessa partita (stesse sezioni, stessi campi).
## Uso (una tantum, il risultato e' versionato): godot --headless --path game --script res://scripts/make_golden_saves.gd

func _init() -> void:
	var src := "res://tests/golden/save_v2_reale_c3q1.sav"
	var dec := SaveCodec.decode(FileAccess.get_file_as_bytes(src))
	if not dec.ok:
		push_error("make_golden_saves: %s non si legge (%s)" % [src, dec.error])
		quit(1)
		return
	var d: Dictionary = dec.data
	d = SaveCodec.migrate_v2_to_v3(d)
	d["schema_version"] = 3
	_write("res://tests/golden/save_v3_reale_c3q1.sav", d)
	d = SaveCodec.migrate_v3_to_v4(d)
	d["schema_version"] = 4
	_write("res://tests/golden/save_v4_reale_c3q1.sav", d)
	quit(0)


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(SaveCodec.encode(d))
	f.close()
	print("scritto ", path, " schema ", d.schema_version)
