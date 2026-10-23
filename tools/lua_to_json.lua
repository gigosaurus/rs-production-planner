-- Prints the table that a Lua file returns, as JSON. tools/generate.py runs it.
-- Command: lua5.4 tools/lua_to_json.lua <file>
-- A table with the keys 1 to n is a JSON array. An empty table is an empty array.
-- Each other table is a JSON object. Its keys become strings, in sorted order.

local encode

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(text)
    return '"'
        .. text:gsub('[%c"\\]', function(char)
            return ESCAPES[char] or string.format("\\u%04x", char:byte())
        end)
        .. '"'
end

local function isArray(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end
    return true
end

local function encodeTable(value)
    local parts = {}
    if isArray(value) then
        for _, item in ipairs(value) do
            parts[#parts + 1] = encode(item)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encodeString(tostring(key)) .. ":" .. encode(value[key])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function encode(value)
    local kind = type(value)
    if kind == "table" then
        return encodeTable(value)
    elseif kind == "string" then
        return encodeString(value)
    elseif kind == "boolean" then
        return tostring(value)
    elseif math.type(value) == "integer" then
        return string.format("%d", value)
    elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return string.format("%.17g", value)
    end
    error("A value of type " .. kind .. " cannot be JSON.")
end

local path = arg[1]
local chunk, loadError = loadfile(path, "t", {})
if not chunk then
    io.stderr:write(loadError, "\n")
    os.exit(1)
end
local ok, result = pcall(chunk)
if not ok then
    io.stderr:write(path, ": ", tostring(result), "\n")
    os.exit(1)
end
if type(result) ~= "table" then
    io.stderr:write(path, ": the file must return a table.\n")
    os.exit(1)
end
io.write(encode(result), "\n")
