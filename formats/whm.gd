class_name WhmParser

class SkinVertice:
	var weights: PackedFloat32Array
	var bones: PackedStringArray

const NUM_BONE_SLOTS := 4

var mod: ModSet
var rsh_parser := RshParser.new()
var meshes: Dictionary[String, Mesh] = {}
var loaded_materials: Dictionary[String, Variant] = {}
var used_files: PackedStringArray = []

static func create(mod: ModSet) -> WhmParser:
	var result := WhmParser.new()
	result.mod = mod
	return result

static func skip_bbox(reader: ChunkReader) -> void:
	reader.skip(61)

class BBox:
	var center: Vector3
	var size: Vector3
	var rotation: Basis

var bbox: BBox

static func read_bbox(reader: ChunkReader) -> BBox:
	reader.read_8()  # bbox_flag
	var res := BBox.new()
	res.center = reader.read_vec3()
	res.size = reader.read_vec3()
	res.rotation = Basis(
		reader.read_vec3(),
		reader.read_vec3(),
		reader.read_vec3(),
	)
	return res

func ensure(condition: bool, message: String, args: Array = [], level: Logging.LogLevel = Logging.LogLevel.INFO) -> void:
	if not condition:
		GsqLogger.log(level, message % args)

func CH_DATASSHR(reader: ChunkReader) -> void:  # CH_DATASSHR > - Chunk Handler - Material Data
	var material_path := reader.read_str()  # -- Read Texture Path

	if material_path in loaded_materials:
		return
	var full_material_path := "%s.rsh" % material_path
	used_files.append(full_material_path)
	var material_data := mod.locate_data(full_material_path)
	if material_data == null:
		GsqLogger.warning('Cannot find material file "%s"', [full_material_path])
		return
	var material_info := rsh_parser.parse(material_data.read_bytes())  # -- create new material
	#if self.wtp_load_enabled:
		#teamcolor_path = f'{material_path}_default.wtp'
		#teamcolor_data = self.layout.find(teamcolor_path)
		#if not teamcolor_data:
			#self.messages.append(('INFO', f'Cannot find {teamcolor_path}'))
		#else:
			#self.load_wtp(open_reader(teamcolor_data), material_path, material)
	if material_info != null:
		loaded_materials[material_path] = create_material(material_info)

static func create_material(info: RshParser.MaterialInfo) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	for channel in info.channels:
		var image := info.channels[channel]
		if channel == RshParser.Channel.DIFFUSE:
			material.albedo_texture = ImageTexture.create_from_image(image)
			var image_aplha_mode := image.detect_alpha()
			if image_aplha_mode != Image.AlphaMode.ALPHA_NONE:
				if image_aplha_mode == Image.AlphaMode.ALPHA_BIT:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				else:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.resource_name = info.name
	return material

func CH_FOLDSTXT(texture_path: String) -> Image:  # Chunk Handler - Reference to an external rtx
	var full_texture_path := "%s.rtx" % texture_path
	used_files.append(full_texture_path)
	var texture_data := mod.locate_data(full_texture_path)
	if not texture_data:
		GsqLogger.warning('Cannot find texture file "%s"', [full_texture_path])
		return
	var parser := RtxParser.new()
	return parser.parse(texture_data.read_bytes())

func CH_FOLDMSGR(reader: ChunkReader) -> void:
	while reader.has_data():  # Read FOLDMSLC Chunks
		var current_chunk := reader.read_header()
		match current_chunk.typeid:
			'FOLDMSLC': CH_FOLDMSLC(reader, current_chunk.name, false)  # 	 - Mesh Data
			'DATADATA':
				reader.skip(current_chunk.size)
				#self.CH_DATADATA(reader)  # -- DATADATA - Mesh List
			'DATABVOL':  # -- DATABVOL - Unknown
				bbox = read_bbox(reader)
				return

