class_name ChunkReader

var stream: StreamPeerBuffer

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
	stream.seek(stream.get_position() + size)

func skip_chunky() -> void:
	skip(CHUNKY_HEADER_SIZE)

func has_data() -> bool:
	return stream.get_position() < stream.get_size()

func read_str() -> String:
	# TODO don't read past the end of the chunks
	var l := stream.get_u32()
	if not l:
		return ""
	return stream.get_data(l)[1].get_string_from_utf8()

func read_str_utf16() -> String:
	var l := stream.get_u32()
	if not l:
		return ""
	return stream.get_data(2 * l)[1].get_string_from_utf16()

func read_8() -> int: return stream.get_8()
func read_u8() -> int: return stream.get_u8()
func read_16() -> int: return stream.get_16()
func read_u16() -> int: return stream.get_u16()
func read_32() -> int: return stream.get_32()
func read_u32() -> int: return stream.get_u32()
func read_float() -> float: return stream.get_float()
func read_vec2() -> Vector2: return Vector2(read_float(), read_float())
func read_vec3() -> Vector3: return Vector3(read_float(), read_float(), read_float())
func read_data(size: int) -> PackedByteArray: return stream.get_data(size)[1]

func read_folder(header: ChunkHeader) -> ChunkReader:
	var data := read_data(header.size)
	return ChunkReader.from_bytes(data)

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
