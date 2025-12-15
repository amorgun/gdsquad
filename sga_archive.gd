# See https://github.com/ModernMAK/Relic-Game-Tool/wiki/SGA-Archive

class_name SgaArchive

const MAGIC_NUMBER: String = "_ARCHIVE"

enum SgaVersion {
	V2_0 = (2 << 16),
	V5_0 = (5 << 16),
}

class Header:
	var table_of_content_offset: int
	var data_offset: int

class TableOfContent:
	var virtual_drive_offset: int
	var virtual_drive_count: int
	var folder_offset: int
	var folder_count: int
	var file_offset: int
	var file_count: int
	var name_buffer_offset: int
	var name_buffer_count: int
	
class VirtualDrive:
	var path: String
	var name: String
	var first_folder: int
	var last_folder: int
	var first_file: int
	var last_file: int
	
class FolderHeader:
	var name_offset: int
	var sub_folder_start_index: int
	var sub_folder_end_index: int
	var file_start_index: int
	var file_end_index: int

class FileHeader:
	var name_offset: int
	var compression_flag: int
	var data_offset: int
	var compressed_size: int
	var decompressed_size: int

class File:
	var name: String
	var compression_flag: int
	var data_offset: int
	var compressed_size: int
	var decompressed_size: int
	
	func _init(
		name: String,
		header: FileHeader,
	):
		self.name = name
		self.compression_flag = header.compression_flag
		self.data_offset = header.data_offset
		self.compressed_size = header.compressed_size
		self.decompressed_size = header.decompressed_size

class Folder:
	var name: String
	var folders: Dictionary[String, Folder]
	var files: Dictionary[String, File]

var root: Folder