func CH_FOLDMSLC(reader: ChunkReader, mesh_name: String, xref: bool):  # Chunk Handler - FOLDMSGR Sub Chunk - Mesh Data
	#------------------------
	#---[ READ MESH DATA ]---
	#------------------------

	#---< DATADATA CHUNK >---

	#bone_array = self.xref_bone_array if xref else self.bone_array
	var current_chunk := reader.read_header('DATADATA')
	var rsv0_a := reader.read_32()
	var flag := reader.read_8()
	var num_polygons := reader.read_u32()
	var rsv0_b := reader.read_32()
	ensure(flag == 1, 'Mesh "%s": flag=%s', [mesh_name, flag])
	#ensure(rsv0_a == 0 and rsv0_b == 0, 'Mesh "%s": rsv0_a=%s rsv0_b=%s', [mesh_name, rsv0_a, rsv0_b]) # Too common in DE

	#---< SKIN BONES >---

	var num_skin_bones := reader.read_u32()  # -- get number of bones mesh is weighted to
	var idx_to_bone_name := {}
	for i in num_skin_bones:
		var bone_name := reader.read_str()  # -- read bone name
		var bone_idx := reader.read_u32()
		idx_to_bone_name[bone_idx] = bone_name

	#---< VERTICES >---

	var num_vertices := reader.read_u32()  # -- read number of vertices
	var vertex_size_id := reader.read_u32()  # 37 or 39
	ensure(vertex_size_id == 5 or (1 if num_skin_bones != 0 else 0) * 2 == vertex_size_id - 37, 'Mesh "%s": num_skin_bones=%s and vertex_size_id=%s', [mesh_name, num_skin_bones, vertex_size_id])

	var vert_array: PackedVector3Array = []       # -- array to store vertex data
	vert_array.resize(num_vertices)
	for idx in num_vertices:
		vert_array[idx] = reader.read_vec3()

	#---< SKIN >---

	var skin_vert_array: Array[SkinVertice] = []  # -- array to store skin vertices
	if num_skin_bones:
		skin_vert_array.resize(num_vertices)
		#skin_data_warn = False
		for idx in num_vertices:
			var skin_vert := SkinVertice.new()  # -- Reset Structure
			var weight_last := 1.
			for slot_idx in NUM_BONE_SLOTS - 1:  # -- Read 1st, 2nd and 3rd Bone Weight
				var wi = reader.read_float()
				weight_last -= wi
				skin_vert.weights.append(wi)
			skin_vert.weights.append(weight_last)  # -- Calculate 4th Bone Weight

			# -- Read Bones
			for bone_slot in NUM_BONE_SLOTS:
				var bone_idx := reader.read_u8()
				if bone_idx == 255:
					skin_vert.bones.append('')  # None
					continue
				#bone_name = idx_to_bone_name.get(bone_idx)
				#if bone_name is None:
					#if bone_idx >= len(bone_array):
						#if not skin_data_warn:
							#self.messages.append(('WARNING', f'Mesh "{mesh_name}": bone index {bone_idx} (slot {bone_slot}) is out of range ({len(bone_array) - 1})'))
							#skin_data_warn = True
						#skin_vert.bone[bone_slot] = None
						#continue
					#bone_name = bone_array[bone_idx].name
				#skin_vert.bone[bone_slot] = bone_name

			# -- Add Vertex To Array
			skin_vert_array[idx] = skin_vert

	#---< NORMALS >---

	var normals: PackedVector3Array = []     # -- array to store normal data
	normals.resize(num_vertices)
	for idx in num_vertices:
		normals[idx] = reader.read_vec3()

	#---< UVW MAP >---

	var uvs: PackedVector2Array = []        # -- array to store texture coordinates
	uvs.resize(num_vertices)
	for idx in num_vertices:
		uvs[idx] = reader.read_vec2()
