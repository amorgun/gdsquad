class_name SgbParser

var mod: ModSet
var num_tiles_X: int
var num_tiles_Z: int
var cell_size: int
var center_cell_idx_X: int
var center_cell_idx_Z: int
var tile_size: int
var tile_meshes: Array[Mesh]
var loaded_materials: Dictionary[String, Variant] = {}

var decals: Array[DecalData] = []
var decal_textures: Dictionary[int, ImageTexture] = {}

const MAP_DECAIL_LAYER = 4

class MapData:
	var num_players: int
	var mapsize: int
	var mod_name: String
	var map_name: String
	var scenario_name: String

class DecalData:
	var id: int
	var decal_idx: int
	var x: float
	var z: float
	var size: float
	var angle: float

static func create(mod: ModSet) -> SgbParser:
	var result := SgbParser.new()
	result.mod = mod
	return result

func ensure(condition: bool, message: String, args: Array = [], level: Logging.LogLevel = Logging.LogLevel.INFO) -> void:
	if not condition:
		GsqLogger.log(level, message % args)

func CH_WMHDDATA(reader: ChunkReader) -> MapData:  # Map Data
	var res := MapData.new()
	res.num_players = reader.read_u32()
	res.mapsize = reader.read_u32()
	res.mod_name = reader.read_str()
	res.map_name = reader.read_str_utf16()
	res.scenario_name = reader.read_str_utf16()
	reader.skip(4)  # unknown
	return res

func locate_image(path: String) -> ModSet.FilePath:
	var image_file := mod.locate_data(path + '.tga')
	if image_file == null:
		image_file = mod.locate_data(path + '.dds')
	return image_file

