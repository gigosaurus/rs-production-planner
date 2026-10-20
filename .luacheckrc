-- luacheck config. The game client uses Lua 5.4.8.
std = "lua54"
-- StyLua sets the line layout.
max_line_length = false

-- tests/run.lua gives these globals to each spec file.
files["tests/"] = { globals = { "describe", "it", "expectEqual" } }
