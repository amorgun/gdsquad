class_name RtxParser

static func create_tga_data(source: StreamPeerBuffer, data_size: int, width: int, height: int, grayscale: bool = false) -> PackedByteArray:
	var res := StreamPeerBuffer.new()
	# See http://www.paulbourke.net/dataformats/tga/
	res.put_u8(0)  # ID length
	res.put_u8(0)  # file contains no color map
	res.put_u8(3 if grayscale else 2)  # uncompressed grayscale image
	res.put_u16(0); res.put_u16(0); res.put_u8(32)  # Color Map Specification
	res.put_u16(0); res.put_u16(0); res.put_u16(width); res.put_u16(height)
	res.put_u8(8 if grayscale else 32); res.put_u8(0)  # Image Specification.
	res.put_data(source.get_data(data_size)[1])
	return res.data_array

static func create_dds_data(source: StreamPeerBuffer, data_size: int, width: int, height: int, num_mips: int, image_format: int, use_mipmaps: bool) -> PackedByteArray:
	const _dwF_MIPMAP := 0x00020000
	#const _dwF_LINEAR := 0x00080000
	const _DEFAULT_FLAGS := 0x00001007
	var _dxt_flags := _DEFAULT_FLAGS
	if use_mipmaps:
		_dxt_flags |= _dwF_MIPMAP
	const _ddsF_FOURCC := 0x00000004
	const _DOW_DDSCAPS_FLAGS := 0x401008 # _ddscaps_F_TEXTURE | _ddscaps_F_COMPLEX | _ddscaps_F_MIPMAP_S
	const fourCC := {8: "DXT1", 10: "DXT3", 11: "DXT5"}
	var res := StreamPeerBuffer.new()
	res.put_data("DDS ".to_ascii_buffer())
	res.put_32(124); res.put_32(_dxt_flags); res.put_u32(height); res.put_u32(width)
	res.put_u32(0) # data_size
	res.put_u32(0); res.put_u32(num_mips)
	var padding: PackedByteArray = []
	padding.resize(44)
	res.put_data(padding)
	res.put_32(32); res.put_32(_ddsF_FOURCC); res.put_data(fourCC[image_format].to_ascii_buffer())  # pixel format
	res.put_data(padding.slice(0, 20))
	res.put_32(_DOW_DDSCAPS_FLAGS); res.put_32(0);  # ddscaps
	res.put_data(padding.slice(0, 12))
	res.put_data(source.get_data(data_size)[1])
	return res.data_array

static func CH_FOLDTXTR(reader: ChunkReader) -> Image:  # Chunk Handler - Texture
	var current_chunk: ChunkReader.ChunkHeader
	while reader.has_data():
		current_chunk = reader.read_header()
		if current_chunk == null: return null
		match current_chunk.typeid:
			"DATAHEAD": reader.skip(current_chunk.size)  # image_type + num_images
			"DATAINFO": reader.skip(current_chunk.size)
			"FOLDIMAG": break
	current_chunk = reader.read_header("DATAATTR")
	if current_chunk == null: return null
	var image_format := reader.read_32()
	var width := reader.read_u32()
	var height := reader.read_u32()
	var num_mips  := reader.read_u32()
	current_chunk = reader.read_header("DATADATA")
	if current_chunk == null: return null
	var is_tga = image_format == 0 or image_format == 2
	var image := Image.new()
	if is_tga:
		var data := create_tga_data(reader.stream, current_chunk.size, width, height)
		image.load_tga_from_buffer(data)
		image.flip_y()
	else:
		var pos := reader.stream.get_position()
		var data := create_dds_data(reader.stream, current_chunk.size, width, height, num_mips, image_format, true)
		image.load_dds_from_buffer(data)
		if image.is_empty():
			# https://github.com/godotengine/godot/issues/96635#issuecomment-2333630124
			reader.stream.seek(pos)
			data = create_dds_data(reader.stream, current_chunk.size, width, height, num_mips, image_format, false)
			image.load_dds_from_buffer(data)
		image.decompress()
	if image.is_empty():
		return null
	return image

func parse(data: PackedByteArray) -> Image:
	var reader := ChunkReader.from_bytes(data)
	reader.skip_chunky()
	reader.read_header("FOLDTXTR")
	return CH_FOLDTXTR(reader)
