-- Throwaway probe: what does PersistentDB keep, for issue #23?
-- Version 1 crashed the client on pon. This version finds the step that crashes:
-- before each step it logs the name and saves it in probe:running.
-- After a crash, the next pon logs that step as CRASHED and skips it from then on.
-- Phase 1 (pon): writes each case and reads it back at once.
-- Phase 2 (prl, then pon): reads each case again, then deletes the probe keys.
-- The data is isolated to this probe plugin. The planner data is safe.

local PREFIX = "probe:"
local PHASE_KEY = PREFIX .. "phase"
local RUNNING_KEY = PREFIX .. "running"
local CRASHED_KEY = PREFIX .. "crashed" -- string of step names, one per line

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log("[pdb-probe] " .. table.concat(parts, " "))
end

say("Loaded. First line before any API call.")

local function numType(v)
    if math and math.type then return math.type(v) end
    return "number"
end

local function show(v)
    if type(v) == "number" then return tostring(v) .. "(" .. numType(v) .. ")" end
    if type(v) == "string" then
        if #v > 40 then return '"' .. v:sub(1, 20) .. '..." (' .. #v .. " bytes)" end
        return '"' .. v .. '"'
    end
    return tostring(v)
end

local function diff(expected, actual, path, out)
    if type(expected) ~= type(actual) then
        out[#out + 1] = path .. ": expected " .. show(expected) .. ", got " .. show(actual)
        return out
    end
    if type(expected) == "table" then
        for k, v in pairs(expected) do
            diff(v, actual[k], path .. "[" .. show(k) .. "]", out)
        end
        for k, v in pairs(actual) do
            if expected[k] == nil then
                out[#out + 1] = path .. "[" .. show(k) .. "]: not expected, got " .. show(v)
            end
        end
    elseif type(expected) == "number" then
        if expected ~= actual or numType(expected) ~= numType(actual) then
            out[#out + 1] = path .. ": expected " .. show(expected) .. ", got " .. show(actual)
        end
    elseif expected ~= actual then
        out[#out + 1] = path .. ": expected " .. show(expected) .. ", got " .. show(actual)
    end
    return out
end

local function check(name, expected, actual)
    local d = diff(expected, actual, name, {})
    if #d == 0 then
        say("OK  ", name)
    else
        say("DIFF", name, "(" .. #d .. " differences)")
        for i = 1, math.min(#d, 8) do say("     ", d[i]) end
    end
end

local function bigTable(n)
    local t = {}
    for i = 1, n do
        t["item " .. i] = { entered = i, remaining = i * 2, baseline = 0 }
    end
    return t
end

-- Value cases, from safe to risky. { name, written, expected (nil = same as written) }
-- Phase 2 builds them again, so they must give the same values each time.
local function cases()
    return {
        { "bool", true },
        { "int", 42 },
        { "string", "Kit Manners" },
        { "float", 4.5 },
        { "wholeFloat", 5.0 },
        { "negInt", -7 },
        { "bigInt", 1 << 40 }, -- coin counts can pass 2^31
        { "emptyString", "" },
        { "flatTable", { a = 1, b = "two" } },
        { "falseField", { on = false, off = true } },
        { "nested", { a = { b = { c = { d = { e = "deep" } } } } } },
        { "numbersInTable", { i = 3, f = 3.25, w = 3.0, big = 1 << 40 } },
        { "spaceKeys", { ["Kit Manners"] = 1, ["Iron Kit"] = 2 } },
        { "array", { 10, 20, 30 } },
        { "arrayOfTables", { { item = "Logs", n = 1 }, { item = "Oak logs", n = 2 } } },
        {
            "character",
            {
                version = 1,
                bank = { ["Logs"] = 120, ["Oak logs"] = 0 },
                assumed = { entries = { { item = "Logs", entered = 5, remaining = 3, baseline = 2 } } },
                detected = { ["Logs"] = 7 },
                reserves = { ["Coins"] = 100000 },
                unlocks = { ["Some quest"] = true },
                accountMode = "normal",
                overrides = { x = 1 },
                made = { counts = { ["Plank"] = 4 } },
            },
        },
        { "emptyTable", {} },
        { "nestedEmptyTable", { overrides = {} } },
        { "sparseArray", { [1] = "a", [3] = "c", [10] = "j" } },
        { "intKeys", { [1511] = 5, [1521] = 6 } },
        { "negIntKey", { [-1] = 0 } },
        { "mixed", { "first", "second", name = "mix", [5] = "five" } },
        { "unicode", "Æsir ß ✓" },
        { "floatKey", { [1.5] = "x" } },
        { "boolKey", { [true] = "yes" } },
        { "withFunction", { keep = 1, fn = print }, { keep = 1 } },
        { "big1000", bigTable(1000) },
        { "longString100k", string.rep("x", 100000) },
        { "big20000", bigTable(20000) },
        { "longString2m", string.rep("y", 2000000) },
    }
end

local KEY_CASES = {
    { "keySpace", "char:Kit Manners" },
    { "keyUnicode", "char:Æsir" },
    { "keyLong", "char:" .. string.rep("k", 300) },
}

local function readCrashed()
    local set = {}
    local s = PersistentDB:Get(CRASHED_KEY)
    if type(s) == "string" then
        for name in s:gmatch("[^\n]+") do set[name] = true end
    end
    return set, s or ""
end

-- Runs fn as a named step. Saves the name first, so a crash in fn is found on the next load.
local crashed, crashedText
local function step(name, fn)
    if crashed[name] then
        say("SKIP", name, "(crashed before)")
        return
    end
    say("Start", name)
    PersistentDB:Set(RUNNING_KEY, name)
    local ok, err = pcall(fn)
    if not ok then say("ERR ", name, "raised:", err) end
end

local function clock()
    if os and os.clock then return os.clock() end
    return nil
end

local function phase1()
    say("Phase 1: write and read back in the same session")
    for _, c in ipairs(cases()) do
        local name, value, expected = c[1], c[2], c[3]
        step(name, function()
            local t0 = clock()
            local result = PersistentDB:Set(PREFIX .. name, value)
            local t1 = clock()
            local ms = (t0 and t1) and string.format("%.1fms", (t1 - t0) * 1000) or "?"
            say("Set ", name, "returned", show(result), ms)
            check(name, expected or value, PersistentDB:Get(PREFIX .. name))
        end)
    end

    for _, c in ipairs(KEY_CASES) do
        step(c[1], function()
            local result = PersistentDB:Set(c[2], 1)
            say("Set ", c[1], "returned", show(result), "Get =", show(PersistentDB:Get(c[2])))
        end)
    end

    step("copyOnSet", function()
        local live = { n = 1 }
        PersistentDB:Set(PREFIX .. "copyOnSet", live)
        live.n = 2
        say("Change after Set: stored n =", show(PersistentDB:Get(PREFIX .. "copyOnSet").n), "(1 = copied)")
        local a = PersistentDB:Get(PREFIX .. "copyOnSet")
        a.n = 99
        local b = PersistentDB:Get(PREFIX .. "copyOnSet")
        say("Change after Get: second Get n =", show(b.n), "(1 = new table)", "same table:", tostring(a == b))
    end)

    step("typeChange", function()
        PersistentDB:Set(PREFIX .. "typeChange", 5)
        PersistentDB:Set(PREFIX .. "typeChange", { now = "table" })
        say("Int then table: Get =", show(PersistentDB:Get(PREFIX .. "typeChange")))
    end)

    step("checkExistsTyped", function()
        say("type(PersistentDBType) =", type(PersistentDBType))
        say("CheckExistsTyped STRUCTURED_DATA =",
            tostring(PersistentDB:CheckExistsTyped(PREFIX .. "typeChange", PersistentDBType.STRUCTURED_DATA)))
    end)

    step("iterate", function()
        say("IterateEntries count =", PersistentDB:IterateEntries(function() return false end))
    end)

    -- Each alias in its own step: indexing a missing member can fail in the client.
    for _, alias in ipairs({ "GetStructuredData", "SetStructuredData", "GetInt", "SetInt" }) do
        step("alias " .. alias, function()
            say("alias", alias, "=", type(PersistentDB[alias]))
        end)
    end

    PersistentDB:Set(PHASE_KEY, 2)
    PersistentDB:Delete(RUNNING_KEY)
    say("Phase 1 done. Now run prl, then pon again for phase 2.")
end

local function phase2()
    say("Phase 2: read after reload")
    for _, c in ipairs(cases()) do
        local name, value, expected = c[1], c[2], c[3]
        step("read " .. name, function()
            check(name, expected or value, PersistentDB:Get(PREFIX .. name))
        end)
    end
    for _, c in ipairs(KEY_CASES) do
        step("read " .. c[1], function()
            say("Get", c[1], "=", show(PersistentDB:Get(c[2])))
        end)
    end

    -- Phase 1 found: a table of 1000 entries fails, a string of 100 KB passes.
    -- These steps find the limit. Each test key is deleted after its Set.
    local function fits(value)
        local ok = PersistentDB:Set(PREFIX .. "limitTest", value)
        PersistentDB:Delete(PREFIX .. "limitTest")
        return ok == true
    end
    -- Largest n in [lo, hi] where fits(build(n)) is true. lo must fit.
    local function largest(lo, hi, build)
        while lo < hi do
            local mid = (lo + hi + 1) // 2
            if fits(build(mid)) then lo = mid else hi = mid - 1 end
        end
        return lo
    end
    local function limit(name, hi, build)
        step("limit " .. name, function()
            if not fits(build(1)) then
                say("LIMIT", name, ": even n = 1 fails")
                return
            end
            say("LIMIT", name, ": largest n that fits =", largest(1, hi, build))
        end)
    end

    limit("flat string keys {['item i'] = i}", 1000, function(n)
        local t = {}
        for i = 1, n do t["item " .. i] = i end
        return t
    end)
    limit("array {1..n}", 1000, function(n)
        local t = {}
        for i = 1, n do t[i] = i end
        return t
    end)
    limit("nested {['item i'] = {a = i}}", 1000, function(n)
        local t = {}
        for i = 1, n do t["item " .. i] = { a = i } end
        return t
    end)
    limit("nested 3 fields {['item i'] = {a, b, c}}", 1000, function(n)
        local t = {}
        for i = 1, n do t["item " .. i] = { a = i, b = i, c = i } end
        return t
    end)
    limit("long keys (40 chars) flat", 1000, function(n)
        local t = {}
        for i = 1, n do t[string.format("%040d", i)] = i end
        return t
    end)
    limit("bytes: one string field, n KB", 2000, function(n)
        return { s = string.rep("z", n * 1024) }
    end)
    limit("bytes: top-level string, n KB", 2000, function(n)
        return string.rep("z", n * 1024)
    end)
    limit("depth: nested n levels", 200, function(n)
        local t = { v = 1 }
        for _ = 2, n do t = { t = t } end
        return t
    end)

    -- Where do integers in a table turn into floats?
    step("int sizes in a table", function()
        local values = { 2147483647, 2147483648, 4294967295, 4294967296, 9007199254740993 }
        PersistentDB:Set(PREFIX .. "intSizes", values)
        local back = PersistentDB:Get(PREFIX .. "intSizes")
        for i, v in ipairs(values) do say("int", show(v), "->", show(back[i])) end
    end)

    step("SetInt round trip", function()
        say("SetInt returned", show(PersistentDB:SetInt(PREFIX .. "typedInt", 42)))
        say("GetInt =", show(PersistentDB:GetInt(PREFIX .. "typedInt")),
            "Get =", show(PersistentDB:Get(PREFIX .. "typedInt")))
    end)

    step("delete", function()
        local keys = {}
        PersistentDB:IterateEntries(function(k)
            keys[#keys + 1] = k
            return false
        end)
        -- Keep the crash list, so the report below stays true.
        for _, k in ipairs(keys) do
            if k ~= CRASHED_KEY then PersistentDB:Delete(k) end
        end
        say("Deleted", #keys - 1, "keys.")
    end)
    say("Crashed steps (all runs):", crashedText == "" and "none" or crashedText:gsub("\n", ", "))
    PersistentDB:Delete(CRASHED_KEY)
    say("Phase 2 done. The next load runs phase 1 again.")
end

local ok, err = pcall(function()
    say("type(PersistentDB) =", type(PersistentDB))
    crashed, crashedText = readCrashed()
    local last = PersistentDB:Get(RUNNING_KEY)
    if type(last) == "string" then
        say("CRASHED last time in step:", last)
        crashedText = crashedText .. last .. "\n"
        crashed[last] = true
        PersistentDB:Set(CRASHED_KEY, crashedText)
        PersistentDB:Delete(RUNNING_KEY)
    end
    if PersistentDB:Get(PHASE_KEY) == 2 then phase2() else phase1() end
end)
if not ok then say("Probe stopped with an error:", err) end
