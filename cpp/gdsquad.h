#ifndef GDSQUADEXT_H
#define GDSQUADEXT_H

#include <godot_cpp/classes/ref_counted.hpp>


namespace godot {

class GDSquadExt : public RefCounted {
	GDCLASS(GDSquadExt, RefCounted)

private:

protected:
	static void _bind_methods();
public:
	GDSquadExt();
	static uint32_t rgd_key_hash(const PackedByteArray &data, const size_t offset = 0, const size_t len = 0);
	static uint32_t crc32(const PackedByteArray &data, const size_t offset = 0, const size_t len = 0);
};

}

#endif