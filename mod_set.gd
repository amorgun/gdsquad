class_name ModSet

enum TextureLevel {HIGH}
const _TextureLevelNames = {TextureLevel.HIGH: "Full"}

enum SoundLevel {HIGH, MEDIUM, LOW}
const _SoundLevelNames = {SoundLevel.HIGH: "Full", SoundLevel.MEDIUM: "Med", SoundLevel.LOW: "Low"}

enum ModelLevel {HIGH, MEDIUM, LOW}
const _ModelLevelNames = {ModelLevel.HIGH: "High", ModelLevel.MEDIUM: "Medium", ModelLevel.LOW: "Low"}

var mods: Array[Mod] = []
var main_mod: Mod:
	get:
		return mods[0]
var sources: Array[Source] = []
var _arcive_cache: Dictionary[String, Variant] = {}

static func capitalize(s: String) -> String:
	return s[0].to_upper() + s.substr(1)

static func try_find_path(root: String, path: String) -> String:
	var default_result := root.path_join(path).simplify_path()
	if FileAccess.file_exists(default_result) or DirAccess.dir_exists_absolute(default_result):
		return default_result
	var path_parts: PackedStringArray = path.simplify_path().split("/")
	var curr := DirAccess.open(root)
	if curr == null:
		return default_result
	if not curr.is_case_sensitive(""):
		return default_result
	var num_parts_found := 0
	var found_file_path: String
	for part in path_parts:
		var lookup := find_child_case_insensitive(curr, part)
		var child_name: String = lookup[0]
		if child_name == "":
			break
		num_parts_found += 1
		var is_folder: bool = lookup[1]
		if is_folder:
			curr.change_dir(child_name)
	if num_parts_found == len(path_parts):
		return curr.get_current_dir().path_join(found_file_path)
	return curr.get_current_dir().path_join("/".join(path_parts.slice(num_parts_found))).path_join(found_file_path)

static func find_child_case_insensitive(parent: DirAccess, child: String, parent_dir: DirAccess = null) -> Array:  # child_name, is_folder
	for p in [child, child.to_lower(), child.to_upper(), capitalize(child)]:
			if parent.dir_exists(p):
				return [p, true]
			if parent.file_exists(p):
				return [p, false]
	for d in parent.get_directories():
		if d.to_lower() == child:
			return [d, true]
	for d in parent.get_files():
		if d.to_lower() == child:
			return [d, false]
	return ['', false]

static func interpolate_path(
	path: String,
	lang: String,
	texture_level: TextureLevel,
	sound_level: SoundLevel,
	model_level: ModelLevel,
) -> String:
	path = path.replace("%LOCALE%", "Locale/" + capitalize(lang))
	path = path.replace("%TEXTURE-LEVEL%", _TextureLevelNames[texture_level])
	path = path.replace("%SOUND-LEVEL%", _SoundLevelNames[sound_level])
	path = path.replace("%MODEL-LEVEL%", _ModelLevelNames[model_level])
	return path

static func get_real_path(path: String) -> PackedStringArray:
	if ':' not in path:
		return ["data", path]
	var path_parts := path.split(":", true, 1)
	if len(path_parts) != 2:
		path_parts.append("")
	return path_parts


class ModPath:
	var path: String = ""
	var root_folder: String = ""

	static var ROOT := ModPath.new()

	static func from_parts(root_folder: String, ...path_parts: Array) -> ModPath:
		var result := ModPath.new()
		result.path = "/".join(path_parts)
		result.root_folder = root_folder
		return result

	static func from_path(p: String) -> ModPath:
		if p == "":
			return ROOT
		var path_parts = ModSet.get_real_path(p)
		var result := ModPath.new()
		result.path = path_parts[1]
		result.root_folder = path_parts[0]
		return result

	func join(other: String) -> ModPath:
		var result := ModPath.from_parts(root_folder)
		result.path = path.path_join(other) if path != "" else other
		return result

	var full_path: String:
		get: return "%s:%s" % [root_folder, path]

	func _to_string() -> String:
		if is_root():
			return "ROOT"
		if root_folder:
			return full_path
		return path

	func is_root() -> bool:
		return self == ROOT

	func get_extension() -> String:
		return path.get_extension()


