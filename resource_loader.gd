class_name ModResourceLoader

var mod: ModSet

static func create(mod: ModSet) -> ModResourceLoader:
	var res := ModResourceLoader.new()
	res.mod = mod
	return res

func fload_bytes(file: ModSet.FilePath) -> PackedByteArray:
	return file.read_bytes()

func fload_text(file: Variant) -> String:
	return fload_bytes(file).get_string_from_utf8()

func fload_lua(file: ModSet.FilePath) -> Lua:
	var lua := Lua.new()
	if file == null:
		return lua
	var err := lua.dostring(file.read_bytes().get_string_from_utf8())
	if err != Error.OK:
		GsqLogger.error('Cannot parse lua file "%s": %s', [mod.mod_path, lua.get_error()])
	return lua

func fload_image(file: ModSet.FilePath) -> Image:
	var bytes = file.read_bytes()
	var image := Image.new()
	if len(bytes) == 0:			
		return image
	match file.mod_path.get_extension().to_lower():
		'tga': image.load_tga_from_buffer(bytes)
		'dds': image.load_dds_from_buffer(bytes)
		'png': image.load_png_from_buffer(bytes)
		'bmp': image.load_bmp_from_buffer(bytes)
		'jpg': image.load_jpg_from_buffer(bytes)
		'svg': image.load_svg_from_buffer(bytes)
	return image

func pload_bytes(path: String) -> PackedByteArray:
	return fload_bytes(mod.locate_file(ModSet.ModPath.from_path(path)))

func pload_text(path: String) -> String:
	return fload_text(mod.locate_file(ModSet.ModPath.from_path(path)))

func pload_lua(path: String) -> Lua:
	return fload_lua(mod.locate_file(ModSet.ModPath.from_path(path)))

func pload_image(path: String) -> Image:
	return fload_image(mod.locate_file(ModSet.ModPath.from_path(path)))
