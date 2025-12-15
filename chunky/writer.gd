class_name ChunkWriter

var stream: FileAccess
var _chunk_stack: Array = []
var _curr_typeid: String = ""
var _chunk_start_position := 0
var _chunk_data_start_position := 0

static func open(path: String) -> ChunkWriter:
	var result := ChunkWriter.new()
	result.stream = FileAccess.open(path, FileAccess.WRITE)
	return result

func start_chunk(typeid: String, version: int, name: String = "") -> void:
	assert(len(typeid) == 8, 'Incorrect typeid "%s"' % typeid)
	assert(typeid.substr(0, 4) in ["FOLD", "DATA"], 'Incorrect typeid "%s"' % typeid)
	assert(_curr_typeid == "" or _curr_typeid.substr(0, 4) == "FOLD", 'Chunk of type "%s" cannot have children' % _curr_typeid)
	_chunk_stack.append([_curr_typeid, _chunk_start_position, _chunk_data_start_position])
	_curr_typeid = typeid
	_chunk_start_position = stream.get_position()
	stream.store_buffer(typeid.to_ascii_buffer())
	stream.store_32(version)
	stream.store_32(0)  # size
	var name_bytes := name.to_utf8_buffer()
	if name_bytes:
		stream.store_32(len(name_bytes) + 1)
		stream.store_buffer(name_bytes)
		stream.store_8(0)  # \0
	else:
		stream.store_32(0)
	_chunk_data_start_position = stream.get_position()

func end_chunk(typeid: String) -> void:
	var end_pos := stream.get_position()
	stream.seek(_chunk_start_position + 12)
	stream.store_32(end_pos - _chunk_data_start_position)
	stream.seek(end_pos)
	var prev_data = _chunk_stack.pop_back()
	assert(_curr_typeid == typeid, "Expected %s, got %s" % [typeid, _curr_typeid])
	_curr_typeid = prev_data[0]
	_chunk_start_position = prev_data[1]
	_chunk_data_start_position = prev_data[2]

func write_chunky() -> void:
	stream.store_buffer("Relic Chunky".to_ascii_buffer())
	stream.store_32(1706509)
	stream.store_32(1)
	stream.store_32(1)

func write_u32(data: int) -> bool: return stream.store_32(data)
func write_u8(data: int) -> bool: return stream.store_8(data)
func write_float(data: float) -> bool: return stream.store_float(data)
func write_str(data: String) -> bool: return stream.store_32(len(data)) and stream.store_buffer(data.to_utf8_buffer())
func write_padding(size: int) -> bool: 
	var buff: PackedByteArray = []
	buff.resize(size)
	return stream.store_buffer(buff)
func write_data(data: PackedByteArray) -> bool: return stream.store_buffer(data)