func load_terrain(reader: ChunkReader, ground_image: Image):
	# WARNING: all distances except specifically stated are NOT in m. 
	var current_chunk := reader.read_header("FOLDTERR")

	current_chunk = reader.read_header("FOLDTFAC")
	current_chunk = reader.read_header("DATAVDAT")  # Ground Data
	center_cell_idx_X = reader.read_u32()  # position offset of center (u)
	center_cell_idx_Z = reader.read_u32()  # position offset of center (u)
	cell_size = reader.read_float()  # size of a cell in m (sampling rate)
	reader.skip(4)  # 1
	var height_scale := reader.read_float()  # height factor : height in m = _heightscale * stored value
	reader.skip(4)  # 30
	var num_cells_X := reader.read_u32()  # nbr of cells (vertex nbr is +1)
	var num_cells_Z  := reader.read_u32()  # nbr of cells (vertex nbr is +1)
	reader.skip(8)  # 8 and 2	
	var num_tile_cells := reader.read_u32() # 16, tile size expressed in dots (not m)
	tile_size = cell_size * num_tile_cells
	var tile_texture_repeat := reader.read_u32()  # nbr of texture repeat in a tile
	reader.skip(6)  # float 0 => 1.0 and 2 unknown bytes

	current_chunk = reader.read_header("FOLDCHAN")
	current_chunk = reader.read_header("DATAHMAP")  # Heigh Map
	var height_size_X := reader.read_u32()  # num_cells_X + 1
	var height_size_Z := reader.read_u32()  # num_cells_Z + 1
	var height_data := reader.read_data(height_size_X * height_size_Z)
	print('center_cell_idx=(%s %s) num_cells=(%s %s) hmap=(%s %s) hdata=(size=%s) ' % [center_cell_idx_X, center_cell_idx_Z, num_cells_X, num_cells_Z, height_size_X, height_size_Z, len(height_data)])
	
	current_chunk = reader.read_header("DATATTYP")  # Terrain Type
	reader.skip(4)  # unk
	var _footfallSizeX := reader.read_u32()
	var _footfallSizeZ := reader.read_u32()
	var footfallData := reader.read_data(_footfallSizeX * _footfallSizeZ)
	var _coverSizeX := reader.read_u32()
	var _coverSizeZ := reader.read_u32()
	var coverData := reader.read_data(_coverSizeX * _coverSizeZ)
	
	current_chunk = reader.read_header("DATAIMAP")  # Impass
	var _imapSizeX := reader.read_u32()
	var _imapSizeZ := reader.read_u32()
	var imap_data := reader.read_data(_imapSizeX * _imapSizeZ)
	
	current_chunk = reader.read_header("DATADETT")  # Tex Tiles
	var num_tiles := reader.read_u32()
	num_tiles_X = num_cells_X / num_tile_cells
	num_tiles_Z = num_cells_Z / num_tile_cells
	var detail_index_data := reader.read_data(4 * num_tiles)

	current_chunk = reader.read_header("DATADSHD")  # Tex Tile FileLinks
	var num_detail_textures := reader.read_u32()
	var detail_texture_paths: Dictionary[int, String] = {}
	for i in num_detail_textures:
		var path := reader.read_str()
		var index := reader.read_32()
		detail_texture_paths[index] = path
	
	current_chunk = reader.read_header("DATAEFFC")
	reader.skip(current_chunk.size)

	current_chunk = reader.read_header("DATAHRZN")
	reader.skip(current_chunk.size)
	
	current_chunk = reader.read_header("FOLDDECL")  # Decals
	current_chunk = reader.read_header("DATASMAP")  # Decal links
	var num_decal_links := reader.read_u32()
	var decal_links: Dictionary[int, String] = {}
	for i in num_decal_links:
		var decal_path := reader.read_str()
		var decal_id := reader.read_32()
		decal_links[decal_id] = decal_path
	
	current_chunk = reader.read_header("DATAENTY")
	var num_decals := reader.read_u32()
	decals.resize(num_decals)
	for i in num_decals:
		var decal := DecalData.new()
		decal.id = reader.read_u32()
		decal.decal_idx = reader.read_32()
		decal.x = reader.read_float()
		decal.z = reader.read_float()
		decal.size = reader.read_float()
		decal.angle = reader.read_float()
		decals[i] = decal
	
	var ground_texture := ImageTexture.create_from_image(ground_image)
	var tile_materials: Dictionary[int, StandardMaterial3D] = {}
	for detail_idx in detail_texture_paths:
		var detail_path := detail_texture_paths[detail_idx]
		var material := StandardMaterial3D.new()
		material.albedo_texture = ground_texture
		var image_file := locate_image(detail_path)
		if image_file != null:
			var detail_image := image_file.read_image()
			material.detail_enabled = true
			material.detail_albedo = ImageTexture.create_from_image(detail_image)
			material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
			material.uv2_scale = Vector3(tile_texture_repeat, tile_texture_repeat, tile_texture_repeat)
			material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		tile_materials[detail_idx] = material

	tile_meshes.resize(num_tiles)
	var mesh_vertex_array: PackedVector3Array = []
	mesh_vertex_array.resize((num_tile_cells + 1) * (num_tile_cells + 1))
	var mesh_uv2_array: PackedVector2Array = []  # UV1 - ground, UV2 - detail
	mesh_uv2_array.resize((num_tile_cells + 1) * (num_tile_cells + 1))
	
	var cell_idx := 0
	var pos_x := 0.
	var pos_z := 0.
	var pos_u2 := 0.
	var pos_v2 := 0.
	var uv2_step := 1. / (num_tile_cells + 1)
	for cell_X in num_tile_cells + 1:
		pos_z = 0
		pos_v2 = 1
		for cell_Z in num_tile_cells + 1:
			mesh_vertex_array[cell_idx].x = pos_x
			mesh_vertex_array[cell_idx].z = pos_z
			mesh_uv2_array[cell_idx].x = pos_u2
			mesh_uv2_array[cell_idx].y = pos_v2
			cell_idx += 1
			pos_z += cell_size
			pos_v2 -= uv2_step
		pos_u2 += uv2_step
		pos_x += cell_size
		
	var mesh_index_array:PackedInt32Array = []
	mesh_index_array.resize(6 * num_tile_cells * num_tile_cells)
	cell_idx = 0
	for cell_X in num_tile_cells:
		for cell_Z in num_tile_cells:
			mesh_index_array.append(cell_idx)
			mesh_index_array.append(cell_idx + num_tile_cells + 1)
			mesh_index_array.append(cell_idx + 1)
			mesh_index_array.append(cell_idx + 1)
			mesh_index_array.append(cell_idx + num_tile_cells + 1)
			mesh_index_array.append(cell_idx + num_tile_cells + 2)
			cell_idx += 1
		cell_idx += 1
	
	var mesh_uv_array: PackedVector2Array = []  # UV1 - ground, UV2 - detail
	mesh_uv_array.resize((num_tile_cells + 1) * (num_tile_cells + 1))
	var uv_step_X := 1. / (num_cells_X + 1)
	var uv_positions_X: PackedFloat32Array = []
	uv_positions_X.resize(num_cells_X + 1)
	for i in num_cells_X:
		uv_positions_X[i + 1] = uv_positions_X[i] + uv_step_X
	var uv_step_Z := 1. / (num_cells_Z + 1)
	var uv_positions_Z: PackedFloat32Array = []
	uv_positions_Z.resize(num_cells_Z + 1)
	uv_positions_Z[0] = 1
	for i in num_cells_Z:
		uv_positions_Z[i + 1] = uv_positions_Z[i] - uv_step_Z

	var tile_idx := 0
	var hmap_row_offset := num_cells_X - num_tile_cells
	for tile_X in num_tiles_X:
		pos_z = 0
		for tile_Z in num_tiles_Z:
			var mesh := ArrayMesh.new()
			var hmap_position := (tile_Z * height_size_X + tile_X) * num_tile_cells
			cell_idx = 0
			for cell_Z in num_tile_cells + 1:
				cell_idx = cell_Z
				for cell_X in num_tile_cells + 1:
					mesh_vertex_array[cell_idx].y = height_data[hmap_position] * height_scale  # height_data is transposed
					cell_idx += num_tile_cells + 1
					hmap_position += 1
				hmap_position += hmap_row_offset
			cell_idx = 0
			var uv_idx_X := tile_X * num_tile_cells
			var uv_idx_Z := tile_Z * num_tile_cells
			for cell_X in num_tile_cells + 1:
				for cell_Z in num_tile_cells + 1:
					mesh_uv_array[cell_idx].x = uv_positions_X[uv_idx_X]
					mesh_uv_array[cell_idx].y = uv_positions_Z[uv_idx_Z]
					cell_idx += 1
					uv_idx_Z += 1
				uv_idx_X += 1
				uv_idx_Z -= num_tile_cells + 1
			var surface_array := []
			surface_array.resize(Mesh.ARRAY_MAX)
			surface_array[Mesh.ARRAY_VERTEX] = mesh_vertex_array
			surface_array[Mesh.ARRAY_TEX_UV] = mesh_uv_array
			surface_array[Mesh.ARRAY_TEX_UV2] = mesh_uv2_array
			surface_array[Mesh.ARRAY_INDEX] = mesh_index_array
			var surf_tool := SurfaceTool.new()
			surf_tool.create_from_arrays(surface_array, Mesh.PRIMITIVE_TRIANGLES)
			surf_tool.generate_normals()
			surf_tool.generate_tangents()
			surf_tool.commit(mesh)
			var detail_tile_ids := tile_Z * num_tiles_X + tile_X
			var material := tile_materials[detail_index_data.decode_u32(detail_tile_ids * 4)]
			mesh.surface_set_material(0, material)
			tile_meshes[tile_idx] = mesh
			pos_z += cell_size
			tile_idx += 1
		pos_x += cell_size

	for decal_idx in decal_links:
		var image_file := locate_image(decal_links[decal_idx])
		if image_file == null:
			continue
		decal_textures[decal_idx] = ImageTexture.create_from_image(image_file.read_image())

	for decail_data in decals:
		var decail := Decal.new()

