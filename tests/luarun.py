#!/usr/bin/env python3
"""Run a Lua script with liblua5.4 via ctypes. Enough of a runner to execute tests."""
import ctypes, sys

lua = ctypes.CDLL("liblua5.4.so.0")

lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t,
                                 ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadbufferx.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                           ctypes.c_void_p, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

path = sys.argv[1]
with open(path, "rb") as f:
    src = f.read()

L = lua.luaL_newstate()
lua.luaL_openlibs(L)

rc = lua.luaL_loadbufferx(L, src, len(src), path.encode(), None)
if rc != 0:
    print("SYNTAX ERROR:", lua.lua_tolstring(L, -1, None).decode(errors="replace"))
    sys.exit(1)

rc = lua.lua_pcallk(L, 0, -1, 0, None, None)
if rc != 0:
    msg = lua.lua_tolstring(L, -1, None)
    print("RUNTIME ERROR:", msg.decode(errors="replace") if msg else "(no message)")
    lua.lua_close(L)
    sys.exit(1)

lua.lua_close(L)
