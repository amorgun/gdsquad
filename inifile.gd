class_name IniFile

var sections : Dictionary[String, Dictionary] = {}

func load(path: String, comment_prefixes: PackedStringArray = ["#", ";", "--"]) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Error.ERR_FILE_CANT_OPEN
	var section : Dictionary[String, String] = {}
	while f.get_position() < f.get_length():
		var line := f.get_line().strip_edges()
		if not line:
			continue
		var is_comment : bool = false
		for pr in comment_prefixes:
			if line.begins_with(pr):
				is_comment = true
		if is_comment:
			continue
		if line.begins_with("["):
			if not line.ends_with("]"):
				return Error.ERR_FILE_CORRUPT
			var section_name := line.substr(1, len(line) - 2)
			section = {}
			sections[section_name] = section
			continue
		var parts := line.split("=", true, 1)
		if len(parts) != 2:
			return Error.ERR_FILE_CORRUPT
		var val := parts[1].strip_edges().c_unescape()
		section[parts[0].strip_edges().to_lower()] = val
	return Error.OK

func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var data = sections.get(section)
	if data == null:
		return default
	return data.get(key, default)
