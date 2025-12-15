class_name Mod

var config_path: String
var files_root: String:
	get: return config_path.get_base_dir()
var name: String
var ui_name: String
var description: String
var folder: String
var version: String
var require_engine := true
var required_mods: PackedStringArray
var sources: Array[SourceConfig] = []

class SourceConfig:
	var path: String
	var root_folder: String
	var is_archive: bool

const SECTION_GLOBAL := "global"
const COMMMON := 'common'

static func make_engine_mod(folders: PackedStringArray) -> Mod:
	var result := Mod.new()
	result.name = "engine"
	result.ui_name = "Engine"
	for folder in folders:
		for f in DirAccess.get_directories_at(folder):
			if f.to_lower() == "engine":
				result.folder = f
				result.config_path = folder.path_join("engine.module")
				break
		if result.folder != "":
			break
	if result.folder == "":
		return null
	for path in [
		"%LOCALE%/EnginLoc",
		"Engine-New",
		"Engine",
	]:
		var source := SourceConfig.new()
		source.path = result.folder.path_join(path + ".sga")
		source.root_folder = "data"
		source.is_archive = true
		result.sources.append(source)
	return result

func load(path: String, lang: String = 'english') -> Error:
	var config := IniFile.new()
	config_path = path
	name = path.get_file().get_basename()
	var err := config.load(path)
	if err != Error.OK:
		GsqLogger.error('Cannot parse %s: %s', [path, err])
		return err
	ui_name = config.get_value(SECTION_GLOBAL, "uiname", name)
	description = config.get_value(SECTION_GLOBAL, "description")
	folder = config.get_value(SECTION_GLOBAL, "modfolder")
	version = config.get_value(SECTION_GLOBAL, "modversion")
	if not DirAccess.dir_exists_absolute(path.get_base_dir().path_join(folder)):
		GsqLogger.error('Cannot find folder %s', [folder])
		return Error.ERR_FILE_NOT_FOUND
	require_engine = bool(config.get_value(SECTION_GLOBAL, "RequireEngine", true))
	for section_name in config.sections:
		var section_root_folder := "data"
		if section_name != SECTION_GLOBAL:
			var section_parts := section_name.split(':', true, 1)
			var section_lang: String = section_parts[1].to_lower()
			section_root_folder = section_parts[0].to_lower()
			if not (section_lang == COMMMON or section_lang == lang):
				continue
		var config_section : Dictionary = config.sections[section_name]
		var last_idx := -1
		var last_key := ''

		for key: String in config_section:
			if "." not in key:
				continue
			var parts := key.split(".", true, 1)
			if len(parts) < 2:
				continue
			var group_key := parts[0].to_lower()
			var item_idx := parts[1].to_int()
			if last_key != group_key:
				last_idx = 0
			if item_idx != last_idx + 1:
				GsqLogger.error('Error parsing mod %s: key "%s.%s" is out of order', [path, group_key, item_idx])
				return Error.ERR_PARSE_ERROR
			last_idx = item_idx
			last_key = group_key

			var value: String = config_section[key]
			if group_key == "requiredmod":
				required_mods.append(value)
				continue
			var source := SourceConfig.new()
			if section_name == SECTION_GLOBAL:
				source.path = folder.path_join(value + ".sga")
				source.is_archive = true
			else:
				source.path = value
				source.is_archive = group_key == "archive"
			source.root_folder = section_root_folder
			sources.append(source)	
	return Error.OK