func load_meta(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		printerr("Error opening SGA file: %s" % file_path)
		return false

	var magic = file.get_buffer(8).get_string_from_ascii()
	if magic != MAGIC_NUMBER:
		printerr("Invalid magic number: %s (expected %s)" % [magic, MAGIC_NUMBER])
		file.close()
		return false
	var version_major := file.get_16()
	var version_minor := file.get_16()
	var version := (version_major << 16) | version_minor#
	if not (
		version == SgaVersion.V2_0
		or version == SgaVersion.V5_0
	):
		printerr("Unsupported SGA version: %s.%s" % [version_major, version_minor])
		file.close()
		return false

	var header := Header.new()
	var header_ok := true
	match version:
		SgaVersion.V2_0: header_ok = _parse_header_v2(file, header)
		SgaVersion.V5_0: header_ok = _parse_header_v5(file, header)
	if not header_ok:
		file.close()
		return false	

	file.seek(header.table_of_content_offset)
	var table_of_content := TableOfContent.new()
	if not _parse_toc_v2_5(file, table_of_content):
		file.close()
		return false	

	file.seek(header.table_of_content_offset + table_of_content.virtual_drive_offset)
	var drives: Array[VirtualDrive] = []
	for i in table_of_content.virtual_drive_count:
		var d := VirtualDrive.new()
		if _parse_virtual_drive_v2_5(file, d):
			drives.append(d)

	file.seek(header.table_of_content_offset + table_of_content.folder_offset)	
	var folders: Array[FolderHeader] = []
	for i in table_of_content.folder_count:
		var f := FolderHeader.new()
		if _parse_folder_v2_5(file, f):
			folders.append(f)

	file.seek(header.table_of_content_offset + table_of_content.file_offset)
	var files: Array[FileHeader]
	for i in table_of_content.file_count:
		var file_ok := true
		var f := FileHeader.new()
		match version:
			SgaVersion.V2_0: file_ok = _parse_file_v2(file, f)
			SgaVersion.V5_0: file_ok = _parse_file_v5(file, f)
		if file_ok:
			files.append(f)
#
	var max_name_offset := 0
	for f in folders:
		max_name_offset = max(max_name_offset, f.name_offset)
	for f in files:
		max_name_offset = max(max_name_offset, f.name_offset)
	file.seek(header.table_of_content_offset + table_of_content.name_buffer_offset + max_name_offset + 1)
	var last_name_size := 1
	var file_len := file.get_length()
	while true:
		last_name_size += 1
		var c := file.get_8()
		if file.get_position() >= file_len or c == 0:
			break
	file.seek(header.table_of_content_offset + table_of_content.name_buffer_offset)
	var name_buffer := file.get_buffer(max_name_offset + last_name_size)
	var name_buffer_splits: PackedInt64Array = []
	for idx in len(name_buffer):
		if name_buffer[idx] == 0:
			name_buffer_splits.append(idx)

	var find_name = func(start: int) -> String:
		var l = 0
		var r = len(name_buffer_splits)
		if name_buffer_splits[l] == start:
			return ""
		while l + 1 != r:
			var m = (l + r) >> 1
			if name_buffer_splits[m] <= start:
				l = m
			else:
				r = m
		return name_buffer.slice(start, name_buffer_splits[r]).get_string_from_utf8()
	
	var index_folders: Array[Folder] = []
	for f in folders:
		var t := Folder.new()
		var full_path: String = find_name.call(f.name_offset)
		t.name = full_path.simplify_path().get_file().to_lower()
		index_folders.append(t)
	var folder_parents: Dictionary[Folder, Folder] = {}
	for drive in drives:
		#print("NEW DRIVE")
		for folder_idx in range(drive.first_folder, drive.last_folder):
			var parent:= index_folders[folder_idx]
			var parent_data:= folders[folder_idx]
			for child_idx in range(parent_data.sub_folder_start_index, parent_data.sub_folder_end_index):
				var child:= index_folders[child_idx]
				parent.folders[child.name] = child
				folder_parents[child] = parent
				#print(parent.name, "->", child.name)
			for f in files.slice(parent_data.file_start_index, parent_data.file_end_index):
				var full_path: String = find_name.call(f.name_offset)
				var child := File.new(full_path.simplify_path().get_file().to_lower(), f)
				child.data_offset += header.data_offset
				parent.files[child.name] = child

		for folder_idx in range(drive.first_folder, drive.last_folder):
			var parent:= index_folders[folder_idx]
			if parent not in folder_parents:
				root = parent
				break
	file.close()
	return true

func _parse_header_v2(file: FileAccess, header: Header) -> bool:
	var checksum1 := file.get_buffer(16)
	var name := file.get_buffer(128).get_string_from_utf16()
	var checksum2 := file.get_buffer(16)
	var size_data := file.get_buffer(8)
	var table_of_content_size := size_data.decode_u32(0)
	header.data_offset = size_data.decode_u32(4)
	header.table_of_content_offset = 180
	if header.data_offset != table_of_content_size + header.table_of_content_offset:
		return false
	return true

func _parse_header_v5(file: FileAccess, header: Header) -> bool:
	var checksum1 := file.get_buffer(16)
	var name := file.get_buffer(128).get_string_from_utf16()
	var checksum2 := file.get_buffer(16)
	var size_data := file.get_buffer(12)
	var table_of_content_size := size_data.decode_u32(0)
	header.data_offset = size_data.decode_u32(4)
	header.table_of_content_offset = size_data.decode_u32(8)
	# 12 unk
	return true

func _parse_toc_v2_5(file: FileAccess, table_of_content: TableOfContent) -> bool:
	var buffer := file.get_buffer(6 * 4)
	table_of_content.virtual_drive_offset = buffer.decode_u32(0)
	table_of_content.virtual_drive_count = buffer.decode_u16(4)
	table_of_content.folder_offset = buffer.decode_u32(6)
	table_of_content.folder_count = buffer.decode_u16(10)
	table_of_content.file_offset = buffer.decode_u32(12)
	table_of_content.file_count = buffer.decode_u16(16)
	table_of_content.name_buffer_offset = buffer.decode_u32(18)
	table_of_content.name_buffer_count = buffer.decode_u16(22)
	return true

func _parse_virtual_drive_v2_5(file: FileAccess, drive: VirtualDrive) -> bool:
	drive.path = file.get_buffer(64).get_string_from_utf8()
	drive.name = file.get_buffer(64).get_string_from_utf8()
	var buffer := file.get_buffer(4 * 2 + 2)
	drive.first_folder = buffer.decode_u16(0)
	drive.last_folder = buffer.decode_u16(2)
	drive.first_file = buffer.decode_u16(4)
	drive.last_file = buffer.decode_u16(6)
	# 2 unk
	return true

func _parse_folder_v2_5(file: FileAccess, folder: FolderHeader) -> bool:
	var buffer := file.get_buffer(4 + 4 * 2)
	folder.name_offset = buffer.decode_u32(0)
	folder.sub_folder_start_index = buffer.decode_u16(4)
	folder.sub_folder_end_index = buffer.decode_u16(6)
	folder.file_start_index = buffer.decode_u16(8)
	folder.file_end_index = buffer.decode_u16(10)
	return true

func _parse_file_v2(file: FileAccess, res: FileHeader) -> bool:
	var buffer := file.get_buffer(5 * 4)
	res.name_offset = buffer.decode_u32(0)
	res.compression_flag = buffer.decode_u32(4)
	res.data_offset = buffer.decode_u32(8)
	res.compressed_size = buffer.decode_u32(12)
	res.decompressed_size = buffer.decode_u32(16)
	return true

func _parse_file_v5(file: FileAccess, res: FileHeader) -> bool:
	var buffer := file.get_buffer(22)
	res.name_offset = buffer.decode_u32(0)
	res.data_offset = buffer.decode_u32(4)
	res.compressed_size = buffer.decode_u32(8)
	res.decompressed_size = buffer.decode_u32(12)
	return true

func find_folder(path: String) -> Folder:
	var res := root
	if path != "":
		var parts := path.split("/")
		for idx in len(parts):
			var part := parts[idx]
			if idx == 0 and part == '':
				continue
			res = res.folders.get(part.to_lower())
			if res == null:
				break
	return res
