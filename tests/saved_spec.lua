local Assumed = require("plan/assumed")
local Made = require("plan/made")
local Plan = require("plan/calculate")
local Saved = require("plan/saved")

-- Acts as PersistentDB (docs/client-behaviour.md): Set copies the value, each Get gives a new copy,
-- and each number has float32 precision. When full is true, Set saves nothing and returns false.
local function fakeStore()
    local values = {}
    local function copy(value)
        if type(value) == "number" then
            return string.unpack("f", string.pack("f", value))
        end
        if type(value) ~= "table" then
            return value
        end
        local result = {}
        for k, v in pairs(value) do
            result[k] = copy(v)
        end
        return result
    end
    local store = { values = values, sets = 0, full = false }
    function store.Get(_, key)
        return copy(values[key])
    end
    function store.Set(_, key, value)
        store.sets = store.sets + 1
        if store.full then
            return false
        end
        values[key] = copy(value)
        return true
    end
    return store
end

-- Gives a store in which Alice already has saved data, so that a change writes only its part.
local function aliceStore()
    local store = fakeStore()
    store.values["global:characters"] = { v = 1, characters = { "Alice" } }
    return store
end

-- Gives saved data that is ready for changes for Alice.
local function newSaved(store)
    local saved = Saved.new(store)
    Saved.loadGlobal(saved)
    Saved.loadCharacter(saved, "Alice")
    return saved
end

