class_name CoopGuildStore
extends RefCounted
## Salvataggio della partita di gilda, separato dagli slot personali (COOP-2; regole R-SAV di docs/17 §10):
## `<dir>/guild_<id>.sav` con scrittura ATOMICA (file .tmp verificato, poi rinomina) e 3 backup a rotazione.
## L'host salva la gilda autorevole; ogni client ne salva una copia (stesso formato) così chiunque può fare da host
## se l'host originale sparisce (si riparte dalla copia con gseq più alto). Formato: SaveCodec (JSON piena precisione,
## gzip) di {"schema_version": GUILD_FILE_SCHEMA, "guild": CoopGuild.to_dict(), "role": "host"|"copy"}.

const GUILD_FILE_SCHEMA := 1
const BACKUPS := 3
const DEFAULT_DIR := "user://coop"

var dir: String = DEFAULT_DIR


func path_for(guild_id: String) -> String:
	return "%s/guild_%s.sav" % [dir, guild_id.trim_prefix("g_")]


func backup_path(guild_id: String, n: int) -> String:
	return "%s.bak%d" % [path_for(guild_id), n]


static func valid_id(guild_id: String) -> bool:
	return RegEx.create_from_string("^g_[0-9a-f]{12}$").search(guild_id) != null


func save(guild: CoopGuild, role: String) -> Error:
	var gid := guild.guild_id()
	if not valid_id(gid):
		return ERR_INVALID_PARAMETER
	var bytes := SaveCodec.encode({"schema_version": GUILD_FILE_SCHEMA, "role": role, "guild": guild.to_dict()})
	var mk := DirAccess.make_dir_recursive_absolute(dir)
	if mk != OK and not DirAccess.dir_exists_absolute(dir):
		return mk
	var path := path_for(gid)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	var back := FileAccess.get_file_as_bytes(tmp)
	if back != bytes or not SaveCodec.decode(back).ok:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	for n in range(BACKUPS, 1, -1):
		var src := backup_path(gid, n - 1)
		if FileAccess.file_exists(src):
			_replace(src, backup_path(gid, n))
	if FileAccess.file_exists(path):
		_replace(path, backup_path(gid, 1))
	return _replace(tmp, path)


## Carica la gilda (file principale, poi i backup). Ritorna {"ok", "guild": Dictionary, "role", "source", "error"}.
func load_guild(guild_id: String) -> Dictionary:
	if not valid_id(guild_id):
		return {"ok": false, "error": "bad_id"}
	var cands := [[path_for(guild_id), "main"]]
	for n in range(1, BACKUPS + 1):
		cands.append([backup_path(guild_id, n), "bak%d" % n])
	var first := "missing"
	for c in cands:
		if not FileAccess.file_exists(c[0]):
			continue
		var dec := SaveCodec.decode(FileAccess.get_file_as_bytes(c[0]))
		if not dec.ok:
			first = dec.error
			continue
		var d: Dictionary = dec.data
		if int(d.get("schema_version", -1)) > GUILD_FILE_SCHEMA:
			return {"ok": false, "error": "newer"}
		if not (d.get("guild") is Dictionary) or str(d.guild["id"]) != guild_id:
			first = "content"
			continue
		return {"ok": true, "guild": d.guild, "role": str(d.get("role", "copy")), "source": c[1], "error": ""}
	return {"ok": false, "error": first}


## Gilde salvate in questa cartella (id), per «Riprendi la gilda» nella Lobby.
func list_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("guild_") and f.ends_with(".sav"):
			var gid := "g_" + f.trim_prefix("guild_").trim_suffix(".sav")
			if valid_id(gid):
				out.append(gid)
	return out


func delete(guild_id: String) -> void:
	if not valid_id(guild_id):
		return
	for p in [path_for(guild_id)] + range(1, BACKUPS + 1).map(func(n: int) -> String: return backup_path(guild_id, n)):
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _replace(src: String, dst: String) -> Error:
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	return DirAccess.rename_absolute(src, dst)