func parse(data: PackedByteArray, ground_image: Image) -> void:
	var reader := ChunkReader.from_bytes(data)
	reader.skip_chunky()
	var current_chunk := reader.read_header("FOLDSCEN")
	current_chunk = reader.read_header("DATAWMHD")
	var map_data := CH_WMHDDATA(reader)
	reader.read_header("FOLDWSTC")
	load_terrain(reader, ground_image)
	
	while reader.has_data():  # Read Chunks Until End Of File
		current_chunk = reader.read_header()
		match current_chunk.typeid:
			#"DATASSHR": self.CH_DATASSHR(reader)  # DATASSHR - Texture Data
			#"FOLDTXTR":  # FOLDTXTR - Internal Texture
				#internal_textures[current_chunk.name] = self.CH_FOLDTXTR(reader, current_chunk.name)
			#"FOLDSHDR":  # FOLDSHDR - Internal Material
				#mat = self.CH_FOLDSHDR(reader, current_chunk.name, internal_textures)
				#props.setup_property(mat, 'internal', True)
			#"DATASKEL": self.CH_DATASKEL(reader, xref=False)  # DATASKEL - Skeleton Data
			#"FOLDMSGR": CH_FOLDMSGR(reader)  # FOLDMSGR - Mesh Data
			#"DATAMARK": self.CH_DATAMARK(reader)  # DATAMARK - Marker Data
			#"FOLDANIM": self.CH_FOLDANIM(reader)  # FOLDANIM - Animations
			#"DATACAMS": self.CH_DATACAMS(reader)  # DATACAMS - Cameras
			_:
				#print(current_chunk.typeid)
				reader.skip(current_chunk.size)

