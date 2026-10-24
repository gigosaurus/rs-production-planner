-- Throwaway probe: how long does it take to read the recipe data of all Objs at runtime?
-- The plugin must scan all Objs to find dummy recipes (RECIPE_NON_DUMMY_OBJ points from the dummy to the item).
-- It runs two passes, one part in each Logic tick (the client stops a call after 1000 ms):
-- 1. light: HasParam and GetParamValue for the four params that build the item -> recipes index.
-- 2. full: GetParamValue for every param of each Obj, as the object export does.
-- For each pass it logs the wall time (sum of Draw timeDeltaSecs), the server ticks, the longest frame,
-- and the longest part in CPU time if os.clock exists.

local LAST_ID = 64356
local IDS_PER_TICK = { light = 250, full = 50 }
local BASELINE_SECONDS = 5

local clock = rawget(_G, "os") and rawget(os, "clock")
local serverTick = 0
local drawSeconds, maxFrame = 0, 0
local pass = nil
local baseline = { seconds = 0, maxFrame = 0 }

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do
        parts[i] = tostring(v)
    end
    log("[Scan timer] " .. table.concat(parts, " "))
end

local function param(name)
    local ok, p = pcall(function()
        return config.Param[name]
    end)
    if not ok or p == nil then
        error("config.Param." .. name .. " is unavailable")
    end
    return p
end

local P = {
    requirement = param("RECIPE_REQUIREMENT_TYPE_1"),
    ingredient = param("RECIPE_INGREDIENT_TYPE_1"),
    multiple = param("RECIPE_INGREDIENT_1_MULTIPLE"),
    nonDummy = param("RECIPE_NON_DUMMY_OBJ"),
}

-- light: gives the item that the Obj is a recipe for, or nil
local function readLight(obj)
    if not (obj:HasParam(P.requirement) or obj:HasParam(P.ingredient) or obj:HasParam(P.multiple)) then
        return nil
    end
    if obj:HasParam(P.nonDummy) then
        return obj:GetParamValue(P.nonDummy).id, true
    end
    return obj.id, false
end

-- full: reads every param, then answers as light does
local function readFull(obj)
    local params = obj.params
    local values = {}
    for name, p in pairs(params or {}) do
        values[name] = obj:GetParamValue(p)
    end
    if values.RECIPE_REQUIREMENT_TYPE_1 == nil
        and values.RECIPE_INGREDIENT_TYPE_1 == nil
        and values.RECIPE_INGREDIENT_1_MULTIPLE == nil then
        return nil
    end
    local target = values.RECIPE_NON_DUMMY_OBJ
    if target ~= nil then
        return target.id, true
    end
    return obj.id, false
end

local PASSES = { { name = "light", read = readLight }, { name = "full", read = readFull } }

local function startPass(index)
    local spec = PASSES[index]
    pass = {
        index = index,
        name = spec.name,
        read = spec.read,
        nextID = 0,
        valid = 0,
        recipes = 0,
        dummies = 0,
        errors = 0,
        index_ = {},
        targets = 0,
        startDraw = drawSeconds,
        startServer = serverTick,
        maxPart = 0,
    }
    maxFrame = 0
    say("Pass", spec.name, "started,", IDS_PER_TICK[spec.name], "IDs per Logic tick")
end

local function endPass()
    local p = pass
    say(
        "Pass " .. p.name .. " done:",
        "IDs=" .. (LAST_ID + 1),
        "valid=" .. p.valid,
        "recipe Objs=" .. p.recipes,
        "dummy recipes=" .. p.dummies,
        "items with a recipe=" .. p.targets,
        "errors=" .. p.errors
    )
    say(
        "Pass " .. p.name .. " time:",
        string.format("wall=%.2fs", drawSeconds - p.startDraw),
        "server ticks=" .. (serverTick - p.startServer),
        string.format("longest frame=%.3fs (baseline %.3fs)", maxFrame, baseline.maxFrame),
        clock and string.format("longest part=%.1fms", p.maxPart * 1000) or "os.clock unavailable"
    )
    if p.index < #PASSES then
        startPass(p.index + 1)
    else
        pass = nil
        say("All passes done")
    end
end

Event.ServerLogic.Subscribe("recipeScanTimer", function()
    serverTick = serverTick + 1
end)

Event.Draw.Subscribe("recipeScanTimer", function(e)
    drawSeconds = drawSeconds + e.timeDeltaSecs
    if e.timeDeltaSecs > maxFrame then
        maxFrame = e.timeDeltaSecs
    end
    -- Measure normal frames first, so the pass can be compared with them.
    if pass == nil and baseline.done == nil then
        baseline.seconds = baseline.seconds + e.timeDeltaSecs
        if baseline.seconds >= BASELINE_SECONDS then
            baseline.done = true
            baseline.maxFrame = maxFrame
            say(string.format("Baseline: longest frame %.3fs in %.1fs", maxFrame, baseline.seconds))
            startPass(1)
        end
    end
end)

Event.Logic.Subscribe("recipeScanTimer", function()
    if pass == nil then
        return
    end
    local started = clock and clock()
    local last = math.min(pass.nextID + IDS_PER_TICK[pass.name] - 1, LAST_ID)
    for id = pass.nextID, last do
        local ok, err = pcall(function()
            local obj = config.Obj.FromID(id)
            if obj == nil or obj.isValid ~= true then
                return
            end
            pass.valid = pass.valid + 1
            local target, isDummy = pass.read(obj)
            if target == nil then
                return
            end
            pass.recipes = pass.recipes + 1
            if isDummy then
                pass.dummies = pass.dummies + 1
            end
            local list = pass.index_[target]
            if list == nil then
                list = {}
                pass.index_[target] = list
                pass.targets = pass.targets + 1
            end
            list[#list + 1] = id
        end)
        if not ok then
            pass.errors = pass.errors + 1
            if pass.errors <= 10 then
                say("Obj", id, "error:", err)
            end
        end
    end
    pass.nextID = last + 1
    if clock then
        pass.maxPart = math.max(pass.maxPart, clock() - started)
    end
    if pass.nextID > LAST_ID then
        endPass()
    end
end)

function PluginShutdown()
    Event.ServerLogic.Unsubscribe("recipeScanTimer")
    Event.Draw.Unsubscribe("recipeScanTimer")
    Event.Logic.Unsubscribe("recipeScanTimer")
end

say("Measuring a baseline for " .. BASELINE_SECONDS .. "s, then scanning")