describe("Saved data", function()
    describe("Bank snapshot", function()
        it("loads the Bank snapshot that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { SNAPE_GRASS = 5, COINS = 2147483647 })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, { SNAPE_GRASS = 5, COINS = 2147483647 })
        end)

        it("writes one line for each item after the version line", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { SNAPE_GRASS = 5, COINS = 1200000 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=1200000\nSNAPE_GRASS=5\n")
        end)

        it("reads the count after the last = of a line", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=1\nA=B=7\n")

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, { ["A=B"] = 7 })
        end)

        it("gives no Bank snapshot to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.bank, nil)
        end)
    end)

    describe("versions", function()
        it("gives no problems for a key at a known version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=1\nCOINS=5\n")

            local _, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(problems, {})
        end)

        it("does not read a key with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=2\nCOINS=5\n")

            local parts, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, nil)
            expectEqual(problems, { { key = "char:Alice:bank", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("does not read a key with no version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "COINS=5\n")

            local parts, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, nil)
            expectEqual(problems, { { key = "char:Alice:bank", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("does not write a key with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=2\nCOINS=5\n")
            local saved = newSaved(store)
            Saved.loadCharacter(saved, "Alice")
            Saved.change(saved, "Alice", "bank", { COINS = 9 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=2\nCOINS=5\n")
        end)
    end)

    describe("bad data", function()
        local function slot(soldCount)
            return { [0] = { item = "COINS", type = Made.BUY, stage = Made.ADDED, soldCount = soldCount } }
        end

        local CASES = {
            { "a bank that is not a string", "char:Alice:bank", { v = 1 } },
            { "a bank line with no line end", "char:Alice:bank", "v=1\nCOINS=5" },
            { "a bank line with no count", "char:Alice:bank", "v=1\nCOINS\n" },
            { "a bank count that is not a number", "char:Alice:bank", "v=1\nCOINS=five\n" },
            { "Assumed stock with no entries", "char:Alice:assumed", { v = 1 } },
            {
                "an Assumed stock count that is not a number",
                "char:Alice:assumed",
                { v = 1, entries = { { item = "COINS", entered = "1", remaining = "x", baseline = "0" } } },
            },
            { "Reserves with no reserves", "char:Alice:reserves", { v = 1 } },
            { "a Reserve count that is not a number", "char:Alice:reserves", { v = 1, reserves = { COINS = "abc" } } },
            { "Unlocks with no unlocks", "char:Alice:unlocks", { v = 1 } },
            { "Made counts with no slots", "char:Alice:made", { v = 1, counts = {}, starts = {} } },
            { "Made counts with no start values", "char:Alice:made", { v = 1, counts = {}, slots = {} } },
            {
                "a start value that is a number",
                "char:Alice:made",
                { v = 1, counts = {}, starts = { [7] = 5 }, slots = {} },
            },
            {
                "a start value with an id that is not a number",
                "char:Alice:made",
                { v = 1, counts = {}, starts = { SHARK = "5" }, slots = {} },
            },
            {
                "a GE slot with no soldCount",
                "char:Alice:made",
                { v = 1, counts = {}, starts = {}, slots = slot(nil) },
            },
            {
                "a Made count that is a number",
                "char:Alice:made",
                { v = 1, counts = { COINS = 5 }, starts = {}, slots = {} },
            },
            {
                "a GE amount that is a number",
                "char:Alice:made",
                { v = 1, counts = {}, starts = {}, slots = {}, ge = { COINS = 5 } },
            },
            { "a Plan with no Targets", "global:plan", { v = 1 } },
            {
                "a Target count that is not an integer",
                "global:plan",
                { v = 1, targets = { { id = 1, item = "COINS", count = "1.5", mode = "HAVE" } } },
            },
            {
                "a Target with no id",
                "global:plan",
                { v = 1, targets = { { item = "COINS", count = "1", mode = "HAVE" } } },
            },
            {
                "a Target id that is not a whole number",
                "global:plan",
                { v = 1, targets = { { id = 1.5, item = "COINS", count = "1", mode = "HAVE" } } },
            },
            {
                "two Targets with one id",
                "global:plan",
                {
                    v = 1,
                    targets = {
                        { id = 1, item = "COINS", count = "1", mode = "HAVE" },
                        { id = 1, item = "BREAD", count = "1", mode = "HAVE" },
                    },
                },
            },
            {
                "a Target with an unknown mode",
                "global:plan",
                { v = 1, targets = { { id = 1, item = "COINS", count = "1", mode = "SELL" } } },
            },
            { "a global setting of the wrong type", "global:settings", { v = 1, madeCountScope = 5 } },
            { "an unknown Made count scope", "global:settings", { v = 1, madeCountScope = "CHAR" } },
            { "characters with no list", "global:characters", { v = 1 } },
            { "a character name that is not a string", "global:characters", { v = 1, characters = { 5 } } },
        }

        local function load(store, badKey)
            local saved = Saved.new(store)
            local globals, problems = Saved.loadGlobal(saved)
            if badKey:find("^char:") then
                return Saved.loadCharacter(saved, "Alice")
            end
            return globals, problems
        end

        for _, case in ipairs(CASES) do
            local name, badKey, value = case[1], case[2], case[3]

            it("does not read " .. name .. ", and gives the start value", function()
                local store = fakeStore()
                store:Set(badKey, value)
                local start = load(fakeStore(), badKey)

                local parts, problems = load(store, badKey)

                local part = badKey:match("[^:]+$")
                expectEqual(parts[part], start[part])
                expectEqual(problems, { { key = badKey, kind = Saved.UNKNOWN_VERSION } })
            end)
        end

        it("does not write a key with bad data", function()
            local store = fakeStore()
            store:Set("char:Alice:reserves", { v = 1 })
            local saved = newSaved(store)
            Saved.loadCharacter(saved, "Alice")
            Saved.change(saved, "Alice", "reserves", { COINS = 1 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:reserves"], { v = 1 })
        end)

        it("loads a negative count that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { COINS = -1 })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, { COINS = -1 })
        end)
    end)

    describe("writes", function()
        it("writes a part that changed two times in one tick one time, with the last value", function()
            local store = aliceStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.change(saved, "Alice", "bank", { COINS = 2 })
            Saved.write(saved)

            expectEqual(store.sets, 1)
            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=2\n")
        end)

        it("gives no problems when each part is saved", function()
            local saved = newSaved(fakeStore())
            Saved.change(saved, "Alice", "bank", { COINS = 1 })

            expectEqual(Saved.write(saved), {})
        end)

        it("gives a problem when the store does not save a part", function()
            local store = aliceStore()
            store.full = true
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })

            expectEqual(Saved.write(saved), { { key = "char:Alice:bank", kind = Saved.NOT_SAVED } })
        end)

        it("does not try again in the next tick after the store does not save a part", function()
            local store = aliceStore()
            store.full = true
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.write(saved)
            Saved.write(saved)

            expectEqual(store.sets, 1)
        end)

        it("tries again after the next change to the part", function()
            local store = aliceStore()
            store.full = true
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.write(saved)
            store.full = false
            Saved.change(saved, "Alice", "bank", { COINS = 2 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=2\n")
        end)
    end)

    describe("Assumed stock", function()
        local function assumedState()
            local states = {}
            Assumed.add(states, "Alice", "COINS", 20000001, { COINS = 16777217 })
            return states.Alice
        end

        it("loads the Assumed stock that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "assumed", assumedState())
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.assumed, assumedState())
        end)

        it("writes each count as a decimal string", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "assumed", assumedState())
            Saved.write(saved)

            expectEqual(store.values["char:Alice:assumed"], {
                v = 1,
                entries = {
                    { item = "COINS", entered = "20000001", remaining = "20000001", baseline = "16777217" },
                },
            })
        end)

        it("gives no Assumed stock to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.assumed, Assumed.new())
        end)

        it("does not read Assumed stock with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:assumed", { v = 2, entries = {} })

            local _, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(problems, { { key = "char:Alice:assumed", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("gives no Assumed stock when the version is newer", function()
            local store = fakeStore()
            store:Set("char:Alice:assumed", { v = 2, entries = { { item = "COINS" } } })

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.assumed, Assumed.new())
        end)
    end)

    describe("Reserves", function()
        it("loads the Reserves that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "reserves", { COINS = 20000001, SNAPE_GRASS = 5 })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.reserves, { COINS = 20000001, SNAPE_GRASS = 5 })
        end)

        it("writes each count as a decimal string", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "reserves", { SNAPE_GRASS = 5 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:reserves"], { v = 1, reserves = { SNAPE_GRASS = "5" } })
        end)

        it("gives no Reserves to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.reserves, {})
        end)
    end)

    describe("Unlocks", function()
        it("loads the Unlocks that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "unlocks", { ZAROS_GODSWORD = true })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.unlocks, { ZAROS_GODSWORD = true })
        end)

        it("writes the Unlocks as a set", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "unlocks", { ZAROS_GODSWORD = true })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:unlocks"], { v = 1, unlocks = { ZAROS_GODSWORD = true } })
        end)

        it("gives no Unlocks to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.unlocks, {})
        end)
    end)

    describe("Made counts", function()
        local function madeState()
            local state = Made.new()
            state.counts = { COINS = 20000001 }
            state.starts = { [7] = 16777217, [8] = -3 }
            state.slots = { [0] = { item = "COINS", type = Made.BUY, stage = Made.ADDED, soldCount = 16777217 } }
            state.ge = { COINS = 16777219 }
            return state
        end

        it("loads the Made counts, GE slots and GE amounts that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "made", madeState())
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.made, madeState())
        end)

        it("writes each count as a decimal string, with no last counts", function()
            local store = fakeStore()
            local saved = newSaved(store)
            local state = madeState()
            state.last = { COINS = 5 }
            Saved.change(saved, "Alice", "made", state)
            Saved.write(saved)

            expectEqual(store.values["char:Alice:made"], {
                v = 1,
                counts = { COINS = "20000001" },
                starts = { [7] = "16777217", [8] = "-3" },
                slots = { [0] = { item = "COINS", type = Made.BUY, stage = Made.ADDED, soldCount = "16777217" } },
                ge = { COINS = "16777219" },
            })
        end)

        it("gives the same Made count to each Make Target after a load, also for two Targets of one item", function()
            local first = { id = 7, item = "SHARK", count = 100, mode = Plan.MAKE }
            local second = { id = 8, item = "SHARK", count = 100, mode = Plan.MAKE }
            local states = {}
            Made.startTarget(states, "Alice", first, { SHARK = 5 }, {})
            Made.observe(states, "Alice", { detected = { SHARK = 25 } })
            Made.startTarget(states, "Alice", second, { SHARK = 25 }, {})
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "made", states.Alice)
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            local counts = Made.counts({ Alice = parts.made }, "Alice", Made.CHARACTER, { first, second })
            expectEqual(counts, { [7] = 20, [8] = 0 })
        end)

        it("gives GE amounts of 0 when the saved data has no GE amounts", function()
            local store = fakeStore()
            store.values["char:Alice:made"] = { v = 1, counts = { COINS = "20" }, starts = {}, slots = {} }

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.made.counts, { COINS = 20 })
            expectEqual(parts.made.ge, {})
        end)

        it("gives Made counts of 0 to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.made, Made.new())
        end)
    end)

    describe("Account mode", function()
        it("gives no settings to a character, because the game gives Account mode (ADR 0014)", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.settings, nil)
        end)

        it("does not read Account mode from old saved data", function()
            local store = fakeStore()
            store:Set("char:Alice:settings", { v = 1, ironman = true })

            local parts, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.settings, nil)
            expectEqual(problems, {})
        end)
    end)

    describe("Plan", function()
        local function plan()
            return {
                targets = {
                    { id = 7, item = "BREAD", count = 20000001, mode = Plan.MAKE },
                    { id = 16777216, item = "CAKE", count = 3, mode = Plan.HAVE },
                },
            }
        end

        it("loads the Plan that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.changeGlobal(saved, "plan", plan())
            Saved.write(saved)

            local globals = Saved.loadGlobal(Saved.new(store))

            expectEqual(globals.plan, plan())
        end)

        it("gives each Target id as an integer, because the store gives back floats", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.changeGlobal(saved, "plan", plan())
            Saved.write(saved)

            local globals = Saved.loadGlobal(Saved.new(store))

            expectEqual(math.type(globals.plan.targets[1].id), "integer")
        end)

        it("writes each Target count as a decimal string", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.changeGlobal(saved, "plan", plan())
            Saved.write(saved)

            expectEqual(store.values["global:plan"], {
                v = 1,
                targets = {
                    { id = 7, item = "BREAD", count = "20000001", mode = Plan.MAKE },
                    { id = 16777216, item = "CAKE", count = "3", mode = Plan.HAVE },
                },
            })
        end)

        it("gives a Plan with no Targets when the plugin has saved no Plan", function()
            local globals = Saved.loadGlobal(Saved.new(fakeStore()))

            expectEqual(globals.plan, { targets = {} })
        end)

        it("does not read or write a Plan with a newer version", function()
            local store = fakeStore()
            store:Set("global:plan", { v = 2, targets = {} })
            local saved = Saved.new(store)
            local globals, problems = Saved.loadGlobal(saved)
            Saved.changeGlobal(saved, "plan", plan())
            Saved.write(saved)

            expectEqual(globals.plan, { targets = {} })
            expectEqual(problems, { { key = "global:plan", kind = Saved.UNKNOWN_VERSION } })
            expectEqual(store.values["global:plan"], { v = 2, targets = {} })
        end)

        it("gives an error for a change before the global data is loaded", function()
            local ok, message = pcall(Saved.changeGlobal, Saved.new(fakeStore()), "plan", plan())

            expectEqual(ok, false)
            expectEqual(message:find("Load the global data before a change.", 1, true) ~= nil, true)
        end)
    end)

    describe("global settings", function()
        it("starts with the Made counts of this character", function()
            local globals = Saved.loadGlobal(Saved.new(fakeStore()))

            expectEqual(globals.settings, { madeCountScope = Made.CHARACTER })
        end)

        it("loads the settings that it wrote", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.changeGlobal(saved, "settings", { madeCountScope = Made.ALL })
            Saved.write(saved)

            local globals = Saved.loadGlobal(Saved.new(store))

            expectEqual(globals.settings, { madeCountScope = Made.ALL })
        end)

        it("writes the settings with a version", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.changeGlobal(saved, "settings", { madeCountScope = Made.ALL })
            Saved.write(saved)

            expectEqual(store.values["global:settings"], { v = 1, madeCountScope = Made.ALL })
        end)

        it("gives the start value of a setting that the saved data does not have", function()
            local store = fakeStore()
            store:Set("global:settings", { v = 1 })

            local globals = Saved.loadGlobal(Saved.new(store))

            expectEqual(globals.settings, { madeCountScope = Made.CHARACTER })
        end)

        it("does not read the old Target mode setting, because each Target has its mode (ADR 0012)", function()
            local store = fakeStore()
            store:Set("global:settings", { v = 1, targetMode = Plan.MAKE, madeCountScope = Made.ALL })

            local globals, problems = Saved.loadGlobal(Saved.new(store))

            expectEqual(globals.settings, { madeCountScope = Made.ALL })
            expectEqual(problems, {})
        end)
    end)

    describe("characters", function()
        it("gives no characters when the plugin has saved no data", function()
            local globals, problems = Saved.loadGlobal(Saved.new(fakeStore()))

            expectEqual(globals.characters, {})
            expectEqual(problems, {})
        end)

        it("adds a character the first time that it saves data for it", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "reserves", {})
            Saved.write(saved)

            expectEqual(store.values["global:characters"], { v = 1, characters = { "Alice" } })
        end)

        it("adds each character one time, after the characters that it saved before", function()
            local store = fakeStore()
            store:Set("global:characters", { v = 1, characters = { "Bob" } })
            local saved = newSaved(store)
            Saved.loadCharacter(saved, "Bob")
            Saved.change(saved, "Alice", "reserves", {})
            Saved.change(saved, "Bob", "reserves", {})
            Saved.change(saved, "Alice", "unlocks", {})
            Saved.write(saved)

            local globals = Saved.loadGlobal(Saved.new(store))

            expectEqual(globals.characters, { "Bob", "Alice" })
        end)

        it("tries again to save the characters after the next change for a character", function()
            local store = fakeStore()
            local saved = newSaved(store)
            Saved.change(saved, "Alice", "reserves", {})
            store.full = true
            Saved.write(saved)
            store.full = false
            Saved.change(saved, "Alice", "reserves", {})
            Saved.write(saved)

            expectEqual(store.values["global:characters"], { v = 1, characters = { "Alice" } })
        end)

        it("does not add a character when the version is newer, but saves its data", function()
            local store = fakeStore()
            store:Set("global:characters", { v = 2, characters = { "Bob" } })
            local saved = Saved.new(store)
            local _, problems = Saved.loadGlobal(saved)
            Saved.loadCharacter(saved, "Alice")
            Saved.change(saved, "Alice", "reserves", { COINS = 1 })
            Saved.write(saved)

            expectEqual(problems, { { key = "global:characters", kind = Saved.UNKNOWN_VERSION } })
            expectEqual(store.values["global:characters"], { v = 2, characters = { "Bob" } })
            expectEqual(store.values["char:Alice:reserves"], { v = 1, reserves = { COINS = "1" } })
        end)

        it("gives an error for a change before the global data is loaded", function()
            local ok, message = pcall(Saved.change, Saved.new(fakeStore()), "Alice", "reserves", {})

            expectEqual(ok, false)
            expectEqual(message:find("Load the global data before a change.", 1, true) ~= nil, true)
        end)

        it("gives an error for a change before the character is loaded", function()
            local saved = Saved.new(fakeStore())
            Saved.loadGlobal(saved)

            local ok, message = pcall(Saved.change, saved, "Alice", "reserves", {})

            expectEqual(ok, false)
            expectEqual(message:find("Load the character Alice before a change.", 1, true) ~= nil, true)
        end)

        it("does not write a key with a newer version when the change comes before the load", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=2\nCOINS=5\n")
            local saved = Saved.new(store)
            Saved.loadGlobal(saved)

            pcall(Saved.change, saved, "Alice", "bank", { COINS = 9 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=2\nCOINS=5\n")
        end)
    end)
end)
