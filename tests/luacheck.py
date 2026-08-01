#!/usr/bin/env python3
"""Syntax-check Lua files using liblua5.4 via ctypes (luaL_loadbuffer only)."""
import ctypes, sys, os

lua = ctypes.CDLL("liblua5.4.so.0")

lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t,
                                 ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadbufferx.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

failed = 0
for path in sys.argv[1:]:
    with open(path, "rb") as f:
        src = f.read()
    L = lua.luaL_newstate()
    rc = lua.luaL_loadbufferx(L, src, len(src), path.encode(), None)
    if rc != 0:
        msg = lua.lua_tolstring(L, -1, None)
        print(f"FAIL {path}: {msg.decode(errors='replace')}")
        failed += 1
    else:
        print(f"OK   {path}")
    lua.lua_close(L)

sys.exit(1 if failed else 0)
