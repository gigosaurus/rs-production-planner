-- Throwaway probe: the PersistentDB questions that probes/persistentdb-probe left open (issue #23).
--   1. Where do integers in a table stop being exact?
--   2. Are floats saved as 32-bit or 64-bit?
--   3. Does SetInt keep large integers?
--   4. What is the exact size limit of one value?
--   5. Does the data survive a full restart of the game client?
-- The game client stops a Lua call after 1000 ms. The probe then runs one step in each Logic tick.
-- Before each step it saves the step name. After a crash, the next pon logs the step and skips it.
-- Load 1 (pon): runs all steps and writes restart markers.
-- Load 2 (close the game client fully, start it, pon): checks the markers, then deletes all keys.

local P = "limits:"
local RUNNING_KEY = P .. "running"
local CRASHED_KEY = P .. "crashed"
local MARKER_KEY = P .. "marker"

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log("[pdb-limits] " .. table.concat(parts, " "))
end

say("Loaded. First line before any API call.")

local function numType(v)
    if math and math.type then return math.type(v) end
    return "number"
end

-- Full precision, so a float32 rounding shows.
local function show(v)
    if type(v) == "number" then
        if numType(v) == "integer" then return tostring(v) .. "(int)" end
        return string.format("%.17g", v) .. "(float)"
    end
    return tostring(v)
end

local function exactInt(want, got)
    return numType(got) == "integer" and got == want
end

-- Each set-and-delete for a size test.
local function fits(value)
    local ok = PersistentDB:Set(P .. "sizeTest", value)
    PersistentDB:Delete(P .. "sizeTest")
    return ok == true
end

-- Largest n in [lo, hi] where fits(build(n)). hi + 1 must not fit.
-- When lo does not fit, it says so. A wrong lo then cannot show as the limit.
local function largest(lo, hi, build)
    if not fits(build(lo)) then return "none: lo = " .. lo .. " does not fit" end
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if fits(build(mid)) then lo = mid else hi = mid - 1 end
    end
    return lo
end

local steps = {}
local function step(name, fn) steps[#steps + 1] = { name = name, fn = fn } end

-- 1. Integers in a table: 2^k - 1, 2^k and 2^k + 1 for k = 1 to 62, and their negatives.
step("int threshold in a table", function()
    local values = {}
    for k = 1, 62 do
        local p = 1 << k
        for _, v in ipairs({ p - 1, p, p + 1, -(p - 1), -p, -(p + 1) }) do values[#values + 1] = v end
    end
    if PersistentDB:Set(P .. "ints", values) ~= true then
        say("Set of the int array returned false")
        return
    end
    local back = PersistentDB:Get(P .. "ints")
    local firstFloat, firstWrong
    for i, v in ipairs(values) do
        local got = back[i]
        if not firstFloat and numType(got) ~= "integer" then firstFloat = i end
        if not firstWrong and got ~= v then firstWrong = i end
    end
    say("first value that comes back as float:", firstFloat and (show(values[firstFloat]) .. " -> " .. show(back[firstFloat])) or "none")
    say("first value that comes back wrong:", firstWrong and (show(values[firstWrong]) .. " -> " .. show(back[firstWrong])) or "none")
    -- Some exact values near the likely limits.
    for _, k in ipairs({ 15, 16, 23, 24, 25, 31, 32, 53 }) do
        local base = (k - 1) * 6
        say("k=" .. k, show(values[base + 1]), "->", show(back[base + 1]), "|",
            show(values[base + 3]), "->", show(back[base + 3]))
    end
end)

-- 2. Float precision: float32 rounds 0.1 to 0.10000000149011612.
step("float precision in a table", function()
    local values = { 0.1, 1 / 3, 16777217.5, 2 ^ 53 + 0.0 }
    PersistentDB:Set(P .. "floats", values)
    local back = PersistentDB:Get(P .. "floats")
    for i, v in ipairs(values) do say("float", show(v), "->", show(back[i])) end
end)

step("float precision at top level", function()
    for i, v in ipairs({ 0.1, 1 / 3, 16777217 }) do
        PersistentDB:Set(P .. "topFloat" .. i, v)
        say("top-level Set", show(v), "->", show(PersistentDB:Get(P .. "topFloat" .. i)))
    end
end)

-- 3. SetInt with large values. Each value in its own pcall: SetInt can raise.
step("SetInt large values", function()
    local values = { 16777217, 2147483647, 2147483648, 4294967296, 1 << 40, (1 << 53) + 1, 1 << 62, -2147483649 }
    for i, v in ipairs(values) do
        local key = P .. "setInt" .. i
        local ok, result = pcall(function() return PersistentDB:SetInt(key, v) end)
        if not ok then
            say("SetInt", show(v), "raised:", result)
        else
            local got = PersistentDB:GetInt(key)
            say("SetInt", show(v), "returned", show(result), "GetInt =", show(got),
                exactInt(v, got) and "EXACT" or "CHANGED")
        end
    end
end)

step("integer as a string", function()
    local v = "9007199254740993"
    PersistentDB:Set(P .. "intString", { coins = v })
    local got = PersistentDB:Get(P .. "intString").coins
    say("string", v, "->", show(got), "tointeger =", show(math.tointeger(tonumber(got))))
end)

-- 4. Exact size limit, in bytes. Phase 1 found 127 KB fits and 128 KB does not.
step("size: top-level string", function()
    say("largest top-level string =", largest(127 * 1024, 129 * 1024, function(n) return string.rep("z", n) end), "bytes")
end)

step("size: string in a table", function()
    say("largest { s = string } =", largest(126 * 1024, 129 * 1024, function(n) return { s = string.rep("z", n) } end), "bytes")
end)

step("size: string with a long key", function()
    local key = string.rep("k", 1000)
    say("largest { [1000-char key] = string } =",
        largest(125 * 1024, 129 * 1024, function(n) return { [key] = string.rep("z", n) } end), "bytes")
end)

step("size: cost of one int entry", function()
    -- n entries { ["eNNNNN"] = 1 }; keys of 6 chars.
    -- hi stays small: each build costs time, and one tick has 1000 ms.
    local n = largest(1, 8000, function(count)
        local t = {}
        for i = 1, count do t[string.format("e%05d", i)] = 1 end
        return t
    end)
    say("largest table of { ['eNNNNN'] = 1 } =", n, "entries, about", (128 * 1024) // n, "bytes each")
end)

-- 5. Restart markers. Load 2 checks them.
step("write restart markers", function()
    PersistentDB:SetInt(P .. "markerInt", 7)
    PersistentDB:Set(P .. "markerTable", { a = { b = "c" }, n = 3 })
    PersistentDB:Set(MARKER_KEY, "written")
    say("Markers written.")
end)

local function checkRestart()
    local int = PersistentDB:GetInt(P .. "markerInt")
    local t = PersistentDB:Get(P .. "markerTable")
    local ok = int == 7 and type(t) == "table" and t.n == 3 and t.a and t.a.b == "c"
    -- The probe cannot tell a restart from prl. The person who runs it must restart the game client.
    say("After restart: markerInt =", show(int), "markerTable =", type(t), ok and "SURVIVED" or "LOST OR CHANGED")
    local keys = {}
    PersistentDB:IterateEntries(function(k)
        keys[#keys + 1] = k
        return false
    end)
    for _, k in ipairs(keys) do
        if k ~= CRASHED_KEY then PersistentDB:Delete(k) end
    end
    local crashed = PersistentDB:Get(CRASHED_KEY)
    say("Crashed steps (all runs):", type(crashed) == "string" and crashed:gsub("\n", ", ") or "none")
    PersistentDB:Delete(CRASHED_KEY)
    say("Deleted", #keys, "keys. Probe done. The next load starts again.")
end

-- Runs one step in each Logic tick.
local crashed = {}
local nextStep = 1
local function runNext()
    while nextStep <= #steps and crashed[steps[nextStep].name] do
        say("SKIP", steps[nextStep].name, "(crashed before)")
        nextStep = nextStep + 1
    end
    if nextStep > #steps then
        PersistentDB:Delete(RUNNING_KEY)
        Event.Logic.Unsubscribe("pdbLimits")
        say("Load 1 done. Close the game client fully, start it again, then pon persistentdb-limits-probe.")
        return
    end
    local s = steps[nextStep]
    nextStep = nextStep + 1
    say("Start", s.name)
    PersistentDB:Set(RUNNING_KEY, s.name)
    local ok, err = pcall(s.fn)
    if not ok then say("ERR ", s.name, "raised:", err) end
end

local ok, err = pcall(function()
    local list = PersistentDB:Get(CRASHED_KEY)
    list = type(list) == "string" and list or ""
    local last = PersistentDB:Get(RUNNING_KEY)
    if type(last) == "string" then
        say("CRASHED last time in step:", last)
        list = list .. last .. "\n"
        PersistentDB:Set(CRASHED_KEY, list)
        PersistentDB:Delete(RUNNING_KEY)
    end
    for name in list:gmatch("[^\n]+") do crashed[name] = true end

    if PersistentDB:Get(MARKER_KEY) == "written" then
        checkRestart()
        return
    end
    say("Load 1: one step in each tick,", #steps, "steps.")
    Event.Logic.Subscribe("pdbLimits", function()
        local stepOk, stepErr = pcall(runNext)
        if not stepOk then say("Tick error:", stepErr) end
    end)
end)
if not ok then say("Probe stopped with an error:", err) end
