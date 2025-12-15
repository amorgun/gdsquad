class_name RshParser

var rtx_parser := RtxParser.new()

enum Channel {
	DIFFUSE = 0,
	SPECULARITY = 1,
	REFLECTION = 2,
	SELF_ILLUMINATION = 3,
	OPACITY = 4,
}

class MaterialInfo:
	var name: String
	var channels: Dictionary[Channel, Image]

static func CH_FOLDSHDR(reader: ChunkReader, images: Dictionary[String, Image]) -> Dictionary[Channel, Image]:  # Chunk Handler - Material
	var current_chunk := reader.read_header("DATAINFO")
	reader.skip(17)  # num_images + info_bytes

	var channels: Dictionary[Channel, String] = {}
	var result: Dictionary[Channel, Image] = {}
	for i1 in 6:  # always 6
		current_chunk = reader.read_header("DATACHAN")
		var channel_idx := reader.read_u32()
		reader.skip(8)  # method + colour_mask
		var channel_texture_name = reader.read_str()
		reader.skip(12)  # 4 + num_coords + 4
		for i2 in 4:  # always 4, not num_coords
			for ref_idx in 4:
				reader.skip(8)  # x, y
		channels[channel_idx] = channel_texture_name
		if channel_texture_name == "":
			continue
		var image: Image = images.get(channel_texture_name.to_lower())
		if image == null:
			GsqLogger.warning("Cannot find image %s", [channel_texture_name])
		else:
			result[channel_idx] = image
	return result

func parse(data: PackedByteArray) -> MaterialInfo:
	var reader := ChunkReader.from_bytes(data)
	reader.skip_chunky()
	var current_chunk := reader.read_header("FOLDSHRF")  # Skip "Folder SHRF" Header
	if current_chunk == null: return null
	var loaded_textures: Dictionary[String, Image] = {}
	var result: MaterialInfo = null
	while reader.has_data():
		current_chunk = reader.read_header()
		if current_chunk == null: return null
		match current_chunk.typeid:
			"FOLDTXTR":
				var image := rtx_parser.CH_FOLDTXTR(reader)
				image.resource_name = current_chunk.name
				loaded_textures[current_chunk.name.to_lower()] = image
			"FOLDSHDR":
				result = MaterialInfo.new()
				result.name = current_chunk.name
				result.channels = CH_FOLDSHDR(reader, loaded_textures)
			_: reader.skip(current_chunk.size)
	return result
