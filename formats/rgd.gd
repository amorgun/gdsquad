class_name Rgd

enum DataType {
	FLOAT = 0,
	INTEGER = 1,
	BOOL = 2,
	STRING = 3,
	WSTRING = 4,
	TABLE = 100,
	NO_DATA = 254,
}

class Parser:
	const HASH_DICT_PATH := "res://addons/gdsquad/formats/RGD_DIC.TXT"
	var hash_dict: Dictionary[int, String]

	func parse(data: PackedByteArray, decode_hashes: bool = true) -> Dictionary:
		var reader := ChunkReader.from_bytes(data)
		reader.skip_chunky()
		var _current_chunk := reader.read_header("DATAAEGD")
		var _hash := reader.read_u32()
		var data_size := reader.read_u32()
		return read_entry(reader, DataType.TABLE, data_size, decode_hashes)

	func parse_file(file: ModSet.FilePath, decode_hashes: bool = true) -> Dictionary:
		return parse(file.read_bytes(), decode_hashes)

	func read_entry(reader: ChunkReader, type_: DataType, data_size: int, decode_hashes: bool) -> Variant:
		var result
		var orig_pos = reader.stream.get_position()
		match type_:
			DataType.TABLE:
				var num_entries = reader.read_u32()
				var entries := []
				var header_size = 4 + num_entries * 12
				for idx in num_entries:
					var hash_ = reader.read_u32()
					var entry_type_ = reader.read_u32()
					var offset = reader.read_u32()
					entries.append([hash_, entry_type_, offset])
				entries.sort_custom(func(a, b): return a[2] < b[2])
				result = {}
				if not num_entries:
					return result
				assert(entries[0][2] == 0)
				for idx in num_entries:
					var entry: Array = entries[idx]
					var entry_end: int = entries[idx + 1][2] if idx < len(entries) - 1 else data_size - header_size
					var key = entry[0] if not decode_hashes else hash_dict.get(entry[0], entry[0])
					result[key] = self.read_entry(reader, entry[1], entry_end - entry[2], decode_hashes)
				return result
			DataType.STRING:
				result = reader.stream.get_data(data_size)[1].get_string_from_ascii()
			DataType.WSTRING:
				var data := PackedByteArray()
				data.append_array(reader.stream.get_data(data_size)[1])
				result = data.get_string_from_utf16()
			DataType.FLOAT:
				result = reader.read_float()
			DataType.INTEGER:
				GsqLogger.debug("HEY THERE IS ACTUALLY AN INT KEY")
				result = reader.read_32()
			DataType.BOOL:
				result = reader.read_u8() != 0
		reader.stream.seek(orig_pos + data_size)
		return result

	func load_hash_dict() -> void:
		var file := FileAccess.open(HASH_DICT_PATH, FileAccess.ModeFlags.READ)
		while file.get_position() < file.get_length():
			var line := file.get_line().strip_edges()
			if not line or line.begins_with("#"):
				continue
			var parts = line.split("=", true, 1)
			hash_dict[parts[0].hex_to_int()] = parts[1]

static func write_file(data: Dictionary, path: String, version: int = 1) -> Error:
	var buff := StreamPeerBuffer.new()
	var res := _write_obj(data, buff)
	var err: Error = res[0]
	if err != Error.OK:
		return err
	var type: DataType = res[1]
	if type != DataType.TABLE:
		GsqLogger.error("Rgd value data must be a table, got %s" % [type_string(typeof(data))])
		return Error.ERR_UNAVAILABLE
	var writer := ChunkWriter.open(path)
	writer.write_chunky()
	writer.start_chunk("DATAAEGD", version)
	writer.write_u32(GDSquadExt.crc32(buff.data_array))
	writer.write_u32(buff.get_size())
	writer.write_data(buff.data_array)
	writer.end_chunk("DATAAEGD")
	return err

static func pad_to(buff: StreamPeerBuffer, pad_unit: int) -> int:
	var pad_width := pad_unit - buff.get_position() % pad_unit
	if pad_width != pad_unit:
		var pad: PackedByteArray
		pad.resize(pad_width)
		buff.put_data(pad)
		return pad_width
	return 0

static func calc_hash(key: Variant) -> int:
	return GDSquadExt.rgd_key_hash(str(key).to_ascii_buffer())

static func _write_obj(data: Variant, buff: StreamPeerBuffer) -> Array:
	var data_type: DataType
	var pad_size: int = 0
	match typeof(data):
		TYPE_DICTIONARY:
			pad_size = pad_to(buff, 4)
			data_type = DataType.TABLE
			buff.put_u32(len(data))
			var header_size := 12 * len(data)
			var header := StreamPeerBuffer.new()
			header.resize(header_size)
			var header_pos := buff.get_position()
			buff.put_data(header.data_array)
			var data_start_pos := buff.get_position()
			var keys: Array = data.keys()
			keys.sort_custom(func(a, b): return calc_hash(a) < calc_hash(b))
			for k in keys:
				var data_offset := buff.get_position() - data_start_pos
				var res := _write_obj(data[k], buff)
				data_offset += res[2]
				var err: Error = res[0]
				if err != Error.OK:
					return [err, data_type, pad_size]
				var key_hash = calc_hash(k)
				header.put_u32(key_hash)
				var item_type: DataType = res[1]
				header.put_u32(item_type)
				header.put_u32(data_offset)
			var end_pos := buff.get_position()
			buff.seek(header_pos)
			buff.put_data(header.data_array)
			buff.seek(end_pos)
		TYPE_STRING:
			var str_buff: PackedByteArray
			if data.begins_with("$") or data.to_ascii_buffer().get_string_from_ascii() != data:
				data_type = DataType.WSTRING
				pad_size = pad_to(buff, 2)
				str_buff = data.to_utf16_buffer()
				str_buff.append(0)
			else:
				data_type = DataType.STRING
				str_buff = data.to_ascii_buffer()
			str_buff.append(0)
			buff.put_data(str_buff)
		TYPE_FLOAT, TYPE_INT:
			pad_size = pad_to(buff, 4)
			data_type = DataType.FLOAT
			buff.put_float(data)
		TYPE_BOOL:
			data_type = DataType.BOOL
			buff.put_u8(1 if data else 0)
		_:
			GsqLogger.error("Cannot write a value or type %s to rgd" % [type_string(typeof(data))])
			return [Error.ERR_UNAVAILABLE, DataType.NO_DATA]
	return [Error.OK, data_type, pad_size]
			
