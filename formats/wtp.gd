class_name WtpParser

var rtx_parser := RtxParser.new()

enum Channel {
	DEFAULT = -1,
	PRIMARY = 0,
	SECONDARY = 1,
	TRIM = 2,
	WEAPONS = 3,
	EYES = 4,
	DIRT = 5,
}

class TeamcolorInfo:
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

func parse(data: PackedByteArray) -> TeamcolorInfo:
	var reader := ChunkReader.from_bytes(data)
	reader.skip_chunky()
	var current_chunk := reader.read_header("FOLDTPAT")
	if current_chunk == null: return null
	current_chunk = reader.read_header("DATAINFO")
	if current_chunk == null: return null
	var width := reader.read_u32()
	var height := reader.read_u32()
	var result := TeamcolorInfo.new()
	while reader.has_data():
		current_chunk = reader.read_header()
		if current_chunk == null: return null
		match current_chunk.typeid:
			"DATAPTLD":
				var layer_in := reader.read_u32()
				var data_size := reader.read_u32()
				var image_data := RtxParser.create_tga_data(reader.stream, data_size, width, height, true)
				var image := Image.new()
				image.load_tga_from_buffer(image_data)
				result.channels[layer_in] = image
			"FOLDIMAG":
				current_chunk = reader.read_header("DATAATTR")
				if current_chunk == null: return null
				var image_format := reader.read_u32()
				var image_width := reader.read_u32()
				var image_height := reader.read_u32()
				var num_mips := reader.read_u32()
				current_chunk = reader.read_header("DATADATA")
				if current_chunk == null: return null
				var image_data := RtxParser.create_tga_data(reader.stream, current_chunk.size, image_width, image_height, false)
				var image := Image.new()
				image.load_tga_from_buffer(image_data)
				result.channels[Channel.DEFAULT] = image
			_: reader.skip(current_chunk.size)
	return result