func setup_map(map: Node3D) -> void:
	for c in map.get_children():
		map.remove_child(c)
		c.queue_free()
	var tile_idx := 0
	var map_center_offset_X := cell_size * center_cell_idx_X - cell_size / 2
	var map_center_offset_Z := cell_size * center_cell_idx_Z - cell_size / 2
	var tile_position_X := -map_center_offset_X
	var tile_position_Z := -map_center_offset_Z
	var tiles_root := Node3D.new()
	tiles_root.name = "Tiles"
	map.add_child(tiles_root)
	for tile_X in num_tiles_X:
		tile_position_Z = -map_center_offset_Z
		for tile_Z in num_tiles_Z:
			var node := MeshInstance3D.new()
			node.mesh = tile_meshes[tile_idx]
			node.name = "Tile %s" % tile_idx
			node.position.x = tile_position_X
			node.position.z = tile_position_Z
			node.set_layer_mask_value(MAP_DECAIL_LAYER, 1)
			tiles_root.add_child(node)
			tile_idx += 1
			tile_position_Z += tile_size
		tile_position_X += tile_size
	var decal_root := Node3D.new()
	decal_root.name = "Decals"
	map.add_child(decal_root)
	var decal_idx := 0
	for decal_data in decals:
		var decal_texture: ImageTexture = decal_textures.get(decal_data.decal_idx)
		if decal_texture == null:
			continue
		var decal := Decal.new()
		decal.texture_albedo = decal_texture
		decal.position.x = decal_data.x
		decal.position.z = decal_data.z
		decal.rotation.y = -decal_data.angle
		decal.size.x = decal_texture.get_width() * decal_data.size
		decal.size.z = decal_texture.get_height() * decal_data.size
		#decal.scale.x = 1. / decal_data.size
		#decal.scale.z = 1. / decal_data.size
		decal.size.y = 100
		decal.sorting_offset = (10 + decal_idx) * 10000000.
		#decal.distance_fade_enabled = true
		#decal.distance_fade_begin = 1000
		decal.sorting_use_aabb_center = true
		decal_root.add_child(decal)
		decal_idx += 1