#
	#-- skip to texture path
	var unk_bytes = reader.read_32()  # -- skip 4 bytes (unknown, zeros)
	ensure(unk_bytes == 0, 'Mesh "%s": unexpected non-zero data: %s', [mesh_name, unk_bytes])

	#---< MATERIALS >---

	var num_materials := reader.read_u32()  # -- read number of materials
	var materials: PackedStringArray = []  # -- array to store material id's
	materials.resize(num_materials)
	var mat_face_array: Array[PackedInt32Array] = []  # -- array to store face data
	mat_face_array.resize(num_materials)
	var total_num_faces := 0
	#-- read materials
	for mat_idx in num_materials:
		var material_path := reader.read_str()  # -- read material path
		materials[mat_idx] = material_path

		#-- read number of faces connected with this material
		var num_faces := reader.read_u32()  # -- faces are given as a number of vertices that makes them - divide by 3
		total_num_faces += num_faces

		#-- read faces connected with this material
		var mat_faces: PackedInt32Array = []
		mat_faces.resize(num_faces)
		var face_idx := 0
		while face_idx < num_faces:
			var x := reader.read_u16()
			var z := reader.read_u16()
			var y := reader.read_u16()
			mat_faces[face_idx] = x
			face_idx += 1
			mat_faces[face_idx] = y
			face_idx += 1
			mat_faces[face_idx] = z
			face_idx += 1
		mat_face_array[mat_idx] = mat_faces
		# -- Skip 8 Bytes To Next Texture Name Length. 4 data bytes + 4 zeros
		var data_min_vertex_idx := reader.read_u16()
		var data_vertex_cnt := reader.read_u16()
		var bytes_zero := reader.read_32()
		var real_min_vertex_idx := 2**18
		for i in mat_faces: real_min_vertex_idx = mini(real_min_vertex_idx, i)
		var real_max_vertex_idx := -1
		for i in mat_faces: real_max_vertex_idx = maxi(real_max_vertex_idx, i)
		var real_vertex_cnt := real_max_vertex_idx + 1 - real_min_vertex_idx
		ensure(bytes_zero == 0, 'Mesh "%s:%s" has non-zero flags: %s', [mesh_name, material_path, bytes_zero])
		ensure(data_min_vertex_idx == real_min_vertex_idx, 'Mesh "%s:%s" min_vertex_idx: %s !=%s' % [mesh_name, material_path, data_min_vertex_idx, real_min_vertex_idx])
		ensure(data_vertex_cnt == real_vertex_cnt, 'Mesh "%s:%s" vertex_cnt: %s != %s', [mesh_name, material_path, data_vertex_cnt, real_vertex_cnt])
	#ensure(num_polygons * 3 == total_num_faces, 'Mesh "%s": %s != %s', [mesh_name, num_polygons * 3, total_num_faces])  # Too common in DE

	#---< SHADOW VOLUME >---

	var num_shadow_vertices := reader.read_u32()  # -- zero is ok
	var shadow_vertices: PackedVector3Array = []
	shadow_vertices.resize(num_shadow_vertices)
	for idx in num_shadow_vertices:
		#x, z, y = reader.read_struct('<3f')
		#shadow_vertices.append((-x, -y, z))
		shadow_vertices[idx] = reader.read_vec3()

	if vertex_size_id != 5:
		var num_shadow_faces := reader.read_u32()  # -- zero is ok
		var shadow_faces := []
		shadow_faces.resize(num_shadow_faces)
		var shadow_face_normals: PackedVector3Array = []
		shadow_face_normals.resize(num_shadow_faces)
		for idx in num_shadow_faces:
			#norm_x, norm_z, norm_y, x, z, y = reader.read_struct('<3f3L')
			#shadow_faces.append((x, y, z))
			#shadow_face_normals.append((-norm_x, -norm_y, norm_z))
			shadow_face_normals[idx] = reader.read_vec3()
			var x := reader.read_u32()
			var z := reader.read_u32()
			var y := reader.read_u32()
			shadow_faces[idx] = [x, y, z]
			
		var num_shadow_edges := reader.read_u32()  # -- zero is ok
		var shadow_edges := []
		shadow_edges.resize(num_shadow_edges)
		for idx in num_shadow_edges:
			## vert1, vert2, face1, face2, vert_pos1, vert_pos2
			shadow_edges[idx] = [
				reader.read_u32(), reader.read_u32(), reader.read_u32(), reader.read_u32(),
				reader.read_vec3(), reader.read_vec3(),
			]

	#---< DATABVOL CHUNK >---

	current_chunk = reader.read_header("DATABVOL")
	skip_bbox(reader)

	##---------------------
	##---[ CREATE MESH ]---
	##---------------------
#
	##---< CREATE MESH >---
	
	var mesh := ArrayMesh.new()
	for mat_idx in num_materials:
		var surface_array := []
		surface_array.resize(Mesh.ARRAY_MAX)
		surface_array[Mesh.ARRAY_VERTEX] = vert_array
		surface_array[Mesh.ARRAY_TEX_UV] = uvs
		surface_array[Mesh.ARRAY_NORMAL] = normals
		surface_array[Mesh.ARRAY_INDEX] = mat_face_array[mat_idx]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
		var material: StandardMaterial3D = loaded_materials.get(materials[mat_idx])
		if material != null:
			mesh.surface_set_material(mat_idx, material)
	# todo set shadow_mesh
	meshes[mesh_name] = mesh

func CH_DATADATA(reader: ChunkReader):  # - Chunk Handler - Sub Chunk Of FOLDMSGR - Mesh List
	pass

