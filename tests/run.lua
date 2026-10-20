-- This script runs every tests/*_spec.lua file outside the game client.
-- Use Lua 5.4. The game client uses Lua 5.4.8.
-- Command: lua5.4 tests/run.lua
package.path = "./?.lua;" .. package.path

local passed, failed = 0, {}
local prefix = {}

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function show(v, indent)
    indent = indent or ""
    if type(v) ~= "table" then
        return type(v) == "string" and string.format("%q", v) or tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(x, y)
        return tostring(x) < tostring(y)
    end)
    local lines = {}
    for _, k in ipairs(keys) do
        lines[#lines + 1] = indent .. "  " .. tostring(k) .. " = " .. show(v[k], indent .. "  ")
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n" .. indent .. "}"
end

function describe(name, body)
    prefix[#prefix + 1] = name
    body()
    prefix[#prefix] = nil
end

function it(name, body)
    local full = table.concat(prefix, " ") .. " " .. name
    local ok, err = pcall(body)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = full .. "\n    " .. tostring(err)
    end
end

function expectEqual(actual, expected)
    if not same(actual, expected) then
        error("expected " .. show(expected) .. "\n    got " .. show(actual), 2)
    end
end

local specs = io.popen("ls tests/*_spec.lua 2>/dev/null")
for path in specs:lines() do
    dofile(path)
end
specs:close()

for _, f in ipairs(failed) do
    print("FAIL " .. f)
end
print(string.format("%d passed, %d failed", passed, #failed))
os.exit(#failed == 0 and 0 or 1)
