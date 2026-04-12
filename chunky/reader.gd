class_name ChunkReader

var stream: StreamPeerBuffer
var _warn_not_enough_bytes := 0

class ChunkHeader:
	var typeid: String
	var version: int
	var size: int
	var name: String

	func is_valid_typeid(expected: String) -> bool:
		if expected != typeid:
			GsqLogger.error('Expected TypeId "%s", got "%s"', [expected, typeid])
			return false
		return true

const CHUNKY_HEADER_SIZE := 24
	
static func from_bytes(data: PackedByteArray) -> ChunkReader:
	var result := ChunkReader.new()
	result.stream = StreamPeerBuffer.new()
	result.stream.data_array = data
	return result

func read_header(expected_typeid: String = "") -> ChunkHeader:
	if stream.get_size() == stream.get_position():
		return null
	var res := ChunkHeader.new()
	res.typeid = stream.get_string(8)
	if expected_typeid != "" and not res.is_valid_typeid(expected_typeid):
		return null
	if res.typeid.substr(0, 4) not in ["FOLD", "DATA"]:
		GsqLogger.error('Invalid typeid "%s"', [res.typeid])
		return null
	res.version = stream.get_u32()
	res.size = stream.get_u32()
	res.name = read_str()
	return res

func skip(size: int) -> void:
	stream.seek(stream.get_position() + get_available_size(size))

func skip_chunky() -> void:
	skip(CHUNKY_HEADER_SIZE)

func has_data() -> bool:
	return stream.get_position() < stream.get_size()

func get_available_size(required: int) -> int:
	return mini(required, stream.get_size() - stream.get_position())

func read_str() -> String:
	# TODO don't read past the end of the chunks
	var l := read_u32()
	if not l:
		return ""
	return read_data(l).get_string_from_utf8()

func read_str_utf16() -> String:
	var l := read_u32()
	if not l:
		return ""
	return read_data(2 * l).get_string_from_utf16()

func _read_or_default(size: int, default: Variant, getter: Callable) -> Variant:
	var available := get_available_size(size)
	if available < size:
		if _warn_not_enough_bytes == 0:
			GsqLogger.error("Not enough bytes: has %s, need %s" % [available, size])
		skip(available)
		return default
	return getter.call()

func read_8() -> int: return _read_or_default(1, 0, stream.get_8)
func read_u8() -> int: return _read_or_default(1, 0, stream.get_u8)
func read_16() -> int: return _read_or_default(2, 0, stream.get_16)
func read_u16() -> int: return _read_or_default(2, 0, stream.get_u16)
func read_32() -> int: return _read_or_default(4, 0, stream.get_32)
func read_u32() -> int: return _read_or_default(4, 0, stream.get_u32)
func read_float() -> float: return _read_or_default(4, 0., stream.get_float)
func read_vec2() -> Vector2: return Vector2(read_float(), read_float())
func read_vec3() -> Vector3: return Vector3(read_float(), read_float(), read_float())
func read_data(size: int) -> PackedByteArray: return stream.get_data(get_available_size(size))[1]

func read_chunk(header: ChunkHeader) -> ChunkReader:
	var data := read_data(header.size)
	return ChunkReader.from_bytes(data)

func do_until_eof(size: int, name: String, fn: Callable, chunk_size: int = 16):
	_warn_not_enough_bytes += 1
	for chunk_idx in (size + chunk_size - 1) / chunk_size:
		for i in mini(chunk_size, size - chunk_idx * chunk_size):
			fn.call()
		if not has_data():
			GsqLogger.error("Not enough bytes available to parse array %s" % [name])
			_warn_not_enough_bytes -= 1
			return
	_warn_not_enough_bytes -= 1

static func is_chunky(data: PackedByteArray) -> bool:
	if len(data) < CHUNKY_HEADER_SIZE + 8:
		return false
	const MAGIC := "Relic Chunky"
	if data.slice(0, len(MAGIC)).get_string_from_ascii() != MAGIC:
		return false
	var typeid = data.slice(CHUNKY_HEADER_SIZE, CHUNKY_HEADER_SIZE + 8).get_string_from_ascii()
	if not (
		typeid.begins_with("DATA")
		or typeid.begins_with("FOLD")
	):
		return false
	return true

class ChunkIndex:
	var typeid: String
	var version: int
	var size: int
	var name: String
	var data_start: int
	var data_end: int
	var children: Array[ChunkIndex]

	func is_folder() -> bool:
		return typeid.begins_with("FOLD")


static func build_chunk_index(data: PackedByteArray) -> ChunkIndex:
	var root := ChunkIndex.new()
	var stack := [root]
	var reader := ChunkReader.from_bytes(data)
	root.typeid = "FOLDROOT"
	root.size = len(data)
	root.data_start = 0
	root.data_end = root.size
	reader.skip_chunky()
	while reader.has_data():
		var pos := reader.stream.get_position()
		while pos >= stack[-1].data_end:
			stack.pop_back()
		var chunk := reader.read_header()
		if chunk == null: return null
		var item := ChunkIndex.new()
		item.typeid = chunk.typeid
		item.version = chunk.version
		item.size = chunk.size
		item.name = chunk.name
		item.data_start = reader.stream.get_position()
		item.data_end = item.data_start + item.size
		stack[-1].children.append(item)
		if item.is_folder():
			stack.append(item)
		else:
			reader.skip(chunk.size)
	return root