class Source:
	var declared_path: String
	var effective_path: String
	var effective_relative_path: String
	var root_folder_name: String
	var packed: bool
	var mod: Mod:
		get: return _mod_ref.get_ref()
	var _mod_ref: WeakRef  # Mod
	var mod_set: ModSet:
		get: return _mod_set_ref.get_ref()
	var _mod_set_ref: WeakRef  # ModSet
	var exists: bool:
		get:
			if packed:
				return FileAccess.file_exists(effective_path) 
			return DirAccess.dir_exists_absolute(effective_path)

	func _to_string():
		return "Source({0}, {1})".format([mod.folder, declared_path])

	static func create(
		declared_path: String,
		root_folder_name: String,
		mod: Mod,
		mod_set: ModSet,
		lang: String,
		texture_level: TextureLevel,
		sound_level: SoundLevel,
		model_level: ModelLevel,
	) -> Source:
		var result := Source.new()
		result._mod_ref = weakref(mod)
		result._mod_set_ref = weakref(mod_set)
		result.declared_path = declared_path
		result.effective_relative_path = ModSet.interpolate_path(declared_path, lang, texture_level, sound_level, model_level)
		result.root_folder_name = root_folder_name.to_lower()
		result.effective_path = ModSet.try_find_path(mod.files_root, result.effective_relative_path)
		result.packed = declared_path.get_extension().to_lower() == "sga"
		return result

	func get_directories_unpacked(path: ModSet.ModPath) -> PackedStringArray:
		var result: PackedStringArray
		if path == ModSet.ModPath.ROOT:
			result.append(root_folder_name)
			return result
		if path.root_folder != root_folder_name:
			return result
		var real_path := effective_path.path_join(path.path)
		if not DirAccess.dir_exists_absolute(real_path):
			return result
		return DirAccess.get_directories_at(real_path)

	func get_files_unpacked(path: ModSet.ModPath) -> PackedStringArray:
		var result: PackedStringArray
		if path == ModSet.ModPath.ROOT:
			return result
		if path.root_folder != root_folder_name:
			return result
		var real_path := effective_path.path_join(path.path)
		if not DirAccess.dir_exists_absolute(real_path):
			return result
		return DirAccess.get_files_at(real_path)

	func get_directories_packed(path: ModSet.ModPath) -> PackedStringArray:
		if path == ModSet.ModPath.ROOT:
			return [root_folder_name]
		if path.root_folder != root_folder_name:
			return []
		var folder := mod_set.find_packed_folder(effective_path, path.path)
		return folder.folders.keys() if folder != null else []

	func get_files_packed(path: ModSet.ModPath) -> PackedStringArray:
		if path == ModSet.ModPath.ROOT:
			return []
		if path.root_folder != root_folder_name:
			return []
		var folder := mod_set.find_packed_folder(effective_path, path.path)
		return folder.files.keys() if folder != null else []

class FilePath:
	var source: Source
	var mod_path: ModPath
	var real_path: String
	var packed: bool:
		get: return source.packed
	var _packed_info: SgaArchive.File
	
	func read_bytes() -> PackedByteArray:
		if packed:
			var file := FileAccess.open(real_path, FileAccess.READ)
			file.seek(_packed_info.data_offset)
			var data := file.get_buffer(_packed_info.compressed_size)
			if _packed_info.compressed_size != _packed_info.decompressed_size:
				if _packed_info.decompressed_size:
					data = data.decompress(_packed_info.decompressed_size, FileAccess.CompressionMode.COMPRESSION_DEFLATE)
				else:
					data = data.decompress_dynamic(-1, FileAccess.CompressionMode.COMPRESSION_DEFLATE)
			return data
		var file := FileAccess.open(real_path, FileAccess.READ)
		return file.get_buffer(file.get_length())

