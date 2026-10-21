-- Throwaway probe for #24.
-- 1. Does a Lua table in resources/ load?
-- 2. What does config.Obj give for a config name that does not exist?

local function shape(ok, result)
    if not ok then return "ERROR: " .. tostring(result)
    elseif result == nil then return "nil"
    elseif type(result) == "table" then return "table " .. tostring(result.name)
    else return type(result) .. " " .. tostring(result) end
end

local function try(label, f)
    log("[recipe-data-probe] " .. label .. " = " .. shape(pcall(f)))
end

-- 1. resources/
try("type(Plugin.resources)", function() return type(Plugin.resources) end)
try("keys of Plugin.resources", function()
    local keys = {}
    for key, value in pairs(Plugin.resources) do
        keys[#keys + 1] = tostring(key) .. ":" .. type(value)
    end
    return #keys == 0 and "(none)" or table.concat(keys, ", ")
end)
try("Plugin.resources.recipes", function() return Plugin.resources.recipes end)
try("require(\"resources/recipes\")", function() return require("resources/recipes") end)

-- 2. config.Obj
local function objName(name)
    return function()
        local obj = config.Obj[name]
        if obj == nil then return nil end
        return obj.configName .. " id=" .. obj.id .. " name=" .. obj.name
    end
end

try("type(config.Obj)", function() return type(config.Obj) end)
try("config.Obj.LANTADYME", objName("LANTADYME")) -- exists (ADR 0001)
try("config.Obj.lantadyme", objName("lantadyme")) -- letter case
try("config.Obj.NOT_A_REAL_NAME", objName("NOT_A_REAL_NAME")) -- does not exist