func parse(data: PackedByteArray) -> void:
	var reader := ChunkReader.from_bytes(data)
	reader.skip_chunky()
	var header := reader.read_header()  # Read 'File Burn Info' Header
	if header.typeid == "DATAFBIF":
		reader.skip(header.size)       # Skip 'File Burn Info' Chunk
		header = reader.read_header("FOLDRSGM")  # Skip 'Folder SGM' Header
	
	var internal_textures: Dictionary[String, Image] = {}
	while reader.has_data():  # Read Chunks Until End Of File
		var current_chunk := reader.read_header()
		if current_chunk == null: return
		match current_chunk.typeid:
			"DATASSHR": CH_DATASSHR(reader)  # DATASSHR - Texture Data
			"FOLDSTXT":  # FOLDSTXT - Reference to an external rtx
				internal_textures[current_chunk.name] = CH_FOLDSTXT(current_chunk.name)
			"FOLDTXTR":  # FOLDTXTR - Internal Texture
				internal_textures[current_chunk.name] = RtxParser.CH_FOLDTXTR(reader)
			"FOLDSHDR":  # FOLDSHDR - Internal Material
				var material_info := RshParser.MaterialInfo.new()
				material_info.name = current_chunk.name
				material_info.channels = RshParser.CH_FOLDSHDR(reader, internal_textures)
				loaded_materials[current_chunk.name] = create_material(material_info)
			#"DATASKEL": self.CH_DATASKEL(reader, xref=False)  # DATASKEL - Skeleton Data
			"FOLDMSGR": CH_FOLDMSGR(reader)  # FOLDMSGR - Mesh Data
			#"DATAMARK": self.CH_DATAMARK(reader)  # DATAMARK - Marker Data
			#"FOLDANIM": self.CH_FOLDANIM(reader)  # FOLDANIM - Animations
			#"DATACAMS": self.CH_DATACAMS(reader)  # DATACAMS - Cameras
			_:
				#print(current_chunk.typeid)
				reader.skip(current_chunk.size)

func setup_model(model: Model) -> void:
	for mesh_name in meshes:
		var node := MeshInstance3D.new()
		node.mesh = meshes[mesh_name]
		node.name = mesh_name
		#node.scale.x = -1
		model.skeleton.add_child(node)
	#if bbox != null:
		#var bbox_root := Node3D.new()
		#
		#var make_edge := func (len: float) -> MeshInstance3D:
			#var mesh := CylinderMesh.new()
			#mesh.height = len
			#mesh.top_radius = 0.005
			#mesh.bottom_radius = 0.005
			#mesh.radial_segments = 3
			#mesh.rings = 2
			#var node := MeshInstance3D.new()
			#node.mesh = mesh
			#bbox_root.add_child(node)
			#return node
		#
		#var e := MeshInstance3D.new()
		##.translate(Vector3(1, 0, 1) * bbox.size)
		#make_edge.call(bbox.size[1] * 2).translate(Vector3(1, 0, 1) * bbox.size)
		#make_edge.call(bbox.size[1] * 2).translate(Vector3(1, 0, -1) * bbox.size)
		#make_edge.call(bbox.size[1] * 2).translate(Vector3(-1, 0, 1) * bbox.size)
		#make_edge.call(bbox.size[1] * 2).translate(Vector3(-1, 0, -1) * bbox.size)
		#var x_basis := Basis.from_euler(Vector3(0, 0, PI / 2))
		#make_edge.call(bbox.size[0] * 2).transform = Transform3D(x_basis, Vector3(0, 1, 1) * bbox.size)
		#make_edge.call(bbox.size[0] * 2).transform = Transform3D(x_basis, Vector3(0, 1, -1) * bbox.size)
		#make_edge.call(bbox.size[0] * 2).transform = Transform3D(x_basis, Vector3(0, -1, 1) * bbox.size)
		#make_edge.call(bbox.size[0] * 2).transform = Transform3D(x_basis, Vector3(0, -1, -1) * bbox.size)
		#var z_basis := Basis.from_euler(Vector3(PI / 2, 0, 0))
		#make_edge.call(bbox.size[2] * 2).transform = Transform3D(z_basis, Vector3(1, 1, 0) * bbox.size)
		#make_edge.call(bbox.size[2] * 2).transform = Transform3D(z_basis, Vector3(1, -1, 0) * bbox.size)
		#make_edge.call(bbox.size[2] * 2).transform = Transform3D(z_basis, Vector3(-1, 1, 0) * bbox.size)
		#make_edge.call(bbox.size[2] * 2).transform = Transform3D(z_basis, Vector3(-1, -1, 0) * bbox.size)
		#bbox_root.transform = Transform3D(bbox.rotation, bbox.center)
		#model.add_child(bbox_root)
	model.scale.x = -1
