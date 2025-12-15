#include "gdsquad.h"
#include <godot_cpp/core/class_db.hpp>

extern "C" {
typedef  uint32_t  ub4;   /* unsigned 4-byte quantities */
typedef  uint8_t ub1;
ub4 hash(const ub1 *k, ub4 length, ub4 initval);
unsigned int crc32_impl(const unsigned char *bin_data, size_t len, unsigned int crc);
}

using namespace godot;

void GDSquadExt::_bind_methods() {
	ClassDB::bind_static_method("GDSquadExt", D_METHOD("rgd_key_hash", "data", "offset", "len"), &GDSquadExt::rgd_key_hash, DEFVAL(0), DEFVAL(0));
	ClassDB::bind_static_method("GDSquadExt", D_METHOD("crc32", "data", "offset", "len"), &GDSquadExt::crc32, DEFVAL(0), DEFVAL(0));
}

GDSquadExt::GDSquadExt() {
}

uint32_t GDSquadExt::rgd_key_hash(const PackedByteArray &data, const size_t offset, const size_t len) {
	if (offset >= data.size()) {
		return 0;
	}
	size_t real_len = len;
	if (real_len == 0) {
		real_len = data.size() - offset;
	}
	if (real_len + offset > data.size()) {
		return 0;
	}
	const uint8_t *data_ptr = data.ptr() + offset;
	return hash(data_ptr, real_len, 0);
}

uint32_t GDSquadExt::crc32(const PackedByteArray &data, const size_t offset, const size_t len) {
	if (offset >= data.size()) {
		return 0;
	}
	size_t real_len = len;
	if (real_len == 0) {
		real_len = data.size() - offset;
	}
	if (real_len + offset > data.size()) {
		return 0;
	}
	const uint8_t *data_ptr = data.ptr() + offset;
	return crc32_impl(data_ptr, real_len, 0);
}