-- luacheck config. The game client uses Lua 5.4.8.
std = "lua54"
-- StyLua sets the line layout.
max_line_length = false

-- tests/run.lua gives these globals to each spec file.
files["tests/"] = { globals = { "describe", "it", "expectEqual" } }

-- The game client gives these globals. The client calls PluginShutdown when it stops the plugin.
files["main.lua"] = {
    read_globals = {
        "config",
        "Event",
        "GameState",
        "id",
        "Inventory",
        "log",
        "PersistentDB",
        "Player",
        "SkillType",
        "ui",
        "var",
    },
    globals = { "PluginShutdown" },
}

-- ui/ draws with PrettyUI. The client gives prettyui as the alias of the dependency (plugin.json).
files["ui/"] = { read_globals = { "config", "prettyui" } }
