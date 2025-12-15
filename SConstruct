#!/usr/bin/env python
env = SConscript("./godot-cpp/SConstruct")
env.Append(LINKFLAGS=[
    "-Wl,--no-as-needed",
    "-Wl,--no-undefined",
])

sources = [Glob("cpp/*.cpp"), "cpp/hash.c", "cpp/crc32.c"]
library = env.SharedLibrary(
    "bin/libgdsquad{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
    source=sources,
)
Default(library)