func load(
	path: String,
	extra_lookup_folders: PackedStringArray = [],
	lang: String = "english",
	texture_level: TextureLevel = TextureLevel.HIGH,
	sound_level: SoundLevel = SoundLevel.HIGH,
	model_level: ModelLevel = ModelLevel.HIGH,
) -> Error:
	var root := Mod.new()
	var err := root.load(path, lang)
	mods.clear()
	mods.append(root)
	if err != Error.OK: return err
	var available_modules: Dictionary[String, String] = {}
	var modules_dirs: PackedStringArray = [path.get_base_dir()]
	modules_dirs.append_array(extra_lookup_folders)
	for modules_dir_path in modules_dirs:
		var modules_dir := DirAccess.open(modules_dir_path)
		if modules_dir == null:
			print("No FOLDER %s" % modules_dir_path)
			continue
		for module_path in modules_dir.get_files():
			if module_path.get_extension().to_lower() != "module":
				continue
			var module_name := module_path.get_file().get_basename().to_lower() 
			if module_name in available_modules:
				continue
			available_modules[module_name] = modules_dir_path.path_join(module_path)
	for required_name: String in root.required_mods:
		var required_full_path = available_modules.get(required_name.to_lower())
		if required_full_path == null:
			GsqLogger.warning("Cannot find mod %s", [required_name])
			continue
		var required_mod := Mod.new()
		var r_err := required_mod.load(required_full_path)
		if r_err != Error.OK: GsqLogger.warning("Cannot load mod %s: %s", [required_full_path, r_err])
		mods.append(required_mod)
	if root.require_engine:
		var engine_mod := Mod.make_engine_mod(modules_dirs)
		if engine_mod == null:
			GsqLogger.error("Mod %s: cannot find Engine", [root.config_path])
		else:
			mods.append(engine_mod)
	sources.clear()
	for mod in mods:
		var make_source := func (path: String, root_folder: String, inside_mod: bool = false) -> Source:
			return Source.create(mod.folder.path_join(path) if inside_mod else path, root_folder, mod, self, lang, texture_level, sound_level, model_level)
		sources.append(make_source.call("Data", "data", true))
		sources.append(make_source.call("Movies", "movies", true))
		sources.append(make_source.call("%LOCALE%", "locale", true))
		for s in mod.sources:
			sources.append(make_source.call(s.path, s.root_folder))
	return Error.OK

func load_archive_meta(source: Source) -> void:
	if not source.packed:
		return
	if source.effective_path not in _arcive_cache:
		var archive := SgaArchive.new()
		archive.load_meta(source.effective_path)
		_arcive_cache[source.effective_path] = archive

func find_packed_folder(sga_path: String, path: String) -> SgaArchive.Folder:
	var archive: SgaArchive = _arcive_cache[sga_path]
	return archive.find_folder(path)

func locate_file(path: ModSet.ModPath) -> FilePath:
	var locations := get_all_file_locations(path.root_folder, path.path, 1)
	return locations[0] if len(locations) > 0 else null

func locate_data(path: String) -> FilePath:
	var locations := get_all_file_locations("data", path)
	return locations[0] if len(locations) > 0 else null

func get_all_file_locations(root_folder: String, path: String, max_locations: int = -1) -> Array[FilePath]:
	var file_folder: String = path.get_base_dir()
	var file_name: String = path.get_file()
	var res: Array[FilePath] = []
	for source in sources:
		if not source.exists:
			continue
		if root_folder != source.root_folder_name:
			continue
		if source.packed:
			var folder := find_packed_folder(source.effective_path, file_folder)
			if folder == null:
				continue
			var file_data: SgaArchive.File = folder.files.get(file_name.to_lower())
			if file_data == null:
				continue
			var loc = FilePath.new()
			loc.source = source
			loc.mod_path = ModPath.from_parts(root_folder, path)
			loc.real_path = source.effective_path
			loc._packed_info = file_data
			res.append(loc)
			if max_locations > 0 and len(res) >= max_locations:
				return res
		else:
			var real_path := try_find_path(source.effective_path, path)
			if not FileAccess.file_exists(real_path):
				continue
			var loc = FilePath.new()
			loc.source = source
			loc.mod_path = ModPath.from_parts(root_folder, path)
			loc.real_path = real_path
			res.append(loc)
			if max_locations > 0 and len(res) >= max_locations:
				return res
	return res
